import Foundation
import Alamofire

// 类型擦除协议
public protocol AnyUploadManager: AnyObject {}

// 泛型上传管理器遵循类型擦除协议
extension UploadManager: AnyUploadManager {}

// 多实例池，支持泛型队列
public actor UploadManagerPool {
    public static let shared = UploadManagerPool()
    private var managers: [String: AnyUploadManager] = [:]

    /// 获取或创建指定 identifier 的泛型 UploadManager
    /// - Parameters:
    ///   - identifier: 队列唯一标识
    ///   - uploadURL: 上传API
    ///   - parameters: 全局参数
    ///   - headers: HTTP头部
    ///   - maxConcurrentUploads: 最大并发上传数
    ///   - modelType: 必须传，保证泛型类型安全
    /// - Returns: 泛型 UploadManager<Model>
    public func manager<Model: JSONParseable>(
        for identifier: String,
        uploadURL: URL,
        parameters: [String: Any]? = nil,
        headers: HTTPHeaders? = nil,
        maxConcurrentUploads: Int = 3,
        modelType: Model.Type,
        interceptor: DefaultInterceptor,
        tokenManager: TokenManagerProtocol = DefaultTokenManager()
    ) -> UploadManager<Model> {
        if let exist = managers[identifier] as? UploadManager<Model> {
            return exist
        }
        let manager = UploadManager<Model>(
            identifier: identifier,
            uploadURL: uploadURL,
            parameters: parameters,
            headers: headers,
            maxConcurrentUploads: maxConcurrentUploads, interceptor: interceptor,tokenManager: tokenManager
        )
        managers[identifier] = manager
        return manager
    }

    /// 获取指定 identifier 的泛型 UploadManager
    public func getManager<Model: JSONParseable>(for identifier: String, modelType: Model.Type) -> UploadManager<Model>? {
        managers[identifier] as? UploadManager<Model>
    }

    /// 所有已创建的 UploadManager（类型擦除）
    public func allManagers() -> [AnyUploadManager] {
        Array(managers.values)
    }

    /// 移除指定 identifier 的 UploadManager
    public func removeManager(for identifier: String) {
        managers[identifier] = nil
    }

    /// 清空全部
    public func removeAll() {
        managers.removeAll()
    }
}
