import Foundation
import Alamofire
import SwiftUI
import SwiftyJSON

/// CryoNet配置对象
@available(macOS 10.15, iOS 13, *)
public struct CryoNetConfiguration {
    /// 基础URL，用于与请求路径拼接
    public var basicURL: String
    
    /// 基础HTTP请求头，会与每个请求的头部合并
    public var basicHeaders: [HTTPHeader]
    
    /// 默认请求超时时间（秒）
    public var defaultTimeout: TimeInterval
    
    /// 默认最大并发下载数
    public var maxConcurrentDownloads: Int
    
    /// 初始化配置
    public init(
        basicURL: String = "",
        basicHeaders: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")],
        defaultTimeout: TimeInterval = 30,
        maxConcurrentDownloads: Int = 6
    ) {
        self.basicURL = basicURL
        self.basicHeaders = basicHeaders
        self.defaultTimeout = defaultTimeout
        self.maxConcurrentDownloads = maxConcurrentDownloads
    }
}

/// CryoNet 网络请求核心封装类
@available(macOS 10.15, iOS 13, *)
public final class CryoNet {
    
    // MARK: - 属性
    
    /// 全局配置
    private var configuration = CryoNetConfiguration()
    
    /// Token管理器
    private static var tokenManager: TokenManagerProtocol = DefaultTokenManager()
    
    /// 请求拦截器
    private static var interceptor: RequestInterceptorProtocol = DefaultInterceptor()
    
    /// 单例实例
    private static var instance: CryoNet?

    // MARK: - 初始化方法
    
    /// 私有初始化方法 - 修复：移除默认参数，使用当前设置的值
    /// - Parameters:
    ///   - url: 基础URL，如果提供则会更新配置
    fileprivate init(_ url: String?) {
        if let url = url, !url.isEmpty {
            configuration.basicURL = url
        }
        // 不再重新设置 tokenManager 和 interceptor，保持当前值
    }

    // MARK: - 配置管理
    
    /// 获取当前配置
    /// - Returns: 当前CryoNet配置
    public static func getConfiguration() -> CryoNetConfiguration {
        return CryoNet.sharedInstance().configuration
    }
    
    /// 设置新的配置
    /// - Parameter config: 新的配置对象
    public func setConfiguration(_ config: CryoNetConfiguration) {
        self.configuration = config
    }
    
    /// 更新部分配置
    /// - Parameter update: 配置更新闭包
    public static func updateConfiguration(_ update: (inout CryoNetConfiguration) -> Void) {
        var config = CryoNet.sharedInstance().configuration
        update(&config)
        CryoNet.sharedInstance().configuration = config
    }
    
    /// 设置基础URL
    /// - Parameter url: 基础URL字符串
    public static func setBasicURL(_ url: String) {
        CryoNet.sharedInstance().configuration.basicURL = url
    }
    
    /// 设置基础请求头
    /// - Parameter headers: HTTP请求头数组
    public static func setBasicHeaders(_ headers: [HTTPHeader]) {
        CryoNet.sharedInstance().configuration.basicHeaders = headers
    }
    
    /// 添加基础请求头
    /// - Parameter header: 要添加的HTTP请求头
    public static func addBasicHeader(_ header: HTTPHeader) {
        CryoNet.sharedInstance().configuration.basicHeaders.append(header)
    }
    
    /// 设置默认超时时间
    /// - Parameter timeout: 超时时间（秒）
    public static func setDefaultTimeout(_ timeout: TimeInterval) {
        CryoNet.sharedInstance().configuration.defaultTimeout = timeout
    }
    
    /// 设置默认默认最大并发下载数
    /// - Parameter timeout: 默认最大并发下载数
    public static func setDefaultMaxConcurrentDownloads(
        _ maxConcurrentDownloads: Int
    ) {
        CryoNet.sharedInstance().configuration.maxConcurrentDownloads = maxConcurrentDownloads
    }

    // MARK: - 单例调用
    
    /// 获取CryoNet共享实例
    /// - Parameter url: 可选的基础URL，如果提供则会更新配置
    /// - Returns: CryoNet实例
    public static func sharedInstance(_ url: String? = nil) -> CryoNet {
        if instance == nil {
            instance = CryoNet(url)
        } else if let url = url, !url.isEmpty {
            // 如果实例已存在但提供了新的URL，则更新配置
            CryoNet.sharedInstance().configuration.basicURL = url
        }
        return instance!
    }

    /// 设置Token管理器
    /// - Parameter tokenManager: 新的Token管理器
    public static func setTokenManager(_ tokenManager: TokenManagerProtocol) {
        CryoNet.tokenManager = tokenManager
    }

    /// 设置请求拦截器
    /// - Parameter interceptor: 新的请求拦截器
    public static func setInterceptor(_ interceptor: RequestInterceptorProtocol) {
        CryoNet.interceptor = interceptor
    }
    
    // MARK: - 配置验证和调试
    
    /// 验证当前拦截器配置
    /// - Returns: 配置验证结果
    public static func validateInterceptorConfiguration() -> (isValid: Bool, message: String) {
        let currentInterceptor = CryoNet.interceptor
        let interceptorType = String(describing: type(of: currentInterceptor))
        
        if interceptorType.contains("DefaultInterceptor") {
            return (false, "当前使用默认拦截器，可能配置未生效")
        } else {
            return (true, "当前使用自定义拦截器: \(interceptorType)")
        }
    }
    
    /// 获取当前拦截器信息
    /// - Returns: 拦截器信息
    public static func getCurrentInterceptorInfo() -> String {
        let interceptorType = String(describing: type(of: CryoNet.interceptor))
        let tokenManagerType = String(describing: type(of: CryoNet.tokenManager))
        
        return """
        当前拦截器类型: \(interceptorType)
        当前Token管理器类型: \(tokenManagerType)
        实例是否已创建: \(instance != nil)
        """
    }
}

// MARK: - 私有扩展方法
@available(macOS 10.15, iOS 13, *)
private extension CryoNet {

    /// 上传文件私有方法
    /// - Parameters:
    ///   - model: 请求模型
    ///   - files: 上传文件数组
    ///   - parameters: 附加参数
    ///   - headers: 请求头
    ///   - interceptor: 可选的请求拦截器
    /// - Returns: 数据请求对象
    func uploadFile(
        _ model: RequestModel,
        files: [UploadData],
        parameters: [String: Any],
        headers: [HTTPHeader],
        interceptor: (any RequestInterceptor)? = nil
    ) -> DataRequest {

        return AF.upload(
            multipartFormData: { multipart in
                files.forEach { item in
                    switch item.file {
                    case .fileData(let data):
                        if let data = data {
                            multipart.append(data, withName: item.name, fileName: item.fileName)
                        }
                    case .fileURL(let url):
                        if let url = url {
                            multipart.append(url, withName: item.name)
                        }
                    }
                }
                // 添加附加参数
                parameters.forEach { key, value in
                    if let data = self.anyToData(value) {
                        multipart.append(data, withName: key)
                    }
                }
            },
            to: model.appendURL,
            method: model.method,
            headers: mergeHeaders(headers),
            interceptor: interceptor
        )
    }

    /// 将任意类型转换为Data
    /// - Parameter value: 任意类型的值
    /// - Returns: 转换后的Data，如果无法转换则返回nil
    func anyToData(_ value: Any) -> Data? {
        switch value {
        case let int as Int:
            return "\(int)".data(using: .utf8)
        case let double as Double:
            return "\(double)".data(using: .utf8)
        case let string as String:
            return string.data(using: .utf8)
        case let dict as [String: Any]:
            let json = JSON(dict)
            return try? json.rawData()
        case let array as [Any]:
            let json = JSON(array)
            return try? json.rawData()
        default:
            return nil
        }
    }

    /// 合并请求头
    /// - Parameter headers: 请求特定的HTTP请求头
    /// - Returns: 合并后的HTTP请求头
    func mergeHeaders(_ headers: [HTTPHeader]) -> HTTPHeaders {
        let allHeaders = CryoNet.sharedInstance().configuration.basicHeaders + headers
        return HTTPHeaders(allHeaders)
    }
}

// MARK: - 公共接口方法
@available(macOS 10.15, iOS 13, *)
public extension CryoNet {

    /// 上传接口
    /// - Parameters:
    ///   - model: 请求模型
    ///   - files: 上传文件数组
    ///   - parameters: 附加参数
    ///   - headers: 请求头
    ///   - interceptor: 可选的请求拦截器
    /// - Returns: CryoResult对象
    @discardableResult
    func upload(
        _ model: RequestModel,
        files: [UploadData],
        parameters: [String: Any] = [:],
        headers: [HTTPHeader] = [],
        interceptor: RequestInterceptorProtocol? = nil
    ) -> CryoResult {
        let userInterceptor = interceptor ?? CryoNet.interceptor
        let adapter = InterceptorAdapter(
            interceptor: userInterceptor,
            tokenManager: CryoNet.tokenManager
        )

        let request = uploadFile(
            model,
            files: files,
            parameters: parameters,
            headers: headers,
            interceptor: adapter
        ).validate()

        return CryoResult(request: request, interceptor: userInterceptor)
    }

    /// 普通请求接口
    /// - Parameters:
    ///   - model: 请求模型
    ///   - parameters: 请求参数
    ///   - headers: 请求头
    ///   - interceptor: 可选的请求拦截器
    /// - Returns: CryoResult对象
    @discardableResult
    func request(
        _ model: RequestModel,
        parameters: [String: Any]? = nil,
        headers: [HTTPHeader] = [],
        interceptor: RequestInterceptorProtocol? = nil
    ) -> CryoResult {
        let mergedHeaders = mergeHeaders(headers)
        let userInterceptor = interceptor ?? CryoNet.interceptor
        let adapter = InterceptorAdapter(
            interceptor: userInterceptor,
            tokenManager: CryoNet.tokenManager
        )

        let request = AF.request(
            model.appendURL,
            method: model.method,
            parameters: parameters,
            encoding: model.encoding.getEncoding(),
            headers: mergedHeaders,
            interceptor: adapter
        ) { $0.timeoutInterval = model.overtime }
        .validate()

        return CryoResult(request: request, interceptor: userInterceptor)
    }

    /// 文件下载接口（支持批量下载）
    /// - Parameters:
    ///   - model: 下载模型
    ///   - progress: 下载进度回调
    ///   - result: 下载结果回调
    func downloadFile(
        _ model: DownloadModel,
        progress: @escaping (DownloadItem) -> Void,
        result: @escaping (DownloadResult) -> Void = { _ in }
    ) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = CryoNet.sharedInstance().configuration.maxConcurrentDownloads
        let semaphore = DispatchSemaphore(
            value: CryoNet.sharedInstance().configuration.maxConcurrentDownloads
        )

        for item in model.models {
            guard item.fileURL != nil else { continue }

            let operation = BlockOperation {
                semaphore.wait()

                let destination: DownloadRequest.Destination = { _, _ in
                    let directory = model.savePathURL ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                    return (
                        directory.appendingPathComponent(item.fileName),
                        [.removePreviousFile, .createIntermediateDirectories]
                    )
                }

                AF.download(item.filePath, to: destination)
                    .validate()
                    .downloadProgress {
                        item.progress = $0.fractionCompleted
                        progress(item)
                    }
                    .response {
                        response in
                        result(DownloadResult(result: response.result, downLoadItem: item))
                        semaphore.signal()
                    }
            }

            queue.addOperation(operation)
        }
    }
}

