import Foundation
import Alamofire

/// 全局多实例上传管理池（业务隔离、并发独立）
/// 可用于图片上传、视频上传、文档上传等多上传队列隔离
public actor UploadManagerPool {
    /// 单例全局池
    public static let shared = UploadManagerPool()
    private var managers: [String: UploadManager] = [:]

    /// 获取或创建指定 identifier 的 UploadManager
    /// - Parameters:
    ///   - identifier: 队列唯一标识（如 "default"、"image"、"video"）
    ///   - maxConcurrentUploads: 最大并发上传数（首次创建时生效，已存在的则无效）
    ///   - headers: HTTP头部（可选）
    ///   - globalParameters: 全局参数（可选）
    ///   - interceptor: 业务拦截器
    ///   - tokenManager: Token管理器
    /// - Returns: UploadManager 实例
    public func manager(
        for identifier: String,
        maxConcurrentUploads: Int = 3,
        headers: HTTPHeaders? = nil,
        globalParameters: [String: Any]? = nil,
        interceptor: DefaultInterceptor,
        tokenManager: TokenManagerProtocol
    ) -> UploadManager {
        if let exist = managers[identifier] {
            return exist
        }
        let manager = UploadManager(
            identifier: identifier,
            maxConcurrentUploads: maxConcurrentUploads,
            headers: headers,
            globalParameters: globalParameters,
            interceptor: interceptor,
            tokenManager: tokenManager
        )
        managers[identifier] = manager
        return manager
    }

    /// 获取所有已创建的 UploadManager
    public func allManagers() -> [UploadManager] {
        Array(managers.values)
    }

    /// 获取指定 identifier 的 UploadManager（不存在不创建，返回 nil）
    public func getManager(for identifier: String) -> UploadManager? {
        managers[identifier]
    }

    /// 移除指定 identifier 的 UploadManager
    public func removeManager(for identifier: String) {
        managers[identifier] = nil
    }

    /// 清空全部 UploadManager
    public func removeAll() {
        managers.removeAll()
    }
}
