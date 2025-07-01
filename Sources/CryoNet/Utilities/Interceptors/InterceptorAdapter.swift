import Foundation
import Alamofire
import SwiftyJSON


// MARK: - 默认响应结构配置
/**
 默认响应结构配置，适用于绝大多数标准接口响应。
 */
open class DefaultResponseStructure: ResponseStructureConfig, @unchecked Sendable {
    public let codeKey: String
    public let messageKey: String
    public let dataKey: String
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
    open func isSuccess(json: JSON) -> Bool {
        return json[codeKey].intValue == successCode
    }
    
    /// 从JSON提取数据
    open func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        let targetData = json[dataKey]
        // 如果不存在或为 null，直接返回原始 data
        if !targetData.exists() || targetData.type == .null {
            return .success(originalData)
        }
        do {
            let validData: Data
            switch targetData.type {
            case .dictionary, .array:
                validData = try targetData.rawData()
            case .string:
                validData = Data(targetData.stringValue.utf8)
            case .number, .bool:
                let stringValue = targetData.stringValue
                validData = Data(stringValue.utf8)
            default:
                return .success(originalData)
            }
            return .success(validData)
        } catch {
            return .failure(NSError(
                domain: "DataError",
                code: -1004,
                userInfo: [
                    NSLocalizedDescriptionKey: "数据转换失败",
                    NSUnderlyingErrorKey: error
                ]
            ))
        }
    }
    
    /// 获取配置信息（便于调试）
    public func getConfigInfo() -> [String: Any] {
        return [
            "codeKey": codeKey,
            "messageKey": messageKey,
            "dataKey": dataKey,
            "successCode": successCode
        ]
    }
}


// MARK: - 可继承、线程安全的默认实现
/**
 默认 Token 管理器，线程安全，支持手动和自动刷新。
 */
open class DefaultTokenManager: TokenManagerProtocol, @unchecked Sendable {
    private let storage = TokenStorageActor()
    
    public init(token: String? = nil) {
        if let token = token {
            Task { await storage.set(token) }
        }
    }
    
    /// 获取当前 Token
    open func getToken() async -> String? {
        await storage.get()
    }
    
    /// 设置新的 Token
    open func setToken(_ newToken: String) async {
        await storage.set(newToken)
    }
    
    /// 刷新 Token（需子类实现）
    open func refreshToken() async -> String? {
        nil
    }
}



// MARK: - 默认拦截器(允许继承)
/**
 默认实现，支持 token 注入、业务异常处理、结构化错误输出，支持响应结构配置定制。
 */
open class DefaultInterceptor: RequestInterceptorProtocol, InterceptorConfigProvider, @unchecked Sendable {
    public let responseConfig: ResponseStructureConfig
    
    /// 初始化，支持自定义响应结构
    public init(responseConfig: ResponseStructureConfig = DefaultResponseStructure()) {
        self.responseConfig = responseConfig
    }
    
    /// 向后兼容老接口
    public convenience init(successCode: Int = 200, successDataKey: String = "data") {
        self.init(responseConfig: DefaultResponseStructure(
            codeKey: "code",
            messageKey: "msg",
            dataKey: successDataKey,
            successCode: successCode
        ))
    }
    
    /// 请求拦截，自动注入 Bearer Token
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
    open func isResponseSuccess(json: JSON) -> Bool {
        responseConfig.isSuccess(json: json)
    }
    
    /// 从JSON中提取业务数据，可重写
    open func extractSuccessData(from json: JSON, data: Data) -> Result<Data, Error> {
        responseConfig.extractData(from: json, originalData: data)
    }
    
    /// 处理自定义业务错误，可重写
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
    
    // MARK: - Private Implementation Methods
    /// 完整响应场景处理
    private func processCompleteResponseData(
        data: Data,
        response: HTTPURLResponse
    ) -> Result<Data, Error> {
        let statusCode = response.statusCode
        // HTTP 状态码处理
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
    
    /// 指定数据响应处理
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
/**
 Alamofire RequestInterceptor 适配器，自动注入 token 并处理 401 自动刷新。
 */
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
