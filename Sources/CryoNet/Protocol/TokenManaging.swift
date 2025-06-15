import Foundation
import SwiftyJSON
// MARK: - Token 管理协议与默认实现
/**
 Token 管理协议, 可自定义实现或继承 DefaultTokenManager。
 */
public protocol TokenManagerProtocol: Sendable {
    /// 获取当前 Token
    func getToken() async -> String?
    /// 设置新的 Token
    func setToken(_ newToken: String) async
    /// 刷新 Token（如支持则返回新 token）
    func refreshToken() async -> String?
}


// MARK: - 封装 token 状态的线程安全 actor
/**
 线程安全的 token 存储。
 */
actor TokenStorageActor {
    private var token: String?
    
    /// 获取 token
    func get() -> String? {
        token
    }
    
    /// 设置 token
    func set(_ newToken: String?) {
        token = newToken
    }
}
