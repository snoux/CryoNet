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
    
    /// Token管理器
    public var tokenManager: TokenManagerProtocol
    
    /// 请求拦截器
    public var interceptor: RequestInterceptorProtocol
    
    /// 初始化配置
    public init(
        basicURL: String = "",
        basicHeaders: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")],
        defaultTimeout: TimeInterval = 30,
        maxConcurrentDownloads: Int = 6,
        tokenManager: TokenManagerProtocol = DefaultTokenManager(),
        interceptor: RequestInterceptorProtocol = DefaultInterceptor()
    ) {
        self.basicURL = basicURL
        self.basicHeaders = basicHeaders
        self.defaultTimeout = defaultTimeout
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.tokenManager = tokenManager
        self.interceptor = interceptor
    }
}

/// CryoNet 网络请求核心封装类
@available(macOS 10.15, iOS 13, *)
public final class CryoNet {
    
    // MARK: - 属性
    
    /// 实例配置
    private let queue = DispatchQueue(label: "com.cryonet.config.queue", attributes: .concurrent)
    private var _configuration: CryoNetConfiguration
    public var configuration: CryoNetConfiguration {
        queue.sync { _configuration }
    }
    
    // MARK: - 初始化方法
    
    /// 初始化方法，允许外部注入配置
    public init(configuration: CryoNetConfiguration = CryoNetConfiguration()) {
        self._configuration = configuration
    }
    
    /// 闭包配置初始化方法
    /// - Parameter configurator: 配置闭包，用于自定义配置
    public convenience init(configurator: (inout CryoNetConfiguration) -> Void) {
        var configuration = CryoNetConfiguration()
        configurator(&configuration)
        self.init(configuration: configuration)
    }

    // MARK: - 配置管理
    
    /// 获取当前配置
    /// - Returns: 当前CryoNet配置
    public func getConfiguration() -> CryoNetConfiguration {
        configuration
    }
    
    /// 设置新的配置
    /// - Parameter config: 新的配置对象
    public func setConfiguration(_ config: CryoNetConfiguration) {
        queue.async(flags: .barrier) {
            self._configuration = config
        }
    }
    
    /// 更新部分配置
    /// - Parameter update: 配置更新闭包（需要标记为 @escaping）
    public func updateConfiguration(_ update: @escaping (inout CryoNetConfiguration) -> Void) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            update(&self._configuration)
        }
    }
    
    // MARK: - 配置验证和调试
    
    /// 验证当前拦截器配置
    /// - Returns: 配置验证结果
    public func validateInterceptorConfiguration() -> (isValid: Bool, message: String) {
        let currentInterceptor = configuration.interceptor
        let interceptorType = String(describing: type(of: currentInterceptor))
        
        if interceptorType.contains("DefaultInterceptor") {
            return (false, "当前使用默认拦截器，可能配置未生效")
        } else {
            return (true, "当前使用自定义拦截器: \(interceptorType)")
        }
    }
    
    /// 获取当前拦截器信息
    /// - Returns: 拦截器信息
    public func getCurrentInterceptorInfo() -> String {
        let interceptorType = String(describing: type(of: configuration.interceptor))
        let tokenManagerType = String(describing: type(of: configuration.tokenManager))
        
        return """
        当前拦截器类型: \(interceptorType)
        当前Token管理器类型: \(tokenManagerType)
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
        let fullURL = model.fullURL(with: configuration.basicURL)

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
            to: fullURL,
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
        let allHeaders = self.configuration.basicHeaders + headers
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
        let config = self.configuration
        let userInterceptor = interceptor ?? config.interceptor
        let adapter = InterceptorAdapter(
            interceptor: userInterceptor,
            tokenManager: config.tokenManager
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
        let config = self.configuration
        let fullURL = model.fullURL(with: config.basicURL)
        let mergedHeaders = mergeHeaders(headers)
        let userInterceptor = interceptor ?? config.interceptor
        let adapter = InterceptorAdapter(
            interceptor: userInterceptor,
            tokenManager: config.tokenManager
        )

        let request = AF.request(
            fullURL,
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
        let maxConcurrent = configuration.maxConcurrentDownloads
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrent
        let semaphore = DispatchSemaphore(value: maxConcurrent)

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
