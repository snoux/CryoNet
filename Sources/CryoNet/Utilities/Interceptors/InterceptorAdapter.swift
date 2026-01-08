import Foundation
import Alamofire
import SwiftyJSON

// MARK: - 默认响应结构配置

/// 默认响应结构配置，适用于绝大多数标准接口响应。
///
/// 用于统一解析接口响应中的业务状态码、消息与数据部分。
open class DefaultResponseStructure: ResponseStructureConfig, @unchecked Sendable {

    /// 从 JSON 提取业务数据字段（可重写）
    open func extractJSON(from json: SwiftyJSON.JSON) -> SwiftyJSON.JSON {
        json[dataKey]
    }

    /// 状态码字段名
    public let codeKey: String
    /// 消息字段名
    public let messageKey: String
    /// 数据字段名
    public let dataKey: String
    /// 成功状态码
    public let successCode: Int

    /// 初始化方法
    /// - Parameters:
    ///   - codeKey: 状态码字段名
    ///   - messageKey: 消息字段名
    ///   - dataKey: 数据字段名
    ///   - successCode: 成功状态码
    public init(
        codeKey: String = "code",
        messageKey: String = "msg",
        dataKey: String = "data",
        successCode: Int = 200
    ) {
        self.codeKey = codeKey
        self.messageKey = messageKey
        self.dataKey = dataKey
        self.successCode = successCode
    }

    /// 判断响应是否成功
    /// - Returns: 是否业务成功
    open func isSuccess(json: JSON) -> Bool {
        return json[codeKey].intValue == successCode
    }

    /// 从 JSON 提取数据（可重写）
    /// - Returns: 提取的数据或错误
    open func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        return JSON.extractDataFromJSON(extractJSON(from: json), originalData: originalData)
    }

    /// 获取配置信息（便于调试）
    /// - Returns: 当前响应结构配置信息
    public func getConfigInfo() -> [String: Any] {
        return [
            "codeKey": codeKey,
            "messageKey": messageKey,
            "dataKey": dataKey,
            "successCode": successCode
        ]
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
///     codeKey: "code",
///     messageKey: "msg",
///     dataKey: "",
///     successCode: 0
/// ) { json, originalData in
///     return .success(originalData)
/// } isSuccess: { json in
///     json["code"].intValue == 0
/// }
/// ```
public struct ResponseConfig: ResponseStructureConfig, @unchecked Sendable {
    public let codeKey: String
    public let messageKey: String
    public let dataKey: String
    public let successCode: Int
    
    /// 自定义数据提取闭包
    private let extractDataHandler: @Sendable (JSON, Data) -> Result<Data, Error>
    /// 自定义成功判断闭包
    private let isSuccessHandler: @Sendable (JSON) -> Bool
    
    /// 初始化响应配置
    /// - Parameters:
    ///   - codeKey: 状态码字段名
    ///   - messageKey: 消息字段名
    ///   - dataKey: 数据字段名
    ///   - successCode: 成功状态码
    ///   - extractData: 可选的自定义数据提取闭包，返回提取的数据或错误。如果为 nil 则使用默认逻辑
    ///   - isSuccess: 可选的自定义成功判断闭包，返回是否成功。如果为 nil 则使用默认逻辑
    public init(
        codeKey: String = "code",
        messageKey: String = "msg",
        dataKey: String = "data",
        successCode: Int = 200,
        extractData: ((JSON, Data) -> Result<Data, Error>)? = nil,
        isSuccess: ((JSON) -> Bool)? = nil
    ) {
        self.codeKey = codeKey
        self.messageKey = messageKey
        self.dataKey = dataKey
        self.successCode = successCode
        
        // 如果提供了自定义闭包，使用自定义闭包；否则使用默认逻辑
        if let extractData = extractData {
            self.extractDataHandler = { @Sendable json, originalData in
                extractData(json, originalData)
            }
        } else {
            // 默认实现：提取指定字段的 JSON，然后转换为 Data
            self.extractDataHandler = { @Sendable json, originalData in
                let extractedJSON = json[dataKey]
                return JSON.extractDataFromJSON(extractedJSON, originalData: originalData)
            }
        }
        
        if let isSuccess = isSuccess {
            self.isSuccessHandler = { @Sendable json in
                isSuccess(json)
            }
        } else {
            // 默认实现：判断状态码是否等于成功码
            self.isSuccessHandler = { @Sendable json in
                json[codeKey].intValue == successCode
            }
        }
    }
    
    /// 从 JSON 提取业务数据字段
    public func extractJSON(from json: JSON) -> JSON {
        json[dataKey]
    }
    
    /// 判断响应是否成功
    public func isSuccess(json: JSON) -> Bool {
        isSuccessHandler(json)
    }
    
    /// 从 JSON 提取数据
    public func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        extractDataHandler(json, originalData)
    }
}

// MARK: - 可继承、线程安全的默认实现

/// 默认 Token 管理器，线程安全，支持手动和自动刷新。
///
/// 通过 actor 保证并发安全，可自定义 token 刷新策略。
open class DefaultTokenManager: TokenManagerProtocol, @unchecked Sendable {
    private let storage = TokenStorageActor()

    /// 初始化，可指定初始 token
    /// - Parameter token: 初始 token
    public init(token: String? = nil) {
        if let token = token {
            Task { await storage.set(token) }
        }
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
open class DefaultInterceptor: RequestInterceptorProtocol, InterceptorConfigProvider, @unchecked Sendable {

    /// 响应结构配置
    public let responseConfig: ResponseStructureConfig

    /// 初始化，支持自定义响应结构
    /// - Parameter responseConfig: 指定响应结构配置
    public nonisolated init(responseConfig: ResponseStructureConfig = DefaultResponseStructure()) {
        self.responseConfig = responseConfig
    }

    /// 向后兼容老接口的便捷初始化
    /// - Parameters:
    ///   - successCode: 成功状态码
    ///   - successDataKey: 数据字段名
    public nonisolated convenience init(successCode: Int = 200, successDataKey: String = "data") {
        self.init(responseConfig: DefaultResponseStructure(
            codeKey: "code",
            messageKey: "msg",
            dataKey: successDataKey,
            successCode: successCode
        ))
    }
    
    /// 便捷初始化方法，支持闭包式快速配置（推荐使用）
    ///
    /// 无需创建类，直接使用闭包配置响应结构，简化配置过程。
    ///
    /// - Parameters:
    ///   - codeKey: 状态码字段名，默认 "code"
    ///   - messageKey: 消息字段名，默认 "msg"
    ///   - dataKey: 数据字段名，默认 "data"，传空字符串表示返回完整数据
    ///   - successCode: 成功状态码，默认 200
    ///   - extractData: 可选的自定义数据提取闭包，如果为 nil 则使用默认逻辑
    ///   - isSuccess: 可选的自定义成功判断闭包，如果为 nil 则使用默认逻辑
    ///
    /// ### 使用示例
    /// ```swift
    /// // 方式1：使用默认逻辑（最简单）
    /// let interceptor = DefaultInterceptor(
    ///     codeKey: "code",
    ///     messageKey: "msg",
    ///     dataKey: "data",
    ///     successCode: 0
    /// )
    ///
    /// // 方式2：自定义数据提取和成功判断
    /// let interceptor = DefaultInterceptor(
    ///     codeKey: "code",
    ///     messageKey: "msg",
    ///     dataKey: "data",
    ///     successCode: 0,
    ///     extractData: { json, originalData in
    ///         return .success(originalData)
    ///     },
    ///     isSuccess: { json in
    ///         json["code"].intValue == successCode // 告诉拦截器，请求是否成功（根据实际业务情况修改）
    ///     }
    /// )
    /// ```
    public nonisolated convenience init(
        codeKey: String = "code",
        messageKey: String = "msg",
        dataKey: String = "data",
        successCode: Int = 200,
        extractData: ((JSON, Data) -> Result<Data, Error>)? = nil,
        isSuccess: ((JSON) -> Bool)? = nil
    ) {
        let config = ResponseConfig(
            codeKey: codeKey,
            messageKey: messageKey,
            dataKey: dataKey,
            successCode: successCode,
            extractData: extractData.map { handler in
                { json, originalData in handler(json, originalData) }
            },
            isSuccess: isSuccess.map { handler in
                { json in handler(json) }
            }
        )
        self.init(responseConfig: config)
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
    /// - Returns: 业务数据或错误
    open func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
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
    /// - Returns: 完整响应体或错误
    open func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
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
    /// - Returns: 错误结果
    open func handleCustomError(
        code: Int,
        jsonData: Data,
        httpResponse: HTTPURLResponse,
        isCompleteResponse: Bool
    ) -> Result<Data, Error> {
        processErrorResponseData(
            code: code,
            jsonData: jsonData,
            httpResponse: httpResponse,
            isCompleteResponse: isCompleteResponse
        )
    }

    /// 获取拦截器配置信息
    /// - Returns: 配置信息字典
    public func getInterceptorConfig() -> [String: Any] {
        var config: [String: Any] = [
            "interceptorType": String(describing: type(of: self))
        ]
        if let defaultConfig = responseConfig as? DefaultResponseStructure{
            config.merge(defaultConfig.getConfigInfo()) { (_, new) in new }
        }else{
            let value =  [
                "codeKey": responseConfig.codeKey,
                "messageKey": responseConfig.messageKey,
                "dataKey": responseConfig.dataKey,
                "successCode": responseConfig.successCode
            ] as [String : Any]
            config.merge(value) { (_, new) in new }
        }
        return config
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
            let code = json[responseConfig.codeKey].intValue
            if !isResponseSuccess(json: json) {
                return handleCustomError(
                    code: code,
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
            let code = json[responseConfig.codeKey].intValue
            if !isResponseSuccess(json: json) {
                return handleCustomError(
                    code: code,
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
        code: Int,
        jsonData: Data,
        httpResponse: HTTPURLResponse,
        isCompleteResponse: Bool
    ) -> Result<Data, Error> {
        let json = try? JSON(data: jsonData)
        let message = json?[responseConfig.messageKey].string ?? "拦截器未获取到失败原因"
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            "statusCode": httpResponse.statusCode,
            "responseCode": code,
            "interceptorConfig": getInterceptorConfig(),
            "originalData": jsonData
        ]
        if isCompleteResponse {
            userInfo["responseData"] = jsonData
        }
        return .failure(NSError(
            domain: "BusinessError",
            code: code,
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

    /// HTTP 状态码错误处理
    /// - Returns: NSError 或 nil
    private func handleHTTPStatusCode(_ statusCode: Int) -> Error? {
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
        let userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            "interceptorConfig": getInterceptorConfig()
        ]
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

    /// 初始化适配器
    /// - Parameters:
    ///   - interceptor: 拦截器
    ///   - tokenManager: tokenManager
    init(interceptor: RequestInterceptorProtocol? = nil, tokenManager: TokenManagerProtocol? = nil) {
        self.interceptor = interceptor
        self.tokenManager = tokenManager ?? DefaultTokenManager()
    }

    /// 请求适配，自动注入 token
    /// - Returns: 适配后的 URLRequest
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        Task {
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
