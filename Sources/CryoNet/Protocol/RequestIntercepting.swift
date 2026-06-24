import Foundation
import Alamofire

// MARK: - 拦截器协议

/// `RequestInterceptorProtocol` 请求/响应拦截器协议，支持请求前后处理。
///
/// 可自定义实现用于自动注入 Token、处理业务错误、结构转换等。
///
/// - Note:
///   - 若不使用 `DefaultInterceptor`，可直接实现本协议并传入 `CryoNetConfiguration.interceptor`。
///   - 建议在 `interceptResponse` 中保持“有 HTTP 响应时先判断非 2xx，否则再处理网络错误”的顺序。
///
/// ### 使用示例
/// ```swift
/// class MyInterceptor: RequestInterceptorProtocol {
///     func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest { ... }
///     func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> { ... }
///     func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> { ... }
/// }
/// ```
public protocol RequestInterceptorProtocol: Sendable {
    /// 请求拦截（如注入 token）
    func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest
    /// 响应拦截（只返回业务数据）
    func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error>
    /// 响应拦截（返回完整响应数据）
    func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error>
}

/// 拦截器配置查询协议，便于调试和业务错误处理。
public protocol InterceptorConfigProvider {
    /// 获取拦截器配置信息
    func getInterceptorConfig() -> [String: Any]
}

// MARK: - 统一失败处理

/// 拦截器的全局失败处理协议。
///
/// 使用该拦截器的 `intercept***` 请求发生最终失败时，CryoNet 会先调用
/// `handleFailure`，然后再调用当前请求的可选局部失败回调。因此，即使调用方
/// 未传入局部失败回调，全局处理仍会执行。
public protocol CryoFailureHandling: Sendable {
    /// 处理使用当前拦截器的请求失败。
    /// - Parameters:
    ///   - failure: 已标准化的统一失败信息。
    ///   - request: 发生失败的 URL 请求；无法获取时为 `nil`。
    func handleFailure(_ failure: CryoFailure, request: URLRequest?)
}
