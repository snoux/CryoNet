import Foundation
import Alamofire
import SwiftUI
import SwiftyJSON

// MARK: - 配置对象
@available(macOS 10.15, iOS 13, *)
public struct CryoNetConfiguration: Sendable {
    public var basicURL: String
    public var basicHeaders: [HTTPHeader]
    public var defaultTimeout: TimeInterval
    public var maxConcurrentDownloads: Int
    public var tokenManager: TokenManagerProtocol
    public var interceptor: RequestInterceptorProtocol?

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
@available(macOS 10.15, iOS 13, *)
public class CryoNet {
    private let configurationActor: CryoNetConfiguration

    public init(configuration: CryoNetConfiguration = CryoNetConfiguration()) {
        self.configurationActor = configuration
    }
    public convenience init(
        configurator: (inout CryoNetConfiguration) -> Void
    ) {
        var configuration = CryoNetConfiguration()
        configurator(&configuration)
        self.init(configuration: configuration)
    }

    // MARK: - 配置管理 API
    public func getConfiguration() -> CryoNetConfiguration {
        self.configurationActor
    }

    

    // MARK: - 配置验证和调试
    public func validateInterceptorConfiguration() -> (isValid: Bool, message: String) {
        let currentInterceptor = self.getConfiguration().interceptor
        let interceptorType = String(describing: type(of: currentInterceptor))
        if interceptorType.contains("DefaultInterceptor") {
            return (false, "当前使用默认拦截器，可能配置未生效")
        } else {
            return (true, "当前使用自定义拦截器: \(interceptorType)")
        }
    }

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

    func mergeHeaders(_ headers: [HTTPHeader], config: CryoNetConfiguration) -> HTTPHeaders {
        let allHeaders = (config.basicHeaders + headers)
        // 合并去重
        let uniqueHeaders = Dictionary(grouping: allHeaders, by: { $0.name.lowercased() })
            .map { $0.value.first! }
        return HTTPHeaders(uniqueHeaders)
    }

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

        // 自定义 actor 信号量
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
    /// 发起流式请求，并返回封装的 CryoStreamResult
    /// - Parameters:
    ///   - model: 请求模型
    ///   - parameters: 请求参数（可选）
    ///   - headers: 请求头（可选）
    ///   - interceptor: 请求拦截器（可选）
    /// - Returns: CryoStreamResult，包含 Alamofire 的 DataStreamRequest
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
extension Sequence {
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
