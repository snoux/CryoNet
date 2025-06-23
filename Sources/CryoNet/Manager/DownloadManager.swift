import Foundation
import Alamofire

#if os(iOS) || os(watchOS)
import Photos
import UIKit
#endif

// MARK: - 下载任务状态
public enum DownloadState: String {
    case idle, downloading, paused, completed, failed, cancelled
}

// MARK: - 下载任务信息
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
    func downloadProgressDidUpdate(task: DownloadTaskInfo)
    func downloadDidComplete(task: DownloadTaskInfo)
    func downloadDidFail(task: DownloadTaskInfo)
}

// MARK: - 内部下载任务
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

// MARK: - 下载管理器（支持基础地址批量下载）
public actor DownloadManager {
    public let identifier: String
    private var tasks: [UUID: DownloadTask] = [:]
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private let fileManager = FileManager.default
    private var maxConcurrentDownloads: Int
    private var currentDownloadingCount: Int = 0
    private var pendingQueue: [UUID] = []

    public init(identifier: String = UUID().uuidString, maxConcurrentDownloads: Int = 3) {
        self.identifier = identifier
        self.maxConcurrentDownloads = maxConcurrentDownloads
    }

    public func setMaxConcurrentDownloads(_ count: Int) {
        self.maxConcurrentDownloads = max(1, count)
        Task { self.checkAndStartNext() }
    }

    public func addDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.add(delegate)
    }
    public func removeDelegate(_ delegate: DownloadManagerDelegate) {
        delegates.remove(delegate)
    }

    /// 批量下载（支持基础地址和多个文件名）
    /// - Parameters:
    ///   - baseURL: 基础地址（如 https://example.com/files/）
    ///   - fileNames: 文件名数组（如 ["a.jpg", "b.jpg"]）
    ///   - destinationFolder: 保存文件夹（可选）
    ///   - saveToAlbum: 是否保存到相册
    /// - Returns: 任务ID数组
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

    /// 单个下载
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

    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
    }

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
                Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
            }
            .responseData { [weak self] response in
                Task { await self?.onComplete(id: id, response: response) }
            }

        currentTask.request = request
        tasks[id] = currentTask
        notifyProgress(currentTask)
    }

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

    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
    }
    public func batchResume(ids: [UUID]) {
        for id in ids { resumeTask(id: id) }
    }
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
    }

    private func checkAndStartNext() {
        while currentDownloadingCount < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            startTaskInternal(id: nextId)
        }
    }

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
            (delegate as? DownloadManagerDelegate)?.downloadProgressDidUpdate(task: info)
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
            (delegate as? DownloadManagerDelegate)?.downloadDidComplete(task: info)
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
            (delegate as? DownloadManagerDelegate)?.downloadDidFail(task: info)
        }
    }

    public static func defaultDownloadFolder() -> URL {
        #if os(macOS)
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
    }

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
}


