import Foundation
import Alamofire

// MARK: - 上传任务状态
public enum UploadState: String {
    case idle
    case uploading
    case paused
    case completed
    case failed
    case cancelled
}

// MARK: - 批量/全部上传的整体状态
public enum UploadBatchState: String {
    case idle
    case uploading
    case paused
    case completed
}

// MARK: - 上传文件来源（支持本地URL或二进制数据）
public enum UploadFileSource {
    case fileURL(URL)
    case fileData(Data)
}

// MARK: - 单个上传文件项
/// 上传文件项，支持URL或Data
public struct UploadFileItem {
    /// 文件来源（本地URL或二进制Data）
    public let source: UploadFileSource
    /// 表单字段名
    public let formFieldName: String
    /// 文件名（Data类型必填，URL类型默认用lastPathComponent）
    public let fileName: String?
    /// MIME类型（可选，推荐Data类型指定）
    public let mimeType: String?

    /// 以本地文件URL初始化
    public init(fileURL: URL, formFieldName: String = "file", fileName: String? = nil, mimeType: String? = nil) {
        self.source = .fileURL(fileURL)
        self.formFieldName = formFieldName
        self.fileName = fileName
        self.mimeType = mimeType
    }
    /// 以二进制Data初始化
    public init(data: Data, formFieldName: String = "file", fileName: String, mimeType: String? = nil) {
        self.source = .fileData(data)
        self.formFieldName = formFieldName
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

// MARK: - 上传任务信息（多文件支持）
public struct UploadTaskInfo: Identifiable, Equatable {
    public static func == (lhs: UploadTaskInfo, rhs: UploadTaskInfo) -> Bool {
        lhs.id == rhs.id
    }
    public let id: UUID
    public let files: [UploadFileItem]
    public let uploadURL: URL
    public var progress: Double
    public var state: UploadState
    public var response: DataRequest?
    public var cryoResult: CryoResult?
}

// MARK: - 上传管理器事件委托
public protocol UploadManagerDelegate: AnyObject {
    func uploadDidUpdate(task: UploadTaskInfo)
    func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo])
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo])
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState)
}
public extension UploadManagerDelegate {
    func uploadDidUpdate(task: UploadTaskInfo) {}
    func uploadManagerDidUpdateActiveTasks(_ tasks: [UploadTaskInfo]) {}
    func uploadManagerDidUpdateCompletedTasks(_ tasks: [UploadTaskInfo]) {}
    func uploadManagerDidUpdateProgress(overallProgress: Double, batchState: UploadBatchState) {}
}

// MARK: - 内部上传任务结构体
private struct UploadTask {
    let id: UUID
    let files: [UploadFileItem]
    let uploadURL: URL
    var progress: Double
    var state: UploadState
    var response: DataRequest?
    var cryoResult: CryoResult?
}

// MARK: - 上传管理器（带baseURL拼接支持）
public actor UploadManager {
    /// 公共API基础URL；如果传入路径为相对路径，则自动拼接baseURL
    public let baseURL: URL?
    public let identifier: String
    private var tasks: [UUID: UploadTask] = [:]
    private var delegates: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    private var maxConcurrentUploads: Int
    private var currentUploadingCount: Int = 0
    private var pendingQueue: [UUID] = []
    private var lastBatchState: UploadBatchState = .idle
    private var overallCompletedCalled: Bool = false
    private let headers: HTTPHeaders?
    private let interceptor: RequestInterceptor?

    // MARK: - 初始化
    /// 创建上传管理器
    /// - Parameters:
    ///   - baseURL: 基础URL；上传任务路径为相对路径时自动拼接
    ///   - identifier: 队列唯一ID，默认自动生成
    ///   - maxConcurrentUploads: 最大并发数，默认3
    ///   - headers: 全局请求头
    ///   - interceptor: 自定义请求拦截器
    public init(
        baseURL: URL? = nil,
        identifier: String = UUID().uuidString,
        maxConcurrentUploads: Int = 3,
        headers: HTTPHeaders? = nil,
        interceptor: RequestInterceptor? = nil
    ) {
        self.baseURL = baseURL
        self.identifier = identifier
        self.maxConcurrentUploads = maxConcurrentUploads
        self.headers = headers
        self.interceptor = interceptor
    }

    // MARK: - 事件委托注册
    public func addDelegate(_ delegate: UploadManagerDelegate) {
        delegates.add(delegate)
    }
    public func removeDelegate(_ delegate: UploadManagerDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - 任务注册与调度

    /// 注册单个上传任务（支持多文件，初始idle，不自动上传）
    /// - Parameters:
    ///   - files: 上传文件数组
    ///   - uploadPathOrUrl: 上传接口路径，可以是相对路径或完整URL字符串
    /// - Returns: 任务ID
    public func addTask(
        files: [UploadFileItem],
        uploadPathOrUrl: String
    ) -> UUID {
        guard let uploadURL = fullUploadURL(for: uploadPathOrUrl) else {
            fatalError("上传路径无效：\(uploadPathOrUrl)")
        }
        let id = UUID()
        let task = UploadTask(
            id: id,
            files: files,
            uploadURL: uploadURL,
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

    /// 批量注册任务
    public func addTasks(
        fileGroups: [(files: [UploadFileItem], uploadPathOrUrl: String)]
    ) -> [UUID] {
        var ids: [UUID] = []
        for group in fileGroups {
            let id = addTask(files: group.files, uploadPathOrUrl: group.uploadPathOrUrl)
            ids.append(id)
        }
        return ids
    }

    /// 注册并立即上传单任务
    public func startUpload(
        files: [UploadFileItem],
        uploadPathOrUrl: String
    ) async -> UUID {
        let id = addTask(files: files, uploadPathOrUrl: uploadPathOrUrl)
        enqueueOrStartTask(id: id)
        updateBatchStateIfNeeded()
        return id
    }

    /// 批量上传
    public func batchUpload(
        fileGroups: [(files: [UploadFileItem], uploadPathOrUrl: String)]
    ) async -> [UUID] {
        var ids: [UUID] = []
        for group in fileGroups {
            let id = await startUpload(files: group.files, uploadPathOrUrl: group.uploadPathOrUrl)
            ids.append(id)
        }
        return ids
    }

    public func startAllTasks() {
        self.batchStart(ids: allTaskIDs())
    }
    public func stopAllTasks() {
        self.batchPause(ids: allTaskIDs())
    }
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
    public func batchResume(ids: [UUID]) {
        batchStart(ids: ids)
    }
    public func batchPause(ids: [UUID]) {
        for id in ids { pauseTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    public func batchCancel(ids: [UUID]) {
        for id in ids { cancelTask(id: id) }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
    public func setMaxConcurrentUploads(_ count: Int) {
        self.maxConcurrentUploads = max(1, count)
        Task { self.checkAndStartNext() }
    }

    // MARK: - 单任务控制
    public func startTask(id: UUID) {
        enqueueOrStartTask(id: id)
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        updateBatchStateIfNeeded()
    }
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
    public func resumeTask(id: UUID) {
        guard let task = tasks[id] else {return}
        if task.state == .paused || task.state == .idle || task.state == .failed {
            enqueueOrStartTask(id: id)
            notifyTaskListUpdate()
            notifyProgressAndBatchState()
            updateBatchStateIfNeeded()
        }
    }
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

    // MARK: - 路径拼接
    /// 根据传入路径字符串，自动拼接baseURL或直接用绝对URL
    private func fullUploadURL(for pathOrURL: String) -> URL? {
        // 若为完整URL则直接用，否则拼接baseURL
        if let url = URL(string: pathOrURL), url.scheme != nil {
            return url
        } else if let baseURL = baseURL {
            // 支持 "/xxx" 或 "xxx" 形式
            if pathOrURL.hasPrefix("/") {
                // /xxx 直接 path 拼接
                return baseURL.appendingPathComponent(String(pathOrURL.dropFirst()))
            } else {
                // 直接拼接
                return baseURL.appendingPathComponent(pathOrURL)
            }
        } else {
            return nil
        }
    }

    // MARK: - 私有：任务调度与上传
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

    /// 内部上传启动，支持本地文件URL和二进制Data
    private func startTaskInternal(id: UUID) {
        guard var currentTask = tasks[id] else { return }
        guard currentTask.state == .idle || currentTask.state == .paused else { return }
        currentTask.state = .uploading
        tasks[id] = currentTask

        currentUploadingCount += 1

        let request = AF.upload(
            multipartFormData: { [self] multipart in
                for item in currentTask.files {
                    switch item.source {
                    case .fileURL(let url):
                        let fileName = item.fileName ?? url.lastPathComponent
                        let mimeType = item.mimeType ?? mimeTypeForURL(url)
                        multipart.append(url, withName: item.formFieldName, fileName: fileName, mimeType: mimeType)
                    case .fileData(let data):
                        // fileName和mimeType必须指定
                        let fileName = item.fileName ?? UUID().uuidString
                        let mimeType = item.mimeType ?? "application/octet-stream"
                        multipart.append(data, withName: item.formFieldName, fileName: fileName, mimeType: mimeType)
                    }
                }
            },
            to: currentTask.uploadURL,
            headers: headers,
            interceptor: interceptor
        )
        .uploadProgress { [weak self] progress in
            Task { await self?.onProgress(id: id, progress: progress.fractionCompleted) }
        }
        .response { [weak self] response in
            Task { await self?.onComplete(id: id, response: response) }
        }
        currentTask.cryoResult = nil
        currentTask.response = request
        tasks[id] = currentTask
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
        currentUploadingCount = max(0, currentUploadingCount - 1)
        defer { Task { self.checkAndStartNext() } }

        if response.error != nil {
            currentTask.state = .failed
            tasks[id] = currentTask
        } else {
            currentTask.progress = 1.0
            currentTask.state = .completed
            tasks[id] = currentTask
        }
        notifyTaskListUpdate()
        notifyProgressAndBatchState()
        notifySingleTaskUpdate(task: currentTask)
    }

    // MARK: - 事件派发
    private func notifySingleTaskUpdate(task: UploadTask) {
        let info = UploadTaskInfo(
            id: task.id,
            files: task.files,
            uploadURL: task.uploadURL,
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

    // MARK: - 状态/查询接口
    public func allTaskInfos() -> [UploadTaskInfo] {
        return tasks.values.map {
            UploadTaskInfo(
                id: $0.id,
                files: $0.files,
                uploadURL: $0.uploadURL,
                progress: $0.progress,
                state: $0.state,
                response: $0.response,
                cryoResult: $0.cryoResult
            )
        }
    }
    public func allTaskIDs() -> [UUID] {
        return Array(tasks.keys)
    }
    public func getTaskInfo(id: UUID) -> UploadTaskInfo? {
        guard let task = tasks[id] else { return nil }
        return UploadTaskInfo(
            id: task.id,
            files: task.files,
            uploadURL: task.uploadURL,
            progress: task.progress,
            state: task.state,
            response: task.response,
            cryoResult: task.cryoResult
        )
    }

    // MARK: - 进度/批量状态计算
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
    /// 推断本地文件的MIME类型（按类别分组，支持常见格式）
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
        case "otf": return "font/otf"
        case "ics": return "text/calendar"
        default: return "application/octet-stream"
        }
    }
}
