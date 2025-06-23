import Foundation
import Alamofire
import SwiftUI
import SwiftyJSON

// MARK: - 配置对象

/// `CryoNetConfiguration` 定义了 `CryoNet` 网络请求库的基础配置。
///
/// 此结构体允许您自定义网络请求的各个方面，包括基础 URL、默认请求头、超时时间、
/// 最大并发下载数、Token 管理策略以及请求拦截器。
///
/// ### 使用示例
/// 以下示例展示了如何创建一个自定义的 `CryoNetConfiguration` 实例：
/// ```swift
/// let customConfig = CryoNetConfiguration(
///     basicURL: "https://api.example.com",
///     basicHeaders: [HTTPHeader(name: "Authorization", value: "Bearer your_token")],
///     defaultTimeout: 60,
///     tokenManager: CustomTokenManager(), // 假设您有一个自定义的Token管理器
///     interceptor: CustomRequestInterceptor() // 假设您有一个自定义的请求拦截器
/// )
///
/// let cryoNet = CryoNet(configuration: customConfig)
/// ```
///
/// - Note:
///   - 配置后，所有通过 `CryoNet` 实例发送的请求都将默认拼接 `basicURL` 和 `basicHeaders`。
///   - `TokenManagerProtocol` 和 `RequestInterceptorProtocol` 允许您实现自定义的认证和请求处理逻辑。
///
/// - SeeAlso: ``CryoNet``, ``TokenManagerProtocol``, ``RequestInterceptorProtocol``
@available(macOS 10.15, iOS 13, *)
public struct CryoNetConfiguration: Sendable {
    /// 基础URL
    public var basicURL: String
    /// 基础请求头
    public var basicHeaders: [HTTPHeader]
    /// 默认超时时间（秒）
    public var defaultTimeout: TimeInterval
    /// Token 管理器
    public var tokenManager: TokenManagerProtocol
    /// 请求响应拦截器
    public var interceptor: RequestInterceptorProtocol?

    /// 初始化一个新的 `CryoNetConfiguration` 实例。
    ///
    /// - Parameters:
    ///   - basicURL: 基础请求地址。默认为空字符串。
    ///   - basicHeaders: 基础请求头数组。默认为 `[HTTPHeader(name: "Content-Type", value: "application/json")]`。
    ///   - defaultTimeout: 默认超时时间（秒）。默认为 30 秒。
    ///   - tokenManager: 用于管理 Token 的实例。默认为 ``DefaultTokenManager``()。
    ///   - interceptor: 请求拦截器实例。默认为 `nil`。
    ///
    /// ### 使用示例
    /// ```swift
    /// // 使用所有默认值初始化
    /// let defaultConfig = CryoNetConfiguration()
    ///
    /// // 自定义部分参数
    /// let customConfig = CryoNetConfiguration(
    ///     basicURL: "https://api.my-app.com",
    ///     defaultTimeout: 45
    /// )
    /// ```
    public init(
        basicURL: String = "",
        basicHeaders: [HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")],
        defaultTimeout: TimeInterval = 30,
        tokenManager: TokenManagerProtocol = DefaultTokenManager(),
        interceptor: RequestInterceptorProtocol? = nil
    ) {
        self.basicURL = basicURL
        self.basicHeaders = basicHeaders
        self.defaultTimeout = defaultTimeout
        self.tokenManager = tokenManager
        self.interceptor = interceptor
    }
}


// MARK: - CryoNet 主体

/// `CryoNet` 网络请求主控制器，负责管理网络配置、发起 HTTP 请求和处理文件下载等核心功能。
///
/// 它提供了一套简洁易用的 API，支持自定义配置、请求拦截、Token 管理以及并发下载控制。
/// `CryoNet` 旨在简化 iOS/macOS 应用中的网络层开发，提供稳定、可扩展的网络解决方案。
/// 基本用法与`Alamofire`保持一致,仅有细微差别,方便理解使用
///
/// ### 使用示例
/// 使用默认配置初始化
/// ```swift
/// let cryoNet = CryoNet()
/// ```
///
/// 使用自定义配置初始化 CryoNet
/// ```swift
/// let customConfig = CryoNetConfiguration(basicURL: "https://api.example.com")
/// let customCryoNet = CryoNet(configuration: customConfig)
/// ```
/// 使用闭包进行便捷配置
/// ```swift
/// let anotherCryoNet = CryoNet { config in
///     config.basicURL = "https://api.another-example.com"
///     config.defaultTimeout = 40
/// }
/// ```
///
/// 发起一个 GET 请求并响应为模型
/// ```swift
/// // `MyAPI.getUserInfo` 为 `RequestModel`
/// cryoNet.request(MyAPI.getUserInfo, parameters: ["id": 123])
///     .responseModel(of: User.self) { response in
///         print("User: \(user.name)")
///     }
/// ```
///
/// - Note:
///   - 所有请求和下载操作都基于``CryoNetConfiguration`` 、``RequestModel``。
///   - 示例中演示了如何获取响应数据为模型,也可以响应为其他数据格式,或者直接从拦截器获取指定数据,具体请查看``CryoResult``
///
/// - SeeAlso: ``CryoNetConfiguration``, ``RequestModel``, ``DownloadModel``, ``CryoResult``, ``CryoStreamResult``
@available(macOS 10.15, iOS 13, *)
public class CryoNet {
    /// 内部持有的 ``CryoNetConfiguration`` 实例，所有网络操作都将基于此配置。
    private let configurationActor: CryoNetConfiguration

    /// 使用指定的配置初始化 `CryoNet` 实例。
    ///
    /// - Parameter configuration: 用于初始化 `CryoNet` 的配置对象。默认为 ``CryoNetConfiguration``() 的默认实例。
    ///
    /// ### 使用示例
    /// ```swift
    /// let customConfig = CryoNetConfiguration(basicURL: "https://api.example.com")
    /// let cryoNet = CryoNet(configuration: customConfig)
    /// ```
    ///
    /// - SeeAlso: ``CryoNetConfiguration``
    public init(configuration: CryoNetConfiguration = CryoNetConfiguration()) {
        self.configurationActor = configuration
    }

    /// 使用闭包进行便捷初始化和配置 `CryoNet` 实例。
    ///
    /// 此初始化器允许您在创建 `CryoNet` 实例时，通过一个闭包直接修改默认的 ``CryoNetConfiguration``。
    ///
    /// - Parameter configurator: 一个闭包，接收一个 `inout CryoNetConfiguration` 参数，允许您在其中修改配置。
    ///
    /// ### 使用示例
    /// ```swift
    /// let cryoNet = CryoNet { config in
    ///     config.basicURL = "https://api.my-app.com"
    ///     config.defaultTimeout = 45
    /// }
    /// ```
    ///
    /// - SeeAlso: ``CryoNetConfiguration``
    public convenience init(
        configurator: (inout CryoNetConfiguration) -> Void
    ) {
        var configuration = CryoNetConfiguration()
        configurator(&configuration)
        self.init(configuration: configuration)
    }

    // MARK: - 配置管理 API
    /// 获取当前 `CryoNet` 实例所使用的配置。
    ///
    /// - Returns: 当前 ``CryoNetConfiguration`` 实例。
    ///
    /// ### 使用示例
    /// ```swift
    /// let currentConfig = cryoNet.getConfiguration()
    /// print("当前基础URL: \(currentConfig.basicURL)")
    /// ```
    public func getConfiguration() -> CryoNetConfiguration {
        self.configurationActor
    }
    
    // MARK: - 配置验证和调试

    /// 校验当前 `CryoNet` 实例的请求拦截器配置是否生效。
    ///
    /// 此方法用于调试目的，帮助开发者确认是否成功配置了自定义的请求拦截器，
    /// 避免在生产环境中使用默认的空拦截器。
    ///
    /// - Returns: 一个元组 `(isValid: Bool, message: String)`。
    ///   - `isValid`: 如果当前使用的是自定义拦截器，则为 `true`；如果仍是默认拦截器，则为 `false`。
    ///   - `message`: 描述拦截器状态的字符串信息。
    ///
    /// ### 使用示例
    /// ```swift
    /// let (isValid, message) = cryoNet.validateInterceptorConfiguration()
    /// if isValid {
    ///     print("拦截器配置有效: \(message)")
    /// } else {
    ///     print("拦截器配置可能未生效: \(message)")
    /// }
    /// ```
    ///
    /// - SeeAlso: ``RequestInterceptorProtocol``, ``CryoNetConfiguration/interceptor``
    public func validateInterceptorConfiguration() -> (isValid: Bool, message: String) {
        let currentInterceptor = self.getConfiguration().interceptor
        let interceptorType = String(describing: type(of: currentInterceptor))
        if interceptorType.contains("DefaultInterceptor") {
            return (false, "当前使用默认拦截器，可能配置未生效")
        } else {
            return (true, "当前使用自定义拦截器: \(interceptorType)")
        }
    }

    /// 获取当前 `CryoNet` 实例所使用的拦截器和 Token 管理器类型信息。
    ///
    /// 此方法提供详细的字符串描述，便于开发者快速了解当前网络层使用的具体实现。
    ///
    /// - Returns: 包含拦截器类型和 Token 管理器类型信息的字符串。
    ///
    /// ### 使用示例
    /// ```swift
    /// let info = cryoNet.getCurrentInterceptorInfo()
    /// print(info)
    /// // 预期输出类似：
    /// // 当前拦截器类型: Optional(MyApp.CustomRequestInterceptor)
    /// // 当前Token管理器类型: MyApp.CustomTokenManager
    /// ```
    ///
    /// - SeeAlso: ``RequestInterceptorProtocol``, ``TokenManagerProtocol``
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

    /// 合并请求头，处理重复项时，后面的请求头会覆盖前面的同名请求头。
    ///
    /// 此方法确保最终的请求头集合是唯一的，并优先使用传入的 `headers` 中的值。
    ///
    /// - Parameters:
    ///   - headers: 本次请求需要添加或覆盖的 HTTP 请求头数组。
    ///   - config: 当前 ``CryoNet`` 实例的配置对象，包含基础请求头。
    ///
    /// - Returns: 合并并去重后的 `HTTPHeaders` 实例。
    ///
    /// ### 使用示例
    /// ```swift
    /// let customHeaders = [HTTPHeader(name: "Custom-Header", value: "Value1")]
    /// let merged = mergeHeaders(customHeaders, config: cryoNet.getConfiguration())
    /// print(merged) // 包含 basicHeaders 和 Custom-Header
    /// ```
    private func mergeHeaders(_ headers: [HTTPHeader], config: CryoNetConfiguration) -> HTTPHeaders {
        let allHeaders = (config.basicHeaders + headers)
        // 合并去重，后面覆盖前面
        let uniqueHeaders = Dictionary(grouping: allHeaders, by: { $0.name.lowercased() })
            .map { $0.value.first! }
        return HTTPHeaders(uniqueHeaders)
    }

    /// 将任意 Swift 类型的值转换为 `Data` 类型。
    ///
    /// 此方法支持 `Int`、`Double`、`String`、`[String: Any]` 和 `[Any]` 类型的转换。
    /// 对于字典和数组，它会尝试将其序列化为 JSON `Data`。
    ///
    /// - Parameter value: 需要转换的任意类型值。
    ///
    /// - Returns: 转换后的 `Data` 对象，如果转换失败则返回 `nil`。
    ///
    /// ### 使用示例
    /// ```swift
    /// let intData = anyToData(123) // Optional(Data("123".utf8))
    /// let stringData = anyToData("hello") // Optional(Data("hello".utf8))
    /// let dictData = anyToData(["key": "value"]) // Optional(Data(JSON representation))
    /// let invalidData = anyToData(Date()) // nil
    /// ```
    private func anyToData(_ value: Any) -> Data? {
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

    /// 内部方法：执行文件上传操作。
    ///
    /// 此方法封装了 `Alamofire` 的 `AF.upload` 功能，处理多部分表单数据，
    /// 包括文件数据和额外的参数，并应用请求头和拦截器。
    ///
    /// - Parameters:
    ///   - model: 包含请求路径、方法等信息的 ``RequestModel`` 实例。
    ///   - files: 包含要上传文件数据的 ``UploadData`` 数组。
    ///   - parameters: 随文件上传的其他键值对参数。
    ///   - headers: 本次请求的额外 HTTP 请求头。
    ///   - interceptor: 可选的请求拦截器，用于本次上传。
    ///   - config: 当前 ``CryoNet`` 实例的配置对象。
    ///
    /// - Returns: 一个 `DataRequest` 实例，代表了文件上传请求。
    ///
    /// - Note:
    ///   - 此方法是 ``upload(_:files:parameters:headers:interceptor:)`` 公共方法的内部实现细节。
    ///   - 文件数据可以是 `Data` 或 `URL` 类型。
    ///
    /// - SeeAlso: ``upload(_:files:parameters:headers:interceptor:)``, ``RequestModel``, ``UploadData``
    private func uploadFile(
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

    /// 发起一个文件上传请求。
    ///
    /// 此方法用于将文件和可选参数作为多部分表单数据上传到服务器。
    /// 它会自动处理基础 URL、请求头合并以及拦截器的应用。
    ///
    /// - Parameters:
    ///   - model: 包含上传目标路径和 HTTP 方法的 ``RequestModel`` 实例。
    ///   - files: 一个 ``UploadData`` 数组，每个元素代表一个要上传的文件及其相关信息。
    ///   - parameters: 可选的额外参数字典，将作为表单字段随文件一起上传。默认为空字典。
    ///   - headers: 可选的额外 HTTP 请求头数组，将与 ``CryoNetConfiguration`` 中的基础请求头合并。默认为空数组。
    ///   - interceptor: 可选的自定义请求拦截器，如果提供，将覆盖 ``CryoNetConfiguration`` 中的默认拦截器。默认为 `nil`。
    ///
    /// - Returns: 一个 ``CryoResult`` 实例，用于链式调用处理上传响应。
    ///
    /// ### 使用示例
    /// ```swift
    /// // 假设 imageData 是要上传的 Data，imageURL 是要上传的本地文件 URL
    /// let imageData = Data("some image data".utf8)
    /// let imageURL = URL(fileURLWithPath: "/path/to/your/image.jpg")
    ///
    /// let uploadData1 = UploadData(file: .fileData(imageData), name: "photo", fileName: "my_photo.png")
    /// let uploadData2 = UploadData(file: .fileURL(imageURL), name: "document", fileName: "report.pdf")
    ///
    /// cryoNet.upload(
    ///     MyAPI.uploadFile,
    ///     files: [uploadData1, uploadData2],
    ///     parameters: ["description": "User profile picture"],
    ///     headers: [HTTPHeader(name: "X-Custom-Upload-Header", value: "true")]
    /// )
    /// .responseJSON { response in
    ///     debugPrint(response)
    /// }
    /// ```
    ///
    /// - SeeAlso: ``RequestModel``, ``UploadData``, ``CryoResult``, ``uploadFile(_:files:parameters:headers:interceptor:config:)``
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

    /// 发起一个普通的 HTTP 网络请求（GET, POST, PUT, DELETE 等）。
    ///
    /// 此方法是 `CryoNet` 的核心请求接口，支持各种 HTTP 方法、参数编码、请求头合并和拦截器处理。
    ///
    /// - Parameters:
    ///   - model: 包含请求路径、HTTP 方法、编码方式和超时设置的 ``RequestModel`` 实例。
    ///   - parameters: 可选的请求参数字典，将根据 `model.encoding` 进行编码。默认为 `nil`。
    ///   - headers: 可选的额外 HTTP 请求头数组，将与 ``CryoNetConfiguration`` 中的基础请求头合并。默认为空数组。
    ///   - interceptor: 可选的自定义请求拦截器，如果提供，将覆盖 ``CryoNetConfiguration`` 中的默认拦截器。默认为 `nil`。
    ///
    /// - Returns: 一个 ``CryoResult`` 实例，用于链式调用处理请求响应。
    ///
    /// ### 使用示例
    /// ```swift
    /// // 发起一个 GET 请求获取用户列表
    /// let getUsers = RequestModel(
    ///    path: "/getUsers",  // 设置拼接路径地址 会与BasicURL进行拼接
    ///    method: .get,   // 请求方式
    /// )
    /// cryoNet.request(getUsers, parameters: ["page": 1, "limit": 10])
    ///     .responseModel(of: User.self) { value in
    ///         print("获取到 \(value.count) 个用户")
    ///     }
    ///
    /// // 发起一个 POST 请求创建新用户
    /// let createUser = RequestModel(
    ///    path: "/createUser",  // 设置拼接路径地址 会与BasicURL进行拼接
    ///    method: .post,   // 请求方式
    /// )
    /// let newUser = ["name": "John Doe", "email": "john.doe@example.com"]
    /// cryoNet.request(createUser, parameters: newUser, method: .post)
    ///     .responseJSON { response in
    ///         debugPrint(response)
    ///     }
    /// ```
    ///
    /// - SeeAlso: ``RequestModel``, ``CryoResult``, ``CryoNetConfiguration``
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
}


// MARK: - 流式请求扩展

@available(macOS 10.15, iOS 13, *)
public extension CryoNet {
    /// 发起流式请求，并返回封装的 `CryoStreamResult`
    /// - Parameters:
    /// - model: 请求模型
    /// - parameters: 请求参数（可选）
    /// - headers: 请求头（可选）
    /// - interceptor: 请求拦截器（可选）
    /// - Returns: ``CryoStreamResult``，包含 `Alamofire` 的 `DataStreamRequest`
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

