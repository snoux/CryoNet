import Foundation
import Alamofire

#if os(iOS) || os(watchOS)
import UIKit
#endif

// MARK: - 上传任务状态
/// 上传任务的状态枚举。
///
/// 定义了上传任务在其生命周期中可能经历的各种状态。
public enum UploadState: String {
    /// 任务处于等待状态，刚创建但尚未开始上传。
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

// MARK: - 批量/整体上传状态
/// 批量或全部上传任务的整体状态枚举。
///
/// 用于表示一组上传任务的聚合状态，方便UI层进行整体展示和控制。
public enum UploadBatchState: String {
    /// 没有上传任务，或者所有任务都处于非活动状态。
    case idle
    /// 所有未取消的任务都在上传中。
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
public struct UploadTaskInfo: Identifiable {
    /// 任务的唯一标识符。
    public let id: UUID
    /// 本地文件路径，表示要上传的源文件。
    public let fileURL: URL
    /// 当前上传进度，范围从0.0到1.0。
    public var progress: Double
    /// 当前任务的状态。
    public var state: UploadState
    /// 关联的Alamofire数据请求对象。
    ///
    /// 如果需要获取更详细的响应信息（例如HTTP状态码、响应头等），
    /// 可以在UI层监听此 `DataRequest` 对象的事件。
    public var response: DataRequest?
    
    /// 关联的CryoResult对象，可用于链式响应处理
    public var cryoResult: CryoResult?
}

// MARK: - 上传任务事件委托
/// 上传管理器事件回调协议。
///
/// 此协议定义了上传任务生命周期中的各种事件回调，包括单任务进度、完成、失败，
/// 以及整体进度和批量状态的更新。遵循此协议的对象可以接收并处理这些事件。
public protocol UploadManagerDelegate: AnyObject {
    /// 当单个上传任务的进度更新时调用。
    /// - Parameter task: 包含最新进度信息的 `UploadTaskInfo` 对象。
    func uploadProgressDidUpdate(task: UploadTaskInfo)
    /// 当单个上传任务成功完成时调用。
    /// - Parameter task: 包含完成任务信息的 `UploadTaskInfo` 对象。
    func uploadDidComplete(task: UploadTaskInfo)
    /// 当单个上传任务失败时调用。
    /// - Parameter task: 包含失败任务信息的 `UploadTaskInfo` 对象。
    func uploadDidFail(task: UploadTaskInfo)
    /// 当所有未取消任务的整体平均进度更新时调用。
    ///
    /// 每次有任何任务的进度变化时都会回调此方法。
    /// - Parameter progress: 所有有效任务的平均进度，范围从0.0到1.0。
    func uploadOverallProgressDidUpdate(progress: Double)
    /// 当批量上传的整体状态发生变化时调用。
    ///
    /// 例如，从“上传中”变为“暂停”或“完成”。
    /// - Parameter state: 最新的批量上传状态。
    func uploadBatchStateDidUpdate(state: UploadBatchState)
}

public extension UploadManagerDelegate {
    func uploadProgressDidUpdate(task: UploadTaskInfo) {}
    func uploadDidComplete(task: UploadTaskInfo) {}
    func uploadDidFail(task: UploadTaskInfo) {}
    func uploadOverallProgressDidUpdate(progress: Double) {}
    func uploadBatchStateDidUpdate(state: UploadBatchState) {}
}

// MARK: - 内部上传任务结构体
/// 内部使用的上传任务结构体。
///
/// 包含上传任务的详细信息，仅供 `UploadManager` 内部管理使用。
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
/// 支持批量/单个上传、并发控制、进度回调、整体进度回调与批量状态回调的上传管理器。
///
/// 此管理器使用 Swift Actor 模型实现线程安全，并支持通过委托模式进行事件通知。
///
/// - Note: `UploadManager` 是一个 `actor`，所有对其状态的修改都应通过异步方法进行。
/// - SeeAlso: `UploadManagerDelegate`, `UploadTaskInfo`, `UploadState`, `UploadBatchState`
public actor UploadManager {
    /// 队列的唯一标识符，便于业务区分和管理。
    public let identifier: String
    /// 存储所有上传任务的字典，以任务ID为键。
    private var tasks: [UUID: UploadTask] = [:]
    /// 存储所有弱引用的事件委托对象。
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    /// 最大并发上传数。
    private var maxConcurrentUploads: Int
    /// 当前正在上传的任务数量。
    private var currentUploadingCount: Int = 0
    /// 等待上传的任务队列。
    private var pendingQueue: [UUID] = []
    /// 默认的HTTP请求头。
    private let headers: HTTPHeaders?
    /// 可自定义的Alamofire请求拦截器（通过 CryoNet 适配器）
    private var interceptor: InterceptorAdapter?
    private var businessInterceptor: RequestInterceptorProtocol?
    /// 最近一次的批量状态，用于防止重复回调。
    private var lastBatchState: UploadBatchState = .idle

    // MARK: - 初始化
    /// 创建 `UploadManager` 实例。
    ///
    /// - Parameters:
    ///   - identifier: 队列的唯一标识符。默认为一个新的UUID字符串。
    ///   - maxConcurrentUploads: 最大并发上传数。默认为3。
    ///   - headers: 应用于所有上传请求的默认HTTP头。默认为 `nil`。
    ///   - interceptor: 自定义的Alamofire请求拦截器。默认为 `nil`。
    ///   - toTokenManager: token管理器，缺省为 DefaultTokenManager
    ///
    /// - Example:
    /// ```swift
    /// let manager = UploadManager(identifier: "myUploadQueue", maxConcurrentUploads: 2)
    /// ```
    public init(
        identifier: String = UUID().uuidString,
        maxConcurrentUploads: Int = 3,
        headers: HTTPHeaders? = nil,
        interceptor: RequestInterceptorProtocol? = nil,
        toTokenManager: TokenManagerProtocol = DefaultTokenManager()
    ) {
        self.identifier = identifier
        self.maxConcurrentUploads = maxConcurrentUploads
        self.headers = headers
        var adapter: InterceptorAdapter? = nil
        if let userInterceptor = interceptor {
            adapter = InterceptorAdapter(
                interceptor: userInterceptor,
                tokenManager: toTokenManager
            )
        }
        self.businessInterceptor = interceptor
        self.interceptor = adapter
    }

    // MARK: - 并发设置
    /// 设置最大并发上传数。
    ///
    /// 更改此设置会立即影响上传队列的调度。
    /// - Parameter count: 新的最大并发数。最小值为1。
    ///
    /// - Example:
    /// ```swift
    /// await manager.setMaxConcurrentUploads(1)
    /// ```
    public func setMaxConcurrentUploads(_ count: Int) {
        self.maxConcurrentUploads = max(1, count)
        Task { await self.checkAndStartNext() }
    }

    // MARK: - 委托管理
    /// 添加上传事件委托对象。
    ///
    /// 委托对象将接收上传任务的进度和状态更新。
    /// - Parameter delegate: 遵循 `UploadManagerDelegate` 协议的委托对象。
    public func addDelegate(_ delegate: UploadManagerDelegate) {
        delegates.add(delegate)
    }
    /// 移除上传事件委托对象。
    ///
    /// 移除后，该委托对象将不再接收上传事件。
    /// - Parameter delegate: 要移除的委托对象。
    public func removeDelegate(_ delegate: UploadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 批量上传
    /// 批量上传一组文件。
    ///
    /// 此方法会为每个文件创建一个上传任务并启动。
    /// - Parameters:
    ///   - uploadURL: 目标上传接口的URL。
    ///   - fileURLs: 要上传的本地文件URL数组。
    ///   - formFieldName: 文件在表单中的字段名。默认为 "file"。
    ///   - extraForm: 额外的表单数据，以字典形式提供。默认为 `nil`。
    /// - Returns: 所有启动上传任务的UUID数组。
    ///
    /// - Example:
    /// ```swift
    /// let uploadURL = URL(string: "https://api.example.com/upload")!
    /// let file1 = URL(fileURLWithPath: "/path/to/file1.jpg")
    /// let file2 = URL(fileURLWithPath: "/path/to/file2.png")
    /// let taskIDs = await manager.batchUpload(uploadURL: uploadURL, fileURLs: [file1, file2])
    /// ```
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
        await updateBatchStateIfNeeded()
        return ids
    }

    // MARK: - 单任务上传
    /// 启动一个单文件上传任务。
    ///
    /// - Parameters:
    ///   - fileURL: 要上传的本地文件URL。
    ///   - uploadURL: 目标上传接口的URL。
    ///   - formFieldName: 文件在表单中的字段名。默认为 "file"。
    ///   - extraForm: 额外的表单数据，以字典形式提供。默认为 `nil`。
    /// - Returns: 新创建上传任务的唯一标识符UUID。
    ///
    /// - Example:
    /// ```swift
    /// let fileToUpload = URL(fileURLWithPath: "/path/to/my_document.pdf")
    /// let uploadTarget = URL(string: "https://api.example.com/documents")!
    /// let taskID = await manager.startUpload(fileURL: fileToUpload, uploadURL: uploadTarget)
    /// ```
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
            cryoResult: nil
        )
        tasks[id] = task
        enqueueOrStartTask(id: id, extraForm: extraForm)
        await updateBatchStateIfNeeded()
        return id
    }

    /// 将任务加入队列或立即开始上传。
    ///
    /// 如果当前并发上传数未达到上限，则立即开始任务；否则，将任务加入等待队列。
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - extraForm: 额外的表单数据，用于启动任务时传递。
    private func enqueueOrStartTask(id: UUID, extraForm: [String: String]?) {
        if currentUploadingCount < maxConcurrentUploads {
            startTaskInternal(id: id, extraForm: extraForm)
        } else {
            if !pendingQueue.contains(id) {
                pendingQueue.append(id)
            }
            updateTaskState(id: id, state: .idle)
        }
        updateBatchStateIfNeeded()
    }

    /// 启动指定ID的任务。
    ///
    /// 此方法会尝试启动一个处于等待或暂停状态的任务。
    /// - Parameters:
    ///   - id: 要启动的任务的唯一标识符。
    ///   - extraForm: 额外的表单数据，用于启动任务时传递。默认为 `nil`。
    public func startTask(id: UUID, extraForm: [String: String]? = nil) {
        enqueueOrStartTask(id: id, extraForm: extraForm)
        updateBatchStateIfNeeded()
    }

    /// 内部方法：真正开始一个上传任务。
    ///
    /// 处理任务状态更新、并发计数、Alamofire请求的创建和回调设置。
    /// - Parameters:
    ///   - id: 要开始的任务的唯一标识符。
    ///   - extraForm: 额外的表单数据，用于构建multipart请求。
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
                extraForm?.forEach { key, value in
                    multipartFormData.append(Data(value.utf8), withName: key)
                }
            },
            to: currentTask.uploadURL,
            method: .post,
            headers: headers,
            interceptor: interceptor
        )
        .uploadProgress { [weak self] progress in
            Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
        }
        .response { [weak self] _ in
            Task { await self?.onComplete(id: id) }
        }
//        currentTask.cryoResult = CryoResult(request: request, interceptor: self.interceptor)
        // 假设 businessInterceptor: RequestInterceptorProtocol?
        currentTask.cryoResult = CryoResult(request: request, interceptor: self.businessInterceptor)
        currentTask.response = request
        tasks[id] = currentTask
        notifyProgress(currentTask)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    // MARK: - 任务控制
    /// 暂停指定ID的上传任务。
    ///
    /// 如果任务正在上传，会减少当前上传计数并尝试启动下一个等待任务。
    /// - Parameter id: 要暂停的任务的唯一标识符。
    public func pauseTask(id: UUID) {
        guard var task = tasks[id], let request = task.response else { return }
        request.suspend()
        if task.state == .uploading {
            currentUploadingCount = max(0, currentUploadingCount - 1)
            Task { await self.checkAndStartNext() }
        }
        task.state = .paused
        tasks[id] = task
        notifyProgress(task)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 恢复指定ID的上传任务。
    ///
    /// 只有当任务处于暂停状态时才能恢复。
    /// - Parameters:
    ///   - id: 要恢复的任务的唯一标识符。
    ///   - extraForm: 恢复任务时可能需要的额外表单数据。默认为 `nil`。
    public func resumeTask(id: UUID, extraForm: [String: String]? = nil) {
        guard let task = tasks[id] else { return }
        if task.state == .paused {
            enqueueOrStartTask(id: id, extraForm: extraForm)
            updateBatchStateIfNeeded()
        }
    }

    /// 取消指定ID的上传任务。
    ///
    /// 如果任务在等待队列中，则直接移除；如果正在上传，则取消Alamofire请求。
    /// - Parameter id: 要取消的任务的唯一标识符。
    public func cancelTask(id: UUID) {
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
            updateTaskState(id: id, state: .cancelled)
            notifyProgress(tasks[id]!)
            notifyOverallProgress()
            updateBatchStateIfNeeded()
            return
        }
        guard var task = tasks[id], let request = task.response else { return }
        request.cancel()
        if task.state == .uploading {
            currentUploadingCount = max(0, currentUploadingCount - 1)
            Task { await self.checkAndStartNext() }
        }
        task.state = .cancelled
        tasks[id] = task
        notifyProgress(task)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 移除指定ID的上传任务。
    ///
    /// 此操作会从管理器中完全删除任务，但不会取消正在进行的上传。
    /// 通常在任务完成后调用。
    /// - Parameter id: 要移除的任务的唯一标识符。
    public func removeTask(id: UUID) {
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    // MARK: - 状态查询
    /// 获取指定ID上传任务的公开信息。
    /// - Parameter id: 任务的唯一标识符。
    /// - Returns: 包含任务信息的 `UploadTaskInfo` 对象，如果任务不存在则返回 `nil`。
    public func getTaskInfo(id: UUID) -> UploadTaskInfo? {
        guard let task = tasks[id] else { return nil }
        return UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
    }

    /// 获取所有上传任务的公开信息。
    /// - Returns: 包含所有任务信息的 `UploadTaskInfo` 数组。
    public func allTaskInfos() -> [UploadTaskInfo] {
        return tasks.values.map {
            UploadTaskInfo(
                id: $0.id,
                fileURL: $0.fileURL,
                progress: $0.progress,
                state: $0.state,
                response: $0.response,
                cryoResult: $0.cryoResult
            )
        }
    }

    // MARK: - 批量控制
    /// 批量暂停指定ID的上传任务。
    /// - Parameter ids: 要暂停的任务ID数组。
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
        updateBatchStateIfNeeded()
    }
    /// 批量恢复指定ID的上传任务。
    /// - Parameters:
    ///   - ids: 要恢复的任务ID数组。
    ///   - extraForm: 恢复任务时可能需要的额外表单数据。默认为 `nil`。
    public func batchResume(ids: [UUID], extraForm: [String: String]? = nil) {
        for id in ids { resumeTask(id: id, extraForm: extraForm) }
        updateBatchStateIfNeeded()
    }
    /// 批量取消指定ID的上传任务。
    /// - Parameter ids: 要取消的任务ID数组。
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
        updateBatchStateIfNeeded()
    }

    // MARK: - 并发队列调度
    /// 检查并启动等待队列中的下一个任务。
    ///
    /// 当有上传任务完成或暂停时，此方法会被调用以维持最大并发数。
    private func checkAndStartNext() {
        while currentUploadingCount < maxConcurrentUploads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            startTaskInternal(id: nextId, extraForm: nil)
        }
        updateBatchStateIfNeeded()
    }

    // MARK: - 上传事件回调
    /// 处理单个任务的进度更新。
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - progress: 当前进度值。
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        currentTask.state = .uploading
        tasks[id] = currentTask
        notifyProgress(currentTask)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 处理单个任务的完成。
    /// - Parameter id: 任务的唯一标识符。
    private func onComplete(id: UUID) async {
        guard var currentTask = tasks[id] else { return }
        currentUploadingCount = max(0, currentUploadingCount - 1)
        defer { Task { await self.checkAndStartNext() } }
        currentTask.progress = 1.0
        currentTask.state = .completed
        tasks[id] = currentTask
        notifyCompletion(currentTask)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 更新内部任务的状态。
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - state: 要设置的新状态。
    private func updateTaskState(id: UUID, state: UploadState) {
        guard var task = tasks[id] else { return }
        task.state = state
        tasks[id] = task
    }

    // MARK: - 代理回调（保证主线程回调，防止 SwiftUI 线程警告）
    /// 通知所有委托对象单个任务的进度更新。
    /// - Parameter task: 包含最新进度信息的内部任务对象。
    private func notifyProgress(_ task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadProgressDidUpdate(task: info)
            }
        }
    }
    /// 通知所有委托对象单个任务的完成。
    /// - Parameter task: 包含完成任务信息的内部任务对象。
    private func notifyCompletion(_ task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadDidComplete(task: info)
            }
        }
    }
    /// 通知所有委托对象单个任务的失败。
    /// - Parameter task: 包含失败任务信息的内部任务对象。
    private func notifyFailure(_ task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            fileURL: task.fileURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadDidFail(task: info)
            }
        }
    }

    // MARK: - 整体进度与整体完成
    /// 计算所有有效（未取消）任务的整体平均进度。
    /// - Returns: 整体平均进度，范围从0.0到1.0。如果没有有效任务，则返回1.0。
    private func calcOverallProgress() -> Double {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        guard !validTasks.isEmpty else { return 1.0 }
        let sum = validTasks.map { min($0.progress, 1.0) }.reduce(0, +)
        return sum / Double(validTasks.count)
    }

    /// 判断所有有效（未取消）任务是否都已完成。
    /// - Returns: 如果所有有效任务都已完成，则返回 `true`；否则返回 `false`。
    private func isOverallCompleted() -> Bool {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        return !validTasks.isEmpty && validTasks.allSatisfy { $0.state == .completed }
    }

    /// 计算批量上传的整体状态。
    /// - Returns: 当前的 `UploadBatchState`。
    private func calcBatchState() -> UploadBatchState {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        if validTasks.isEmpty { return .idle }
        if validTasks.allSatisfy({ $0.state == .completed }) { return .completed }
        if validTasks.allSatisfy({ $0.state == .paused }) { return .paused }
        if validTasks.allSatisfy({ $0.state == .uploading }) { return .uploading }
        return .idle
    }

    /// 检查并通知批量上传状态变更。
    ///
    /// 如果当前批量状态与上次记录的状态不同，则通知所有委托对象。
    private func updateBatchStateIfNeeded() {
        let newState = calcBatchState()
        if newState != lastBatchState {
            lastBatchState = newState
            for delegate in delegates.allObjects {
                Task { @MainActor in
                    (delegate as? UploadManagerDelegate)?.uploadBatchStateDidUpdate(state: newState)
                }
            }
        }
    }

    /// 通知所有委托对象整体上传进度更新。
    private func notifyOverallProgress() {
        let progress = calcOverallProgress()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadOverallProgressDidUpdate(progress: progress)
            }
        }
    }

    // MARK: - 工具方法
    /// 根据文件扩展名推测MIME类型。
    ///
    /// - Parameter url: 文件的URL。
    /// - Returns: 推测出的MIME类型字符串。如果无法推测，则返回 "application/octet-stream"。
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
