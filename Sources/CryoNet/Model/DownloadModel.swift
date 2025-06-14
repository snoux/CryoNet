import Foundation
import Alamofire
/**
 下载模型 DownloadModel
 用于批量下载，包含保存路径和所有下载项。
 */
@available(iOS 13 ,*)
public struct DownloadModel {
    /// 文件保存目录（可选）
    public var savePath: String?
    /// 下载项数组
    public var models: [DownloadItem]
    
    /// 保存目录的 URL
    public var savePathURL: URL? {
        if savePath != nil {
            return URL(string: savePath!)
        } else {
            return nil
        }
    }

    /**
     初始化方法
     - Parameters:
        - savePath: 保存目录
        - models: 下载项列表
     */
    public init(savePath: String?, models: [DownloadItem]) {
        self.savePath = savePath
        self.models = models
    }
}

