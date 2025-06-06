import Foundation
import SwiftyJSON

// MARK: - JSON解析协议
/// 支持从SwiftyJSON直接解析的协议
public protocol JSONParseable {
    /// 从JSON初始化
    init?(json: JSON)
}

// MARK: - SwiftyJSON 模型转换扩展
public extension JSON {
    
    /// 直接从JSON对象转换为遵循JSONParseable协议的模型
    /// - Parameters:
    ///   - type: 目标模型类型
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
    /// - Returns: 转换后的模型，失败返回nil
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
    
    /// 直接从JSON对象转换为遵循JSONParseable协议的模型数组
    /// - Parameters:
    ///   - type: 目标模型类型
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
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
    
    /// 直接从JSON对象转换为模型（使用自定义解析闭包）
    /// - Parameter parser: 自定义解析闭包
    /// - Returns: 转换后的模型
    func toModel<T>(parser: (JSON) -> T?) -> T? {
        return parser(self)
    }
    
    /// 直接从JSON对象转换为模型数组（使用自定义解析闭包）
    /// - Parameters:
    ///   - keyPath: JSON中的键路径，默认为nil（根路径）
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
    
    /// 获取字符串值，支持默认值
    func string(_ keyPath: String, defaultValue: String = "") -> String {
        return self[keyPath].stringValue.isEmpty ? defaultValue : self[keyPath].stringValue
    }
    
    /// 获取可选字符串值
    func optionalString(_ keyPath: String) -> String? {
        return self[keyPath].type == .string ? self[keyPath].stringValue : nil
    }
    
    /// 获取整数值，支持默认值
    func int(_ keyPath: String, defaultValue: Int = 0) -> Int {
        return self[keyPath].type == .number ? self[keyPath].intValue : defaultValue
    }
    
    /// 获取可选整数值
    func optionalInt(_ keyPath: String) -> Int? {
        return self[keyPath].type == .number ? self[keyPath].intValue : nil
    }
    
    /// 获取双精度浮点值，支持默认值
    func double(_ keyPath: String, defaultValue: Double = 0.0) -> Double {
        return self[keyPath].type == .number ? self[keyPath].doubleValue : defaultValue
    }
    
    /// 获取可选双精度浮点值
    func optionalDouble(_ keyPath: String) -> Double? {
        return self[keyPath].type == .number ? self[keyPath].doubleValue : nil
    }
    
    /// 获取布尔值，支持默认值
    func bool(_ keyPath: String, defaultValue: Bool = false) -> Bool {
        return self[keyPath].type == .bool ? self[keyPath].boolValue : defaultValue
    }
    
    /// 获取可选布尔值
    func optionalBool(_ keyPath: String) -> Bool? {
        return self[keyPath].type == .bool ? self[keyPath].boolValue : nil
    }
    
    /// 获取数组，支持默认值
    func array(_ keyPath: String, defaultValue: [JSON] = []) -> [JSON] {
        return self[keyPath].type == .array ? self[keyPath].arrayValue : defaultValue
    }
    
    /// 获取可选数组
    func optionalArray(_ keyPath: String) -> [JSON]? {
        return self[keyPath].type == .array ? self[keyPath].arrayValue : nil
    }
    
    /// 获取字典，支持默认值
    func dictionary(_ keyPath: String, defaultValue: [String: JSON] = [:]) -> [String: JSON] {
        return self[keyPath].type == .dictionary ? self[keyPath].dictionaryValue : defaultValue
    }
    
    /// 获取可选字典
    func optionalDictionary(_ keyPath: String) -> [String: JSON]? {
        return self[keyPath].type == .dictionary ? self[keyPath].dictionaryValue : nil
    }
    
    /// 安全获取嵌套JSON字符串并解析
    func parseNestedJSON(_ keyPath: String) -> JSON {
        let value = self[keyPath]
        
        // 如果已经是对象或数组类型，直接返回
        if value.type == .dictionary || value.type == .array {
            return value
        }
        
        // 如果是字符串类型，尝试解析为JSON
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
        
        // 解析失败返回空JSON对象
        return JSON()
    }
}

// MARK: - 示例模型实现
/*
// 示例：如何使用JSONParseable协议
struct User: JSONParseable {
    let id: Int
    let name: String
    let email: String?
    let isActive: Bool
    let profile: Profile?
    
    init?(json: JSON) {
        // 必填字段
        guard json["id"].type == .number else { return nil }
        
        self.id = json.int("id")
        self.name = json.string("name")
        self.email = json.optionalString("email") // 使用可选字符串方法
        self.isActive = json.bool("isActive")
        
        // 嵌套对象
        if json["profile"].exists() {
            self.profile = Profile(json: json["profile"])
        } else {
            self.profile = nil
        }
    }
}

struct Profile: JSONParseable {
    let bio: String
    let age: Int
    
    init?(json: JSON) {
        self.bio = json.string("bio")
        self.age = json.int("age")
    }
}

// 使用示例
let jsonString = """
{
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "isActive": true,
    "profile": {
        "bio": "Software Developer",
        "age": 30
    }
}
"""

if let data = jsonString.data(using: .utf8),
   let json = try? JSON(data: data),
   let user = json.toModel(User.self) {
    print("User: \(user.name), Email: \(user.email ?? "N/A")")
    if let profile = user.profile {
        print("Bio: \(profile.bio), Age: \(profile.age)")
    }
}
*/

