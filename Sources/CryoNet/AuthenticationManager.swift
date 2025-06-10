import Foundation
import Alamofire
import SwiftyJSON

// MARK: - 响应结构配置协议
/// 响应结构配置协议
public protocol ResponseStructureConfig: Sendable {
    /// 状态码字段的key
    var codeKey: String { get }
    
    /// 消息字段的key
    var messageKey: String { get }
    
    /// 数据字段的key
    var dataKey: String { get }
    
    /// 成功状态码
    var successCode: Int { get }
    
    /// 判断响应是否成功
    func isSuccess(json: JSON) -> Bool
    
    /// 从JSON中提取数据
    func extractData(from json: JSON, originalData: Data) -> Result<Data, Error>
}

// MARK: - 默认响应结构配置
/// 默认响应结构配置
open class DefaultResponseStructure: ResponseStructureConfig, @unchecked Sendable {
    
    // 请求状态码key值
    public let codeKey: String
    // 返回说明
    public let messageKey: String
    // 请求结果Key值
    public let dataKey: String
    // 成功状态
    public let successCode: Int
    
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
    
    open func isSuccess(json: JSON) -> Bool {
        return json[codeKey].intValue == successCode
    }
    
    open func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        let targetData = json[dataKey]
        
        // 如果不存在或者是 null，直接返回原始 data
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
    
    // 获取配置信息
    public func getConfigInfo() -> [String: Any] {
        return [
            "codeKey": codeKey,
            "messageKey": messageKey,
            "dataKey": dataKey,
            "successCode": successCode
        ]
    }
}

// MARK: - 嵌套响应结构配置
/// 嵌套响应结构配置
public struct NestedResponseStructure: ResponseStructureConfig {
    public let codeKey: String
    public let messageKey: String
    public let dataKey: String
    public let successCode: Int
    public let resultKey: String
    
    public init(
        codeKey: String,
        messageKey: String,
        dataKey: String,
        successCode: Int,
        resultKey: String
    ) {
        self.codeKey = codeKey
        self.messageKey = messageKey
        self.dataKey = dataKey
        self.successCode = successCode
        self.resultKey = resultKey
    }
    
    public func isSuccess(json: JSON) -> Bool {
        return json[codeKey].intValue == successCode
    }
    
    public func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        // 先获取result对象
        let resultData = json[resultKey]
        
        // 如果result不存在，返回原始数据
        if !resultData.exists() || resultData.type == .null {
            return .success(originalData)
        }
        
        // 从result中获取data
        let targetData = resultData[dataKey]
        
        // 如果不存在或者是 null，直接返回result数据
        if !targetData.exists() || targetData.type == .null {
            do {
                return .success(try resultData.rawData())
            } catch {
                return .success(originalData)
            }
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
    
    // 获取配置信息
    public func getConfigInfo() -> [String: Any] {
        return [
            "codeKey": codeKey,
            "messageKey": messageKey,
            "dataKey": dataKey,
            "successCode": successCode,
            "resultKey": resultKey
        ]
    }
}

// MARK: - 响应结构配置工厂方法
public extension ResponseStructureConfig {
    /// 创建标准响应结构配置
    static func standard(
        codeKey: String = "code",
        messageKey: String = "msg",
        dataKey: String = "data",
        successCode: Int = 200
    ) -> ResponseStructureConfig {
        return DefaultResponseStructure(
            codeKey: codeKey,
            messageKey: messageKey,
            dataKey: dataKey,
            successCode: successCode
        )
    }
    
    /// 创建嵌套响应结构配置
    static func nested(
        codeKey: String,
        messageKey: String,
        resultKey: String,
        dataKey: String,
        successCode: Int
    ) -> ResponseStructureConfig {
        return NestedResponseStructure(
            codeKey: codeKey,
            messageKey: messageKey,
            dataKey: dataKey,
            successCode: successCode,
            resultKey: resultKey
        )
    }
}

// MARK: - Token 管理协议与默认实现
/// Token 管理协议,继承该协议自己实现,也可继承自DefaultTokenManager重写方法
public protocol TokenManagerProtocol: Sendable {
    func getToken() async -> String?
    func setToken(_ newToken: String) async
    func refreshToken() async -> String?
}

/// Token 管理 actor(允许继承)
public actor DefaultTokenManager: TokenManagerProtocol {
    /// 令牌存储
    private var token: String?
    
    /// 获取当前的 Token
    public func getToken() async -> String? {
        return token
    }
    
    /// 设置新的 Token
    public func setToken(_ newToken: String) async {
        token = newToken
    }
    
    /// 刷新 Token
    public func refreshToken() async -> String? {
        // 默认实现：子类应当提供具体的刷新逻辑
        return nil
    }
    
    public init(token: String? = nil) {
        self.token = token
    }
}

// MARK: - 拦截器协议与默认实现
/// 拦截器协议,继承该协议自己实现,也可继承自DefaultInterceptor重写方法
public protocol RequestInterceptorProtocol: Sendable {
    /// 请求拦截
    func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest
    /// 响应拦截
    func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error>
    /// 走拦截器，但是响应完整数据
    func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error>
}

/// 默认拦截器(允许继承)
open class DefaultInterceptor: RequestInterceptorProtocol, InterceptorConfigProvider, @unchecked Sendable {
    
    // MARK: - Configuration
    private let responseConfig: ResponseStructureConfig
    
    /// 初始化方法
    /// - Parameters:
    ///   - responseConfig: 响应结构配置，默认使用标准配置
    public init(responseConfig: ResponseStructureConfig = DefaultResponseStructure()) {
        self.responseConfig = responseConfig
    }
    
    // 为了向后兼容，保留原来的初始化方法
    /// 初始化方法
    /// - Parameters:
    ///   - successCode: 成功状态码，默认 200
    ///   - successDataKey: 成功数据字段名，默认 "data"
    public convenience init(successCode: Int = 200, successDataKey: String = "data") {
        self.init(responseConfig: DefaultResponseStructure(
            codeKey: "code",
            messageKey: "msg",
            dataKey: successDataKey,
            successCode: successCode
        ))
    }
    
    // MARK: - Request Interception
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
    
    // MARK: - Response Interception
    /// 获取响应指定数据(只响应指定key值中的数据!!!)
    open func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        // 处理网络层错误
        if let error = response.error {
            return .failure(handleAFError(error))
        }
        
        // 验证基础响应
        guard let httpResponse = response.response else {
            return .failure(makeError(domain: "NetworkError", code: -1, message: "无效的服务器响应"))
        }
        
        // 处理数据转换
        guard let data = response.data else {
            return .failure(makeError(
                domain: "DataError",
                code: httpResponse.statusCode,
                message: "响应数据为空"
            ))
        }
        
        return processSpecificResponseData(data: data, response: httpResponse)
    }
    
    /// 获取响应为完整数据
    open func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        // 处理网络层错误
        if let error = response.error {
            return .failure(handleAFError(error))
        }
        
        // 验证基础响应
        guard let httpResponse = response.response else {
            return .failure(makeError(domain: "NetworkError", code: -1, message: "无效的服务器响应"))
        }
        
        // 处理数据转换
        guard let data = response.data else {
            return .failure(makeError(
                domain: "DataError",
                code: httpResponse.statusCode,
                message: "响应数据为空"
            ))
        }
        
        return processCompleteResponseData(data: data, response: httpResponse)
    }
    
    // MARK: - Public Customizable Methods
    /// 判断响应是否成功（可重写）
    /// - Parameters:
    ///   - json: 响应的JSON数据
    /// - Returns: 是否成功
    open func isResponseSuccess(json: JSON) -> Bool {
        return responseConfig.isSuccess(json: json)
    }
    
    /// 从JSON中提取成功数据（可重写）
    /// - Parameters:
    ///   - json: 响应的JSON数据
    ///   - data: 原始响应数据
    /// - Returns: 提取的数据结果
    open func extractSuccessData(from json: JSON, data: Data) -> Result<Data, Error> {
        return responseConfig.extractData(from: json, originalData: data)
    }
    
    /// 处理自定义错误（可重写）
    /// - Parameters:
    ///   - code: 业务状态码
    ///   - jsonData: 响应JSON数据
    ///   - httpResponse: HTTP响应
    ///   - isCompleteResponse: 是否返回完整响应
    /// - Returns: 处理结果
    open func handleCustomError(
        code: Int,
        jsonData: Data,
        httpResponse: HTTPURLResponse,
        isCompleteResponse: Bool
    ) -> Result<Data, Error> {
        return processErrorResponseData(
            code: code,
            jsonData: jsonData,
            httpResponse: httpResponse,
            isCompleteResponse: isCompleteResponse
        )
    }
    
    // MARK: - InterceptorConfigProvider 实现
    /// 获取拦截器配置信息
    public func getInterceptorConfig() -> [String: Any] {
        var config: [String: Any] = [
            "interceptorType": String(describing: type(of: self))
        ]
        
        // 添加响应配置信息
        if let defaultConfig = responseConfig as? DefaultResponseStructure {
            config.merge(defaultConfig.getConfigInfo()) { (_, new) in new }
        } else if let nestedConfig = responseConfig as? NestedResponseStructure {
            config.merge(nestedConfig.getConfigInfo()) { (_, new) in new }
        } else {
            config["responseConfigType"] = String(describing: type(of: responseConfig))
        }
        
        return config
    }
    
    // MARK: - Private Implementation Methods
    
    /// 处理完整响应数据
    /// - Parameters:
    ///   - data: 响应数据
    ///   - response: HTTP响应
    /// - Returns: 处理结果
    private func processCompleteResponseData(
        data: Data,
        response: HTTPURLResponse
    ) -> Result<Data, Error> {
        let statusCode = response.statusCode
        
        // 先处理 HTTP 状态码
        if let httpError = handleHTTPStatusCode(statusCode) {
            return .failure(httpError)
        }
        
        do {
            let json = try JSON(data: data)
            
            // 获取业务状态码
            let code = json[responseConfig.codeKey].intValue
            
            // 判断响应是否成功
            if !isResponseSuccess(json: json) {
                // 走业务错误处理
                return handleCustomError(
                    code: code,
                    jsonData: data,
                    httpResponse: response,
                    isCompleteResponse: true
                )
            } else {
                // 业务正常，返回成功
                return .success(data)
            }
            
        } catch {
            // JSON解析失败 - 增强错误信息
            let parsingError = handleJSONError(error, statusCode: statusCode, originalData: data)
            return .failure(parsingError)
        }
    }
    
    /// 处理指定响应数据
    /// - Parameters:
    ///   - data: 响应数据
    ///   - response: HTTP响应
    /// - Returns: 处理结果
    private func processSpecificResponseData(
        data: Data,
        response: HTTPURLResponse
    ) -> Result<Data, Error> {
        let statusCode = response.statusCode
        
        // 先处理 HTTP 状态码
        if let httpError = handleHTTPStatusCode(statusCode) {
            return .failure(httpError)
        }
        
        do {
            let json = try JSON(data: data)
            
            // 获取业务状态码
            let code = json[responseConfig.codeKey].intValue
            
            // 判断响应是否成功
            if !isResponseSuccess(json: json) {
                // 走业务错误处理
                return handleCustomError(
                    code: code,
                    jsonData: data,
                    httpResponse: response,
                    isCompleteResponse: false
                )
            } else {
                // 业务正常，提取指定数据
                return extractSuccessData(from: json, data: data)
            }
            
        } catch {
            // JSON解析失败 - 增强错误信息
            let parsingError = handleJSONError(error, statusCode: statusCode, originalData: data)
            return .failure(parsingError)
        }
    }
    
    /// 处理错误响应数据
    /// - Parameters:
    ///   - code: 业务状态码
    ///   - jsonData: 响应JSON数据
    ///   - httpResponse: HTTP响应
    ///   - isCompleteResponse: 是否返回完整响应
    /// - Returns: 处理结果
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
            "interceptorConfig": getInterceptorConfig()
        ]
        
        // 始终包含原始响应数据，以便调试
        userInfo["originalData"] = jsonData
        
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
    /// **错误处理**
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
    
    private func handleURLError(_ error: URLError) -> Error {
        let (message, code) = switch error.code {
        case .timedOut: ("请求超时", -1007)
        case .notConnectedToInternet: ("网络连接已断开", -1008)
        case .cannotConnectToHost: ("无法连接到服务器", -1009)
        case .networkConnectionLost: ("网络连接丢失", -1010)
        case .secureConnectionFailed: ("安全连接失败", -1011)
        default: (error.localizedDescription, error.errorCode)
        }
        
        let userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            NSUnderlyingErrorKey: error,
            "interceptorConfig": getInterceptorConfig()
        ]
        
        return NSError(domain: "URLError", code: code, userInfo: userInfo)
    }
    
    private func handleHTTPStatusCode(_ statusCode: Int) -> Error? {
        guard statusCode < 200 || statusCode >= 300 else { return nil }
        
        var message: String
        var domain: String
        
        switch statusCode {
        case 400:
            message = "请求参数错误"
            domain = "ClientError"
        case 401:
            message = "身份验证失败"
            domain = "AuthError"
        case 403:
            message = "访问被拒绝"
            domain = "AuthError"
        case 404:
            message = "资源未找到"
            domain = "ClientError"
        case 405:
            message = "方法不被允许"
            domain = "ClientError"
        case 500..<600:
            message = "服务器错误"
            domain = "ServerError"
        default:
            message = "未知HTTP错误"
            domain = "HTTPError"
        }
        
        let userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            "interceptorConfig": getInterceptorConfig()
        ]
        
        return NSError(domain: domain, code: statusCode, userInfo: userInfo)
    }
    
    // MARK: - Utilities
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
    
    private func handleJSONError(_ error: Error, statusCode: Int, originalData: Data? = nil) -> Error {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: "JSON解析失败: \(error.localizedDescription)",
            NSUnderlyingErrorKey: error,
            "interceptorConfig": getInterceptorConfig()
        ]
        
        // 添加原始数据以便调试
        if let originalData = originalData {
            userInfo["originalData"] = originalData
            
            // 尝试将原始数据转换为字符串，以便更好地调试
            if let dataString = String(data: originalData, encoding: .utf8) {
                userInfo["originalDataString"] = dataString
            }
        }
        
        return NSError(domain: "DataError", code: statusCode, userInfo: userInfo)
    }
}

// MARK: - 适配器实现
class InterceptorAdapter: RequestInterceptor, @unchecked Sendable {
    private let interceptor: RequestInterceptorProtocol
    private let tokenManager: TokenManagerProtocol
    
    init(interceptor: RequestInterceptorProtocol, tokenManager: TokenManagerProtocol) {
        self.interceptor = interceptor
        self.tokenManager = tokenManager
    }
    
    // 适配请求
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        Task {
            let modifiedRequest = await interceptor.interceptRequest(urlRequest, tokenManager: tokenManager)
            completion(.success(modifiedRequest))
        }
    }
    
    // 自动重试
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
