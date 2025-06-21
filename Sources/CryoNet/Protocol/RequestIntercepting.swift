import Foundation
import Alamofire

// MARK: - 拦截器协议

/// `RequestInterceptorProtocol` 请求/响应拦截器协议，支持请求前后处理。
///
/// 可自定义实现用于自动注入 Token、处理业务错误、结构转换等。
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
