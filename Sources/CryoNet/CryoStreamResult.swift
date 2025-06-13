import Foundation
import Alamofire
import SwiftyJSON

// MARK: - 流式请求结果对象
/// CryoStreamResult 提供多种流式数据消费方式，并支持自动格式判断与调试日志
@available(macOS 10.15, iOS 13, *)
public class CryoStreamResult {
    public let request: DataStreamRequest

    public init(request: DataStreamRequest) {
        self.request = request
    }

    /// 取消当前流式请求
    public func cancel() {
        request.cancel()
    }
}

// MARK: - 原始数据流
@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 获取原始 Data 类型的异步流
    /// - Returns: AsyncThrowingStream<Data, Error>
    func dataStream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            request.responseStream { stream in
                switch stream.event {
                case .stream(let result):
                    if case .success(let data) = result {
                        continuation.yield(data)
                    }
                case .complete(let completion):
                    if let error = completion.error {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }
}

// MARK: - JSON 对象流
@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 获取 SwiftyJSON 的 JSON 对象流
    /// - Returns: AsyncThrowingStream<JSON, Error>
    func jsonStream() -> AsyncThrowingStream<JSON, Error> {
        AsyncThrowingStream { continuation in
            request.responseStream { stream in
                switch stream.event {
                case .stream(let result):
                    if case .success(let data) = result {
                        let json = try JSON(data: data)
                        continuation.yield(json)
                    }
                case .complete(let completion):
                    if let error = completion.error {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }
}

// MARK: - JSONParseable 模型流
@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 获取 JSONParseable 协议模型流
    /// - Parameter type: 模型类型
    /// - Returns: AsyncThrowingStream<T, Error>
    func modelStream<T: JSONParseable>(_ type: T.Type) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            request.responseStream { stream in
                switch stream.event {
                case .stream(let result):
                    if case .success(let data) = result {
                        let json = try JSON(data: data)
                        if let model = json.toModel(T.self) {
                            continuation.yield(model)
                        } else {
                            let error = NSError(domain: "CryoStreamResult", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法将 JSON 转换为模型"])
                            continuation.yield(with: .failure(error))
                        }
                    }
                case .complete(let completion):
                    if let error = completion.error {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }
}

// MARK: - Decodable 模型流
@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 获取 Decodable 协议模型流
    /// - Parameters:
    ///   - type: Decodable 模型类型
    ///   - decoder: 解码器，默认 JSONDecoder
    /// - Returns: AsyncThrowingStream<T, Error>
    func decodableStream<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            request.responseStream { stream in
                switch stream.event {
                case .stream(let result):
                    if case .success(let data) = result {
                        do {
                            let model = try decoder.decode(T.self, from: data)
                            continuation.yield(model)
                        } catch {
                            if let str = String(data: data, encoding: .utf8) {
                                let decodingError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "解码失败: \(str)"))
                                continuation.yield(with: .failure(decodingError))
                            } else {
                                continuation.yield(with: .failure(error))
                            }
                        }
                    }
                case .complete(let completion):
                    if let error = completion.error {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }
}

// MARK: - 行分隔 Decodable 流
@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 获取按行分隔的 Decodable 模型流（如 OpenAI 等接口格式）
    /// - Parameters:
    ///   - type: Decodable 模型类型
    ///   - decoder: 解码器，默认 JSONDecoder
    /// - Returns: AsyncThrowingStream<T, Error>
    func lineDelimitedDecodableStream<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            var buffer = Data()
            request.responseStream { stream in
                switch stream.event {
                case .stream(let result):
                    if case .success(let data) = result {
                        buffer.append(data)
                        while let range = buffer.firstRange(of: [0x0A]) { // \n
                            let chunk = buffer.prefix(upTo: range.lowerBound)
                            buffer.removeSubrange(..<range.upperBound)
                            guard !chunk.isEmpty else { continue }
                            do {
                                let model = try decoder.decode(T.self, from: chunk)
                                continuation.yield(model)
                            } catch {
                                if let str = String(data: chunk, encoding: .utf8) {
                                    let decodingError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "解码失败: \(str)"))
                                    continuation.yield(with: .failure(decodingError))
                                } else {
                                    continuation.yield(with: .failure(error))
                                }
                            }
                        }
                    }
                case .complete(let completion):
                    // 处理剩余 buffer
                    if !buffer.isEmpty {
                        do {
                            let model = try decoder.decode(T.self, from: buffer)
                            continuation.yield(model)
                        } catch { /* 忽略最后解码错误 */ }
                    }
                    if let error = completion.error {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }
}

// MARK: - SSE 事件流
@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 获取 SSE（Server-Sent Events）事件字符串流
    /// - Returns: AsyncThrowingStream<String, Error>
    func sseStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            var buffer = ""
            request.responseStream { stream in
                switch stream.event {
                case .stream(let result):
                    if case .success(let data) = result,
                       let text = String(data: data, encoding: .utf8) {
                        buffer += text
                        while let range = buffer.range(of: "\n\n") {
                            let event = String(buffer[..<range.lowerBound])
                            buffer = String(buffer[range.upperBound...])
                            if let eventData = Self.extractSSEData(from: event) {
                                continuation.yield(eventData)
                            }
                        }
                    }
                case .complete(let completion):
                    // 处理剩余数据
                    if !buffer.isEmpty, let eventData = Self.extractSSEData(from: buffer) {
                        continuation.yield(eventData)
                    }
                    if let error = completion.error {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }

    /// 将 SSE 事件流转换为 JSONParseable 模型流
    /// - Parameter type: JSONParseable 类型
    /// - Returns: AsyncThrowingStream<T, Error>
    func sseModelStream<T: JSONParseable>(_ type: T.Type) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in sseStream() {
                        let json = JSON(parseJSON: event)
                        if let model = json.toModel(T.self) {
                            continuation.yield(model)
                        } else {
                            let error = NSError(domain: "CryoStreamResult", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法将 SSE 数据转换为模型"])
                            continuation.yield(with: .failure(error))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// 将 SSE 事件流转换为 Decodable 模型流
    /// - Parameters:
    ///   - type: Decodable 类型
    ///   - decoder: 解码器，默认 JSONDecoder
    /// - Returns: AsyncThrowingStream<T, Error>
    func sseDecodableStream<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in sseStream() {
                        guard let data = event.data(using: .utf8) else {
                            let err = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "SSE 事件无法转换为 UTF-8 数据"))
                            continuation.yield(with: .failure(err))
                            continue
                        }
                        do {
                            let model = try decoder.decode(T.self, from: data)
                            continuation.yield(model)
                        } catch {
                            continuation.yield(with: .failure(error))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// 私有：提取 SSE 事件中的 data 内容
    /// - Parameter event: SSE 事件字符串
    /// - Returns: data 行内容
    private static func extractSSEData(from event: String) -> String? {
        let lines = event.split(separator: "\n")
        for line in lines {
            if line.starts(with: "data: ") {
                return String(line.dropFirst(6))
            }
        }
        return nil
    }
}

// MARK: - 自动格式判定流
@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 根据 Content-Type 自动判定并返回合适的 Decodable 流
    /// - Parameters:
    ///   - type: Decodable 类型
    ///   - decoder: 解码器
    /// - Returns: AsyncThrowingStream<T, Error>
    func autoDecodableStream<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> AsyncThrowingStream<T, Error> {
        if let contentType = request.response?.headers.value(for: "Content-Type"),
           contentType.contains("text/event-stream") {
            return sseDecodableStream(type, decoder: decoder)
        }
        return lineDelimitedDecodableStream(type, decoder: decoder)
    }

    /// 根据 Content-Type 自动判定并返回合适的 JSONParseable 流
    /// - Parameter type: JSONParseable 类型
    /// - Returns: AsyncThrowingStream<T, Error>
    func autoModelStream<T: JSONParseable>(_ type: T.Type) -> AsyncThrowingStream<T, Error> {
        if let contentType = request.response?.headers.value(for: "Content-Type"),
           contentType.contains("text/event-stream") {
            return sseModelStream(type)
        }
        return modelStream(type)
    }
}

// MARK: - 通用流式数据项
/// 支持多种类型自动包装的流式数据项
public enum StreamDataItem {
    /// 原始二进制数据
    case data(Data)
    /// SwiftyJSON 对象
    case json(JSON)
    /// JSONParseable 模型
    case model(any JSONParseable)
    /// Decodable 模型
    case decodable(any Decodable)
    /// SSE 事件字符串
    case sseEvent(String)
    /// 错误
    case error(Error)

    /// 获取 Data 值
    public var dataValue: Data? {
        if case .data(let data) = self { return data }
        return nil
    }
    /// 获取 JSON 值
    public var jsonValue: JSON? {
        if case .json(let json) = self { return json }
        return nil
    }
    /// 获取模型值
    public var modelValue: (any JSONParseable)? {
        if case .model(let model) = self { return model }
        return nil
    }
    /// 获取 Decodable 值
    public var decodableValue: (any Decodable)? {
        if case .decodable(let model) = self { return model }
        return nil
    }
    /// 获取 SSE 字符串
    public var sseValue: String? {
        if case .sseEvent(let event) = self { return event }
        return nil
    }
    /// 获取错误
    public var errorValue: Error? {
        if case .error(let error) = self { return error }
        return nil
    }
}

@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 通用流式数据项流，自动按内容类型判断封装
    /// - Returns: AsyncThrowingStream<StreamDataItem, Error>
    func asStreamDataItems() -> AsyncThrowingStream<StreamDataItem, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // 优先处理 SSE
                    if let contentType = request.response?.headers.value(for: "Content-Type"),
                       contentType.contains("text/event-stream") {
                        for try await event in sseStream() {
                            continuation.yield(.sseEvent(event))
                        }
                        continuation.finish()
                        return
                    }
                    // 普通数据流
                    for try await data in dataStream() {
                        if let json = try? JSON(data: data) {
                            continuation.yield(.json(json))
                        } else if let string = String(data: data, encoding: .utf8) {
                            continuation.yield(.sseEvent(string))
                        } else {
                            continuation.yield(.data(data))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - 调试日志
@available(macOS 10.15, iOS 13, *)
public extension CryoStreamResult {
    /// 启用调试日志（仅 Debug 编译下打印 cURL 及数据块信息）
    /// - Returns: Self
    func enableDebugLogging() -> Self {
        #if DEBUG
        request
            .cURLDescription { description in
                print("🚀 流式请求 cURL:\n\(description)")
            }
            .responseStream { stream in
                switch stream.event {
                case .stream(let result):
                    switch result {
                    case .success(let data):
                        if let string = String(data: data, encoding: .utf8) {
                            print("📥 收到数据块: \(string)")
                        } else {
                            print("📥 收到二进制数据: \(data.count) 字节")
                        }
                    }
                case .complete(let completion):
                    if let error = completion.error {
                        print("❌ 流式请求完成错误: \(error)")
                    } else {
                        print("✅ 流式请求成功完成")
                    }
                }
            }
        #endif
        return self
    }
}



// MARK: - 控制管理
/// 一个用于管理和控制流式请求的控制器，便于外部随时启动、停止流任务
@available(macOS 10.15, iOS 13, *)
public final class CryoStreamController {
    public let streamResult: CryoStreamResult
    private var task: Task<Void, Never>? = nil
    private(set) public var isActive: Bool = false

    public init(streamResult: CryoStreamResult) {
        self.streamResult = streamResult
    }

    /// 启动原始 Data 流消费
    public func startDataStream(onData: @escaping (Data) -> Bool) {
        stop()
        isActive = true
        task = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await data in self.streamResult.dataStream() {
                    if !onData(data) { break }
                    if Task.isCancelled { break }
                }
            } catch {
                print("Error in dataStream: \(error)")
            }
            self.isActive = false
        }
    }

    /// 启动 JSON 流消费
    public func startJSONStream(onJSON: @escaping (JSON) -> Bool) {
        stop()
        isActive = true
        task = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await json in self.streamResult.jsonStream() {
                    if !onJSON(json) { break }
                    if Task.isCancelled { break }
                }
            } catch {
                print("Error in jsonStream: \(error)")
            }
            self.isActive = false
        }
    }

    /// 启动 Decodable 流消费
    public func startDecodableStream<T: Decodable>(_ type: T.Type, onModel: @escaping (T) -> Bool) {
        stop()
        isActive = true
        task = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await item in self.streamResult.decodableStream(type) {
                    if !onModel(item) { break }
                    if Task.isCancelled { break }
                }
            } catch {
                print("Error in decodableStream: \(error)")
            }
            self.isActive = false
        }
    }

    /// 启动 SSE 事件字符串流消费
    public func startSSEStream(onEvent: @escaping (String) -> Bool) {
        stop()
        isActive = true
        task = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await event in self.streamResult.sseStream() {
                    if !onEvent(event) { break }
                    if Task.isCancelled { break }
                }
            } catch {
                print("Error in sseStream: \(error)")
            }
            self.isActive = false
        }
    }

    /// 停止流式请求（可随时调用）
    public func stop() {
        guard isActive else { return }
        isActive = false
        streamResult.cancel()
        task?.cancel()
        task = nil
    }
}
