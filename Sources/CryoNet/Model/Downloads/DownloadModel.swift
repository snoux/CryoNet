import Foundation
import Alamofire

@available(iOS 13, *)
public struct DownloadModel {
    /// 下载项数组
    public var items: [DownloadItem]
    /// 全局保存目录（优先级低于每个item的filePath）
    public var defaultSaveDirectory: String?
    /// 是否保存到相册（优先级低于每个item的isSaveToAlbum）
    public var isSaveToAlbum: Bool

    public init(items: [DownloadItem],
                defaultSaveDirectory: String? = nil,
                isSaveToAlbum: Bool = false) {
        self.items = items
        self.defaultSaveDirectory = defaultSaveDirectory
        self.isSaveToAlbum = isSaveToAlbum
    }
}
