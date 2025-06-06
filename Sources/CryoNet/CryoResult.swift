import Foundation
import SwiftyJSON
import Alamofire

// MARK: - CryoResult 核心功能
/// CryoResult 封装了 Alamofire 的数据请求处理功能
@available(macOS 10.15, iOS 13, *)
public struct CryoResult: Sendable {
    public let request: DataRequest
    private let interceptor: RequestInterceptorProtocol
    
    /// 初始化方法
    /// - Parameters:
    ///   - request: 数据请求对象
    ///   - interceptor: 拦截器
    init(
        request: DataRequest,
        interceptor: RequestInterceptorProtocol
    ) {
        self.request = request
        self.interceptor = interceptor
    }
    
    private func debugRequestLog(_ data: Data?, error: String? = nil, fromInterceptor: Bool) {
        #if DEBUG
        guard let request = self.request.request else {
            debugLog("无效的请求,请检查 \(error ?? "")")
            return
        }
        
        let responseType = fromInterceptor ? "响应拦截器数据:" : "响应完整数据:"
        let separator = "\n\n\n\n⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️\n"
        let endMark = "\n⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️\n\n\n\n"
        
        let urlString = request.url?.absoluteString ?? "未知URL"
        let httpBodyInfo = request.httpBody.flatMap { "\nhttpBody 参数: \(SwiftyJSONUtils.dataToPrettyJSONString($0))" } ?? ""
        let headersInfo = "\nheaders: \(request.headers.dictionary)"
        
        var logContent = separator
        
        logContent += "请求地址: \(urlString)"
        logContent += headersInfo
        logContent += httpBodyInfo
        
        if let error = error {
            logContent += "\n\(responseType)失败!\(error)"
            if let responseData = data {
                logContent += "\n失败原因:\n\(SwiftyJSONUtils.dataToPrettyJSONString(responseData))"
            }
        } else if let responseData = data {
            logContent += "\n\(responseType)成功!\n\(SwiftyJSONUtils.dataToPrettyJSONString(responseData))"
        } else {
            logContent += "\n\(responseType)无数据返回"
        }
        
        logContent += endMark
        debugLog(logContent)
        #endif
    }
    
    private func debugLog(_ message: Any) {
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - 上传进度
@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    /// 上传进度回调
    /// - Parameter progress: 进度闭包
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func progress(_ progress: @escaping (Double) -> Void) -> CryoResult {
        request.uploadProgress { uploadProgress in
            progress(uploadProgress.fractionCompleted)
        }
        return self
    }
}

// MARK: - 错误统一处理协议
public protocol CryoError: Error {
    var localizedDescription: String { get }
}

extension AFError: CryoError {}
extension DecodingError: CryoError {}

// MARK: - 通用错误包装器
struct GenericCryoError: CryoError {
    let underlyingError: Error
    
    var localizedDescription: String {
        return underlyingError.localizedDescription
    }
    
    init(_ error: Error) {
        self.underlyingError = error
    }
}

// MARK: - 直接获取处理(完整数据,不走拦截器)
@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    
    /// 响应为data数据
    @discardableResult
    public func responseData(
        success: @escaping (Data) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        handleResponse { response in
            switch response.result {
            case .success(let data):
                debugRequestLog(data, fromInterceptor: false)
                success(data)
            case .failure(let error):
                failed(error)
                debugRequestLog(nil, error: error.localizedDescription, fromInterceptor: false)
            }
        }
        return self
    }
    
    /// 响应为 SwiftyJSON 对象
    @discardableResult
    public func responseJSON(
        success: @escaping (JSON) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        handleResponse { response in
            switch response.result {
            case .success(let data):
                do {
                    let json = try JSON(data: data)
                    debugRequestLog(data, fromInterceptor: false)
                    success(json)
                } catch {
                    // 修复类型转换错误：将普通Error包装为CryoError
                    let jsonError = GenericCryoError(error)
                    failed(jsonError)
                    debugRequestLog(data, error: "JSON解析失败: \(error.localizedDescription)", fromInterceptor: false)
                }
            case .failure(let error):
                failed(error)
                debugRequestLog(nil, error: error.localizedDescription, fromInterceptor: false)
            }
        }
        return self
    }

    /// 响应为模型
    @discardableResult
    public func responseModel<T: Decodable>(
        type: T.Type,
        success: @escaping (T) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        handleResponse { response in
            switch response.result {
            case .success(let data):
                do {
                    let model = try JSONDecoder().decode(T.self, from: data)
                    debugRequestLog(data, fromInterceptor: false)
                    success(model)
                } catch let error as DecodingError {
                    debugRequestLog(data, error: "Model 解析失败: \(error)", fromInterceptor: false)
                    failed(error)
                } catch {
                    // 修复类型转换错误：将普通Error包装为CryoError
                    let genericError = GenericCryoError(error)
                    debugRequestLog(data, error: "Model 解析失败: \(error)", fromInterceptor: false)
                    failed(genericError)
                }
            case .failure(let error):
                failed(error)
                debugRequestLog(nil, error: error.localizedDescription, fromInterceptor: false)
            }
        }
        return self
    }

    /// 响应为模型数组
    @discardableResult
    public func responseModelArray<T: Decodable>(
        type: T.Type,
        success: @escaping ([T]) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        handleResponse { response in
            switch response.result {
            case .success(let data):
                do {
                    let modelArray = try JSONDecoder().decode([T].self, from: data)
                    debugRequestLog(data, fromInterceptor: false)
                    success(modelArray)
                } catch let error as DecodingError {
                    debugRequestLog(data, error: "Model 数组解析失败: \(error)", fromInterceptor: false)
                    failed(error)
                } catch {
                    // 修复类型转换错误：将普通Error包装为CryoError
                    let genericError = GenericCryoError(error)
                    debugRequestLog(data, error: "Model 数组解析失败: \(error)", fromInterceptor: false)
                    failed(genericError)
                }
            case .failure(let error):
                failed(error)
                debugRequestLog(nil, error: error.localizedDescription, fromInterceptor: false)
            }
        }
        return self
    }
}

// MARK: - 从拦截器获取数据
@available(macOS 10.15, iOS 13, *)
extension CryoResult {

    // MARK: - 单个模型
    @discardableResult
    public func interceptModel<T: Codable>(
        type: T.Type,
        success: @escaping (T) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            switch self.interceptor.interceptResponse(response) {
            case .success(let data):
                do {
                    let model = try JSONDecoder().decode(T.self, from: data)
                    debugRequestLog(data, fromInterceptor: true)
                    success(model)
                } catch {
                    failed("DataToModel失败: \(error.localizedDescription)")
                    debugRequestLog(data, error: "DataToModel失败: \(error.localizedDescription)", fromInterceptor: true)
                }
            case .failure(let error):
                debugRequestLog(nil, error: error.localizedDescription, fromInterceptor: true)
                failed(error.localizedDescription)
            }
        }
        return self
    }
    
    // MARK: - 从拦截器完整数据
    @discardableResult
    public func interceptModelCompleteData<T: Codable>(
        type: T.Type,
        success: @escaping (T) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            switch self.interceptor.interceptResponseWithCompleteData(response) {
            case .success(let data):
                do {
                    let model = try JSONDecoder().decode(T.self, from: data)
                    debugRequestLog(data, fromInterceptor: true)
                    success(model)
                } catch {
                    failed("DataToModel失败: \(error.localizedDescription)")
                    debugRequestLog(data, error: "DataToModel失败: \(error.localizedDescription)", fromInterceptor: true)
                }
            case .failure(let error):
                debugRequestLog(nil, error: error.localizedDescription, fromInterceptor: true)
                failed(error.localizedDescription)
            }
        }
        return self
    }
    
    // MARK: - 从拦截器完整数据SwiftyJSON
    @discardableResult
    public func interceptJSON(
        success: @escaping (JSON) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            switch self.interceptor.interceptResponseWithCompleteData(response) {
            case .success(let data):
                do {
                    let json = try JSON(data: data)
                    debugRequestLog(data, fromInterceptor: true)
                    success(json)
                } catch {
                    failed("JSON解析失败: \(error.localizedDescription)")
                    debugRequestLog(data, error: "JSON解析失败: \(error.localizedDescription)", fromInterceptor: true)
                }
            case .failure(let error):
                debugRequestLog(nil, error: error.localizedDescription, fromInterceptor: true)
                failed(error.localizedDescription)
            }
        }
        return self
    }
    
    // MARK: - 模型数组
    @discardableResult
    public func interceptModelArray<T: Codable>(
        type: T.Type,
        success: @escaping ([T]) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            switch self.interceptor.interceptResponse(response) {
            case .success(let data):
                do {
                    let modelArray = try JSONDecoder().decode([T].self, from: data)
                    debugRequestLog(data, fromInterceptor: true)
                    success(modelArray)
                } catch {
                    failed("DataToModel数组失败: \(error.localizedDescription)")
                    debugRequestLog(data, error: "DataToModel数组失败: \(error.localizedDescription)", fromInterceptor: true)
                }
            case .failure(let error):
                debugRequestLog(nil, error: error.localizedDescription, fromInterceptor: true)
                failed(error.localizedDescription)
            }
        }
        return self
    }
}

// MARK: - 辅助功能
@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    /// 处理响应回调
    private func handleResponse(
        completion: @escaping (AFDataResponse<Data>) -> Void
    ) {
        request.responseData { response in
            completion(response)
        }
    }
}

// MARK: - 直接处理数据 Async 扩展
@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    /// 异步获取原始 Data 数据
    public func responseDataAsync() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            responseData { data in
                continuation.resume(returning: data)
            } failed: { error in
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// 异步获取 SwiftyJSON 对象
    public func responseJSONAsync() async throws -> JSON {
        let data = try await responseDataAsync()
        do {
            return try JSON(data: data)
        } catch {
            // 修复类型转换错误：包装为适当的错误类型
            throw GenericCryoError(error)
        }
    }
    
    /// 异步解码模型
    public func responseModelAsync<T: Decodable>(_ type: T.Type) async throws -> T {
        let data = try await responseDataAsync()
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw decodingError
        } catch {
            // 修复类型转换错误：包装为适当的错误类型
            throw GenericCryoError(error)
        }
    }
    
    /// 异步解码模型数组
    public func responseModelArrayAsync<T: Decodable>(_ type: T.Type) async throws -> [T] {
        let data = try await responseDataAsync()
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch let decodingError as DecodingError {
            throw decodingError
        } catch {
            // 修复类型转换错误：包装为适当的错误类型
            throw GenericCryoError(error)
        }
    }
}

// MARK: - 拦截器处理 Async 扩展
@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    /// 统一拦截器错误处理
    private func handleInterceptorError(_ error: String) -> Error {
        return NSError(
            domain: "InterceptorError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: error]
        )
    }
    
    /// 异步拦截器获取模型
    public func interceptModelAsync<T: Codable>(_ type: T.Type) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            interceptModel(type: type) { model in
                continuation.resume(returning: model)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }
    
    /// 异步拦截器获取完整数据模型
    public func interceptModelCompleteDataAsync<T: Codable>(_ type: T.Type) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            interceptModelCompleteData(type: type) { model in
                continuation.resume(returning: model)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }
    
    /// 异步拦截器获取完整 SwiftyJSON
    public func interceptJSONAsync() async throws -> JSON {
        return try await withCheckedThrowingContinuation { continuation in
            interceptJSON { json in
                continuation.resume(returning: json)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }
    
    /// 异步拦截器获取模型数组
    public func interceptModelArrayAsync<T: Codable>(_ type: T.Type) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            interceptModelArray(type: type) { models in
                continuation.resume(returning: models)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }
}

