import Foundation

/// CryoNet 统一失败信息。
///
/// 该类型统一表示 HTTP、业务、网络、数据解析和取消等失败场景。
/// 全局 ``CryoFailureHandling/handleFailure(_:request:)`` 与当前请求的局部失败
/// 回调使用同一个 `CryoFailure` 实例。
public struct CryoFailure: LocalizedError, @unchecked Sendable {

    /// 统一失败类别。
    public enum Kind: String, Sendable {
        /// 登录或会话已失效，通常需要刷新凭证或重新登录。
        case authenticationExpired

        /// HTTP 状态码为非 2xx。
        case http

        /// HTTP 响应成功，但业务成功条件未通过。
        case business

        /// 超时、断网、DNS、TLS 或连接中断等网络层错误。
        case network

        /// JSON、`Decodable` 或其他响应数据转换失败。
        case decoding

        /// 请求被主动取消。
        case cancelled

        /// 调用 `intercept***` 系列 API 时未配置响应拦截器。
        case interceptorMissing

        /// 无法归类到其他已知类别的错误。
        case unknown
    }

    /// 失败类别。
    public let kind: Kind

    /// 可用于日志或用户提示的错误文案。
    public let message: String

    /// HTTP 状态码；未收到 HTTP 响应时为 `nil`。
    public let statusCode: Int?

    /// 服务端业务错误码；未配置或未提取到时为 `nil`。
    public let businessCode: Int?

    /// 请求首次发送时捕获的认证会话 UUID revision。
    ///
    /// 可与认证状态管理器的当前 revision 比较，以忽略旧会话延迟返回的失败响应。
    public let authenticationRevision: UUID?

    /// 服务端返回的原始响应体；无响应数据时为 `nil`。
    public let responseData: Data?

    /// Alamofire、URLSession 或解析器产生的底层错误。
    public let underlyingError: Error?

    /// `LocalizedError` 使用的错误描述。
    public var errorDescription: String? { message }

    /// 创建统一失败信息。
    /// - Parameters:
    ///   - kind: 失败类别。
    ///   - message: 错误文案。
    ///   - statusCode: HTTP 状态码。
    ///   - businessCode: 服务端业务错误码。
    ///   - authenticationRevision: 请求首次发送时捕获的认证会话 UUID revision。
    ///   - responseData: 原始响应体。
    ///   - underlyingError: 底层错误。
    public init(
        kind: Kind,
        message: String,
        statusCode: Int? = nil,
        businessCode: Int? = nil,
        authenticationRevision: UUID? = nil,
        responseData: Data? = nil,
        underlyingError: Error? = nil
    ) {
        self.kind = kind
        self.message = message
        self.statusCode = statusCode
        self.businessCode = businessCode
        self.authenticationRevision = authenticationRevision
        self.responseData = responseData
        self.underlyingError = underlyingError
    }
}

extension CryoFailure {
    /// 将旧错误封装为统一失败信息。
    /// - Parameters:
    ///   - error: 需要封装的原始错误。
    ///   - response: 当前 HTTP 响应。
    ///   - responseData: 当前原始响应体。
    ///   - authenticationRevision: 请求首次发送时捕获的认证会话 UUID revision。
    ///   - preferredKind: 上层已确定的错误类别。
    /// - Returns: 标准化后的 `CryoFailure`。
    static func wrapping(
        _ error: Error,
        response: HTTPURLResponse?,
        responseData: Data?,
        authenticationRevision: UUID? = nil,
        preferredKind: Kind? = nil
    ) -> CryoFailure {
        if let failure = error as? CryoFailure {
            return failure.attachingAuthenticationRevision(authenticationRevision)
        }

        let nsError = error as NSError
        let statusCode = nsError.userInfo["statusCode"] as? Int ?? response?.statusCode
        let businessCode = nsError.userInfo["businessCode"] as? Int
        let storedData = nsError.userInfo["responseData"] as? Data
            ?? nsError.userInfo["originalData"] as? Data
            ?? responseData
        let kind = preferredKind ?? inferKind(
            nsError: nsError,
            statusCode: statusCode,
            businessCode: businessCode
        )

        return CryoFailure(
            kind: kind,
            message: error.localizedDescription,
            statusCode: statusCode,
            businessCode: businessCode,
            authenticationRevision: authenticationRevision,
            responseData: storedData,
            underlyingError: error
        )
    }

    /// 返回附加认证会话 revision 后的失败副本。
    /// - Parameter revision: 请求首次发送时捕获的认证会话 UUID revision。
    /// - Returns: 包含指定 revision 的新失败实例。
    func attachingAuthenticationRevision(_ revision: UUID?) -> CryoFailure {
        guard authenticationRevision == nil, let revision else { return self }
        return CryoFailure(
            kind: kind,
            message: message,
            statusCode: statusCode,
            businessCode: businessCode,
            authenticationRevision: revision,
            responseData: responseData,
            underlyingError: underlyingError
        )
    }

    /// 从旧 `NSError` 字段推断统一失败类别。
    private static func inferKind(
        nsError: NSError,
        statusCode: Int?,
        businessCode: Int?
    ) -> Kind {
        if statusCode == 401 {
            return .authenticationExpired
        }
        if let statusCode, !(200..<300).contains(statusCode) {
            return .http
        }
        if businessCode != nil || nsError.domain == "BusinessError" {
            return .business
        }
        switch nsError.domain {
        case "URLError", "NetworkError", NSURLErrorDomain:
            return .network
        case "DataError", "SerializationError":
            return .decoding
        case "CancellationError":
            return .cancelled
        case "InterceptorError":
            return .interceptorMissing
        default:
            return .unknown
        }
    }
}
