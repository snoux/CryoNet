import Foundation
import Alamofire
import SwiftyJSON

// MARK: - 默认响应结构配置

/// 默认响应结构配置，提供闭包默认实现。
open class DefaultResponseStructure: ResponseStructureConfig, @unchecked Sendable {
    public init() {}

    /// 判断响应是否成功
    /// - Returns: 是否业务成功
    open func isSuccess(json: JSON) -> Bool {
        true
    }

    /// 从 JSON 提取数据（可重写）
    /// - Returns: 提取的数据或错误
    open func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        .success(originalData)
    }

    /// 失败原因提取，可重写
    open func extractFailureReason(from json: JSON, originalData: Data) -> String? {
        let commonKeys = ["message", "msg", "error", "reason", "detail"]
        for key in commonKeys {
            let value = json[key]
            if let text = value.string, !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// 业务错误码提取，默认读取 `code` 字段。
    /// - Returns: 业务错误码，无法提取时返回 `nil`。
    open func extractBusinessCode(from json: JSON, originalData: Data) -> Int? {
        json["code"].int
    }
}

// MARK: - 便捷配置结构体

/// `ResponseConfig` 响应结构配置结构体，支持闭包式快速配置，无需创建类。
///
/// 通过闭包方式自定义数据提取和成功判断逻辑，简化配置过程。
///
/// ### 使用示例
/// ```swift
/// let responseConfig = ResponseConfig(
///     extractData: { json, originalData in
///         JSON.extractDataFromJSON(json["result"], originalData: originalData)
///     },
///     isSuccess: { json in
///         json["status"] == "ok"
///     },
///     extractFailureReason: { json, _ in
///         json["message"].string
///     }
/// )
/// ```
public struct ResponseConfig: ResponseStructureConfig, @unchecked Sendable {
    /// 自定义数据提取闭包
    private let extractDataHandler: @Sendable (JSON, Data) -> Result<Data, Error>
    /// 自定义成功判断闭包
    private let isSuccessHandler: @Sendable (JSON) -> Bool
    /// 自定义失败原因提取闭包
    private let extractFailureReasonHandler: @Sendable (JSON, Data) -> String?
    /// 自定义业务错误码提取闭包
    private let extractBusinessCodeHandler: @Sendable (JSON, Data) -> Int?
    
    /// 初始化响应配置
    /// - Parameters:
    ///   - extractData: 可选的自定义数据提取闭包，返回提取的数据或错误。如果为 nil 则使用默认逻辑
    ///   - isSuccess: 可选的自定义成功判断闭包，返回是否成功。如果为 nil 则使用默认逻辑
    ///   - extractFailureReason: 可选的失败原因提取闭包
    ///   - extractBusinessCode: 可选的业务错误码提取闭包，默认读取 `code` 字段。
    public init(
        extractData: ((JSON, Data) -> Result<Data, Error>)? = nil,
        isSuccess: ((JSON) -> Bool)? = nil,
        extractFailureReason: ((JSON, Data) -> String?)? = nil,
        extractBusinessCode: ((JSON, Data) -> Int?)? = nil
    ) {
        // 如果提供了自定义闭包，使用自定义闭包；否则使用默认逻辑
        if let extractData = extractData {
            self.extractDataHandler = { @Sendable json, originalData in
                extractData(json, originalData)
            }
        } else {
            self.extractDataHandler = { @Sendable _, originalData in
                .success(originalData)
            }
        }
        
        if let isSuccess = isSuccess {
            self.isSuccessHandler = { @Sendable json in
                isSuccess(json)
            }
        } else {
            self.isSuccessHandler = { @Sendable _ in
                true
            }
        }

        if let extractFailureReason = extractFailureReason {
            self.extractFailureReasonHandler = { @Sendable json, originalData in
                extractFailureReason(json, originalData)
            }
        } else {
            self.extractFailureReasonHandler = { @Sendable json, _ in
                let commonKeys = ["message", "msg", "error", "reason", "detail"]
                for key in commonKeys {
                    let value = json[key]
                    if let text = value.string, !text.isEmpty {
                        return text
                    }
                }
                return nil
            }
        }

        if let extractBusinessCode = extractBusinessCode {
            self.extractBusinessCodeHandler = { @Sendable json, originalData in
                extractBusinessCode(json, originalData)
            }
        } else {
            self.extractBusinessCodeHandler = { @Sendable json, _ in
                json["code"].int
            }
        }
    }
    
    /// 判断响应是否成功
    public func isSuccess(json: JSON) -> Bool {
        isSuccessHandler(json)
    }
    
    /// 从 JSON 提取数据
    public func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        extractDataHandler(json, originalData)
    }

    /// 从 JSON 提取失败原因
    public func extractFailureReason(from json: JSON, originalData: Data) -> String? {
        extractFailureReasonHandler(json, originalData)
    }

    /// 从响应中提取业务错误码。
    public func extractBusinessCode(from json: JSON, originalData: Data) -> Int? {
        extractBusinessCodeHandler(json, originalData)
    }
}

// MARK: - 可继承、线程安全的默认实现

/// 默认 Token 管理器，线程安全，支持手动和自动刷新。
///
/// 通过 actor 保证并发安全，可自定义 token 刷新策略。
open class DefaultTokenManager: TokenManagerProtocol, @unchecked Sendable {
    private let storage: TokenStorageActor

    /// 初始化，可指定初始 token
    /// - Parameter token: 初始 token
    public init(token: String? = nil) {
        self.storage = TokenStorageActor(token: token)
    }

    /// 获取当前 Token
    /// - Returns: 当前 Token，若无则为 nil
    open func getToken() async -> String? {
        await storage.get()
    }

    /// 设置新的 Token
    /// - Parameter newToken: 新 Token
    open func setToken(_ newToken: String) async {
        await storage.set(newToken)
    }

    /// 刷新 Token（需子类实现）
    /// - Returns: 新 Token，默认 nil
    open func refreshToken() async -> String? {
        nil
    }
}

// MARK: - 默认拦截器(允许继承)

/// 默认实现，支持 token 注入、业务异常处理、结构化错误输出，支持响应结构配置定制。
///
/// 可用于自定义拦截链路、业务状态码识别、自动注入 token、错误封装等。
open class DefaultInterceptor: RequestInterceptorProtocol, InterceptorConfigProvider, CryoFailureHandling, AuthenticationSessionProviding, @unchecked Sendable {

    /// 响应结构配置
    public let responseConfig: ResponseStructureConfig

    /// 当前拦截器使用的可选认证会话状态管理器。
    ///
    /// 配置后，框架会在请求首次适配时捕获会话 UUID revision，并保存到最终 ``CryoFailure``。
    public let authenticationSession: AuthenticationSessionManaging?

    /// 初始化，支持自定义响应结构
    /// - Parameters:
    ///   - responseConfig: 指定响应结构配置。
    ///   - authenticationSession: 可选认证会话状态管理器。
    public nonisolated init(
        responseConfig: ResponseStructureConfig,
        authenticationSession: AuthenticationSessionManaging? = nil
    ) {
        self.responseConfig = responseConfig
        self.authenticationSession = authenticationSession
    }

    /// 使用默认响应结构且不配置认证状态管理器创建拦截器。
    public nonisolated convenience init() {
        self.init(responseConfig: DefaultResponseStructure())
    }

    /// 便捷初始化方法，支持闭包式快速配置（推荐使用）。
    /// - Parameters:
    ///   - extractData: 从完整 JSON 中提取最终业务数据的闭包。
    ///   - isSuccess: 判断 HTTP 2xx 响应是否业务成功的闭包。
    ///   - extractFailureReason: 从业务失败响应中提取错误文案的闭包。
    ///   - extractBusinessCode: 从业务失败响应中提取业务错误码的闭包。
    ///   - authenticationSession: 可选认证会话状态管理器。
    public nonisolated convenience init(
        extractData: ((JSON, Data) -> Result<Data, Error>)? = nil,
        isSuccess: ((JSON) -> Bool)? = nil,
        extractFailureReason: ((JSON, Data) -> String?)? = nil,
        extractBusinessCode: ((JSON, Data) -> Int?)? = nil,
        authenticationSession: AuthenticationSessionManaging? = nil
    ) {
        let config = ResponseConfig(
            extractData: extractData,
            isSuccess: isSuccess,
            extractFailureReason: extractFailureReason,
            extractBusinessCode: extractBusinessCode
        )
        self.init(
            responseConfig: config,
            authenticationSession: authenticationSession
        )
    }

    /// 向后兼容老接口的便捷初始化（已废弃）
    @available(*, deprecated, message: "请改用 init(extractData:isSuccess:extractFailureReason:)")
    public nonisolated convenience init(successCode: Int = 200, successDataKey: String = "data") {
        self.init(
            extractData: { json, originalData in
                JSON.extractDataFromJSON(json[successDataKey], originalData: originalData)
            },
            isSuccess: { json in
                json["code"].intValue == successCode
            },
            extractFailureReason: { json, _ in
                json["msg"].string
            }
        )
    }

    /// 向后兼容老接口的便捷初始化（已废弃）
    @available(*, deprecated, message: "请改用 init(extractData:isSuccess:extractFailureReason:)")
    public nonisolated convenience init(
        codeKey: String = "code",
        messageKey: String = "msg",
        dataKey: String = "data",
        successCode: Int = 200,
        extractData: ((JSON, Data) -> Result<Data, Error>)? = nil,
        isSuccess: ((JSON) -> Bool)? = nil
    ) {
        self.init(
            extractData: extractData ?? { json, originalData in
                JSON.extractDataFromJSON(json[dataKey], originalData: originalData)
            },
            isSuccess: isSuccess ?? { json in
                json[codeKey].intValue == successCode
            },
            extractFailureReason: { json, _ in
                json[messageKey].string
            }
        )
    }

    /// 请求拦截，自动注入 Bearer Token
    /// - Returns: 注入 token 后的新请求
    open func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
        guard let token = await tokenManager.getToken() else {
            return urlRequest
        }
        var modifiedRequest = urlRequest
        let authValue = "Bearer \(token)"
        if var headers = modifiedRequest.allHTTPHeaderFields {
            headers["Authorization"] = authValue
            modifiedRequest.allHTTPHeaderFields = headers
        } else {
            modifiedRequest.setValue(authValue, forHTTPHeaderField: "Authorization")
        }
        return modifiedRequest
    }

    /// 响应拦截，只返回业务数据 data
    ///
    /// 处理顺序：
    /// 1) 已收到 HTTP 响应且为非 2xx 时，返回对应 HTTP 错误；
    /// 2) HTTP 2xx 或未收到 HTTP 响应时，再处理底层网络错误；
    /// 3) HTTP 2xx 后进入业务判断（`isSuccess`）；
    /// 4) 业务成功返回 `extractData`，业务失败返回 `extractFailureReason`。
    /// - Returns: 业务数据或错误
    open func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        if let httpResponse = response.response,
           let httpError = handleHTTPStatusCode(
               httpResponse.statusCode,
               data: response.data,
               underlyingError: response.error
           ) {
            return .failure(httpError)
        }
        if let error = response.error {
            return .failure(handleAFError(error))
        }
        guard let httpResponse = response.response else {
            return .failure(makeError(domain: "NetworkError", code: -1, message: "无效的服务器响应"))
        }
        guard let data = response.data else {
            return .failure(makeError(
                domain: "DataError",
                code: httpResponse.statusCode,
                message: "响应数据为空"
            ))
        }
        return processSpecificResponseData(data: data, response: httpResponse)
    }

    /// 响应拦截，返回完整响应体
    ///
    /// 网络层与 HTTP 层判断规则与 `interceptResponse` 一致。
    /// - Returns: 完整响应体或错误
    open func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        if let httpResponse = response.response,
           let httpError = handleHTTPStatusCode(
               httpResponse.statusCode,
               data: response.data,
               underlyingError: response.error
           ) {
            return .failure(httpError)
        }
        if let error = response.error {
            return .failure(handleAFError(error))
        }
        guard let httpResponse = response.response else {
            return .failure(makeError(domain: "NetworkError", code: -1, message: "无效的服务器响应"))
        }
        guard let data = response.data else {
            return .failure(makeError(
                domain: "DataError",
                code: httpResponse.statusCode,
                message: "响应数据为空"
            ))
        }
        return processCompleteResponseData(data: data, response: httpResponse)
    }

    /// 判断响应是否成功，可重写
    ///
    /// - Note: 仅用于业务层判断，网络层与 HTTP 层由上游先行处理。
    /// - Returns: 响应是否业务成功
    open func isResponseSuccess(json: JSON) -> Bool {
        responseConfig.isSuccess(json: json)
    }

    /// 从 JSON 中提取业务数据，可重写
    /// - Returns: 提取的数据或错误
    open func extractSuccessData(from json: JSON, data: Data) -> Result<Data, Error> {
        // 直接调用协议方法，支持所有实现 ResponseStructureConfig 的类型
        // 如果用户重写了 extractData，会自动调用重写的方法
        return responseConfig.extractData(from: json, originalData: data)
    }

    /// 处理自定义业务错误，可重写
    ///
    /// - Note: 失败原因默认来自 `responseConfig.extractFailureReason`，获取不到时使用兜底文案。
    /// - Returns: 错误结果
    open func handleCustomError(
        jsonData: Data,
        httpResponse: HTTPURLResponse,
        isCompleteResponse: Bool
    ) -> Result<Data, Error> {
        processErrorResponseData(
            jsonData: jsonData,
            httpResponse: httpResponse,
            isCompleteResponse: isCompleteResponse
        )
    }

    /// 使用当前拦截器处理响应时的全局失败入口，默认不执行任何操作。
    ///
    /// `intercept***` 系列的 HTTP、业务、网络和数据解析错误都会经过本方法。业务方可通过
    /// 继承 ``DefaultInterceptor`` 并重写本方法，统一处理登录失效、公共提示、
    /// 错误日志或监控上报。执行后仍会继续调用当前请求的可选局部失败回调。
    ///
    /// - Important: 本方法不保证在主线程执行；如需更新 UI，请切换到 `MainActor`。
    /// - Parameters:
    ///   - failure: 已标准化的统一失败信息。
    ///   - request: 发生失败的 URL 请求；无法获取时为 `nil`。
    open func handleFailure(_ failure: CryoFailure, request: URLRequest?) {}

    /// 获取拦截器配置信息
    /// - Returns: 配置信息字典
    public func getInterceptorConfig() -> [String: Any] {
        [
            "interceptorType": String(describing: type(of: self))
        ]
    }

    // MARK: - 私有实现方法

    /// 完整响应场景处理
    /// - Returns: 处理结果
    private func processCompleteResponseData(
        data: Data,
        response: HTTPURLResponse
    ) -> Result<Data, Error> {
        let statusCode = response.statusCode
        if let httpError = handleHTTPStatusCode(statusCode) {
            return .failure(httpError)
        }
        do {
            let json = try JSON(data: data)
            if !isResponseSuccess(json: json) {
                return handleCustomError(
                    jsonData: data,
                    httpResponse: response,
                    isCompleteResponse: true
                )
            } else {
                return .success(data)
            }
        } catch {
            return .failure(handleJSONError(error, statusCode: statusCode, originalData: data))
        }
    }

    /// 指定业务数据响应处理
    /// - Returns: 处理结果
    private func processSpecificResponseData(
        data: Data,
        response: HTTPURLResponse
    ) -> Result<Data, Error> {
        let statusCode = response.statusCode
        if let httpError = handleHTTPStatusCode(statusCode) {
            return .failure(httpError)
        }
        do {
            let json = try JSON(data: data)
            if !isResponseSuccess(json: json) {
                return handleCustomError(
                    jsonData: data,
                    httpResponse: response,
                    isCompleteResponse: false
                )
            } else {
                return extractSuccessData(from: json, data: data)
            }
        } catch {
            return .failure(handleJSONError(error, statusCode: statusCode, originalData: data))
        }
    }

    /// 业务错误组装
    /// - Returns: 错误结果
    private func processErrorResponseData(
        jsonData: Data,
        httpResponse: HTTPURLResponse,
        isCompleteResponse: Bool
    ) -> Result<Data, Error> {
        let json = try? JSON(data: jsonData)
        let message = json.flatMap {
            responseConfig.extractFailureReason(from: $0, originalData: jsonData)
        } ?? "拦截器未获取到失败原因"
        let businessCode = json.flatMap {
            responseConfig.extractBusinessCode(from: $0, originalData: jsonData)
        }
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            "statusCode": httpResponse.statusCode,
            "interceptorConfig": getInterceptorConfig(),
            "originalData": jsonData
        ]
        if let businessCode = businessCode {
            userInfo["businessCode"] = businessCode
            userInfo["responseCode"] = businessCode
        }
        if isCompleteResponse {
            userInfo["responseData"] = jsonData
        }
        return .failure(NSError(
            domain: "BusinessError",
            code: businessCode ?? httpResponse.statusCode,
            userInfo: userInfo
        ))
    }

    // MARK: - Error Handling

    /// AFError 统一封装
    /// - Returns: NSError
    private func handleAFError(_ error: AFError) -> Error {
        var userInfo: [String: Any] = [
            "interceptorConfig": getInterceptorConfig()
        ]
        switch error {
        case .sessionTaskFailed(let underlyingError as URLError):
            return handleURLError(underlyingError)
        case .responseSerializationFailed:
            userInfo[NSLocalizedDescriptionKey] = "数据解析失败"
            userInfo[NSUnderlyingErrorKey] = error
            return NSError(domain: "SerializationError", code: -1002, userInfo: userInfo)
        case .responseValidationFailed:
            userInfo[NSLocalizedDescriptionKey] = "响应验证失败"
            userInfo[NSUnderlyingErrorKey] = error
            return NSError(domain: "ValidationError", code: -1003, userInfo: userInfo)
        case .requestAdaptationFailed(let error):
            userInfo[NSLocalizedDescriptionKey] = "请求适配失败"
            userInfo[NSUnderlyingErrorKey] = error
            return NSError(domain: "RequestError", code: -1005, userInfo: userInfo)
        case .explicitlyCancelled:
            userInfo[NSLocalizedDescriptionKey] = "请求已取消"
            return NSError(domain: "CancellationError", code: -1006, userInfo: userInfo)
        default:
            userInfo[NSLocalizedDescriptionKey] = error.localizedDescription
            userInfo[NSUnderlyingErrorKey] = error
            return NSError(domain: "NetworkError", code: -1000, userInfo: userInfo)
        }
    }

    /// URLError 单独处理
    /// - Returns: NSError
    private func handleURLError(_ error: URLError) -> Error {
        let (message, code): (String, Int) = {
            switch error.code {
            case .timedOut: return ("请求超时", -1007)
            case .notConnectedToInternet: return ("网络连接已断开", -1008)
            case .cannotConnectToHost: return ("无法连接到服务器", -1009)
            case .networkConnectionLost: return ("网络连接丢失", -1010)
            case .secureConnectionFailed: return ("安全连接失败", -1011)
            default: return (error.localizedDescription, error.errorCode)
            }
        }()
        let userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            NSUnderlyingErrorKey: error,
            "interceptorConfig": getInterceptorConfig()
        ]
        return NSError(domain: "URLError", code: code, userInfo: userInfo)
    }

    /// HTTP 状态码错误处理。
    ///
    /// 非 2xx 时构造标准化错误，并返回给统一失败分发链路。
    /// - Parameters:
    ///   - statusCode: HTTP 状态码。
    ///   - data: 原始响应体。
    ///   - underlyingError: Alamofire 或 URLSession 产生的底层错误。
    /// - Returns: 非 2xx 时返回标准化错误，2xx 时返回 `nil`。
    private func handleHTTPStatusCode(
        _ statusCode: Int,
        data: Data? = nil,
        underlyingError: Error? = nil
    ) -> Error? {
        guard statusCode < 200 || statusCode >= 300 else { return nil }
        let (message, domain): (String, String) = {
            switch statusCode {
            case 400: return ("请求参数错误", "ClientError")
            case 401: return ("身份验证失败", "AuthError")
            case 403: return ("访问被拒绝", "AuthError")
            case 404: return ("资源未找到", "ClientError")
            case 405: return ("方法不被允许", "ClientError")
            case 500..<600: return ("服务器错误", "ServerError")
            default: return ("未知HTTP错误", "HTTPError")
            }
        }()
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            "statusCode": statusCode,
            "responseCode": statusCode,
            "interceptorConfig": getInterceptorConfig()
        ]
        if let data = data {
            userInfo["originalData"] = data
            userInfo["responseData"] = data
        }
        if let underlyingError = underlyingError {
            userInfo[NSUnderlyingErrorKey] = underlyingError
        }
        return NSError(domain: domain, code: statusCode, userInfo: userInfo)
    }

    // MARK: - Utilities

    /// 构造 NSError
    /// - Returns: NSError
    private func makeError(
        domain: String,
        code: Int,
        message: String,
        underlyingError: Error? = nil
    ) -> NSError {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            "interceptorConfig": getInterceptorConfig()
        ]
        if let underlyingError = underlyingError {
            userInfo[NSUnderlyingErrorKey] = underlyingError
        }
        if let afError = underlyingError as? AFError {
            userInfo["AFErrorDescription"] = afError.errorDescription
        }
        return NSError(domain: domain, code: code, userInfo: userInfo)
    }

    /// JSON 解析错误加强
    /// - Returns: NSError
    private func handleJSONError(_ error: Error, statusCode: Int, originalData: Data? = nil) -> Error {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: "JSON解析失败: \(error.localizedDescription)",
            NSUnderlyingErrorKey: error,
            "interceptorConfig": getInterceptorConfig()
        ]
        if let originalData = originalData {
            userInfo["originalData"] = originalData
            if let dataString = String(data: originalData, encoding: .utf8) {
                userInfo["originalDataString"] = dataString
            }
        }
        return NSError(domain: "DataError", code: statusCode, userInfo: userInfo)
    }
}

// MARK: - Alamofire 适配器实现

/// InterceptorAdapter
///
/// Alamofire RequestInterceptor 适配器，自动注入 token 并处理 401 自动刷新。
class InterceptorAdapter: RequestInterceptor, @unchecked Sendable {
    private let interceptor: RequestInterceptorProtocol?
    private let tokenManager: TokenManagerProtocol
    private let authenticationSession: AuthenticationSessionManaging?
    private let authenticationContext: RequestAuthenticationContext?

    /// 初始化适配器
    /// - Parameters:
    ///   - interceptor: 拦截器
    ///   - tokenManager: tokenManager
    ///   - authenticationSession: 可选认证会话状态管理器。
    ///   - authenticationContext: 用于保存请求首次适配时会话 revision 的上下文。
    init(
        interceptor: RequestInterceptorProtocol? = nil,
        tokenManager: TokenManagerProtocol? = nil,
        authenticationSession: AuthenticationSessionManaging? = nil,
        authenticationContext: RequestAuthenticationContext? = nil
    ) {
        self.interceptor = interceptor
        self.tokenManager = tokenManager ?? DefaultTokenManager()
        self.authenticationSession = authenticationSession
        self.authenticationContext = authenticationContext
    }

    /// 请求适配，自动注入 token
    /// - Returns: 适配后的 URLRequest
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        Task {
            if let authenticationSession, let authenticationContext {
                let snapshot = await authenticationSession.snapshot()
                authenticationContext.captureIfNeeded(snapshot.revision)
            }
            if let modifiedRequest = await interceptor?.interceptRequest(urlRequest, tokenManager: tokenManager) {
                completion(.success(modifiedRequest))
            } else {
                completion(.success(urlRequest))
            }
        }
    }

    /// 401 自动重试刷新 token
    /// - Returns: RetryResult
    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        Task {
            if let afError = error as? AFError, afError.responseCode == 401 {
                let newToken = await tokenManager.refreshToken()
                if newToken != nil {
                    completion(.retry)
                    return
                }
            }
            completion(.doNotRetry)
        }
    }
}
