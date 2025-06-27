import Foundation
import Alamofire

// MARK: - 上传任务状态
/// 上传任务的状态枚举。
///
/// 定义了上传任务在其生命周期中可能经历的各种状态。
public enum UploadState: String {
    /// 任务处于等待状态，尚未开始上传或已完成。
    case idle
    /// 任务正在进行上传。
    case uploading
    /// 任务已暂停，可以恢复。
    case paused
    /// 任务已成功完成上传。
    case completed
    /// 任务上传失败。
    case failed
    /// 任务已被取消。
    case cancelled
}

// MARK: - 批量/全部上传的整体状态
/// 批量或全部上传任务的整体状态枚举。
///
/// 用于表示一组上传任务的聚合状态，方便UI层进行整体展示和控制。
public enum UploadBatchState: String {
    /// 没有上传任务，或者所有任务都处于非活动状态。
    case idle
    /// 所有未完成的任务都在上传中。
    case uploading
    /// 所有未完成的任务都处于暂停状态。
    case paused
    /// 所有未取消的任务都已成功完成。
    case completed
}

// MARK: - 上传任务信息
/// 上传任务的公开信息结构体。
///
/// 此结构体提供了上传任务的关键信息，供UI层展示和外部模块查询任务状态与详情。
/// 它实现了 `Identifiable` 协议，方便在SwiftUI等框架中使用。
public struct UploadTaskInfo: Identifiable, Equatable {
    public static func == (lhs: UploadTaskInfo, rhs: UploadTaskInfo) -> Bool {
        lhs.id == rhs.id
    }
    /// 任务的唯一标识符。
    public let id: UUID
    /// 本地文件路径。
    public let fileURL: URL
    /// 上传目标接口URL。
    public let uploadURL: URL
    /// 表单字段名
    public let formFieldName: String
    /// 当前上传进度，范围从0.0到1.0。
    public var progress: Double
    /// 当前任务的状态。
    public var state: UploadState
    /// 关联的Alamofire请求对象。
    public var response: DataRequest?
    /// 关联的CryoResult对象。
    public var cryoResult: CryoResult?
}

// MARK: - 上传管理器事件委托（推荐，仅需实现UI友好型回调，无需手动刷新列表）
/// 上传事件回调协议
///
/// ⚠️ legacy 方法（如 uploadProgressDidUpdate/OverallProgressDidUpdate 等）未来将被删除。
/// 推荐使用：
/// - uploadManagerDidUpdateActiveTasks(_:)
/// - uploadManagerDidUpdateCompletedTasks(_:)
/// - uploadManagerDidUpdateProgress(overallProgress:batchState:)
///
/// 示例用法:
/// ```swift
/// class MyUploadVM: ObservableObject, UploadManagerDelegate {
///     @Published var tasks: [UploadTaskInfo] = []
///     @Published var completed: [UploadTaskInfo] = []
///     @Published var progress: Double = 0
///     @Published var state: UploadBatchState = .paused
///     func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo]) { self.tasks = tasks }
///     func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo]) { self.completed = tasks }
///     func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) {
///         self.progress = overallProgress
///         self.state = batchState
///     }
/// }
/// ```
public protocol UploadManagerDelegate: AnyObject {
    /// ⚠️ legacy: 单任务进度更新（即将废弃）
    func uploadProgressDidUpdate(task: UploadTaskInfo)
    /// ⚠️ legacy: 单任务完成（即将废弃）
    func uploadDidComplete(task: UploadTaskInfo)
    /// ⚠️ legacy: 单任务失败（即将废弃）
    func uploadDidFail(task: UploadTaskInfo)
    /// ⚠️ legacy: 整体进度变更（即将废弃）
    func uploadOverallProgressDidUpdate(progress: Double)
    /// ⚠️ legacy: 批量状态变更（即将废弃）
    func uploadBatchStateDidUpdate(state: UploadBatchState)

    /// 所有未完成任务变化时回调（推荐）
    func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo])
    /// 已完成任务变化时回调（推荐）
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo])
    /// 整体进度或批量状态变化时回调（推荐）
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState)
}
public extension UploadManagerDelegate {
    func uploadProgressDidUpdate(task: UploadTaskInfo) {}
    func uploadDidComplete(task: UploadTaskInfo) {}
    func uploadDidFail(task: UploadTaskInfo) {}
    func uploadOverallProgressDidUpdate(progress: Double) {}
    func uploadBatchStateDidUpdate(state: UploadBatchState) {}
    func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo]) {}
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo]) {}
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) {}
}

// MARK: - 内部上传任务结构体
private struct UploadTask {
    /// 任务的唯一标识符。
    let id: UUID
    /// 本地文件路径。
    let fileURL: URL
    /// 目标上传接口的URL。
    let uploadURL: URL
    /// 文件在表单中的字段名。
    let formFieldName: String
    /// 当前上传进度，范围从0.0到1.0。
    var progress: Double
    /// 当前任务状态。
    var state: UploadState
    /// 关联的Alamofire数据请求对象。
    var response: DataRequest?
    /// 关联的CryoResult对象，可用于链式响应处理
    var cryoResult: CryoResult?
}

// MARK: - 上传管理器
/// 支持批量/单个上传、并发控制、进度与状态自动推送的上传管理器。
///
/// - 推荐仅用 uploadManagerDidUpdateActiveTasks / uploadManagerDidUpdateCompletedTasks / uploadManagerDidUpdateProgress
/// - 线程安全，基于 actor 实现
///
/// ### 常用用法:
/// ```swift
/// let manager = UploadManager()
/// await manager.addDelegate(self)
/// let ids = await manager.addTasks(files: [...])
/// await manager.batchStart(ids: ids)
/// ```
public actor UploadManager {
    /// 队列唯一标识
    public let identifier: String
    /// 全部上传任务
    private var tasks: [UUID: UploadTask] = [:]
    /// 事件委托
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    /// 最大并发数
    private var maxConcurrentUploads: Int
    /// 当前上传中数量
    private var currentUploadingCount: Int = 0
    /// 等待队列
    private var pendingQueue: [UUID] = []
    /// 批量状态缓存
    private var lastBatchState: UploadBatchState = .idle
    /// 总完成标记
    private var overallCompletedCalled: Bool = false
    private let headers: HTTPHeaders?
    private let interceptor: RequestInterceptor?

    // MARK: - 初始化
    /// 创建上传管理器
    /// - Parameters:
    ///   - identifier: 队列唯一ID，默认自动生成
    ///   - maxConcurrentUploads: 最大并发数，默认3
    ///   - headers: 全局请求头
    ///   - interceptor: 自定义请求拦截器
    public init(
        identifier: String = UUID().uuidString,
        maxConcurrentUploads: Int = 3,
        headers: HTTPHeaders? = nil,
        interceptor: RequestInterceptor? = nil
    ) {
        self.identifier = identifier
        self.maxConcurrentUploads = maxConcurrentUploads
        self.headers = headers
        self.interceptor = interceptor
    }

    // MARK: - 事件委托注册
    /// 添加事件委托
    public func addDelegate(_ delegate: UploadManagerDelegate) {
        delegates.add(delegate)
    }
    /// 移除事件委托
    public func removeDelegate(_ delegate: UploadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 任务注册与调度
    /// 注册单个上传任务（初始idle，不自动上传）
    ///
    /// - Returns: 任务ID
    public func addTask(
        fileURL: URL,
        uploadURL: URL,
        formFieldName: String = "file"
    ) -> UUID {
        let id = UUID()
        let task = UploadTask(
            id: id,
            fileURL: fileURL,
            uploadURL: uploadURL,
            formFieldName: formFieldName,
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
    public func addTasks(
        files: [(fileURL: URL, uploadURL: URL, formFieldName: String)]
    ) -> [UUID] {
        var ids: [UUID] = []
        for info in files {
            let id = addTask(fileURL: info.fileURL, uploadURL: info.uploadURL, formFieldName: info.formFieldName)
            ids.append(id)
        }
        return ids
    }
    /// 启动单任务（注册并立即上传）
    public func startUpload(
        fileURL: URL,
        uploadURL: URL,
        formFieldName: String = "file"
    ) async -> UUID {
        let id = addTask(fileURL: fileURL, uploadURL: uploadURL, formFieldName: formFieldName)
        enqueueOrStartTask(id: id)
        updateBatchStateIfNeeded()
        return id
    }
    /// 批量上传（注册并立即上传）
    public func batchUpload(
        files: [(fileURL: URL, uploadURL: URL, formFieldName: String)]
    ) async -> [UUID] {
        var ids: [UUID] = []
        for info in files {
            let id = await startUpload(fileURL: info.fileURL, uploadURL: info.uploadURL, formFieldName: info.formFieldName)
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
    public func batchResume(ids: [UUID]) {
        batchStart(ids: ids)
    }
    /// 批量暂停
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 批量取消
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 设置最大并发数
    public func setMaxConcurrentUploads(_ count: Int) {
        self.maxConcurrentUploads = max(1, count)
        Task { self.checkAndStartNext() }
    }

    // MARK: - 单任务控制
    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
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
    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else {return}
        if task.state == .paused || task.state == .idle || task.state == .failed {
            enqueueOrStartTask(id: id)
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
        }
    }
    public func cancelTask(id: UUID) {
        guard var task = tasks[id] else { return }
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
            task.state = .cancelled
            tasks[id] = task
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
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
    }
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
    private func startTaskInternal(id: UUID) {
        guard var currentTask = tasks[id] else { return }
        guard currentTask.state == .idle || currentTask.state == .paused else { return }
        currentTask.state = .uploading
        tasks[id] = currentTask

        currentUploadingCount += 1

        let request = AF.upload(
            multipartFormData: { multipart in
                multipart.append(currentTask.fileURL, withName: currentTask.formFieldName)
            },
            to: currentTask.uploadURL,
            headers: headers,
            interceptor: interceptor
        )
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
    private func checkAndStartNext() {
        while currentUploadingCount < maxConcurrentUploads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            if let task = tasks[nextId], task.state == .idle {
                startTaskInternal(id: nextId)
            }
        }
        notifyProgressAndBatchState()
    }

    // MARK: - 上传事件处理
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        if currentTask.state == .uploading {
            tasks[id] = currentTask
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
        }
    }
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
    }

    // MARK: - 事件派发(自动推送任务列表与进度)
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
                // legacy兼容
                (delegate as? UploadManagerDelegate)?.uploadOverallProgressDidUpdate(progress: progress)
                (delegate as? UploadManagerDelegate)?.uploadBatchStateDidUpdate(state: batch)
            }
        }
        if isOverallCompleted(), !overallCompletedCalled {
            overallCompletedCalled = true
        } else if !isOverallCompleted() && overallCompletedCalled {
            overallCompletedCalled = false
        }
    }
    private func updateBatchStateIfNeeded() {
        let newState = calcBatchState()
        if newState != lastBatchState {
            lastBatchState = newState
            notifyProgressAndBatchState()
        }
    }

    // MARK: - 状态/查询接口
    /// 获取所有任务信息
    public func allTaskInfos() -> [UploadTaskInfo] {
        return tasks.values.map {
            UploadTaskInfo(
                id: $0.id,
                fileURL: $0.fileURL,
                uploadURL: $0.uploadURL,
                formFieldName: $0.formFieldName,
                progress: $0.progress,
                state: $0.state,
                response: $0.response,
                cryoResult: $0.cryoResult
            )
        }
    }
    /// 获取所有任务ID
    public func allTaskIDs() -> [UUID] {
        return Array(tasks.keys)
    }
    /// 获取单个任务信息
    public func getTaskInfo(id: UUID) -> UploadTaskInfo? {
        guard let task = tasks[id] else { return nil }
        return UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            uploadURL: task.uploadURL,
            formFieldName: task.formFieldName,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
    }

    // MARK: - 进度/批量状态计算
    private func calcOverallProgress() -> Double {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        guard !validTasks.isEmpty else { return 1.0 }
        let sum = validTasks.map { min($0.progress, 1.0) }.reduce(0, +)
        return sum / Double(validTasks.count)
    }
    private func isOverallCompleted() -> Bool {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        return !validTasks.isEmpty && validTasks.allSatisfy { $0.state == .completed }
    }
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
}
