import Foundation
import SwiftyJSON
import Alamofire

// MARK: - SwiftyJSON 模型转换扩展
@available(macOS 10.15, iOS 13, *)
extension CryoResult {
    
    /// 响应为 SwiftyJSON 对象，并直接转换为模型
    /// - Parameters:
    ///   - type: 目标模型类型
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
    ///   - success: 成功回调，返回转换后的模型
    ///   - failed: 失败回调，返回错误信息
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func responseJSONModel<T: JSONParseable>(
        type: T.Type,
        keyPath: String? = nil,
        success: @escaping (T) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        responseJSON { json in
            if let model = json.toModel(type, keyPath: keyPath) {
                success(model)
            } else {
                let error = AFError.responseSerializationFailed(
                    reason: .decodingFailed(
                        error: NSError(
                            domain: "JSONModelError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "SwiftyJSON转换模型失败"]
                        )
                    )
                )
                failed(error)
            }
        } failed: { error in
            failed(error)
        }
        return self
    }
    
    /// 响应为 SwiftyJSON 对象，并使用自定义解析闭包转换为模型
    /// - Parameters:
    ///   - parser: 自定义解析闭包
    ///   - success: 成功回调，返回转换后的模型
    ///   - failed: 失败回调，返回错误信息
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func responseJSONModel<T>(
        parser: @escaping (JSON) -> T?,
        success: @escaping (T) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        responseJSON { json in
            if let model = json.toModel(parser: parser) {
                success(model)
            } else {
                let error = AFError.responseSerializationFailed(
                    reason: .decodingFailed(
                        error: NSError(
                            domain: "JSONModelError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "SwiftyJSON自定义解析模型失败"]
                        )
                    )
                )
                failed(error)
            }
        } failed: { error in
            failed(error)
        }
        return self
    }
    
    /// 响应为 SwiftyJSON 对象，并直接转换为模型数组
    /// - Parameters:
    ///   - type: 目标模型类型
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
    ///   - success: 成功回调，返回转换后的模型数组
    ///   - failed: 失败回调，返回错误信息
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func responseJSONModelArray<T: JSONParseable>(
        type: T.Type,
        keyPath: String? = nil,
        success: @escaping ([T]) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        responseJSON { json in
            let modelArray = json.toModelArray(type, keyPath: keyPath)
            success(modelArray)
        } failed: { error in
            failed(error)
        }
        return self
    }
    
    /// 响应为 SwiftyJSON 对象，并使用自定义解析闭包转换为模型数组
    /// - Parameters:
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
    ///   - parser: 自定义解析闭包
    ///   - success: 成功回调，返回转换后的模型数组
    ///   - failed: 失败回调，返回错误信息
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func responseJSONModelArray<T>(
        keyPath: String? = nil,
        parser: @escaping (JSON) -> T?,
        success: @escaping ([T]) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        responseJSON { json in
            let modelArray = json.toModelArray(keyPath: keyPath, parser: parser)
            success(modelArray)
        } failed: { error in
            failed(error)
        }
        return self
    }
    
    // MARK: - 拦截器方法
    
    /// 从拦截器获取 SwiftyJSON 对象，并直接转换为模型
    /// - Parameters:
    ///   - type: 目标模型类型
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
    ///   - success: 成功回调，返回转换后的模型
    ///   - failed: 失败回调，返回错误信息
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func interceptJSONModel<T: JSONParseable>(
        type: T.Type,
        keyPath: String? = nil,
        success: @escaping (T) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            // 获取拦截器配置信息
            let interceptorInfo = self.getInterceptorInfo()
            
            // 保存原始响应数据用于调试
            let originalData = response.data
            
            switch self.interceptor.interceptResponseWithCompleteData(response) {
            case .success(let data):
                do {
                    let json = try JSON(data: data)
                    if let model = json.toModel(type, keyPath: keyPath) {
                        debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                        success(model)
                    } else {
                        let errorMessage = "SwiftyJSON转换模型失败，keyPath: \(keyPath ?? "nil")"
                        failed(errorMessage)
                        debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    }
                } catch {
                    let errorMessage = "JSON解析失败: \(error.localizedDescription)"
                    failed(errorMessage)
                    debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                failed(errorMessage)
                
                // 如果有原始数据，打印出来以便调试
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }
    
    /// 从拦截器获取 SwiftyJSON 对象，并使用自定义解析闭包转换为模型
    /// - Parameters:
    ///   - parser: 自定义解析闭包
    ///   - success: 成功回调，返回转换后的模型
    ///   - failed: 失败回调，返回错误信息
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func interceptJSONModel<T>(
        parser: @escaping (JSON) -> T?,
        success: @escaping (T) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            // 获取拦截器配置信息
            let interceptorInfo = self.getInterceptorInfo()
            
            // 保存原始响应数据用于调试
            let originalData = response.data
            
            switch self.interceptor.interceptResponseWithCompleteData(response) {
            case .success(let data):
                do {
                    let json = try JSON(data: data)
                    if let model = json.toModel(parser: parser) {
                        debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                        success(model)
                    } else {
                        let errorMessage = "SwiftyJSON自定义解析模型失败"
                        failed(errorMessage)
                        debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    }
                } catch {
                    let errorMessage = "JSON解析失败: \(error.localizedDescription)"
                    failed(errorMessage)
                    debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                failed(errorMessage)
                
                // 如果有原始数据，打印出来以便调试
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }
    
    /// 从拦截器获取 SwiftyJSON 对象，并直接转换为模型数组
    /// - Parameters:
    ///   - type: 目标模型类型
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
    ///   - success: 成功回调，返回转换后的模型数组
    ///   - failed: 失败回调，返回错误信息
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func interceptJSONModelArray<T: JSONParseable>(
        type: T.Type,
        keyPath: String? = nil,
        success: @escaping ([T]) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            // 获取拦截器配置信息
            let interceptorInfo = self.getInterceptorInfo()
            
            // 保存原始响应数据用于调试
            let originalData = response.data
            
            switch self.interceptor.interceptResponse(response) {
            case .success(let data):
                do {
                    let json = try JSON(data: data)
                    let modelArray = json.toModelArray(type, keyPath: keyPath)
                    debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    success(modelArray)
                } catch {
                    let errorMessage = "JSON解析失败: \(error.localizedDescription)"
                    failed(errorMessage)
                    debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                failed(errorMessage)
                
                // 如果有原始数据，打印出来以便调试
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }
    
    /// 从拦截器获取 SwiftyJSON 对象，并使用自定义解析闭包转换为模型数组
    /// - Parameters:
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
    ///   - parser: 自定义解析闭包
    ///   - success: 成功回调，返回转换后的模型数组
    ///   - failed: 失败回调，返回错误信息
    /// - Returns: 当前 CryoResult 对象
    @discardableResult
    public func interceptJSONModelArray<T>(
        keyPath: String? = nil,
        parser: @escaping (JSON) -> T?,
        success: @escaping ([T]) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            // 获取拦截器配置信息
            let interceptorInfo = self.getInterceptorInfo()
            
            // 保存原始响应数据用于调试
            let originalData = response.data
            
            switch self.interceptor.interceptResponse(response) {
            case .success(let data):
                do {
                    let json = try JSON(data: data)
                    let modelArray = json.toModelArray(keyPath: keyPath, parser: parser)
                    debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    success(modelArray)
                } catch {
                    let errorMessage = "JSON解析失败: \(error.localizedDescription)"
                    failed(errorMessage)
                    debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                failed(errorMessage)
                
                // 如果有原始数据，打印出来以便调试
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }
    
    // MARK: - Async 扩展
    
    /// 异步获取 SwiftyJSON 对象并转换为模型
    public func responseJSONModelAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> T {
        let json = try await responseJSONAsync()
        guard let model = json.toModel(type, keyPath: keyPath) else {
            throw AFError.responseSerializationFailed(
                reason: .decodingFailed(
                    error: NSError(
                        domain: "JSONModelError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "SwiftyJSON转换模型失败"]
                    )
                )
            )
        }
        return model
    }
    
    /// 异步获取 SwiftyJSON 对象并使用自定义解析闭包转换为模型
    public func responseJSONModelAsync<T>(parser: @escaping (JSON) -> T?) async throws -> T {
        let json = try await responseJSONAsync()
        guard let model = json.toModel(parser: parser) else {
            throw AFError.responseSerializationFailed(
                reason: .decodingFailed(
                    error: NSError(
                        domain: "JSONModelError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "SwiftyJSON自定义解析模型失败"]
                    )
                )
            )
        }
        return model
    }
    
    /// 异步获取 SwiftyJSON 对象并转换为模型数组
    public func responseJSONModelArrayAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> [T] {
        let json = try await responseJSONAsync()
        return json.toModelArray(type, keyPath: keyPath)
    }
    
    /// 异步获取 SwiftyJSON 对象并使用自定义解析闭包转换为模型数组
    public func responseJSONModelArrayAsync<T>(keyPath: String? = nil, parser: @escaping (JSON) -> T?) async throws -> [T] {
        let json = try await responseJSONAsync()
        return json.toModelArray(keyPath: keyPath, parser: parser)
    }
    
    /// 异步从拦截器获取 SwiftyJSON 对象并转换为模型
    public func interceptJSONModelAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            interceptJSONModel(type: type, keyPath: keyPath) { model in
                continuation.resume(returning: model)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }
    
    /// 异步从拦截器获取 SwiftyJSON 对象并使用自定义解析闭包转换为模型
    public func interceptJSONModelAsync<T>(parser: @escaping (JSON) -> T?) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            interceptJSONModel(parser: parser) { model in
                continuation.resume(returning: model)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }
    
    /// 异步从拦截器获取 SwiftyJSON 对象并转换为模型数组
    public func interceptJSONModelArrayAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            self.request.response { response in
                // 获取拦截器配置信息
                let interceptorInfo = self.getInterceptorInfo()
                
                // 保存原始响应数据用于调试
                let originalData = response.data
                
                switch self.interceptor.interceptResponse(response) {
                case .success(let data):
                    do {
                        let json = try JSON(data: data)
                        let modelArray = json.toModelArray(type, keyPath: keyPath)
                        self.debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                        continuation.resume(returning: modelArray)
                    } catch {
                        let errorMessage = "JSON解析失败: \(error.localizedDescription)"
                        self.debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                        continuation.resume(throwing: self.handleInterceptorError(errorMessage))
                    }
                case .failure(let error):
                    let errorMessage = error.localizedDescription
                    
                    // 如果有原始数据，打印出来以便调试
                    if let originalData = originalData {
                        self.debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                    } else {
                        self.debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    }
                    
                    continuation.resume(throwing: self.handleInterceptorError(errorMessage))
                }
            }
        }
    }
    
    /// 异步从拦截器获取 SwiftyJSON 对象并使用自定义解析闭包转换为模型数组
    public func interceptJSONModelArrayAsync<T>(keyPath: String? = nil, parser: @escaping (JSON) -> T?) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            self.request.response { response in
                // 获取拦截器配置信息
                let interceptorInfo = self.getInterceptorInfo()
                
                // 保存原始响应数据用于调试
                let originalData = response.data
                
                switch self.interceptor.interceptResponse(response) {
                case .success(let data):
                    do {
                        let json = try JSON(data: data)
                        let modelArray = json.toModelArray(keyPath: keyPath, parser: parser)
                        self.debugRequestLog(data, fromInterceptor: true, interceptorInfo: interceptorInfo)
                        continuation.resume(returning: modelArray)
                    } catch {
                        let errorMessage = "JSON解析失败: \(error.localizedDescription)"
                        self.debugRequestLog(data, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                        continuation.resume(throwing: self.handleInterceptorError(errorMessage))
                    }
                case .failure(let error):
                    let errorMessage = error.localizedDescription
                    
                    // 如果有原始数据，打印出来以便调试
                    if let originalData = originalData {
                        self.debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                    } else {
                        self.debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                    }
                    
                    continuation.resume(throwing: self.handleInterceptorError(errorMessage))
                }
            }
        }
    }
}
