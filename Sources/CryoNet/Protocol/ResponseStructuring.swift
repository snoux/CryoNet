import Foundation
import SwiftyJSON

// MARK: - 响应结构配置协议

/// `ResponseStructureConfig` 响应结构配置协议，定义如何从响应中解析通用结构体（如 code/msg/data）。
///
/// 适用于自定义业务结构解析（如 code/msg/data、status/message/result 等）
///
/// ### 使用示例
/// ```swift
/// struct MyResponseConfig: ResponseStructureConfig {
///     var codeKey = "status"
///     var messageKey = "msg"
///     var dataKey = "result"
///     var successCode = 0
///     func isSuccess(json: JSON) -> Bool { json[codeKey].intValue == successCode }
///     func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> { ... }
/// }
/// ```
public protocol ResponseStructureConfig: Sendable {
    /// 状态码字段的key
    var codeKey: String { get }
    /// 消息字段的key
    var messageKey: String { get }
    /// 数据字段的key
    var dataKey: String { get }
    /// 成功状态码
    var successCode: Int { get }
    
    /// 判断响应是否成功
    func isSuccess(json: JSON) -> Bool
    
    /// 从JSON中提取数据
    func extractJSON(from json: JSON) -> JSON
    
    /// 从 JSON 提取数据并转换为 Data（可重写）
    /// - Parameters:
    ///   - json: 原始 JSON 对象
    ///   - originalData: 原始响应数据
    /// - Returns: 提取的数据或错误
    func extractData(from json: JSON, originalData: Data) -> Result<Data, Error>
}

// MARK: - 协议扩展：提供默认实现
public extension ResponseStructureConfig {
    /// 默认实现：使用 extractJSON 提取 JSON，然后转换为 Data
    func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        return JSON.extractDataFromJSON(extractJSON(from: json), originalData: originalData)
    }
}
