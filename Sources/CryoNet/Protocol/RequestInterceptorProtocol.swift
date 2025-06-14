import Foundation
import Alamofire

// MARK: - 拦截器协议与默认实现
/**
 拦截器协议，支持请求与响应拦截。
 */
public protocol RequestInterceptorProtocol: Sendable {
    /// 请求拦截（如注入 token）
    func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest
    /// 响应拦截（只返回业务数据）
    func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error>
    /// 响应拦截（返回完整响应数据）
    func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error>
}
