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
    public var response: DownloadRequest?
    /// 关联的CryoResult对象，可用于链式响应处理。
    public var cryoResult: CryoResult?
}

// MARK: - 下载管理器事件委托
/// 下载管理器的事件委托协议。
///
/// 通过实现本协议，可以订阅下载任务和整体的各种状态变更事件，便于UI或业务层响应。
public protocol DownloadManagerDelegate: AnyObject {
    /// 单任务状态或进度更新
    ///
    /// - Parameter task: 最新的任务信息
    func downloadDidUpdate(task: DownloadTaskInfo)
    /// 所有未完成任务更新时回调
    ///
    /// - Parameter tasks: 当前所有未完成任务
    func downloadManagerDidUpdateActiveTasks(_ tasks: [DownloadTaskInfo])
    /// 已完成任务更新时回调
    ///
    /// - Parameter tasks: 当前所有已完成任务
    func downloadManagerDidUpdateCompletedTasks(_ tasks: [DownloadTaskInfo])
    /// 整体进度或批量状态更新时回调
    ///
    /// - Parameters:
    ///   - overallProgress: 总体进度(0.0-1.0)
    ///   - batchState: 批量下载状态
    func downloadManagerDidUpdateProgress(overallProgress: Double, batchState: DownloadBatchState)
}
public extension DownloadManagerDelegate {
    func downloadDidUpdate(task: DownloadTaskInfo) {}
    func downloadManagerDidUpdateActiveTasks(_ tasks: [DownloadTaskInfo]) {}
    func downloadManagerDidUpdateCompletedTasks(_ tasks: [DownloadTaskInfo]) {}
    func downloadManagerDidUpdateProgress(overallProgress: Double, batchState: DownloadBatchState) {}
}

// MARK: - 内部任务结构体
private struct DownloadTask {
    let id: UUID
    let url: URL
    let destination: URL
    let saveToAlbum: Bool
    var progress: Double
    var state: DownloadState
    var response: DownloadRequest?
    var cryoResult: CryoResult?
}

// MARK: - 下载管理器
/// 下载管理器，支持批量/单个下载、并发控制、进度与状态自动推送。
///
/// - 支持最大并发数设置，自动排队
/// - 支持批量/单个暂停、恢复、取消、移除，并自动删除本地文件
/// - 线程安全，基于 actor 实现
/// - 推荐只监听 downloadDidUpdate / downloadManagerDidUpdateActiveTasks / downloadManagerDidUpdateCompletedTasks / downloadManagerDidUpdateProgress
///
/// - Parameters:
///   - identifier: 队列唯一ID，默认自动生成
///   - maxConcurrentDownloads: 最大并发数，默认3
///   - headers: 全局请求头
///   - interceptor: 业务拦截器
///
/// ### 使用示例：
/// ```swift
/// let manager = DownloadManager()
/// await manager.addDelegate(self)
/// let ids = await manager.addTasks(urls: [url1, url2])
/// await manager.batchStart(ids: ids)
/// ```
///
/// - Note: 推荐仅在主UI层持有DownloadManager实例，避免多实例并发下载同一文件。
/// - SeeAlso: ``DownloadManagerDelegate``, ``DownloadTaskInfo``
public actor DownloadManager {
    public let identifier: String
    private var tasks: [UUID: DownloadTask] = [:]
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private var maxConcurrentDownloads: Int
    private var currentDownloadingCount: Int = 0
    private var pendingQueue: [UUID] = []
    private var lastBatchState: DownloadBatchState = .idle
    private var overallCompletedCalled: Bool = false
    private let headers: HTTPHeaders?
    private let interceptor: RequestInterceptor?
    private let businessInterceptor: RequestInterceptorProtocol?

    /// 创建下载管理器
    ///
    /// - Parameters:
    ///   - identifier: 队列唯一ID，默认自动生成
    ///   - maxConcurrentDownloads: 最大并发数，默认3
    ///   - headers: 全局请求头
    ///   - interceptor: 业务拦截器
    ///
    /// ### 使用示例
    /// ```
    /// let manager = DownloadManager()
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
        self.interceptor = nil
    }

    // MARK: - 事件委托注册

    /// 添加事件委托
    ///
    /// - Parameter delegate: 订阅者
    ///
    /// ### 使用示例
    /// ```
    /// manager.addDelegate(self)
    /// ```
    public func addDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.add(delegate)
    }

    /// 移除事件委托
    ///
    /// - Parameter delegate: 订阅者
    public func removeDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 任务注册与调度

    /// 注册单个任务（初始idle）
    ///
    /// - Parameters:
    ///   - url: 远程文件URL
    ///   - destination: 保存路径(可选)
    ///   - saveToAlbum: 是否自动保存到相册
    /// - Returns: 任务ID
    ///
    /// ### 使用示例
    /// ```
    /// let id = manager.addTask(url: url)
    /// ```
    /// - Note: 只注册任务，不自动开始下载。
    public func addTask(
        url: URL,
        destination: URL? = nil,
        saveToAlbum: Bool = false
    ) -> UUID {
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
    ///   - urls: 文件URL数组
    ///   - destinationFolder: 保存目录(可选)
    ///   - saveToAlbum: 是否自动保存到相册
    /// - Returns: 任务ID数组
    ///
    /// ### 使用示例
    /// ```
    /// let ids = manager.addTasks(urls: [url1, url2])
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

    /// 启动单任务（注册并立即下载）
    ///
    /// - Parameters:
    ///   - url: 远程文件URL
    ///   - destination: 保存路径(可选)
    ///   - saveToAlbum: 是否自动保存到相册
    /// - Returns: 任务ID
    ///
    /// ### 使用示例
    /// ```
    /// let id = await manager.startDownload(from: url)
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

    /// 批量下载（注册并立即下载）
    ///
    /// - Parameters:
    ///   - baseURL: 基础下载URL
    ///   - fileNames: 文件名数组
    ///   - destinationFolder: 保存目录(可选)
    ///   - saveToAlbum: 是否自动保存到相册
    /// - Returns: 任务ID数组
    ///
    /// ### 使用示例
    /// ```
    /// let ids = await manager.batchDownload(baseURL: url, fileNames: ["1.png", "2.png"])
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

    /// 启动所有任务（idle/paused）
    public func startAllTasks() {
        self.batchStart(ids: allTaskIDs())
    }
    /// 暂停所有任务
    public func stopAllTasks() {
        self.batchPause(ids: allTaskIDs())
    }
    /// 批量启动任务
    ///
    /// - Parameter ids: 需要启动的任务ID数组
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
    ///
    /// ### 使用示例
    /// ```
    /// manager.batchCancel(ids: [id1, id2], shouldDeleteFile: true)
    /// ```
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
    ///
    /// ### 使用示例
    /// ```
    /// manager.batchRemove(ids: [id1, id2])
    /// manager.batchRemove(ids: [id1, id2], shouldDeleteFile: false)
    /// ```
    public func batchRemove(ids: [UUID], shouldDeleteFile: Bool = true) {
        for id in ids { removeTask(id: id, shouldDeleteFile: shouldDeleteFile) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 设置最大并发下载数
    ///
    /// - Parameter count: 新的并发数，最小1
    ///
    /// ### 使用示例
    /// ```
    /// manager.setMaxConcurrentDownloads(5)
    /// ```
    public func setMaxConcurrentDownloads(_ count: Int) {
        self.maxConcurrentDownloads = max(1, count)
        Task { await self.checkAndStartNext() }
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

    /// 取消单个任务
    ///
    /// - Parameters:
    ///   - id: 任务ID
    ///   - shouldDeleteFile: 是否删除本地已下载文件（默认不删）
    ///
    /// - Note: 仅取消下载并保留任务记录，无法恢复下载，需重新创建任务。
    /// - SeeAlso: ``removeTask(id:shouldDeleteFile:)``
    ///
    /// ### 使用示例
    /// ```
    /// manager.cancelTask(id: taskId)
    /// manager.cancelTask(id: taskId, shouldDeleteFile: true)
    /// ```
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

    /// 移除任务
    ///
    /// - Parameters:
    ///   - id: 任务ID
    ///   - shouldDeleteFile: 是否删除本地文件（默认删除）
    ///
    /// - Note: 完全删除任务及本地文件，无法恢复。
    /// - SeeAlso: ``cancelTask(id:shouldDeleteFile:)``
    ///
    /// ### 使用示例
    /// ```
    /// manager.removeTask(id: taskId)
    /// manager.removeTask(id: taskId, shouldDeleteFile: false)
    /// ```
    public func removeTask(id: UUID, shouldDeleteFile: Bool = true) {
        // 始终统一通过 cancelTask 做状态和文件处理，避免重复删除
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

    /// 将任务加入队列或立即启动
    ///
    /// - Parameter id: 任务ID
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

    /// 内部启动任务
    ///
    /// - Parameter id: 任务ID
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
        currentTask.cryoResult = nil
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

    /// 下载进度回调
    ///
    /// - Parameters:
    ///   - id: 任务ID
    ///   - progress: 当前进度（0.0~1.0）
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

    /// 下载完成回调
    ///
    /// - Parameters:
    ///   - id: 任务ID
    ///   - response: 下载响应
    private func onComplete(id: UUID, response: AFDownloadResponse<Data>) async {
        guard var currentTask = tasks[id] else { return }
        currentDownloadingCount = max(0, currentDownloadingCount - 1)
        defer { Task { await self.checkAndStartNext() } }

        if let _ = response.error {
            currentTask.state = .failed
            tasks[id] = currentTask
        } else {
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
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        notifySingleTaskUpdate(currentTask)
    }

    /// 推送单任务更新事件
    ///
    /// - Parameter task: 内部任务结构体
    private func notifySingleTaskUpdate(_ task: DownloadTask) {
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
                (delegate as? DownloadManagerDelegate)?.downloadDidUpdate(task: info)
            }
        }
    }

    // MARK: - 事件派发

    /// 推送未完成和已完成任务列表
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

    /// 推送整体进度和批量状态
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
            for delegate in delegates.allObjects {
                Task { @MainActor in
                    // (delegate as? DownloadManagerDelegate)?.downloadOverallDidComplete() // 可扩展整体完成事件
                }
            }
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
    /// - Returns: 所有任务的 DownloadTaskInfo 数组
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

    /// 获取所有任务ID
    ///
    /// - Returns: 所有任务ID数组
    public func allTaskIDs() -> [UUID] {
        return Array(tasks.keys)
    }

    /// 获取单个任务信息
    ///
    /// - Parameter id: 任务ID
    /// - Returns: 任务信息 DownloadTaskInfo 或 nil
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
    /// - Returns: 批量下载状态
    private func calcBatchState() -> DownloadBatchState {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        if validTasks.isEmpty { return .idle }
        if validTasks.allSatisfy({ $0.state == .completed }) { return .completed }
        if validTasks.allSatisfy({ $0.state == .paused }) { return .paused }
        if validTasks.contains(where: { $0.state == .downloading }) { return .downloading }
        return .idle
    }

    // MARK: - 文件管理辅助

    /// 获取默认下载目录
    ///
    /// - Returns: 下载目录URL
    ///
    /// ### 使用示例
    /// ```
    /// let folder = DownloadManager.defaultDownloadFolder()
    /// ```
    private static func defaultDownloadFolder() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsFolder = documentsPath.appendingPathComponent("Downloads")
        if !FileManager.default.fileExists(atPath: downloadsFolder.path) {
            try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true, attributes: nil)
        }
        return downloadsFolder
    }

    /// 下载完成后保存到相册（仅支持图片/视频）
    ///
    /// - Parameter fileURL: 文件本地路径
    ///
    /// - Note: 只会保存图片/视频到相册，非媒体文件不处理。
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
    /// 实际保存到系统相册
    ///
    /// - Parameters:
    ///   - fileURL: 本地文件路径
    ///   - isVideo: 是否为视频
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
