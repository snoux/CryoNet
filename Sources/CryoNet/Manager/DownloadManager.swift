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
/// 下载任务公开信息（供 UI 使用）
public struct DownloadTaskInfo: Identifiable {
    public let id: UUID
    public let url: URL
    public var progress: Double
    public var state: DownloadState
    public var destination: URL
    public var error: Error?
}

// MARK: - 下载任务事件委托
public protocol DownloadManagerDelegate: AnyObject {
    /// 下载进度更新
    func downloadProgressDidUpdate(task: DownloadTaskInfo)
    /// 下载完成
    func downloadDidComplete(task: DownloadTaskInfo)
    /// 下载失败
    func downloadDidFail(task: DownloadTaskInfo)
}

// MARK: - 内部下载任务结构体
private struct DownloadTask {
    let id: UUID
    let url: URL
    let destination: URL
    let saveToAlbum: Bool
    var progress: Double
    var state: DownloadState
    var error: Error?
    var request: DownloadRequest?
}

// MARK: - 下载管理器
/// 支持批量/单个下载、并发控制、进度回调
public actor DownloadManager {
    public let identifier: String
    private var tasks: [UUID: DownloadTask] = [:]
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private var maxConcurrentDownloads: Int
    private var currentDownloadingCount: Int = 0
    private var pendingQueue: [UUID] = []
    private let fileManager = FileManager.default

    // MARK: 初始化
    /// 初始化 DownloadManager
    /// - Parameters:
    ///   - identifier: 队列标识
    ///   - maxConcurrentDownloads: 最大并发数（默认3）
    public init(identifier: String = UUID().uuidString, maxConcurrentDownloads: Int = 3) {
        self.identifier = identifier
        self.maxConcurrentDownloads = maxConcurrentDownloads
    }

    // MARK: 并发设置
    /// 设置最大并发下载数
    public func setMaxConcurrentDownloads(_ count: Int) {
        self.maxConcurrentDownloads = max(1, count)
        Task { self.checkAndStartNext() }
    }

    // MARK: 委托管理
    public func addDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.add(delegate)
    }
    public func removeDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: 批量下载
    /// 批量下载（基础地址+文件名数组）
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

    // MARK: 单任务下载
    /// 启动单个下载任务
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
            error: nil,
            request: nil
        )
        tasks[id] = task
        enqueueOrStartTask(id: id)
        return id
    }

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

    /// 手动启动任务（恢复）
    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
    }

    /// 实际发起下载
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

        let request = AF.download(currentTask.url, to: destination)
            .downloadProgress { [weak self] progress in
                // 用 actor 保证线程安全，不直接访问 self
                Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
            }
            .responseData { [weak self] response in
                Task { await self?.onComplete(id: id, response: response) }
            }

        currentTask.request = request
        tasks[id] = currentTask
        notifyProgress(currentTask)
    }

    // MARK: 任务控制
    public func pauseTask(id: UUID) {
        guard var task = tasks[id], let request = task.request else { return }
        request.suspend()
        if task.state == .downloading {
            currentDownloadingCount = max(0, currentDownloadingCount - 1)
            Task { self.checkAndStartNext() }
        }
        task.state = .paused
        tasks[id] = task
        notifyProgress(task)
    }

    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else { return }
        if task.state == .paused {
            enqueueOrStartTask(id: id)
        }
    }

    public func cancelTask(id: UUID) {
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
            updateTaskState(id: id, state: .cancelled)
            notifyProgress(tasks[id]!)
            return
        }
        guard var task = tasks[id], let request = task.request else { return }
        request.cancel()
        if task.state == .downloading {
            currentDownloadingCount = max(0, currentDownloadingCount - 1)
            Task { self.checkAndStartNext() }
        }
        task.state = .cancelled
        tasks[id] = task
        notifyProgress(task)
    }

    public func removeTask(id: UUID) {
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
    }

    // MARK: 状态查询
    public func getTaskInfo(id: UUID) -> DownloadTaskInfo? {
        guard let task = tasks[id] else { return nil }
        return DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            error: task.error
        )
    }

    public func allTaskInfos() -> [DownloadTaskInfo] {
        return tasks.values.map {
            DownloadTaskInfo(
                id: $0.id,
                url: $0.url,
                progress: $0.progress,
                state: $0.state,
                destination: $0.destination,
                error: $0.error
            )
        }
    }

    // MARK: 批量控制
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
    }
    public func batchResume(ids: [UUID]) {
        for id in ids { resumeTask(id: id) }
    }
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
    }

    // MARK: 并发队列调度
    private func checkAndStartNext() {
        while currentDownloadingCount < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            startTaskInternal(id: nextId)
        }
    }

    // MARK: 下载事件回调
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        currentTask.state = .downloading
        tasks[id] = currentTask
        notifyProgress(currentTask)
    }

    private func onComplete(id: UUID, response: AFDownloadResponse<Data>) async {
        guard var currentTask = tasks[id] else { return }
        currentDownloadingCount = max(0, currentDownloadingCount - 1)
        defer { Task { self.checkAndStartNext() } }
        if let error = response.error {
            currentTask.state = .failed
            currentTask.error = error
            tasks[id] = currentTask
            notifyFailure(currentTask)
            return
        }
        currentTask.progress = 1.0
        currentTask.state = .completed
        tasks[id] = currentTask
        notifyCompletion(currentTask)

        if currentTask.saveToAlbum {
            await Self.saveToAlbumIfNeeded(fileURL: currentTask.destination)
        }
    }

    private func updateTaskState(id: UUID, state: DownloadState) {
        guard var task = tasks[id] else { return }
        task.state = state
        tasks[id] = task
    }

    // MARK: 代理回调封装（保证主线程回调，防止SwiftUI警告）
    private func notifyProgress(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            error: task.error
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadProgressDidUpdate(task: info)
            }
        }
    }
    private func notifyCompletion(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            error: task.error
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadDidComplete(task: info)
            }
        }
    }
    private func notifyFailure(_ task: DownloadTask) {
        let info = DownloadTaskInfo(
            id: task.id,
            url: task.url,
            progress: task.progress,
            state: task.state,
            destination: task.destination,
            error: task.error
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? DownloadManagerDelegate)?.downloadDidFail(task: info)
            }
        }
    }

    // MARK: 工具方法
    /// 默认下载目录
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
    static func saveImageToAlbum(fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else { return }
        await MainActor.run {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }
    static func saveVideoToAlbum(fileURL: URL) async {
        await MainActor.run {
            UISaveVideoAtPathToSavedPhotosAlbum(fileURL.path, nil, nil, nil)
        }
    }
    #endif
    
    
//    /// 获取总进度（0~1），参数可选过滤（如排除 cancelled）
//    public func totalProgress(includeCancelled: Bool = false) -> Double {
//        let all = tasks.values
//        let filtered = includeCancelled ? all : all.filter { $0.state != .cancelled }
//        guard !filtered.isEmpty else { return 0 }
//        let sum = filtered.map { min($0.progress, 1.0) }.reduce(0, +)
//        return sum / Double(filtered.count)
//    }
}
