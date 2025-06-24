import Foundation
import Alamofire
import CryoNet
#if os(iOS) || os(watchOS)
import UIKit
#endif

// MARK: - 上传任务状态
/// 上传任务的状态枚举
public enum UploadState: String {
    case idle          /// 等待中（刚创建，未上传）
    case uploading     /// 正在上传
    case paused        /// 已暂停
    case completed     /// 已完成
    case failed        /// 失败
    case cancelled     /// 已取消
}

// MARK: - 上传任务信息
/// 上传任务公开信息（供 UI 使用）
public struct UploadTaskInfo: Identifiable {
    public let id: UUID                  /// 任务唯一标识
    public let fileURL: URL              /// 本地文件路径
    public var progress: Double          /// 当前进度（0~1）
    public var state: UploadState        /// 当前任务状态
    public var response: Data?           /// 上传响应（成功时）
    public var error: Error?             /// 错误信息（失败时）
}

// MARK: - 上传任务事件委托
/// 上传任务事件协议，支持单任务/整体进度与完成通知
public protocol UploadManagerDelegate: AnyObject {
    /// 单任务上传进度更新
    func uploadProgressDidUpdate(task: UploadTaskInfo)
    /// 单任务上传完成
    func uploadDidComplete(task: UploadTaskInfo)
    /// 单任务上传失败
    func uploadDidFail(task: UploadTaskInfo)
    /// 整体上传进度更新（所有未取消任务的平均进度，每次有变化都会回调）
    func uploadOverallProgressDidUpdate(progress: Double)
    /// 整体上传全部完成（所有未取消任务 completed 时回调，只回调一次）
    func uploadOverallDidComplete()
}

// MARK: - 内部上传任务结构体
/// UploadManager 内部使用的上传任务结构体
private struct UploadTask {
    let id: UUID                   /// 任务唯一标识
    let fileURL: URL               /// 本地文件路径
    let uploadURL: URL             /// 目标上传接口URL
    let formFieldName: String      /// 表单字段名
    var progress: Double           /// 当前进度
    var state: UploadState         /// 状态
    var response: AFDataResponse<Data?>            /// 上传响应数据
    var error: Error?              /// 错误信息
    var request: UploadRequest?    /// Alamofire 上传请求对象
}

// MARK: - 上传管理器
/// 支持批量/单个上传、并发控制、进度回调、整体进度回调
public actor UploadManager {
    public let identifier: String                          /// 队列唯一标识
    private var tasks: [UUID: UploadTask] = [:]            /// 所有任务（任务ID为Key）
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects() /// 事件委托集合
    private var maxConcurrentUploads: Int                  /// 最大并发上传数
    private var currentUploadingCount: Int = 0             /// 当前正在上传的任务数
    private var pendingQueue: [UUID] = []                  /// 等待上传的任务队列
    private var overallCompletedCalled: Bool = false       /// 整体完成回调只调用一次
    
    /// Token 管理器
    private var headers: [HTTPHeader] = []
    /// 请求响应拦截器
    private var interceptor: RequestInterceptorProtocol?

    // MARK: - 初始化
    /// 初始化 UploadManager
    /// - Parameters:
    ///   - identifier: 队列标识
    ///   - maxConcurrentUploads: 最大并发上传数（默认3）
    ///   - headers: 基础 Headers
    ///   - interceptor: 拦截器
    public init(identifier: String = UUID().uuidString, maxConcurrentUploads: Int = 3,headers: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "multipart/form-data")],interceptor:RequestInterceptorProtocol? = nil) {
        self.identifier = identifier
        self.maxConcurrentUploads = maxConcurrentUploads
        self.headers = headers
        self.interceptor = interceptor
    }

    // MARK: - 并发设置
    /// 设置最大并发上传数
    /// - Parameter count: 新的并发数（最小1）
    public func setMaxConcurrentUploads(_ count: Int) {
        self.maxConcurrentUploads = max(1, count)
        Task { self.checkAndStartNext() }
    }

    // MARK: - 委托管理
    /// 添加上传事件委托对象
    /// - Parameter delegate: 要添加的委托对象
    public func addDelegate(_ delegate: UploadManagerDelegate) {
        delegates.add(delegate)
    }
    /// 移除上传事件委托对象
    /// - Parameter delegate: 要移除的委托对象
    public func removeDelegate(_ delegate: UploadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 批量上传
    /// 批量上传文件
    /// - Parameters:
    ///   - uploadURL: 目标上传接口URL
    ///   - fileURLs: 本地文件URL数组
    ///   - formFieldName: 上传字段名，通常为"file"或"files"
    ///   - extraForm: 额外表单参数
    /// - Returns: 各任务ID组成的数组
    public func batchUpload(
        uploadURL: URL,
        fileURLs: [URL],
        formFieldName: String = "file",
        extraForm: [String: String]? = nil
    ) async -> [UUID] {
        var ids: [UUID] = []
        for fileURL in fileURLs {
            let id = await startUpload(
                fileURL: fileURL,
                uploadURL: uploadURL,
                formFieldName: formFieldName,
                extraForm: extraForm
            )
            ids.append(id)
        }
        return ids
    }

    // MARK: - 单任务上传
    /// 启动单个上传任务
    /// - Parameters:
    ///   - fileURL: 本地文件路径
    ///   - uploadURL: 目标上传接口URL
    ///   - formFieldName: 上传字段名
    ///   - extraForm: 额外表单参数
    /// - Returns: 任务ID
    public func startUpload(
        fileURL: URL,
        uploadURL: URL,
        formFieldName: String = "file",
        extraForm: [String: String]? = nil
    ) async -> UUID {
        let id = UUID()
        let task = UploadTask(
            id: id,
            fileURL: fileURL,
            uploadURL: uploadURL,
            formFieldName: formFieldName,
            progress: 0,
            state: .idle,
            response: nil,
            error: nil,
            request: nil
        )
        tasks[id] = task
        enqueueOrStartTask(id: id, extraForm: extraForm)
        return id
    }

    /// 判断是否可立即启动任务，否则加入等待队列
    private func enqueueOrStartTask(id: UUID, extraForm: [String: String]?) {
        if currentUploadingCount < maxConcurrentUploads {
            startTaskInternal(id: id, extraForm: extraForm)
        } else {
            if !pendingQueue.contains(id) {
                pendingQueue.append(id)
            }
            updateTaskState(id: id, state: .idle)
        }
    }

    /// 手动启动任务（用于恢复等场景）
    public func startTask(id: UUID, extraForm: [String: String]? = nil) {
        enqueueOrStartTask(id: id, extraForm: extraForm)
    }

    /// 实际发起上传（内部并发调度）
    private func startTaskInternal(id: UUID, extraForm: [String: String]?) {
        guard let task = tasks[id] else { return }
        guard task.state == .idle || task.state == .paused else { return }
        var currentTask = task
        currentTask.state = .uploading

        currentUploadingCount += 1

        let request = AF.upload(
            multipartFormData: { multipartFormData in
                if let data = try? Data(contentsOf: currentTask.fileURL) {
                    multipartFormData.append(data, withName: currentTask.formFieldName, fileName: currentTask.fileURL.lastPathComponent, mimeType: Self.mimeType(for: currentTask.fileURL))
                }
                // 额外表单参数
                extraForm?.forEach { key, value in
                    multipartFormData.append(Data(value.utf8), withName: key)
                }
            },
            to: currentTask.uploadURL,
            method: .post,
            headers: self.headers,
            interceptor:self.interceptor
        )
        .uploadProgress { [weak self] progress in
            Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
        }
        .response { [weak self] response in
            Task { await self?.onComplete(id: id, response: response) }
        }

        currentTask.request = request
        tasks[id] = currentTask
        notifyProgress(currentTask)
        notifyOverallProgress()
    }

    // MARK: - 任务控制
    /// 暂停指定任务
    /// - Parameter id: 任务ID
    public func pauseTask(id: UUID) {
        guard var task = tasks[id], let request = task.request else { return }
        request.suspend()
        if task.state == .uploading {
            currentUploadingCount = max(0, currentUploadingCount - 1)
            Task { self.checkAndStartNext() }
        }
        task.state = .paused
        tasks[id] = task
        notifyProgress(task)
        notifyOverallProgress()
    }

    /// 恢复指定任务
    /// - Parameter id: 任务ID
    public func resumeTask(id: UUID, extraForm: [String: String]? = nil) {
        guard let task = tasks[id] else { return }
        if task.state == .paused {
            enqueueOrStartTask(id: id, extraForm: extraForm)
        }
    }

    /// 取消指定任务
    /// - Parameter id: 任务ID
    public func cancelTask(id: UUID) {
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
            updateTaskState(id: id, state: .cancelled)
            notifyProgress(tasks[id]!)
            notifyOverallProgress()
            return
        }
        guard var task = tasks[id], let request = task.request else { return }
        request.cancel()
        if task.state == .uploading {
            currentUploadingCount = max(0, currentUploadingCount - 1)
            Task { self.checkAndStartNext() }
        }
        task.state = .cancelled
        tasks[id] = task
        notifyProgress(task)
        notifyOverallProgress()
    }

    /// 移除任务（不会删除本地文件，仅移除管理器记录）
    /// - Parameter id: 任务ID
    public func removeTask(id: UUID) {
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
        notifyOverallProgress()
    }

    // MARK: - 状态查询
    /// 获取单个任务的信息
    /// - Parameter id: 任务ID
    /// - Returns: 任务信息
    public func getTaskInfo(id: UUID) -> UploadTaskInfo? {
        guard let task = tasks[id] else { return nil }
        return UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            error: task.error
        )
    }

    /// 获取所有任务的信息
    /// - Returns: 任务信息数组
    public func allTaskInfos() -> [UploadTaskInfo] {
        return tasks.values.map {
            UploadTaskInfo(
                id: $0.id,
                fileURL: $0.fileURL,
                progress: $0.progress,
                state: $0.state,
                response: $0.response,
                error: $0.error
            )
        }
    }

    // MARK: - 批量控制
    /// 批量暂停
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
    }
    /// 批量恢复
    public func batchResume(ids: [UUID], extraForm: [String: String]? = nil) {
        for id in ids { resumeTask(id: id, extraForm: extraForm) }
    }
    /// 批量取消
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
    }

    // MARK: - 并发队列调度
    /// 检查等待队列并按并发数启动新任务
    private func checkAndStartNext() {
        while currentUploadingCount < maxConcurrentUploads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            startTaskInternal(id: nextId, extraForm: nil)
        }
    }

    // MARK: - 上传事件回调
    /// 进度事件
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        currentTask.state = .uploading
        tasks[id] = currentTask
        notifyProgress(currentTask)
        notifyOverallProgress()
    }

    /// 完成事件
    private func onComplete(id: UUID, response: AFDataResponse<Data?>) async {
        guard var currentTask = tasks[id] else { return }
        currentUploadingCount = max(0, currentUploadingCount - 1)
        defer { Task { self.checkAndStartNext() } }
        if let error = response.error {
            currentTask.state = .failed
            currentTask.error = error
            tasks[id] = currentTask
            notifyFailure(currentTask)
            notifyOverallProgress()
            return
        }
        currentTask.progress = 1.0
        currentTask.state = .completed
        currentTask.response = response
        tasks[id] = currentTask
        notifyCompletion(currentTask)
        notifyOverallProgress()
    }

    /// 更新任务状态（内部调度用）
    private func updateTaskState(id: UUID, state: UploadState) {
        guard var task = tasks[id] else { return }
        task.state = state
        tasks[id] = task
    }

    // MARK: - 代理回调（保证主线程回调，防止 SwiftUI 线程警告）
    /// 通知所有委托：进度更新
    private func notifyProgress(_ task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            error: task.error
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadProgressDidUpdate(task: info)
            }
        }
    }
    /// 通知所有委托：上传完成
    private func notifyCompletion(_ task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            error: task.error
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadDidComplete(task: info)
            }
        }
    }
    /// 通知所有委托：上传失败
    private func notifyFailure(_ task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            error: task.error
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadDidFail(task: info)
            }
        }
    }

    // MARK: - 整体进度与整体完成
    /// 计算所有未取消任务的平均进度
    private func calcOverallProgress() -> Double {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        guard !validTasks.isEmpty else { return 1.0 }
        let sum = validTasks.map { min($0.progress, 1.0) }.reduce(0, +)
        return sum / Double(validTasks.count)
    }

    /// 检查所有未取消任务是否全部完成
    private func isOverallCompleted() -> Bool {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        return !validTasks.isEmpty && validTasks.allSatisfy { $0.state == .completed }
    }

    /// 通知整体进度、整体完成
    private func notifyOverallProgress() {
        let progress = calcOverallProgress()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadOverallProgressDidUpdate(progress: progress)
            }
        }
        // 整体完成事件只回调一次
        if isOverallCompleted(), !overallCompletedCalled {
            overallCompletedCalled = true
            for delegate in delegates.allObjects {
                Task { @MainActor in
                    (delegate as? UploadManagerDelegate)?.uploadOverallDidComplete()
                }
            }
        }
        // 若有新任务加入，重置整体完成flag
        if !isOverallCompleted() {
            overallCompletedCalled = false
        }
    }

    // MARK: - 工具方法
    /// 根据文件扩展名推测MIME类型
    /// - Parameter url: 本地文件路径
    /// - Returns: MIME类型字符串
    static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
