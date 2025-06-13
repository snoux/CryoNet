import Foundation
import Alamofire

// MARK: - 定义请求模型

/**
 请求模型 RequestModel
 封装单个网络请求的所有参数，包括路径、方法、超时、编码方式等。
 */
@available(iOS 13, *)
public struct RequestModel {
    /// api 接口路径（如 "/user/info"）
    var path: String
    
    /// 是否拼接 BasicURL（true 时使用配置的基础 URL 拼接 path）
    var applyBasicURL: Bool = true

    /// HTTP 请求方式（GET、POST、PUT 等）
    var method: HTTPMethod = .get
    
    /// 参数编码格式（默认 json）
    var encoding: ParameterEncoder = .jsonDefault
    
    /// 超时时间（秒）
    var overtime: Double
    
    /// 接口说明（用于文档、调试等）
    var explain: String = ""
    
    /**
     初始化方法
     - Parameters:
        - path: API 路径
        - applyBasicURL: 是否拼接基础 URL
        - method: HTTP 方法
        - encoding: 参数编码方式
        - overtime: 超时时间（秒）
        - explain: 接口说明
     */
    public init(
        path: String,
        applyBasicURL: Bool = true,
        method: HTTPMethod = .post,
        encoding: ParameterEncoder = .jsonDefault,
        overtime: Double = 30,
        explain: String = ""
    ) {
        self.path = path
        self.applyBasicURL = applyBasicURL
        self.method = method
        self.encoding = encoding
        self.overtime = overtime
        self.explain = explain
    }
    
    /**
     获取完整 URL
     - Parameter basicURL: 基础 URL
     - Returns: 完整的请求 URL 字符串
     */
    public func fullURL(with basicURL: String) -> String {
        applyBasicURL ? basicURL + path : path
    }
}


// MARK: - 扩展流式请求

extension RequestModel {
    /// 流式响应处理器类型
    public typealias StreamHandler = @Sendable (Result<Data, Error>) -> Void
    
    /**
     创建流式请求模型（如 SSE、OpenAI 流式接口等）
     - Parameters:
        - path: API 路径
        - applyBasicURL: 是否拼接基础 URL
        - method: HTTP 方法
        - overtime: 超时时间（默认 1 小时）
        - explain: 说明
     - Returns: RequestModel 实例
     */
    public static func streamRequest(
        path: String,
        applyBasicURL: Bool = true,
        method: HTTPMethod = .get,
        overtime: Double = 60 * 60, // 默认1小时超时
        explain: String = ""
    ) -> RequestModel {
        return RequestModel(
            path: path,
            applyBasicURL: applyBasicURL,
            method: method,
            encoding: .custom { urlRequest, _ in
                var request = try URLEncoding.default.encode(urlRequest, with: nil)
                // 设置流式请求头
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.timeoutInterval = overtime
                return request
            },
            overtime: overtime,
            explain: explain
        )
    }
}

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
