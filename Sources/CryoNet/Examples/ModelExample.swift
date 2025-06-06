import Foundation
import SwiftyJSON

// MARK: - 示例模型
struct User: JSONParseable {
    let id: Int
    let name: String
    let email: String?
    let isActive: Bool
    let profile: Profile?
    let tags: [String]
    
    // 从JSON初始化
    init?(json: JSON) {
        // 必填字段，如果id不存在则初始化失败
        guard json["id"].exists() else { return nil }
        
        // 使用扩展方法获取值，支持默认值
        self.id = json.int("id")
        self.name = json.string("name")
        self.email = json.optionalString("email")
        self.isActive = json.bool("isActive")
        
        // 处理嵌套对象
        self.profile = json["profile"].exists() ? Profile(json: json["profile"]) : nil
        
        // 处理数组
        self.tags = json["tags"].arrayValue.map { $0.stringValue }
    }
}

struct Profile: JSONParseable {
    let bio: String
    let age: Int
    let address: Address?
    
    init?(json: JSON) {
        self.bio = json.string("bio")
        self.age = json.int("age")
        
        // 处理嵌套对象
        self.address = json["address"].exists() ? Address(json: json["address"]) : nil
    }
}

struct Address: JSONParseable {
    let street: String
    let city: String
    let country: String
    
    init?(json: JSON) {
        self.street = json.string("street")
        self.city = json.string("city")
        self.country = json.string("country")
    }
}

// MARK: - 使用示例
/*
// 示例JSON字符串
let jsonString = """
{
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "isActive": true,
    "profile": {
        "bio": "Software Developer",
        "age": 30,
        "address": {
            "street": "123 Main St",
            "city": "New York",
            "country": "USA"
        }
    },
    "tags": ["swift", "ios", "developer"]
}
"""

// 解析JSON
if let data = jsonString.data(using: .utf8),
   let json = try? JSON(data: data) {
    
    // 方法1：使用JSONParseable协议
    if let user = json.toModel(User.self) {
        print("User: \(user.name), Email: \(user.email ?? "N/A")")
        if let profile = user.profile {
            print("Bio: \(profile.bio), Age: \(profile.age)")
            if let address = profile.address {
                print("Location: \(address.city), \(address.country)")
            }
        }
        print("Tags: \(user.tags.joined(separator: ", "))")
    }
    
    // 方法2：使用自定义解析闭包
    if let user = json.toModel(parser: { json in
        guard json["id"].exists() else { return nil }
        
        return User(json: json)
    }) {
        print("User parsed with custom parser: \(user.name)")
    }
    
    // 方法3：处理嵌套JSON字符串
    let nestedJsonString = """
    {
        "data": "{\\\"user\\\":{\\\"id\\\":2,\\\"name\\\":\\\"Jane Doe\\\"}}"
    }
    """
    
    if let nestedData = nestedJsonString.data(using: .utf8),
       let nestedJson = try? JSON(data: nestedData) {
        
        // 解析嵌套的JSON字符串
        let userJson = nestedJson.parseNestedJSON("data")["user"]
        if let nestedUser = userJson.toModel(User.self) {
            print("Nested user: \(nestedUser.name)")
        }
    }
}

// 在CryoNet中使用
let request = CryoNet.sharedInstance("https://api.example.com")
let model = RequestModel(url: "/users/1", method: .get)

// 使用JSONParseable协议
request.request(model)
    .responseJSONModel(type: User.self) { user in
        print("User: \(user.name)")
    } failed: { error in
        print("Error: \(error.localizedDescription)")
    }

// 使用自定义解析闭包
request.request(model)
    .responseJSONModel(parser: { json in
        return User(json: json)
    }) { user in
        print("User: \(user.name)")
    } failed: { error in
        print("Error: \(error.localizedDescription)")
    }

// 使用async/await
Task {
    do {
        let user = try await request.request(model).responseJSONModelAsync(User.self)
        print("User: \(user.name)")
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}
*/

