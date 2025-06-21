import Foundation
import Alamofire

/// `DownloadItem` 线程安全下载项，封装单个文件下载的所有状态与信息。
///
/// 该 Actor 用于在批量或并发下载场景下，安全管理每个文件的下载进度、文件名、保存路径、是否保存到相册等属性。
///
/// ### 使用示例
/// ```swift
/// let item = DownloadItem(downloadURL: "https://example.com/file.zip", fileName: "file.zip")
/// Task {
///     print(await item.getFileName()) // 获取文件名
///     await item.setProgress(0.7)     // 更新进度
///     print(await item.getProgress()) // 当前进度
/// }
/// ```
///
/// - Note:
///   - Actor 保证并发场景下的数据安全。
///   - 实现了 `Identifiable` 和 `Equatable`，可用作 SwiftUI 列表绑定。
///   - 支持自定义文件名、保存路径、是否保存到相册标记。
///
/// - SeeAlso: ``BatchDownloadManager``, ``DownloadModel``
@available(iOS 13, macOS 10.15, *)
public actor DownloadItem: Identifiable, Equatable, @unchecked Sendable {
    /// 唯一标识符
    public let id = UUID().uuidString

    private var _downloadURL: String = ""
    private var _fileName: String = ""
    private var _filePath: String = ""
    private var _progress: Double = 0.0
    private var _isSaveToAlbum: Bool = false

    /// 判断两个 DownloadItem 是否相等（通过 id 比较）
    public static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id
    }

    /// 初始化
    /// - Parameters:
    ///   - downloadURL: 下载链接
    ///   - fileName: 文件名（可选，不填则自动从 URL 提取）
    ///   - filePath: 本地保存路径（可选）
    ///   - isSaveToAlbum: 是否保存到相册（可选）
    public init(downloadURL: String,
                fileName: String? = nil,
                filePath: String? = nil,
                isSaveToAlbum: Bool = false) {
        self._downloadURL = downloadURL
        self._fileName = fileName ?? (downloadURL as NSString).lastPathComponent
        self._filePath = filePath ?? ""
        self._isSaveToAlbum = isSaveToAlbum
    }

    /// 空初始化（用于后续 set）
    public init() {}

    /// 设置下载进度
    /// - Parameter value: 进度（0.0~1.0）
    public func setProgress(_ value: Double) { _progress = value }
    /// 获取下载进度
    public func getProgress() -> Double { _progress }
    /// 获取文件名
    public func getFileName() -> String { _fileName }
    /// 获取文件本地保存路径
    public func getFilePath() -> String { _filePath }
    /// 设置文件保存路径
    public func setFilePath(_ path: String) { _filePath = path }
    /// 获取下载链接
    public func getDownloadURL() -> String { _downloadURL }
    /// 是否保存到相册
    public func isSaveToAlbum() -> Bool { _isSaveToAlbum }
    /// 获取下载链接的 URL 对象
    public func fileURL() -> URL? { URL(string: _downloadURL) }
}
