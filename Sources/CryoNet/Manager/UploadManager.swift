import Foundation
import Alamofire
import CryoNet
import SwiftyJSON

// MARK: - 上传文件来源
/// 上传文件来源
///
/// 上传文件内容的来源，可以是本地文件URL或内存中的二进制数据。
public enum UploadFileSource {
    /// 本地文件路径
    case fileURL(URL)
    /// 内存二进制数据
    case fileData(Data)
}

// MARK: - 单个上传文件项
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

// MARK: - 上传任务状态
/// 上传任务状态
///
/// 上传任务的生命周期状态枚举，表示当前任务的运行阶段。
public enum UploadState: String {
    /// 等待上传或刚创建
    case idle
    /// 正在上传
    case uploading
    /// 已暂停
    case paused
    /// 上传成功完成
    case completed
    /// 上传失败
    case failed
    /// 已取消
    case cancelled
}

// MARK: - 批量上传整体状态
/// 批量上传状态
///
/// 批量上传的整体状态，适用于批量控制和展示。
public enum UploadBatchState: String {
    case idle
    case uploading
    case paused
    case completed
}

// MARK: - 上传任务信息（对外可见）
/// 上传任务只读信息
///
/// 公开的上传任务视图，供UI层或业务层获取进度、状态等。
///
/// - Parameters:
///   - id: 任务唯一ID
///   - files: 本任务包含的所有上传文件
///   - uploadURL: 上传目标接口
///   - parameters: 附加参数（表单键值对）
///   - progress: 上传进度（0~1）
///   - state: 当前任务状态
///   - response: AF请求对象（可选）
///   - cryoResult: cryo解析结果（可选）
///   -
///
/// ### 使用示例
/// ```swift
/// let infoList = uploadManager.allTaskInfos()
/// for info in infoList {
///     print("进度:", info.progress, "状态:", info.state)
/// }
/// ```
public struct UploadTaskInfo: Identifiable, Equatable {
    public static func == (lhs: UploadTaskInfo, rhs: UploadTaskInfo) -> Bool { lhs.id == rhs.id }
    public let id: UUID
    public let files: [UploadFileItem]
    public let uploadURL: URL
    public let parameters: [String: Any]?
    public var progress: Double
    public var state: UploadState
    public var response: DataRequest?
    public var cryoResult: CryoResult?
}

// MARK: - 上传事件委托协议
/// 上传事件回调协议
///
/// 通过实现该协议，UI层或业务层可以实时感知上传进度、状态、任务列表变化等。
/// 推荐只实现自己需要的方法。
///
/// ### 使用示例
/// ```swift
/// class MyUploadVM: ObservableObject, UploadManagerDelegate {
///     func uploadDidUpdate(task: UploadTaskInfo) { /* 处理单任务 */ }
///     func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo]) { /* 更新活跃任务 */ }
///     func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo]) { /* 更新已完成 */ }
///     func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) { /* 更新进度 */ }
/// }
/// ```
/// - SeeAlso: ``UploadTaskInfo``
public protocol UploadManagerDelegate: AnyObject {
    /// 上传任务变化时回调（包括进度、状态等）
    func uploadDidUpdate(task: UploadTaskInfo)
    /// 活跃任务（未完成/未取消）变化时回调
    func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo])
    /// 已完成任务变化时回调
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo])
    /// 整体进度和批量上传状态变化时回调
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState)
}
public extension UploadManagerDelegate {
    func uploadDidUpdate(task: UploadTaskInfo) {}
    func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo]) {}
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo]) {}
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) {}
}

// MARK: - 上传管理器
/// 支持多文件、参数、并发控制的批量上传管理器
///
/// 1. 支持本地文件和二进制内存数据上传；
/// 2. 支持全局和任务级别表单参数（全局参数可被任务参数覆盖）；
/// 3. 支持多文件合并为一个任务，文件和参数一同拼接到 multipart/form-data；
/// 4. 线程安全，基于 actor 实现；
/// 5. 所有进度、状态、任务变化都通过委托推送，UI层可直接监听使用。
///
/// ### 使用示例
/// ```swift
/// let manager = UploadManager(globalParameters: ["token": "..."])
/// let fileItem = UploadFileItem(fileURL: fileURL)
/// let id = manager.addTask(files: [fileItem], uploadURL: someURL, parameters: ["extra": "v1"])
/// manager.startTask(id: id)
/// ```
///
/// - Note: 推荐仅在主UI层单例持有UploadManager实例，避免多实例竞争同一文件。
/// - SeeAlso: ``UploadManagerDelegate``, ``UploadTaskInfo``
public actor UploadManager {
    /// 队列唯一标识
    public let identifier: String
    /// 最大并发数
    public var maxConcurrentUploads: Int
    /// 队列统一的附加参数（每个任务可覆盖/追加）
    private let globalParameters: [String: Any]?
    /// 全局HTTP请求头
    private let headers: HTTPHeaders?
    
    private var tasks: [UUID: UploadTask] = [:]
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private var currentUploadingCount: Int = 0
    private var pendingQueue: [UUID] = []
    private var lastBatchState: UploadBatchState = .idle
    private var overallCompletedCalled: Bool = false
    private let interceptor: DefaultInterceptor
    private let tokenManager: TokenManagerProtocol
    
    
    private var interceptorAdapter:RequestInterceptor{
        InterceptorAdapter(interceptor: interceptor,tokenManager: tokenManager)
    }
    
    // MARK: - 内部上传任务结构体
    /// 内部上传任务结构体
    private struct UploadTask {
        let id: UUID
        let files: [UploadFileItem]
        let uploadURL: URL
        let parameters: [String: Any]?
        var progress: Double
        var state: UploadState
        var response: DataRequest?
        var cryoResult: CryoResult?
    }
    
    // MARK: - 初始化
    /// 创建上传管理器
    ///
    /// - Parameters:
    ///   - identifier: 队列唯一ID，默认自动生成
    ///   - maxConcurrentUploads: 最大并发数，默认3
    ///   - headers: 全局请求头（如需统一token等）
    ///   - globalParameters: 所有上传任务默认携带的表单参数，可被任务单独参数覆盖
    ///   - interceptor: 业务拦截器(必须继承自DefaultInterceptor,重写响应结构)
    ///   - tokenManager: Token 管理
    ///
    ///
    /// ### 示例:
    /// ``` swift
    /// // 继承 DefaultInterceptor 实现拦截器,将 MyInterceptor 传入到 interceptor 参数
    /// class MyInterceptor: DefaultInterceptor, @unchecked Sendable {
    ///     init(){
    ///         let responseConfig = myResponseConfig()
    ///         super.init(responseConfig: responseConfig)  /// 为拦截器配置数据结构
    ///     }
    /// }
    /// final class myResponseConfig: DefaultResponseStructure, @unchecked Sendable {
    ///     // 配置数据结构
    ///     init(){
    ///         super.init(
    ///             codeKey: "error_code",
    ///             messageKey: "reason",
    ///             dataKey: "result",
    ///             successCode: 0
    ///         )
    ///     }
    ///
    ///     // 从 JSON 数据 响应指定数据或者完整数据
    ///     override func extractData(from json: JSON, originalData: Data) -> Result<Data, any Error> {
    ///         let targetData = json[dataKey]["data"]
    ///
    ///         // 如果不存在或者是 null，直接返回原始 data
    ///         if !targetData.exists() || targetData.type == .null {
    ///             return .success(originalData)
    ///         }
    ///
    ///         do {
    ///             let validData: Data = try targetData.rawData()
    ///             return .success(validData)
    ///         } catch {
    ///             return .failure(NSError(
    ///                 domain: "DataError",
    ///                 code: -1004,
    ///                 userInfo: [
    ///                     NSLocalizedDescriptionKey: "数据转换失败",
    ///                     NSUnderlyingErrorKey: error
    ///                 ]
    ///             ))
    ///         }
    ///     }
    ///     // 告诉拦截器,error_code 等于 0 时表示请求成功
    ///     override func isSuccess(json: JSON) -> Bool {
    ///         return json[codeKey].intValue == successCode
    ///     }
    /// }
    /// ```
    ///
    /// - Note:
    ///   - ``RequestInterceptorProtocol`` 与 ``TokenManagerProtocol`` 需要搭配一起使用.
    ///   - 当``RequestInterceptorProtocol``为请求注入token时,会默认从传入的``TokenManagerProtocol``进行读取
    public init(
        identifier: String = UUID().uuidString,
        baseURL: URL? = nil,
        maxConcurrentUploads: Int = 3,
        headers: HTTPHeaders? = nil,
        globalParameters: [String: Any]? = nil,
        interceptor:DefaultInterceptor,
        tokenManager: TokenManagerProtocol = DefaultTokenManager()
    ) {
        self.identifier = identifier
        self.maxConcurrentUploads = maxConcurrentUploads
        self.headers = headers
        self.globalParameters = globalParameters
        self.interceptor = interceptor
        self.tokenManager = tokenManager
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
    
    // MARK: - 任务注册与调度
    /// 注册一个上传任务
    ///
    /// - Parameters:
    ///   - files: 本任务要上传的所有文件
    ///   - uploadURL: 上传API接口URL
    ///   - parameters: 该任务的附加表单参数
    /// - Returns: 任务ID
    ///
    /// ### 使用示例
    /// ```swift
    /// let id = manager.addTask(files: [fileItem], uploadURL: url, parameters: ["bizId": "123"])
    /// ```
    public func addTask(
        files: [UploadFileItem],
        uploadURL: URL,
        parameters: [String: Any]? = nil
    ) -> UUID {
        let id = UUID()
        let task = UploadTask(
            id: id,
            files: files,
            uploadURL: uploadURL,
            parameters: parameters,
            progress: 0,
            state: .idle,
            response: nil,
            cryoResult: nil
        )
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        return id
    }
    
    /// 批量注册多个上传任务
    ///
    /// - Parameter fileGroups: 每个元素含[文件]、uploadURL、参数
    /// - Returns: 所有任务ID
    ///
    /// ### 使用示例
    /// ```swift
    /// let ids = manager.addTasks(fileGroups: [
    ///     (files: [item1], uploadURL: url1, parameters: nil),
    ///     (files: [item2], uploadURL: url2, parameters: ["bizId": "xxx"])
    /// ])
    /// ```
    public func addTasks(
        fileGroups: [(files: [UploadFileItem], uploadURL: URL, parameters: [String: Any]?)]
    ) -> [UUID] {
        var ids: [UUID] = []
        for group in fileGroups {
            let id = addTask(files: group.files, uploadURL: group.uploadURL, parameters: group.parameters)
            ids.append(id)
        }
        return ids
    }
    
    /// 注册并立即上传一个任务
    ///
    /// - Parameters:
    ///   - files: 上传文件
    ///   - uploadURL: 上传API
    ///   - parameters: 附加参数
    /// - Returns: 任务ID
    public func startUpload(
        files: [UploadFileItem],
        uploadURL: URL,
        parameters: [String: Any]? = nil
    ) async -> UUID {
        let id = addTask(files: files, uploadURL: uploadURL, parameters: parameters)
        enqueueOrStartTask(id: id)
        updateBatchStateIfNeeded()
        return id
    }
    
    /// 批量注册并立即上传多个任务
    ///
    /// - Parameter fileGroups: 每个元素含[文件]、uploadURL、参数
    /// - Returns: 所有任务ID
    public func batchUpload(
        fileGroups: [(files: [UploadFileItem], uploadURL: URL, parameters: [String: Any]?)]
    ) async -> [UUID] {
        var ids: [UUID] = []
        for group in fileGroups {
            let id = await startUpload(files: group.files, uploadURL: group.uploadURL, parameters: group.parameters)
            ids.append(id)
        }
        return ids
    }
    
    /// 启动所有任务
    public func startAllTasks() {
        self.batchStart(ids: allTaskIDs())
    }
    /// 暂停所有任务
    public func stopAllTasks() {
        self.batchPause(ids: allTaskIDs())
    }
    /// 批量启动
    public func batchStart(ids: [UUID]) {
        for id in ids {
            if let task = tasks[id], task.state == .idle || task.state == .paused {
                enqueueOrStartTask(id: id)
            }
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 批量恢复（等价启动）
    public func batchResume(ids: [UUID]) { batchStart(ids: ids) }
    /// 批量暂停
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 批量取消
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 设置最大并发数
    public func setMaxConcurrentUploads(_ count: Int) {
        self.maxConcurrentUploads = max(1, count)
        Task { self.checkAndStartNext() }
    }
    
    // MARK: - 单任务控制
    /// 启动单任务
    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    /// 暂停单任务
    public func pauseTask(id: UUID) {
        guard var task = tasks[id] else { return }
        guard task.state == .uploading else {
            if task.state != .paused {
                task.state = .paused
                tasks[id] = task
                notifyTaskListUpdate()
                notifyProgressAndBatchState()
            }
            return
        }
        task.response?.suspend()
        currentUploadingCount = max(0, currentUploadingCount - 1)
        task.state = .paused
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        Task { self.checkAndStartNext() }
    }
    /// 恢复单任务
    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else { return }
        if task.state == .paused || task.state == .idle || task.state == .failed {
            enqueueOrStartTask(id: id)
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
        }
    }
    /// 取消单任务
    public func cancelTask(id: UUID) {
        guard var task = tasks[id] else { return }
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
            task.state = .cancelled
            tasks[id] = task
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
            notifySingleTaskUpdate(task: task)
            return
        }
        if task.state == .uploading {
            task.response?.cancel()
            currentUploadingCount = max(0, currentUploadingCount - 1)
            Task { self.checkAndStartNext() }
        }
        task.state = .cancelled
        tasks[id] = task
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
        notifySingleTaskUpdate(task: task)
    }
    /// 移除任务
    public func removeTask(id: UUID) {
        if let task = tasks[id], task.state == .uploading || pendingQueue.contains(id) {
            cancelTask(id: id)
        }
        tasks[id] = nil
        if let idx = pendingQueue.firstIndex(of: id) {
            pendingQueue.remove(at: idx)
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    
    // MARK: - 私有: 任务调度与上传实现
    private func enqueueOrStartTask(id: UUID) {
        guard var task = tasks[id] else { return }
        guard task.state == .idle || task.state == .paused else { return }
        if currentUploadingCount < maxConcurrentUploads {
            startTaskInternal(id: id)
        } else {
            if !pendingQueue.contains(id) {
                pendingQueue.append(id)
            }
            task.state = .idle
            tasks[id] = task
        }
    }
    
    /// 内部上传启动，自动处理多文件、全局/单任务参数
    private func startTaskInternal(id: UUID) {
        guard var currentTask = tasks[id] else { return }
        guard currentTask.state == .idle || currentTask.state == .paused else { return }
        currentTask.state = .uploading
        tasks[id] = currentTask
        
        currentUploadingCount += 1
        
        // 合并全局参数与任务参数（任务参数优先）
        let mergedParameters = mergeParameters(global: globalParameters, local: currentTask.parameters)
        
        let request = AF.upload(
            multipartFormData: { [self] multipart in
                // 添加文件
                for item in currentTask.files {
                    switch item.file {
                    case .fileData(let data):
                        let fileName = item.fileName ?? UUID().uuidString
                        multipart.append(data, withName: item.name, fileName: fileName, mimeType: item.mimeType)
                    case .fileURL(let url):
                        let fileName = item.fileName ?? url.lastPathComponent
                        let mimeType = item.mimeType ?? mimeTypeForURL(url)
                        multipart.append(url, withName: item.name, fileName: fileName, mimeType: mimeType)
                    }
                }
                // 添加额外参数
                mergedParameters?.forEach { key, value in
                    if let data = Self.anyToData(value) {
                        multipart.append(data, withName: key)
                    }
                }
            },
            to: currentTask.uploadURL,
            headers: headers,
            interceptor: self.interceptorAdapter
        )
            .uploadProgress { [weak self] progress in
                Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
            }
            .response { [weak self] response in
                Task { await self?.onComplete(id: id, response: response) }
            }
        currentTask.cryoResult = CryoResult(
            request: request,
            interceptor: self.interceptor
        )
        currentTask.response = request
        tasks[id] = currentTask
    }
    
    /// 合并全局参数与任务单独参数（任务参数优先）
    private func mergeParameters(global: [String: Any]?, local: [String: Any]?) -> [String: Any]? {
        guard global != nil || local != nil else { return nil }
        var dict = global ?? [:]
        local?.forEach { dict[$0.key] = $0.value }
        return dict.isEmpty ? nil : dict
    }
    
    /// 转换常见类型为Data（支持String、Int、Double、Bool、Data）
    private static func anyToData(_ value: Any) -> Data? {
        switch value {
        case let str as String: return str.data(using: .utf8)
        case let int as Int: return "\(int)".data(using: .utf8)
        case let double as Double: return "\(double)".data(using: .utf8)
        case let bool as Bool: return (bool ? "true" : "false").data(using: .utf8)
        case let data as Data: return data
        default: return nil
        }
    }
    
    // MARK: - 上传事件处理
    private func onProgress(id: UUID, progress: Double) {
        guard var currentTask = tasks[id] else { return }
        currentTask.progress = progress
        if currentTask.state == .uploading {
            tasks[id] = currentTask
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            notifySingleTaskUpdate(task: currentTask)
        }
    }
    
    private func onComplete(id: UUID, response: AFDataResponse<Data?>) async {
        guard var currentTask = tasks[id] else { return }
        if let data = response.data {
            if let json = try? JSON(data: data) {
                if self.interceptor.isResponseSuccess(json: json){
                    currentTask.progress = 1.0
                    currentTask.state = .completed
                    tasks[id] = currentTask
                }
            } else {
                currentTask.state = .failed
                tasks[id] = currentTask
            }
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        notifySingleTaskUpdate(task: currentTask)
    }
    private func checkAndStartNext() {
        while currentUploadingCount < maxConcurrentUploads, !pendingQueue.isEmpty {
            let nextId = pendingQueue.removeFirst()
            if let task = tasks[nextId], task.state == .idle {
                startTaskInternal(id: nextId)
            }
        }
        notifyProgressAndBatchState()
    }
    
    // MARK: - 事件推送
    private func notifySingleTaskUpdate(task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            files: task.files,
            uploadURL: task.uploadURL,
            parameters: task.parameters,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadDidUpdate(task: info)
            }
        }
    }
    private func notifyTaskListUpdate() {
        let all = allTaskInfos()
        let active = all.filter { $0.state != .completed && $0.state != .cancelled }
        let completed = all.filter { $0.state == .completed }
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateActiveTasks(active)
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateCompletedTasks(completed)
            }
        }
    }
    private func notifyProgressAndBatchState() {
        let progress = calcOverallProgress()
        let batch = calcBatchState()
        for delegate in delegates.allObjects {
            Task { @MainActor in
                (delegate as? UploadManagerDelegate)?.uploadManagerDidUpdateProgress(overallProgress: progress, batchState: batch)
            }
        }
        if isOverallCompleted(), !overallCompletedCalled {
            overallCompletedCalled = true
        } else if !isOverallCompleted() && overallCompletedCalled {
            overallCompletedCalled = false
        }
    }
    private func updateBatchStateIfNeeded() {
        let newState = calcBatchState()
        if newState != lastBatchState {
            lastBatchState = newState
            notifyProgressAndBatchState()
        }
    }
    
    // MARK: - 查询接口
    /// 获取所有任务信息
    public func allTaskInfos() -> [UploadTaskInfo] {
        return tasks.values.map {
            UploadTaskInfo(
                id: $0.id,
                files: $0.files,
                uploadURL: $0.uploadURL,
                parameters: $0.parameters,
                progress: $0.progress,
                state: $0.state,
                response: $0.response,
                cryoResult: $0.cryoResult
            )
        }
    }
    /// 获取所有任务ID
    public func allTaskIDs() -> [UUID] {
        return Array(tasks.keys)
    }
    /// 获取指定任务信息
    public func getTaskInfo(id: UUID) -> UploadTaskInfo? {
        guard let task = tasks[id] else { return nil }
        return UploadTaskInfo(
            id: task.id,
            files: task.files,
            uploadURL: task.uploadURL,
            parameters: task.parameters,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
    }
    
    // MARK: - 进度与批量状态
    private func calcOverallProgress() -> Double {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        guard !validTasks.isEmpty else { return 1.0 }
        let sum = validTasks.map { min($0.progress, 1.0) }.reduce(0, +)
        return sum / Double(validTasks.count)
    }
    private func isOverallCompleted() -> Bool {
        let validTasks = tasks.values.filter { $0.state != .cancelled }
        return !validTasks.isEmpty && validTasks.allSatisfy { $0.state == .completed }
    }
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
    
    // MARK: - MIME类型推断
    /// 推断本地文件的MIME类型（常见类型，按类别分组，未匹配返回octet-stream）
    ///
    /// - Parameter url: 文件URL
    /// - Returns: 推断出的MIME类型
    ///
    /// ### 使用示例
    /// ```swift
    /// let mime = uploadManager.mimeTypeForURL(fileURL)
    /// ```
    ///
    /// - Note: 支持图片、音视频、文档、压缩包、常见代码、字体等主流类型。
    private func mimeTypeForURL(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        // MARK: 图片
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
        case "psd": return "image/vnd.adobe.photoshop"
        case "ai": return "application/postscript"
            // MARK: 音频
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "m4a": return "audio/mp4"
        case "amr": return "audio/amr"
        case "wma": return "audio/x-ms-wma"
        case "aiff", "aif": return "audio/aiff"
        case "opus": return "audio/opus"
            // MARK: 视频
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "wmv": return "video/x-ms-wmv"
        case "mkv": return "video/x-matroska"
        case "flv": return "video/x-flv"
        case "webm": return "video/webm"
        case "3gp": return "video/3gpp"
        case "3g2": return "video/3gpp2"
        case "f4v": return "video/x-f4v"
        case "m4v": return "video/x-m4v"
        case "mts": return "video/MP2T"
        case "ts": return "video/MP2T"
        case "m2ts": return "video/MP2T"
            // MARK: 文档
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
        case "yaml", "yml": return "application/x-yaml"
        case "html", "htm": return "text/html"
        case "xps": return "application/oxps"
        case "odt": return "application/vnd.oasis.opendocument.text"
        case "ods": return "application/vnd.oasis.opendocument.spreadsheet"
        case "odp": return "application/vnd.oasis.opendocument.presentation"
            // MARK: 压缩包
        case "zip": return "application/zip"
        case "rar": return "application/vnd.rar"
        case "7z": return "application/x-7z-compressed"
        case "tar": return "application/x-tar"
        case "gz": return "application/gzip"
        case "bz2": return "application/x-bzip2"
        case "xz": return "application/x-xz"
        case "lz": return "application/x-lzip"
        case "lzma": return "application/x-lzma"
        case "z": return "application/x-compress"
        case "cab": return "application/vnd.ms-cab-compressed"
        case "arj": return "application/x-arj"
            // MARK: 代码文件/脚本
        case "js": return "application/javascript"
        case "mjs": return "application/javascript"
        case "ts": return "application/typescript"
        case "css": return "text/css"
        case "swift": return "text/x-swift"
        case "java": return "text/x-java-source"
        case "c": return "text/x-c"
        case "cpp", "cxx": return "text/x-c++src"
        case "h": return "text/x-chdr"
        case "hpp": return "text/x-c++hdr"
        case "m": return "text/x-objective-c"
        case "py": return "text/x-python"
        case "rb": return "text/x-ruby"
        case "go": return "text/x-go"
        case "sh": return "application/x-sh"
        case "php": return "application/x-httpd-php"
        case "pl": return "text/x-perl"
        case "scala": return "text/x-scala"
        case "kt", "kts": return "text/x-kotlin"
        case "dart": return "text/x-dart"
        case "rs": return "text/x-rustsrc"
        case "vue": return "text/x-vue"
        case "sql": return "application/sql"
        case "bat": return "application/x-bat"
            // MARK: 电子书
        case "epub": return "application/epub+zip"
        case "mobi": return "application/x-mobipocket-ebook"
        case "azw", "azw3": return "application/vnd.amazon.ebook"
        case "fb2": return "application/x-fictionbook+xml"
            // MARK: 字体
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "eot": return "application/vnd.ms-fontobject"
            // MARK: 其它
        case "apk": return "application/vnd.android.package-archive"
        case "ipa": return "application/octet-stream"
        case "exe": return "application/vnd.microsoft.portable-executable"
        case "dmg": return "application/x-apple-diskimage"
        case "iso": return "application/x-iso9660-image"
        case "sketch": return "application/octet-stream"
        case "ps": return "application/postscript"
        case "ics": return "text/calendar"
        case "torrent": return "application/x-bittorrent"
        case "swf": return "application/x-shockwave-flash"
        case "crx": return "application/x-chrome-extension"
        case "vcf": return "text/vcard"
        case "eml": return "message/rfc822"
        case "msg": return "application/vnd.ms-outlook"
        default: return "application/octet-stream"
        }
    }
}
