import Foundation
import Alamofire
import SwiftyJSON

// MARK: - 上传文件来源
/// 上传文件来源
///
/// 支持本地文件URL或内存中的二进制数据。
public enum UploadFileSource {
    /// 本地文件路径
    case fileURL(URL)
    /// 内存二进制数据
    case fileData(Data)
}

// MARK: - 上传文件项
/// 上传任务中的单个文件描述，支持本地文件和内存数据。
///
/// - Parameters:
///   - file: 文件来源（URL或Data）
///   - name: 此文件对应的表单字段名
///   - fileName: 文件名（对于Data类型必填，URL类型默认lastPathComponent）
///   - mimeType: MIME类型（可选，建议Data类型传）
///
/// ### 使用示例
/// ```swift
/// // 使用本地文件
/// let fileItem1 = UploadFileItem(fileURL: someURL, name: "image")
/// // 使用内存数据
/// let fileItem2 = UploadFileItem(data: imageData, name: "image", fileName: "photo.png", mimeType: "image/png")
/// ```
public struct UploadFileItem {
    public let file: UploadFileSource
    public let name: String
    public let fileName: String?
    public let mimeType: String?
    
    /// 以本地文件初始化
    public init(fileURL: URL, name: String = "file", fileName: String? = nil, mimeType: String? = nil) {
        self.file = .fileURL(fileURL)
        self.name = name
        self.fileName = fileName
        self.mimeType = mimeType
    }
    
    /// 以内存二进制数据初始化
    public init(data: Data, name: String = "file", fileName: String, mimeType: String? = nil) {
        self.file = .fileData(data)
        self.name = name
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

// MARK: - 上传状态
/// 上传任务状态枚举
public enum UploadState: String {
    case idle, uploading, paused, completed, failed, cancelled
}

// MARK: - 批量上传整体状态
/// 批量上传状态，用于整体进度与控制
public enum UploadBatchState: String {
    case idle, uploading, paused, completed
}

// MARK: - 上传任务泛型结构体
/// 泛型上传任务结构体
///
/// 用于描述一个上传任务的详细信息，支持与后端返回的泛型模型类型自动关联。
/// 该结构体实现了 `Identifiable` 和 `Equatable` 协议，便于在 SwiftUI 等数据驱动的框架中进行唯一标识和比较。
///
/// - Parameters:
///   - Model: 响应模型类型，需遵循 `JSONParseable` 协议
///
/// - Note:
///     - 支持任务唯一 ID、进度、状态、Alamofire 响应、泛型模型解析等
///
/// ### 使用示例
/// ```swift
/// let task = UploadTask<UploadModel>(id: UUID(), files: [item], progress: 0, state: .idle)
/// ```
public struct UploadTask<Model: JSONParseable>: Identifiable, Equatable {
    /// 任务的唯一标识符。
    public let id: UUID
    /// 上传的文件项列表，每个 `UploadFileItem` 表示一个待上传的文件。
    public let files: [UploadFileItem]
    /// 当前上传任务的进度，范围为 0.0~1.0。
    public var progress: Double
    /// 当前上传任务的状态。
    public var state: UploadState
    /// 关联的 Alamofire 数据请求对象
    /// 可以进一步进行处理请求
    public var response: DataRequest?
    /// 上传任务的 CryoResult 结果信息
    /// 可以基于 CryoResult 获取数据,也可以直接使用 `model`
    public var cryoResult: CryoResult?
    /// 上传后自动解析的响应数据模型，类型为泛型 `Model`
    /// 一般默认使用改数据即可,也可以通过`cryoResult``response`参数自定义处理数据
    public var model: Model?
    /// 判断两个上传任务是否为同一个任务（根据唯一 id）。
    public static func == (lhs: UploadTask<Model>, rhs: UploadTask<Model>) -> Bool { lhs.id == rhs.id }
}

// MARK: - 类型擦除协议（用于多态委托等场景）
/// 支持多态的上传任务协议
public protocol AnyUploadTask: Identifiable {
    var state: UploadState { get }
    var progress: Double { get }
}
extension UploadTask: AnyUploadTask {}

// MARK: - 上传事件委托协议
/// 上传事件回调协议
///
/// 通过实现该协议，UI层或业务层可以实时感知上传进度、状态、任务列表变化等。
/// 推荐只实现自己需要的方法。
///
/// - SeeAlso: ``UploadTask``
///
/// ### 使用示例
/// ```swift
/// class MyUploadVM: ObservableObject, UploadManagerDelegate {
///     func uploadDidUpdate(task: any AnyUploadTask) { /* 处理单任务 */ }
///     func uploadManagerDidUpdateActiveTasks(_ tasks: [any AnyUploadTask]) { /* 活跃队列 */ }
///     func uploadManagerDidUpdateCompletedTasks(_ tasks: [any AnyUploadTask]) { /* 已完成 */ }
///     func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) { /* 总体进度 */ }
/// }
/// ```
public protocol UploadManagerDelegate: AnyObject {
    func uploadDidUpdate(task: any AnyUploadTask)
    func uploadManagerDidUpdateActiveTasks(_ tasks: [any AnyUploadTask])
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [any AnyUploadTask])
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState)
}
public extension UploadManagerDelegate {
    func uploadDidUpdate(task: any AnyUploadTask) {}
    func uploadManagerDidUpdateActiveTasks(_ tasks: [any AnyUploadTask]) {}
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [any AnyUploadTask]) {}
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) {}
}

// MARK: - 上传管理器（支持泛型模型，批量/单个任务管理）
/// 批量/单任务上传管理器（支持泛型模型响应）
///
/// 1. 支持本地文件和二进制内存数据上传；
/// 2. 支持全局和任务级别表单参数（全局参数可被任务参数覆盖）；
/// 3. 支持多文件合并为一个任务，文件和参数一同拼接到 multipart/form-data；
/// 4. 支持任务进度、队列/并发控制、暂停/恢复/取消/删除等操作；
/// 5. 支持委托推送任务进度、状态、队列变更、批量进度等；
/// 6. 泛型响应类型，自动解析响应为你的自定义模型；
///
/// - Note:
///   - 需要准确判断上传结果(成功或失败),必须传入自定义拦截器，且该拦截器继承自`DefaultInterceptor`，并配置好响应数据结构（见下方示例）。
///   - 泛型`Model`必须实现`JSONParseable`协议，见下方示例。
/// - SeeAlso: ``UploadFileItem``, ``UploadTask``, ``UploadManagerDelegate``
///
/// ### 配置拦截器和响应结构示例
/// ```swift
/// // 自定义拦截器，必须继承 DefaultInterceptor
/// class UploadInterceptor: DefaultInterceptor, @unchecked Sendable {
///     init(){
///         let responseConfig = UploadResponseConfig()
///         super.init(responseConfig: responseConfig)  // 配置响应结构
///     }
/// }
///
/// // 配置响应结构（支持深层数据）
/// final class UploadResponseConfig: DefaultResponseStructure, @unchecked Sendable {
///     init(){
///         super.init(
///             codeKey: "status",
///             messageKey: "success",
///             dataKey: "data",
///             successCode: 200
///         )
///     }
///     override func extractData(from json: JSON, originalData: Data) -> Result<Data, any Error> {
///         let targetData = json[dataKey]
///         if !targetData.exists() || targetData.type == .null { return .success(originalData) }
///         do {
///             let validData: Data = try targetData.rawData()
///             return .success(validData)
///         } catch {
///             return .failure(error)
///         }
///     }
///     override func isSuccess(json: JSON) -> Bool {
///         return json[codeKey].intValue == successCode
///     }
/// }
/// ```
///
/// ### 泛型响应模型示例
/// ```swift
/// class UploadModel: JSONParseable {
///     var url_viewer: String = ""
///     var display_url: String = ""
///     let id = UUID()
///     required init?(json: JSON) {
///         url_viewer = json.string("url_viewer", defaultValue: "")
///         display_url = json.string("display_url", defaultValue: "")
///     }
/// }
/// ```
///
/// ### 使用示例
/// ```swift
/// let uploadManager = UploadManager<UploadModel>(
///     uploadURL: URL(string: "https://api.imgbb.com/1/upload")!,
///     parameters: ["key": "xxx"],
///     maxConcurrentUploads: 3,
///     interceptor: UploadInterceptor()
/// )
///
/// let fileItem = UploadFileItem(data: imageData, name: "image", fileName: "photo.jpg", mimeType: "image/jpeg")
/// let taskID = await uploadManager.addTask(files: [fileItem])
/// await uploadManager.startTask(id: taskID)
/// ```
///
public actor UploadManager<Model: JSONParseable> {
    // MARK: - 基本属性
    /// 队列唯一标识
    public let identifier: String
    /// 全局上传API接口URL
    public let uploadURL: URL
    /// 全局表单参数
    public let parameters: [String: Any]?
    /// 全局HTTP请求头
    public let headers: HTTPHeaders?
    /// 最大并发上传数
    public var maxConcurrentUploads: Int

    // 任务存储
    internal var tasks: [UUID: UploadTask<Model>] = [:]
    internal var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    internal var currentUploadingCount = 0
    internal var pendingQueue: [UUID] = []
    internal var lastBatchState: UploadBatchState = .idle
    
    /// 业务拦截器（必须继承 DefaultInterceptor，见类注释示例）
    internal var interceptor: DefaultInterceptor
    /// Token 管理
    internal var tokenManager: TokenManagerProtocol
    /// 内部请求拦截器适配
    internal var interceptorAdapter: RequestInterceptor {
        InterceptorAdapter(interceptor: interceptor, tokenManager: tokenManager)
    }

    // MARK: - 初始化
    /// 创建上传管理器
    ///
    /// - Parameters:
    ///   - identifier: 队列唯一ID，默认自动生成
    ///   - uploadURL: 全局上传API接口URL
    ///   - parameters: 全局表单参数
    ///   - headers: 全局请求头
    ///   - maxConcurrentUploads: 最大并发数
    ///   - interceptor: 必须继承自DefaultInterceptor的业务拦截器，配置响应结构
    ///   - tokenManager: Token管理器，默认为DefaultTokenManager
    ///
    /// - Note: 必须正确配置 interceptor 和 Model 泛型，详见类注释示例。
    public init(
        identifier: String = UUID().uuidString,
        uploadURL: URL,
        parameters: [String: Any]? = nil,
        headers: HTTPHeaders? = nil,
        maxConcurrentUploads: Int = 3,
        interceptor: DefaultInterceptor,
        tokenManager: TokenManagerProtocol = DefaultTokenManager()
    ) {
        self.identifier = identifier
        self.uploadURL = uploadURL
        self.parameters = parameters
        self.headers = headers
        self.maxConcurrentUploads = maxConcurrentUploads
        self.interceptor = interceptor
        self.tokenManager = tokenManager
    }

    // MARK: - 任务注册与启动
    /// 添加上传任务（只需文件，API和参数全局统一）
    ///
    /// - Parameter files: 上传文件项数组
    /// - Returns: 新建任务ID
    ///
    /// ### 使用示例
    /// ```swift
    /// let taskID = await uploadManager.addTask(files: [fileItem])
    /// ```
    public func addTask(files: [UploadFileItem]) -> UUID {
        let id = UUID()
        let task = UploadTask<Model>(
            id: id,
            files: files,
            progress: 0,
            state: .idle,
            response: nil,
            model: nil
        )
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        return id
    }

    /// 启动单任务
    ///
    /// - Parameter id: 任务ID
    ///
    /// ### 使用示例
    /// ```swift
    /// await uploadManager.startTask(id: taskID)
    /// ```
    public func startTask(id: UUID) {
        guard var task = tasks[id], task.state == .idle || task.state == .paused || task.state == .cancelled else { return }
        if currentUploadingCount < maxConcurrentUploads {
            task.state = .uploading
            tasks[id] = task
            currentUploadingCount += 1
            let request = AF.upload(
                multipartFormData: { multipart in
                    for item in task.files {
                        switch item.file {
                        case .fileData(let data):
                            let fileName = item.fileName ?? UUID().uuidString
                            let mimeType = item.mimeType ?? "application/octet-stream"
                            multipart.append(data, withName: item.name, fileName: fileName, mimeType: mimeType)
                        case .fileURL(let url):
                            let fileName = item.fileName ?? url.lastPathComponent
                            let mimeType = item.mimeType ?? self.mimeTypeForURL(url)
                            multipart.append(url, withName: item.name, fileName: fileName, mimeType: mimeType)
                        }
                    }
                    self.parameters?.forEach { key, value in
                        if let str = value as? String {
                            multipart.append(str.data(using: .utf8)!, withName: key)
                        }
                        if let int = value as? Int {
                            multipart.append("\(int)".data(using: .utf8)!, withName: key)
                        }
                        // 其它类型可扩展
                    }
                },
                to: uploadURL,
                headers: headers,
                interceptor: self.interceptorAdapter
            )
            .uploadProgress { [weak self] progress in
                Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
            }
            .response { [weak self] response in
                Task { await self?.onComplete(id: id, response: response) }
            }
            task.cryoResult = CryoResult(
                request: request,
                interceptor: self.interceptor
            )
            task.response = request
            tasks[id] = task
        } else {
            if !pendingQueue.contains(id) {
                pendingQueue.append(id)
            }
            task.state = .idle
            tasks[id] = task
        }
    }

    // MARK: - 单任务控制（暂停、恢复、取消、删除）
    /// 暂停单任务
    ///
    /// - Parameter id: 任务ID
    public func pauseTask(id: UUID) {
        if var task = tasks[id], task.state == .uploading {
            task.response?.suspend()
            task.state = .paused
            tasks[id] = task
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            notifySingleTaskUpdate(task: task)
        }
    }

    /// 恢复单任务（可从暂停或取消恢复）
    ///
    /// - Parameter id: 任务ID
    public func resumeTask(id: UUID) {
        if var task = tasks[id], task.state == .paused {
            task.response?.resume()
            task.state = .uploading
            tasks[id] = task
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            notifySingleTaskUpdate(task: task)
        } else if let task = tasks[id], task.state == .cancelled {
            // 重新提交（即重新上传）
            startTask(id: id)
        }
    }

    /// 取消单任务（仅标记为已取消，可恢复）
    ///
    /// - Parameter id: 任务ID
    public func cancelTask(id: UUID) {
        if var task = tasks[id], [.uploading, .paused, .idle].contains(task.state) {
            task.response?.cancel()
            task.state = .cancelled
            tasks[id] = task
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            notifySingleTaskUpdate(task: task)
        }
    }

    /// 删除单任务（彻底移除，无法恢复）
    ///
    /// - Parameter id: 任务ID
    public func deleteTask(id: UUID) {
        if let task = tasks[id], [.uploading, .paused, .idle].contains(task.state) {
            task.response?.cancel()
        }
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
    }

    // MARK: - 批量任务控制
    /// 批量暂停任务
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
    }

    /// 批量恢复任务
    public func batchResume(ids: [UUID]) {
        for id in ids { resumeTask(id: id) }
    }

    /// 批量取消任务
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
    }

    /// 批量删除任务
    public func batchDelete(ids: [UUID]) {
        for id in ids { deleteTask(id: id) }
    }

    // MARK: - 上传进度与完成回调
    /// 上传进度回调
    private func onProgress(id: UUID, progress: Double) async {
        guard var task = tasks[id] else { return }
        task.progress = progress
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        notifySingleTaskUpdate(task: task)
    }

    /// 上传单任务完成回调（自动解析为泛型模型）
    private func onComplete(id: UUID, response: AFDataResponse<Data?>) async {
        guard var task = tasks[id] else { return }
        currentUploadingCount = max(0, currentUploadingCount - 1)

        // 默认标记为失败
        var completed = false

        if let data = response.data, let json = try? JSON(data: data) {
            if self.interceptor.isResponseSuccess(json: json) {
                task.progress = 1.0
                task.state = .completed
                completed = true

                // 异步解析模型并保存回 tasks 字典
                if let cryoResult = task.cryoResult {
                    cryoResult.interceptJSONModel(type: Model.self) { value in
                        // 保证写回全局 tasks
                        var updatedTask = task
                        updatedTask.model = value
                        self.tasks[id] = updatedTask
                        self.notifyTaskListUpdate()
                        self.notifySingleTaskUpdate(task: updatedTask)
                    }
                }
            }
        }

        // 如果不是正常完成，标记为失败
        if !completed {
            task.state = .failed
        }

        // 最终写回任务并通知
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        notifySingleTaskUpdate(task: task)
        await checkAndStartNext()
    }

    // MARK: - 调度与并发控制
    /// 检查并启动下一个等待任务
    private func checkAndStartNext() async {
        while currentUploadingCount < maxConcurrentUploads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            if let task = tasks[nextId], task.state == .idle {
                startTask(id: nextId)
            }
        }
        notifyProgressAndBatchState()
    }

    // MARK: - 委托注册与移除
    /// 注册上传事件监听者
    public func addDelegate(_ delegate: UploadManagerDelegate) {
        delegates.add(delegate)
    }
    /// 注销上传事件监听者
    public func removeDelegate(_ delegate: UploadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 事件推送
    /// 通知单个任务变化
    private func notifySingleTaskUpdate(task: UploadTask<Model>) {
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadDidUpdate(task: task)
            }
        }
    }
    /// 通知任务列表变化
    private func notifyTaskListUpdate() {
        let all = Array(tasks.values)
        let active = all.filter { $0.state != .completed && $0.state != .cancelled }
        let completed = all.filter { $0.state == .completed }
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateActiveTasks(active)
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateCompletedTasks(completed)
            }
        }
    }
    /// 通知总体进度和批量状态
    private func notifyProgressAndBatchState() {
        let progress = calcOverallProgress()
        let batch = calcBatchState()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateProgress(overallProgress: progress, batchState: batch)
            }
        }
    }

    // MARK: - 进度与批量状态计算
    /// 计算所有任务总进度
    private func calcOverallProgress() -> Double {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        guard !validTasks.isEmpty else { return 1.0 }
        let sum = validTasks.map { min($0.progress, 1.0) }.reduce(0, +)
        return sum / Double(validTasks.count)
    }
    /// 计算批量上传状态
    private func calcBatchState() -> UploadBatchState {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        if validTasks.isEmpty { return .idle }
        let completedCount = validTasks.filter { $0.state == .completed }.count
        let pausedCount = validTasks.filter { $0.state == .paused }.count
        let uploadingCount = validTasks.filter { $0.state == .uploading }.count
        let idleCount = validTasks.filter { $0.state == .idle }.count
        if completedCount == validTasks.count { return .completed }
        if pausedCount == validTasks.count { return .paused }
        if uploadingCount > 0 { return .uploading }
        if idleCount > 0 && uploadingCount == 0 && pausedCount == 0 { return .idle }
        if pausedCount > 0 && uploadingCount == 0 { return .paused }
        return .idle
    }

    // MARK: - 查询接口
    /// 获取所有任务
    public func allTasks() -> [UploadTask<Model>] { Array(tasks.values) }
    /// 获取指定任务
    public func getTask(id: UUID) -> UploadTask<Model>? { tasks[id] }
    /// 获取所有任务ID
    public func allTaskIDs() -> [UUID] { Array(tasks.keys) }

    // MARK: - MIME类型推断（支持常见扩展名，未命中返回octet-stream）
    /// 推断本地文件的MIME类型（常见类型，未匹配返回octet-stream）
    ///
    /// - Parameter url: 文件URL
    /// - Returns: 推断出的MIME类型
    ///
    /// ### 使用示例
    /// ```swift
    /// let mime = uploadManager.mimeTypeForURL(fileURL)
    /// ```
    private func mimeTypeForURL(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        // MARK: - 图片类
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "ico": return "image/x-icon"
        case "svg": return "image/svg+xml"

        // MARK: - 音频类
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "m4a": return "audio/mp4"
        case "ogg", "oga": return "audio/ogg"
        case "opus": return "audio/opus"
        case "amr": return "audio/amr"
        case "aiff", "aif": return "audio/aiff"

        // MARK: - 视频类
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "wmv": return "video/x-ms-wmv"
        case "flv": return "video/x-flv"
        case "3gp": return "video/3gpp"
        case "3g2": return "video/3gpp2"
        case "mpeg", "mpg": return "video/mpeg"
        case "m4v": return "video/x-m4v"

        // MARK: - 文档类
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt": return "text/plain"
        case "rtf": return "application/rtf"
        case "csv": return "text/csv"
        case "md": return "text/markdown"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "html", "htm": return "text/html"
        case "yml", "yaml": return "text/yaml"
        case "log": return "text/plain"

        // MARK: - 压缩包类
        case "zip": return "application/zip"
        case "rar": return "application/vnd.rar"
        case "7z": return "application/x-7z-compressed"
        case "tar": return "application/x-tar"
        case "gz": return "application/gzip"
        case "bz2": return "application/x-bzip2"
        case "xz": return "application/x-xz"
        case "lz": return "application/x-lzip"
        case "lzma": return "application/x-lzma"

        // MARK: - 编程/代码类
        case "js": return "application/javascript"
        case "ts": return "application/typescript"
        case "jsonc": return "application/json"
        case "css": return "text/css"
        case "scss", "sass": return "text/x-scss"
        case "swift": return "text/x-swift"
        case "java": return "text/x-java-source"
        case "py": return "text/x-python"
        case "c", "h": return "text/x-c"
        case "cpp", "cc", "cxx": return "text/x-c++"
        case "hpp": return "text/x-c++hdr"
        case "m": return "text/x-objective-c"
        case "mm": return "text/x-objective-c++"
        case "go": return "text/x-go"
        case "rs": return "text/x-rustsrc"
        case "php": return "application/x-httpd-php"
        case "sh": return "application/x-sh"
        case "bat": return "application/x-msdos-program"
        case "pl": return "text/x-perl"
        case "rb": return "application/x-ruby"

        // MARK: - 字体类
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "eot": return "application/vnd.ms-fontobject"

        // MARK: - 应用程序安装包
        case "apk": return "application/vnd.android.package-archive"
        case "ipa": return "application/octet-stream"
        case "exe": return "application/vnd.microsoft.portable-executable"
        case "msi": return "application/x-msdownload"
        case "dmg": return "application/x-apple-diskimage"
        case "pkg": return "application/octet-stream"

        // MARK: - 虚拟镜像类
        case "iso": return "application/x-iso9660-image"
        case "img": return "application/octet-stream"
        case "vhd": return "application/octet-stream"
        case "vmdk": return "application/octet-stream"

        // MARK: - 默认类型
        default:
            return "application/octet-stream"
        }
    }
}
