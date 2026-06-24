# Changelog

## Unreleased

### 统一失败模型

- 新增 `CryoFailure`，统一表示 HTTP、业务、网络、解析、取消和未配置拦截器等失败。
- `CryoFailure.Kind` 新增 `authenticationExpired`、`http`、`business`、`network`、`decoding`、`cancelled`、`interceptorMissing` 和 `unknown`。
- `CryoFailure` 保留错误文案、HTTP 状态码、业务错误码、原始响应体和底层错误。
- HTTP 401 默认归类为 `authenticationExpired`，其他 HTTP 非 `2xx` 归类为 `http`。

### 拦截器的单一全局失败入口

`DefaultInterceptor` 新增可重写方法：

```swift
open func handleFailure(
    _ failure: CryoFailure,
    request: URLRequest?
)
```

- 使用支持 `CryoFailureHandling` 的拦截器处理 `intercept***` 响应时，HTTP、业务、网络和解析错误统一经过该入口。
- 该拦截器的全局处理始终先于当前请求的可选局部失败回调执行。
- 即使调用方未传入局部失败回调，已配置拦截器的 `handleFailure` 仍会执行。
- 同步回调与 async/await 拦截调用都遵循相同规则；直接 `response***` API 不在此入口的触发范围内。
- 普通拦截请求、SwiftyJSON 拦截请求、上传和下载失败均接入统一处理。
- 方法不保证在主线程执行，UI 动作需切换到 `MainActor`。

### 局部结构化失败回调

以下核心 API 新增 `failure: (CryoFailure) -> Void` 重载：

- `interceptModel`
- `interceptModelCompleteData`
- `interceptJSON`
- `interceptModelArray`
- `interceptJSONModel`
- `interceptJSONModelArray`

`interceptJSONModelAsync` 和 `interceptJSONModelArrayAsync` 现在直接抛出 `CryoFailure`，
不再将 HTTP、业务或解析错误降级为只包含文案的 `InterceptorError`。

原有 `failed: (String) -> Void` 保持兼容，无需修改现有调用代码。

### 业务错误码

- `ResponseStructureConfig` 新增 `extractBusinessCode(from:originalData:)`。
- `ResponseConfig` 和 `DefaultInterceptor` 便捷初始化方法新增 `extractBusinessCode` 闭包。
- 默认尝试读取 JSON 中的 `code` 字段。
- 提取结果保存到 `CryoFailure.businessCode`，可与 HTTP 状态码在同一 `handleFailure` 中处理。

### HTTP 响应判断

- 默认响应拦截器优先根据 `HTTPURLResponse.statusCode` 判断 HTTP 成败。
- HTTP `2xx` 继续执行 JSON 解析、`isSuccess` 业务判断和数据提取。
- HTTP 非 `2xx` 保留真实状态码和错误响应体，不再被 `.validate()` 生成的 `ValidationError(-1003)` 遮蔽。
- 保留 `.validate()`、401 Token 刷新和 Alamofire 自动重试机制。

### 验证

- 新增 HTTP 404 分类和错误响应体保留测试。
- 新增业务错误码提取测试。
- 新增全局失败处理先于局部回调执行的测试。
- `swift test` 全部通过。

### 认证状态与会话 revision

- 新增 `AuthenticationSessionManaging`，用户可注入自己的认证状态与持久化实现。
- 新增 Actor 实现 `DefaultAuthenticationSessionManager`，原子维护 `authenticated`、`loggingOut` 和 `unauthenticated` 状态。
- 会话 revision 使用 UUID，只进行相等性比较，不依赖大小顺序。
- 请求首次适配时捕获 revision，并保存到 `CryoFailure.authenticationRevision`。
- 登录、退出或切换账号后生成新的 UUID，可阻止旧会话延迟失败响应退出当前新会话。
- 多个 `CryoNet` 实例可共享同一个认证状态管理器。
- 框架不强制 Token 持久化方案；用户可使用自己的 Keychain、UserDefaults、数据库或账号系统。
