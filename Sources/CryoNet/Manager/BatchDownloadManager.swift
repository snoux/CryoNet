
import Foundation
import Alamofire

#if os(iOS)
import UIKit
import Photos
#elseif os(macOS)
import AppKit
#endif

/// `BatchDownloadManager` 定义了 CryoNet 框架中的批量下载管理器，
/// 提供多文件并发下载、进度跟踪、暂停、恢复与保存到相册等能力。
///
/// 此类用于统一调度和管理批量下载任务，控制最大并发数，对每个下载项进行进度、暂停、恢复、
/// 取消等操作，并支持图片/视频自动保存至系统相册（iOS）或在 Finder 中展示（macOS）。
///
/// ### 使用示例
/// 以下示例展示了如何批量下载多个文件并监听每个文件的进度和完成状态：
/// ```swift
/// // 构建下载项数组
/// let items = [
///     DownloadItem(downloadURL: "https://example.com/image1.png"),
///     DownloadItem(downloadURL: "https://example.com/image2.jpg")
/// ]
/// let model = DownloadModel(items: items, defaultSaveDirectory: nil, isSaveToAlbum: false)
///
/// // 启动批量下载
/// BatchDownloadManager.shared.startBatchDownload(
///     model: model,
///     progress: { item, progress in
///         Task { print("进度: \(progress), 文件: \(await item.getFileName())") }
///     },
///     completion: { item, result in
///         switch result {
///         case .success(let url):
///             print("下载完成: \(url)")
///         case .failure(let error):
///             print("下载失败: \(error.localizedDescription)")
///         }
///     }
/// )
/// ```
///
/// - Note:
///   - 支持 iOS/macOS 平台，iOS 可保存图片/视频到相册，macOS 可自动打开 Finder 展示下载文件。
///   - 支持暂停、恢复、取消单个下载项或全部下载任务。
///   - 并发下载数由 `maxConcurrent` 控制（默认4），建议结合业务场景合理设定。
///   - 单项下载的进度与完成回调均以 DownloadItem 作为参数，便于绑定界面与业务逻辑。
///
/// - SeeAlso: ``DownloadModel``, ``DownloadItem``, ``CryoNet/batchDownload(_:progress:completion:)``
@available(iOS 13, macOS 10.15, *)
public class BatchDownloadManager {
    /// 批量下载单例实例，推荐统一使用
    public static let shared = BatchDownloadManager()
    /// 下载任务映射表，key为item.id，value为Alamofire DownloadRequest
    private var downloadTasks: [String: DownloadRequest] = [:]
    /// 最大并发下载数
    private let maxConcurrent: Int

    /// 初始化一个新的 `BatchDownloadManager` 实例
    ///
    /// - Parameter maxConcurrent: 最大同时进行的下载任务数量，默认为4
    public init(maxConcurrent: Int = 4) {
        self.maxConcurrent = maxConcurrent
    }

    /// 启动批量下载任务
    ///
    /// - Parameters:
    ///   - model: 下载模型，包含所有待下载项及全局保存配置
    ///   - progress: 单项下载进度回调 (DownloadItem, 进度 0~1)
    ///   - completion: 单项下载完成回调 (DownloadItem, 结果)
    ///
    /// ### 使用示例
    /// ```swift
    /// let model = DownloadModel(items: [...])
    /// BatchDownloadManager.shared.startBatchDownload(
    ///     model: model,
    ///     progress: { item, prog in ... },
    ///     completion: { item, result in ... }
    /// )
    /// ```
    public func startBatchDownload(
        model: DownloadModel,
        progress: ((DownloadItem, Double) -> Void)? = nil,
        completion: ((DownloadItem, Result<URL, Error>) -> Void)? = nil
    ) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                var index = 0
                let items = model.items

                func addNext() {
                    guard index < items.count else { return }
                    let item = items[index]
                    group.addTask {
                        await self.downloadSingleItem(
                            item: item,
                            globalSaveDir: model.defaultSaveDirectory,
                            globalSaveToAlbum: model.isSaveToAlbum,
                            progress: progress,
                            completion: completion
                        )
                    }
                    running += 1
                    index += 1
                }

                // 启动最大并发数
                while running < maxConcurrent && index < items.count {
                    addNext()
                }

                for await _ in group {
                    running -= 1
                    addNext()
                }
            }
        }
    }

    /// 暂停指定下载项
    ///
    /// - Parameter item: 要暂停的下载项
    ///
    /// ### 使用示例
    /// ```swift
    /// BatchDownloadManager.shared.pauseDownload(item: downloadItem)
    /// ```
    public func pauseDownload(item: DownloadItem) {
        let id = item.id
        downloadTasks[id]?.suspend()
    }

    /// 恢复指定下载项
    ///
    /// - Parameter item: 要恢复的下载项
    ///
    /// ### 使用示例
    /// ```swift
    /// BatchDownloadManager.shared.resumeDownload(item: downloadItem)
    /// ```
    public func resumeDownload(item: DownloadItem) {
        let id = item.id
        downloadTasks[id]?.resume()
    }

    /// 取消指定下载项
    ///
    /// - Parameter item: 要取消的下载项
    ///
    /// ### 使用示例
    /// ```swift
    /// BatchDownloadManager.shared.cancelDownload(item: downloadItem)
    /// ```
    public func cancelDownload(item: DownloadItem) {
        let id = item.id
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)
    }

    /// 取消所有下载任务
    ///
    /// ### 使用示例
    /// ```swift
    /// BatchDownloadManager.shared.cancelAll()
    /// ```
    public func cancelAll() {
        for (_, task) in downloadTasks { task.cancel() }
        downloadTasks.removeAll()
    }

    // MARK: - 单项下载实现

    /// 内部方法：负责单个下载项的具体下载与保存流程
    ///
    /// - Parameters:
    ///   - item: 单个下载项
    ///   - globalSaveDir: 全局保存目录
    ///   - globalSaveToAlbum: 是否全局保存到相册
    ///   - progress: 单项进度回调
    ///   - completion: 单项完成回调
    private func downloadSingleItem(
        item: DownloadItem,
        globalSaveDir: String?,
        globalSaveToAlbum: Bool,
        progress: ((DownloadItem, Double) -> Void)?,
        completion: ((DownloadItem, Result<URL, Error>) -> Void)?
    ) async {
        let downloadURL = await item.getDownloadURL()
        guard let url = URL(string: downloadURL) else {
            completion?(item, .failure(NSError(domain: "InvalidURL", code: -1)))
            return
        }
        let fileName = await item.getFileName()
        let saveToAlbum = await item.isSaveToAlbum() || globalSaveToAlbum
        let saveDir = await item.getFilePath().isEmpty ? (globalSaveDir ?? BatchDownloadManager.defaultDirectory()) : item.getFilePath()
        let saveURL = URL(fileURLWithPath: saveDir).appendingPathComponent(fileName)
        await item.setFilePath(saveURL.path)

        let request = AF.download(url, to: { _, _ in
            (saveURL, [.removePreviousFile, .createIntermediateDirectories])
        })
        .downloadProgress { prog in
            Task { await item.setProgress(prog.fractionCompleted) }
            progress?(item, prog.fractionCompleted)
        }
        .validate()
        .response { response in
            if let error = response.error {
                completion?(item, .failure(error))
            } else if let fileURL = response.fileURL {
                if saveToAlbum, BatchDownloadManager.isImageOrVideo(fileURL: fileURL) {
                    BatchDownloadManager.saveFileToAlbum(fileURL: fileURL) { result in
                        completion?(item, result.map { fileURL })
                    }
                } else {
                    completion?(item, .success(fileURL))
                }
            }
        }

        let id = item.id
        downloadTasks[id] = request
    }

    // MARK: - 辅助方法

    /// 获取平台默认保存目录（iOS: Documents，macOS: Downloads）
    ///
    /// - Returns: 路径字符串
    public static func defaultDirectory() -> String {
        #if os(iOS)
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        #elseif os(macOS)
        return NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        #endif
    }

    /// 判断文件是否为图片或视频类型（用于自动保存到相册）
    ///
    /// - Parameter fileURL: 文件 URL
    /// - Returns: 是否为图片或视频
    public static func isImageOrVideo(fileURL: URL) -> Bool {
        let pathExt = fileURL.pathExtension.lowercased()
        let imageTypes = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff"]
        let videoTypes = ["mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v"]
        return imageTypes.contains(pathExt) || videoTypes.contains(pathExt)
    }

    /// 保存文件到系统相册（iOS: 相册，macOS: Finder/Photos）
    ///
    /// - Parameters:
    ///   - fileURL: 文件 URL
    ///   - completion: 结果回调
    ///
    /// - Note:
    ///   - iOS会自动请求相册权限，图片/视频分别采用不同API保存。
    ///   - macOS会尝试用“照片”应用打开，若失败则直接在 Finder 选中文件。
    public static func saveFileToAlbum(fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        #if os(iOS)
        PHPhotoLibrary.requestAuthorization { status in
            let authorized: Bool
            if #available(iOS 14, *) {
                authorized = status == .authorized || status == .limited
            } else {
                authorized = status == .authorized
            }
            guard authorized else {
                completion(.failure(NSError(domain: "NoAlbumPermission", code: -1)))
                return
            }
            let ext = fileURL.pathExtension.lowercased()
            let imageTypes = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff"]
            if imageTypes.contains(ext), let image = UIImage(contentsOfFile: fileURL.path) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                completion(.success(()))
            } else {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }) { success, error in
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(error ?? NSError(domain: "AlbumSaveFailed", code: -2)))
                    }
                }
            }
        }
        #elseif os(macOS)
        let ext = fileURL.pathExtension.lowercased()
        let imageTypes = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff"]
        let workspace = NSWorkspace.shared
        if imageTypes.contains(ext) {
            let photosBundleId = "com.apple.Photos"
            if let photosAppURL = workspace.urlForApplication(withBundleIdentifier: photosBundleId) {
                if #available(macOS 11.0, *) {
                    workspace.open([fileURL], withApplicationAt: photosAppURL, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                        if let error = error {
                            workspace.activateFileViewerSelecting([fileURL])
                            completion(.failure(error))
                        } else {
                            completion(.success(()))
                        }
                    }
                } else {
                    workspace.activateFileViewerSelecting([fileURL])
                    completion(.success(()))
                }
            } else {
                workspace.activateFileViewerSelecting([fileURL])
                completion(.success(()))
            }
        } else {
            workspace.activateFileViewerSelecting([fileURL])
            completion(.success(()))
        }
        #endif
    }
}
