import Foundation

/// 全局管理多个 DownloadManager 实例（每个可设置并发数、任务隔离）
public actor DownloadManagerPool {
    public static let shared = DownloadManagerPool()
    private var managers: [String: DownloadManager] = [:]

    /// 获取（或创建）指定 identifier 的 DownloadManager
    /// - Parameters:
    ///   - identifier: 标识符（如 "default"、"image"、"video" 等）
    ///   - maxConcurrentDownloads: 并发数（首次创建时生效，已存在则忽略）
    /// - Returns: DownloadManager 实例
    public func manager(for identifier: String, maxConcurrentDownloads: Int = 3) -> DownloadManager {
        if let exist = managers[identifier] {
            return exist
        }
        let manager = DownloadManager(identifier: identifier, maxConcurrentDownloads: maxConcurrentDownloads)
        managers[identifier] = manager
        return manager
    }
    
    /// 获取指定 identifier 的 DownloadManager（不存在不创建，返回 nil）
    public func getManager(for identifier: String) -> DownloadManager? {
        managers[identifier]
    }

    /// 获取所有已创建的 DownloadManager
    public func allManagers() -> [DownloadManager] {
        Array(managers.values)
    }
    
    /// 移除指定 identifier 的 DownloadManager
    /// - Parameters:
    ///   - identifier: DownloadManager  的  identifier
    ///   - shouldDeleteFile: 是否同时删除已下载的文件,默认不删除
    public func removeManager(
        for identifier: String,
        shouldDeleteFile: Bool = false
    ) {
        Task {
            if let manager = managers[identifier] {
                await manager.removeAllTasks(shouldDeleteFile: shouldDeleteFile)
            }
            managers[identifier] = nil
        }
    }
    
    /// 移除全部 DownloadManager
    /// - Parameter shouldDeleteFile: 是否同时删除已下载的文件,默认不删除
    public func removeAll(shouldDeleteFile: Bool = false) {
        Task {
            for manager in allManagers() {
                await manager.removeAllTasks(shouldDeleteFile: shouldDeleteFile)
            }
            managers.removeAll()
        }
    }
}
