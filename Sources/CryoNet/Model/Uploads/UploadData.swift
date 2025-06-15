import Foundation
import Alamofire

// MARK: - 上传/下载相关结构体

/**
 上传文件参数结构体
 封装上传文件的基本信息和数据来源（本地文件、内存数据）。
 */
@available(iOS 13 ,*)
public struct UploadData: Identifiable, Equatable {
    public static func == (lhs: UploadData, rhs: UploadData) -> Bool {
        lhs.id == rhs.id
    }
    /// 唯一标识
    public let id: UUID = UUID()
    /// 要上传的文件（data 或 fileURL）
    public var file: fileType
    /// 与数据相关联的表单名称
    public var name: String
    /// 与数据相关联的文件名（可选）
    public var fileName: String?
    
    /// 文件类型
    public enum fileType {
        /// 本地文件 URL
        case fileURL(URL?)
        /// 内存数据
        case fileData(Data?)
    }
    
    /**
     初始化方法
     - Parameters:
        - file: 文件数据类型
        - name: 表单名称
        - fileName: 文件名
     */
    public init(file: fileType, name: String, fileName: String? = nil) {
        self.file = file
        self.name = name
        self.fileName = fileName
    }
}
