import Foundation
import Alamofire
import SwiftUI
import SwiftyJSON

// MARK: - 配置对象

/**
 CryoNetConfiguration
 网络配置对象，提供基础URL、默认请求头、超时、最大并发下载、Token管理、拦截器等参数。
 */
@available(macOS 10.15, iOS 13, *)
public struct CryoNetConfiguration: Sendable {
    /// 基础URL
    public var basicURL: String
    /// 基础请求头
    public var basicHeaders: [HTTPHeader]
    /// 默认超时时间（秒）
    public var defaultTimeout: TimeInterval
    /// 最大并发下载数
    public var maxConcurrentDownloads: Int
    /// Token 管理器
    public var tokenManager: TokenManagerProtocol
    /// 请求响应拦截器
    public var interceptor: RequestInterceptorProtocol?

    /**
     初始化方法
     - Parameters:
        - basicURL: 基础请求URL
        - basicHeaders: 默认请求头
        - defaultTimeout: 默认超时时间
        - maxConcurrentDownloads: 最大并发下载数
        - tokenManager: Token管理器
        - interceptor: 请求拦截器
     */
    public init(
        basicURL: String = "",
        basicHeaders: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")],
        defaultTimeout: TimeInterval = 30,
        maxConcurrentDownloads: Int = 6,
        tokenManager: TokenManagerProtocol = DefaultTokenManager(),
        interceptor: RequestInterceptorProtocol? = nil
    ) {
        self.basicURL = basicURL
        self.basicHeaders = basicHeaders
        self.defaultTimeout = defaultTimeout
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.tokenManager = tokenManager
        self.interceptor = interceptor
    }
}


// MARK: - CryoNet 主体

/**
 CryoNet
 网络请求主控制器，负责管理配置、请求和下载等功能。
 */
@available(macOS 10.15, iOS 13, *)
public class CryoNet {
    /// 当前配置
    private let configurationActor: CryoNetConfiguration

    /**
     初始化方法，传入配置
     - Parameter configuration: 配置对象
     */
    public init(configuration: CryoNetConfiguration = CryoNetConfiguration()) {
        self.configurationActor = configuration
    }

    /**
     便捷初始化，支持闭包式配置
     - Parameter configurator: 闭包修改配置
     */
    public convenience init(
        configurator: (inout CryoNetConfiguration) -> Void
    ) {
        var configuration = CryoNetConfiguration()
        configurator(&configuration)
        self.init(configuration: configuration)
    }

    // MARK: - 配置管理 API

    /// 获取当前配置
    public func getConfiguration() -> CryoNetConfiguration {
        self.configurationActor
    }
    
    // MARK: - 配置验证和调试

    /**
     校验当前拦截器配置是否生效
     - Returns: (isValid, message) 元组
     */
    public func validateInterceptorConfiguration() -> (isValid: Bool, message: String) {
        let currentInterceptor = self.getConfiguration().interceptor
        let interceptorType = String(describing: type(of: currentInterceptor))
        if interceptorType.contains("DefaultInterceptor") {
            return (false, "当前使用默认拦截器，可能配置未生效")
        } else {
            return (true, "当前使用自定义拦截器: \(interceptorType)")
        }
    }

    /// 获取当前拦截器及Token管理器类型信息
    public func getCurrentInterceptorInfo() -> String {
        let config = self.getConfiguration()
        let interceptorType = String(describing: type(of: config.interceptor))
        let tokenManagerType = String(describing: type(of: config.tokenManager))
        return """
        当前拦截器类型: \(interceptorType)
        当前Token管理器类型: \(tokenManagerType)
        """
    }
}


// MARK: - 私有扩展方法

@available(macOS 10.15, iOS 13, *)
private extension CryoNet {

    /**
     合并请求头（去重，后面的覆盖前面的）
     - Parameters:
        - headers: 本次请求头
        - config: 配置对象
     - Returns: 合并后的 HTTPHeaders
     */
    func mergeHeaders(_ headers: [HTTPHeader], config: CryoNetConfiguration) -> HTTPHeaders {
        let allHeaders = (config.basicHeaders + headers)
        // 合并去重，后面覆盖前面
        let uniqueHeaders = Dictionary(grouping: allHeaders, by: { $0.name.lowercased() })
            .map { $0.value.first! }
        return HTTPHeaders(uniqueHeaders)
    }

    /**
     将任意类型转换为 Data
     - Parameter value: 需要转换的值
     - Returns: Data 或 nil
     */
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

    /**
     上传文件（内部方法）
     - Parameters:
        - model: 请求模型
        - files: 上传文件数据
        - parameters: 其他参数
        - headers: 请求头
        - interceptor: 拦截器
        - config: CryoNet配置
     - Returns: DataRequest
     */
    func uploadFile(
        _ model: RequestModel,
        files: [UploadData],
        parameters: [String: Any],
        headers: [HTTPHeader],
        interceptor: (any RequestInterceptor)? = nil,
        config: CryoNetConfiguration
    ) -> DataRequest {
        let fullURL = model.fullURL(with: config.basicURL)
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
                parameters.forEach { key, value in
                    if let data = self.anyToData(value) {
                        multipart.append(data, withName: key)
                    }
                }
            },
            to: fullURL,
            method: model.method,
            headers: mergeHeaders(headers, config: config),
            interceptor: interceptor
        )
    }
}


// MARK: - 公共接口方法

@available(macOS 10.15, iOS 13, *)
public extension CryoNet {

    /**
     上传文件接口
     - Parameters:
        - model: 请求模型
        - files: 上传文件数组
        - parameters: 额外参数
        - headers: 额外请求头
        - interceptor: 自定义拦截器
     - Returns: CryoResult
     */
    @discardableResult
    func upload(
        _ model: RequestModel,
        files: [UploadData],
        parameters: [String: Any] = [:],
        headers: [HTTPHeader] = [],
        interceptor: RequestInterceptorProtocol? = nil
    ) -> CryoResult {
        let config = self.getConfiguration()
        let userInterceptor = interceptor ?? config.interceptor
        var adapter: InterceptorAdapter? = nil
        if let _ = userInterceptor{
            adapter = InterceptorAdapter(
                interceptor: userInterceptor,
                tokenManager: config.tokenManager
            )
        }
        let request = uploadFile(
            model,
            files: files,
            parameters: parameters,
            headers: headers,
            interceptor: adapter,
            config: config
        ).validate()
        return CryoResult(request: request, interceptor: userInterceptor)
    }

    /**
     普通请求接口
     - Parameters:
        - model: 请求模型
        - parameters: 请求参数
        - headers: 额外请求头
        - interceptor: 自定义拦截器
     - Returns: CryoResult
     */
    @discardableResult
    func request(
        _ model: RequestModel,
        parameters: [String: Any]? = nil,
        headers: [HTTPHeader] = [],
        interceptor: RequestInterceptorProtocol? = nil
    ) -> CryoResult {
        let config = self.getConfiguration()
        let fullURL = model.fullURL(with: config.basicURL)
        let mergedHeaders = mergeHeaders(headers, config: config)
        let userInterceptor = interceptor ?? config.interceptor
        var adapter: InterceptorAdapter? = nil
        if let _ = userInterceptor{
            adapter = InterceptorAdapter(
                interceptor: userInterceptor,
                tokenManager: config.tokenManager
            )
        }
        
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

    /**
     并发/限流批量下载接口
     - Parameters:
        - model: 下载模型
        - progress: 进度回调
        - result: 单个文件下载结果回调
     */
    @available(macOS 10.15, iOS 13, *)
    func downloadFile(
        _ model: DownloadModel,
        progress: @escaping @Sendable (DownloadItem) -> Void,
        result: @escaping @Sendable (DownloadResult) -> Void = { _ in }
    ) async {
        let config = self.getConfiguration()
        let maxConcurrent = config.maxConcurrentDownloads

        // 过滤掉无效下载项
        let items = await model.models.asyncFilter {
            await $0.fileURL() != nil
        }

        // 自定义 actor 信号量，实现最大并发
        actor AsyncSemaphore {
            private var value: Int
            private var waitQueue: [CheckedContinuation<Void, Never>] = []

            init(value: Int) {
                self.value = value
            }

            func wait() async {
                if value > 0 {
                    value -= 1
                } else {
                    await withCheckedContinuation { continuation in
                        waitQueue.append(continuation)
                    }
                }
            }

            func signal() async {
                if !waitQueue.isEmpty {
                    let continuation = waitQueue.removeFirst()
                    continuation.resume()
                } else {
                    value += 1
                }
            }
        }

        let semaphore = AsyncSemaphore(value: maxConcurrent)

        await withTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } } // 用Task包裹，避免defer里不能直接await

                    let fileName = await item.getFileName()
                    let filePath = await item.getFilePath()
                    let destination: DownloadRequest.Destination = { _, _ in
                        let directory = model.savePathURL ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                        return (
                            directory.appendingPathComponent(fileName),
                            [.removePreviousFile, .createIntermediateDirectories]
                        )
                    }

                    let downloadRequest = AF.download(filePath, to: destination)
                        .validate()
                        .downloadProgress { downloadProgress in
                            // 始终回调到主线程，方便UI刷新
                            DispatchQueue.main.async {
                                Task {
                                    await item.setProgress(downloadProgress.fractionCompleted)
                                    progress(item)
                                }
                            }
                        }
                        .response { response in
                            DispatchQueue.main.async {
                                Task {
                                    result(DownloadResult(result: response.result, downLoadItem: item))
                                }
                            }
                        }

                    // 等待下载完成
                    await withCheckedContinuation { continuation in
                        downloadRequest.response { _ in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    /**
     信号量 actor：支持异步限流任务组
     */
    actor AsyncSemaphore {
        private var value: Int
        private var waitQueue: [CheckedContinuation<Void, Never>] = []

        init(value: Int) {
            self.value = value
        }

        func wait() async {
            if value > 0 {
                value -= 1
            } else {
                await withCheckedContinuation { continuation in
                    waitQueue.append(continuation)
                }
            }
        }

        func signal() {
            if !waitQueue.isEmpty {
                let continuation = waitQueue.removeFirst()
                continuation.resume()
            } else {
                value += 1
            }
        }
    }
}


// MARK: - 流式请求扩展

@available(macOS 10.15, iOS 13, *)
public extension CryoNet {
    /**
     发起流式请求，并返回封装的 CryoStreamResult
     - Parameters:
        - model: 请求模型
        - parameters: 请求参数（可选）
        - headers: 请求头（可选）
        - interceptor: 请求拦截器（可选）
     - Returns: CryoStreamResult，包含 Alamofire 的 DataStreamRequest
     */
    func streamRequest(
        _ model: RequestModel,
        parameters: [String: Any]? = nil,
        headers: [HTTPHeader] = [],
        interceptor: RequestInterceptorProtocol? = nil
    ) -> CryoStreamResult {
        let config = getConfiguration()
        let fullURL = model.fullURL(with: config.basicURL)
        let mergedHeaders = mergeHeaders(headers, config: config)
        let userInterceptor = interceptor ?? config.interceptor

        // 构造适配器（如果有自定义拦截器）
        var adapter: InterceptorAdapter? = nil
        if let userInterceptor = userInterceptor {
            adapter = InterceptorAdapter(
                interceptor: userInterceptor,
                tokenManager: config.tokenManager
            )
        }
        
        // 构造流式请求
        let request = AF.streamRequest(
            fullURL,
            method: model.method,
            headers: mergedHeaders,
            automaticallyCancelOnStreamError: false,
            interceptor: adapter
        )
        
        // 返回 CryoStreamResult，只传入 request
        return CryoStreamResult(request: request)
    }
}


// MARK: - 异步过滤扩展

/**
 Sequence 异步过滤扩展，便于并发下载等场景用 await 过滤元素
 */
extension Sequence {
    /**
     异步过滤方法
     - Parameter isIncluded: 异步过滤闭包
     - Returns: 过滤后的数组
     */
    func asyncFilter(_ isIncluded: @escaping (Element) async -> Bool) async -> [Element] {
        var result: [Element] = []
        for element in self {
            if await isIncluded(element) {
                result.append(element)
            }
        }
        return result
    }
}
