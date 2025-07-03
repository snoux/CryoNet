import Foundation
import SwiftyJSON

// MARK: - JSON解析协议

/// JSONParseable 协议
///
/// 适用于支持从 SwiftyJSON 直接解析的模型。
///
/// 实现该协议后可通过 `toModel`、`toModelArray` 等扩展方法，直接从 JSON 生成模型或模型数组。
///
/// ### 使用示例
/// ```swift
/// struct User: JSONParseable {
///     let id: Int
///     let name: String
///     init?(json: JSON) {
///         guard let id = json["id"].int, let name = json["name"].string else { return nil }
///         self.id = id
///         self.name = name
///     }
/// }
/// let user = json.toModel(User.self)
/// let users = json.toModelArray(User.self)
/// ```
/// - Note: 只需实现 `init(json:)` 初始化方法即可。
/// - SeeAlso: `JSON.toModel(_:, keyPath:)`, `JSON.toModelArray(_:, keyPath:)`
/// - Parameters:
///   - json: SwiftyJSON.JSON对象
public protocol JSONParseable {
    /// 从JSON初始化模型
    /// - Parameter json: SwiftyJSON.JSON对象
    init?(json: JSON)
}

// MARK: - SwiftyJSON 模型转换扩展

public extension JSON {
    /// 从JSON中提取目标数据为Data
    ///
    /// 支持直接提取JSON中的Data数据，若JSON无效则返回原始Data。
    ///
    /// ### 使用示例
    /// ```swift
    /// let result = JSON.extractDataFromJSON(json, originalData: data)
    /// ```
    /// - Note: 若JSON为null或不存在，则返回原始Data。
    /// - Parameters:
    ///   - json: 目标JSON
    ///   - originalData: 原始数据
    /// - Returns: 提取后的Data，或原始Data，或失败
    static func extractDataFromJSON(_ json: SwiftyJSON.JSON, originalData: Data) -> Result<Data, Error> {
        if !json.exists() || json.type == .null {
            return .success(originalData)
        } else {
            do {
                let validData: Data
                switch json.type {
                case .dictionary, .array:
                    validData = try json.rawData()
                case .string:
                    validData = Data(json.stringValue.utf8)
                case .number, .bool:
                    validData = Data(json.stringValue.utf8)
                default:
                    return .success(originalData)
                }
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
    }

    /// 直接从 JSON 对象转换为遵循 JSONParseable 协议的模型
    ///
    /// ### 使用示例
    /// ```swift
    /// let user = json.toModel(User.self)
    /// let user = json.toModel(User.self, keyPath: "data.user")
    /// ```
    /// - Note: 若 keyPath 无效或数据不符合模型，返回 nil。
    /// - SeeAlso: `toModelArray(_:keyPath:)`
    /// - Parameters:
    ///   - type: 目标模型类型
    ///   - keyPath: JSON 中的键路径，默认 nil（根路径）
    /// - Returns: 转换后的模型，失败返回 nil
    func toModel<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) -> T? {
        let targetJSON: JSON
        if let keyPath = keyPath {
            targetJSON = self[keyPath]
            if targetJSON.type == .null || targetJSON.type == .unknown {
                return nil
            }
        } else {
            targetJSON = self
        }
        return T(json: targetJSON)
    }

    /// 直接从 JSON 对象转换为遵循 JSONParseable 协议的模型数组
    ///
    /// ### 使用示例
    /// ```swift
    /// let users = json.toModelArray(User.self)
    /// ```
    /// - Note: 仅当JSON为数组类型时有效。
    /// - Parameters:
    ///   - type: 目标模型类型
    ///   - keyPath: JSON 中的键路径，默认 nil（根路径）
    /// - Returns: 转换后的模型数组
    func toModelArray<T: JSONParseable>(_ type: T.Type, keyPath: String? = nil) -> [T] {
        let targetJSON: JSON
        if let keyPath = keyPath {
            targetJSON = self[keyPath]
        } else {
            targetJSON = self
        }

        guard targetJSON.type == .array else { return [] }

        var result: [T] = []
        for (_, json) in targetJSON {
            if let model = T(json: json) {
                result.append(model)
            }
        }
        return result
    }

    /// 直接从 JSON 对象转换为模型（使用自定义解析闭包）
    ///
    /// ### 使用示例
    /// ```swift
    /// let user = json.toModel { json in User(json: json) }
    /// ```
    /// - Parameters:
    ///   - parser: 自定义解析闭包
    /// - Returns: 转换后的模型
    func toModel<T>(parser: (JSON) -> T?) -> T? {
        return parser(self)
    }

    /// 直接从 JSON 对象转换为模型数组（使用自定义解析闭包）
    ///
    /// ### 使用示例
    /// ```swift
    /// let users = json.toModelArray { json in User(json: json) }
    /// ```
    /// - Parameters:
    ///   - keyPath: JSON中的键路径，默认 nil（根路径）
    ///   - parser: 自定义解析闭包
    /// - Returns: 转换后的模型数组
    func toModelArray<T>(keyPath: String? = nil, parser: (JSON) -> T?) -> [T] {
        let targetJSON: JSON
        if let keyPath = keyPath {
            targetJSON = self[keyPath]
        } else {
            targetJSON = self
        }

        guard targetJSON.type == .array else { return [] }

        var result: [T] = []
        for (_, json) in targetJSON {
            if let model = parser(json) {
                result.append(model)
            }
        }
        return result
    }

    // MARK: - 类型安全的便捷取值方法

    /// 获取字符串值，支持默认值
    ///
    /// ### 使用示例
    /// ```swift
    /// let name = json.string("name", defaultValue: "未知")
    /// ```
    /// - Parameters:
    ///   - keyPath: 键路径
    ///   - defaultValue: 默认值，默认为空字符串
    /// - Returns: 字符串值或默认值
    func string(_ keyPath: String, defaultValue: String = "") -> String {
        return self[keyPath].stringValue.isEmpty ? defaultValue : self[keyPath].stringValue
    }

    /// 获取可选字符串值
    ///
    /// ### 使用示例
    /// ```swift
    /// let name = json.optionalString("name")
    /// ```
    /// - Parameter keyPath: 键路径
    /// - Returns: 字符串值或 nil
    func optionalString(_ keyPath: String) -> String? {
        return self[keyPath].type == .string ? self[keyPath].stringValue : nil
    }

    /// 获取整数值，支持默认值
    ///
    /// ### 使用示例
    /// ```swift
    /// let age = json.int("age", defaultValue: 18)
    /// ```
    /// - Parameters:
    ///   - keyPath: 键路径
    ///   - defaultValue: 默认值，默认为0
    /// - Returns: 整数值或默认值
    func int(_ keyPath: String, defaultValue: Int = 0) -> Int {
        return self[keyPath].type == .number ? self[keyPath].intValue : defaultValue
    }

    /// 获取可选整数值
    ///
    /// ### 使用示例
    /// ```swift
    /// let age = json.optionalInt("age")
    /// ```
    /// - Parameter keyPath: 键路径
    /// - Returns: 整数值或 nil
    func optionalInt(_ keyPath: String) -> Int? {
        return self[keyPath].type == .number ? self[keyPath].intValue : nil
    }

    /// 获取双精度浮点数值，支持默认值
    ///
    /// ### 使用示例
    /// ```swift
    /// let price = json.double("price", defaultValue: 0.99)
    /// ```
    /// - Parameters:
    ///   - keyPath: 键路径
    ///   - defaultValue: 默认值，默认为0.0
    /// - Returns: Double 值或默认值
    func double(_ keyPath: String, defaultValue: Double = 0.0) -> Double {
        return self[keyPath].type == .number ? self[keyPath].doubleValue : defaultValue
    }

    /// 获取可选双精度浮点数值
    ///
    /// ### 使用示例
    /// ```swift
    /// let price = json.optionalDouble("price")
    /// ```
    /// - Parameter keyPath: 键路径
    /// - Returns: Double 值或 nil
    func optionalDouble(_ keyPath: String) -> Double? {
        return self[keyPath].type == .number ? self[keyPath].doubleValue : nil
    }

    /// 获取布尔值，支持默认值
    ///
    /// ### 使用示例
    /// ```swift
    /// let isActive = json.bool("active", defaultValue: true)
    /// ```
    /// - Parameters:
    ///   - keyPath: 键路径
    ///   - defaultValue: 默认值，默认为false
    /// - Returns: Bool 值或默认值
    func bool(_ keyPath: String, defaultValue: Bool = false) -> Bool {
        return self[keyPath].type == .bool ? self[keyPath].boolValue : defaultValue
    }

    /// 获取可选布尔值
    ///
    /// ### 使用示例
    /// ```swift
    /// let isActive = json.optionalBool("active")
    /// ```
    /// - Parameter keyPath: 键路径
    /// - Returns: Bool 值或 nil
    func optionalBool(_ keyPath: String) -> Bool? {
        return self[keyPath].type == .bool ? self[keyPath].boolValue : nil
    }

    /// 获取数组，支持默认值
    ///
    /// ### 使用示例
    /// ```swift
    /// let items = json.array("items", defaultValue: [])
    /// ```
    /// - Parameters:
    ///   - keyPath: 键路径
    ///   - defaultValue: 默认值，默认为空数组
    /// - Returns: JSON 数组或默认值
    func array(_ keyPath: String, defaultValue: [JSON] = []) -> [JSON] {
        return self[keyPath].type == .array ? self[keyPath].arrayValue : defaultValue
    }

    /// 获取可选数组
    ///
    /// ### 使用示例
    /// ```swift
    /// let items = json.optionalArray("items")
    /// ```
    /// - Parameter keyPath: 键路径
    /// - Returns: JSON 数组或 nil
    func optionalArray(_ keyPath: String) -> [JSON]? {
        return self[keyPath].type == .array ? self[keyPath].arrayValue : nil
    }

    /// 获取字典，支持默认值
    ///
    /// ### 使用示例
    /// ```swift
    /// let dict = json.dictionary("detail", defaultValue: [:])
    /// ```
    /// - Parameters:
    ///   - keyPath: 键路径
    ///   - defaultValue: 默认值，默认为空字典
    /// - Returns: JSON 字典或默认值
    func dictionary(_ keyPath: String, defaultValue: [String: JSON] = [:]) -> [String: JSON] {
        return self[keyPath].type == .dictionary ? self[keyPath].dictionaryValue : defaultValue
    }

    /// 获取可选字典
    ///
    /// ### 使用示例
    /// ```swift
    /// let dict = json.optionalDictionary("detail")
    /// ```
    /// - Parameter keyPath: 键路径
    /// - Returns: JSON 字典或 nil
    func optionalDictionary(_ keyPath: String) -> [String: JSON]? {
        return self[keyPath].type == .dictionary ? self[keyPath].dictionaryValue : nil
    }

    /// 安全获取嵌套 JSON 字符串并解析
    ///
    /// 若目标为对象或数组，直接返回；若为字符串类型，尝试解析为 JSON。
    ///
    /// ### 使用示例
    /// ```swift
    /// let nested = json.parseNestedJSON("profile")
    /// ```
    /// - Parameter keyPath: 键路径
    /// - Returns: 如果是对象或数组直接返回，若为字符串则尝试解析，否则返回空 JSON
    func parseNestedJSON(_ keyPath: String) -> JSON {
        let value = self[keyPath]

        // 如果已经是对象或数组类型，直接返回
        if value.type == .dictionary || value.type == .array {
            return value
        }

        // 如果是字符串类型，尝试解析为 JSON
        if value.type == .string {
            let jsonString = value.stringValue
            if let data = jsonString.data(using: .utf8) {
                do {
                    return try JSON(data: data)
                } catch {
                    print("解析嵌套JSON字符串失败: \(error.localizedDescription)")
                }
            }
        }

        // 解析失败返回空 JSON 对象
        return JSON()
    }
}
