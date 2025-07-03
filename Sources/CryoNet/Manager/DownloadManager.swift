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
/// 下载任务的信息结构体。
///
/// 该结构体用于管理和展示下载任务的关键信息，实现了 `Identifiable` 和 `Equatable` 协议，方便在SwiftUI等框架中使用。
public struct DownloadTask: Identifiable, Equatable {
    public static func == (lhs: DownloadTask, rhs: DownloadTask) -> Bool {
        lhs.id == rhs.id
    }
    /// 任务的唯一标识符。
    public let id: UUID
    /// 下载资源的URL。
    public let url: URL
    /// 文件保存的本地路径。
    public let destination: URL
    /// 下载完成后是否自动保存到相册。
    public let saveToAlbum: Bool
    /// 当前下载进度，范围从0.0到1.0。
    public var progress: Double
    /// 当前任务的状态。
    public var state: DownloadState
    /// 关联的Alamofire下载请求对象。
    public var response: DownloadRequest?
    /// 附加参数（query/body参数，可选）。
    public let parameters: [String: Any]?
    /// 单任务自定义header（可选）。
    public let headers: HTTPHeaders?
}

// MARK: - 下载管理器事件委托
/// 下载管理器的事件委托协议。
///
/// 通过实现本协议，可以订阅下载任务和整体的各种状态变更事件，便于UI或业务层响应。
public protocol DownloadManagerDelegate: AnyObject {
    /// 单任务状态或进度更新
    ///
    /// - Parameter task: 最新的任务信息
    func downloadDidUpdate(task: DownloadTask)
    /// 所有未完成任务更新时回调
    ///
    /// - Parameter tasks: 当前所有未完成任务
    func downloadManagerDidUpdateActiveTasks(_ tasks: [DownloadTask])
    /// 已完成任务更新时回调
    ///
    /// - Parameter tasks: 当前所有已完成任务
    func downloadManagerDidUpdateCompletedTasks(_ tasks: [DownloadTask])
    /// 整体进度或批量状态更新时回调
    ///
    /// - Parameters:
    ///   - overallProgress: 总体进度(0.0-1.0)
    ///   - batchState: 批量下载状态
    func downloadManagerDidUpdateProgress(overallProgress: Double, batchState: DownloadBatchState)
}
public extension DownloadManagerDelegate {
    func downloadDidUpdate(task: DownloadTask) {}
    func downloadManagerDidUpdateActiveTasks(_ tasks: [DownloadTask]) {}
    func downloadManagerDidUpdateCompletedTasks(_ tasks: [DownloadTask]) {}
    func downloadManagerDidUpdateProgress(overallProgress: Double, batchState: DownloadBatchState) {}
}

// MARK: - 下载管理器
/// 下载管理器，支持批量/单个下载、并发控制、进度与状态推送，支持额外参数与自定义header。
///
/// 支持最大并发数设置，自动排队。
/// 支持批量/单个暂停、恢复、取消、移除，并自动删除本地文件。
/// 线程安全，基于 actor 实现。
///
/// - Parameters:
///   - identifier: 队列唯一ID，默认自动生成
///   - baseURL: 下载基础URL（可选），如传入则addTask和批量任务可用相对路径
///   - maxConcurrentDownloads: 最大并发数，默认3
///   - headers: 全局请求头
///   - interceptor: 业务拦截器
///
/// ### 使用示例：
/// ```swift
/// let manager = DownloadManager(baseURL: URL(string: "https://files.example.com"))
/// await manager.addDelegate(self)
/// let id1 = manager.addTask(pathOrURL: "/video/1.mp4", parameters: ["token": "abc"], headers: ["X-Auth": "token"])
/// let ids = manager.batchAddTasks(pathsOrURLs: ["/a.png", "/b.png"], parameters: ["userId":123])
/// await manager.batchStart(ids: ids)
/// ```
///
/// - Note: 推荐仅在主UI层持有DownloadManager实例，避免多实例并发下载同一文件。
/// - SeeAlso: ``DownloadManagerDelegate``
public actor DownloadManager {
    public let identifier: String
    /// 下载基础URL。支持传相对路径给下载任务。
    private let baseURL: URL?
    private var tasks: [UUID: DownloadTask] = [:]
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private var maxConcurrentDownloads: Int
    private var currentDownloadingCount: Int = 0
    private var pendingQueue: [UUID] = []
    private var lastBatchState: DownloadBatchState = .idle
    private var overallCompletedCalled: Bool = false
    private let globalHeaders: HTTPHeaders?
    private let interceptor: RequestInterceptorProtocol?
    private let tokenManager: TokenManagerProtocol?
    
    private var interceptorAdapter: RequestInterceptor {
        InterceptorAdapter(interceptor: interceptor, tokenManager: tokenManager)
    }
    
    /// 创建下载管理器
    ///
    /// - Parameters:
    ///   - identifier: 队列唯一ID，默认自动生成
    ///   - baseURL: 下载基础URL（可选），如传入则addTask和批量任务可用相对路径
    ///   - maxConcurrentDownloads: 最大并发数，默认3
    ///   - headers: 全局请求头
    ///   - interceptor: 业务拦截器
    ///   - tokenManager: Token 管理
    ///
    /// - Note:
    ///   - ``RequestInterceptorProtocol`` 与 ``TokenManagerProtocol`` 需要搭配一起使用.
    ///   - 当``RequestInterceptorProtocol``为请求注入token时,会默认从传入的``TokenManagerProtocol``进行读取
    public init(
        identifier: String = UUID().uuidString,
        baseURL: URL? = nil,
        maxConcurrentDownloads: Int = 3,
        headers: HTTPHeaders? = nil,
        interceptor: RequestInterceptorProtocol? = nil,
        tokenManager: TokenManagerProtocol? = nil
    ) {
        self.identifier = identifier
        self.baseURL = baseURL
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.globalHeaders = headers
        self.interceptor = interceptor
        self.tokenManager = tokenManager
    }
    
    // MARK: - URL拼接辅助
    /// 将相对路径或完整URL转换为绝对URL
    ///
    /// - Parameter pathOrURL: 路径或完整URL
    /// - Returns: 绝对URL
    private func makeAbsoluteURL(from pathOrURL: String) -> URL? {
        if let url = URL(string: pathOrURL), url.scheme != nil {
            return url
        } else if let baseURL, let url = URL(string: pathOrURL, relativeTo: baseURL) {
            return url.absoluteURL
        } else {
            return nil
        }
    }
    
    // MARK: - 事件委托注册
    public func addDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.add(delegate)
    }
    public func removeDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.remove(delegate)
    }
    
    // MARK: - 任务注册与调度
    
    /// 注册单个任务（支持参数/headers）
    ///
    /// - Parameters:
    ///   - pathOrURL: 下载资源的相对路径或完整URL
    ///   - destination: 保存路径(可选)
    ///   - saveToAlbum: 是否自动保存到相册
    ///   - parameters: 附加参数（query/body参数，可选）
    ///   - headers: 单任务自定义header（可选）
    /// - Returns: 任务ID
    public func addTask(
        pathOrURL: String,
        destination: URL? = nil,
        saveToAlbum: Bool = false,
        parameters: [String: Any]? = nil,
        headers: HTTPHeaders? = nil
    ) -> UUID {
        guard let url = makeAbsoluteURL(from: pathOrURL) else {
            fatalError("Invalid download url: \(pathOrURL)")
        }
        let id = UUID()
        let destURL = destination ?? Self.defaultDownloadFolder().appendingPathComponent(url.lastPathComponent)
        let task = DownloadTask(
            id: id,
            url: url,
            destination: destURL,
            saveToAlbum: saveToAlbum,
            progress: 0,
            state: .idle,
            response: nil,
            parameters: parameters,
            headers: headers
        )
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        return id
    }
    
    /// 批量注册任务（支持参数/headers）
    ///
    /// - Parameters:
    ///   - pathsOrURLs: 路径/URL字符串数组
    ///   - destinationFolder: 保存目录(可选)
    ///   - saveToAlbum: 是否自动保存到相册
    ///   - parameters: 附加参数（query/body参数，可选）
    ///   - headers: 单任务自定义header（可选）
    /// - Returns: 任务ID数组
    public func batchAddTasks(
        pathsOrURLs: [String],
        destinationFolder: URL? = nil,
        saveToAlbum: Bool = false,
        parameters: [String: Any]? = nil,
        headers: HTTPHeaders? = nil
    ) -> [UUID] {
        var ids: [UUID] = []
        for pathOrURL in pathsOrURLs {
            let id = addTask(
                pathOrURL: pathOrURL,
                destination: destinationFolder?.appendingPathComponent((URL(string: pathOrURL)?.lastPathComponent) ?? (pathOrURL as NSString).lastPathComponent),
                saveToAlbum: saveToAlbum,
                parameters: parameters,
                headers: headers
            )
            ids.append(id)
        }
        return ids
    }
    
    /// 启动单任务（注册并立即下载），支持参数/headers
    ///
    /// - Parameters:
    ///   - pathOrURL: 下载资源的相对路径或完整URL
    ///   - destination: 保存路径(可选)
    ///   - saveToAlbum: 是否自动保存到相册
    ///   - parameters: 附加参数（query/body参数，可选）
    ///   - headers: 单任务自定义header（可选）
    /// - Returns: 任务ID
    public func startDownload(
        pathOrURL: String,
        destination: URL? = nil,
        saveToAlbum: Bool = false,
        parameters: [String: Any]? = nil,
        headers: HTTPHeaders? = nil
    ) async -> UUID {
        let id = addTask(
            pathOrURL: pathOrURL,
            destination: destination,
            saveToAlbum: saveToAlbum,
            parameters: parameters,
            headers: headers
        )
        enqueueOrStartTask(id: id)
        await updateBatchStateIfNeeded()
        return id
    }
    
    /// 批量注册并立即启动下载任务，支持参数/headers
    ///
    /// - Parameters:
    ///   - pathsOrURLs: 路径/URL字符串数组
    ///   - destinationFolder: 保存目录(可选)
    ///   - saveToAlbum: 是否自动保存到相册
    ///   - parameters: 附加参数（query/body参数，可选）
    ///   - headers: 单任务自定义header（可选）
    /// - Returns: 任务ID数组
    public func batchDownload(
        pathsOrURLs: [String],
        destinationFolder: URL? = nil,
        saveToAlbum: Bool = false,
        parameters: [String: Any]? = nil,
        headers: HTTPHeaders? = nil
    ) async -> [UUID] {
        var ids: [UUID] = []
        for pathOrURL in pathsOrURLs {
            let id = await startDownload(
                pathOrURL: pathOrURL,
                destination: destinationFolder?.appendingPathComponent((URL(string: pathOrURL)?.lastPathComponent) ?? (pathOrURL as NSString).lastPathComponent),
                saveToAlbum: saveToAlbum,
                parameters: parameters,
                headers: headers
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
    
    /// 取消全部任务（可以重新启动/恢复）
    ///
    /// - Parameter shouldDeleteFile: 是否同时删除已下载文件,默认不删除
    public func cancelAllTasks(shouldDeleteFile: Bool = false) {
        let ids = allTaskIDs()
        for id in ids {
            cancelTask(id: id, shouldDeleteFile: shouldDeleteFile)
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }

    /// 删除全部任务（彻底删除，无法恢复/重新启动）
    ///
    /// - Parameter shouldDeleteFile: 是否同时删除已下载文件,默认删除
    public func removeAllTasks(shouldDeleteFile: Bool = true) {
        let ids = allTaskIDs()
        for id in ids {
            // 先取消（移除前确保下载终止&文件可选删除）
            cancelTask(id: id, shouldDeleteFile: shouldDeleteFile)
            tasks[id] = nil
            if let idx = pendingQueue.firstIndex(of: id) {
                pendingQueue.remove(at: idx)
            }
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    
    /// 批量启动任务
    ///
    /// - Parameter ids: 需要启动的任务ID数组
    public func batchStart(ids: [UUID]) {
        for id in ids {
            if let task = tasks[id], task.state == .idle || task.state == .paused || task.state == .cancelled || task.state == .failed{
                enqueueOrStartTask(id: id)
            }
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 批量恢复任务（等价于批量启动）
    ///
    /// - Parameter ids: 需要恢复的任务ID数组
    public func batchResume(ids: [UUID]) {
        batchStart(ids: ids)
    }
    /// 批量暂停任务
    ///
    /// - Parameter ids: 需要暂停的任务ID数组
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 批量取消任务
    ///
    /// - Parameters:
    ///   - ids: 需要取消的任务ID数组
    ///   - shouldDeleteFile: 是否删除本地文件（默认不删除）
    public func batchCancel(ids: [UUID], shouldDeleteFile: Bool = false) {
        for id in ids { cancelTask(id: id, shouldDeleteFile: shouldDeleteFile) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 批量移除任务
    ///
    /// - Parameters:
    ///   - ids: 需要移除的任务ID数组
    ///   - shouldDeleteFile: 是否删除本地文件（默认删除）
    public func batchRemove(ids: [UUID], shouldDeleteFile: Bool = true) {
        for id in ids { removeTask(id: id, shouldDeleteFile: shouldDeleteFile) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 设置最大并发下载数
    ///
    /// - Parameter count: 新的并发数，最小1
    public func setMaxConcurrentDownloads(_ count: Int) {
        self.maxConcurrentDownloads = max(1, count)
        Task { await self.checkAndStartNext() }
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
        guard task.state == .downloading else {
            if task.state != .paused {
                task.state = .paused
                tasks[id] = task
                notifyTaskListUpdate()
                notifyProgressAndBatchState()
            }
            return
        }
        task.response?.suspend()
        currentDownloadingCount = max(0, currentDownloadingCount - 1)
        task.state = .paused
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        Task { await self.checkAndStartNext() }
    }
    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else {return}
        if task.state == .paused || task.state == .idle || task.state == .failed || task.state == .cancelled{
            enqueueOrStartTask(id: id)
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
        }
    }
    public func cancelTask(id: UUID, shouldDeleteFile: Bool = false) {
        guard var task = tasks[id] else { return }
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
            if shouldDeleteFile, FileManager.default.fileExists(atPath: task.destination.path) {
                try? FileManager.default.removeItem(at: task.destination)
            }
            task.state = .cancelled
            tasks[id] = task
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
            return
        }
        if task.state == .downloading {
            task.response?.cancel()
            currentDownloadingCount = max(0, currentDownloadingCount - 1)
            if shouldDeleteFile, FileManager.default.fileExists(atPath: task.destination.path) {
                try? FileManager.default.removeItem(at: task.destination)
            }
            Task { await self.checkAndStartNext() }
        } else if task.state == .completed || task.state == .failed || task.state == .paused || task.state == .idle {
            if shouldDeleteFile, FileManager.default.fileExists(atPath: task.destination.path) {
                try? FileManager.default.removeItem(at: task.destination)
            }
        }
        task.state = .cancelled
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    public func removeTask(id: UUID, shouldDeleteFile: Bool = true) {
        cancelTask(id: id, shouldDeleteFile: shouldDeleteFile)
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    
    // MARK: - 私有：任务调度与下载
    
    /// 将任务加入队列或立即启动。参数/headers会应用到实际请求。
    private func enqueueOrStartTask(id: UUID) {
        guard var task = tasks[id] else { return }
        guard task.state == .idle || task.state == .paused else { return }
        if currentDownloadingCount < maxConcurrentDownloads {
            startTaskInternal(id: id)
        } else {
            if !pendingQueue.contains(id) {
                pendingQueue.append(id)
            }
            task.state = .idle
            tasks[id] = task
        }
    }
    
    /// 内部启动任务，支持参数/headers
    private func startTaskInternal(id: UUID) {
        guard var currentTask = tasks[id] else { return }
        guard currentTask.state == .idle || currentTask.state == .paused else { return }
        currentTask.state = .downloading
        tasks[id] = currentTask
        let destinationURL = currentTask.destination
        let destination: DownloadRequest.Destination = { _, _ in
            (destinationURL, [.createIntermediateDirectories, .removePreviousFile])
        }
        currentDownloadingCount += 1
        
        // 合并全局header和任务header
        var mergedHeaders = globalHeaders ?? HTTPHeaders()
        if let headers = currentTask.headers {
            for h in headers { mergedHeaders.update(name: h.name, value: h.value) }
        }
        
        // 支持参数（自动拼接query，或可扩展为POST/body方式）
        let method: HTTPMethod = .get // 如需post/put可扩展参数
        let urlRequestConvertible: URLConvertible
        if method == .get, let parameters = currentTask.parameters, !parameters.isEmpty {
            var components = URLComponents(url: currentTask.url, resolvingAgainstBaseURL: false)!
            let queryItems: [URLQueryItem] = parameters.map { (k,v) in URLQueryItem(name: k, value: "\(v)") }
            components.queryItems = (components.queryItems ?? []) + queryItems
            urlRequestConvertible = components.url ?? currentTask.url
        } else {
            urlRequestConvertible = currentTask.url
        }
        
        let request = AF.download(
            urlRequestConvertible,
            method: method,
            headers: mergedHeaders,
            interceptor: interceptorAdapter,
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
    }
    
    /// 检查等待队列，尝试启动下一个任务
    private func checkAndStartNext() {
        while currentDownloadingCount < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            if let task = tasks[nextId], task.state == .idle {
                startTaskInternal(id: nextId)
            }
        }
        notifyProgressAndBatchState()
    }
    
    // MARK: - 下载事件处理
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        if currentTask.state == .downloading {
            tasks[id] = currentTask
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            notifySingleTaskUpdate(currentTask)
        }
    }
    private func onComplete(id: UUID, response: AFDownloadResponse<Data>) async {
        guard var currentTask = tasks[id] else { return }
        currentDownloadingCount = max(0, currentDownloadingCount - 1)
        defer { Task { await self.checkAndStartNext() } }
        
        let fileExists = FileManager.default.fileExists(atPath: currentTask.destination.path)
        let httpCode = response.response?.statusCode ?? 0
        let noError = response.error == nil
        
        // 判断下载是否真正成功：无错误、HTTP状态码为200～299、文件已写入本地
        if noError, (200...299).contains(httpCode), fileExists {
            currentTask.progress = 1.0
            currentTask.state = .completed
            tasks[id] = currentTask
            if currentTask.saveToAlbum {
#if os(iOS) || os(watchOS) || os(macOS)
                if #available(iOS 14, watchOS 7, macOS 11, *) {
                    await Self.saveToAlbumIfNeeded(fileURL: currentTask.destination)
                }
#endif
            }
        } else {
            currentTask.state = .failed
            tasks[id] = currentTask
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        notifySingleTaskUpdate(currentTask)
    }
    
    
    /// 推送单任务更新事件
    private func notifySingleTaskUpdate(_ task: DownloadTask) {
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadDidUpdate(task: task)
            }
        }
    }
    
    // MARK: - 事件派发
    private func notifyTaskListUpdate() {
        let all = allTaskInfos()
        let active = all.filter { $0.state != .completed && $0.state != .cancelled }
        let completed = all.filter { $0.state == .completed }
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadManagerDidUpdateActiveTasks(active)
                (delegate as? DownloadManagerDelegate)?.downloadManagerDidUpdateCompletedTasks(completed)
            }
        }
    }
    private func notifyProgressAndBatchState() {
        let progress = calcOverallProgress()
        let batch = calcBatchState()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadManagerDidUpdateProgress(overallProgress: progress, batchState: batch)
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
    public func allTaskInfos() -> [DownloadTask] {
        return Array(tasks.values)
    }
    /// 获取所有任务ID
    public func allTaskIDs() -> [UUID] {
        return Array(tasks.keys)
    }
    /// 获取单个任务信息
    public func getTaskInfo(id: UUID) -> DownloadTask? {
        return tasks[id]
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
    private func calcBatchState() -> DownloadBatchState {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        if validTasks.isEmpty { return .idle }
        if validTasks.allSatisfy({ $0.state == .completed }) { return .completed }
        if validTasks.allSatisfy({ $0.state == .paused }) { return .paused }
        if validTasks.contains(where: { $0.state == .downloading }) { return .downloading }
        return .idle
    }
    
    // MARK: - 文件管理辅助
    private static func defaultDownloadFolder() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsFolder = documentsPath.appendingPathComponent("Downloads")
        if !FileManager.default.fileExists(atPath: downloadsFolder.path) {
            try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true, attributes: nil)
        }
        return downloadsFolder
    }
    
    private static func saveToAlbumIfNeeded(fileURL: URL) async {
#if os(iOS) || os(watchOS) || os(macOS)
        let fileExtension = fileURL.pathExtension.lowercased()
        let isImage = ["jpg", "jpeg", "png", "gif", "heic"].contains(fileExtension)
        let isVideo = ["mp4", "mov", "m4v"].contains(fileExtension)
        guard isImage || isVideo else { return }
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
            default:
                break
            }
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
        } completionHandler: { _, _ in }
    }
#endif
}
