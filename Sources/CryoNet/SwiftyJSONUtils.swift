import Foundation
import SwiftyJSON

// MARK: - SwiftyJSON 工具扩展
public enum SwiftyJSONUtils {
    
    // MARK: - 解码方法（反序列化）
    /// 从JSON字符串解码对象
    /// - Parameters:
    ///   - type: 目标类型 (需遵守 Decodable 协议)
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
    
    /// 从Data解码对象
    /// - Parameters:
    ///   - type: 目标类型
    ///   - data: JSON 格式二进制数据
    public static func decodeFromData<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            debugPrint("[SwiftyJSONUtils] 解码失败: \(error)")
            return nil
        }
    }
    
    /// 从字典或字典数组解码对象或对象数组
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
    /// 编码对象为Data
    /// - Parameters:
    ///   - value: 要编码的对象 (需遵守 Encodable 协议)
    ///   - prettyPrinted: 是否美化输出格式
    /// - Returns: JSON 格式二进制数据，失败返回 nil
    public static func encodeToData<T: Encodable>(_ value: T, prettyPrinted: Bool = false) -> Data? {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = .prettyPrinted
        }
        return try? encoder.encode(value)
    }
    
    /// 编码对象为JSON字符串
    /// - Parameters:
    ///   - value: 要编码的对象
    ///   - prettyPrinted: 是否美化输出格式
    public static func encodeToString<T: Encodable>(_ value: T, prettyPrinted: Bool = false) -> String? {
        guard let data = encodeToData(value, prettyPrinted: prettyPrinted) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// 编码对象为字典
    /// - Parameter value: 要编码的对象
    public static func encodeToDictionary<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = encodeToData(value) else { return nil }
        return try? JSON(data: data).dictionaryObject
    }
    
    /// 编码数组为字典数组
    /// - Parameter values: 要编码的对象数组
    public static func encodeToDictionaries<T: Encodable>(_ values: [T]) -> [[String: Any]]? {
        guard let data = encodeToData(values) else { return nil }
        return try? JSON(data: data).arrayObject as? [[String: Any]]
    }
    
    // MARK: - 复杂JSON处理
    
    /// 规范化JSON字符串（处理嵌套JSON字符串问题）
    /// - Parameter jsonString: 原始JSON字符串
    public static func normalize(_ jsonString: String) -> String? {
        let pattern = #"("([^"]+)"\s*:\s*)"(\\?\[.*?\]|\\?\{.*?\})""#
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
    
    /// 预处理JSON字符串
    private static func sanitize(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - SwiftyJSON 扩展方法
    
    /// 将JSON对象转换为美化的字符串
    public static func toPrettyJSONString(_ json: JSON) -> String {
        if let prettyString = json.rawString(options: .prettyPrinted) {
            return prettyString.replacingOccurrences(of: "\\/", with: "/")
        }
        return json.description
    }
    
    /// 将Data转换为美化的JSON字符串
    public static func dataToPrettyJSONString(_ data: Data) -> String {
        do {
            let json = try JSON(data: data)
            return toPrettyJSONString(json)
        } catch {
            return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\\/", with: "/") ?? ""
        }
    }
    
    // MARK: - 调试工具
    private static func debugPrint(_ message: Any) {
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - JSONString 属性包装器
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
    /// 转换为美化的JSON字符串
    func toPrettyString() -> String {
        return SwiftyJSONUtils.toPrettyJSONString(self)
    }
    
    /// 转换为模型对象
    func toModel<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? self.rawData() else { return nil }
        return SwiftyJSONUtils.decodeFromData(type, from: data)
    }
    
    /// 转换为模型数组
    func toModelArray<T: Decodable>(_ type: T.Type) -> [T]? {
        guard let data = try? self.rawData() else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }
}

