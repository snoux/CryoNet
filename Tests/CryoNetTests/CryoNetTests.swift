//import XCTest
//@testable import CryoNet
//import Alamofire
//
//final class CryoNetTests: XCTestCase {
//    
//    private var cryoNet: CryoNet!
//    private let testURL = "https://example.com/api"
//    
//    override func setUp() {
//        super.setUp()
//        let config = CryoNetConfiguration(
//            basicURL: "https://api.example.com/",
//            tokenManager: TestTokenManager()
//        )
//        cryoNet = CryoNet(configuration: config)
//    }
//    
//    func testTokenManagerConcurrency() async {
//        let tokenManager = DefaultTokenManager()
//        
//        // 测试并发设置token
//        async let setToken1: () = tokenManager.setToken("token1")
//        async let setToken2: () = tokenManager.setToken("token2")
//        async let setToken3: () = tokenManager.setToken("token3")
//        _ = await [setToken1, setToken2, setToken3]
//        
//        // 验证token值
//        let token = await tokenManager.getToken()
//        XCTAssertNotNil(token)
//        XCTAssertEqual(token, "token3")
//        
//        // 测试刷新token
//        let refreshedToken = await tokenManager.refreshToken()
//        print("token --- \(await tokenManager.getToken())")
//        XCTAssertNil(refreshedToken) // 默认实现返回nil
//    }
//    
//    func testConfigurationThreadSafety() async {
//        let initialConfig = await cryoNet.getConfiguration()
//        XCTAssertEqual(initialConfig.basicURL, "https://api.example.com/")
//        
//        // 并发更新配置
//        let group = DispatchGroup()
//        for i in 0..<100 {
//            group.enter()
//            DispatchQueue.global().async {
//                self.cryoNet.updateConfiguration { config in
//                    config.defaultTimeout = TimeInterval(i)
//                }
//                group.leave()
//            }
//        }
//        group.wait()
//        
//        // 验证配置一致性
//        let finalConfig = await cryoNet.getConfiguration()
//        XCTAssertNotEqual(finalConfig.defaultTimeout, initialConfig.defaultTimeout)
//    }
//    
//    func testRequestWithToken() async throws {
//        // 设置token
//        let tokenManager = TestTokenManager()
//        await tokenManager.setToken("test_token")
//        
//        let config = CryoNetConfiguration(
//            tokenManager: tokenManager,
//            interceptor: TestInterceptor()
//        )
//        await cryoNet.setConfiguration(config)
//        
//        // 创建请求
//        let model = RequestModel(url: "user/profile", method: .get)
//        let result = await cryoNet.request(model)
//        
//        // 异步获取响应
//        do {
//            let data = try await result.responseDataAsync()
//            XCTAssertFalse(data.isEmpty)
//        } catch {
//            XCTFail("Request failed: \(error)")
//        }
//    }
//}
//
//// MARK: - Test Helpers
//
//private actor TestTokenManager: TokenManagerProtocol {
//    private var token: String?
//    
//    func getToken() async -> String? {
//        token
//    }
//    
//    func setToken(_ newToken: String) async {
//        token = newToken
//    }
//    
//    func refreshToken() async -> String? {
//        "refreshed_token"
//    }
//}
//
//private class TestInterceptor: RequestInterceptorProtocol {
//    func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
//        
////        if await (tokenManager.getToken() != nil){
////            
////        }
//        var modifiedRequest = urlRequest
//
//        if let token = await tokenManager.getToken() {
//            if var headers = modifiedRequest.allHTTPHeaderFields {
//                headers["Authorization"] = "Bearer \(token)"
//                modifiedRequest.allHTTPHeaderFields = headers
//            } else {
//                modifiedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
//            }
//        }
//        return modifiedRequest
//    }
//    
//    func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
//        .success(Data("{\"success\": true}".utf8))
//    }
//    
//    func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
//        .success(Data("{\"complete\": true}".utf8))
//    }
//}
