import Foundation
import Alamofire


// MARK: - 自定义 ParameterEncoding
/**
 自定义 ParameterEncoding
 用于自定义参数编码方式，兼容 Alamofire ParameterEncoding 协议。
 */
public struct CustomParameterEncoding: ParameterEncoding {
    /// 编码闭包
    private let encodingClosure: @Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest

    /**
     初始化自定义编码
     - Parameter encoding: 编码逻辑闭包
     */
    public init(encoding: @escaping @Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest) {
        self.encodingClosure = encoding
    }

    /**
     执行编码
     - Parameters:
        - urlRequest: URL 请求
        - parameters: 参数字典
     - Returns: 编码后的 URLRequest
     */
    public func encode(_ urlRequest: any URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        return try encodingClosure(urlRequest, parameters)
    }
}

/**
 ParameterEncoder
 枚举封装 Alamofire 的 ParameterEncoding，方便自定义和切换参数编码方式。
 */
public enum ParameterEncoder {
    /// 默认 URL 编码（key=value&key2=value2 放在 URL 上）
    case urlDefault
    /// 查询字符串 URL 编码（强制参数在 URL 上）
    case urlQueryString
    /// HTTP Body 编码（参数在 body 内）
    case urlHttpBody
    /// 默认 JSON 编码（JSONEncoding.default）
    case jsonDefault
    /// 美化格式的 JSON 编码
    case jsonPrettyPrinted
    /// 自定义编码闭包
    case custom(@Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest)

    /**
     获取实际的 ParameterEncoding 实例
     - Returns: ParameterEncoding
     */
    func getEncoding() -> ParameterEncoding {
        switch self {
        case .urlDefault:
            return URLEncoding.default
        case .urlQueryString:
            return URLEncoding.queryString
        case .urlHttpBody:
            return URLEncoding.httpBody
        case .jsonDefault:
            return JSONEncoding.default
        case .jsonPrettyPrinted:
            return JSONEncoding.prettyPrinted
        case .custom(let encoding):
            return CustomParameterEncoding(encoding: encoding)
        }
    }
}


/**
 单个下载项 DownloadItem
 使用 actor 保证线程安全，支持进度和文件信息管理。
 */
@available(iOS 13, *)
public actor DownloadItem: Identifiable, Equatable, @unchecked Sendable {
    public static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id
    }

    /// 唯一标识
    public let id = UUID().uuidString

    private var _fileName: String = ""
    private var _filePath: String = ""
    private var _previewPath: String = ""
    private var _progress: Double = 0.0

    /**
     初始化方法
     - Parameters:
        - fileName: 文件名
        - filePath: 文件路径
        - previewPath: 预览路径
     */
    public init(fileName: String?, filePath: String, previewPath: String?) {
        self._fileName = fileName ?? ""
        self._filePath = filePath
        self._previewPath = previewPath ?? ""
    }

    /// 空初始化
    public init() {}

    /// 设置下载进度
    public func setProgress(_ value: Double) {
        _progress = value
    }

    /// 获取下载进度
    public func getProgress() -> Double {
        _progress
    }

    /// 获取文件名
    public func getFileName() -> String {
        _fileName
    }

    /// 获取文件路径
    public func getFilePath() -> String {
        _filePath
    }

    /// 获取文件 URL
    public func fileURL() -> URL? {
        URL(string: _filePath)
    }
}
