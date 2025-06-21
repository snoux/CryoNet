import Foundation
import Alamofire

/// `DownloadModel` 批量下载模型，描述一组待下载的文件及全局下载配置。
///
/// 用于批量下载接口，封装多个 `DownloadItem`，并可设置全局保存目录和是否保存到相册。
///
/// ### 使用示例
/// ```swift
/// let items = [
///     DownloadItem(downloadURL: "https://example.com/file1.mp4"),
///     DownloadItem(downloadURL: "https://example.com/file2.jpg")
/// ]
/// let model = DownloadModel(items: items, defaultSaveDirectory: "/tmp", isSaveToAlbum: true)
/// ```
@available(iOS 13, *)
public struct DownloadModel {
    /// 下载项数组
    public var items: [DownloadItem]
    /// 全局保存目录（优先级低于每个item的filePath）
    public var defaultSaveDirectory: String?
    /// 是否保存到相册（优先级低于每个item的isSaveToAlbum）
    public var isSaveToAlbum: Bool

    /// 初始化
    /// - Parameters:
    ///   - items: 下载项数组
    ///   - defaultSaveDirectory: 全局保存目录（可选）
    ///   - isSaveToAlbum: 是否保存到相册（可选）
    public init(items: [DownloadItem],
                defaultSaveDirectory: String? = nil,
                isSaveToAlbum: Bool = false) {
        self.items = items
        self.defaultSaveDirectory = defaultSaveDirectory
        self.isSaveToAlbum = isSaveToAlbum
    }
}
