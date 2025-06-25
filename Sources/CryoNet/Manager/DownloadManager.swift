import Foundation
import Alamofire

#if os(iOS) || os(watchOS)
import Photos
import UIKit
#endif

// MARK: - 下载任务状态
/// 下载任务的状态枚举
public enum DownloadState: String {
    case idle          /// 等待中
    case downloading   /// 正在下载
    case paused        /// 已暂停
    case completed     /// 已完成
    case failed        /// 失败
    case cancelled     /// 已取消
}

// MARK: - 下载任务信息
/// 下载任务公开信息（供 UI 使用、外部获取任务状态与详情）
/// - response: DataRequest?，可用于外部获取 Alamofire 的详细响应
public struct DownloadTaskInfo: Identifiable {
    public let id: UUID                  /// 任务唯一标识
    public let url: URL                  /// 下载资源的URL
    public var progress: Double          /// 当前进度（0~1）
    public var state: DownloadState      /// 当前任务状态
    public var destination: URL          /// 文件保存路径
    public var response: DownloadRequest?    /// 下载请求对象（如需获取详细响应，可在 UI 层监听 response 事件）
}

// MARK: - 下载任务事件委托
/// 下载任务事件回调协议，便于 UI 或业务层监听进度、完成、失败，以及整体下载进度与完成
public protocol DownloadManagerDelegate: AnyObject {
    /// 单任务进度更新
    func downloadProgressDidUpdate(task: DownloadTaskInfo)
    /// 单任务完成
    func downloadDidComplete(task: DownloadTaskInfo)
    /// 单任务失败
    func downloadDidFail(task: DownloadTaskInfo)
    /// 整体下载进度更新（所有未取消任务的平均进度，每次有任务进度变化都会回调）
    func downloadOverallProgressDidUpdate(progress: Double)
    /// 整体下载全部完成（所有未取消任务均为 completed 时回调，只回调一次）
    func downloadOverallDidComplete()
}

// MARK: - 内部下载任务结构体
/// DownloadManager 内部使用的下载任务结构体
private struct DownloadTask {
    let id: UUID                   /// 任务唯一标识
    let url: URL                   /// 下载资源URL
    let destination: URL           /// 目标保存路径
    let saveToAlbum: Bool          /// 下载完成后是否保存到相册（仅图片/视频）
    var progress: Double           /// 当前进度
    var state: DownloadState       /// 状态
    var response: DownloadRequest?     /// 下载请求对象
}

// MARK: - 下载管理器
/// 支持批量/单个下载、并发控制、进度与状态回调的下载管理器
/// 可配合 DownloadManagerPool 支持多队列业务隔离
public actor DownloadManager {
    public let identifier: String                          /// 队列唯一标识，便于业务区分
    private var tasks: [UUID: DownloadTask] = [:]          /// 所有任务（任务ID为Key）
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects() /// 事件委托集合
    private var maxConcurrentDownloads: Int                /// 最大并发下载数
    private var currentDownloadingCount: Int = 0           /// 当前正在下载的任务数
    private var pendingQueue: [UUID] = []                  /// 等待下载的任务队列
    private let fileManager = FileManager.default          /// 文件管理器
    private var overallCompletedCalled: Bool = false       /// 整体完成只回调一次

    private let headers: HTTPHeaders?                      /// 默认HTTP头
    private let interceptor: RequestInterceptor?           /// 可自定义拦截器

    // MARK: - 初始化
    /// 创建 DownloadManager
    /// - Parameters:
    ///   - identifier: 队列唯一标识
    ///   - maxConcurrentDownloads: 最大并发数（默认3）
    ///   - headers: 默认HTTP头
    ///   - interceptor: 自定义Alamofire拦截器
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
    /// 设置最大并发下载数
    /// - Parameter count: 新的并发数（最小1）
    public func setMaxConcurrentDownloads(_ count: Int) {
        self.maxConcurrentDownloads = max(1, count)
        Task { self.checkAndStartNext() }
    }

    // MARK: - 委托管理
    /// 添加下载事件委托对象
    public func addDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.add(delegate)
    }
    /// 移除下载事件委托对象
    public func removeDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 批量下载
    /// 批量下载（基础地址+文件名数组）
    /// - Parameters:
    ///   - baseURL: 基础下载地址（如 https://example.com/files/）
    ///   - fileNames: 文件名数组（如 ["a.mp4","b.jpg"]）
    ///   - destinationFolder: 保存目录（可选，默认为应用的下载目录）
    ///   - saveToAlbum: 下载完成后是否保存到相册
    /// - Returns: 各任务ID组成的数组
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
    /// 启动单个下载任务
    /// - Parameters:
    ///   - url: 下载链接
    ///   - destination: 保存路径（可选，默认应用下载目录）
    ///   - saveToAlbum: 下载完成后是否保存到相册
    /// - Returns: 任务ID
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
        return id
    }

    /// 判断是否可立即启动任务，否则加入等待队列
    private func enqueueOrStartTask(id: UUID) {
        if currentDownloadingCount < maxConcurrentDownloads {
            startTaskInternal(id: id)
        } else {
            if !pendingQueue.contains(id) {
                pendingQueue.append(id)
            }
            updateTaskState(id: id, state: .idle)
        }
    }

    /// 手动启动任务（用于恢复等场景）
    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
    }

    /// 实际发起下载请求（内部并发调度）
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

        /// 创建 Alamofire 下载请求，支持自定义 headers/interceptor
        let request = AF.download(
            currentTask.url,
            method: .get,
            headers: headers,
            interceptor: interceptor,
            to: destination
        )
        .downloadProgress { [weak self] progress in
            // Alamofire 的回调非actor主线程，这里用 Task 切回 actor
            Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
        }
        .responseData { [weak self] response in
            Task { await self?.onComplete(id: id, response: response) }
        }

        currentTask.response = request
        tasks[id] = currentTask
        notifyProgress(currentTask)
        notifyOverallProgress()
    }

    // MARK: - 任务控制
    /// 暂停指定任务
    /// - Parameter id: 任务ID
    public func pauseTask(id: UUID) {
        guard var task = tasks[id], let request = task.response else { return }
        request.suspend()
        if task.state == .downloading {
            currentDownloadingCount = max(0, currentDownloadingCount - 1)
            Task { self.checkAndStartNext() }
        }
        task.state = .paused
        tasks[id] = task
        notifyProgress(task)
        notifyOverallProgress()
    }

    /// 恢复指定任务
    /// - Parameter id: 任务ID
    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else { return }
        if task.state == .paused {
            enqueueOrStartTask(id: id)
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
        guard var task = tasks[id], let request = task.response else { return }
        request.cancel()
        if task.state == .downloading {
            currentDownloadingCount = max(0, currentDownloadingCount - 1)
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

    /// 获取所有任务的信息
    /// - Returns: 任务信息数组
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
    /// 批量暂停
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
    }
    /// 批量恢复
    public func batchResume(ids: [UUID]) {
        for id in ids { resumeTask(id: id) }
    }
    /// 批量取消
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
    }

    // MARK: - 并发队列调度
    /// 检查等待队列并按并发数启动新任务
    private func checkAndStartNext() {
        while currentDownloadingCount < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            startTaskInternal(id: nextId)
        }
    }

    // MARK: - 下载事件回调
    /// 进度事件
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        currentTask.state = .downloading
        tasks[id] = currentTask
        notifyProgress(currentTask)
        notifyOverallProgress()
    }

    /// 完成事件
    private func onComplete(id: UUID, response: AFDownloadResponse<Data>) async {
        guard var currentTask = tasks[id] else { return }
        currentDownloadingCount = max(0, currentDownloadingCount - 1)
        defer { Task { self.checkAndStartNext() } }
        if response.error != nil {
            currentTask.state = .failed
            // 若你需要可自定义 error 信息，用 response.data/request 等
            tasks[id] = currentTask
            notifyFailure(currentTask)
            notifyOverallProgress()
            return
        }
        currentTask.progress = 1.0
        currentTask.state = .completed
        tasks[id] = currentTask
        notifyCompletion(currentTask)
        notifyOverallProgress()
        // 若需要保存到相册（图片/视频）
        if currentTask.saveToAlbum {
            await Self.saveToAlbumIfNeeded(fileURL: currentTask.destination)
        }
    }

    /// 更新任务状态（内部调度用）
    private func updateTaskState(id: UUID, state: DownloadState) {
        guard var task = tasks[id] else { return }
        task.state = state
        tasks[id] = task
    }

    // MARK: - 代理回调（保证主线程回调，防止 SwiftUI 线程警告）
    /// 通知所有委托：进度更新
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
    /// 通知所有委托：下载完成
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
    /// 通知所有委托：下载失败
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
    /// 计算所有未取消任务的平均进度
    private func calcOverallProgress() -> Double {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        guard !validTasks.isEmpty else { return 1.0 }
        let sum = validTasks.map { min($0.progress, 1.0) }.reduce(0, +)
        return sum / Double(validTasks.count)
    }

    /// 检查所有未取消任务是否已全部完成
    private func isOverallCompleted() -> Bool {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        return !validTasks.isEmpty && validTasks.allSatisfy { $0.state == .completed }
    }

    /// 通知整体进度、整体完成
    private func notifyOverallProgress() {
        let progress = calcOverallProgress()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadOverallProgressDidUpdate(progress: progress)
            }
        }
        // 整体完成事件只回调一次
        if isOverallCompleted(), !overallCompletedCalled {
            overallCompletedCalled = true
            for delegate in delegates.allObjects {
                Task { @MainActor in
                    (delegate as? DownloadManagerDelegate)?.downloadOverallDidComplete()
                }
            }
        }
        // 若有新任务加入，重置整体完成flag
        if !isOverallCompleted() {
            overallCompletedCalled = false
        }
    }

    // MARK: - 工具方法
    /// 获取默认下载目录（macOS: ~/Downloads, iOS: ~/Documents）
    public static func defaultDownloadFolder() -> URL {
        #if os(macOS)
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
    }

    /// 下载完成后，若为图片/视频则保存到相册（iOS/watchOS）
    static func saveToAlbumIfNeeded(fileURL: URL) async {
        #if os(iOS) || os(watchOS)
        let ext = fileURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif", "gif"].contains(ext) {
            await saveImageToAlbum(fileURL: fileURL)
        } else if ["mp4", "mov", "avi"].contains(ext) {
            await saveVideoToAlbum(fileURL: fileURL)
        }
        #endif
    }

    #if os(iOS) || os(watchOS)
    /// 保存图片到相册
    static func saveImageToAlbum(fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else { return }
        await MainActor.run {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }
    /// 保存视频到相册
    static func saveVideoToAlbum(fileURL: URL) async {
        await MainActor.run {
            UISaveVideoAtPathToSavedPhotosAlbum(fileURL.path, nil, nil, nil)
        }
    }
    #endif
}
