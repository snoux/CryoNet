# CryoNet

基于 Alamofire + SwiftyJSON 的 Swift 网络层封装，适用于 iOS/macOS/tvOS/watchOS。

`CryoNet` 主要做了三件事：
- 统一请求配置（`basicURL`、默认 `headers`、超时、token、拦截器）
- 统一响应处理（`Data` / `JSON` / `Decodable` / `JSONParseable`）
- 提供独立的批量上传与下载管理器（并发、队列、状态回调）

## 安装

通过 Swift Package Manager：

```swift
https://github.com/snoux/CryoNet.git
```

依赖：
- Alamofire `>= 5.10.2`
- SwiftyJSON `>= 5.0.2`

## 快速开始

### 1) 初始化

```swift
import CryoNet

let cryoNet = CryoNet { config in
    config.basicURL = "https://api.example.com"
    config.defaultTimeout = 30
    config.basicHeaders = [
        .init(name: "Content-Type", value: "application/json")
    ]
    config.tokenManager = DefaultTokenManager()
    config.interceptor = DefaultInterceptor(
        codeKey: "code",
        messageKey: "msg",
        dataKey: "data",
        successCode: 0,
        extractData: { json, originalData in
            // 自定义数据提取逻辑：返回完整数据
            return .success(originalData)
        },
        isSuccess: { json in
            // 自定义成功判断逻辑
            return json["code"].intValue == 0
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
```

## 拦截器与 Token

### 便捷配置（推荐）

```swift
let interceptor = DefaultInterceptor(
    codeKey: "code",
    messageKey: "message",
    dataKey: "result",
    successCode: 200,
    isSuccess: { json in
        // 告诉拦截器，响应的数据结构中code字段数据为200时表示请求成功
        json["code"].intValue == 200
    }
)
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
    interceptor: DefaultInterceptor(codeKey: "code", messageKey: "msg", dataKey: "data", successCode: 0)
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

- `RequestModel.applyBasicURL = false` 时不会拼接 `basicURL`。
- 超时优先级：`RequestModel.overtime > 0` 时使用请求级超时；否则回退到 `CryoNetConfiguration.defaultTimeout`。
- 批量上传/下载的 URL、headers、并发配置在各自 manager 内独立维护。
- 默认 `DefaultInterceptor` 会按 `codeKey/messageKey/dataKey` 解析业务结构。
- 调试日志主要在 `DEBUG` 下输出。
- `DownloadManagerPool.removeManager/removeAll` 与 `UploadManagerPool.removeManager` 为 `async` 方法，调用时需要 `await`，返回时清理已完成。

## 资源

- 项目地址：https://github.com/snoux/CryoNet
- 文档地址：https://snoux.github.io/CryoNet
