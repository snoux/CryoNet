import Foundation
import Alamofire
/**
 下载结果 DownloadResult
 包含下载结果和关联的下载项
 */
@available(iOS 13 ,*)
public class DownloadResult {
    /// 结果信息（URL 或错误）
    public var result: Result<URL?, AFError>
    
    /// Result 对应的 downLoadItem
    public let downLoadItem: DownloadItem
    
    /**
     初始化方法
     - Parameters:
        - result: 下载结果
        - downLoadItem: 关联的下载项
     */
    init(result: Result<URL?, AFError>, downLoadItem: DownloadItem) {
        self.result = result
        self.downLoadItem = downLoadItem
    }
}
