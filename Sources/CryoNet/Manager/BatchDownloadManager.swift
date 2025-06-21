import Foundation
import Alamofire

#if os(iOS)
import UIKit
import Photos
#elseif os(macOS)
import AppKit
#endif

@available(iOS 13, macOS 10.15, *)
public class BatchDownloadManager {
    public static let shared = BatchDownloadManager()
    private var downloadTasks: [String: DownloadRequest] = [:]
    private let maxConcurrent: Int

    public init(maxConcurrent: Int = 4) {
        self.maxConcurrent = maxConcurrent
    }

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

    public func pauseDownload(item: DownloadItem) {
        let id = item.id
        downloadTasks[id]?.suspend()
    }

    public func resumeDownload(item: DownloadItem) {
        let id = item.id
        downloadTasks[id]?.resume()
    }

    public func cancelDownload(item: DownloadItem) {
        let id = item.id
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)
    }

    public func cancelAll() {
        for (_, task) in downloadTasks { task.cancel() }
        downloadTasks.removeAll()
    }

    // MARK: 单项下载
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

    // MARK: - 辅助
    public static func defaultDirectory() -> String {
        #if os(iOS)
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        #elseif os(macOS)
        return NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        #endif
    }

    public static func isImageOrVideo(fileURL: URL) -> Bool {
        let pathExt = fileURL.pathExtension.lowercased()
        let imageTypes = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff"]
        let videoTypes = ["mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v"]
        return imageTypes.contains(pathExt) || videoTypes.contains(pathExt)
    }

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
