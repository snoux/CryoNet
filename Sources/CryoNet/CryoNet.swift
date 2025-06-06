import Foundation
import Alamofire
import SwiftUI
import SwiftyJSON

/// CryoNet 网络请求核心封装类
@available(macOS 10.15, iOS 13, *)
public final class CryoNet {
    
    // MARK: - 属性
    private var tokenManager: TokenManagerProtocol
    private var interceptor: RequestInterceptorProtocol
    private static var instance: CryoNet?

    // MARK: - 初始化方法
    private init(
        _ url: String?,
        tokenManager: TokenManagerProtocol = DefaultTokenManager(),
        interceptor: RequestInterceptorProtocol = DefaultInterceptor()
    ) {
        GlobalManager.Basic_URL = url ?? ""
        self.tokenManager = tokenManager
        self.interceptor = interceptor
    }

    // MARK: - 单例调用
    public static func sharedInstance(_ url: String? = nil) -> CryoNet {
        if instance == nil {
            instance = CryoNet(url)
        }
        return instance!
    }

    /// 设置 Token 管理器
    public func setTokenManager(_ tokenManager: TokenManagerProtocol) {
        self.tokenManager = tokenManager
    }

    /// 设置请求拦截器
    public func setInterceptor(_ interceptor: RequestInterceptorProtocol) {
        self.interceptor = interceptor
    }
}

// MARK: - 私有扩展方法
@available(macOS 10.15, iOS 13, *)
private extension CryoNet {

    /// 上传文件私有方法
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

    /// 将任意类型转换为 Data
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
    func mergeHeaders(_ headers: [HTTPHeader]) -> HTTPHeaders {
        let allHeaders = GlobalManager.Basic_Headers + headers
        return HTTPHeaders(allHeaders)
    }
}

// MARK: - 公共接口方法
@available(macOS 10.15, iOS 13, *)
public extension CryoNet {

    /// 上传接口
    @discardableResult
    func upload(
        _ model: RequestModel,
        files: [UploadData],
        parameters: [String: Any] = [:],
        headers: [HTTPHeader] = [],
        interceptor: RequestInterceptorProtocol? = nil
    ) -> CryoResult {
        let userInterceptor = interceptor ?? self.interceptor
        let adapter = InterceptorAdapter(interceptor: userInterceptor, tokenManager: tokenManager)

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
    @discardableResult
    func request(
        _ model: RequestModel,
        parameters: [String: Any]? = nil,
        headers: [HTTPHeader] = [],
        interceptor: RequestInterceptorProtocol? = nil
    ) -> CryoResult {
        let mergedHeaders = mergeHeaders(headers)
        let userInterceptor = interceptor ?? self.interceptor
        let adapter = InterceptorAdapter(interceptor: userInterceptor, tokenManager: tokenManager)

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
    func downloadFile(
        _ model: DownloadModel,
        progress: @escaping (DownloadItem) -> Void,
        result: @escaping (DownloadResult) -> Void = { _ in }
    ) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 6
        let semaphore = DispatchSemaphore(value: 6)

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

