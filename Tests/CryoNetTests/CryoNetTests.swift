import XCTest
@testable import CryoNet
import Alamofire

final class CryoNetTests: XCTestCase {
    
    // MARK: - 测试配置
    
    override func setUp() {
        super.setUp()
        // 每个测试前重置状态
    }
    
    override func tearDown() {
        super.tearDown()
        // 清理工作
    }
    
    // MARK: - 闭包配置初始化测试
    func testClosureInitialization() {
        // 使用闭包配置初始化
        let cryoNet = CryoNet { config in
            config.basicURL = "https://api.example.com"
            config.defaultTimeout = 45
            config.basicHeaders.append(HTTPHeader(name: "X-Custom", value: "Value"))
            config.tokenManager = MockTokenManager(token: "test-token")
        }
        
        // 验证配置
        XCTAssertEqual(cryoNet.configuration.basicURL, "https://api.example.com")
        XCTAssertEqual(cryoNet.configuration.defaultTimeout, 45)
        XCTAssertEqual(cryoNet.configuration.basicHeaders.count, 2)
        XCTAssertEqual(cryoNet.configuration.basicHeaders[1].name, "X-Custom")
        XCTAssertEqual(cryoNet.configuration.basicHeaders[1].value, "Value")
        XCTAssertTrue(cryoNet.configuration.tokenManager is MockTokenManager)
        XCTAssertEqual((cryoNet.configuration.tokenManager as? MockTokenManager)?.getToken(), "test-token")
    }
    
    func testClosureInitializationWithDefaultValues() {
        // 使用闭包配置初始化，但只修改部分值
        let cryoNet = CryoNet { config in
            config.basicURL = "https://api.custom.com"
        }
        
        // 验证配置
        XCTAssertEqual(cryoNet.configuration.basicURL, "https://api.custom.com")
        XCTAssertEqual(cryoNet.configuration.defaultTimeout, 30) // 保持默认值
        XCTAssertEqual(cryoNet.configuration.basicHeaders.count, 1) // 默认头
        XCTAssertTrue(cryoNet.configuration.tokenManager is DefaultTokenManager) // 默认Token管理器
    }
    
    func testClosureInitializationWithComplexConfiguration() {
        // 创建复杂的闭包配置
        let cryoNet = CryoNet { config in
            config.basicURL = "https://api.complex.com/v2"
            config.defaultTimeout = 60
            config.maxConcurrentDownloads = 10
            config.basicHeaders = [
                HTTPHeader(name: "Authorization", value: "Basic token"),
                HTTPHeader(name: "Accept", value: "application/json")
            ]
            config.tokenManager = MockTokenManager(token: "complex-token")
            config.interceptor = MockInterceptor()
        }
        
        // 验证配置
        XCTAssertEqual(cryoNet.configuration.basicURL, "https://api.complex.com/v2")
        XCTAssertEqual(cryoNet.configuration.defaultTimeout, 60)
        XCTAssertEqual(cryoNet.configuration.maxConcurrentDownloads, 10)
        XCTAssertEqual(cryoNet.configuration.basicHeaders.count, 2)
        XCTAssertEqual(cryoNet.configuration.basicHeaders[0].name, "Authorization")
        XCTAssertEqual(cryoNet.configuration.basicHeaders[0].value, "Basic token")
        XCTAssertEqual(cryoNet.configuration.basicHeaders[1].name, "Accept")
        XCTAssertEqual(cryoNet.configuration.basicHeaders[1].value, "application/json")
        XCTAssertTrue(cryoNet.configuration.tokenManager is MockTokenManager)
        XCTAssertEqual((cryoNet.configuration.tokenManager as? MockTokenManager)?.getToken(), "complex-token")
        XCTAssertTrue(cryoNet.configuration.interceptor is MockInterceptor)
    }
    
    // MARK: - 闭包配置与更新配置组合测试
    func testClosureInitializationAndUpdateCombination() {
        // 初始闭包配置
        let cryoNet = CryoNet { config in
            config.basicURL = "https://initial.com"
            config.defaultTimeout = 40
        }
        
        // 初始验证
        XCTAssertEqual(cryoNet.configuration.basicURL, "https://initial.com")
        XCTAssertEqual(cryoNet.configuration.defaultTimeout, 40)
        
        // 更新配置
        cryoNet.updateConfiguration { config in
            config.basicURL = "https://updated.com"
            config.defaultTimeout = 60
            config.basicHeaders.append(HTTPHeader(name: "X-Update", value: "Updated"))
        }
        
        // 更新后验证
        XCTAssertEqual(cryoNet.configuration.basicURL, "https://updated.com")
        XCTAssertEqual(cryoNet.configuration.defaultTimeout, 60)
        XCTAssertEqual(cryoNet.configuration.basicHeaders.count, 2)
        XCTAssertEqual(cryoNet.configuration.basicHeaders[1].name, "X-Update")
        XCTAssertEqual(cryoNet.configuration.basicHeaders[1].value, "Updated")
    }
    
    func testMultipleClosureConfigurations() {
        // 创建多个实例，每个实例有自己的闭包配置
        let client1 = CryoNet { config in
            config.basicURL = "https://service1.com"
            config.tokenManager = MockTokenManager(token: "token1")
        }
        
        let client2 = CryoNet { config in
            config.basicURL = "https://service2.com"
            config.tokenManager = MockTokenManager(token: "token2")
        }
        
        // 验证实例独立
        XCTAssertEqual(client1.configuration.basicURL, "https://service1.com")
        XCTAssertEqual((client1.configuration.tokenManager as? MockTokenManager)?.getToken(), "token1")
        
        XCTAssertEqual(client2.configuration.basicURL, "https://service2.com")
        XCTAssertEqual((client2.configuration.tokenManager as? MockTokenManager)?.getToken(), "token2")
        
        // 更新第一个实例的配置
        client1.updateConfiguration { config in
            config.basicURL = "https://service1-updated.com"
        }
        
        // 验证修改后第一个实例变化，第二个实例不变
        XCTAssertEqual(client1.configuration.basicURL, "https://service1-updated.com")
        XCTAssertEqual(client2.configuration.basicURL, "https://service2.com")
    }
    
    // MARK: - 辅助类型
    
    class MockTokenManager: TokenManagerProtocol {
        private var token: String?
        
        init(token: String? = nil) {
            self.token = token
        }
        
        func getToken() -> String? {
            return token
        }
        
        func setToken(_ newToken: String) {
            token = newToken
        }
        
        func refreshToken() -> String? {
            return "refreshed-token"
        }
    }
    
    class MockInterceptor: RequestInterceptorProtocol, InterceptorConfigProvider {
        func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
            return urlRequest
        }
        
        func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
            return .success(Data())
        }
        
        func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
            return .success(Data())
        }
        
        func getInterceptorConfig() -> [String: Any] {
            return ["type": "MockInterceptor"]
        }
    }
    
    // MARK: - 基础功能测试
    func testInitializationWithDefaultConfiguration() {
        let cryoNet = CryoNet()
        let config = cryoNet.configuration
        
        XCTAssertEqual(config.basicURL, "")
        XCTAssertEqual(config.basicHeaders.count, 1)
        XCTAssertEqual(config.basicHeaders.first?.name, "Content-Type")
        XCTAssertEqual(config.basicHeaders.first?.value, "application/json")
        XCTAssertEqual(config.defaultTimeout, 30)
        XCTAssertEqual(config.maxConcurrentDownloads, 6)
        XCTAssertTrue(config.tokenManager is DefaultTokenManager)
        XCTAssertTrue(config.interceptor is DefaultInterceptor)
    }
    
    func testInitializationWithCustomConfiguration() {
        let tokenManager = MockTokenManager()
        let interceptor = MockInterceptor()
        
        let customConfig = CryoNetConfiguration(
            basicURL: "https://api.example.com",
            basicHeaders: [HTTPHeader(name: "X-Custom", value: "Value")],
            defaultTimeout: 60,
            maxConcurrentDownloads: 10,
            tokenManager: tokenManager,
            interceptor: interceptor
        )
        
        let cryoNet = CryoNet(configuration: customConfig)
        let config = cryoNet.configuration
        
        XCTAssertEqual(config.basicURL, "https://api.example.com")
        XCTAssertEqual(config.basicHeaders.count, 1)
        XCTAssertEqual(config.basicHeaders.first?.name, "X-Custom")
        XCTAssertEqual(config.basicHeaders.first?.value, "Value")
        XCTAssertEqual(config.defaultTimeout, 60)
        XCTAssertEqual(config.maxConcurrentDownloads, 10)
        XCTAssertTrue(config.tokenManager is MockTokenManager)
        XCTAssertTrue(config.interceptor is MockInterceptor)
    }
    
    // MARK: - 多实例测试
    
    func testMultipleInstancesIndependentConfigurations() {
        // 创建第一个实例
        let config1 = CryoNetConfiguration(
            basicURL: "https://api.service1.com",
            tokenManager: MockTokenManager(token: "token1")
        )
        let client1 = CryoNet(configuration: config1)
        
        // 创建第二个实例
        let config2 = CryoNetConfiguration(
            basicURL: "https://api.service2.com",
            tokenManager: MockTokenManager(token: "token2")
        )
        let client2 = CryoNet(configuration: config2)
        
        // 验证实例独立
        XCTAssertEqual(client1.configuration.basicURL, "https://api.service1.com")
        XCTAssertEqual((client1.configuration.tokenManager as? MockTokenManager)?.getToken(), "token1")
        
        XCTAssertEqual(client2.configuration.basicURL, "https://api.service2.com")
        XCTAssertEqual((client2.configuration.tokenManager as? MockTokenManager)?.getToken(), "token2")
        
        // 修改第一个实例的配置
        client1.updateConfiguration { config in
            config.basicURL = "https://api.service1-updated.com"
            (config.tokenManager as? MockTokenManager)?.setToken("new-token1")
        }
        
        // 验证修改后第一个实例变化，第二个实例不变
        XCTAssertEqual(client1.configuration.basicURL, "https://api.service1-updated.com")
        XCTAssertEqual((client1.configuration.tokenManager as? MockTokenManager)?.getToken(), "new-token1")
        
        XCTAssertEqual(client2.configuration.basicURL, "https://api.service2.com")
        XCTAssertEqual((client2.configuration.tokenManager as? MockTokenManager)?.getToken(), "token2")
    }
    
    // MARK: - 线程安全测试
    
    func testThreadSafetyForConfigurationUpdates() {
        let cryoNet = CryoNet()
        let expectation = self.expectation(description: "Concurrent configuration updates")
        expectation.expectedFulfillmentCount = 5
        
        // 并发队列执行配置更新
        let queue = DispatchQueue(label: "test.concurrent.queue", attributes: .concurrent)
        for i in 0..<5 {
            queue.async {
                cryoNet.updateConfiguration { config in
                    // 模拟耗时操作
                    Thread.sleep(forTimeInterval: 0.01)
                    config.defaultTimeout += Double(i)
                }
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5) { error in
            if let error = error {
                XCTFail("等待超时: \(error)")
            }
            
            // 验证配置最终状态
            let timeout = cryoNet.configuration.defaultTimeout
            XCTAssertGreaterThan(timeout, 30.0, "配置更新未正确应用")
        }
    }
    
    // MARK: - 配置管理测试
    
    func testSetConfiguration() {
        let cryoNet = CryoNet()
        
        let newConfig = CryoNetConfiguration(
            basicURL: "https://api.new.com",
            defaultTimeout: 45
        )
        
        cryoNet.setConfiguration(newConfig)
        
        XCTAssertEqual(cryoNet.configuration.basicURL, "https://api.new.com")
        XCTAssertEqual(cryoNet.configuration.defaultTimeout, 45)
    }
    
    func testUpdateConfiguration() {
        let cryoNet = CryoNet()
        
        cryoNet.updateConfiguration { config in
            config.basicURL = "https://api.updated.com"
            config.defaultTimeout = 60
            config.basicHeaders.append(HTTPHeader(name: "X-Test", value: "Value"))
        }
        
        XCTAssertEqual(cryoNet.configuration.basicURL, "https://api.updated.com")
        XCTAssertEqual(cryoNet.configuration.defaultTimeout, 60)
        XCTAssertEqual(cryoNet.configuration.basicHeaders.count, 2)
        XCTAssertEqual(cryoNet.configuration.basicHeaders[1].name, "X-Test")
        XCTAssertEqual(cryoNet.configuration.basicHeaders[1].value, "Value")
    }
    
    // MARK: - 请求模型测试
    
    func testRequestModelURLConstruction() {
        let client = CryoNet(configuration: CryoNetConfiguration(basicURL: "https://api.example.com"))
        
        // 测试拼接基础URL
        let model1 = RequestModel(url: "/users", applyBasicURL: true)
        XCTAssertEqual(model1.fullURL(with: client.configuration.basicURL), "https://api.example.com/users")
        
        // 测试不拼接基础URL
        let model2 = RequestModel(url: "https://api.other.com/data", applyBasicURL: false)
        XCTAssertEqual(model2.fullURL(with: client.configuration.basicURL), "https://api.other.com/data")
        
        // 测试超时时间
        let model3 = RequestModel(url: "/posts", overtime: 15)
        XCTAssertEqual(model3.overtime, 15)
    }
    
    // MARK: - 请求方法测试
    
    func testRequestMethodCreatesCorrectURLRequest() {
        // 设置模拟客户端
        let mockTokenManager = MockTokenManager(token: "test-token")
        let mockInterceptor = MockInterceptor()
        
        let config = CryoNetConfiguration(
            basicURL: "https://api.example.com",
            tokenManager: mockTokenManager,
            interceptor: mockInterceptor
        )
        
        let client = CryoNet(configuration: config)
        
        // 创建请求模型
        let model = RequestModel(
            url: "/users",
            method: .get,
            encoding: .jsonDefault,
            overtime: 10
        )
        
        // 创建请求
        let result = client.request(model)
        let request = result.request.request
        
        // 验证请求属性
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.url?.absoluteString, "https://api.example.com/users")
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.timeoutInterval, 10)
    }
    
    // MARK: - 拦截器测试
    
    func testInterceptorIntegration() {
        // 设置模拟客户端
        let mockTokenManager = MockTokenManager(token: "test-token")
        let mockInterceptor = MockInterceptor()
        
        let config = CryoNetConfiguration(
            tokenManager: mockTokenManager,
            interceptor: mockInterceptor
        )
        
        let client = CryoNet(configuration: config)
        
        // 创建请求模型
        let model = RequestModel(url: "/test")
        
        // 创建请求
        let result = client.request(model)
        let request = result.request.request
        
        // 验证拦截器是否被调用
        XCTAssertTrue(mockInterceptor.interceptRequestCalled)
        XCTAssertEqual(mockInterceptor.lastRequest?.url, request?.url)
    }
    
    func testTokenManagerIntegration() {
        // 设置模拟客户端
        let mockTokenManager = MockTokenManager(token: "test-token")
        let mockInterceptor = MockInterceptor()
        
        let config = CryoNetConfiguration(
            tokenManager: mockTokenManager,
            interceptor: mockInterceptor
        )
        
        let client = CryoNet(configuration: config)
        
        // 创建请求模型
        let model = RequestModel(url: "/secure")
        
        // 创建请求
        let result = client.request(model)
        let request = result.request.request
        
        // 验证Token是否添加到请求头
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }
    
    // MARK: - 配置验证测试
    
    func testInterceptorValidation() {
        let client = CryoNet()
        
        // 使用默认拦截器
        var validation = client.validateInterceptorConfiguration()
        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.message, "当前使用默认拦截器，可能配置未生效")
        
        // 使用自定义拦截器
        client.updateConfiguration { config in
            config.interceptor = MockInterceptor()
        }
        
        validation = client.validateInterceptorConfiguration()
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.message, "当前使用自定义拦截器: MockInterceptor")
    }
    
    // MARK: - 并发下载测试
    
    func testDownloadConcurrencySetting() {
        let client = CryoNet(configuration: CryoNetConfiguration(maxConcurrentDownloads: 4))
        XCTAssertEqual(client.configuration.maxConcurrentDownloads, 4)
        
        client.updateConfiguration { config in
            config.maxConcurrentDownloads = 8
        }
        XCTAssertEqual(client.configuration.maxConcurrentDownloads, 8)
    }
    
    // MARK: - 辅助类型
    
    class MockTokenManager: TokenManagerProtocol {
        private var token: String?
        
        init(token: String? = nil) {
            self.token = token
        }
        
        func getToken() -> String? {
            return token
        }
        
        func setToken(_ newToken: String) {
            token = newToken
        }
        
        func refreshToken() -> String? {
            return "refreshed-token"
        }
    }
    
    class MockInterceptor: RequestInterceptorProtocol, InterceptorConfigProvider {
        var interceptRequestCalled = false
        var lastRequest: URLRequest?
        
        func interceptRequest(_ urlRequest: URLRequest, tokenManager: TokenManagerProtocol) async -> URLRequest {
            interceptRequestCalled = true
            lastRequest = urlRequest
            
            var modifiedRequest = urlRequest
            if let token = tokenManager.getToken() {
                modifiedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return modifiedRequest
        }
        
        func interceptResponse(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
            return .success(Data())
        }
        
        func interceptResponseWithCompleteData(_ response: AFDataResponse<Data?>) -> Result<Data, Error> {
            return .success(Data())
        }
        
        func getInterceptorConfig() -> [String: Any] {
            return ["type": "MockInterceptor"]
        }
    }
    
}
