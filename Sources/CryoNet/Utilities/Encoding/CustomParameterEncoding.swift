import Foundation
import Alamofire


// MARK: - 自定义 ParameterEncoding

/// `CustomParameterEncoding` 允许您定义和使用自定义的参数编码逻辑。
///
/// 此结构体遵循 Alamofire 的 `ParameterEncoding` 协议，使得您可以将任何自定义的参数编码行为
/// 集成到 Alamofire 的请求流程中。这对于处理非标准或特定于业务的请求体格式非常有用。
///
/// ### 使用示例
/// ```swift
/// // 示例：一个简单的自定义编码，将参数编码为 URL 查询字符串，即使是 POST 请求
/// let customURLEncoding = CustomParameterEncoding { urlRequest, parameters in
///     var mutableRequest = try urlRequest.asURLRequest()
///     guard let parameters = parameters else { return mutableRequest }
///
///     var urlComponents = URLComponents(url: mutableRequest.url!, resolvingAgainstBaseURL: false)
///     urlComponents?.queryItems = parameters.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
///     mutableRequest.url = urlComponents?.url
///     return mutableRequest
/// }
///
/// // 在请求中使用自定义编码
/// AF.request("https://api.example.com/data", method: .post, parameters: ["id": 123], encoding: customURLEncoding)
///     .responseJSON { response in
///         debugPrint(response)
///     }
/// ```
///
/// - Note:
///   - `encodingClosure` 闭包必须是 `@Sendable` 的，以确保在并发环境中安全执行。
///   - 通常情况下，您会通过 ``CryoParameterEncoder/custom(_:)`` 枚举成员来使用此自定义编码。
///
/// - SeeAlso: ``CryoParameterEncoder``, ``CryoParameterEncoder/custom(_:)``
public struct CustomParameterEncoding: ParameterEncoding {
    /// 编码闭包，定义了如何将 `URLRequestConvertible` 和 `Parameters` 转换为 `URLRequest`。
    private let encodingClosure: @Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest

    /// 初始化 `CustomParameterEncoding` 实例。
    ///
    /// - Parameter encoding: 一个 `@Sendable` 闭包，它接收一个 `URLRequestConvertible` 和一个可选的 `Parameters` 字典，
    ///   并返回一个经过编码的 `URLRequest`。此闭包将定义实际的参数编码逻辑。
    ///
    /// ### 使用示例
    /// ```swift
    /// let myCustomEncoding = CustomParameterEncoding { urlRequest, parameters in
    ///     // 实现您的自定义编码逻辑
    ///     var request = try urlRequest.asURLRequest()
    ///     // ... 对 request 和 parameters 进行处理 ...
    ///     return request
    /// }
    /// ```
    public init(encoding: @escaping @Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest) {
        self.encodingClosure = encoding
    }

    /// 执行参数编码。
    ///
    /// 此方法是 `ParameterEncoding` 协议的要求，它会调用内部存储的 `encodingClosure` 来执行实际的编码操作。
    ///
    /// - Parameters:
    ///   - urlRequest: 待编码的 `URLRequestConvertible` 实例。
    ///   - parameters: 可选的参数字典，包含要编码到请求中的数据。
    ///
    /// - Returns: 经过编码后的 `URLRequest` 实例。
    ///
    /// - Throws: 如果编码过程中发生错误，则抛出相应的 `Error`。
    ///
    /// ### 使用示例
    /// ```swift
    /// // 通常由 Alamofire 内部调用，无需手动调用。
    /// ```
    public func encode(_ urlRequest: any URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        return try encodingClosure(urlRequest, parameters)
    }
}

/// `CryoParameterEncoder` 枚举封装了 Alamofire 提供的多种参数编码方式，并支持自定义编码。
///
/// 它提供了一个便捷的方式来选择和切换请求的参数编码策略，包括 URL 编码、JSON 编码以及完全自定义的编码。
///
/// ### 使用示例
/// ```swift
/// // 使用 URL 默认编码
/// let urlEncoder = CryoParameterEncoder.urlDefault
///
/// // 使用 JSON 美化格式编码
/// let jsonPrettyEncoder = CryoParameterEncoder.jsonPrettyPrinted
///
/// // 使用自定义编码
/// let customEncoder = CryoParameterEncoder.custom { urlRequest, parameters in
///     var request = try urlRequest.asURLRequest()
///     // ... 自定义编码逻辑 ...
///     return request
/// }
///
/// // 在 RequestModel 中使用
/// // let requestModel = RequestModel(path: "/api/data", encoding: .jsonDefault)
/// ```
///
/// - SeeAlso: ``CustomParameterEncoding``, ``RequestModel``
public enum CryoParameterEncoder: Sendable {
    /// 默认 URL 编码方式，参数通常以 `key=value&key2=value2` 的形式附加到 URL 上。
    case urlDefault
    /// 查询字符串 URL 编码方式，强制将所有参数编码为 URL 查询字符串（不考虑请求方式，始终拼接到 URL）。
    case urlQueryString
    /// HTTP Body 编码方式，参数将编码到 HTTP 请求体中。
    case urlHttpBody
    /// 默认 JSON 编码方式，参数将编码为 JSON 格式并放入请求体。
    case jsonDefault
    /// 美化格式的 JSON 编码方式，参数将编码为易于阅读的 JSON 格式并放入请求体。
    case jsonPrettyPrinted
    /// 自定义编码闭包，允许您提供完全自定义的参数编码逻辑。
    ///
    /// - Parameter encoding: 一个 `@Sendable` 闭包，用于定义自定义编码行为。
    case custom(@Sendable (any URLRequestConvertible, Parameters?) throws -> URLRequest)

    /// 获取与当前枚举成员对应的 Alamofire `ParameterEncoding` 实例。
    ///
    /// - Returns: 相应的 `ParameterEncoding` 实例。
    ///
    /// ### 使用示例
    /// ```swift
    /// let encodingInstance = CryoParameterEncoder.jsonDefault.getEncoding()
    /// // encodingInstance 现在是 Alamofire.JSONEncoding.default
    /// ```
    ///
    /// - SeeAlso: ``CustomParameterEncoding``
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
