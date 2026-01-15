import Foundation
import Alamofire

// 多实例池，支持泛型队列
public actor UploadManagerPool {
    public static let shared = UploadManagerPool()
    private var managers: [String: AnyObject] = [:]

    /// 获取或创建指定 identifier 的泛型 UploadManager
    /// - Parameters:
    ///   - identifier: 队列唯一标识
    ///   - uploadURL: 上传API
    ///   - parameters: 全局参数
    ///   - headers: HTTP头部
    ///   - maxConcurrentUploads: 最大并发上传数
    ///   - modelType: 必须传，保证泛型类型安全
    ///   - tokenManager: 默认DefaultTokenManager()
    /// - Returns: 泛型 UploadManager<Model>
    public func manager<Model: JSONParseable & Sendable>(
        for identifier: String,
        uploadURL: URL,
        parameters: Parameters? = nil,
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
    public func getManager<Model: JSONParseable & Sendable>(for identifier: String, modelType: Model.Type) -> UploadManager<Model>? {
        managers[identifier] as? UploadManager<Model>
    }

    /// 移除指定 identifier 的 UploadManager
    public func removeManager<Model: JSONParseable & Sendable>(for identifier: String, modelType: Model.Type) {
        Task{
            if let manager = managers[identifier] as? UploadManager<Model> {
                await manager.deleteAllTasks()
            }
            managers[identifier] = nil
        }
    }
}
