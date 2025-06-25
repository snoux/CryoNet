import Foundation
import Alamofire

#if os(iOS) || os(watchOS) || os(macOS)
import Photos
import UIKit
#endif

// MARK: - 下载任务状态
/// 下载任务的状态枚举。
///
/// 定义了下载任务在其生命周期中可能经历的各种状态。
public enum DownloadState: String {
    /// 任务处于等待状态，尚未开始下载或已完成。
    case idle
    /// 任务正在进行下载。
    case downloading
    /// 任务已暂停，可以恢复。
    case paused
    /// 任务已成功完成下载。
    case completed
    /// 任务下载失败。
    case failed
    /// 任务已被取消。
    case cancelled
}

// MARK: - 批量/全部下载的整体状态
/// 批量或全部下载任务的整体状态枚举。
///
/// 用于表示一组下载任务的聚合状态，方便UI层进行整体展示和控制。
public enum DownloadBatchState: String {
    /// 没有下载任务，或者所有任务都处于非活动状态。
    case idle
    /// 所有未完成的任务都在下载中。
    case downloading
    /// 所有未完成的任务都处于暂停状态。
    case paused
    /// 所有未取消的任务都已成功完成。
    case completed
}

// MARK: - 下载任务信息
/// 下载任务的公开信息结构体。
///
/// 此结构体提供了下载任务的关键信息，供UI层展示和外部模块查询任务状态与详情。
/// 它实现了 `Identifiable` 协议，方便在SwiftUI等框架中使用。
public struct DownloadTaskInfo: Identifiable {
    /// 任务的唯一标识符。
    public let id: UUID
    /// 下载资源的URL。
    public let url: URL
    /// 当前下载进度，范围从0.0到1.0。
    public var progress: Double
    /// 当前任务的状态。
    public var state: DownloadState
    /// 文件保存的本地路径。
    public var destination: URL
    /// 关联的Alamofire下载请求对象。
    ///
    /// 如果需要获取更详细的响应信息（例如HTTP状态码、响应头等），
    /// 可以在UI层监听此 `DownloadRequest` 对象的事件。
    public var response: DownloadRequest?
}

// MARK: - 下载任务事件委托
/// 下载管理器事件回调协议。
///
/// 此协议定义了下载任务生命周期中的各种事件回调，包括单任务进度、完成、失败，
/// 以及整体进度和批量状态的更新。遵循此协议的对象可以接收并处理这些事件。
public protocol DownloadManagerDelegate: AnyObject {
    /// 当单个下载任务的进度更新时调用。
    /// - Parameter task: 包含最新进度信息的 `DownloadTaskInfo` 对象。
    func downloadProgressDidUpdate(task: DownloadTaskInfo)
    /// 当单个下载任务成功完成时调用。
    /// - Parameter task: 包含完成任务信息的 `DownloadTaskInfo` 对象。
    func downloadDidComplete(task: DownloadTaskInfo)
    /// 当单个下载任务失败时调用。
    /// - Parameter task: 包含失败任务信息的 `DownloadTaskInfo` 对象。
    func downloadDidFail(task: DownloadTaskInfo)
    /// 当所有未取消任务的整体平均进度更新时调用。
    ///
    /// 每次有任何任务的进度变化时都会回调此方法。
    /// - Parameter progress: 所有有效任务的平均进度，范围从0.0到1.0。
    func downloadOverallProgressDidUpdate(progress: Double)
    /// 当所有未取消任务都已完成时调用。
    ///
    /// 此方法只会在所有任务首次全部完成时回调一次。
    func downloadOverallDidComplete()
    /// 当批量下载的整体状态发生变化时调用。
    ///
    /// 例如，从“下载中”变为“暂停”或“完成”。
    /// - Parameter state: 最新的批量下载状态。
    func downloadBatchStateDidUpdate(state: DownloadBatchState)
}

/// `DownloadManagerDelegate` 协议的默认实现。
///
/// 允许遵循此协议的类选择性地实现协议方法，而无需实现所有方法。
public extension DownloadManagerDelegate {
    func downloadProgressDidUpdate(task: DownloadTaskInfo) {}
    func downloadDidComplete(task: DownloadTaskInfo) {}
    func downloadDidFail(task: DownloadTaskInfo) {}
    func downloadOverallProgressDidUpdate(progress: Double) {}
    func downloadOverallDidComplete() {}
    func downloadBatchStateDidUpdate(state: DownloadBatchState) {}
}

// MARK: - 内部下载任务结构体
/// 内部使用的下载任务结构体。
///
/// 包含下载任务的详细信息，仅供 `DownloadManager` 内部管理使用。
private struct DownloadTask {
    /// 任务的唯一标识符。
    let id: UUID
    /// 下载资源的URL。
    let url: URL
    /// 目标文件保存路径。
    let destination: URL
    /// 下载完成后是否保存到相册（仅对图片/视频文件有效）。
    let saveToAlbum: Bool
    /// 当前下载进度，范围从0.0到1.0。
    var progress: Double
    /// 当前任务状态。
    var state: DownloadState
    /// 关联的Alamofire下载请求对象。
    var response: DownloadRequest?
}

// MARK: - 下载管理器
/// 支持批量/单个下载、并发控制、进度与状态回调的下载管理器。
///
/// 此管理器使用 Swift Actor 模型实现线程安全，并支持通过委托模式进行事件通知。
/// 可配合 `DownloadManagerPool` 支持多队列业务隔离。
///
/// - Note: `DownloadManager` 是一个 `actor`，所有对其状态的修改都应通过异步方法进行。
/// - SeeAlso: `DownloadManagerDelegate`, `DownloadTaskInfo`, `DownloadState`, `DownloadBatchState`
public actor DownloadManager {
    /// 队列的唯一标识符，便于业务区分和管理。
    public let identifier: String
    /// 存储所有下载任务的字典，以任务ID为键。
    private var tasks: [UUID: DownloadTask] = [:]
    /// 存储所有弱引用的事件委托对象。
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    /// 最大并发下载数。
    private var maxConcurrentDownloads: Int
    /// 当前正在下载的任务数量。
    private var currentDownloadingCount: Int = 0
    /// 等待下载的任务队列。
    private var pendingQueue: [UUID] = []
    /// 文件管理器实例。
    private let fileManager = FileManager.default
    /// 标记整体完成回调是否已触发，确保只回调一次。
    private var overallCompletedCalled: Bool = false
    /// 默认的HTTP请求头。
    private let headers: HTTPHeaders?
    /// 可自定义的Alamofire请求拦截器。
    private let interceptor: RequestInterceptor?

    /// 最近一次的批量状态，用于防止重复回调。
    private var lastBatchState: DownloadBatchState = .idle

    // MARK: - 初始化
    /// 创建 `DownloadManager` 实例。
    ///
    /// - Parameters:
    ///   - identifier: 队列的唯一标识符。默认为一个新的UUID字符串。
    ///   - maxConcurrentDownloads: 最大并发下载数。默认为3。
    ///   - headers: 应用于所有下载请求的默认HTTP头。默认为 `nil`。
    ///   - interceptor: 自定义的Alamofire请求拦截器。默认为 `nil`。
    ///
    /// - Example:
    /// ```swift
    /// let manager = DownloadManager(identifier: "myDownloadQueue", maxConcurrentDownloads: 5)
    /// ```
    public init(
        identifier: String = UUID().uuidString,
        maxConcurrentDownloads: Int = 3,
        headers: HTTPHeaders? = nil,
        interceptor: RequestInterceptor? = nil
    ) {
        self.identifier = identifier
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.headers = headers
        self.interceptor = interceptor
    }

    // MARK: - 并发设置
    /// 设置最大并发下载数。
    ///
    /// 更改此设置会立即影响下载队列的调度。
    /// - Parameter count: 新的最大并发数。最小值为1。
    ///
    /// - Example:
    /// ```swift
    /// await manager.setMaxConcurrentDownloads(2)
    /// ```
    public func setMaxConcurrentDownloads(_ count: Int) {
        self.maxConcurrentDownloads = max(1, count)
        Task { await self.checkAndStartNext() }
    }

    // MARK: - 委托管理
    /// 添加下载事件委托对象。
    ///
    /// 委托对象将接收下载任务的进度和状态更新。
    /// - Parameter delegate: 遵循 `DownloadManagerDelegate` 协议的委托对象。
    ///
    /// - Example:
    /// ```swift
    /// class MyDelegate: DownloadManagerDelegate { /* ... */ }
    /// let delegate = MyDelegate()
    /// manager.addDelegate(delegate)
    /// ```
    public func addDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.add(delegate)
    }
    /// 移除下载事件委托对象。
    ///
    /// 移除后，该委托对象将不再接收下载事件。
    /// - Parameter delegate: 要移除的委托对象。
    ///
    /// - Example:
    /// ```swift
    /// manager.removeDelegate(delegate)
    /// ```
    public func removeDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 批量下载
    /// 批量下载一组文件。
    ///
    /// 此方法会为每个文件创建一个下载任务并启动。
    /// - Parameters:
    ///   - baseURL: 所有文件的基础URL。
    ///   - fileNames: 要下载的文件名数组。
    ///   - destinationFolder: 文件保存的目标文件夹。如果为 `nil`，则使用默认下载文件夹。
    ///   - saveToAlbum: 下载完成后是否保存到相册（仅对图片/视频文件有效）。默认为 `false`。
    /// - Returns: 所有启动下载任务的UUID数组。
    ///
    /// - Example:
    /// ```swift
    /// let baseURL = URL(string: "https://example.com/files/")!
    /// let fileNames = ["image1.jpg", "document.pdf"]
    /// let taskIDs = await manager.batchDownload(baseURL: baseURL, fileNames: fileNames)
    /// ```
    public func batchDownload(
        baseURL: URL,
        fileNames: [String],
        destinationFolder: URL? = nil,
        saveToAlbum: Bool = false
    ) async -> [UUID] {
        var ids: [UUID] = []
        for name in fileNames {
            let fileURL = baseURL.appendingPathComponent(name)
            let destFolder = destinationFolder ?? Self.defaultDownloadFolder()
            let destURL = destFolder.appendingPathComponent(name)
            let id = await startDownload(from: fileURL, to: destURL, saveToAlbum: saveToAlbum)
            ids.append(id)
        }
        return ids
    }

    // MARK: - 单任务下载
    /// 启动一个单文件下载任务。
    ///
    /// - Parameters:
    ///   - url: 要下载的资源的URL。
    ///   - destination: 文件保存的目标路径。如果为 `nil`，则使用默认下载文件夹和文件名。
    ///   - saveToAlbum: 下载完成后是否保存到相册（仅对图片/视频文件有效）。默认为 `false`。
    /// - Returns: 新创建下载任务的唯一标识符UUID。
    ///
    /// - Example:
    /// ```swift
    /// let fileURL = URL(string: "https://example.com/image.png")!
    /// let taskID = await manager.startDownload(from: fileURL)
    /// ```
    public func startDownload(
        from url: URL,
        to destination: URL? = nil,
        saveToAlbum: Bool = false
    ) async -> UUID {
        let id = UUID()
        let destURL = destination ?? DownloadManager.defaultDownloadFolder().appendingPathComponent(url.lastPathComponent)
        let task = DownloadTask(
            id: id,
            url: url,
            destination: destURL,
            saveToAlbum: saveToAlbum,
            progress: 0,
            state: .idle,
            response: nil
        )
        tasks[id] = task
        enqueueOrStartTask(id: id)
        await updateBatchStateIfNeeded() /// 新增任务后，检查整体状态
        return id
    }

    /// 将任务加入队列或立即开始下载。
    ///
    /// 如果当前并发下载数未达到上限，则立即开始任务；否则，将任务加入等待队列。
    /// - Parameter id: 任务的唯一标识符。
    private func enqueueOrStartTask(id: UUID) {
        if currentDownloadingCount < maxConcurrentDownloads {
            startTaskInternal(id: id)
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
    /// - Parameter id: 要启动的任务的唯一标识符。
    ///
    /// - Example:
    /// ```swift
    /// // 假设 taskID 是一个已存在的任务ID
    /// await manager.startTask(id: taskID)
    /// ```
    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
        updateBatchStateIfNeeded()
    }

    /// 内部方法：真正开始一个下载任务。
    ///
    /// 处理任务状态更新、并发计数、Alamofire请求的创建和回调设置。
    /// - Parameter id: 要开始的任务的唯一标识符。
    private func startTaskInternal(id: UUID) {
        guard let task = tasks[id] else { return }
        guard task.state == .idle || task.state == .paused else { return }
        var currentTask = task
        currentTask.state = .downloading

        let destinationURL = currentTask.destination
        let destination: DownloadRequest.Destination = { _, _ in
            (destinationURL, [.createIntermediateDirectories, .removePreviousFile])
        }
        currentDownloadingCount += 1

        let request = AF.download(
            currentTask.url,
            method: .get,
            headers: headers,
            interceptor: interceptor,
            to: destination
        )
        .downloadProgress { [weak self] progress in
            Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
        }
        .responseData { [weak self] response in
            Task { await self?.onComplete(id: id, response: response) }
        }

        currentTask.response = request
        tasks[id] = currentTask
        notifyProgress(currentTask)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    // MARK: - 任务控制
    /// 暂停指定ID的下载任务。
    ///
    /// 如果任务正在下载，会减少当前下载计数并尝试启动下一个等待任务。
    /// - Parameter id: 要暂停的任务的唯一标识符。
    ///
    /// - Example:
    /// ```swift
    /// await manager.pauseTask(id: taskID)
    /// ```
    public func pauseTask(id: UUID) {
        guard var task = tasks[id], let request = task.response else { return }
        request.suspend()
        if task.state == .downloading {
            currentDownloadingCount = max(0, currentDownloadingCount - 1)
            Task { await self.checkAndStartNext() }
        }
        task.state = .paused
        tasks[id] = task
        notifyProgress(task)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 恢复指定ID的下载任务。
    ///
    /// 只有当任务处于暂停状态时才能恢复。
    /// - Parameter id: 要恢复的任务的唯一标识符。
    ///
    /// - Example:
    /// ```swift
    /// await manager.resumeTask(id: taskID)
    /// ```
    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else { return }
        if task.state == .paused {
            enqueueOrStartTask(id: id)
            updateBatchStateIfNeeded()
        }
    }

    /// 取消指定ID的下载任务。
    ///
    /// 如果任务在等待队列中，则直接移除；如果正在下载，则取消Alamofire请求。
    /// - Parameter id: 要取消的任务的唯一标识符。
    ///
    /// - Example:
    /// ```swift
    /// await manager.cancelTask(id: taskID)
    /// ```
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
        if task.state == .downloading {
            currentDownloadingCount = max(0, currentDownloadingCount - 1)
            Task { await self.checkAndStartNext() }
        }
        task.state = .cancelled
        tasks[id] = task
        notifyProgress(task)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 移除指定ID的下载任务。
    ///
    /// 此操作会从管理器中完全删除任务，但不会取消正在进行的下载。
    /// 通常在任务完成后调用。
    /// - Parameter id: 要移除的任务的唯一标识符。
    ///
    /// - Example:
    /// ```swift
    /// await manager.removeTask(id: taskID)
    /// ```
    public func removeTask(id: UUID) {
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    // MARK: - 状态查询
    /// 获取指定ID下载任务的公开信息。
    /// - Parameter id: 任务的唯一标识符。
    /// - Returns: 包含任务信息的 `DownloadTaskInfo` 对象，如果任务不存在则返回 `nil`。
    ///
    /// - Example:
    /// ```swift
    /// if let taskInfo = await manager.getTaskInfo(id: taskID) {
    ///     print("Task state: \(taskInfo.state)")
    /// }
    /// ```
    public func getTaskInfo(id: UUID) -> DownloadTaskInfo? {
        guard let task = tasks[id] else { return nil }
        return DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            response: task.response
        )
    }

    /// 获取所有下载任务的公开信息。
    /// - Returns: 包含所有任务信息的 `DownloadTaskInfo` 数组。
    ///
    /// - Example:
    /// ```swift
    /// let allTasks = await manager.allTaskInfos()
    /// for task in allTasks {
    ///     print("Task \(task.id): \(task.state)")
    /// }
    /// ```
    public func allTaskInfos() -> [DownloadTaskInfo] {
        return tasks.values.map {
            DownloadTaskInfo(
                id: $0.id,
                url: $0.url,
                progress: $0.progress,
                state: $0.state,
                destination: $0.destination,
                response: $0.response
            )
        }
    }

    // MARK: - 批量控制
    /// 批量暂停指定ID的下载任务。
    /// - Parameter ids: 要暂停的任务ID数组。
    ///
    /// - Example:
    /// ```swift
    /// await manager.batchPause(ids: [taskID1, taskID2])
    /// ```
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
        updateBatchStateIfNeeded()
    }
    /// 批量恢复指定ID的下载任务。
    /// - Parameter ids: 要恢复的任务ID数组。
    ///
    /// - Example:
    /// ```swift
    /// await manager.batchResume(ids: [taskID1, taskID2])
    /// ```
    public func batchResume(ids: [UUID]) {
        for id in ids { resumeTask(id: id) }
        updateBatchStateIfNeeded()
    }
    /// 批量取消指定ID的下载任务。
    /// - Parameter ids: 要取消的任务ID数组。
    ///
    /// - Example:
    /// ```swift
    /// await manager.batchCancel(ids: [taskID1, taskID2])
    /// ```
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
        updateBatchStateIfNeeded()
    }

    // MARK: - 并发队列调度
    /// 检查并启动等待队列中的下一个任务。
    ///
    /// 当有下载任务完成或暂停时，此方法会被调用以维持最大并发数。
    private func checkAndStartNext() {
        while currentDownloadingCount < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            startTaskInternal(id: nextId)
        }
        updateBatchStateIfNeeded()
    }

    // MARK: - 下载事件回调
    /// 处理单个任务的进度更新。
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - progress: 当前进度值。
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        currentTask.state = .downloading
        tasks[id] = currentTask
        notifyProgress(currentTask)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 处理单个任务的完成或失败。
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - response: Alamofire的下载响应对象。
    private func onComplete(id: UUID, response: AFDownloadResponse<Data>) async {
        guard var currentTask = tasks[id] else { return }
        currentDownloadingCount = max(0, currentDownloadingCount - 1)
        defer { Task { await self.checkAndStartNext() } }
        if response.error != nil {
            currentTask.state = .failed
            tasks[id] = currentTask
            notifyFailure(currentTask)
            notifyOverallProgress()
            updateBatchStateIfNeeded()
            return
        }
        currentTask.progress = 1.0
        currentTask.state = .completed
        tasks[id] = currentTask
        notifyCompletion(currentTask)
        notifyOverallProgress()
        updateBatchStateIfNeeded()
        if currentTask.saveToAlbum {
            #if os(iOS) || os(watchOS) || os(macOS)
            if #available(iOS 14, watchOS 7, macOS 11, *) {
                await Self.saveToAlbumIfNeeded(fileURL: currentTask.destination)
            }
            #endif
        }
    }

    /// 更新内部任务的状态。
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - state: 要设置的新状态。
    private func updateTaskState(id: UUID, state: DownloadState) {
        guard var task = tasks[id] else { return }
        task.state = state
        tasks[id] = task
    }

    // MARK: - 代理回调（保证主线程回调，防止 SwiftUI 线程警告）
    /// 通知所有委托对象单个任务的进度更新。
    /// - Parameter task: 包含最新进度信息的内部任务对象。
    private func notifyProgress(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            response: task.response
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadProgressDidUpdate(task: info)
            }
        }
    }
    /// 通知所有委托对象单个任务的完成。
    /// - Parameter task: 包含完成任务信息的内部任务对象。
    private func notifyCompletion(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            response: task.response
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadDidComplete(task: info)
            }
        }
    }
    /// 通知所有委托对象单个任务的失败。
    /// - Parameter task: 包含失败任务信息的内部任务对象。
    private func notifyFailure(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            response: task.response
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadDidFail(task: info)
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
    
    /// 计算当前批量下载的整体状态。
    /// - Returns: 当前的 `DownloadBatchState`。
    private func calcBatchState() -> DownloadBatchState {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        if validTasks.isEmpty { return .idle }
        if validTasks.allSatisfy({ $0.state == .completed }) { return .completed }
        if validTasks.allSatisfy({ $0.state == .paused }) { return .paused }
        if validTasks.allSatisfy({ $0.state == .downloading }) { return .downloading }
        return .idle
    }

    /// 检查并通知批量下载状态变更。
    ///
    /// 如果当前批量状态与上次记录的状态不同，则通知所有委托对象。
    private func updateBatchStateIfNeeded() {
        let newState = calcBatchState()
        if newState != lastBatchState {
            lastBatchState = newState
            for delegate in delegates.allObjects {
                Task { @MainActor in
                    (delegate as? DownloadManagerDelegate)?.downloadBatchStateDidUpdate(state: newState)
                }
            }
        }
    }

    /// 通知所有委托对象整体下载进度更新，并在整体完成时触发一次性回调。
    private func notifyOverallProgress() {
        let progress = calcOverallProgress()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadOverallProgressDidUpdate(progress: progress)
            }
        }
        if isOverallCompleted(), !overallCompletedCalled {
            overallCompletedCalled = true
            for delegate in delegates.allObjects {
                Task { @MainActor in
                    (delegate as? DownloadManagerDelegate)?.downloadOverallDidComplete()
                }
            }
        }
        if !isOverallCompleted() {
            overallCompletedCalled = false
        }
    }

    // MARK: - 工具方法
    /// 获取默认的下载文件夹URL。
    ///
    /// 在macOS上，返回用户的“下载”文件夹；在iOS/watchOS上，返回应用的“Documents”文件夹。
    /// - Returns: 默认下载文件夹的URL。
    public static func defaultDownloadFolder() -> URL {
        #if os(macOS)
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
    }

    #if os(iOS) || os(watchOS) || os(macOS)
    /// 将文件保存到相册（仅支持图片和视频）。
    /// - Parameter fileURL: 要保存的本地文件URL。
    /// - Note: 此方法仅在iOS 14+, watchOS 7+, macOS 11+ 平台上可用。
    /// - SeeAlso: `PHPhotoLibrary`
    @available(iOS 14, watchOS 7, macOS 11, *)
    private static func saveToAlbumIfNeeded(fileURL: URL) async {
        let pathExtension = fileURL.pathExtension.lowercased()
        let isImage = ["jpg", "jpeg", "png", "gif", "heic"].contains(pathExtension)
        let isVideo = ["mp4", "mov", "avi", "mkv"].contains(pathExtension)

        guard isImage || isVideo else { return }

        PHPhotoLibrary.requestAuthorization(for: isImage ? .addOnly : .readWrite) { status in
            guard status == .authorized else { return }

            PHPhotoLibrary.shared().performChanges { [fileURL] in
                if isImage {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                } else if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
            } completionHandler: { success, error in
                if !success {
                    print("Error saving to album: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    #endif

}


