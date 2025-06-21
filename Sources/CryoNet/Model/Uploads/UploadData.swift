import Foundation
import Alamofire

// MARK: - 上传/下载相关结构体

/// `UploadData` 上传文件参数结构体，封装单条上传文件的基本信息和数据来源。
///
/// 支持文件数据来源于本地文件（URL）或内存数据（Data），并指定表单字段名及文件名。
///
/// ### 使用示例
/// ```swift
/// let fileData = Data(...) // 文件的二进制内容
/// let upload1 = UploadData(file: .fileData(fileData), name: "photo", fileName: "avatar.jpg")
/// let fileURL = URL(fileURLWithPath: "/tmp/video.mp4")
/// let upload2 = UploadData(file: .fileURL(fileURL), name: "video")
/// ```
///
/// - Note:
///   - `id` 唯一标识，可用于区分多文件上传。
///   - `fileName` 可选，未指定时部分服务端不要求。
///
/// - SeeAlso: ``CryoNet/upload(_:files:parameters:headers:interceptor:)``
@available(iOS 13 ,*)
public struct UploadData: Identifiable, Equatable {
    /// 判断两个 UploadData 是否相等（通过 id）
    public static func == (lhs: UploadData, rhs: UploadData) -> Bool {
        lhs.id == rhs.id
    }
    /// 唯一标识
    public let id: UUID = UUID()
    /// 要上传的文件数据
    public var file: fileType
    /// 表单字段名（如 "photo"、"file"）
    public var name: String
    /// 文件名（可选）
    public var fileName: String?
    
    /// 文件类型
    public enum fileType {
        /// 本地文件 URL
        case fileURL(URL?)
        /// 内存数据
        case fileData(Data?)
    }
    
    /// 初始化
    /// - Parameters:
    ///   - file: 文件数据类型
    ///   - name: 表单字段名
    ///   - fileName: 文件名（可选）
    public init(file: fileType, name: String, fileName: String? = nil) {
        self.file = file
        self.name = name
        self.fileName = fileName
    }
}
