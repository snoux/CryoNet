import Foundation
import Alamofire

/// `CryoNet` 批量下载扩展，提供批量文件下载的便捷方法。
///
/// 此扩展为 `CryoNet` 添加了批量下载能力，允许开发者一次性并发下载多个文件，并在每个文件下载过程中获取进度和完成回调。
///
/// ### 使用示例
/// ```swift
/// let items = [
///     DownloadItem(downloadURL: "https://example.com/image1.png"),
///     DownloadItem(downloadURL: "https://example.com/image2.jpg")
/// ]
/// let model = DownloadModel(items: items)
/// cryoNet.batchDownload(model, progress: { item, progress in
///     print("进度: \(progress)")
/// }, completion: { item, result in
///     switch result {
///     case .success(let url): print("完成: \(url)")
///     case .failure(let error): print("失败: \(error)")
///     }
/// })
/// ```
///
/// - Note:
///   - 该方法底层调用 `BatchDownloadManager`，并返回一个空的 `CryoResult` 仅用于链式调用（如 .progress()）。
///   - 进度与完成回调针对每个下载项分别触发。
///
/// - SeeAlso: ``DownloadModel``, ``DownloadItem``, ``BatchDownloadManager``
@available(iOS 13, *)
public extension CryoNet {
    /// 批量下载接口
    /// - Parameters:
    ///   - model: 批量下载模型，包含多个下载项
    ///   - progress: 单个下载项进度回调 (DownloadItem, 进度)
    ///   - completion: 单个下载项完成回调 (DownloadItem, 结果)
    /// - Returns: 支持链式调用的 CryoResult（返回空 DataRequest）
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
