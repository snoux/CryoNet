import Foundation
@preconcurrency import SwiftyJSON

// MARK: - SwiftyJSON 工具扩展

/// SwiftyJSONUtils
///
/// 提供 SwiftyJSON 与 Codable/Decodable 类型之间的便捷转换、复杂 JSON 字符串处理及调试辅助等工具方法。
///
/// ### 使用示例
/// ```swift
/// struct User: Codable { let id: Int; let name: String }
/// let user = SwiftyJSONUtils.decodeFromJson(User.self, from: "{\"id\":1,\"name\":\"Tom\"}")
/// let jsonString = SwiftyJSONUtils.encodeToString(user)
/// ```
/// - Note: 对于嵌套JSON字符串处理可使用 normalize() 方法。
/// - SeeAlso: `SwiftyJSONUtils.decodeFromData`, `SwiftyJSONUtils.encodeToData`
public enum SwiftyJSONUtils {

    // MARK: - 解码方法（反序列化）

    /// 从 JSON 字符串解码为对象
    ///
    /// ### 使用示例
    /// ```swift
    /// let user = SwiftyJSONUtils.decodeFromJson(User.self, from: "{\"id\":1}")
    /// ```
    /// - Parameters:
    ///   - type: 目标类型（需遵守 Decodable 协议）
    ///   - string: JSON 格式字符串
    /// - Returns: 解码后的对象，失败返回 nil
    public static func decodeFromJson<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        let sanitizedString = sanitize(string)
        guard let data = sanitizedString.data(using: .utf8) else {
            debugPrint("[SwiftyJSONUtils] 字符串转Data失败")
            return nil
        }
        return decodeFromData(type, from: data)
    }

    /// 从 Data 解码为对象
    ///
    /// ### 使用示例
    /// ```swift
    /// let user = SwiftyJSONUtils.decodeFromData(User.self, from: data)
    /// ```
    /// - Parameters:
    ///   - type: 目标类型
    ///   - data: JSON 格式二进制数据
    /// - Returns: 解码后的对象，失败返回 nil
    public static func decodeFromData<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            debugPrint("[SwiftyJSONUtils] 解码失败: \(error)")
            return nil
        }
    }

    /// 从字典或字典数组解码为对象或对象数组
    ///
    /// ### 使用示例
    /// ```swift
    /// let user = SwiftyJSONUtils.decodeFromObject(User.self, from: dict)
    /// ```
    /// - Parameters:
    ///   - type: 目标类型（T 或 [T]，需遵守 Decodable 协议）
    ///   - object: 字典或字典数组
    /// - Returns: 解码后的对象或对象数组，失败返回 nil
    public static func decodeFromObject<T: Decodable>(_ type: T.Type, from object: Any) -> T? {
        do {
            let json = JSON(object)
            let data = try json.rawData()
            return decodeFromData(type, from: data)
        } catch {
            debugPrint("[SwiftyJSONUtils] 对象转Data失败: \(error)")
            return nil
        }
    }

    // MARK: - 编码方法（序列化）

    /// 编码对象为 Data
    ///
    /// ### 使用示例
    /// ```swift
    /// let data = SwiftyJSONUtils.encodeToData(user)
    /// ```
    /// - Parameters:
    ///   - value: 要编码的对象（需遵守 Encodable 协议）
    ///   - prettyPrinted: 是否美化输出格式
    /// - Returns: JSON 格式二进制数据，失败返回 nil
    public static func encodeToData<T: Encodable>(_ value: T, prettyPrinted: Bool = false) -> Data? {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = .prettyPrinted
        }
        return try? encoder.encode(value)
    }

    /// 编码对象为 JSON 字符串
    ///
    /// ### 使用示例
    /// ```swift
    /// let jsonString = SwiftyJSONUtils.encodeToString(user)
    /// ```
    /// - Parameters:
    ///   - value: 要编码的对象
    ///   - prettyPrinted: 是否美化输出格式
    /// - Returns: JSON 字符串
    public static func encodeToString<T: Encodable>(_ value: T, prettyPrinted: Bool = false) -> String? {
        guard let data = encodeToData(value, prettyPrinted: prettyPrinted) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 编码对象为字典
    ///
    /// ### 使用示例
    /// ```swift
    /// let dict = SwiftyJSONUtils.encodeToDictionary(user)
    /// ```
    /// - Parameter value: 要编码的对象
    /// - Returns: 字典对象，失败返回 nil
    public static func encodeToDictionary<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = encodeToData(value) else { return nil }
        return try? JSON(data: data).dictionaryObject
    }

    /// 编码数组为字典数组
    ///
    /// ### 使用示例
    /// ```swift
    /// let dicts = SwiftyJSONUtils.encodeToDictionaries([user])
    /// ```
    /// - Parameter values: 要编码的对象数组
    /// - Returns: 字典数组，失败返回 nil
    public static func encodeToDictionaries<T: Encodable>(_ values: [T]) -> [[String: Any]]? {
        guard let data = encodeToData(values) else { return nil }
        return try? JSON(data: data).arrayObject as? [[String: Any]]
    }

    // MARK: - 复杂JSON处理

    /// 规范化 JSON 字符串（处理嵌套 JSON 字符串问题）
    ///
    /// ### 使用示例
    /// ```swift
    /// let normalized = SwiftyJSONUtils.normalize(jsonString)
    /// ```
    /// - Parameter jsonString: 原始 JSON 字符串
    /// - Returns: 规范化后的字符串（去除部分转义和嵌套结构），失败返回 nil
    public static func normalize(_ jsonString: String) -> String? {
        let pattern = #"("([^"]+)"\s*:\s*)"(\[.*?\]|\{.*?\})""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let modifiedString = regex.stringByReplacingMatches(
            in: jsonString,
            options: [],
            range: NSRange(location: 0, length: jsonString.utf16.count),
            withTemplate: #"$1$3"#
        )

        return modifiedString.replacingOccurrences(of: "\\", with: "")
    }

    // MARK: - 辅助方法

    /// 预处理 JSON 字符串，去除换行和空白
    ///
    /// - Parameter string: 原始字符串
    /// - Returns: 预处理后的字符串
    private static func sanitize(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - SwiftyJSON 扩展方法

    /// 将 JSON 对象转换为美化的字符串
    ///
    /// ### 使用示例
    /// ```swift
    /// let pretty = SwiftyJSONUtils.toPrettyJSONString(json)
    /// ```
    /// - Parameter json: SwiftyJSON 对象
    /// - Returns: 美化的 JSON 字符串
    public static func toPrettyJSONString(_ json: JSON) -> String {
        if let prettyString = json.rawString(options: .prettyPrinted) {
            return prettyString.replacingOccurrences(of: "\\/", with: "/")
        }
        return json.description
    }

    /// 将 Data 转换为美化的 JSON 字符串
    ///
    /// ### 使用示例
    /// ```swift
    /// let pretty = SwiftyJSONUtils.dataToPrettyJSONString(data)
    /// ```
    /// - Parameter data: JSON 二进制数据
    /// - Returns: 美化的 JSON 字符串（如解码失败则原样输出）
    public static func dataToPrettyJSONString(_ data: Data) -> String {
        do {
            let json = try JSON(data: data)
            return toPrettyJSONString(json)
        } catch {
            return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\\/", with: "/") ?? ""
        }
    }

    // MARK: - 调试工具

    /// 调试日志（仅 DEBUG 构建输出）
    ///
    /// - Parameter message: 日志内容
    private static func debugPrint(_ message: Any) {
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - JSONString 属性包装器

/// JSONString 属性包装器
///
/// 用于属性为 JSON 字符串的字段，自动进行解码或编码。
///
/// ### 使用示例
/// ```swift
/// struct Wrapper: Codable {
///     @JSONString var value: User
/// }
/// ```
/// - Note: 支持嵌套 JSON 的自动解析。
@propertyWrapper
public struct JSONString<T: Codable>: Codable {
    public var wrappedValue: T

    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let jsonString = try container.decode(String.self)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON string is not valid UTF-8"
            )
        }
        self.wrappedValue = try JSONDecoder().decode(T.self, from: jsonData)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let jsonData = try JSONEncoder().encode(wrappedValue)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                wrappedValue,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Encoded JSON data is not valid UTF-8"
                )
            )
        }
        try container.encode(jsonString)
    }
}

// MARK: - SwiftyJSON 扩展

public extension JSON {
    /// 转换为美化的 JSON 字符串
    ///
    /// ### 使用示例
    /// ```swift
    /// let pretty = json.toPrettyString()
    /// ```
    /// - Returns: 格式化 JSON 字符串
    func toPrettyString() -> String {
        return SwiftyJSONUtils.toPrettyJSONString(self)
    }

    /// 转换为 Decodable 模型对象
    ///
    /// ### 使用示例
    /// ```swift
    /// let user = json.toModel(User.self)
    /// ```
    /// - Parameter type: 目标模型类型
    /// - Returns: 解码后的模型对象，失败返回 nil
    func toModel<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? self.rawData() else { return nil }
        return SwiftyJSONUtils.decodeFromData(type, from: data)
    }

    /// 转换为 Decodable 模型数组
    ///
    /// ### 使用示例
    /// ```swift
    /// let users = json.toModelArray(User.self)
    /// ```
    /// - Parameter type: 目标模型类型
    /// - Returns: 模型数组，失败返回 nil
    func toModelArray<T: Decodable>(_ type: T.Type) -> [T]? {
        guard let data = try? self.rawData() else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }
}
