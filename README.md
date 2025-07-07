# CryoNet

CryoNet 是一款现代化、灵活且易于扩展的 Swift 网络请求与数据解析框架。基于 Alamofire 和 SwiftyJSON 封装，支持异步/并发、灵活的 Token 与拦截器、批量下载、模型驱动开发等特性，适用于多业务线及复杂网络场景。

---


## 项目说明

**CryoNet 目前仍处于开发与测试阶段，API 可能会有微小调整，但整体用法和核心理念不会有太大变化。欢迎关注、试用、提出建议和 issue！**

- **仅支持 Swift Package Manager 安装**。
- 目前推荐开发者**始终选择 main 分支**作为依赖来源，后续正式发布将提供更稳定的版本标签。
- 欢迎贡献代码、反馈 bug，您的建议是 CryoNet 持续完善的最大动力！

---

## 安装说明（Swift Package Manager）

1. 打开 Xcode，选择 **File > Add Packages...**
2. 在输入框中填入仓库地址：

   ```
   https://github.com/snoux/CryoNet.git
   ```

3. 选择分支 **main** 作为依赖源进行集成：
   > **分支选择说明：** 目前处于开发阶段，请选择 `main` 分支，后续稳定后将发布 tag 版本。

4. 在您的 target 中导入模块：

   ```swift
   import CryoNet
   ```

---

## [CryoNet](https://github.com/snoux/CryoNet) 是什么？

[CryoNet](https://github.com/snoux/CryoNet) 是一个基于 [Alamofire](https://github.com/Alamofire/Alamofire) 和 [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) 二次封装的现代化网络请求框架，旨在为 iOS/macOS 项目提供更简单易用、可扩展且高效的网络层解决方案。

**目标**：简化网络请求的书写、统一错误与数据处理，提升开发效率，减少冗余代码。

---

## CryoNet 主要做了哪些优化？解决了什么问题？

虽然 Alamofire 已经非常优秀，但实际项目中经常需要二次封装以满足具体需求，例如：

- **统一的错误处理与日志输出**：每个接口的错误处理、日志格式通常都需要一致，分散在各处难以维护。
- **请求头与 Token 处理**：大部分接口需要统一的请求头（如 Content-Type、Authorization 等），每次手动配置极其繁琐且容易遗漏。
- **数据响应处理**：通常我们只关心业务数据（如 data 字段），但服务端返回的数据格式可能冗余且多变，每次都手动解析很繁琐。
- **代码复用和可维护性**：项目发展后接口数量激增，接口定义、参数、响应等如果没有统一的结构，维护成本极高。
- **异步/并发控制与批量请求**：如批量下载时的并发控制、进度管理等，Alamofire 虽然支持但仍需大量手工代码。

**CryoNet 针对上述痛点，做了深入的抽象和优化，带来极大便利和一致性。**

---

## CryoNet 的核心功能与特点


<summary>点击展开核心功能介绍</summary>

### 统一的配置管理（CryoNetConfiguration）

- `CryoNet` 提供了配置对象 `CryoNetConfiguration`，用于集中管理网络层常用的全局参数：
  - **基础 URL（basicURL）**：可统一设置**基础请求**的服务端根地址（注意：批量下载、上传等独立管理，不受 basicURL 限制），避免硬编码和散乱管理。
  - **默认请求头（basicHeaders）**：如 Content-Type、Accept、Authorization 等，可在此统一设置，所有请求自动带上。
  - **默认超时时间（defaultTimeout）**：全局控制每个请求的超时时长，避免单独设置。
  - **默认 Token 管理策略（tokenManager）**：内置支持 Token 的获取、刷新、设置，可自定义实现，自动注入到请求头。
  - **默认请求拦截器（interceptor）**：可自定义业务拦截器，统一处理请求、响应、错误、结构化数据抽取等逻辑。

> 你可以通过构造 `CryoNetConfiguration` 实例来灵活配置上述参数，并通过注入到 `CryoNet` 实例，实现项目级的全局配置和切换：

```swift
// 通过传入配置
let config = CryoNetConfiguration(
    basicURL: "http://v.juhe.cn"
)
let cryoNet = CryoNet(configuration: config)

// 通过闭包形式
let cryoNet = CryoNet() { config in
    config.basicURL = "http://v.juhe.cn"
}
```

---

### 统一的请求模型封装

- API 接口参数、方法、路径、超时时间等都通过 `RequestModel` 结构体进行统一管理，接口定义一目了然，便于维护和扩展。
- 配合 `CryoNetConfiguration`，可实现请求参数与全局设置的无缝衔接。

**示例：**
```swift
/// 新闻 API 管理
struct API_News {
    static private func getURL(_ url: String) -> String {
        return "/toutiao\(url)"
    }

    /// 新闻列表
    static let index = RequestModel(
        path: getURL("/index"),  // 设置拼接路径地址
        method: .get,            // 请求方式，默认get，此处仅为演示
        explain: "新闻列表接口"  // 仅为接口描述，无实际意义
    )

    /// 新闻详情
    static let details = RequestModel(
        path: getURL("/details"),
        method: .get,
        explain: "新闻详情接口"
    )
}

// 参数
let parameters = [
    "key": juheKey   // 聚合数据头条新闻获取的key
]
// 发送请求
cryoNet.request(API_News.index, parameters: parameters)
```

---

### 拦截器与请求预处理机制

- 支持自定义和继承的请求拦截器（`RequestInterceptorProtocol`），可统一处理 token 注入、业务错误、响应结构解析等。
- Token 管理器协议（`TokenManagerProtocol`），支持自动 Token 刷新与存储，减少重复劳动。
- 所有拦截策略均可通过 `CryoNetConfiguration` 集中注入，或发送请求时针对单个请求单独注入。

**示例：**
```swift
/// 配置响应结构（返回深层数据,如果需要的话!）
final class myResponseConfig: DefaultResponseStructure, @unchecked Sendable {
    init() {
        super.init(
            codeKey: "error_code",
            messageKey: "reason",
            dataKey: "result",
            successCode: 0
        )
    }
    // 可选重写，返回指定层级数据
    override func extractJSON(from json: JSON) -> JSON {
        return json[dataKey]["data"]
    }
    // 可选重写
    // 内部会默认调用 `extractJSON`，然后调用`JSON.extractDataFromJSON` 提取最终 Data 数据
    // 无特殊情况仅需要重写 `extractJSON` 即可
    override func extractData(from json: JSON, originalData: Data) -> Result<Data, any Error> {}
    // 告诉拦截器请求是否成功
    override func isSuccess(json: JSON) -> Bool {
        return json[codeKey].intValue == successCode
    }
}

class MyInterceptor: DefaultInterceptor {
    init() {
        let responseConfig = myResponseConfig()
        super.init(responseConfig: responseConfig)
    }
    override func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
        return await super.interceptRequest(urlRequest, tokenManager: tokenManager)
    }
}

//  全局配置
let cryoNet = CryoNet() { config in
    config.tokenManager = DefaultTokenManager()
    config.interceptor = MyInterceptor()
}
// 为单个请求设置拦截器
let parameters = [
    "key": juheKey,
    "page_size": 1
]
cryoNet.request(API_News.index, parameters: parameters, interceptor: MyInterceptor())
```

---

### 丰富且详细的请求日志与调试

- 内建详细的请求、响应日志打印，包含 `URL`、`Header`、`Body`、`响应数据`等，极大方便开发与调试。

**示例请求:**
```swift
let parameters = [
    "key": juheKey,
    "page_size": 1
]
cryoNet.request(API_News.index, parameters: parameters)
    .responseJSON { _ in } // 日志打印必须调用响应数据，以响应JSON数据为例
```
**控制台打印日志:**
![控制台打印日志](https://i-blog.csdnimg.cn/direct/7d5c2e1092254793a4d7fb48881c1f9c.png)

---

### 多格式数据响应与便捷处理

- 支持直接将响应数据解析为模型、数组、SwiftyJSON、原始 Data、甚至自定义格式，极大简化数据处理逻辑。
- 集成 SwiftyJSON，提升对灵活数据结构的支持和便捷性。

**示例:**
```swift
// 新闻模型，为做演示，仅取标题
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
        // 拦截器自动提取业务数据并转为 [NewModel]
        // 通过拦截器仅获取响应数据中的result -> data 数据
    }
    .responseData { _ in } // 响应为Data（完整数据）数据
    //.responseJSON { _ in } // 响应为JSON对象
    //.responseModel(type: Decodable.Type, success: ...) // 响应为模型
    //.responseJSONModel(parser: ..., success: ...) // 响应为自定义解析
    //.interceptJSONAsync() // 异步拦截器
```
**控制台将打印如下日志：**
![数据响应](https://i-blog.csdnimg.cn/direct/bb96a741253f4b49aea1042952a0de53.png)


---

## CryoNet 基础请求与上传/下载分离说明

> **特别说明：CryoNet 的基础请求（普通网络请求）与上传/下载做了解耦，配置与并发控制分离。**
>
> - **基础请求**（如 GET/POST/PUT/DELETE）全部通过 `CryoNet` 实例发起，受 `CryoNetConfiguration` 及相关全局配置影响。
> - **批量上传/下载** 属于特殊场景，需通过 `UploadManager`、`DownloadManager` 独立管理，支持最大并发数、队列池、进度/状态回调、批量控制等高级特性。上传/下载的基础URL、请求头、并发数均在对应 Manager 独立配置，**不受 CryoNetConfiguration.basicURL 控制！**

---

## 批量上传（UploadManager）示例

> - **CryoNet 提供了强大且线程安全的批量上传能力（支持进度、状态、并发数、任务池隔离等），适用于图片、视频、文档等多文件上传场景。**
> 
> - **找到一个免费的图片上传接口[https://api.imgbb.com/](https://api.imgbb.com/)，下面我将以此演示如何进行批量上传**

![imgbb](https://i-blog.csdnimg.cn/direct/31e92001ab454c2b9fcebfb17c056fe8.png)

### 基础用法
* **首先看官方数据响应结构**
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

* **根据API接口及响应结构进行创建请求**
```swift
import CryoNet

// 由于需要准确判断上传结果(成功或失败),必须传入自定义拦截器，且该拦截器继承自`DefaultInterceptor`，并配置好响应数据结构
// 1.创建响应
final class UploadResponseConfig: DefaultResponseStructure, @unchecked Sendable {
    // 配置数据结构（根据你的数据结构来调整）
    init(){
        super.init(
            codeKey: "status",
            messageKey: "success",
            dataKey: "data",
            successCode: 200
        )
    }
    // 获取数据（仅获取响应结构中的data数据）
    override func extractJSON(from json: JSON) -> JSON {
        json[dataKey]
    }
    // 告诉拦截器, status 等于 200 时请求成功
    override func isSuccess(json: JSON) -> Bool {
        return json[codeKey].intValue == successCode
    }
}
// 2.配置拦截器
class UploadInterceptor: DefaultInterceptor, @unchecked Sendable {
    init(){
        let responseConfig = UploadResponseConfig()
        super.init(responseConfig: responseConfig)  /// 为拦截器配置数据结构
    }
}

// 3. 创建响应模型（最终会在`UploadTask`中反馈该模型结果）
class uploadModel: JSONParseable {
    var url_viewer: String = ""
    var display_url: String = ""
    let id = UUID()
    required init?(json: JSON) { // 为做测试仅取部分数据
        url_viewer = json.string("url_viewer", defaultValue: "")
        display_url = json.string("display_url", defaultValue: "")
    }
}

// 4. 创建一个上传管理器实例（推荐通过 UploadManagerPool 隔离业务队列）
let uploadManager = UploadManager<ImageUploadModel>(
    uploadURL: "https://api.imgbb.com/1/upload",    // 请求URL
    parameters: ["key": "imgbb申请的key"],    // 附带参数
    maxConcurrentUploads: 3,    // 最大并发上传数量
    interceptor:UploadInterceptor()    // 拦截器
)

// 5. 开启下载
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

**批量上传实现最终效果:**

![上传效果](https://i-blog.csdnimg.cn/direct/26742ae8e2544ca19189c81beacd20e8.png)

**进入你的个人主页即可看到刚刚上传的图片：**
![在这里插入图片描述](https://i-blog.csdnimg.cn/direct/3688a1ad812f47e3998fe8700c8956be.png)



---

## 批量下载（DownloadManager）示例

同样支持多任务并发下载、状态/进度回调、批量操作和保存到相册等高级能力。

#### 基础用法

```swift
import CryoNet

// 1. 创建下载管理器（推荐通过 DownloadManagerPool 隔离业务队列）
let downloadManager = DownloadManager(identifier: "files", maxConcurrentDownloads: 3)

// 2. 构造待下载资源（下载三个视频）
private let videoList: [String] = [
    "https://sf1-cdn-tos.huoshanstatic.com/obj/media-fe/xgplayer_doc_video/mp4/xgplayer-demo-360p.mp4",
    "https://www.w3schools.com/html/movie.mp4",
    "https://media.w3.org/2010/05/sintel/trailer.mp4"
]
    

// 3. 启动批量下载
Task {
    let ids = await downloadManager.batchDownload(
        pathsOrURLs: videoList,     // 路径、URL字符串数组
        destinationFolder: nil,   // 文件保存路径（默认保存到 Documents）
        saveToAlbum: true        // 图片、视频可设为 true，下载成功后自动保存相册
    )
    print("全部下载任务ID:", ids)
}

// 4. 监听进度与状态
class MyDownloadDelegate: DownloadManagerDelegate {
    func downloadDidUpdate(task: DownloadTask) {
        // 单任务状态或进度更新
    }
    func downloadManagerDidUpdateActiveTasks(tasks: [DownloadTask]) {
        // 当前所有未完成任务更新 (非 completed/cancelled)
    }
    func downloadManagerDidUpdateCompletedTasks(tasks: [DownloadTask]) {
        // 已完成任务更新时回调
    }
    func downloadManagerDidUpdateFailureTasks(tasks: [DownloadTask]) {
        // 当前所有已失败任务更新回调
    }
    func ownloadManagerDidUpdateCancelTasks(tasks: [DownloadTask]) {
        // 当前所有已取消任务更新回调
    }
    func downloadManagerDidUpdateProgress(overallProgress: Double, batchState: DownloadBatchState){
        // 整体进度或批量状态更新时回调
    }
}
let delegate = MyDownloadDelegate()
await downloadManager.addDelegate(delegate)
```

**批量下载也支持使用闭包形式获取任务更新：** 
```swift
// 闭包回调
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
**最终效果**

![请添加图片描述](https://i-blog.csdnimg.cn/direct/57b7239c07334fdab19982d8512db5ef.jpeg)


---

### 流式请求与 Server-Sent Events

支持流式 JSON/Decodable/SSE/自定义数据流，自动内容类型判定。

---


- 项目地址：[https://github.com/snoux/CryoNet](https://github.com/snoux/CryoNet)
- 文档地址：[https://snoux.github.io/CryoNet](https://snoux.github.io/CryoNet)

---

> **CryoNet 致力于让网络开发变得现代、优雅、极致易用。欢迎 Star 和交流！**
