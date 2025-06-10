import Foundation
import Alamofire

// MARK: - 自定义 ParameterEncoding
/// 自定义 ParameterEncoding
public struct CustomParameterEncoding: ParameterEncoding {
    /// 编码闭包
    private let encodingClosure: @Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest

    /// 初始化自定义编码
    /// - Parameter encoding: 编码逻辑闭包
    public init(encoding: @escaping @Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest) {
        self.encodingClosure = encoding
    }

    /// 执行编码
    /// - Parameters:
    ///   - urlRequest: URL 请求
    ///   - parameters: 参数字典
    /// - Returns: 编码后的 URL 请求
    /// - Throws: 编码过程中的错误
    public func encode(_ urlRequest: any URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        return try encodingClosure(urlRequest, parameters)
    }
}

/// 枚举封装 Alamofire 的 ParameterEncoding
public enum ParameterEncoder {
    /// 默认 URL 编码
    case urlDefault
    /// 查询字符串 URL 编码
    case urlQueryString
    /// HTTP Body 编码
    case urlHttpBody
    /// 默认 JSON 编码
    case jsonDefault
    /// 美化格式的 JSON 编码
    case jsonPrettyPrinted
    /// 自定义编码
    case custom(@Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest)

    /// 获取对应的 ParameterEncoding
    /// - Returns: 对应的 ParameterEncoding 实例
    func getEncoding() -> ParameterEncoding {
        switch self {
        case .urlDefault:
            /// 默认 URL 编码
            return URLEncoding.default
        case .urlQueryString:
            /// 查询字符串 URL 编码
            return URLEncoding.queryString
        case .urlHttpBody:
            /// HTTP Body 编码
            return URLEncoding.httpBody
        case .jsonDefault:
            /// 默认 JSON 编码
            return JSONEncoding.default
        case .jsonPrettyPrinted:
            /// 美化格式的 JSON 编码
            return JSONEncoding.prettyPrinted
        case .custom(let encoding):
            /// 自定义编码
            return CustomParameterEncoding(encoding: encoding)
        }
    }
}

/// 请求模型
@available(iOS 13, *)
public struct RequestModel {
    /// api 接口
    var url: String
    
    /// 是否拼接 BasicURL
    var applyBasicURL: Bool = true

    /// 请求方式
    var method: HTTPMethod = .get
    
    /// 参数编码格式(默认json)
    var encoding: ParameterEncoder = .jsonDefault
    
    /// 超时时间
    var overtime: Double
    
    /// 接口说明
    var explain: String = ""
    
    /// 初始化方法
    public init(
        url: String,
        applyBasicURL: Bool = true,
        method: HTTPMethod = .post,
        encoding: ParameterEncoder = .jsonDefault,
        overtime: Double = 30,
        explain: String = ""
    ) {
        self.url = url
        self.applyBasicURL = applyBasicURL
        self.method = method
        self.encoding = encoding
        self.overtime = overtime
        self.explain = explain
    }
    
    /// 获取完整URL
    /// - Parameter basicURL: 基础URL
    /// - Returns: 完整URL
    public func fullURL(with basicURL: String) -> String {
        applyBasicURL ? basicURL + url : url
    }
}

/// 上传文件参数
@available(iOS 13 ,*)
public struct UploadData: Identifiable, Equatable {
    public static func == (lhs: UploadData, rhs: UploadData) -> Bool {
        lhs.id == rhs.id
    }
    public let id: UUID = UUID()
    /// 要上传的文件
    public var file: fileType
    /// 与数据相关联的名称
    public var name: String
    /// 与数据相关联的文件名
    public var fileName: String?
    
    public enum fileType {
        case fileURL(URL?)
        case fileData(Data?)
    }
    
    public init(file: fileType, name: String, fileName: String? = nil) {
        self.file = file
        self.name = name
        self.fileName = fileName
    }
}

/// 下载文件
@available(iOS 13 ,*)
public struct DownloadModel {
    public var savePath: String?
    public var models: [DownloadItem]
    
    public var savePathURL: URL? {
        if savePath != nil {
            return URL(string: savePath!)
        } else {
            return nil
        }
    }

    public init(savePath: String?, models: [DownloadItem]) {
        self.savePath = savePath
        self.models = models
    }
}

@available(iOS 13, *)
public actor DownloadItem: Identifiable, Equatable, @unchecked Sendable {
    public static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id
    }

    public let id = UUID().uuidString

    private var _fileName: String = ""
    private var _filePath: String = ""
    private var _previewPath: String = ""
    private var _progress: Double = 0.0

    public init(fileName: String?, filePath: String, previewPath: String?) {
        self._fileName = fileName ?? ""
        self._filePath = filePath
        self._previewPath = previewPath ?? ""
    }

    public init() {}

    public func setProgress(_ value: Double) {
        _progress = value
    }

    public func getProgress() -> Double {
        _progress
    }

    public func getFileName() -> String {
        _fileName
    }

    public func getFilePath() -> String {
        _filePath
    }

    public func fileURL() -> URL? {
        URL(string: _filePath)
    }
}




@available(iOS 13 ,*)
/// 下载结果
public class DownloadResult {
    /// 结果信息
    public var result: Result<URL?, AFError>
    
    /// Result 对应的 downLoadItem
    public let downLoadItem: DownloadItem
    
    init(result: Result<URL?, AFError>, downLoadItem: DownloadItem) {
        self.result = result
        self.downLoadItem = downLoadItem
    }
}
