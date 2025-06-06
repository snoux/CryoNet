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
        interceptJSON { json in
            if let model = json.toModel(type, keyPath: keyPath) {
                success(model)
            } else {
                failed("SwiftyJSON转换模型失败")
            }
        } failed: { error in
            failed(error)
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
        interceptJSON { json in
            if let model = json.toModel(parser: parser) {
                success(model)
            } else {
                failed("SwiftyJSON自定义解析模型失败")
            }
        } failed: { error in
            failed(error)
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
        interceptJSON { json in
            let modelArray = json.toModelArray(type, keyPath: keyPath)
            success(modelArray)
        } failed: { error in
            failed(error)
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
        interceptJSON { json in
            let modelArray = json.toModelArray(keyPath: keyPath, parser: parser)
            success(modelArray)
        } failed: { error in
            failed(error)
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
        let json = try await interceptJSONAsync()
        guard let model = json.toModel(type, keyPath: keyPath) else {
            throw NSError(
                domain: "JSONModelError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "SwiftyJSON转换模型失败"]
            )
        }
        return model
    }
    
    /// 异步从拦截器获取 SwiftyJSON 对象并使用自定义解析闭包转换为模型
    public func interceptJSONModelAsync<T>(parser: @escaping (JSON) -> T?) async throws -> T {
        let json = try await interceptJSONAsync()
        guard let model = json.toModel(parser: parser) else {
            throw NSError(
                domain: "JSONModelError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "SwiftyJSON自定义解析模型失败"]
            )
        }
        return model
    }
    
    /// 异步从拦截器获取 SwiftyJSON 对象并转换为模型数组
    public func interceptJSONModelArrayAsync<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) async throws -> [T] {
        let json = try await interceptJSONAsync()
        return json.toModelArray(type, keyPath: keyPath)
    }
    
    /// 异步从拦截器获取 SwiftyJSON 对象并使用自定义解析闭包转换为模型数组
    public func interceptJSONModelArrayAsync<T>(keyPath: String? = nil, parser: @escaping (JSON) -> T?) async throws -> [T] {
        let json = try await interceptJSONAsync()
        return json.toModelArray(keyPath: keyPath, parser: parser)
    }
}

