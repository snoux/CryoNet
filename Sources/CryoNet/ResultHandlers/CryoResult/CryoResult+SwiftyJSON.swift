import Foundation
import SwiftyJSON
import Alamofire

// MARK: - SwiftyJSON 模型转换扩展（同步回调）

/// CryoResult + SwiftyJSON模型转换扩展
///
/// 提供基于 SwiftyJSON 的模型与模型数组的同步回调方式（支持可选 keyPath 与自定义解析）
///
/// ### 使用示例
/// ```swift
/// result.responseJSONModel(type: User.self) { user in
///     // 成功回调
/// }
/// ```
@available(macOS 10.15, iOS 13, *)
public extension CryoResult {

    /// 响应为 SwiftyJSON 对象，并直接转换为模型
    ///
    /// - Parameters:
    ///   - type: 模型类型，需实现 JSONParseable 协议
    ///   - keyPath: 可选，JSON路径，若为 nil 则用整个 JSON
    ///   - success: 成功回调，返回模型
    ///   - failed: 失败回调，返回 CryoError
    /// - Returns: CryoResult
    @discardableResult
    func responseJSONModel<T: JSONParseable>(
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

    /// 响应为 SwiftyJSON 对象，并使用自定义闭包解析为模型
    ///
    /// - Parameters:
    ///   - parser: 自定义解析闭包
    ///   - success: 成功回调，返回模型
    ///   - failed: 失败回调，返回 CryoError
    /// - Returns: CryoResult
    @discardableResult
    func responseJSONModel<T>(
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
    ///
    /// - Parameters:
    ///   - type: 模型类型，需实现 JSONParseable 协议
    ///   - keyPath: 可选，JSON路径
    ///   - success: 成功回调，返回模型数组
    ///   - failed: 失败回调
    /// - Returns: CryoResult
    @discardableResult
    func responseJSONModelArray<T: JSONParseable>(
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

    /// 响应为 SwiftyJSON 对象，并用自定义闭包解析为模型数组
    ///
    /// - Parameters:
    ///   - keyPath: 可选，JSON路径
    ///   - parser: 自定义解析闭包
    ///   - success: 成功回调
    ///   - failed: 失败回调
    /// - Returns: CryoResult
    @discardableResult
    func responseJSONModelArray<T>(
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
}

// MARK: - SwiftyJSON 拦截器模型转换扩展（同步回调）

/// CryoResult + SwiftyJSON拦截器模型转换扩展
///
/// 支持结合拦截器方式下的 SwiftyJSON 转模型（含 keyPath 或自定义闭包）
///
/// ### 使用示例
/// ```swift
/// result.interceptJSONModel(type: User.self) { user in }
/// ```
@available(macOS 10.15, iOS 13, *)
public extension CryoResult {

    /// 从拦截器获取 SwiftyJSON 对象，并直接转换为模型
    ///
    /// - Parameters:
    ///   - type: 模型类型
    ///   - keyPath: 可选，JSON路径
    ///   - success: 成功回调
    ///   - failed: 失败回调（错误信息字符串）
    /// - Returns: CryoResult
    @discardableResult
    func interceptJSONModel<T: JSONParseable & Sendable>(
        type: T.Type,
        keyPath: String? = nil,
        success: @escaping (T) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            let interceptorInfo = self.getInterceptorInfo()
            let originalData = response.data

            guard let interceptor = self.interceptor else {
                // 未配置拦截器，直接解析原始数据
                if let data = originalData {
                    do {
                        let json = try JSON(data: data)
                        if let model = json.toModel(type, keyPath: keyPath) {
                            debugRequestLog(data, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                            success(model)
                        } else {
                            let errorMessage = "未配置拦截器，SwiftyJSON转换模型失败，keyPath: \(keyPath ?? "nil")"
                            failed(errorMessage)
                            debugRequestLog(data, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                        }
                    } catch {
                        let errorMessage = "未配置拦截器，JSON解析失败: \(error.localizedDescription)"
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
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }

    /// 从拦截器获取 SwiftyJSON 对象，并使用自定义闭包解析为模型
    ///
    /// - Parameters:
    ///   - parser: 自定义解析闭包
    ///   - success: 成功回调
    ///   - failed: 失败回调（错误信息字符串）
    /// - Returns: CryoResult
    @discardableResult
    func interceptJSONModel<T>(
        parser: @escaping (JSON) -> T?,
        success: @escaping (T) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            let interceptorInfo = self.getInterceptorInfo()
            let originalData = response.data

            guard let interceptor = self.interceptor else {
                if let data = originalData {
                    do {
                        let json = try JSON(data: data)
                        if let model = json.toModel(parser: parser) {
                            debugRequestLog(data, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                            success(model)
                        } else {
                            let errorMessage = "未配置拦截器，SwiftyJSON自定义解析模型失败"
                            failed(errorMessage)
                            debugRequestLog(data, error: errorMessage, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                        }
                    } catch {
                        let errorMessage = "未配置拦截器，JSON解析失败: \(error.localizedDescription)"
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
    ///
    /// - Parameters:
    ///   - type: 模型类型
    ///   - keyPath: 可选，JSON路径
    ///   - success: 成功回调
    ///   - failed: 失败回调
    /// - Returns: CryoResult
    @discardableResult
    func interceptJSONModelArray<T: JSONParseable & Sendable>(
        type: T.Type,
        keyPath: String? = nil,
        success: @escaping ([T]) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            let interceptorInfo = self.getInterceptorInfo()
            let originalData = response.data

            guard let interceptor = self.interceptor else {
                if let data = originalData {
                    do {
                        let json = try JSON(data: data)
                        let modelArray = json.toModelArray(type, keyPath: keyPath)
                        debugRequestLog(data, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                        success(modelArray)
                    } catch {
                        let errorMessage = "未配置拦截器，JSON解析失败: \(error.localizedDescription)"
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
                if let originalData = originalData {
                    debugRequestLog(originalData, error: "\(errorMessage)", fromInterceptor: true, interceptorInfo: interceptorInfo)
                } else {
                    debugRequestLog(nil, error: errorMessage, fromInterceptor: true, interceptorInfo: interceptorInfo)
                }
            }
        }
        return self
    }

    /// 从拦截器获取 SwiftyJSON 对象，并用自定义闭包解析为模型数组
    ///
    /// - Parameters:
    ///   - keyPath: 可选，JSON路径
    ///   - parser: 自定义解析闭包
    ///   - success: 成功回调
    ///   - failed: 失败回调
    /// - Returns: CryoResult
    @discardableResult
    func interceptJSONModelArray<T>(
        keyPath: String? = nil,
        parser: @escaping (JSON) -> T?,
        success: @escaping ([T]) -> Void,
        failed: @escaping (String) -> Void = { _ in }
    ) -> CryoResult {
        self.request.response { response in
            let interceptorInfo = self.getInterceptorInfo()
            let originalData = response.data

            guard let interceptor = self.interceptor else {
                if let data = originalData {
                    do {
                        let json = try JSON(data: data)
                        let modelArray = json.toModelArray(keyPath: keyPath, parser: parser)
                        debugRequestLog(data, fromInterceptor: false, interceptorInfo: nil, noInterceptor: true)
                        success(modelArray)
                    } catch {
                        let errorMessage = "未配置拦截器，JSON解析失败: \(error.localizedDescription)"
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

// MARK: - SwiftyJSON 模型转换扩展（Async）

/// CryoResult + SwiftyJSON模型转换异步扩展
///
/// 提供 await/async 风格的 SwiftyJSON 转模型（含 keyPath、自定义闭包、拦截器）
///
/// ### 使用示例
/// ```swift
/// let user = try await result.responseJSONModelAsync(User.self)
/// let users = try await result.interceptJSONModelArrayAsync(User.self)
/// ```
@available(macOS 10.15, iOS 13, *)
public extension CryoResult {

    /// await 方式，SwiftyJSON -> 单模型
    ///
    /// - Parameters:
    ///   - type: 模型类型
    ///   - keyPath: 可选，JSON路径
    /// - Throws: 转换失败时抛出异常
    /// - Returns: 解码后的模型
    func responseJSONModelAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> T {
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

    /// await 方式，SwiftyJSON -> 单模型，支持自定义闭包
    ///
    /// - Parameters:
    ///   - parser: 自定义解析闭包
    /// - Throws: 转换失败时抛出异常
    /// - Returns: 解码后的模型
    func responseJSONModelAsync<T>(parser: @escaping (JSON) -> T?) async throws -> T {
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

    /// await 方式，SwiftyJSON -> 模型数组
    ///
    /// - Parameters:
    ///   - type: 模型类型
    ///   - keyPath: 可选，JSON路径
    /// - Returns: 模型数组
    func responseJSONModelArrayAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> [T] {
        let json = try await responseJSONAsync()
        return json.toModelArray(type, keyPath: keyPath)
    }

    /// await 方式，SwiftyJSON -> 模型数组，支持自定义闭包
    ///
    /// - Parameters:
    ///   - keyPath: 可选，JSON路径
    ///   - parser: 自定义解析闭包
    /// - Returns: 模型数组
    func responseJSONModelArrayAsync<T>(keyPath: String? = nil, parser: @escaping (JSON) -> T?) async throws -> [T] {
        let json = try await responseJSONAsync()
        return json.toModelArray(keyPath: keyPath, parser: parser)
    }

    /// await 方式，拦截器+SwiftyJSON -> 单模型
    ///
    /// - Parameters:
    ///   - type: 模型类型
    ///   - keyPath: 可选，JSON路径
    /// - Throws: 错误处理
    /// - Returns: 模型
    func interceptJSONModelAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            interceptJSONModel(type: type, keyPath: keyPath) { model in
                continuation.resume(returning: model)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }

    /// await 方式，拦截器+SwiftyJSON+自定义闭包 -> 单模型
    ///
    /// - Parameters:
    ///   - parser: 自定义解析闭包
    /// - Throws: 错误处理
    /// - Returns: 模型
    func interceptJSONModelAsync<T>(parser: @escaping (JSON) -> T?) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            interceptJSONModel(parser: parser) { model in
                continuation.resume(returning: model)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }

    /// await 方式，拦截器+SwiftyJSON -> 模型数组
    ///
    /// - Parameters:
    ///   - type: 模型类型
    ///   - keyPath: 可选，JSON路径
    /// - Throws: 错误处理
    /// - Returns: 模型数组
    func interceptJSONModelArrayAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            interceptJSONModelArray(type: type, keyPath: keyPath) { arr in
                continuation.resume(returning: arr)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }

    /// await 方式，拦截器+SwiftyJSON+自定义闭包 -> 模型数组
    ///
    /// - Parameters:
    ///   - keyPath: 可选，JSON路径
    ///   - parser: 自定义解析闭包
    /// - Throws: 错误处理
    /// - Returns: 模型数组
    func interceptJSONModelArrayAsync<T>(keyPath: String? = nil, parser: @escaping (JSON) -> T?) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            interceptJSONModelArray(keyPath: keyPath, parser: parser) { arr in
                continuation.resume(returning: arr)
            } failed: { error in
                continuation.resume(throwing: self.handleInterceptorError(error))
            }
        }
    }
}
