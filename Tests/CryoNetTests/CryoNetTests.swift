//
//  CryoNetTests.swift
//  CryoNetTests
//
//  Created by mac on 2024/6/10.
//

import XCTest
import CryoNet
import Alamofire
import SwiftyJSON

final class CryoNetTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - DefaultTokenManager Tests

    func testSetAndGetToken() async throws {
        let tokenManager = DefaultTokenManager()
        let initialToken = await tokenManager.getToken()
        XCTAssertNil(initialToken, "Initial token should be nil")

        let newToken = "test_token_123"
        await tokenManager.setToken(newToken)
        let fetchedToken = await tokenManager.getToken()
        XCTAssertEqual(fetchedToken, newToken, "Fetched token should match the set token")
    }

    func testRefreshTokenDefaultImplementation() async throws {
        let tokenManager = DefaultTokenManager()
        let refreshedToken = await tokenManager.refreshToken()
        XCTAssertNil(refreshedToken, "Default refreshToken implementation should return nil")
    }

    // MARK: - DefaultInterceptor Tests

    func testDefaultInterceptorDefaultInitialization() throws {
        let interceptor = DefaultInterceptor()
        let config = interceptor.getInterceptorConfig()
        XCTAssertEqual(config["codeKey"] as? String, "code")
        XCTAssertEqual(config["messageKey"] as? String, "msg")
        XCTAssertEqual(config["dataKey"] as? String, "data")
        XCTAssertEqual(config["successCode"] as? Int, 200)
        XCTAssertEqual(config["interceptorType"] as? String, "DefaultInterceptor")
    }

    func testDefaultInterceptorCustomInitialization() throws {
        let customConfig = DefaultResponseStructure(
            codeKey: "status",
            messageKey: "message",
            dataKey: "result",
            successCode: 1
        )
        let interceptor = DefaultInterceptor(responseConfig: customConfig)
        let config = interceptor.getInterceptorConfig()
        XCTAssertEqual(config["codeKey"] as? String, "status")
        XCTAssertEqual(config["messageKey"] as? String, "message")
        XCTAssertEqual(config["dataKey"] as? String, "result")
        XCTAssertEqual(config["successCode"] as? Int, 1)
        XCTAssertEqual(config["interceptorType"] as? String, "DefaultInterceptor")
    }

    func testDefaultInterceptorInterceptRequestWithToken() async throws {
        let tokenManager = DefaultTokenManager()
        await tokenManager.setToken("test_auth_token")
        let interceptor = DefaultInterceptor()
        var urlRequest = URLRequest(url: URL(string: "https://example.com")!)

        let modifiedRequest = await interceptor.interceptRequest(urlRequest, tokenManager: tokenManager)

        XCTAssertEqual(modifiedRequest.allHTTPHeaderFields?["Authorization"], "Bearer test_auth_token")
    }

    func testDefaultInterceptorInterceptRequestWithoutToken() async throws {
        let tokenManager = DefaultTokenManager()
        let interceptor = DefaultInterceptor()
        var urlRequest = URLRequest(url: URL(string: "https://example.com")!)

        let modifiedRequest = await interceptor.interceptRequest(urlRequest, tokenManager: tokenManager)

        XCTAssertNil(modifiedRequest.allHTTPHeaderFields?["Authorization"], "Authorization header should not be added if token is nil")
    }

    // MARK: - Mocking for Interceptor Response Tests

    // Helper function to create a mock AFDataResponse
    func createMockResponse(
        statusCode: Int,
        data: Data?,
        error: AFError? = nil,
        url: URL = URL(string: "https://example.com/api")!
    ) -> AFDataResponse<Data?> {
        let httpResponse = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        return AFDataResponse<Data?>(
            request: URLRequest(url: url),
            response: httpResponse,
            data: data,
            metrics: nil,
            serializationDuration: 0,
            result: error == nil ? .success(data) : .failure(error!)
        )
    }

    func testDefaultInterceptorInterceptResponseSuccess() throws {
        let interceptor = DefaultInterceptor()
        let jsonString = "{\"code\": 200, \"msg\": \"Success\", \"data\": {\"id\": 1, \"name\": \"Test\"}}"
        let mockData = jsonString.data(using: .utf8)
        let mockResponse = createMockResponse(statusCode: 200, data: mockData)

        let result = interceptor.interceptResponse(mockResponse)

        switch result {
        case .success(let data):
            let json = try JSON(data: data)
            XCTAssertEqual(json["id"].intValue, 1)
            XCTAssertEqual(json["name"].stringValue, "Test")
        case .failure(let error):
            XCTFail("Expected success, but got error: \(error)")
        }
    }

    func testDefaultInterceptorInterceptResponseSuccessNoData() throws {
        let interceptor = DefaultInterceptor()
        let jsonString = "{\"code\": 200, \"msg\": \"Success\"}"
        let mockData = jsonString.data(using: .utf8)
        let mockResponse = createMockResponse(statusCode: 200, data: mockData)

        let result = interceptor.interceptResponse(mockResponse)

        switch result {
        case .success(let data):
            // Should return original data if data key is missing or null
            let json = try JSON(data: data)
             XCTAssertEqual(json["code"].intValue, 200)
             XCTAssertEqual(json["msg"].stringValue, "Success")
             XCTAssertFalse(json["data"].exists())
        case .failure(let error):
            XCTFail("Expected success, but got error: \(error)")
        }
    }

    func testDefaultInterceptorInterceptResponseHTTPError() throws {
        let interceptor = DefaultInterceptor()
        let mockResponse = createMockResponse(statusCode: 404, data: nil)

        let result = interceptor.interceptResponse(mockResponse)

        switch result {
        case .success:
            XCTFail("Expected failure for HTTP 404, but got success")
        case .failure(let error as NSError):
            XCTAssertEqual(error.domain, "ClientError")
            XCTAssertEqual(error.code, 404)
            XCTAssertEqual(error.localizedDescription, "资源未找到")
        }
    }

    func testDefaultInterceptorInterceptResponseJSONParsingError() throws {
        let interceptor = DefaultInterceptor()
        let invalidJsonData = "invalid json".data(using: .utf8)
        let mockResponse = createMockResponse(statusCode: 200, data: invalidJsonData)

        let result = interceptor.interceptResponse(mockResponse)

        switch result {
        case .success:
            XCTFail("Expected failure for invalid JSON, but got success")
        case .failure(let error as NSError):
            XCTAssertEqual(error.domain, "DataError")
            XCTAssertEqual(error.code, 200)
            XCTAssertTrue(error.localizedDescription.contains("JSON解析失败"))
        }
    }

    func testDefaultInterceptorInterceptResponseBusinessError() throws {
        let interceptor = DefaultInterceptor()
        let jsonString = "{\"code\": 400, \"msg\": \"Bad Request\"}"
        let mockData = jsonString.data(using: .utf8)
        let mockResponse = createMockResponse(statusCode: 200, data: mockData)

        let result = interceptor.interceptResponse(mockResponse)

        switch result {
        case .success:
            XCTFail("Expected failure for business error code, but got success")
        case .failure(let error as NSError):
            XCTAssertEqual(error.domain, "BusinessError")
            XCTAssertEqual(error.code, 400)
            XCTAssertEqual(error.localizedDescription, "Bad Request")
        }
    }

    func testDefaultInterceptorInterceptResponseWithCompleteDataSuccess() throws {
        let interceptor = DefaultInterceptor()
        let jsonString = "{\"code\": 200, \"msg\": \"Success\", \"data\": {\"id\": 1, \"name\": \"Test\"}}"
        let mockData = jsonString.data(using: .utf8)
        let mockResponse = createMockResponse(statusCode: 200, data: mockData)

        let result = interceptor.interceptResponseWithCompleteData(mockResponse)

        switch result {
        case .success(let data):
            let json = try JSON(data: data)
            XCTAssertEqual(json["code"].intValue, 200)
            XCTAssertEqual(json["msg"].stringValue, "Success")
            XCTAssertEqual(json["data"]["id"].intValue, 1)
            XCTAssertEqual(json["data"]["name"].stringValue, "Test")
        case .failure(let error):
            XCTFail("Expected success, but got error: \(error)")
        }
    }

    func testDefaultInterceptorInterceptResponseWithCompleteDataBusinessError() throws {
        let interceptor = DefaultInterceptor()
        let jsonString = "{\"code\": 401, \"msg\": \"Unauthorized\"}"
        let mockData = jsonString.data(using: .utf8)
        let mockResponse = createMockResponse(statusCode: 200, data: mockData)

        let result = interceptor.interceptResponseWithCompleteData(mockResponse)

        switch result {
        case .success:
            XCTFail("Expected failure for business error code, but got success")
        case .failure(let error as NSError):
            XCTAssertEqual(error.domain, "BusinessError")
            XCTAssertEqual(error.code, 401)
            XCTAssertEqual(error.localizedDescription, "Unauthorized")
        }
    }

    // MARK: - CryoNet Integration Tests (Requires Mocking Network Requests)

    // Due to the limitations of the current environment and available tools for mocking network requests
    // in Swift XCTest within this sandbox, comprehensive integration tests for CryoNet's `request`
    // and `upload` methods with mocked network responses are challenging to implement directly.
    // These tests would typically involve using libraries like Mockingjay or OHHTTPStubs
    // to intercept and provide canned responses for Alamofire requests.

    // A basic example of how an integration test *could* be structured (conceptually):
    /*
    func testCryoNetRequestWithDefaultInterceptor() async throws {
        // This test would require setting up a mock server or using a network mocking library
        // to intercept the request made by CryoNet and return a predefined response.

        // 1. Set up mock response for a specific URL and method
        // e.g., stub(urlString("https://example.com/test"), json(["code": 200, "data": "success"]))

        // 2. Create a CryoNet instance with default configuration
        let cryoNet = CryoNet()

        // 3. Create a RequestModel
        let requestModel = RequestModel(url: "/test", method: .get)

        // 4. Make the request using CryoNet
        let result = await cryoNet.request(requestModel).responseData()

        // 5. Assert the result based on the mocked response and interceptor logic
        switch result {
        case .success(let data):
            let json = try JSON(data: data)
            XCTAssertEqual(json.stringValue, "success")
        case .failure(let error):
            XCTFail("Expected success, but got error: \(error)")
        }
    }

    func testCryoNetRequestWithCustomTokenManager() async throws {
        // Similar to the above, but with a custom TokenManagerProtocol implementation
        // that provides a specific token, and verify the Authorization header in the mocked request.
    }

    func testCryoNetRequestWithCustomInterceptor() async throws {
        // Similar to the above, but with a custom RequestInterceptorProtocol implementation
        // that modifies the request or response in a specific way, and verify the behavior.
    }
    */

    // Placeholder tests to indicate where integration tests would go
    func testCryoNetRequestIntegrationPlaceholder() {
        XCTFail("Integration tests for CryoNet.request require network mocking setup not available in this environment.")
    }

    func testCryoNetUploadIntegrationPlaceholder() {
         XCTFail("Integration tests for CryoNet.upload require network mocking setup not available in this environment.")
    }

    func testCryoNetDownloadIntegrationPlaceholder() {
         XCTFail("Integration tests for CryoNet.downloadFile require network mocking setup not available in this environment.")
    }
}


