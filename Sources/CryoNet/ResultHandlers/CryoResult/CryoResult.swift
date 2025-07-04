import Foundation
import SwiftyJSON
import Alamofire

// MARK: - CryoResult 核心功能

/// `CryoResult` 封装了 Alamofire 的数据请求处理功能，支持同步与异步响应回调、模型解码、拦截器集成等能力。
///
/// 常用于链式响应处理，支持 JSON、模型、模型数组等多种格式，便于统一管理请求响应逻辑。
///
/// ### 使用示例
/// ```swift
/// cryoNet.request(model)
///     .responseJSON { json in ... }
///     .responseModel(type: User.self) { user in ... }
///     .interceptModel(type: User.self) { user in ... }
/// ```
@available(macOS 10.15, iOS 13, *)
public struct CryoResult: Sendable {
    /// Alamofire 请求对象
    public let request: DataRequest
    /// 请求拦截器 (可选)
    let interceptor: RequestInterceptorProtocol?

    /// 初始化
    /// - Parameters:
    ///   - request: 数据请求对象
    ///   - interceptor: 拦截器
    init(
        request: DataRequest,
        interceptor: RequestInterceptorProtocol? = nil
    ){
        self.request = request
        self.interceptor = interceptor
    }

    /// 调试请求日志（仅 DEBUG 模式打印）
    /// - Parameters:
    ///   - data: 响应数据
    ///   - error: 错误信息
    ///   - fromInterceptor: 是否来源于拦截器
    ///   - interceptorInfo: 拦截器配置信息
    ///   - noInterceptor: 是否未配置拦截器
    internal func debugRequestLog(_ data: Data?, error: String? = nil, fromInterceptor: Bool, interceptorInfo: [String: Any]? = nil, noInterceptor: Bool = false) {
        #if DEBUG
        guard let request = self.request.request else {
            debugLog("无效的请求,请检查 \(error ?? "")")
            return
        }
        let responseType = fromInterceptor ? "响应拦截器数据:" : "响应完整数据:"
        let separator = "\n\n\n\n⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️⬇️"
        let endMark = "\n⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️⬆️\n"

        let urlString = request.url?.absoluteString ?? "未知URL"
        let httpBodyInfo = request.httpBody.flatMap { "\nhttpBody 参数: \(SwiftyJSONUtils.dataToPrettyJSONString($0))" } ?? ""
        let headersInfo = "\nheaders: \(request.headers.dictionary)"

        var logContent = separator

        logContent += "请求地址: \(urlString)"
        logContent += headersInfo
        logContent += httpBodyInfo

        // 添加拦截器配置信息（如果有）
        if let interceptorInfo = interceptorInfo, !interceptorInfo.isEmpty {
            logContent += "\n拦截器配置信息:"
            for (key, value) in interceptorInfo {
                logContent += "\n  - \(key): \(value)"
            }
        }
        if noInterceptor {
            logContent += "\n[提示] 未配置拦截器，返回原始数据"
        }

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

    /// 打印调试日志（仅 DEBUG）
    /// - Parameter message: 日志内容
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
    /// - Parameter progress: 进度闭包（0~1）
    /// - Returns: self
    @discardableResult
    public func progress(_ progress: @escaping (Double) -> Void) -> Self {
        request.uploadProgress { uploadProgress in
            progress(uploadProgress.fractionCompleted)
        }
        return self
    }
}

// MARK: - 错误统一处理协议

/// `CryoError` 统一错误协议，所有网络相关错误均实现该协议，便于统一处理
public protocol CryoError: Error {
    var localizedDescription: String { get }
}

extension AFError: CryoError {}
extension DecodingError: CryoError {}

/// 通用错误包装器，适配任意 Error
struct GenericCryoError: CryoError {
    let underlyingError: Error
    var localizedDescription: String { underlyingError.localizedDescription }
    init(_ error: Error) { self.underlyingError = error }
}

/// 拦截器错误包装器，包含拦截器配置和原始数据
struct InterceptorError: CryoError {
    let message: String
    let originalData: Data?
    let interceptorInfo: [String: Any]?
    var localizedDescription: String { message }
    init(message: String, originalData: Data? = nil, interceptorInfo: [String: Any]? = nil) {
        self.message = message
        self.originalData = originalData
        self.interceptorInfo = interceptorInfo
    }
}

// MARK: - 直接获取处理(完整数据,不走拦截器)

@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    /// 响应为原始 Data
    /// - Parameters:
    ///   - success: 成功回调（Data）
    ///   - failed: 失败回调（CryoError）
    /// - Returns: self
    @discardableResult
    public func responseData(
        success: @escaping (Data) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> Self {
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

    /// 响应为 SwiftyJSON
    /// - Parameters:
    ///   - success: 成功回调
    ///   - failed: 失败回调
    /// - Returns: self
    @discardableResult
    public func responseJSON(
        success: @escaping (JSON) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> Self {
        handleResponse { response in
            switch response.result {
            case .success(let data):
                do {
                    let json = try JSON(data: data)
                    debugRequestLog(data, fromInterceptor: false)
                    success(json)
                } catch {
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

    /// 响应为单模型解码
    /// - Parameters:
    ///   - type: 模型类型
    ///   - success: 成功回调
    ///   - failed: 失败回调
    /// - Returns: self
    @discardableResult
    public func responseModel<T: Decodable>(
        type: T.Type,
        success: @escaping (T) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> Self {
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

    /// 响应为模型数组解码
    /// - Parameters:
    ///   - type: 模型类型
    ///   - success: 成功回调
    ///   - failed: 失败回调
    /// - Returns: self
    @discardableResult
    public func responseModelArray<T: Decodable>(
        type: T.Type,
        success: @escaping ([T]) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> Self {
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
    /// 获取拦截器配置信息（用于日志和错误包装）
    func getInterceptorInfo() -> [String: Any]? {
        if let configProvider = interceptor as? InterceptorConfigProvider {
            return configProvider.getInterceptorConfig()
        }
        return nil
    }

    /// 拦截器响应并解码单个模型
    /// - Parameters:
    ///   - type: 模型类型
    ///   - success: 成功回调
    ///   - failed: 失败回调（错误信息 String）
    /// - Returns: self
    @discardableResult
    public func interceptModel<T: Codable>(
        type: T.Type,
        success: @escaping (T) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> Self {
        self.request.response { response in
            let interceptorInfo = self.getInterceptorInfo()
            let originalData = response.data

            guard let interceptor = self.interceptor else {
                // 未配置拦截器，直接返回原始数据
                if let data = originalData {
                    do {
                        let model = try JSONDecoder().decode(T.self, from: data)
                        debugRequestLog(data, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                        success(model)
                    } catch {
                        let errorMessage = "未配置拦截器，原始数据解析失败: \(error.localizedDescription)"
                        failed(errorMessage)
                        debugRequestLog(data, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                    }
                } else {
                    let errorMessage = "未配置拦截器，且无原始数据"
                    failed(errorMessage)
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                }
                return
            }

            switch interceptor.interceptResponse(response) {
            case .success(let data):
                do {
                    let model = try JSONDecoder().decode(T.self, from: data)
                    debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    success(model)
                } catch {
                    let errorMessage = "DataToModel失败: \(error.localizedDescription)"
                    failed(errorMessage)
                    debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                failed(errorMessage)
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }

    /// 拦截器响应完整数据并解码模型
    @discardableResult
    public func interceptModelCompleteData<T: Codable>(
        type: T.Type,
        success: @escaping (T) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> Self {
        self.request.response { response in
            let interceptorInfo = self.getInterceptorInfo()
            let originalData = response.data

            guard let interceptor = self.interceptor else {
                if let data = originalData {
                    do {
                        let model = try JSONDecoder().decode(T.self, from: data)
                        debugRequestLog(data, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                        success(model)
                    } catch {
                        let errorMessage = "未配置拦截器，原始数据解析失败: \(error.localizedDescription)"
                        failed(errorMessage)
                        debugRequestLog(data, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                    }
                } else {
                    let errorMessage = "未配置拦截器，且无原始数据"
                    failed(errorMessage)
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                }
                return
            }

            switch interceptor.interceptResponseWithCompleteData(response) {
            case .success(let data):
                do {
                    let model = try JSONDecoder().decode(T.self, from: data)
                    debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    success(model)
                } catch {
                    let errorMessage = "DataToModel失败: \(error.localizedDescription)"
                    failed(errorMessage)
                    debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                failed(errorMessage)
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }

    /// 拦截器响应完整数据并解码 SwiftyJSON
    @discardableResult
    public func interceptJSON(
        success: @escaping (JSON) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> Self {
        self.request.response { response in
            let interceptorInfo = self.getInterceptorInfo()
            let originalData = response.data

            guard let interceptor = self.interceptor else {
                if let data = originalData {
                    do {
                        let json = try JSON(data: data)
                        debugRequestLog(data, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                        success(json)
                    } catch {
                        let errorMessage = "未配置拦截器，原始数据JSON解析失败: \(error.localizedDescription)"
                        failed(errorMessage)
                        debugRequestLog(data, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                    }
                } else {
                    let errorMessage = "未配置拦截器，且无原始数据"
                    failed(errorMessage)
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                }
                return
            }

            switch interceptor.interceptResponseWithCompleteData(response) {
            case .success(let data):
                do {
                    let json = try JSON(data: data)
                    debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    success(json)
                } catch {
                    let errorMessage = "JSON解析失败: \(error.localizedDescription)"
                    failed(errorMessage)
                    debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                failed(errorMessage)
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }

    /// 拦截器响应模型数组
    @discardableResult
    public func interceptModelArray<T: Codable>(
        type: T.Type,
        success: @escaping ([T]) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> Self {
        self.request.response { response in
            let interceptorInfo = self.getInterceptorInfo()
            let originalData = response.data

            guard let interceptor = self.interceptor else {
                if let data = originalData {
                    do {
                        let modelArray = try JSONDecoder().decode([T].self, from: data)
                        debugRequestLog(data, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                        success(modelArray)
                    } catch {
                        let errorMessage = "未配置拦截器，原始数据数组解析失败: \(error.localizedDescription)"
                        failed(errorMessage)
                        debugRequestLog(data, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                    }
                } else {
                    let errorMessage = "未配置拦截器，且无原始数据"
                    failed(errorMessage)
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                }
                return
            }

            switch interceptor.interceptResponse(response) {
            case .success(let data):
                do {
                    let modelArray = try JSONDecoder().decode([T].self, from: data)
                    debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    success(modelArray)
                } catch {
                    let errorMessage = "DataToModel数组失败: \(error.localizedDescription)"
                    failed(errorMessage)
                    debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                failed(errorMessage)
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }
}

// MARK: - 辅助功能

@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    /// 处理响应回调，封装 responseData
    /// - Parameter completion: 回调闭包
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
    /// - Returns: Data
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
    /// - Returns: JSON
    public func responseJSONAsync() async throws -> JSON {
        let data = try await responseDataAsync()
        do {
            return try JSON(data: data)
        } catch {
            throw GenericCryoError(error)
        }
    }

    /// 异步解码模型
    /// - Parameter type: 模型类型
    /// - Returns: 解码后的模型
    public func responseModelAsync<T: Decodable>(_ type: T.Type) async throws -> T {
        let data = try await responseDataAsync()
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            throw decodingError
        } catch {
            throw GenericCryoError(error)
        }
    }

    /// 异步解码模型数组
    /// - Parameter type: 模型类型
    /// - Returns: 解码后的模型数组
    public func responseModelArrayAsync<T: Decodable>(_ type: T.Type) async throws -> [T] {
        let data = try await responseDataAsync()
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch let decodingError as DecodingError {
            throw decodingError
        } catch {
            throw GenericCryoError(error)
        }
    }
}

// MARK: - 拦截器处理 Async 扩展

@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    /// 统一拦截器错误处理，包装为 InterceptorError
    /// - Parameter error: 错误信息
    /// - Returns: Error
    internal func handleInterceptorError(_ error: String) -> Error {
        let interceptorInfo = getInterceptorInfo()
        return InterceptorError(
            message: error,
            interceptorInfo: interceptorInfo
        )
    }

    /// 异步拦截器获取模型
    /// - Parameter type: 模型类型(Codable)
    /// - Returns: 解码后的模型
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
    /// - Parameter type: 模型类型(Codable)
    /// - Returns: 解码后的模型
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
    /// 
    /// - Returns: JSON
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
    /// 
    /// - Parameter type: 模型类型(Codable)
    /// - Returns: 模型数组
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
