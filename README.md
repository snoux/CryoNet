# CryoNet

CryoNet 是一个基于 Alamofire 和 SwiftyJSON 的轻量级网络请求框架，专为 Swift 项目设计。它提供了简洁易用的 API，支持多种数据解析方式，并具有强大的错误处理和拦截器功能。**（开发测试中）**

原项目是本人为方便维护整理项目中的请求而进行封装的私有库，原名为`XFRequest`，它现在依旧在我的私有库存放。`CryoNet`在此基础上进行了优化

`XFRequest`中我写了一个工具类专门用来处理数据，本框架中我将其进行了删除，统一调整使用`SwiftyJSON`来处理数据。



## 特性

- **简洁的 API**：链式调用，简化网络请求代码
- **灵活的数据解析**：支持 SwiftyJSON 直接解析为模型，无需使用 JSONDecoder
- **强大的拦截器**：支持请求和响应拦截，轻松处理认证和错误
- **完整的类型支持**：支持 Swift 的强类型特性
- **异步/等待支持**：提供现代化的 async/await API
- **上传/下载支持**：简化文件上传和下载操作
- **全面的错误处理**：详细的错误信息和调试日志
- **可扩展性**：易于扩展和定制

## 安装

### Swift Package Manager

在 `Package.swift` 文件中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/snow-xf/CryoNet.git")
]
```

然后在需要使用的文件中导入：

```swift
import CryoNet
```

## 基本用法

### 初始化

```swift
// 设置基础 URL
let request = CryoNet.sharedInstance("https://api.example.com")
```

### 发送 GET 请求

```swift
// 创建请求模型
let model = RequestModel(
    url: "/users",
    method: .get
)

// 发送请求
request.request(model)
    .responseJSON { json in
        print(json)
    } failed: { error in
        print(error.localizedDescription)
    }
```

### 发送 POST 请求

```swift
// 创建请求模型
let model = RequestModel(
    url: "/users",
    method: .post,
    parameters: ["name": "John", "email": "john@example.com"]
)

// 发送请求
request.request(model)
    .responseJSON { json in
        print(json)
    } failed: { error in
        print(error.localizedDescription)
    }
```

### 使用 async/await

```swift
do {
    let model = RequestModel(url: "/users", method: .get)
    let json = try await request.request(model).responseJSONAsync()
    print(json)
} catch {
    print(error.localizedDescription)
}
```

## 数据解析

### 使用 SwiftyJSON

```swift
request.request(model)
    .responseJSON { json in
        let name = json["name"].stringValue
        let age = json["age"].intValue
        print("Name: \(name), Age: \(age)")
    }
```

### 使用 JSONParseable 协议解析为模型

首先定义符合 JSONParseable 协议的模型：

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

然后直接解析为模型：

```swift
request.request(model)
    .responseJSONModel(type: User.self) { user in
        print("User: \(user.name), Email: \(user.email ?? "N/A")")
    } failed: { error in
        print(error.localizedDescription)
    }
```

### 使用自定义解析闭包

```swift
request.request(model)
    .responseJSONModel(parser: { json in
        guard json["id"].exists() else { return nil }
        
        return User(
            id: json.int("id"),
            name: json.string("name"),
            email: json.optionalString("email")
        )
    }) { user in
        print("User: \(user.name)")
    }
```

### 处理嵌套 JSON

```swift
// 处理嵌套的JSON路径
request.request(model)
    .responseJSONModel(type: User.self, keyPath: "data.user") { user in
        print("User: \(user.name)")
    }

// 处理嵌套的JSON字符串
request.request(model)
    .responseJSON { json in
        let userJson = json.parseNestedJSON("data")["user"]
        if let user = userJson.toModel(User.self) {
            print("User from nested JSON string: \(user.name)")
        }
    }
```

## 拦截器

### 创建拦截器

```swift
class MyInterceptor: RequestInterceptorProtocol {
    func interceptRequest(_ request: URLRequest) -> URLRequest {
        var mutableRequest = request
        // 添加认证头
        mutableRequest.addValue("Bearer token", forHTTPHeaderField: "Authorization")
        return mutableRequest
    }
    
    func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        // 处理响应
        switch response.result {
        case .success(let data):
            if let data = data {
                // 检查API状态码
                let json = try? JSON(data: data)
                if let code = json?["code"].int, code != 200 {
                    let message = json?["message"].stringValue ?? "Unknown error"
                    return .failure(NSError(domain: "APIError", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
                }
                // 返回数据部分
                if let dataJson = json?["data"], let dataData = try? dataJson.rawData() {
                    return .success(dataData)
                }
            }
            return .failure(NSError(domain: "APIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data"]))
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
        // 返回完整响应
        switch response.result {
        case .success(let data):
            if let data = data {
                return .success(data)
            }
            return .failure(NSError(domain: "APIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty data"]))
        case .failure(let error):
            return .failure(error)
        }
    }
}
```

### 使用拦截器

```swift
// 设置拦截器
CryoNet.setInterceptor(MyInterceptor())

// 使用拦截器处理响应
request.request(model)
    .interceptJSON { json in
        print("Intercepted JSON: \(json)")
    } failed: { error in
        print("Error: \(error)")
    }

// 获取拦截器处理后的模型
request.request(model)
    .interceptJSONModel(type: User.self) { user in
        print("User: \(user.name)")
    } failed: { error in
        print("Error: \(error)")
    }
```

## 上传文件

```swift
// 创建上传数据
let imageData = UIImage(named: "example")?.jpegData(compressionQuality: 0.8)
let uploadData = UploadData(
    file: .fileData(imageData),
    name: "file",
    fileName: "image.jpg"
)

// 创建请求模型
let model = RequestModel(url: "/upload", method: .post)

// 上传文件
request.upload(model, files: [uploadData])
    .progress { progress in
        print("上传进度: \(progress)")
    }
    .responseJSON { json in
        print("上传成功: \(json)")
    } failed: { error in
        print("上传失败: \(error.localizedDescription)")
    }
```

## 下载文件

```swift
// 创建下载项
let item = DownloadItem(
    fileName: "example.pdf",
    filePath: "https://example.com/files/example.pdf"
)
let model = DownloadModel(savePath: nil, models: [item])

// 下载文件
request.downloadFile(model) { item in
    print("下载进度: \(item.progress)")
} result: { result in
    switch result.result {
    case .success(let url):
        print("下载成功: \(url?.path ?? "")")
    case .failure(let error):
        print("下载失败: \(error.localizedDescription)")
    }
}
```

## 高级用法

### 设置全局配置

```swift
// 设置全局超时时间
CryoNet.setTimeout(30)

// 设置全局头部
CryoNet.setHeaders(["User-Agent": "CryoNet/1.0"])

// 设置全局参数
CryoNet.setParameters(["app_version": "1.0.0"])
```

### 取消请求

```swift
// 取消单个请求
let task = request.request(model)
task.cancel()

// 取消所有请求
CryoNet.cancelAllRequests()
```

### 处理复杂嵌套 JSON

```swift
struct Response: JSONParseable {
    let success: Bool
    let message: String
    let data: ResponseData?
    
    init?(json: JSON) {
        self.success = json.bool("success")
        self.message = json.string("message")
        self.data = ResponseData(json: json["data"])
    }
}

struct ResponseData: JSONParseable {
    let users: [User]
    let pagination: Pagination
    
    init?(json: JSON) {
        guard json.exists() else { return nil }
        
        self.users = json.toModelArray(User.self, keyPath: "users")
        self.pagination = Pagination(json: json["pagination"]) ?? Pagination.default
    }
}

// 使用
request.request(model)
    .responseJSONModel(type: Response.self) { response in
        if response.success {
            if let data = response.data {
                print("Total users: \(data.users.count)")
                print("Page: \(data.pagination.page)/\(data.pagination.total)")
            }
        } else {
            print("Error message: \(response.message)")
        }
    }
```

### 与 Codable 协议兼容

对于需要与现有 Codable 模型兼容的情况，可以同时实现两个协议：

```swift
struct User: JSONParseable, Codable {
    let id: Int
    let name: String
    
    // Codable 默认实现
    
    // JSONParseable 实现
    init?(json: JSON) {
        guard json["id"].exists() else { return nil }
        self.id = json.int("id")
        self.name = json.string("name")
    }
}
```

或者为 CryoResult 添加支持 Codable 的扩展方法：

```swift
extension CryoResult {
    @discardableResult
    public func responseCodableModel<T: Decodable>(
        type: T.Type,
        success: @escaping (T) -> Void,
        failed: @escaping (CryoError) -> Void = { _ in }
    ) -> CryoResult {
        responseData { data in
            do {
                let model = try JSONDecoder().decode(T.self, from: data)
                success(model)
            } catch {
                let decodingError = GenericCryoError(error)
                failed(decodingError)
            }
        } failed: { error in
            failed(error)
        }
        return self
    }
}
```

## 调试

CryoNet 在 DEBUG 模式下会自动打印详细的请求和响应日志，包括：

- 请求 URL
- 请求头
- 请求参数
- 响应状态
- 响应数据
- 错误信息

这些日志可以帮助您快速定位问题。

## 要求

- iOS 13.0+ / macOS 10.15+
- Swift 5.0+
- Xcode 12.0+

## 许可证

CryoNet 使用 MIT 许可证。详情请参阅 LICENSE 文件。

