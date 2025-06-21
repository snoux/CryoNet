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
    func extractData(from json: JSON, originalData: Data) -> Result<Data, Error>
}
