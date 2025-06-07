import Foundation
import Alamofire
import SwiftyJSON

// MARK: - Token 管理协议与默认实现
/// Token 管理协议,继承该协议自己实现,也可继承自DefaultTokenManager重写方法
public protocol TokenManagerProtocol: Sendable {
    func getToken() -> String?
    func setToken(_ newToken: String)
    func refreshToken() -> String?
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

/// Token 管理类
open class DefaultTokenManager: TokenManagerProtocol,@unchecked Sendable {
    /// 令牌存储，使用 private 保护，外部无法直接访问
    private var token: String?
    
    
    private let queue = DispatchQueue(label: "com.token.manager.queue", attributes: .concurrent)
    
    /// 获取当前的 Token
    public func getToken() -> String? {
        return queue.sync { token }
    }
    
    /// 设置新的 Token
    public func setToken(_ newToken: String) {
        queue.async(flags: .barrier) {
            self.token = newToken
        }
    }
    
    /// 刷新 Token（子类可重写）
    open func refreshToken() -> String? {
        // 默认实现：子类应当提供具体的刷新逻辑
        return nil
    }
    
    public init(token: String? = nil) {
        if let token = token {
            setToken(token)
        }
    }
}


// MARK: - 默认拦截器
/// 默认拦截器,可以继承重写
open class DefaultInterceptor: RequestInterceptorProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    public let successCode: Int
    private let successDataKey: String
    
    /// 初始化方法
    /// - Parameters:
    ///   - successCode: 成功状态码，默认 200
    ///   - successDataKey: 成功数据字段名，默认 "data"
    public init(successCode: Int = 200, successDataKey: String = "data") {
        self.successCode = successCode
        self.successDataKey = successDataKey
    }
    
    // MARK: - Request Interception
    open func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
        guard let token = tokenManager.getToken() else { return urlRequest }
        
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
    ///   - code: 响应中的状态码
    ///   - json: 响应的JSON数据
    /// - Returns: 是否成功
    open func isResponseSuccess(code: Int, json: JSON) -> Bool {
        return isSuccessResponse(code: code, json: json)
    }
    
    /// 从JSON中提取成功数据（可重写）
    /// - Parameters:
    ///   - json: 响应的JSON数据
    ///   - data: 原始响应数据
    /// - Returns: 提取的数据结果
    open func extractSuccessData(from json: JSON, data: Data) -> Result<Data, Error> {
        return extractDataFromJSON(json, originalData: data)
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
    
    // MARK: - Private Implementation Methods
    
    /// 判断响应是否成功
    /// - Parameters:
    ///   - code: 响应中的状态码
    ///   - json: 响应的JSON数据
    /// - Returns: 是否成功
    private func isSuccessResponse(code: Int, json: JSON) -> Bool {
        return code == successCode
    }
    
    /// 从JSON中提取成功数据
    /// - Parameters:
    ///   - json: 响应的JSON数据
    ///   - data: 原始响应数据
    /// - Returns: 提取的数据结果
    private func extractDataFromJSON(_ json: JSON, originalData data: Data) -> Result<Data, Error> {
        let targetData = json[successDataKey]
        
        // 如果不存在或者是 null，直接返回原始 data
        if !targetData.exists() || targetData.type == .null {
            return .success(data)
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
                return .success(data)
            }
            
            return .success(validData)
        } catch {
            return .failure(makeError(
                domain: "DataError",
                code: -1004,
                message: "数据转换失败",
                underlyingError: error
            ))
        }
    }
    
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
            let code = json["code"].intValue
            
            // 判断响应是否成功
            if !isResponseSuccess(code: code, json: json) {
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
            // JSON解析失败
            let parsingError = handleJSONError(error, statusCode: statusCode)
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
            let code = json["code"].intValue
            
            // 判断响应是否成功
            if !isResponseSuccess(code: code, json: json) {
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
            // JSON解析失败
            let parsingError = handleJSONError(error, statusCode: statusCode)
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
        let message = json?["msg"].string ?? "请求失败"
        
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: message,
            "statusCode": httpResponse.statusCode,
            "responseCode": code
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
    /// **错误处理**
    private func handleAFError(_ error: AFError) -> Error {
        switch error {
        case .sessionTaskFailed(let underlyingError as URLError):
            return handleURLError(underlyingError)
            
        case .responseSerializationFailed:
            return makeError(
                domain: "SerializationError",
                code: -1002,
                message: "数据解析失败",
                underlyingError: error
            )
            
        case .responseValidationFailed:
            return makeError(
                domain: "ValidationError",
                code: -1003,
                message: "响应验证失败",
                underlyingError: error
            )
            
        case .requestAdaptationFailed(let error):
            return makeError(
                domain: "RequestError",
                code: -1005,
                message: "请求适配失败",
                underlyingError: error
            )
            
        case .explicitlyCancelled:
            return makeError(
                domain: "CancellationError",
                code: -1006,
                message: "请求已取消"
            )
            
        default:
            return makeError(
                domain: "NetworkError",
                code: -1000,
                message: error.localizedDescription,
                underlyingError: error
            )
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
        
        return makeError(
            domain: "URLError",
            code: code,
            message: message,
            underlyingError: error
        )
    }
    
    private func handleHTTPStatusCode(_ statusCode: Int) -> Error? {
        switch statusCode {
        case 200..<300: return nil
        case 400: return makeError(domain: "ClientError", code: 400, message: "请求参数错误")
        case 401: return makeError(domain: "AuthError", code: 401, message: "身份验证失败")
        case 403: return makeError(domain: "AuthError", code: 403, message: "访问被拒绝")
        case 404: return makeError(domain: "ClientError", code: 404, message: "资源未找到")
        case 405: return makeError(domain: "ClientError", code: 405, message: "方法不被允许")
        case 500..<600: return makeError(domain: "ServerError", code: statusCode, message: "服务器错误")
        default: return makeError(domain: "HTTPError", code: statusCode, message: "未知HTTP错误")
        }
    }
    
    // MARK: - Utilities
    private func makeError(
        domain: String,
        code: Int,
        message: String,
        underlyingError: Error? = nil
    ) -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        userInfo[NSUnderlyingErrorKey] = underlyingError
        
        if let afError = underlyingError as? AFError {
            userInfo["AFErrorDescription"] = afError.errorDescription
        }
        
        return NSError(domain: domain, code: code, userInfo: userInfo)
    }
    
    private func handleJSONError(_ error: Error, statusCode: Int) -> Error {
        makeError(
            domain: "DataError",
            code: statusCode,
            message: "JSON解析失败: \(error.localizedDescription)",
            underlyingError: error
        )
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
                let newToken = tokenManager.refreshToken()
                if newToken != nil {
                    completion(.retry)
                    return
                }
            }
            completion(.doNotRetry)
        }
    }
}

