import Foundation
import SwiftyJSON

// MARK: - Token 管理协议与默认实现

/// `TokenManagerProtocol` 定义访问和管理 Token 的接口，支持异步获取、设置和刷新。
///
/// 可自定义实现以适配不同的 Token 存储、刷新逻辑（如 OAuth、JWT、API Key 等）。
///
/// ### 使用示例
/// ```swift
/// class MyTokenManager: TokenManagerProtocol {
///     func getToken() async -> String? { ... }
///     func setToken(_ newToken: String) async { ... }
///     func refreshToken() async -> String? { ... }
/// }
/// ```
public protocol TokenManagerProtocol: Sendable {
    /// 获取当前 Token
    func getToken() async -> String?
    /// 设置新的 Token
    func setToken(_ newToken: String) async
    /// 刷新 Token（如支持则返回新 token）
    func refreshToken() async -> String?
}


/// 线程安全的 token 存储 Actor，封装单实例 Token。
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
