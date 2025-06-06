import Foundation
import Alamofire

/// 全局变量
public class GlobalManager {
    
    /// 设置全局的 Basic_Header
    /// Basic_Header 会默认使用
    /// 发送请求时传入的 Header 会与其合并在一起发送请求
    public static var Basic_Headers:[HTTPHeader] = [HTTPHeader(name: "Content-Type", value: "application/json")]
    
    /// 配置 Basic_URL
    /// **发送请求前配置 或者 初始化 CryoNet 时传入**
    public static var Basic_URL:String = ""
}

