import Foundation
import Alamofire

// MARK: - 上传任务状态
/// 上传任务的状态枚举。
///
/// 定义了上传任务在其生命周期中可能经历的各种状态。
public enum UploadState: String {
    /// 任务处于等待状态，尚未开始上传或已完成。
    case idle
    /// 任务正在进行上传
    case uploading
    /// 任务已暂停，可以恢复
    case paused
    /// 任务已成功完成上传
    case completed
    /// 任务上传失败
    case failed
    /// 任务已被取消
    case cancelled
}

// MARK: - 批量/全部上传的整体状态
/// 批量或全部上传任务的整体状态枚举。
///
/// 用于表示一组上传任务的聚合状态，方便UI层进行整体展示和控制。
public enum UploadBatchState: String {
    /// 没有上传任务，或者所有任务都处于非活动状态。
    case idle
    /// 所有未完成的任务都在上传中
    case uploading
    /// 所有未完成的任务都处于暂停状态
    case paused
    /// 所有未取消的任务都已成功完成
    case completed
}

// MARK: - 上传数据源类型
/// 上传数据的来源类型定义
public enum UploadSource: Equatable {
    /// 本地文件URL
    case file(url: URL)
    /// 二进制数据（可选文件名，MIME类型）
    case data(data: Data, filename: String, mimeType: String?)
}

// MARK: - 上传任务信息
/// 上传任务的公开信息结构体。
///
/// 提供上传任务的关键信息，供UI层展示和外部模块查询任务状态与详情。
/// 实现了 `Identifiable` 协议，方便在SwiftUI等框架中使用。
public struct UploadTaskInfo: Identifiable, Equatable {
    public static func == (lhs: UploadTaskInfo, rhs: UploadTaskInfo) -> Bool {
        lhs.id == rhs.id
    }
    /// 任务的唯一标识符。
    public let id: UUID
    /// 上传源（本地文件/二进制数据）
    public let source: UploadSource
    /// 上传目标接口URL。
    public let uploadURL: URL
    /// 表单字段名。
    public let formFieldName: String
    /// 附加参数（表单键值对，可选）
    public let parameters: [String: Any]?
    /// 当前上传进度，范围从0.0到1.0。
    public var progress: Double
    /// 当前任务的状态。
    public var state: UploadState
    /// 关联的Alamofire请求对象。
    public var response: DataRequest?
    /// 关联的CryoResult对象。
    public var cryoResult: CryoResult?
}

// MARK: - 上传管理器事件委托
/// 上传事件回调协议
///
/// 实现该协议可自动感知上传任务及批量状态变更，推荐仅实现新API。
///
/// ### 使用示例
/// ```swift
/// class MyUploadVM: ObservableObject, UploadManagerDelegate {
///     @Published var tasks: [UploadTaskInfo] = []
///     @Published var completed: [UploadTaskInfo] = []
///     @Published var progress: Double = 0
///     @Published var state: UploadBatchState = .paused
///     func uploadDidUpdate(task: UploadTaskInfo) { /* 单任务变化 */ }
///     func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo]) { self.tasks = tasks }
///     func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo]) { self.completed = tasks }
///     func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) {
///         self.progress = overallProgress
///         self.state = batchState
///     }
/// }
/// ```
///
/// - SeeAlso: ``UploadTaskInfo``
public protocol UploadManagerDelegate: AnyObject {
    /// 单任务变化回调（状态或进度等）
    ///
    /// - Parameter task: 最新任务信息
    func uploadDidUpdate(task: UploadTaskInfo)
    /// 所有未完成任务变化时回调
    ///
    /// - Parameter tasks: 当前所有未完成任务
    func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo])
    /// 已完成任务变化时回调
    ///
    /// - Parameter tasks: 当前所有已完成任务
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo])
    /// 整体进度或批量状态变化时回调
    ///
    /// - Parameters:
    ///   - overallProgress: 总体进度(0.0-1.0)
    ///   - batchState: 批量上传状态
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState)
}
public extension UploadManagerDelegate {
    func uploadDidUpdate(task: UploadTaskInfo) {}
    func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo]) {}
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo]) {}
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) {}
}

// MARK: - 内部上传任务结构体
private struct UploadTask {
    let id: UUID
    let source: UploadSource
    let uploadURL: URL
    let formFieldName: String
    let parameters: [String: Any]?
    var progress: Double
    var state: UploadState
    var response: DataRequest?
    var cryoResult: CryoResult?
}

// MARK: - 上传管理器
/// 支持批量/单个上传、并发控制、进度与状态自动推送的上传管理器。
///
/// 支持本地文件或二进制数据上传，支持baseURL和相对路径，支持多表单字段参数，线程安全，基于actor实现。
///
/// ### 使用示例
/// ```swift
/// let manager = UploadManager(baseURL: URL(string: "https://api.example.com"))
/// // 上传本地文件并附带参数
/// let id = manager.addTask(
///     source: .file(url: fileURL),
///     uploadPathOrURL: "/upload/image",
///     parameters: [ "userId": 123, "desc": "图像" ]
/// )
/// // 上传二进制
/// let id2 = manager.addTask(
///     source: .data(data: data, filename: "demo.jpg", mimeType: "image/jpeg"),
///     uploadPathOrURL: "/upload/image",
///     parameters: [ "userId": 456 ]
/// )
/// await manager.startTask(id: id)
/// await manager.startTask(id: id2)
/// ```
///
/// - Note: 推荐仅在主UI层持有UploadManager实例，避免多实例竞争同一文件。
/// - SeeAlso: ``UploadManagerDelegate``, ``UploadTaskInfo``, ``UploadSource``
public actor UploadManager {
    /// 队列唯一标识
    public let identifier: String
    /// 上传基础URL。支持传相对路径给上传任务。
    private let baseURL: URL?
    private var tasks: [UUID: UploadTask] = [:]
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private var maxConcurrentUploads: Int
    private var currentUploadingCount: Int = 0
    private var pendingQueue: [UUID] = []
    private var lastBatchState: UploadBatchState = .idle
    private var overallCompletedCalled: Bool = false
    private let headers: HTTPHeaders?
    private let interceptor: RequestInterceptor?

    // MARK: - 初始化
    /// 创建上传管理器
    ///
    /// - Parameters:
    ///   - identifier: 队列唯一ID，默认自动生成
    ///   - baseURL: 上传基础URL（可选），如传入则addTask可用相对路径
    ///   - maxConcurrentUploads: 最大并发数，默认3
    ///   - headers: 全局请求头
    ///   - interceptor: 自定义请求拦截器
    ///
    /// ### 使用示例
    /// ```
    /// let manager = UploadManager(baseURL: URL(string: "https://api.example.com"))
    /// ```
    public init(
        identifier: String = UUID().uuidString,
        baseURL: URL? = nil,
        maxConcurrentUploads: Int = 3,
        headers: HTTPHeaders? = nil,
        interceptor: RequestInterceptor? = nil
    ) {
        self.identifier = identifier
        self.baseURL = baseURL
        self.maxConcurrentUploads = maxConcurrentUploads
        self.headers = headers
        self.interceptor = interceptor
    }

    // MARK: - URL拼接辅助
    /// 内部：将字符串路径或URL转为绝对URL
    ///
    /// - Parameter pathOrURL: 路径或完整URL
    /// - Returns: 绝对URL
    private func makeAbsoluteURL(from pathOrURL: String) -> URL? {
        if let url = URL(string: pathOrURL), url.scheme != nil {
            // 已是完整URL
            return url
        } else if let baseURL, let url = URL(string: pathOrURL, relativeTo: baseURL) {
            return url.absoluteURL
        } else {
            return nil
        }
    }

    // MARK: - 事件委托注册
    /// 添加事件委托
    ///
    /// - Parameter delegate: 订阅者
    public func addDelegate(_ delegate: UploadManagerDelegate) {
        delegates.add(delegate)
    }
    /// 移除事件委托
    ///
    /// - Parameter delegate: 订阅者
    public func removeDelegate(_ delegate: UploadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 任务注册与调度
    /// 注册单个上传任务（初始idle，不自动上传）
    ///
    /// - Parameters:
    ///   - source: 上传数据源（本地文件或二进制数据）
    ///   - uploadPathOrURL: 上传接口的相对路径或完整URL
    ///   - formFieldName: 表单字段名，默认"file"
    ///   - parameters: 附加参数（如表单键值对），可选
    /// - Returns: 任务ID
    ///
    /// - Note: 只注册任务，不自动开始上传。附加参数会以普通表单字段方式随文件一起上传。
    public func addTask(
        source: UploadSource,
        uploadPathOrURL: String,
        formFieldName: String = "file",
        parameters: [String: Any]? = nil
    ) -> UUID {
        guard let uploadURL = makeAbsoluteURL(from: uploadPathOrURL) else {
            fatalError("Invalid upload url: \(uploadPathOrURL)")
        }
        let id = UUID()
        let task = UploadTask(
            id: id,
            source: source,
            uploadURL: uploadURL,
            formFieldName: formFieldName,
            parameters: parameters,
            progress: 0,
            state: .idle,
            response: nil,
            cryoResult: nil
        )
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        return id
    }

    /// 批量注册任务（初始idle）
    ///
    /// - Parameters:
    ///   - files: 文件信息元组数组（source, uploadPathOrURL, formFieldName, parameters）
    /// - Returns: 任务ID数组
    public func addTasks(
        files: [(source: UploadSource, uploadPathOrURL: String, formFieldName: String, parameters: [String: Any]?)]
    ) -> [UUID] {
        var ids: [UUID] = []
        for info in files {
            let id = addTask(source: info.source, uploadPathOrURL: info.uploadPathOrURL, formFieldName: info.formFieldName, parameters: info.parameters)
            ids.append(id)
        }
        return ids
    }

    /// 启动单任务（注册并立即上传）
    ///
    /// - Parameters:
    ///   - source: 上传数据源（本地文件或二进制数据）
    ///   - uploadPathOrURL: 上传接口的相对路径或完整URL
    ///   - formFieldName: 表单字段名，默认"file"
    ///   - parameters: 附加参数（如表单键值对），可选
    /// - Returns: 任务ID
    public func startUpload(
        source: UploadSource,
        uploadPathOrURL: String,
        formFieldName: String = "file",
        parameters: [String: Any]? = nil
    ) async -> UUID {
        let id = addTask(source: source, uploadPathOrURL: uploadPathOrURL, formFieldName: formFieldName, parameters: parameters)
        enqueueOrStartTask(id: id)
        updateBatchStateIfNeeded()
        return id
    }

    /// 批量上传（注册并立即上传）
    ///
    /// - Parameters:
    ///   - files: 文件信息元组数组（source, uploadPathOrURL, formFieldName, parameters）
    /// - Returns: 任务ID数组
    public func batchUpload(
        files: [(source: UploadSource, uploadPathOrURL: String, formFieldName: String, parameters: [String: Any]?)]
    ) async -> [UUID] {
        var ids: [UUID] = []
        for info in files {
            let id = await startUpload(
                source: info.source,
                uploadPathOrURL: info.uploadPathOrURL,
                formFieldName: info.formFieldName,
                parameters: info.parameters
            )
            ids.append(id)
        }
        return ids
    }

    /// 启动所有任务（idle/paused）
    public func startAllTasks() {
        self.batchStart(ids: allTaskIDs())
    }
    /// 暂停所有任务
    public func stopAllTasks() {
        self.batchPause(ids: allTaskIDs())
    }
    /// 批量启动
    ///
    /// - Parameter ids: 任务ID数组
    public func batchStart(ids: [UUID]) {
        for id in ids {
            if let task = tasks[id], task.state == .idle || task.state == .paused {
                enqueueOrStartTask(id: id)
            }
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 批量恢复（等价于启动）
    ///
    /// - Parameter ids: 任务ID数组
    public func batchResume(ids: [UUID]) {
        batchStart(ids: ids)
    }
    /// 批量暂停
    ///
    /// - Parameter ids: 任务ID数组
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 批量取消
    ///
    /// - Parameter ids: 任务ID数组
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 设置最大并发数
    ///
    /// - Parameter count: 新的并发数，最小1
    ///
    /// ### 使用示例
    /// ```
    /// manager.setMaxConcurrentUploads(5)
    /// ```
    public func setMaxConcurrentUploads(_ count: Int) {
        self.maxConcurrentUploads = max(1, count)
        Task { self.checkAndStartNext() }
    }

    // MARK: - 单任务控制
    /// 启动单任务
    ///
    /// - Parameter id: 任务ID
    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 暂停单任务
    ///
    /// - Parameter id: 任务ID
    public func pauseTask(id: UUID) {
        guard var task = tasks[id] else { return }
        guard task.state == .uploading else {
            if task.state != .paused {
                task.state = .paused
                tasks[id] = task
                notifyTaskListUpdate()
                notifyProgressAndBatchState()
            }
            return
        }
        task.response?.suspend()
        currentUploadingCount = max(0, currentUploadingCount - 1)
        task.state = .paused
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        Task { self.checkAndStartNext() }
    }
    /// 恢复单任务
    ///
    /// - Parameter id: 任务ID
    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else {return}
        if task.state == .paused || task.state == .idle || task.state == .failed {
            enqueueOrStartTask(id: id)
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
        }
    }
    /// 取消单任务
    ///
    /// - Parameter id: 任务ID
    public func cancelTask(id: UUID) {
        guard var task = tasks[id] else { return }
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
            task.state = .cancelled
            tasks[id] = task
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
            notifySingleTaskUpdate(task: task)
            return
        }
        if task.state == .uploading {
            task.response?.cancel()
            currentUploadingCount = max(0, currentUploadingCount - 1)
            Task { self.checkAndStartNext() }
        }
        task.state = .cancelled
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
        notifySingleTaskUpdate(task: task)
    }
    /// 移除任务
    ///
    /// - Parameter id: 任务ID
    public func removeTask(id: UUID) {
        if let task = tasks[id], task.state == .uploading || pendingQueue.contains(id) {
            cancelTask(id: id)
        }
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }

    // MARK: - 私有：任务调度与上传
    /// 尝试立即启动任务，否则排队
    ///
    /// - Parameter id: 任务ID
    private func enqueueOrStartTask(id: UUID) {
        guard var task = tasks[id] else { return }
        guard task.state == .idle || task.state == .paused else { return }
        if currentUploadingCount < maxConcurrentUploads {
            startTaskInternal(id: id)
        } else {
            if !pendingQueue.contains(id) {
                pendingQueue.append(id)
            }
            task.state = .idle
            tasks[id] = task
        }
    }
    /// 内部上传启动
    ///
    /// - Parameter id: 任务ID
    private func startTaskInternal(id: UUID) {
        guard var currentTask = tasks[id] else { return }
        guard currentTask.state == .idle || currentTask.state == .paused else { return }
        currentTask.state = .uploading
        tasks[id] = currentTask

        currentUploadingCount += 1

        let request: DataRequest
        let params = currentTask.parameters ?? [:]
        switch currentTask.source {
        case .file(let url):
            request = AF.upload(
                multipartFormData: { multipart in
                    multipart.append(url, withName: currentTask.formFieldName)
                    Self.appendParameters(multipart: multipart, parameters: params)
                },
                to: currentTask.uploadURL,
                headers: headers,
                interceptor: interceptor
            )
        case .data(let data, let filename, let mimeType):
            request = AF.upload(
                multipartFormData: { multipart in
                    multipart.append(data, withName: currentTask.formFieldName, fileName: filename, mimeType: mimeType)
                    Self.appendParameters(multipart: multipart, parameters: params)
                },
                to: currentTask.uploadURL,
                headers: headers,
                interceptor: interceptor
            )
        }

        request
        .uploadProgress { [weak self] progress in
            Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
        }
        .response { [weak self] response in
            Task { await self?.onComplete(id: id, response: response) }
        }

        currentTask.cryoResult = nil
        currentTask.response = request
        tasks[id] = currentTask
    }

    /// 附加参数转换，支持Int/Float/Bool/String等常用类型
    private static func appendParameters(multipart: MultipartFormData, parameters: [String: Any]) {
        for (key, value) in parameters {
            if let data = Self.anyToData(value) {
                multipart.append(data, withName: key)
            }
        }
    }
    /// 任意类型转Data
    private static func anyToData(_ value: Any) -> Data? {
        switch value {
        case let v as Data: return v
        case let v as String: return v.data(using: .utf8)
        case let v as Int: return String(v).data(using: .utf8)
        case let v as Double: return String(v).data(using: .utf8)
        case let v as Float: return String(v).data(using: .utf8)
        case let v as Bool: return (v ? "true" : "false").data(using: .utf8)
        default: return nil
        }
    }

    // MARK: - 上传事件处理
    /// 上传进度回调
    ///
    /// - Parameters:
    ///   - id: 任务ID
    ///   - progress: 当前进度（0.0~1.0）
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        if currentTask.state == .uploading {
            tasks[id] = currentTask
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            notifySingleTaskUpdate(task: currentTask)
        }
    }
    /// 上传完成回调
    ///
    /// - Parameters:
    ///   - id: 任务ID
    ///   - response: 上传响应
    private func onComplete(id: UUID, response: AFDataResponse<Data?>) async {
        guard var currentTask = tasks[id] else { return }
        currentUploadingCount = max(0, currentUploadingCount - 1)
        defer { Task { self.checkAndStartNext() } }

        if response.error != nil {
            currentTask.state = .failed
            tasks[id] = currentTask
        } else {
            currentTask.progress = 1.0
            currentTask.state = .completed
            tasks[id] = currentTask
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        notifySingleTaskUpdate(task: currentTask)
    }

    // MARK: - 事件派发
    /// 推送单任务变化事件
    ///
    /// - Parameter task: 内部任务结构体
    private func notifySingleTaskUpdate(task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            source: task.source,
            uploadURL: task.uploadURL,
            formFieldName: task.formFieldName,
            parameters: task.parameters,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadDidUpdate(task: info)
            }
        }
    }
    /// 推送未完成和已完成任务列表
    private func notifyTaskListUpdate() {
        let all = allTaskInfos()
        let active = all.filter { $0.state != .completed && $0.state != .cancelled }
        let completed = all.filter { $0.state == .completed }
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateActiveTasks(active)
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateCompletedTasks(completed)
            }
        }
    }
    /// 推送整体进度和批量状态
    private func notifyProgressAndBatchState() {
        let progress = calcOverallProgress()
        let batch = calcBatchState()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateProgress(overallProgress: progress, batchState: batch)
            }
        }
        if isOverallCompleted(), !overallCompletedCalled {
            overallCompletedCalled = true
        } else if !isOverallCompleted() && overallCompletedCalled {
            overallCompletedCalled = false
        }
    }
    /// 检查并推送批量状态
    private func updateBatchStateIfNeeded() {
        let newState = calcBatchState()
        if newState != lastBatchState {
            lastBatchState = newState
            notifyProgressAndBatchState()
        }
    }

    // MARK: - 状态/查询接口
    /// 获取所有任务信息
    ///
    /// - Returns: 所有任务的 UploadTaskInfo 数组
    public func allTaskInfos() -> [UploadTaskInfo] {
        return tasks.values.map {
            UploadTaskInfo(
                id: $0.id,
                source: $0.source,
                uploadURL: $0.uploadURL,
                formFieldName: $0.formFieldName,
                parameters: $0.parameters,
                progress: $0.progress,
                state: $0.state,
                response: $0.response,
                cryoResult: $0.cryoResult
            )
        }
    }
    /// 获取所有任务ID
    ///
    /// - Returns: 所有任务ID数组
    public func allTaskIDs() -> [UUID] {
        return Array(tasks.keys)
    }
    /// 获取单个任务信息
    ///
    /// - Parameter id: 任务ID
    /// - Returns: 任务信息 UploadTaskInfo 或 nil
    public func getTaskInfo(id: UUID) -> UploadTaskInfo? {
        guard let task = tasks[id] else { return nil }
        return UploadTaskInfo(
            id: task.id,
            source: task.source,
            uploadURL: task.uploadURL,
            formFieldName: task.formFieldName,
            parameters: task.parameters,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
    }

    // MARK: - 进度/批量状态计算
    /// 计算所有未取消任务的平均进度
    ///
    /// - Returns: 平均进度
    private func calcOverallProgress() -> Double {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        guard !validTasks.isEmpty else { return 1.0 }
        let sum = validTasks.map { min($0.progress, 1.0) }.reduce(0, +)
        return sum / Double(validTasks.count)
    }
    /// 检查所有未取消任务是否全部完成
    ///
    /// - Returns: 是否全部完成
    private func isOverallCompleted() -> Bool {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        return !validTasks.isEmpty && validTasks.allSatisfy { $0.state == .completed }
    }
    /// 计算批量状态
    ///
    /// - Returns: 批量上传状态
    private func calcBatchState() -> UploadBatchState {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        if validTasks.isEmpty { return .idle }
        let completedCount = validTasks.filter { $0.state == .completed }.count
        let pausedCount = validTasks.filter { $0.state == .paused }.count
        let uploadingCount = validTasks.filter { $0.state == .uploading }.count
        let idleCount = validTasks.filter { $0.state == .idle }.count
        if completedCount == validTasks.count { return .completed }
        if pausedCount == validTasks.count { return .paused }
        if uploadingCount > 0 { return .uploading }
        if idleCount > 0 && uploadingCount == 0 && pausedCount == 0 { return .idle }
        if pausedCount > 0 && uploadingCount == 0 { return .paused }
        return .idle
    }

    /// 检查等待队列，尝试启动下一个任务
    private func checkAndStartNext() {
        while currentUploadingCount < maxConcurrentUploads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            if let task = tasks[nextId], task.state == .idle {
                startTaskInternal(id: nextId)
            }
        }
        notifyProgressAndBatchState()
    }
}
