import Foundation
import SwiftyJSON

// MARK: - JSON 值包装器（支持类型推断和默认值）

/// JSON 值包装器，用于支持类型推断的下标访问和默认值设置
///
/// 此结构体用于实现 `json["key"] ?? "默认值"` 的便捷语法。
/// 支持 String、Int、Double、Bool 等常见类型的自动推断。
///
/// - Note: 内部使用，您无需直接使用此类型
public struct JSONValue<T> {
    let json: JSON
    let keyPath: String
    
    /// 获取值（如果存在且类型匹配）
    var value: T? {
        let jsonValue = json[keyPath]
        
        // 根据类型进行转换（使用类型擦除和强制转换）
        if T.self == String.self {
            if jsonValue.type == .string && !jsonValue.stringValue.isEmpty {
                return unsafeBitCast(jsonValue.stringValue, to: T.self)
            }
            return nil
        } else if T.self == Int.self {
            if jsonValue.type == .number {
                return unsafeBitCast(jsonValue.intValue, to: T.self)
            }
            return nil
        } else if T.self == Double.self {
            if jsonValue.type == .number {
                return unsafeBitCast(jsonValue.doubleValue, to: T.self)
            }
            return nil
        } else if T.self == Bool.self {
            if jsonValue.type == .bool {
                return unsafeBitCast(jsonValue.boolValue, to: T.self)
            }
            return nil
        }
        
        return nil
    }
}

// MARK: - JSONValue 默认值支持

/// 支持 `??` 操作符设置默认值（基本类型）
extension JSONValue {
    /// 使用 `??` 操作符设置默认值
    ///
    /// ### 使用示例
    /// ```swift
    /// let title = json["title"] ?? "默认标题"
    /// let status = json["status"] ?? 0
    /// ```
    ///
    /// - Parameters:
    ///   - lhs: JSON 值包装器
    ///   - rhs: 默认值
    /// - Returns: JSON 中的值（如果存在）或默认值
    public static func ?? (lhs: JSONValue<T>, rhs: T) -> T {
        return lhs.value ?? rhs
    }
}

// MARK: - JSONValue 嵌套模型支持

/// 支持嵌套模型解析（JSONParseable 类型）
extension JSONValue where T: JSONParseable {
    /// 获取嵌套模型值（如果存在且类型匹配）
    var modelValue: T? {
        let jsonValue = json[keyPath]
        // 如果 JSON 值为 null 或不存在，返回 nil
        if jsonValue.type == .null || jsonValue.type == .unknown {
            return nil
        }
        // 使用 toModel 方法解析嵌套模型
        return jsonValue.toModel(T.self)
    }
    
    /// 使用 `??` 操作符设置默认值（嵌套模型）
    ///
    /// ### 使用示例
    /// ```swift
    /// let details = json["details"] ?? NewDetailsModel(json: JSON())!
    /// // 或者使用默认模型
    /// let defaultDetails = NewDetailsModel(json: JSON(["title": "默认详情"]))!
    /// let details = json["details"] ?? defaultDetails
    /// ```
    ///
    /// - Parameters:
    ///   - lhs: JSON 值包装器
    ///   - rhs: 默认模型实例
    /// - Returns: JSON 中的模型（如果存在）或默认模型
    public static func ?? (lhs: JSONValue<T>, rhs: T) -> T {
        return lhs.modelValue ?? rhs
    }
}

// MARK: - JSONValue 嵌套模型数组支持

/// 支持嵌套模型数组解析（[JSONParseable] 类型）
/// 使用条件扩展来处理 Array<Element> 类型，其中 Element 遵循 JSONParseable
extension JSONValue where T: RangeReplaceableCollection, T.Element: JSONParseable {
    /// 获取嵌套模型数组值（如果存在且类型匹配）
    var modelArrayValue: T? {
        let jsonValue = json[keyPath]
        // 如果 JSON 值为 null 或不存在，返回 nil
        if jsonValue.type == .null || jsonValue.type == .unknown {
            return nil
        }
        // 使用 toModelArray 方法解析嵌套模型数组
        let array = jsonValue.toModelArray(T.Element.self)
        // 将 [T.Element] 转换为 T 类型
        // 由于 T 是 RangeReplaceableCollection，我们可以使用 init(_:) 初始化
        return T(array)
    }
    
    /// 使用 `??` 操作符设置默认值（嵌套模型数组）
    ///
    /// ### 使用示例
    /// ```swift
    /// let comments: [CommentModel] = json["comments"] ?? []
    /// // 或者使用默认数组
    /// let defaultComments: [CommentModel] = [CommentModel(json: JSON(["title": "默认"]))!]
    /// let comments = json["comments"] ?? defaultComments
    /// ```
    ///
    /// - Parameters:
    ///   - lhs: JSON 值包装器
    ///   - rhs: 默认模型数组
    /// - Returns: JSON 中的模型数组（如果存在）或默认数组
    public static func ?? (lhs: JSONValue<T>, rhs: T) -> T {
        return lhs.modelArrayValue ?? rhs
    }
}

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

// MARK: - Codable 自动桥接支持（测试/临时版本）

/// ⚠️ 测试/临时版本：为同时实现 Codable 的类型提供 JSONParseable 自动桥接
///
/// 此功能为测试版本，可能会在后续版本中调整或移除。
/// 当模型同时实现 `Codable` 和 `JSONParseable` 时，无需手动实现 `init?(json:)`，
/// 系统会自动使用 Codable 的 Decodable 能力进行解析。
///
/// ### 使用示例
/// ```swift
/// // 方式1：自动桥接（最简单，无默认值需求）
/// struct NewModel: Codable, JSONParseable {
///     let title: String
///     var id = UUID()
///     // 无需实现 init?(json:) 或 init(from decoder:)，自动从 Codable 桥接
/// }
///
/// // 方式2：自定义 Decodable 实现（支持默认值）
/// struct NewModel: Codable, JSONParseable {
///     let title: String
///     let status: Int
///
///     enum CodingKeys: String, CodingKey {
///         case title, status
///     }
///
///     // 实现自定义解码
///     init(from decoder: Decoder) throws {
///         let container = try decoder.container(keyedBy: CodingKeys.self)
///         title = try container.decodeIfPresent(String.self, forKey: .title) ?? "默认标题"
///         status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 0
///     }
///     // 注意：如果实现了 init(from decoder:)，自动桥接会优先使用它
/// }
///
/// // 方式3：手动实现 init?(json:)（特殊场景）
/// struct NewModel: Codable, JSONParseable {
///     let title: String
///     init?(json: JSON) {
///         self.title = json.string("title", defaultValue: "默认标题")
///     }
/// }
/// ```
///
/// - Note:
///   - ⚠️ 此功能为测试版本，API 可能会变化
///   - **优先级**：`init(from decoder:)` > `init?(json:)` > 自动桥接
///   - 如果实现了自定义 `init(from decoder:)`，自动桥接会优先使用它（完全支持默认值）
///   - 如果手动实现了 `init?(json:)`，则优先使用手动实现
///   - 自动桥接使用 `JSONDecoder` 进行解码，支持所有 Codable 特性（如 CodingKeys、自定义解码等）
///   - 性能：需要将 JSON 转换为 Data 再解码，性能略低于直接解析，但可接受
///   - **默认值支持**：自动桥接不支持默认值，如需默认值请使用方式2（自定义 `init(from decoder:)`）
extension JSONParseable where Self: Decodable {
    /// 从 JSON 自动桥接初始化（使用 Codable）
    ///
    /// ⚠️ 测试/临时版本：此方法会自动将 SwiftyJSON.JSON 转换为 Data，然后使用 JSONDecoder 解码。
    ///
    /// - Parameter json: SwiftyJSON.JSON 对象
    /// - Returns: 解码后的模型实例，失败返回 nil
    ///
    /// - Note:
    ///   - 如果模型实现了自定义 `init(from decoder:)`，会自动使用它（支持默认值）
    ///   - 如果模型手动实现了 `init?(json:)`，会优先使用手动实现
    ///   - 自动桥接不支持默认值，如需默认值请实现自定义 `init(from decoder:)`
    public init?(json: JSON) {
        // 步骤1：将 JSON 转换为 Data
        // 使用 json.rawData() 方法，这是 SwiftyJSON 提供的标准方法
        guard let data = try? json.rawData() else {
            #if DEBUG
            debugPrint("[JSONParseable] ⚠️ Codable 自动桥接失败: JSON 转 Data 失败")
            #endif
            return nil
        }
        
        // 步骤2：使用 JSONDecoder 解码为 Codable 类型
        // 如果模型实现了自定义 init(from decoder:)，会自动使用它
        do {
            let decoder = JSONDecoder()
            // 可以在这里配置 decoder 的选项，如日期格式、键名策略等
            // decoder.dateDecodingStrategy = .iso8601
            // decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            self = try decoder.decode(Self.self, from: data)
        } catch {
            // 解码失败，返回 nil
            // 在 DEBUG 模式下打印错误信息，便于调试
            #if DEBUG
            debugPrint("[JSONParseable] ⚠️ Codable 自动桥接失败: \(error)")
            debugPrint("[JSONParseable] JSON 内容: \(json)")
            #endif
            return nil
        }
    }
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
    
    // MARK: - 类型推断下标访问（便捷方式）
    
    /// 类型推断的下标访问，支持 `??` 操作符设置默认值
    ///
    /// 提供更简洁的语法来访问 JSON 值，支持类型推断和默认值。
    /// **支持嵌套路径访问**和**嵌套模型解析**。
    ///
    /// ### 使用示例
    /// ```swift
    /// // 简单字段
    /// let title = json["title"] ?? "默认标题"
    /// let status = json["status"] ?? 0
    /// let price = json["price"] ?? 0.0
    /// let isActive = json["isActive"] ?? false
    ///
    /// // 嵌套路径（支持点号分隔）
    /// let userName = json["user.name"] ?? "未知用户"
    /// let userAge = json["user.profile.age"] ?? 0
    /// let city = json["data.address.city"] ?? "未知城市"
    ///
    /// // 嵌套模型解析
    /// struct NewModel: JSONParseable {
    ///     let title: String
    ///     let details: NewDetailsModel
    ///     let comments: [CommentModel]
    ///
    ///     init?(json: JSON) {
    ///         self.title = json["title"] ?? "默认标题"
    ///         
    ///         // 单个嵌套模型：方式1（使用 ?? 操作符）
    ///         let defaultDetails = NewDetailsModel(json: JSON(["title": "默认详情"]))!
    ///         self.details = json["details"] ?? defaultDetails
    ///         
    ///         // 单个嵌套模型：方式2（使用 toModel 方法，推荐）
    ///         // self.details = json.toModel(NewDetailsModel.self, keyPath: "details") ?? defaultDetails
    ///         
    ///         // 嵌套模型数组：使用 ?? 操作符
    ///         self.comments = json["comments"] ?? []
    ///         
    ///         // 嵌套模型数组：使用 toModelArray 方法（推荐）
    ///         // self.comments = json.toModelArray(CommentModel.self, keyPath: "comments")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter keyPath: JSON 键路径，支持嵌套路径（使用点号分隔，如 `"user.name"`）
    /// - Returns: `JSONValue` 包装器，支持类型推断和 `??` 操作符
    ///
    /// - Note:
    ///   - 此方法提供便捷语法，不影响现有的 `string(_:defaultValue:)` 等方法
    ///   - 支持类型推断，编译器会自动推断返回类型
    ///   - **支持嵌套路径**：使用点号分隔的路径（如 `"user.name"`），与现有方法行为一致
    ///   - **支持嵌套模型**：如果类型遵循 `JSONParseable` 协议，会自动解析嵌套模型
    ///   - 如果 JSON 中不存在该键或类型不匹配，返回 nil，可使用 `??` 设置默认值
    ///   - 嵌套路径访问与 `json.string("user.name", defaultValue:)` 等现有方法行为完全一致
    ///   - **嵌套模型建议**：对于嵌套模型，推荐使用 `json.toModel(_:keyPath:)` 方法，更安全且支持可选值
    subscript<T>(_ keyPath: String) -> JSONValue<T> {
        return JSONValue(json: self, keyPath: keyPath)
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
