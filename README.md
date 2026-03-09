# CryoNet

基于 Alamofire + SwiftyJSON 的 Swift 网络层封装，适用于 iOS/macOS/tvOS/watchOS。

`CryoNet` 主要做了三件事：
- 统一请求配置（`baseURL`、默认 `headers`、超时、token、拦截器）
- 统一响应处理（`Data` / `JSON` / `Decodable` / `JSONParseable`）
- 提供独立的批量上传与下载管理器（并发、队列、状态回调）

## 安装

通过 Swift Package Manager：

```swift
https://github.com/snoux/CryoNet.git
```

依赖：
- Alamofire `>= 5.11.1`
- SwiftyJSON `>= 5.0.2`

## 快速开始

### 1) 初始化

```swift
import CryoNet

let cryoNet = CryoNet { config in
    config.baseURL = "https://api.example.com"
    config.defaultTimeout = 30
    config.basicHeaders = [
        .init(name: "Content-Type", value: "application/json")
    ]
    config.tokenManager = DefaultTokenManager()
    config.interceptor = DefaultInterceptor(
        extractData: { json, originalData in
            // 自定义数据提取逻辑：提取业务字段
            JSON.extractDataFromJSON(json["data"], originalData: originalData)
        },
        isSuccess: { json in
            // 自定义成功判断逻辑
            return json["code"].intValue == 0
        },
        extractFailureReason: { json, _ in
            // 自定义失败原因提取逻辑
            json["msg"].string
        }
    )
}
```

### 2) 定义请求

```swift
import Alamofire

struct API {
    static let newsList = RequestModel(
        path: "/news/list",
        method: .get,
        encoding: .urlDefault,
        explain: "新闻列表"
    )
}
```

### 3) 发起请求

```swift
cryoNet.request(API.newsList, parameters: ["page": 1])
    .responseJSON { json in
        print(json)
    } failed: { error in
        print(error.localizedDescription)
    }
```

## 响应处理

`request(...)` 返回 `CryoResult`，可按需选择解析方式。

### 直接解析完整响应

```swift
cryoNet.request(API.newsList)
    .responseData { data in }
    .responseJSON { json in }
    .responseModel(type: MyDecodable.self) { model in }
    .responseModelArray(type: MyDecodable.self) { list in }
```

### 使用 SwiftyJSON 模型解析

```swift
struct NewsItem: JSONParseable {
    let title: String
    init?(json: JSON) {
        self.title = json["title"] ?? ""
    }
}

cryoNet.request(API.newsList)
    .responseJSONModelArray(type: NewsItem.self) { list in
        print(list.count)
    }
```

### 使用拦截器后的业务数据

```swift
cryoNet.request(API.newsList)
    .interceptJSONModelArray(type: NewsItem.self) { list in
        // list 来自初始化CryoNet配置的拦截器或发送请求时配置的拦截器提取后的数据
    } failed: { message in
        print(message)
    }

// 注意：如果未配置拦截器，intercept*** 会直接失败，
// 错误信息为：未配置拦截器，请使用response***获取响应数据
```

### 为什么推荐配置响应拦截器

一般情况下,业务接口返回结构都比较统一，例如：

```json
{
  "code": 0,
  "msg": "ok",
  "data": {
    "title": "CryoNet"
  }
}
```

如果不使用响应拦截器，每个请求都需要重复写：
- 判断 `code` 是否成功
- 读取失败文案 `msg`
- 从包裹结构中手动取 `data`
- 再把 `data` 转成模型

配置一次 `DefaultInterceptor` 后，这些通用逻辑就会沉到网络层：
- `isSuccess` 统一判断业务成功条件
- `extractFailureReason` 统一提取错误信息
- `extractData` 统一提取真正业务数据

业务层拿到的就是“可直接使用的数据”：

```swift
cryoNet.request(API.newsList)
    .interceptModel(type: NewsItem.self) { model in
        // 这里通常已经是 data 对应的模型，不再关心 code/msg
        print(model)
    } failed: { message in
        // 统一失败信息，便于直接提示用户
        print(message)
    }
```

这样做的好处：
- 减少重复解析代码，接口越多收益越明显
- 统一错误处理口径，避免不同页面提示不一致
- 业务层更专注“功能逻辑”，而不是“响应结构细节”
- 后端字段调整时，通常只需改一处拦截配置

#### 和“每次请求后手动调用通用方法”有什么区别

这是一个很常见的疑惑：
- "我已经有 `parseResponse(data)`，是不是就不需要拦截器了？"
- "只要团队约定好都调用这个方法，不也一样吗？"

结论是：思路类似，但落地效果通常不一样。

手动通用方法更像“约定”；响应拦截器更像“机制”。
- 执行时机不同：拦截器在网络层统一生效；手动方法依赖每个调用点自觉调用，容易漏。
- 约束力度不同：`intercept***` 链路天然只暴露业务数据；手动方法无法强约束所有人都走同一入口。
- 错误口径不同：拦截器可统一网络错误/HTTP错误/业务错误的优先级与文案；手动方法常出现页面各自处理。
- 维护成本不同：后端结构变化时，拦截器一般改一处；手动方法模式下常要排查多个调用点。

可以简单理解为：
- 个人项目或接口很少：手动方法可用。
- 团队协作、接口多、迭代快：拦截器更稳，更不容易出现“某个页面忘记处理 code/msg”的问题。

## 拦截器与 Token

### 默认行为说明（重要）

- 网络层错误优先：如超时、断网、DNS/TLS、请求取消等，直接返回网络错误。
- HTTP 层其次：HTTP 非 `2xx` 直接失败，不进入业务 `isSuccess` 判断。
- 业务层最后：仅在 HTTP `2xx` 且 JSON 可解析时，才会执行 `isSuccess`。
- `isSuccess` 默认值：未配置时默认返回 `true`（即业务层默认成功）。
- `extractFailureReason` 调用时机：仅在 `isSuccess == false` 时调用。
- `extractFailureReason` 默认逻辑：尝试 `message/msg/error/reason/detail`，取不到使用兜底文案。
- 未配置拦截器时：所有 `intercept***` 系列接口直接失败，提示使用 `response***` 系列接口。

### 便捷配置（推荐）

```swift
let interceptor = DefaultInterceptor(
    extractData: { json, originalData in
        JSON.extractDataFromJSON(json["result"], originalData: originalData)
    },
    isSuccess: { json in
        // 告诉拦截器，响应的数据结构中 code 字段为 200 时表示请求成功
        json["code"].intValue == 200
    },
    extractFailureReason: { json, _ in
        json["message"].string
    }
)
```

### 不使用 `DefaultInterceptor` 时如何配置

你可以直接实现 `RequestInterceptorProtocol`，完全自定义请求与响应处理逻辑。

你也可以继承 `DefaultInterceptor`，只重写你关心的部分（例如 `isResponseSuccess`、`extractSuccessData`、`handleCustomError`）。

```swift
import Alamofire
import CryoNet

final class MyCustomInterceptor: RequestInterceptorProtocol, @unchecked Sendable {
    func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
        var request = urlRequest
        if let token = await tokenManager.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        if let error = response.error { return .failure(error) } // 网络层优先
        guard let httpResponse = response.response, 200..<300 ~= httpResponse.statusCode else {
            return .failure(NSError(domain: "HTTPError", code: response.response?.statusCode ?? -1))
        }
        guard let data = response.data else {
            return .failure(NSError(domain: "DataError", code: -1))
        }
        // 这里可按你的业务结构自行判断成功/失败并返回最终 Data
        return .success(data)
    }

    func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        interceptResponse(response)
    }
}
```

继承 `DefaultInterceptor` 示例：

```swift
import CryoNet
import SwiftyJSON

final class MyBusinessInterceptor: DefaultInterceptor, @unchecked Sendable {
    override func isResponseSuccess(json: JSON) -> Bool {
        json["status"] == "ok"
    }

    override func extractSuccessData(from json: JSON, data: Data) -> Result<Data, Error> {
        JSON.extractDataFromJSON(json["result"], originalData: data)
    }
}
```

### 自定义 Token 管理

```swift
final class MyTokenManager: TokenManagerProtocol, @unchecked Sendable {
    func getToken() async -> String? { "token" }
    func setToken(_ newToken: String) async {}
    func refreshToken() async -> String? { nil }
}
```

## 流式请求（SSE / JSON / Decodable）

```swift
let streamModel = RequestModel.streamRequest(path: "/stream", method: .get)
let stream = cryoNet.streamRequest(streamModel)

Task {
    do {
        for try await event in stream.sseStream() {
            print("SSE:", event)
        }
    } catch {
        print(error)
    }
}
```

可用流接口：
- `dataStream()`
- `jsonStream()`
- `modelStream(_:)`
- `decodableStream(_:)`
- `lineDelimitedDecodableStream(_:)`
- `sseStream()`
- `sseModelStream(_:)`
- `sseDecodableStream(_:)`

## 批量下载

下载与基础 `CryoNetConfiguration` 解耦，使用 `DownloadManager` 单独管理。

推荐流程：
- 创建 manager（设置并发数、可选 `baseURL`/全局 headers）
- 注册回调（任务状态、任务分组、整体进度）
- 批量创建并启动任务（`batchDownload`）或先注册再启动（`batchAddTasks` + `batchStart`）
- 根据业务控制任务（暂停/恢复/取消/移除）
- 通过查询方法读取当前任务分组（active/completed/failed/cancelled）

常用控制方法说明：
- `batchPause(ids:)`：暂停任务，可 `batchResume(ids:)` 恢复
- `batchCancel(ids:shouldDeleteFile:)`：取消任务，任务记录保留，可重新 `batchStart(ids:)`
- `batchRemove(ids:shouldDeleteFile:)`：彻底移除任务记录（可选删除本地文件）
- `removeAllTasks(shouldDeleteFile:)`：清空所有任务记录

非闭包获取状态：
- 下载支持 `DownloadManagerDelegate`，可以不用链式闭包
- 适合在 `ViewModel`/`Controller` 中统一接收状态事件

```swift
final class MyDownloadDelegate: DownloadManagerDelegate {
    func downloadDidUpdate(task: DownloadTask) {
        print("单任务:", task.id, task.state.rawValue, task.progress)
    }
    func downloadManagerDidUpdateActiveTasks(_ tasks: [DownloadTask]) {
        print("活跃任务数:", tasks.count)
    }
    func downloadManagerDidUpdateCompletedTasks(_ tasks: [DownloadTask]) {
        print("已完成任务数:", tasks.count)
    }
    func downloadManagerDidUpdateFailureTasks(_ tasks: [DownloadTask]) {
        print("失败任务数:", tasks.count)
    }
    func downloadManagerDidUpdateCancelTasks(_ tasks: [DownloadTask]) {
        print("已取消任务数:", tasks.count)
    }
    func downloadManagerDidUpdateProgress(overallProgress: Double, batchState: DownloadBatchState) {
        print("整体进度:", overallProgress, "批量状态:", batchState.rawValue)
    }
}

let delegate = MyDownloadDelegate()
await manager.addDelegate(delegate)
```

闭包获取状态：

```swift
let manager = DownloadManager(identifier: "videos", maxConcurrentDownloads: 3)

await manager
    .onDownloadDidUpdate { task in
        print("单任务:", task.id, task.state.rawValue, task.progress)
    }
    .onActiveTasksUpdate { tasks in
        print("活跃任务数:", tasks.count)
    }
    .onCompletedTasksUpdate { tasks in
        print("已完成任务数:", tasks.count)
    }
    .onFailedTasksUpdate { tasks in
        print("失败任务数:", tasks.count)
    }
    .onCancelTasksUpdate { tasks in
        print("已取消任务数:", tasks.count)
    }
    .onProgressUpdate { overall, batchState in
        print("整体进度:", overall, "批量状态:", batchState.rawValue)
    }

let ids = await manager.batchDownload(
    pathsOrURLs: [
        "https://example.com/a.mp4",
        "https://example.com/b.mp4"
    ],
    destinationFolder: nil,
    saveToAlbum: false
)

// 例如：暂停第一个，恢复全部，取消全部
if let first = ids.first {
    await manager.pauseTask(id: first)
}
await manager.batchResume(ids: ids)
await manager.batchCancel(ids: ids, shouldDeleteFile: false)

// 查询分组结果
let active = await manager.activeTasks()
let completed = await manager.completedTasks()
let failed = await manager.failedTasks()
let cancelled = await manager.cancelledTasks()
print(active.count, completed.count, failed.count, cancelled.count)
```

## 批量上传

上传使用泛型 `UploadManager<Model>`，`Model` 需实现 `JSONParseable`。

推荐流程：
- 先按服务端响应结构配置 `DefaultInterceptor`（决定成功码和数据字段）
- 初始化 `UploadManager<Model>`
- `addTask(files:)` 生成任务，`startTask(id:)` 或 `startAllTasks()` 启动
- 通过 `uploadDidUpdate` / `onProgressUpdate` / 各任务分组回调更新 UI
- 失败后可 `resumeTask(id:)` 或 `batchResume(ids:)` 重试，彻底删除用 `deleteTask(id:)`

常用控制方法说明：
- `pauseTask(id:)` / `resumeTask(id:)`：暂停与恢复
- `cancelTask(id:)`：取消任务（任务记录保留，可恢复）
- `deleteTask(id:)`：删除任务（不可恢复）
- `cancelAllTasks()` / `deleteAllTasks()`：全部取消或全部删除

非闭包获取状态：
- 当前上传管理器未提供 delegate 接口

```swift
final class UploadModel: JSONParseable {
    var url: String = ""
    required init?(json: JSON) {
        self.url = json["url"] ?? ""
    }
}

let uploadManager = UploadManager<UploadModel>(
    uploadURL: URL(string: "https://api.example.com/upload")!,
    parameters: ["key": "xxx"],
    maxConcurrentUploads: 3,
    interceptor: DefaultInterceptor(
        extractData: { json, originalData in
            JSON.extractDataFromJSON(json["data"], originalData: originalData)
        },
        isSuccess: { json in
            json["code"].intValue == 0
        },
        extractFailureReason: { json, _ in
            json["msg"].string
        }
    )
)

await uploadManager
    .uploadDidUpdate { task in
        print("单任务:", task.id, task.state.rawValue, task.progress)
    }
    .onTasksUpdate { tasks in
        print("总任务数:", tasks.count)
    }
    .onActiveTasksUpdate { tasks in
        print("活跃任务数:", tasks.count)
    }
    .onFailureTasksUpdated { tasks in
        print("失败任务数:", tasks.count)
    }
    .onCompletedTasksUpdate { tasks in
        print("完成任务数:", tasks.count)
    }
    .onProgressUpdate { overall, batchState in
        print("整体进度:", overall, "批量状态:", batchState.rawValue)
    }

let file = UploadFileItem(data: imageData, name: "file", fileName: "a.jpg", mimeType: "image/jpeg") // 构造上传文件项（内存数据）
let id = await uploadManager.addTask(files: [file]) // 注册任务，返回任务ID
await uploadManager.startTask(id: id) // 按任务ID启动上传

// 查询任务分组
let active = await uploadManager.activeTasks()
let completed = await uploadManager.completedTasks()
let failed = await uploadManager.failedTasks()
let cancelled = await uploadManager.cancelledTasks()
print(active.count, completed.count, failed.count, cancelled.count)
```

## 说明

- `RequestModel.applyBasicURL = false` 时不会拼接 `baseURL`。
- 超时优先级：`RequestModel.overtime > 0` 时使用请求级超时；否则回退到 `CryoNetConfiguration.defaultTimeout`。
- 批量上传/下载的 URL、headers、并发配置在各自 manager 内独立维护。
- 默认 `DefaultInterceptor` 不强依赖固定字段，建议通过 `isSuccess/extractData/extractFailureReason` 声明业务结构。
- 调试日志主要在 `DEBUG` 下输出。
- `DownloadManagerPool.removeManager/removeAll` 与 `UploadManagerPool.removeManager` 为 `async` 方法，调用时需要 `await`，返回时清理已完成。

## 资源

- 项目地址：https://github.com/snoux/CryoNet
- 文档地址：https://snoux.github.io/CryoNet
