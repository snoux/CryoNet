import Foundation
import Alamofire

// MARK: - 定义请求模型

/// `RequestModel` 封装单个网络请求的所有参数，包括路径、方法、超时、编码方式等。
///
/// 该结构体用于描述 HTTP 请求的所有细节，支持灵活定制请求方式、参数编码、超时、以及接口说明。
///
/// ### 使用示例
/// ```swift
/// // 最基础用法
/// let model = RequestModel(path: "/user/info")
/// // 自定义 GET
/// let model = RequestModel(path: "/user/list", method: .get, overtime: 10)
/// // 自定义编码
/// let model = RequestModel(path: "/upload", encoding: .urlDefault)
/// ```
///
/// - Note:
///   - `applyBasicURL` 为 true 时，path 会自动与配置的 basicURL 拼接。
///   - 支持自定义 CryoParameterEncoder，便于特殊接口适配。
///
/// - SeeAlso: ``CryoParameterEncoder``, ``CryoNet/request(_:parameters:headers:interceptor:)``
@available(iOS 13, *)
public struct RequestModel {
    /// api 接口路径（如 "/user/info"）
    var path: String
    
    /// 是否拼接 BasicURL（true 时使用配置的基础 URL 拼接 path）
    var applyBasicURL: Bool = true

    /// HTTP 请求方式（GET、POST、PUT 等）
    var method: HTTPMethod = .get
    
    /// 参数编码格式（默认 json）
    var encoding: CryoParameterEncoder = .jsonDefault
    
    /// 超时时间（秒）
    var overtime: Double
    
    /// 接口说明（用于文档、调试等）
    var explain: String = ""
    
    /// 初始化
    /// - Parameters:
    ///   - path: API 路径
    ///   - applyBasicURL: 是否拼接基础 URL
    ///   - method: HTTP 方法
    ///   - encoding: 参数编码方式
    ///   - overtime: 超时时间（秒）
    ///   - explain: 接口说明
    public init(
        path: String,
        applyBasicURL: Bool = true,
        method: HTTPMethod = .post,
        encoding: CryoParameterEncoder = .jsonDefault,
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
    
    /// 获取完整 URL（自动拼接 BasicURL 或原样返回）
    /// - Parameter basicURL: 基础 URL
    /// - Returns: 拼接后的完整请求 URL
    public func fullURL(with basicURL: String) -> String {
        applyBasicURL ? basicURL + path : path
    }
}


// MARK: - 扩展流式请求

extension RequestModel {
    /// 流式响应处理器类型
    public typealias StreamHandler = @Sendable (Result<Data, Error>) -> Void
    
    /// 创建流式请求模型（如 SSE、OpenAI 流式接口等）
    ///
    /// - Parameters:
    ///   - path: API 路径
    ///   - applyBasicURL: 是否拼接基础 URL
    ///   - method: HTTP 方法
    ///   - overtime: 超时时间（默认 1 小时）
    ///   - explain: 说明
    /// - Returns: RequestModel 实例
    ///
    /// ### 使用示例
    /// ```swift
    /// let sseModel = RequestModel.streamRequest(path: "/stream")
    /// ```
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
