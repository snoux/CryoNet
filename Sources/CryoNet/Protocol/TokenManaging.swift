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
///     func clearToken() async { ... }
///     func refreshToken() async -> String? { ... }
/// }
/// ```
public protocol TokenManagerProtocol: Sendable {
    /// 获取当前 Token
    func getToken() async -> String?
    /// 设置新的 Token
    func setToken(_ newToken: String) async
    /// 清除当前 Token
    func clearToken() async
    /// 刷新 Token（如支持则返回新 token）
    func refreshToken() async -> String?
}

public extension TokenManagerProtocol {
    /// 默认清除 Token 实现。
    ///
    /// 自定义 Token 管理器建议重写本方法，清除 Keychain、UserDefaults、数据库等持久化存储。
    /// 默认实现通过设置空字符串保持旧实现源码兼容；默认拦截器会忽略空字符串 Token，不会注入 `Authorization`。
    func clearToken() async {
        await setToken("")
    }
}

/// 线程安全的 token 存储 Actor，封装单实例 Token。
actor TokenStorageActor {
    private var token: String?

    /// 创建 Token 存储。
    /// - Parameter token: 初始 Token。
    init(token: String? = nil) {
        self.token = token
    }
    
    /// 获取 token
    func get() -> String? {
        token
    }
    
    /// 设置 token
    func set(_ newToken: String?) {
        token = newToken
    }
}
