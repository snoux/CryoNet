import Foundation
import SwiftyJSON

// MARK: - 响应结构配置协议

/// `ResponseStructureConfig` 响应结构配置协议。
///
/// 用户可通过闭包或自定义类型，声明响应是否成功、如何提取业务数据、失败时如何提取失败原因。
///
/// - Note:
///   - 在 `DefaultInterceptor` 中，网络层错误（AFError/URLError）与 HTTP 非 2xx 会先返回失败，
///     仅在 HTTP 2xx 且可解析 JSON 时，才会进入 `isSuccess` / `extractData` / `extractFailureReason`。
public protocol ResponseStructureConfig: Sendable {
    /// 判断响应是否成功
    ///
    /// - Note:
    ///   - 仅用于业务层成功判断，不负责网络层成功判断。
    func isSuccess(json: JSON) -> Bool

    /// 从 JSON 提取数据并转换为 Data（可重写）
    func extractData(from json: JSON, originalData: Data) -> Result<Data, Error>

    /// 失败时从响应中提取错误原因（可选）
    ///
    /// - Note:
    ///   - 仅在 `isSuccess(json:) == false` 的业务失败场景调用。
    func extractFailureReason(from json: JSON, originalData: Data) -> String?
}

// MARK: - 协议扩展：提供默认实现
public extension ResponseStructureConfig {
    /// 默认实现：业务层默认成功（网络层成功由 `DefaultInterceptor` 先行判断）
    func isSuccess(json: JSON) -> Bool {
        true
    }

    /// 默认实现：直接返回完整原始数据
    func extractData(from json: JSON, originalData: Data) -> Result<Data, Error> {
        .success(originalData)
    }

    /// 默认实现：自动提取常见失败字段，提取失败返回 nil（由上层使用兜底文案）
    func extractFailureReason(from json: JSON, originalData: Data) -> String? {
        let commonKeys = ["message", "msg", "error", "reason", "detail"]
        for key in commonKeys {
            let value = json[key]
            if let text = value.string, !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
