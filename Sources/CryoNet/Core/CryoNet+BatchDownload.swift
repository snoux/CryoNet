import Foundation
import Alamofire

@available(iOS 13, *)
public extension CryoNet {
    /// 批量下载接口
    /// - Parameters:
    ///   - model: DownloadModel
    ///   - progress: 单个下载项进度回调 (DownloadItem, 进度)
    ///   - completion: 单个下载项完成回调 (DownloadItem, 结果)
    /// - Returns: 支持链式的 CryoResult
    @discardableResult
    func batchDownload(
        _ model: DownloadModel,
        progress: ((DownloadItem, Double) -> Void)? = nil,
        completion: ((DownloadItem, Result<URL, Error>) -> Void)? = nil
    ) -> CryoResult {
        BatchDownloadManager.shared.startBatchDownload(
            model: model,
            progress: progress,
            completion: completion
        )
        // CryoResult只是为了链式风格，这里返回一个空的DataRequest
        return CryoResult(request: AF.request("about:blank"))
    }
}
