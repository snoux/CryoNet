import Foundation

/// 应用认证状态。
public enum AuthenticationState: String, Sendable {
    /// 当前持有有效登录会话。
    case authenticated

    /// 已开始处理退出，后续并发登录失效事件不应再次执行退出操作。
    case loggingOut

    /// 当前没有有效登录会话。
    case unauthenticated
}

/// 请求发出时的认证会话快照。
public struct AuthenticationSnapshot: Sendable {
    /// 请求发出时的认证状态。
    public let state: AuthenticationState

    /// 当前认证会话的唯一 revision。
    ///
    /// revision 只用于相等性比较，不表示大小或先后顺序。登录、退出或切换账号后会生成新的 UUID。
    public let revision: UUID

    /// 创建认证会话快照。
    /// - Parameters:
    ///   - state: 当前认证状态。
    ///   - revision: 当前认证会话唯一 revision。
    public init(state: AuthenticationState, revision: UUID) {
        self.state = state
        self.revision = revision
    }
}

/// 认证会话状态管理协议。
///
/// 用户可实现该协议接入自己的账号系统与持久化方案；框架默认实现只维护运行期状态，
/// 不强制使用 Keychain、UserDefaults 或数据库。
public protocol AuthenticationSessionManaging: Sendable {
    /// 获取当前认证状态与 revision 快照。
    func snapshot() async -> AuthenticationSnapshot

    /// 当前请求 revision 仍属于现有登录会话时，原子切换到退出中。
    /// - Parameter expectedRevision: 请求发出时记录的会话 revision；为 `nil` 时只检查登录状态。
    /// - Returns: 当前调用是否获得执行退出操作的权限。
    func beginLogoutIfCurrent(expectedRevision: UUID?) async -> Bool

    /// 登录成功后切换到已登录状态，并生成新的会话 revision。
    func markAuthenticated() async

    /// 退出完成后切换到未登录状态，并生成新的会话 revision。
    func markLoggedOut() async
}

/// 线程安全的默认认证会话状态管理器。
///
/// 该实现通过 Actor 保证 revision 比较和状态切换为原子操作。Token 的持久化仍由用户自己的
/// `TokenManagerProtocol` 或账号系统负责。
public actor DefaultAuthenticationSessionManager: AuthenticationSessionManaging {
    /// 当前认证状态。
    public private(set) var state: AuthenticationState

    /// 当前认证会话的唯一 revision。
    public private(set) var revision: UUID

    /// 创建默认认证会话状态管理器。
    /// - Parameters:
    ///   - initialState: App 启动时根据持久化 Token 或账号状态恢复的初始状态。
    ///   - initialRevision: 初始会话 revision，默认自动生成 UUID。
    public init(
        initialState: AuthenticationState = .unauthenticated,
        initialRevision: UUID = UUID()
    ) {
        self.state = initialState
        self.revision = initialRevision
    }

    /// 根据 Token 管理器中的持久化结果恢复默认认证状态管理器。
    /// - Parameter tokenManager: 用户配置的 Token 管理器。
    /// - Returns: 有 Token 时初始为已登录，否则初始为未登录的状态管理器。
    public static func restore(
        using tokenManager: TokenManagerProtocol
    ) async -> DefaultAuthenticationSessionManager {
        let token = await tokenManager.getToken()
        return DefaultAuthenticationSessionManager(
            initialState: token == nil ? .unauthenticated : .authenticated
        )
    }

    /// 获取当前认证状态与 revision 快照。
    public func snapshot() -> AuthenticationSnapshot {
        AuthenticationSnapshot(state: state, revision: revision)
    }

    /// 当前 revision 匹配且处于已登录状态时，原子切换到退出中。
    public func beginLogoutIfCurrent(expectedRevision: UUID?) -> Bool {
        if let expectedRevision, expectedRevision != revision {
            return false
        }
        guard state == .authenticated else {
            return false
        }
        state = .loggingOut
        return true
    }

    /// 登录成功后切换到已登录状态，并生成新的会话 revision。
    public func markAuthenticated() {
        revision = UUID()
        state = .authenticated
    }

    /// 退出完成后切换到未登录状态，并生成新的会话 revision。
    public func markLoggedOut() {
        revision = UUID()
        state = .unauthenticated
    }
}

/// 为请求保存认证 revision 的内部线程安全上下文。
final class RequestAuthenticationContext: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRevision: UUID?

    /// 请求首次适配时记录认证 revision；重试不会覆盖初始 revision。
    func captureIfNeeded(_ revision: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard storedRevision == nil else { return }
        storedRevision = revision
    }

    /// 返回请求首次适配时记录的认证 revision。
    var revision: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return storedRevision
    }
}

/// 为拦截器提供可选认证会话状态管理器。
public protocol AuthenticationSessionProviding: Sendable {
    /// 当前拦截器使用的认证会话状态管理器。
    var authenticationSession: AuthenticationSessionManaging? { get }
}
