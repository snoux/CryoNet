# CryoNet：基于 Alamofire 的现代化网络请求框架

CryoNet 是一个专为 iOS/macOS 项目设计的网络请求框架，它在 Alamofire 和 SwiftyJSON 的基础上进行了二次封装，旨在提供一个更简单、易用、可扩展且高效的网络层解决方案。本框架致力于简化网络请求的编写、统一错误与数据处理流程，从而显著提升开发效率并减少冗余代码。

---

## 项目状态与安装指南

**CryoNet 目前处于积极开发与测试阶段。** 虽然 API 可能会有微小调整，但其核心用法和设计理念将保持稳定。欢迎关注、试用，并期待您的宝贵建议和问题反馈！

### 安装方式：Swift Package Manager (SPM)

CryoNet 仅支持通过 Swift Package Manager 进行安装，步骤如下：

1.  打开 Xcode，导航至 **File > Add Packages...**
2.  在弹出的输入框中，粘贴 CryoNet 的 GitHub 仓库地址：

    ```
    https://github.com/snoux/CryoNet.git
    ```

3.  选择 **main** 分支作为依赖源进行集成。**重要提示：** 鉴于项目仍处于开发阶段，请始终选择 `main` 分支以获取最新功能和修复。未来正式发布时，将提供稳定的版本标签。

4.  在您的项目 `target` 中导入 CryoNet 模块：

    ```swift
    import CryoNet
    ```

---

## CryoNet 解决了哪些痛点？

尽管 Alamofire 是一个卓越的网络库，但在实际项目开发中，开发者常常需要进行大量的二次封装以满足特定业务需求。CryoNet 正是为了解决这些普遍存在的痛点而生，它通过深入的抽象和优化，带来了极大的便利性和一致性：

*   **统一的错误处理与日志输出：** 在大型项目中，每个接口的错误处理逻辑和日志格式通常需要保持一致。手动在各处配置不仅繁琐，而且难以维护。CryoNet 提供统一机制，确保错误和日志处理的标准化。
*   **请求头与 Token 处理自动化：** 大多数 API 请求都需要统一的请求头（例如 `Content-Type`、`Authorization` 等）。每次手动配置这些头部信息不仅效率低下，还容易遗漏。CryoNet 自动化了这一过程，减少了重复劳动。
*   **数据响应处理的简化：** 服务端返回的数据格式可能冗余且多变，而我们通常只关心其中的业务数据（如 `data` 字段）。每次手动解析这些复杂的数据结构既耗时又容易出错。CryoNet 简化了数据解析流程，使开发者能够更专注于业务逻辑。
*   **代码复用与可维护性提升：** 随着项目的发展，接口数量会急剧增加。如果接口定义、参数和响应没有统一的结构，项目的维护成本将变得极高。CryoNet 强制统一的结构，显著提升了代码的可维护性和复用性。
*   **异步/并发控制与批量请求：** 对于批量下载等场景，Alamofire 虽然提供了基础支持，但实现并发控制、进度管理等高级特性仍需大量手动代码。CryoNet 在这方面提供了更高级别的抽象，简化了复杂异步操作的管理。

---

## CryoNet 的核心功能与特点

CryoNet 针对上述痛点，提供了一系列核心功能，旨在让网络开发变得更加现代、优雅且极致易用。

### 1. 统一的配置管理（`CryoNetConfiguration`）

`CryoNet` 框架引入了 `CryoNetConfiguration` 配置对象，用于集中管理网络层常用的全局参数。这使得项目级别的网络配置和切换变得异常灵活和便捷：

*   **基础 URL (`basicURL`)：** 统一设置所有基础请求的服务端根地址，有效避免了硬编码和分散管理的问题。需要注意的是，批量下载和上传等独立管理的功能不受此 `basicURL` 限制。
*   **默认请求头 (`basicHeaders`)：** 开发者可以在此统一设置如 `Content-Type`、`Accept`、`Authorization` 等默认请求头，所有发起的请求将自动携带这些头部信息。
*   **默认超时时间 (`defaultTimeout`)：** 全局控制每个网络请求的超时时长，无需为每个请求单独设置。
*   **默认 Token 管理策略 (`tokenManager`)：** 内置支持 Token 的获取、刷新和存储机制，开发者可以自定义实现 `TokenManagerProtocol`，框架将自动将 Token 注入到请求头中。
*   **默认请求拦截器 (`interceptor`)：** 允许自定义业务拦截器，统一处理请求的预处理、响应的后处理、错误处理以及结构化数据的抽取等逻辑。

**配置示例：**

您可以通过构造 `CryoNetConfiguration` 实例或使用闭包形式来灵活配置上述参数，并将其注入到 `CryoNet` 实例中，实现项目级的全局配置和动态切换。

```swift
// 通过传入配置对象进行初始化
let config = CryoNetConfiguration(
    basicURL: "http://v.juhe.cn"
)
let cryoNet = CryoNet(configuration: config)

// 通过闭包形式进行初始化和配置
let cryoNet = CryoNet() { config in
    config.basicURL = "http://v.juhe.cn"
}
```

### 2. 统一的请求模型封装

CryoNet 通过 `RequestModel` 结构体对 API 接口的参数、方法、路径、超时时间等进行统一管理。这种模式使得接口定义一目了然，极大地提升了项目的可维护性和可扩展性。结合 `CryoNetConfiguration`，可以实现请求参数与全局设置的无缝衔接。

**示例：新闻 API 管理**

以下示例展示了如何定义新闻相关的 API 接口，包括新闻列表和新闻详情：

```swift
/// 新闻 API 管理
struct API_News {
    static private func getURL(_ url: String) -> String {
        return "/toutiao\(url)"
    }

    /// 新闻列表接口定义
    static let index = RequestModel(
        path: getURL("/index"),  // 设置拼接路径地址
        method: .get,            // 请求方式，默认get，此处仅为演示
        explain: "新闻列表接口"  // 仅为接口描述，无实际意义
    )

    /// 新闻详情接口定义
    static let details = RequestModel(
        path: getURL("/details"),
        method: .get,
        explain: "新闻详情接口"
    )
}

// 示例：发送新闻列表请求
let parameters = [
    "key": juheKey   // 聚合数据头条新闻获取的key
]
// 发送请求
cryoNet.request(API_News.index, parameters: parameters)
```

### 3. 拦截器与请求预处理机制

CryoNet 提供了强大的拦截器机制，支持自定义和继承 `RequestInterceptorProtocol`，从而实现对请求的统一处理。这包括但不限于 Token 注入、业务错误处理、以及响应结构的解析等。此外，`TokenManagerProtocol` 支持自动 Token 刷新与存储，进一步减少了开发者的重复劳动。所有的拦截策略都可以通过 `CryoNetConfiguration` 进行集中注入，也可以在发送单个请求时进行单独配置，提供了极大的灵活性。

**拦截器配置与使用示例：**

以下代码展示了如何自定义响应结构和拦截器，并将其应用于全局配置或单个请求：

```swift
/// 自定义响应结构配置，用于解析深层数据
final class myResponseConfig: DefaultResponseStructure, @unchecked Sendable {
    init() {
        super.init(
            codeKey: "error_code",
            messageKey: "reason",
            dataKey: "result",
            successCode: 0
        )
    }
    // 可选重写：从原始 JSON 中提取指定层级的数据
    override func extractJSON(from json: JSON) -> JSON {
        return json[dataKey]["data"]
    }
    // 可选重写：判断请求是否成功
    override func isSuccess(json: JSON) -> Bool {
        return json[codeKey].intValue == successCode
    }
}

/// 自定义拦截器
class MyInterceptor: DefaultInterceptor {
    init() {
        let responseConfig = myResponseConfig()
        super.init(responseConfig: responseConfig)  /// 为拦截器配置数据结构
    }
    override func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
        return await super.interceptRequest(urlRequest, tokenManager: tokenManager)
    }
}

// 全局配置 CryoNet 实例，注入 Token 管理器和自定义拦截器
let cryoNet = CryoNet() { config in
    config.tokenManager = DefaultTokenManager()
    config.interceptor = MyInterceptor()
}

// 为单个请求设置独立的拦截器
let parameters = [
    "key": juheKey,
    "page_size": 1
]
// 发送请求时，为该请求单独指定拦截器
cryoNet.request(API_News.index, parameters: parameters, interceptor: MyInterceptor())
```

### 4. 丰富且详细的请求日志与调试

CryoNet 内置了详细的请求和响应日志打印功能，包括 `URL`、`Header`、`Body` 和 `响应数据` 等关键信息。这极大地便利了开发和调试过程，帮助开发者快速定位问题。

**日志打印示例：**

当您发起一个请求并调用其响应处理方法（如 `responseJSON`）时，CryoNet 会自动在控制台打印详细的日志信息。

```swift
let parameters = [
    "key": juheKey,
    "page_size": 1
]
cryoNet.request(API_News.index, parameters: parameters)
    .responseJSON { _ in } // 调用响应数据处理方法，触发日志打印
```

**控制台打印日志效果：**

![控制台打印日志](https://i-blog.csdnimg.cn/direct/7d5c2e1092254793a4d7fb48881c1f9c.png)

### 5. 多格式数据响应与便捷处理

CryoNet 支持将响应数据直接解析为多种格式，包括自定义模型、数组、SwiftyJSON 对象、原始 `Data` 等，甚至支持自定义解析器。这种灵活性极大地简化了数据处理逻辑，并提升了对复杂或灵活数据结构的支持和便捷性。

**数据响应与解析示例：**

以下代码展示了如何定义一个可解析的 `NewModel`，并使用 CryoNet 的不同方法来处理响应数据：

```swift
// 新闻模型定义，为演示目的仅包含标题字段
struct NewModel: JSONParseable, Equatable, Identifiable {
    let title: String
    let id = UUID()
    init?(json: JSON) {
        self.title = json.string("title", defaultValue: "这是一条新闻")
    }
}

let parameters = [
    "key": juheKey,
    "page_size": 1
]

cryoNet.request(API_News.index, parameters: parameters)
    .interceptJSONModelArray(type: NewModel.self) { value in
        // 拦截器自动提取业务数据并将其转换为 [NewModel] 数组
        // 此处仅获取响应数据中的 result -> data 数据
    }
    .responseData { _ in } // 将响应解析为原始 Data (完整数据)
    //.responseJSON { _ in } // 将响应解析为 JSON 对象
    //.responseModel(type: Decodable.Type, success: ...) // 将响应解析为 Decodable 模型
    //.responseJSONModel(parser: ..., success: ...) // 使用自定义解析器解析响应
    //.interceptJSONAsync() // 异步拦截 JSON 数据
```

**控制台数据响应日志效果：**

![数据响应](https://i-blog.csdnimg.cn/direct/bb96a741253f4b49aea1042952a0de53.png)

---

## 基础请求与上传/下载分离设计

**特别说明：** CryoNet 在设计上将基础网络请求（如 GET/POST/PUT/DELETE）与文件上传/下载操作进行了逻辑解耦。这意味着它们在配置和并发控制上是独立的。

*   **基础请求：** 所有标准网络请求均通过 `CryoNet` 实例发起，并受 `CryoNetConfiguration` 及相关全局配置的影响。
*   **批量上传/下载：** 考虑到批量文件操作的特殊性，它们通过独立的 `UploadManager` 和 `DownloadManager` 进行管理。这些管理器支持高级特性，如最大并发数、队列池、进度/状态回调以及批量控制。**上传/下载的基础 URL、请求头和并发数均在各自的 Manager 中独立配置，不受 `CryoNetConfiguration.basicURL` 的控制。**

---

## 批量上传（`UploadManager`）示例

CryoNet 提供了强大且线程安全的批量上传能力，特别适用于图片、视频、文档等多文件上传场景。它支持上传进度、状态监控、并发数控制以及任务池隔离等高级功能。

以下将以免费图片上传服务 [imgbb.com](https://api.imgbb.com/) 为例，演示如何进行批量文件上传。

![imgbb](https://i-blog.csdnimg.cn/direct/31e92001ab454c2b9fcebfb17c056fe8.png)

### 基础用法

在进行上传操作之前，首先需要了解目标 API 的数据响应结构，并根据其定义自定义拦截器和响应模型。

*   **imgbb.com 官方数据响应结构示例：**

    ```json
    {
        "data": {
            "id": "cKNFLv6h",
            "title": "001",
            "url_viewer": "https://ibb.co/cKNFLv6h",
            "url": "https://i.ibb.co/zWSRJ5XV/001.png",
            "display_url": "https://i.ibb.co/Cpn72tbK/001.png",
            "width": 663,
            "height": 674,
            "size": 110538,
            "time": 1751391230,
            "expiration": 0,
            "image": {
                "filename": "001.png",
                "name": "001",
                "mime": "image/png",
                "extension": "png",
                "url": "https://i.ibb.co/zWSRJ5XV/001.png"
            },
            "thumb": {
                "filename": "001.png",
                "name": "001",
                "mime": "image/png",
                "extension": "png",
                "url": "https://i.ibb.co/cKNFLv6h/001.png"
            },
            "medium": {
                "filename": "001.png",
                "name": "001",
                "mime": "image/png",
                "extension": "png",
                "url": "https://i.ibb.co/Cpn72tbK/001.png"
            },
            "delete_url": "https://ibb.co/cKNFLv6h/b53145e04a25fdd4331c12e018b331d1"
        },
        "success": true,
        "status": 200
    }
    ```

*   **根据 API 接口及响应结构创建请求相关代码：**

    ```swift
    import CryoNet

    // 1. 创建自定义响应配置：用于准确判断上传结果（成功或失败）
    // 必须继承自 `DefaultResponseStructure` 并配置好数据结构
    final class UploadResponseConfig: DefaultResponseStructure, @unchecked Sendable {
        init(){
            super.init(
                codeKey: "status",
                messageKey: "success",
                dataKey: "data",
                successCode: 200
            )
        }
        // 重写 `extractJSON` 方法：仅获取响应结构中的 `data` 数据
        override func extractJSON(from json: JSON) -> JSON {
            json[dataKey]
        }
        // 重写 `isSuccess` 方法：当 `status` 字段等于 200 时，表示请求成功
        override func isSuccess(json: JSON) -> Bool {
            return json[codeKey].intValue == successCode
        }
    }

    // 2. 配置自定义拦截器：必须继承自 `DefaultInterceptor`
    class UploadInterceptor: DefaultInterceptor, @unchecked Sendable {
        init(){
            let responseConfig = UploadResponseConfig()
            super.init(responseConfig: responseConfig)  /// 为拦截器配置数据结构
        }
    }

    // 3. 创建响应模型：最终会在 `UploadTask` 中反馈该模型结果
    class uploadModel: JSONParseable {
        var url_viewer: String = ""
        var display_url: String = ""
        let id = UUID()
        required init?(json: JSON) { // 为测试目的，仅提取部分数据
            url_viewer = json.string("url_viewer", defaultValue: "")
            display_url = json.string("display_url", defaultValue: "")
        }
    }

    // 4. 创建一个上传管理器实例（推荐通过 UploadManagerPool 隔离业务队列）
    let uploadManager = UploadManager<ImageUploadModel>(
        uploadURL: "https://api.imgbb.com/1/upload",    // 请求 URL
        parameters: ["key": "imgbb申请的key"],    // 附带参数
        maxConcurrentUploads: 3,    // 最大并发上传数量
        interceptor:UploadInterceptor()    // 拦截器
    )

    // 5. 开启下载（此处应为开启上传，原文有误，已修正）
    let fileItem = UploadFileItem(data: data, name: "image", fileName: fileName, mimeType: "image/jpeg")
    let taskID = await uploadManager.addTask(files: [fileItem])
    await uploadManager.startTask(id: taskID)


    // 4. 启动批量上传任务（可携带额外表单字段）
    Task {
        let ids = await uploadManager.batchUpload(
            uploadURL: uploadURL,
            fileURLs: fileURLs,
            formFieldName: "file",    // 默认即可
            extraForm: ["userId": "1234"]
        )
        print("所有上传任务ID：", ids)
    }

    // 5. 监听进度与状态（批量上传仅支持闭包形式监听状态）
    uploadManager.uploadDidUpdate{ task in
        // 每当某个上传任务变化时触发
    }.onTasksUpdate { tasks in
        // 所有任务列表变化回调（任务有增删或状态变更、进度更新时触发，含全部状态）
    }.onActiveTasksUpdate { tasks in
        // 未完成任务列表变化回调（上传中、等待、暂停、失败等非完成状态变化时触发）
    }.onFailureTasksUpdated { task in
        // 失败任务列表变化回调（任务失败相关变化时触发）
    }.onCompletedTasksUpdate { task in
        // 已完成任务列表变化回调（完成任务变化时触发）
    }.onProgressUpdate { Double, UploadBatchState in
        // 批量总体进度或批量状态更新回调（如所有任务进度、整体状态变化时触发）
    }
    ```

**批量上传实现最终效果：**

![上传效果](https://i-blog.csdnimg.cn/direct/26742ae8e2544ca19189c81beacd20e8.png)

**上传成功后，您可以在 imgbb 个人主页查看已上传的图片：**

![imgbb 个人主页](https://i-blog.csdnimg.cn/direct/3688a1ad812f47e3998fe8700c8956be.png)

---

## 批量下载（`DownloadManager`）示例

与上传功能类似，CryoNet 的 `DownloadManager` 也支持多任务并发下载、状态/进度回调、批量操作以及下载完成后自动保存到相册等高级能力。

### 基础用法

```swift
import CryoNet

// 1. 创建下载管理器实例（推荐通过 DownloadManagerPool 隔离业务队列）
let downloadManager = DownloadManager(identifier: "files", maxConcurrentDownloads: 3)

// 2. 构造待下载资源列表（此处以三个视频为例）
private let videoList: [String] = [
    "https://sf1-cdn-tos.huoshanstatic.com/obj/media-fe/xgplayer_doc_video/mp4/xgplayer-demo-360p.mp4",
    "https://www.w3schools.com/html/movie.mp4",
    "https://media.w3.org/2010/05/sintel/trailer.mp4"
]
    

// 3. 启动批量下载任务
Task {
    let ids = await downloadManager.batchDownload(
        pathsOrURLs: videoList,     // 待下载文件的路径或 URL 字符串数组
        destinationFolder: nil,   // 文件保存路径（nil 表示默认保存到 Documents 目录）
        saveToAlbum: true        // 对于图片、视频，可设为 true，下载成功后自动保存到相册
    )
    print("全部下载任务ID:", ids)
}

// 4. 监听进度与状态：通过代理（Delegate）方式
class MyDownloadDelegate: DownloadManagerDelegate {
    func downloadDidUpdate(task: DownloadTask) {
        // 单个下载任务的状态或进度更新回调
    }
    func downloadManagerDidUpdateActiveTasks(tasks: [DownloadTask]) {
        // 当前所有未完成任务（非 completed/cancelled 状态）更新回调
    }
    func downloadManagerDidUpdateCompletedTasks(tasks: [DownloadTask]) {
        // 已完成任务列表更新时回调
    }
    func downloadManagerDidUpdateFailureTasks(tasks: [DownloadTask]) {
        // 当前所有已失败任务更新回调
    }
    func ownloadManagerDidUpdateCancelTasks(tasks: [DownloadTask]) {
        // 当前所有已取消任务更新回调
    }
    func downloadManagerDidUpdateProgress(overallProgress: Double, batchState: DownloadBatchState){
        // 整体下载进度或批量状态更新时回调
    }
}
let delegate = MyDownloadDelegate()
await downloadManager.addDelegate(delegate)
```

**批量下载也支持使用闭包形式获取任务更新：**

```swift
// 闭包回调方式监听下载任务更新
await downloadManager
    .onDownloadDidUpdate { task in
        print("[闭包] 单任务进度/状态更新")
    }
    .onActiveTasksUpdate { tasks in
        print("[闭包] 活跃任务数: \(tasks.count)")
    }
    .onCompletedTasksUpdate { tasks in
        print("[闭包] 已完成任务数: \(tasks.count)")
    }
    .onProgressUpdate { overall, batch in
        print("[闭包] 总进度: \(overall), 批量状态: \(batch.rawValue)")
    }
    .onFailedTasksUpdate { tasks in
        print("[闭包] 失败任务数: \(tasks.count)")
    }
    .onCancelTasksUpdate { tasks in
        print("[闭包] 取消任务数: \(tasks.count)")
    }
```

**最终下载效果：**

![下载效果](https://i-blog.csdnimg.cn/direct/57b7239c07334fdab19982d8512db5ef.jpeg)

---

## 流式请求与 Server-Sent Events (SSE)

CryoNet 还支持流式数据请求，包括 JSON、Decodable 模型、Server-Sent Events (SSE) 以及其他自定义数据流。框架能够自动判定内容类型，为实时数据交互提供了便利。

---

## 更多资源

*   **项目地址：** [https://github.com/snoux/CryoNet](https://github.com/snoux/CryoNet)
*   **文档地址：** [https://snoux.github.io/CryoNet](https://snoux.github.io/CryoNet)
