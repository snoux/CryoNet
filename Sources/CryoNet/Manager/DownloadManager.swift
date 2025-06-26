
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
public struct DownloadTaskInfo: Identifiable, Equatable {
    public static func == (lhs: DownloadTaskInfo, rhs: DownloadTaskInfo) -> Bool {
        lhs.id == rhs.id
    }

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
    /// 关联的CryoResult对象，可用于链式响应处理
    public var cryoResult: CryoResult?
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
    /// 关联的CryoResult对象，可用于链式响应处理
    var cryoResult: CryoResult?
}

// MARK: - 下载管理器
/// 支持批量/单个下载、并发控制、进度与状态回调的下载管理器。
///
/// - 支持任务预注册（addTask/addTasks），可实现“先注册、后统一批量下载/暂停/恢复”
/// - 支持批量下载、批量暂停、批量恢复、批量取消
/// - 支持下载进度、完成、失败、状态变更的委托回调
/// - 支持 iOS/watchOS/macOS 的相册自动存储
/// - 支持 CryoResult 响应链式处理（部分功能）
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
    /// 业务拦截器，供 CryoResult 链式处理使用
    private let businessInterceptor: RequestInterceptorProtocol?
    /// 最近一次的批量状态，用于防止重复回调。
    private var lastBatchState: DownloadBatchState = .idle

    // MARK: - 初始化
    /// 创建 `DownloadManager` 实例。
    ///
    /// - Parameters:
    ///   - identifier: 队列的唯一标识符。默认为一个新的UUID字符串。
    ///   - maxConcurrentDownloads: 最大并发下载数。默认为3。
    ///   - headers: 应用于所有下载请求的默认HTTP头。默认为 `nil`。
    ///   - interceptor: 可选业务拦截器（链式处理用）。
    ///
    /// ### 使用示例:
    /// ```swift
    /// let manager = DownloadManager(identifier: "myDownloadQueue", maxConcurrentDownloads: 5)
    /// ```
    public init(
        identifier: String = UUID().uuidString,
        maxConcurrentDownloads: Int = 3,
        headers: HTTPHeaders? = nil,
        interceptor: RequestInterceptorProtocol? = nil
    ) {
        self.identifier = identifier
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.headers = headers
        self.businessInterceptor = interceptor
        // CryoResult链式处理与Alamofire上传一致，业务拦截器与请求无关
        self.interceptor = nil
    }

    // MARK: - 任务注册与统一批量调度

    /// 仅注册一个下载任务，不自动开始下载。任务初始状态为 `.idle`。
    ///
    /// 此方法适用于需要预先注册任务，然后通过 `batchStart` 或 `startTask` 统一调度的场景。
    ///
    /// - Parameters:
    ///   - url: 资源URL，即要下载的文件的网络地址。
    ///   - destination: 文件保存的本地路径。如果为 `nil`，则默认保存到应用的 `Documents/Downloads` 文件夹，并使用URL的最后一个路径组件作为文件名。
    ///   - saveToAlbum: 一个布尔值，指示下载完成后是否尝试将文件保存到系统相册（仅对图片和视频文件有效）。默认为 `false`。
    /// - Returns: 新注册任务的唯一标识符 `UUID`。
    ///
    /// ### 使用示例:
    /// ```swift
    /// let manager = DownloadManager()
    /// let fileURL = URL(string: "https://example.com/large_file.zip")!
    /// let taskId = await manager.addTask(url: fileURL)
    /// // 此时任务已注册，但未开始下载
    /// print("Task registered with ID: \(taskId)")
    /// ```
    public func addTask(
        url: URL,
        destination: URL? = nil,
        saveToAlbum: Bool = false
    ) -> UUID {
        let id = UUID()
        let destURL = destination ?? DownloadManager.defaultDownloadFolder().appendingPathComponent(url.lastPathComponent)
        let task = DownloadTask(
            id: id,
            url: url,
            destination: destURL,
            saveToAlbum: saveToAlbum,
            progress: 0,
            state: .idle,
            response: nil,
            cryoResult: nil
        )
        tasks[id] = task
        // 不自动开始
        return id
    }

    /// 批量注册下载任务，不自动开始下载。所有任务初始状态为 `.idle`。
    ///
    /// 此方法适用于需要预先注册多个任务，然后通过 `batchStart` 统一调度的场景。
    ///
    /// - Parameters:
    ///   - urls: 资源URL数组，包含所有要下载的文件的网络地址。
    ///   - destinationFolder: 文件保存的目标文件夹。如果为 `nil`，则所有文件默认保存到应用的 `Documents/Downloads` 文件夹。
    ///   - saveToAlbum: 一个布尔值，指示下载完成后是否尝试将文件保存到系统相册（仅对图片和视频文件有效）。默认为 `false`。
    /// - Returns: 新注册任务的唯一标识符 `UUID` 数组。
    ///
    /// ### 使用示例:
    /// ```swift
    /// let manager = DownloadManager()
    /// let urls = [
    ///     URL(string: "https://example.com/file1.pdf")!,
    ///     URL(string: "https://example.com/file2.jpg")!
    /// ]
    /// let taskIds = await manager.addTasks(urls: urls)
    /// print("Tasks registered: \(taskIds)")
    /// // 稍后可以调用 await manager.batchStart(ids: taskIds) 来开始下载
    /// ```
    public func addTasks(
        urls: [URL],
        destinationFolder: URL? = nil,
        saveToAlbum: Bool = false
    ) -> [UUID] {
        var ids: [UUID] = []
        for url in urls {
            let dest = destinationFolder?.appendingPathComponent(url.lastPathComponent)
            let id = addTask(url: url, destination: dest, saveToAlbum: saveToAlbum)
            ids.append(id)
        }
        return ids
    }

    /// 批量开始指定ID的下载任务。
    ///
    /// 此方法会尝试启动处于 `.idle` 或 `.paused` 状态的任务。任务将根据并发限制排队或立即开始。
    ///
    /// - Parameter ids: 要开始下载的任务的唯一标识符 `UUID` 数组。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 taskIds 是之前通过 addTask/addTasks 注册的任务ID数组
    /// await manager.batchStart(ids: taskIds)
    /// ```
    public func batchStart(ids: [UUID]) {
        for id in ids {
            if let task = tasks[id], task.state == .idle || task.state == .paused {
                enqueueOrStartTask(id: id)
            }
        }
        updateBatchStateIfNeeded()
    }

    /// 批量恢复指定ID的下载任务。
    ///
    /// 此方法等价于 `batchStart`，主要用于语义上的清晰，表示恢复之前暂停的任务。
    ///
    /// - Parameter ids: 要恢复下载的任务的唯一标识符 `UUID` 数组。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 pausedTaskIds 是之前暂停的任务ID数组
    /// await manager.batchResume(ids: pausedTaskIds)
    /// ```
    public func batchResume(ids: [UUID]) {
        batchStart(ids: ids)
    }

    /// 批量暂停指定ID的下载任务。
    ///
    /// 此方法会尝试暂停当前正在下载的任务。暂停后的任务状态变为 `.paused`。
    ///
    /// - Parameter ids: 要暂停下载的任务的唯一标识符 `UUID` 数组。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 downloadingTaskIds 是当前正在下载的任务ID数组
    /// await manager.batchPause(ids: downloadingTaskIds)
    /// ```
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
        updateBatchStateIfNeeded()
    }

    /// 批量取消指定ID的下载任务。
    ///
    /// 此方法会终止任务的下载进程，并将其状态设置为 `.cancelled`。取消的任务不能恢复。
    ///
    /// - Parameter ids: 要取消下载的任务的唯一标识符 `UUID` 数组。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 taskIdsToCancel 是要取消的任务ID数组
    /// await manager.batchCancel(ids: taskIdsToCancel)
    /// ```
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
        updateBatchStateIfNeeded()
    }

    // MARK: - 并发设置
    /// 设置下载管理器的最大并发下载数。
    ///
    /// 更改此设置会立即影响任务调度，可能会启动更多任务或暂停当前任务以符合新的限制。
    ///
    /// - Parameter count: 新的最大并发数。最小值为1。
    ///
    /// ### 使用示例:
    /// ```swift
    /// await manager.setMaxConcurrentDownloads(2) // 将最大并发数设置为2
    /// ```
    public func setMaxConcurrentDownloads(_ count: Int) {
        self.maxConcurrentDownloads = max(1, count)
        Task { await self.checkAndStartNext() }
    }

    // MARK: - 委托管理
    /// 添加下载事件委托对象。
    ///
    /// 委托对象将接收到下载任务生命周期中的各种事件回调。
    ///
    /// - Parameter delegate: 遵循 `DownloadManagerDelegate` 协议的委托对象。
    ///
    /// ### 使用示例:
    /// ```swift
    /// class MyDelegate: DownloadManagerDelegate { /* ... */ }
    /// let myDelegate = MyDelegate()
    /// await manager.addDelegate(myDelegate)
    /// ```
    public func addDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.add(delegate)
    }

    /// 移除下载事件委托对象。
    ///
    /// 移除后，该委托对象将不再接收到下载事件回调。
    ///
    /// - Parameter delegate: 要移除的委托对象。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 myDelegate 是之前添加的委托对象
    /// await manager.removeDelegate(myDelegate)
    /// ```
    public func removeDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 常规批量下载（兼容旧用法，注册即自动开始）
    /// 批量下载一组文件，注册后立即自动开始下载。
    ///
    /// 此方法适用于需要立即开始下载多个文件的场景。
    ///
    /// - Parameters:
    ///   - baseURL: 所有文件的基础URL。例如，如果文件都在 `https://example.com/downloads/` 下，则传入此URL。
    ///   - fileNames: 要下载的文件名数组。例如 `["image1.jpg", "document.pdf"]`。
    ///   - destinationFolder: 文件保存的目标文件夹。如果为 `nil`，则使用默认下载文件夹 `Documents/Downloads`。
    ///   - saveToAlbum: 下载完成后是否保存到相册（仅对图片/视频文件有效）。默认为 `false`。
    /// - Returns: 所有启动下载任务的 `UUID` 数组。
    ///
    /// ### 使用示例:
    /// ```swift
    /// let manager = DownloadManager()
    /// let base = URL(string: "https://example.com/assets/")!
    /// let files = ["video.mp4", "audio.mp3"]
    /// let taskIds = await manager.batchDownload(baseURL: base, fileNames: files, saveToAlbum: true)
    /// print("Batch download started for tasks: \(taskIds)")
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

    // MARK: - 单任务下载（注册即自动开始）
    /// 启动一个单文件下载任务，注册后立即自动开始下载。
    ///
    /// 此方法适用于需要立即开始下载单个文件的场景。
    ///
    /// - Parameters:
    ///   - url: 要下载的资源的URL。
    ///   - destination: 文件保存的目标路径。如果为 `nil`，则使用默认下载文件夹和URL的最后一个路径组件作为文件名。
    ///   - saveToAlbum: 下载完成后是否保存到相册（仅对图片/视频文件有效）。默认为 `false`。
    /// - Returns: 新创建下载任务的唯一标识符 `UUID`。
    ///
    /// ### 使用示例:
    /// ```swift
    /// let manager = DownloadManager()
    /// let imageUrl = URL(string: "https://example.com/photo.jpg")!
    /// let taskId = await manager.startDownload(from: imageUrl, saveToAlbum: true)
    /// print("Single download started for task: \(taskId)")
    /// ```
    public func startDownload(
        from url: URL,
        to destination: URL? = nil,
        saveToAlbum: Bool = false
    ) async -> UUID {
        let id = addTask(url: url, destination: destination, saveToAlbum: saveToAlbum)
        enqueueOrStartTask(id: id)
        await updateBatchStateIfNeeded()
        return id
    }

    /// 将任务加入队列或立即开始下载。
    ///
    /// 此内部方法根据当前并发数决定是立即启动任务还是将其加入等待队列。
    ///
    /// - Parameter id: 任务的唯一标识符。
    private func enqueueOrStartTask(id: UUID) {
        guard var task = tasks[id] else { return }

        // 如果任务已经在下载中或已完成/失败/取消，则不处理
        guard task.state == .idle || task.state == .paused else { return }

        if currentDownloadingCount < maxConcurrentDownloads {
            // 立即开始下载
            startTaskInternal(id: id)
        } else {
            // 加入等待队列
            if !pendingQueue.contains(id) {
                pendingQueue.append(id)
            }
            // 更新任务状态为 idle (等待中)
            task.state = .idle
            tasks[id] = task
            notifyProgress(task) // 通知状态更新为 idle
        }
        updateBatchStateIfNeeded()
    }

    /// 启动指定ID的下载任务。
    ///
    /// 此方法会尝试启动处于 `.idle` 或 `.paused` 状态的任务。任务将根据并发限制排队或立即开始。
    ///
    /// - Parameter id: 要启动的任务的唯一标识符。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 taskId 是一个已注册但未开始或已暂停的任务ID
    /// await manager.startTask(id: taskId)
    /// ```
    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
        // updateBatchStateIfNeeded() 已经在 enqueueOrStartTask 内部调用
    }

    /// 内部方法：真正开始一个下载任务。
    ///
    /// 此方法负责创建并启动Alamofire下载请求，并设置进度和完成回调。
    ///
    /// - Parameter id: 要开始的任务的唯一标识符。
    private func startTaskInternal(id: UUID) {
        guard var currentTask = tasks[id] else { return }
        // 确保任务状态是 idle 或 paused 才能开始
        guard currentTask.state == .idle || currentTask.state == .paused else { return }

        currentTask.state = .downloading
        tasks[id] = currentTask // 立即更新状态并保存
        notifyProgress(currentTask) // 立即通知状态变为 downloading

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
        
        currentTask.cryoResult = nil // 重置 cryoResult
        currentTask.response = request
        tasks[id] = currentTask // 更新任务的 response 对象
        
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    // MARK: - 任务控制
    /// 暂停指定ID的下载任务。
    ///
    /// 此方法会尝试暂停当前正在下载的任务。如果任务成功暂停，其状态将变为 `.paused`。
    ///
    /// - Parameter id: 要暂停的任务的唯一标识符。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 taskId 是一个正在下载的任务ID
    /// await manager.pauseTask(id: taskId)
    /// ```
    public func pauseTask(id: UUID) {
        guard var task = tasks[id] else { return }

        // 如果任务不是 downloading 状态，则直接更新状态并返回
        guard task.state == .downloading else {
            if task.state != .paused { // 避免重复通知已是暂停状态的任务
                task.state = .paused
                tasks[id] = task
                notifyProgress(task)
                notifyOverallProgress()
                updateBatchStateIfNeeded()
            }
            return
        }

        // 暂停 Alamofire 请求
        task.response?.suspend()
        
        currentDownloadingCount = max(0, currentDownloadingCount - 1)
        task.state = .paused
        tasks[id] = task
        notifyProgress(task) // 通知状态更新为 paused
        notifyOverallProgress()
        updateBatchStateIfNeeded()
        
        // 检查并启动等待队列中的下一个任务，因为一个下载槽位已释放
        Task { await self.checkAndStartNext() }
    }

    /// 恢复指定ID的下载任务。
    ///
    /// 此方法会尝试恢复处于 `.paused` `.idle` `.failed` 状态的任务。恢复后的任务将根据并发限制排队或立即开始。
    ///
    /// - Parameter id: 要恢复的任务的唯一标识符。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 taskId 是一个已暂停的任务ID
    /// await manager.resumeTask(id: taskId)
    /// ```
    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else {return}
        if task.state == .paused || task.state == .idle || task.state == .failed {
            enqueueOrStartTask(id: id)
        }
    }

    /// 取消指定ID的下载任务。
    ///
    /// 此方法会终止任务的下载进程，并将其状态设置为 `.cancelled`。取消的任务不能恢复。
    ///
    /// - Parameter id: 要取消的任务的唯一标识符。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 taskId 是一个正在下载或等待中的任务ID
    /// await manager.cancelTask(id: taskId)
    /// ```
    public func cancelTask(id: UUID) {
        guard var task = tasks[id] else { return }

        // 如果任务在等待队列中，直接移除并更新状态
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
            task.state = .cancelled
            tasks[id] = task
            notifyProgress(task) // 通知状态更新为 cancelled
            notifyOverallProgress()
            updateBatchStateIfNeeded()
            return
        }
        
        // 如果任务正在下载，取消 Alamofire 请求
        if task.state == .downloading {
            task.response?.cancel()
            currentDownloadingCount = max(0, currentDownloadingCount - 1)
            Task { await self.checkAndStartNext() }
        }
        
        task.state = .cancelled
        tasks[id] = task
        notifyProgress(task) // 通知状态更新为 cancelled
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 移除指定ID的下载任务。
    ///
    /// 此方法会从管理器中完全移除任务。如果任务正在下载或等待中，它将被取消。
    ///
    /// - Parameter id: 要移除的任务的唯一标识符。
    ///
    /// ### 使用示例:
    /// ```swift
    /// // 假设 taskId 是一个已完成或不再需要的任务ID
    /// await manager.removeTask(id: taskId)
    /// ```
    public func removeTask(id: UUID) {
        // 先尝试取消任务，确保资源释放
        if let task = tasks[id], task.state == .downloading || pendingQueue.contains(id) {
            cancelTask(id: id)
        }
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    // MARK: - 状态查询
    /// 获取指定ID下载任务的公开信息。
    ///
    /// - Parameter id: 任务的唯一标识符。
    /// - Returns: 包含任务信息的 `DownloadTaskInfo` 对象，如果任务不存在则返回 `nil`。
    ///
    /// ### 使用示例:
    /// ```swift
    /// if let taskInfo = await manager.getTaskInfo(id: someTaskId) {
    ///     print("Task state: \(taskInfo.state), progress: \(taskInfo.progress)")
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
            response: task.response,
            cryoResult: task.cryoResult
        )
    }

    /// 获取所有下载任务的公开信息。
    ///
    /// - Returns: 包含所有任务信息的 `DownloadTaskInfo` 数组。
    ///
    /// ### 使用示例:
    /// ```swift
    /// let allTasks = await manager.allTaskInfos()
    /// for task in allTasks {
    ///     print("Task \(task.id): state=\(task.state), progress=\(task.progress)")
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
                response: $0.response,
                cryoResult: $0.cryoResult
            )
        }
    }

    /// 获取当前管理器中所有下载任务的唯一标识符数组。
    ///
    /// 可用于批量操作（如批量开始、暂停、恢复等）。
    ///
    /// - Returns: `UUID` 数组，包含所有注册任务的ID。
    ///
    /// ### 使用示例:
    /// ```swift
    /// let allTaskIDs = await manager.allTaskIDs()
    /// await manager.batchPause(ids: allTaskIDs) // 暂停所有任务
    /// ```
    public func allTaskIDs() -> [UUID] {
        return Array(tasks.keys)
    }
    
    /// 开始所有已注册但未完成的任务。
    ///
    /// 此方法会尝试启动所有处于 `.idle` 或 `.paused` 状态的任务。
    ///
    /// ### 使用示例:
    /// ```swift
    /// await manager.startAllTasks()
    /// ```
    public func startAllTasks(){
        self.batchStart(ids: allTaskIDs())
    }
    
    /// 暂停所有正在下载或等待中的任务。
    ///
    /// 此方法会尝试暂停所有处于 `.downloading` 或 `.idle` 状态的任务。
    ///
    /// ### 使用示例:
    /// ```swift
    /// await manager.stopAllTasks()
    /// ```
    public func stopAllTasks(){
        self.batchPause(ids: allTaskIDs())
    }

    // MARK: - 并发队列调度
    /// 检查并启动等待队列中的下一个任务。
    ///
    /// 当有下载槽位空闲时，此方法会从 `pendingQueue` 中取出任务并启动。
    private func checkAndStartNext() {
        while currentDownloadingCount < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            // 确保任务状态是 idle 才能被启动
            if let task = tasks[nextId], task.state == .idle {
                startTaskInternal(id: nextId)
            } else { // 如果任务状态不是 idle (例如已被取消或已完成)，则跳过
                continue
            }
        }
        updateBatchStateIfNeeded()
    }

    // MARK: - 下载事件回调
    /// 处理单个任务的进度更新。
    ///
    /// 此方法由Alamofire的 `downloadProgress` 回调触发，用于更新任务进度并通知委托。
    ///
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - progress: 当前进度值，范围从0.0到1.0。
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        // 只有当任务处于 downloading 状态时才更新状态，避免覆盖 paused 等状态
        if currentTask.state == .downloading {
            tasks[id] = currentTask
            notifyProgress(currentTask)
            notifyOverallProgress()
            updateBatchStateIfNeeded()
        }
    }

    /// 处理单个任务的完成或失败。
    ///
    /// 此方法由Alamofire的 `responseData` 回调触发，用于处理下载结果并通知委托。
    ///
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - response: Alamofire的下载响应对象，包含下载结果和可能的错误。
    private func onComplete(id: UUID, response: AFDownloadResponse<Data>) async {
        guard var currentTask = tasks[id] else { return }
        
        // 无论成功或失败，下载槽位都已释放
        currentDownloadingCount = max(0, currentDownloadingCount - 1)
        defer { Task { await self.checkAndStartNext() } } // 确保释放槽位后检查下一个任务

        if let error = response.error {
            currentTask.state = .failed
            tasks[id] = currentTask
            notifyFailure(currentTask) // 通知任务失败
            print("Download task \(id) failed: \(error.localizedDescription)")
        } else {
            currentTask.progress = 1.0
            currentTask.state = .completed
            tasks[id] = currentTask
            notifyCompletion(currentTask) // 通知任务完成
            print("Download task \(id) completed.")

            // 如果需要保存到相册
            if currentTask.saveToAlbum {
                #if os(iOS) || os(watchOS) || os(macOS)
                // 确保在支持的系统版本上才调用 PHPhotoLibrary 相关方法
                if #available(iOS 14, watchOS 7, macOS 11, *) {
                    await Self.saveToAlbumIfNeeded(fileURL: currentTask.destination)
                }
                #endif
            }
        }
        notifyOverallProgress()
        updateBatchStateIfNeeded()
    }

    /// 更新内部任务的状态。
    ///
    /// 此方法用于直接修改任务的内部状态，并触发相应的进度通知。
    ///
    /// - Parameters:
    ///   - id: 任务的唯一标识符。
    ///   - state: 要设置的新状态。
    private func updateTaskState(id: UUID, state: DownloadState) {
        guard var task = tasks[id] else { return }
        task.state = state
        tasks[id] = task
        notifyProgress(task) // 状态改变也应通知进度更新
    }
    
    // MARK: - 代理回调（保证主线程回调，防止 SwiftUI 线程警告）
    /// 通知所有委托对象单个任务的进度更新。
    ///
    /// 此方法会将回调调度到主线程，以确保UI更新安全。
    ///
    /// - Parameter task: 包含最新进度信息的内部任务对象。
    private func notifyProgress(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            response: task.response,
            cryoResult: task.cryoResult
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadProgressDidUpdate(task: info)
            }
        }
    }

    /// 通知所有委托对象单个任务的完成。
    ///
    /// 此方法会将回调调度到主线程，以确保UI更新安全。
    ///
    /// - Parameter task: 包含完成任务信息的内部任务对象。
    private func notifyCompletion(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            response: task.response,
            cryoResult: task.cryoResult
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadDidComplete(task: info)
            }
        }
    }

    /// 通知所有委托对象单个任务的失败。
    ///
    /// 此方法会将回调调度到主线程，以确保UI更新安全。
    ///
    /// - Parameter task: 包含失败任务信息的内部任务对象。
    private func notifyFailure(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            response: task.response,
            cryoResult: task.cryoResult
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadDidFail(task: info)
            }
        }
    }

    // MARK: - 整体进度与整体完成
    /// 计算所有有效（未取消）任务的整体平均进度。
    ///
    /// - Returns: 整体平均进度，范围从0.0到1.0。如果没有有效任务，则返回1.0。
    private func calcOverallProgress() -> Double {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        guard !validTasks.isEmpty else { return 1.0 }
        let sum = validTasks.map { min($0.progress, 1.0) }.reduce(0, +)
        return sum / Double(validTasks.count)
    }

    /// 判断所有有效（未取消）任务是否都已完成。
    ///
    /// - Returns: 如果所有有效任务都已完成，则返回 `true`；否则返回 `false`。
    private func isOverallCompleted() -> Bool {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        return !validTasks.isEmpty && validTasks.allSatisfy { $0.state == .completed }
    }
    
    /// 计算当前批量下载的整体状态。
    ///
    /// - Returns: 当前的 `DownloadBatchState`。
    private func calcBatchState() -> DownloadBatchState {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        if validTasks.isEmpty { return .idle }
        
        let completedCount = validTasks.filter { $0.state == .completed }.count
        let pausedCount = validTasks.filter { $0.state == .paused }.count
        let downloadingCount = validTasks.filter { $0.state == .downloading }.count
        let idleCount = validTasks.filter { $0.state == .idle }.count

        if completedCount == validTasks.count { return .completed }
        if pausedCount == validTasks.count { return .paused }
        if downloadingCount > 0 { return .downloading }
        if idleCount > 0 && downloadingCount == 0 && pausedCount == 0 { return .idle }
        if pausedCount > 0 && downloadingCount == 0 { return .paused } // 混合状态，但没有下载中的，视为暂停
        
        return .idle // 默认或混合状态
    }

    /// 检查并通知批量下载状态变更。
    ///
    /// 此方法会在批量状态发生变化时通知所有委托对象。
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
    ///
    /// 此方法会将回调调度到主线程，以确保UI更新安全。
    private func notifyOverallProgress() {
        let progress = calcOverallProgress()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadOverallProgressDidUpdate(progress: progress)
            }
        }
        
        // 只有当所有任务都已完成且尚未触发过整体完成回调时才触发
        if isOverallCompleted(), !overallCompletedCalled {
            overallCompletedCalled = true
            for delegate in delegates.allObjects {
                Task { @MainActor in
                    (delegate as? DownloadManagerDelegate)?.downloadOverallDidComplete()
                }
            }
        } else if !isOverallCompleted() && overallCompletedCalled { // 如果不再是整体完成状态，重置标记
            overallCompletedCalled = false
        }
    }

    // MARK: - 文件管理辅助
    /// 获取默认的下载文件夹URL。
    ///
    /// 默认路径为 `Documents/Downloads`。
    ///
    /// - Returns: 默认下载文件夹的 `URL`。
    private static func defaultDownloadFolder() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsFolder = documentsPath.appendingPathComponent("Downloads")
        // 确保文件夹存在
        if !FileManager.default.fileExists(atPath: downloadsFolder.path) {
            try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true, attributes: nil)
        }
        return downloadsFolder
    }

    /// 将文件保存到相册（仅限iOS/watchOS/macOS）。
    ///
    /// 此方法会检查文件类型（图片或视频）并尝试保存到系统相册。
    ///
    /// - Parameter fileURL: 要保存的文件的本地URL。
    private static func saveToAlbumIfNeeded(fileURL: URL) async {
        #if os(iOS) || os(watchOS) || os(macOS)
        let fileExtension = fileURL.pathExtension.lowercased()
        let isImage = ["jpg", "jpeg", "png", "gif", "heic"].contains(fileExtension)
        let isVideo = ["mp4", "mov", "m4v"].contains(fileExtension)

        guard isImage || isVideo else { return }

        // 确保在支持的系统版本上才调用 PHPhotoLibrary 相关方法
        if #available(iOS 14, watchOS 7, macOS 11, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            switch status {
            case .authorized:
                performSaveToAlbum(fileURL: fileURL, isVideo: isVideo)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    if newStatus == .authorized {
                        performSaveToAlbum(fileURL: fileURL, isVideo: isVideo)
                    }
                }
            case .restricted, .denied:
                print("Photo Library access denied or restricted.")
            case .limited:
                print("Photo Library access limited.")
            @unknown default:
                print("Unknown Photo Library authorization status.")
            }
        } else {
            // 对于不支持的版本，可以打印日志或采取其他兼容性措施
            print("PHPhotoLibrary methods are not available on this OS version.")
        }
        #endif
    }

    #if os(iOS) || os(watchOS) || os(macOS)
    private static func performSaveToAlbum(fileURL: URL, isVideo: Bool) {
        PHPhotoLibrary.shared().performChanges {
            if isVideo {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }
        } completionHandler: { success, error in
            if success {
                print("File saved to album successfully.")
            } else if let error = error {
                print("Error saving file to album: \(error.localizedDescription)")
            }
        }
    }
    #endif
}


