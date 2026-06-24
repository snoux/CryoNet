# CryoNet

基于 Alamofire + SwiftyJSON 的 Swift 网络层封装，适用于 iOS/macOS/tvOS/watchOS。

`CryoNet` 主要做了三件事：
- 统一请求配置（`baseURL`、默认 `headers`、超时、token、拦截器）
- 统一响应处理（`Data` / `JSON` / `Decodable` / `JSONParseable`）
- 提供独立的批量上传与下载管理器（并发、队列、状态回调）

## 本次更新：统一失败模型与全局处理入口

本次更新保持原有 `failed(String)` 调用方式可用，将 HTTP、业务、网络和解析失败统一为 `CryoFailure`，并由拦截器的 `handleFailure` 作为唯一全局处理入口。

主要变化：

- 收到 HTTP 响应时，以 `HTTPURLResponse.statusCode` 作为 HTTP 成败的最终依据。
- HTTP `2xx` 继续执行 JSON 解析、业务成功判断和模型转换。
- HTTP 非 `2xx` 直接返标准化 HTTP 错误，不再统一降级为 `ValidationError(-1003)`。
- `CryoFailure` 保留 `kind`、`statusCode`、`businessCode`、`responseData` 和底层错误。
- 新增 `handleFailure(_ failure:request:)`：使用支持 `CryoFailureHandling` 的拦截器处理 `intercept***` 响应时，最终失败会先经过该方法。
- 新增 `failure: (CryoFailure) -> Void` 局部回调，仅在当前请求需要额外处理时传入。
- 新增 `extractBusinessCode`，用于提取服务端业务错误码。
- 新增可选 `AuthenticationSessionManaging` 与默认 Actor 实现，使用 UUID revision 防止并发重复退出及旧请求影响新会话。
- 保留 `.validate()` 和现有 401 Token 刷新、自动重试机制。

失败流转顺序：

```text
收到响应
├─ HTTP 非 2xx
│  ├─ 401 先按现有机制刷新 Token 并重试
│  └─ 不再重试或重试后仍失败
│     → CryoFailure(.http / .authenticationExpired)
├─ HTTP 2xx
│  → 处理底层错误
│  → 解析 JSON
│  → isSuccess
│  ├─ 业务成功 → extractData / 完整响应体 → success
│  └─ 业务失败 → CryoFailure(.business)
└─ 未收到 HTTP 响应
   → CryoFailure(.network / .cancelled)

使用支持 CryoFailureHandling 的拦截器处理 intercept*** 响应时
→ handleFailure（该拦截器的全局处理）
→ failure / failed（当前请求，可选）
```

兼容性说明：

- 原有 `failed: (String) -> Void` 保留，旧代码不需要修改。
- 原有 `success` 回调、业务数据提取和模型解析方式不变。
- `handleFailure` 只属于当前请求使用的拦截器；未配置拦截器，或自定义拦截器未实现 `CryoFailureHandling` 时，不会调用。
- `DefaultInterceptor.handleFailure` 默认为空实现，不重写时不会产生额外动作。
- 全局 `handleFailure` 不会吞掉当前请求的局部失败回调。
- 详细变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 安装

通过 Swift Package Manager：

```swift
https://github.com/snoux/CryoNet.git
```

备用地址
```swift
https://gitee.com/snoux/CryoNet.git
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
            // 自定义数据提取逻辑：提取业务字段（按照自己服务端数据结构直接提取相应层级数据）
            JSON.extractDataFromJSON(json["data"], originalData: originalData)
        },
        isSuccess: { json in
            // 自定义成功判断逻辑（按照自己服务端状态码判断请求是否正确，失败则进入failed）
            return json["code"].intValue == 0
        },
        extractFailureReason: { json, _ in
            // 自定义失败原因提取逻辑（直接从服务端响应数据中提取失败信息）
            json["msg"].string
        }
    )
}
```

你也可以在初始化 `CryoNet` 时不配置全局拦截器。
这种情况下：
- 普通 `response***` 系列仍可正常使用。
- 如果要使用 `intercept***` 系列，请在 `request(..., interceptor:)` 为该请求显式传入拦截器。
- 未配置拦截器却调用 `intercept***` 时会直接失败（错误信息：`未配置拦截器，请使用response***获取响应数据`）。

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

`interceptModelArray` 使用 `JSONDecoder`，因此模型必须实现 `Codable`；
`interceptJSONModelArray` 使用 SwiftyJSON，模型必须实现 `JSONParseable`。
模型协议与 API 不匹配时，Xcode 可能不会补全或高亮对应方法。

Async 写法使用 `do/catch` 捕获失败：

```swift
Task {
    do {
        let list = try await cryoNet
            .request(API.newsList)
            .interceptJSONModelArrayAsync(NewsItem.self)

        await MainActor.run {
            self.newsList = list
        }
    } catch {
        guard let failure = error as? CryoFailure else {
            print(error.localizedDescription)
            return
        }

        switch failure.kind {
        case .authenticationExpired:
            print("登录状态已失效")

        case .http:
            print("HTTP 错误：\(failure.statusCode ?? -1)")

        case .business:
            print("业务错误：\(failure.businessCode ?? -1)")

        default:
            print(failure.message)
        }
    }
}
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

- HTTP 响应优先：收到 HTTP 响应时，非 `2xx` 直接失败，不进入业务 `isSuccess` 判断。
- 网络层错误：HTTP `2xx` 或未收到 HTTP 响应时，再处理超时、断网、DNS/TLS、请求取消等错误。
- 业务层最后：仅在 HTTP `2xx` 且 JSON 可解析时，才会执行 `isSuccess`。
- `isSuccess` 默认值：未配置时默认返回 `true`（即业务层默认成功）。
- `extractFailureReason` 调用时机：仅在 `isSuccess == false` 时调用。
- `extractFailureReason` 默认逻辑：尝试 `message/msg/error/reason/detail`，取不到使用兜底文案。
- 拦截器优先级：`request(..., interceptor:)` 传入的请求级拦截器优先；未传时回退到 `CryoNetConfiguration.interceptor`。
- 未配置拦截器时：所有 `intercept***` 系列接口直接失败，提示使用 `response***` 系列接口。

### 默认 HTTP 错误映射

| HTTP 状态码 | `NSError.domain` | `NSError.code` | 默认文案 |
| --- | --- | ---: | --- |
| 400 | `ClientError` | 400 | 请求参数错误 |
| 401 | `AuthError` | 401 | 身份验证失败 |
| 403 | `AuthError` | 403 | 访问被拒绝 |
| 404 | `ClientError` | 404 | 资源未找到 |
| 405 | `ClientError` | 405 | 方法不被允许 |
| 500...599 | `ServerError` | 原始状态码 | 服务器错误 |
| 其他非 2xx | `HTTPError` | 原始状态码 | 未知HTTP错误 |

HTTP 错误的 `userInfo` 会尽可能包含：

```swift
let nsError = error as NSError
let statusCode = nsError.userInfo["statusCode"] as? Int
let responseCode = nsError.userInfo["responseCode"] as? Int
let responseData = nsError.userInfo["responseData"] as? Data
let originalData = nsError.userInfo["originalData"] as? Data
let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error
```

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

### 统一失败模型

`CryoFailure` 为全局处理和当前请求提供相同的结构化信息：

| 属性 | 说明 |
| --- | --- |
| `kind` | 失败类别，包含认证失效、HTTP、业务、网络、解析、取消等 |
| `message` | 用于日志或用户提示的错误文案 |
| `statusCode` | HTTP 状态码，无 HTTP 响应时为 `nil` |
| `businessCode` | 服务端业务错误码 |
| `authenticationRevision` | 请求首次适配时捕获的认证会话 UUID revision |
| `responseData` | 服务端原始响应体 |
| `underlyingError` | Alamofire、URLSession 或解析器的底层错误 |

`CryoFailure.Kind` 包含：

- `.authenticationExpired`：HTTP 401 等认证失效。
- `.http`：其他 HTTP 非 `2xx`。
- `.business`：HTTP 成功，但业务成功判断未通过。
- `.network`：超时、断网、DNS、TLS 等网络失败。
- `.decoding`：JSON 或模型转换失败。
- `.cancelled`：请求被取消。
- `.interceptorMissing`：未配置拦截器却调用 `intercept***`。
- `.unknown`：其他未归类错误。

四个接口的适用场景：

| API | 成功时解析的数据 | 典型用途 |
| --- | --- | --- |
| `interceptModel` | `extractData` 提取后的业务数据 | 单个业务模型 |
| `interceptModelArray` | `extractData` 提取后的业务数组 | 业务列表 |
| `interceptModelCompleteData` | 服务端完整 JSON 响应体 | 需要 `code/message/data` 包装层的模型 |
| `interceptJSON` | 服务端完整 JSON 响应体 | 需要手动读取完整 JSON |

`完整响应体` 指 HTTP `2xx` 且业务成功时的服务端完整 JSON。底层对应 `interceptResponseWithCompleteData`；业务方通常使用 `interceptModelCompleteData` 或 `interceptJSON`。

### 拦截器的单一全局失败入口

继承 `DefaultInterceptor` 并重写 `handleFailure`，即可统一处理所有使用该拦截器的 `intercept***` 请求产生的 HTTP、业务、网络和解析失败。同步回调与 async/await 调用的规则相同。

`response***` 系列是不经过业务响应拦截的直接响应 API，不属于这个全局入口的触发范围。

```swift
import CryoNet
import Foundation

/// App 全局会话与提示协调器。
/// 实际项目中可以替换为路由器、Toast 管理器或依赖注入服务。
@MainActor
final class AppSessionCoordinator {
    static let shared = AppSessionCoordinator()

    func requireLogin() {
        // 清理本地会话并跳转登录页
    }

    func showMessage(_ message: String) {
        // 展示 Toast / Alert
    }
}

/// 全局业务拦截器。
final class AppInterceptor: DefaultInterceptor, @unchecked Sendable {
    override func handleFailure(_ failure: CryoFailure, request: URLRequest?) {
        // 响应回调不保证在主线程，UI 动作需要切换到 MainActor。
        Task { @MainActor in
            if failure.statusCode == 401 || failure.businessCode == 10001 {
                AppSessionCoordinator.shared.requireLogin()
                return
            }

            switch failure.kind {
            case .http where failure.statusCode == 403:
                AppSessionCoordinator.shared.showMessage("没有访问权限")
            case .http where (500...599).contains(failure.statusCode ?? 0):
                AppSessionCoordinator.shared.showMessage("服务器异常，请稍后再试")
            case .business:
                AppSessionCoordinator.shared.showMessage(failure.message)
            default:
                break
            }
        }
    }
}
```

`handleFailure` 可能从非主线程调用，UI 操作需要显式切换到 `MainActor`。多个并发请求可能同时返回登录失效，建议会话管理器对退出登录动作做幂等保护。

#### 并发安全注意事项

`CryoFailure` 是每次失败独立创建的不可变值，`businessCode` 不是全局变量，多个请求或多个 `CryoNet` 实例之间不会相互覆盖。但 `handleFailure` 可能被多个并发请求同时调用，因此需要对以下共享动作自行保证幂等与线程安全：

- 清理登录信息与跳转登录页。
- 展示 Toast 或 Alert。
- 写入共享状态或数据库。
- 上报错误日志与监控事件。

框架提供可选的 `DefaultAuthenticationSessionManager` Actor，用于原子维护登录状态和 UUID 会话 revision。revision 仅用于相等性比较：登录、退出或切换账号后生成新的 UUID；请求首次适配时会捕获当时的 revision，并保存到 `CryoFailure.authenticationRevision`。

使用默认状态管理器：

```swift
let tokenManager = MyTokenManager()

// App 启动时根据用户自己的持久化 Token 恢复登录状态。
let authenticationSession =
    await DefaultAuthenticationSessionManager.restore(
        using: tokenManager
    )

final class AppInterceptor: DefaultInterceptor, @unchecked Sendable {
    override func handleFailure(_ failure: CryoFailure, request: URLRequest?) {
        let requiresLogin =
            failure.statusCode == 401 ||
            failure.businessCode == 10001

        guard requiresLogin else { return }

        Task {
            // revision 比较与 authenticated -> loggingOut 在 Actor 内原子完成。
            guard let authenticationSession,
                  await authenticationSession.beginLogoutIfCurrent(
                      expectedRevision: failure.authenticationRevision
                  ) else {
                return
            }

            // 清除 Token 的具体持久化方式仍由用户自己的账号系统负责。
            await MainActor.run {
                // SessionManager.shared.clearSession()
                // Router.shared.showLogin()
            }

            await authenticationSession.markLoggedOut()
        }
    }
}

let interceptor = AppInterceptor(
    extractData: { json, originalData in
        JSON.extractDataFromJSON(json["data"], originalData: originalData)
    },
    isSuccess: { json in
        json["code"].intValue == 0
    },
    extractFailureReason: { json, _ in
        json["message"].string
    },
    extractBusinessCode: { json, _ in
        json["code"].int
    },
    authenticationSession: authenticationSession
)
```

登录成功后，用户先持久化 Token，再更新框架运行期状态：

```swift
await tokenManager.setToken(newToken)
await authenticationSession.markAuthenticated()
```

用户也可以实现 `AuthenticationSessionManaging`，使用自己的 Actor、Keychain、UserDefaults、数据库或账号系统。自定义实现必须保证 `beginLogoutIfCurrent(expectedRevision:)` 中的 revision 比较与状态切换是原子操作。

```swift
actor AppAuthenticationSession: AuthenticationSessionManaging {
    private var state: AuthenticationState
    private var revision = UUID()

    init(hasPersistedToken: Bool) {
        state = hasPersistedToken ? .authenticated : .unauthenticated
    }

    func snapshot() -> AuthenticationSnapshot {
        AuthenticationSnapshot(state: state, revision: revision)
    }
    // 自行当前会话是否登录
    func beginLogoutIfCurrent(expectedRevision: UUID?) -> Bool {
        return true
    }
    // 已认证（登录）
    func markAuthenticated() {
        revision = UUID()
        state = .authenticated
    }
    // 退出登录
    func markLoggedOut() {
        // 可在调用本方法前由用户自己的账号系统清除持久化 Token。
        revision = UUID()
        state = .unauthenticated
    }
}
```

如果多个 `CryoNet` 实例或不同拦截器共享同一登录状态，应注入同一个 `AuthenticationSessionManaging` 实例。不要在拦截器中保存 `currentBusinessCode`、`currentFailure` 等可变的“当前请求”状态。

状态与 revision 规则：

- `.authenticated`：允许一次调用原子切换到 `.loggingOut`。
- `.loggingOut`：并发登录失效请求不再重复执行退出操作。
- `.unauthenticated`：忽略后续登录失效请求。
- `markAuthenticated()`：生成新 UUID revision 并切换为已登录。
- `markLoggedOut()`：生成新 UUID revision 并切换为未登录。
- 旧请求携带的 revision 与当前 revision 不一致时，不能退出当前新会话。
- revision 通常不需要持久化；App 重启后旧进程请求已不存在，启动时重新生成 UUID 即可。

HTTP 401 仍会先由 Alamofire `RequestRetrier` 尝试刷新 Token 并重试；只有刷新失败或重试后仍然失败才进入 `handleFailure`。HTTP 200 下的业务登录失效码会直接进入 `handleFailure`。如果该业务码也需要自动刷新并重放原请求，则需要额外的异步业务重试机制，不建议在 `handleFailure` 中直接重放 `URLRequest`。

> `handleFailure` 不依赖局部 `failed` / `failure` 闭包，但仍需要通过 `interceptModel`、`interceptJSON` 等响应 API 消费响应，才能解析服务端业务状态。仅创建 `request()` 而不注册任何响应处理时，业务 JSON 不会被解析。

### 完整接入示例

以如下服务端响应为例：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 1001,
    "name": "CryoNet"
  }
}
```

1. 定义业务模型和请求：

```swift
import Alamofire
import CryoNet

struct User: Codable {
    let id: Int
    let name: String
}

struct APIResponse<T: Codable>: Codable {
    let code: Int
    let message: String
    let data: T
}

enum API {
    static let userDetail = RequestModel(
        path: "/users/detail",
        method: .get,
        encoding: .urlDefault,
        explain: "用户详情"
    )
}
```

2. 创建全局拦截器并配置 `CryoNet`：

```swift
let appInterceptor = AppInterceptor(
    extractData: { json, originalData in
        // interceptModel / interceptModelArray 成功时只返回 data 字段。
        JSON.extractDataFromJSON(json["data"], originalData: originalData)
    },
    isSuccess: { json in
        // 只有 HTTP 2xx 才会执行该业务成功判断。
        json["code"].intValue == 0
    },
    extractFailureReason: { json, _ in
        // HTTP 2xx 但 code != 0 时，生成 BusinessError 文案。
        json["message"].string
    },
    extractBusinessCode: { json, _ in
        // 保存到 CryoFailure.businessCode，供全局 handleFailure 判断。
        json["code"].int
    }
)

let cryoNet = CryoNet { config in
    config.baseURL = "https://api.example.com"
    config.defaultTimeout = 30
    config.basicHeaders = [
        .init(name: "Content-Type", value: "application/json")
    ]
    config.tokenManager = MyTokenManager()
    config.interceptor = appInterceptor
}
```

3. 只解析 `data` 字段。全局失败处理不依赖局部失败回调：

```swift
cryoNet.request(
    API.userDetail,
    parameters: ["id": 1001]
)
.interceptModel(
    type: User.self,
    success: { user in
        // HTTP 2xx + code == 0 + User 解码成功。
        print("用户: \(user.name)")
    }
)
```

4. 当前页面需要额外处理时，再传入结构化 `failure` 回调：

```swift
cryoNet.request(API.userDetail, parameters: ["id": 1001])
    .interceptModel(
        type: User.self,
        success: { user in
            updateUI(user)
        },
        failure: { failure in
            // 全局 handleFailure 已经先执行。
            stopLoading()

            switch failure.kind {
            case .network:
                showRetryButton()
            case .decoding:
                print("解析失败: \(failure.message)")
            default:
                break
            }
        }
    )
```

5. 如果模型需要包含 `code/message/data` 完整包装层，使用 `interceptModelCompleteData`：

```swift
cryoNet.request(API.userDetail, parameters: ["id": 1001])
    .interceptModelCompleteData(
        type: APIResponse<User>.self,
        success: { response in
            print(response.code)
            print(response.message)
            print(response.data.name)
        },
        failure: { failure in
            print("请求失败: \(failure.message)")
        }
    )
```

6. 原有字符串失败回调仍可使用：

```swift
cryoNet.request(API.userDetail, parameters: ["id": 1001])
    .interceptModel(
        type: User.self,
        success: { user in
            print(user)
        },
        failed: { message in
            // 兼容旧代码，但这里只能获取错误文案。
            print(message)
        }
    )
```

全局与局部处理的职责建议：

- `handleFailure`：处理退出登录、全局提示、日志、监控上报等所有请求的公共动作。
- `failure(CryoFailure)`：当前页面停止 loading、展示空态、提供重试按钮等局部动作。
- `failed(String)`：保留给旧代码或只需错误文案的简单场景。

### 不使用 `DefaultInterceptor` 时如何配置

你可以直接实现 `RequestInterceptorProtocol`，完全自定义请求与响应处理逻辑。如果仍需要统一全局失败入口，同时实现 `CryoFailureHandling`。

你也可以继承 `DefaultInterceptor`，只重写你关心的部分（例如 `isResponseSuccess`、`extractSuccessData`、`handleCustomError`）。

```swift
import Alamofire
import CryoNet

final class MyCustomInterceptor: RequestInterceptorProtocol, CryoFailureHandling, @unchecked Sendable {
    func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
        var request = urlRequest
        if let token = await tokenManager.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        if let httpResponse = response.response, !(200..<300).contains(httpResponse.statusCode) {
            return .failure(NSError(domain: "HTTPError", code: httpResponse.statusCode))
        }
        if let error = response.error { return .failure(error) }
        guard let data = response.data else {
            return .failure(NSError(domain: "DataError", code: -1))
        }
        // 这里可按你的业务结构自行判断成功/失败并返回最终 Data
        return .success(data)
    }

    func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        interceptResponse(response)
    }

    func handleFailure(_ failure: CryoFailure, request: URLRequest?) {
        // 统一处理使用当前拦截器的 intercept*** 最终失败
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
- 简单Demo: https://gitee.com/snoux/cryo-net-demo.git
