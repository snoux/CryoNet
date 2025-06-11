# CryoNet

CryoNet 是一款现代化、灵活且易于扩展的 Swift 网络请求与数据解析解决方案。它基于 Alamofire 和 SwiftyJSON 封装，支持异步/并发、灵活的 Token 与拦截器管理、多实例、模型驱动解析、本地 JSON 直转 Model 等特性，帮助你高效、优雅、可维护地构建网络层。

---

## 为什么选择 CryoNet

- **原生 URLSession/Alamofire 太繁琐？**  
  还在为参数封装、重复写数据解析、Token/刷新逻辑、调试日志痛苦吗？
- **现有网络库扩展性不够？**  
  难以支持多业务线、多 Token、多后端场景？
- **模型驱动开发与本地模拟数据不统一？**  
  希望本地 JSON、线上数据一键转 Model，无缝切换？

CryoNet 针对上述痛点重构自用私有网络库，为多项目、多业务线场景提供统一、易扩展的网络层解决方案。

---

## 主要特性

- 🚀 **多实例架构**：支持多 baseURL、业务线、独立配置
- 🧩 **模型驱动解析**：SwiftyJSON + JSONParseable，网络/本地数据一键转 Model
- 🛡️ **Token/拦截器可插拔**：自定义 Token 管理与权限校验，拦截器可精准获取所需数据
- 🧰 **链式/异步/回调 API**：支持 async/await 与回调风格
- 🔄 **批量下载与并发管理**：自定义最大并发下载数，实时进度回调
- 🧪 **本地 JSON 解析**：无需网络即可将本地 JSON/Data 解析为模型
- 🛠 **高度可扩展**：配置、拦截器、Token 管理、下载目录等均可自定义

---

## 安装

**仅支持 Swift Package Manager**

1. 打开你的 Xcode 项目（或 workspace）
2. 菜单栏选择：File > Add Packages...
3. 输入 `https://github.com/snow-xf/CryoNet.git`
4. 选择 `main` 分支（开发中，代码随时更新），点击 `Add Package`
5. Xcode 会自动拉取并集成

---

## 快速开始

### 1. 创建实例

**配置结构体初始化,每个实例独立互不干扰**

```swift
import CryoNet

let net = CryoNet(configuration: CryoNetConfiguration(
    basicURL: "https://api.example.com",
    basicHeaders: [HTTPHeader(name: "Content-Type", value: "application/json")],
    defaultTimeout: 15,
    maxConcurrentDownloads: 4,
    tokenManager: MyTokenManager(),    // 可自定义
    interceptor: MyRequestInterceptor() // 可自定义
))
```

**链式自定义配置：**

```swift
let net = CryoNet { config in
    config.basicURL = "https://api.example.com"
    config.defaultTimeout = 20
    config.tokenManager = MyTokenManager()
}
```

### 2. 组织与管理 API

推荐用 `struct + static`、`enum` 管理接口，模块化分文件：

```swift
struct API_User {
    static let getUser = RequestModel(url: "/user", method: .get, explain: "获取用户信息")
}
struct API_Login {
    static let login = RequestModel(url: "/login", method: .get, explain: "登录接口")
}
```

---

## 典型用法示例

### 1. 基本请求与 JSON 响应

```swift
net.request(API_User.getUser)
   .responseJSON { json in
        print(json["name"].stringValue)
   } failed: { error in
        print(error.localizedDescription)
   }
```

### 2. 直接响应为 Model

#### 定义 Model

```swift
struct User: JSONParseable {
    let id: Int
    let name: String
    let email: String?

    init?(json: JSON) {
        guard json["id"].exists() else { return nil }
        self.id = json.int("id")
        self.name = json.string("name")
        self.email = json.optionalString("email")
    }
}
```

#### 网络响应直接转 Model

```swift
net.request(API_User.getUser)
    .responseJSONModel(type: User.self) { user in
        print("User: \(user.name)")
    } failed: { error in
        print(error.localizedDescription)
    }
```

### 3. 拦截器精准提取数据（如只取 data 字段）

假设你的响应为：

```json
{
    "reason": "success",
    "result": {
        "stat": "1",
        "data": [...]
    },
    "error_code": 0
}
```

**自定义响应结构解析：**

```swift
final class MyResponseConfig: DefaultResponseStructure, @unchecked Sendable {
    init() {
        super.init(
            codeKey: "error_code",  // 状态码 key path
            messageKey: "reason",  //  说明 key path 
            dataKey: "result",  // 结果 key path
            successCode: 0  // 表示成功的 key path
        )
    }

    // 重写 extractData 方法 ，返回需要的数据（一般来说数据仅有一层仅需要调用super.init进行配置即可，无需再重写该方法，但深层数据必须重写该方法返回正确的数据）
    override func extractData(from json: JSON, originalData: Data) -> Result<Data, any Error> {
        let targetData = json[dataKey]["data"]

        do {
            let validData: Data = try targetData.rawData()
            return .success(validData)
        } catch {
            return .failure(NSError(
                domain: "DataError",
                code: -1004,
                userInfo: [
                    NSLocalizedDescriptionKey: "数据转换失败",
                    NSUnderlyingErrorKey: error
                ]
            ))
        }
    }
    // 重写 isSuccess 方法，告诉拦截器请求是否成功（一般来说可以不用实现该方法，响应会从配置中做验证，状态码层级较深时必须实现，否则将判断失效）
    override func isSuccess(json: JSON) -> Bool {
        return json[codeKey].intValue == successCode
    }
}
```


**拦截器注入：**

```swift
class MyInterceptor: DefaultInterceptor, @unchecked Sendable {
    init() {
        let responseConfig = MyResponseConfig()
        super.init(responseConfig: responseConfig)
    }
}
```

**用法：**

```swift
let net = CryoNet { config in
    config.basicURL = "https://api.example.com"
    config.interceptor = MyInterceptor()
}
```

或在请求时指定：

```swift
await net.request(API_News.index, interceptor: MyInterceptor())
    .interceptJSONModelArray(type: NewsModel.self) { value in
        self.newsList = value
    } failed: { error in
        print("失败原因:\(error)")
    }
```

**控制台打印：**
> 完整的日志打印（如遇异常会打印完整数据，帮助与后端对接调试）
<img width="1274" alt="image" src="https://github.com/user-attachments/assets/289a9b93-4d16-42e3-af17-a16c3e85efd7" />



---

### 4. 本地 JSON/Data 解析为 Model（无需网络）

```swift
let jsonString = """
{
    "id": 1,
    "name": "Tom"
}
"""
if let data = jsonString.data(using: .utf8),
   let json = try? JSON(data: data),
   let user = json.toModel(User.self) {
    print(user.name)
}
```

---

### 5. 批量下载与进度管理

```swift
let downloadModel = DownloadModel(models: [...], savePathURL: ...)

await net.downloadFile(
    downloadModel,
    progress: { item in
        print("进度: \(item.progress)")
    },
    result: { downloadResult in
        print("单项下载完成: \(downloadResult.downLoadItem)")
    }
)
```

---

## 拦截器与 Token 管理

### 1. 自定义 TokenManager/Interceptor

```swift
class MyTokenManager: TokenManagerProtocol {
    // 实现协议，管理 accessToken/refreshToken
}

class MyRequestInterceptor: RequestInterceptorProtocol {
    // 实现协议，统一添加 Token、处理 401 等
}
```

### 2. 注入实例

```swift
let net = CryoNet { config in
    config.basicURL = "..."
    config.tokenManager = MyTokenManager()
    config.interceptor = MyRequestInterceptor()
}
```

### 3. 动态配置/Token 更新

```swift
await net.updateConfiguration { config in
    config.tokenManager = NewTokenManager()
}
```

---

## 扩展与自定义

- 所有配置、拦截器、Token 管理等均可自定义扩展，满足多业务线、复杂场景需求
- 支持本地/远程 JSON、Data 解析与模型转换
- 支持多实例、动态切换 baseURL、独立 Token、拦截器

---

## 贡献与反馈

CryoNet 致力于让 Swift 网络开发更高效、安全、优雅。欢迎 Star及反馈建议！

更多高级用法和 API 参考，请查阅源码与即将发布的 Demo。

---

**如需详细代码示例或深入用法，欢迎联系作者或关注仓库更新。**
