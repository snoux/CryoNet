import XCTest
import Alamofire
@testable import CryoNet

/// 测试用拦截器，记录统一全局失败入口收到的内容。
private final class FailureObservingInterceptor: DefaultInterceptor, @unchecked Sendable {
    private(set) var receivedFailure: CryoFailure?
    private(set) var receivedRequest: URLRequest?

    override func handleFailure(_ failure: CryoFailure, request: URLRequest?) {
        receivedFailure = failure
        receivedRequest = request
    }
}

@available(iOS 13, macOS 10.15, *)
final class CryoNetTests: XCTestCase {

    func testRequestModelDefaultOvertimeIsZero() {
        let model = RequestModel(path: "/ping")
        XCTAssertEqual(model.overtime, 0)
        XCTAssertEqual(model.method, HTTPMethod.post)
    }

    func testDefaultTokenManagerCanClearToken() async {
        let tokenManager = DefaultTokenManager(token: "token")

        await tokenManager.clearToken()
        let token = await tokenManager.getToken()

        XCTAssertNil(token)
    }

    func testDefaultInterceptorDoesNotInjectEmptyToken() async {
        let interceptor = DefaultInterceptor()
        let tokenManager = DefaultTokenManager(token: "")
        let url = URL(string: "https://example.com")!

        let request = await interceptor.interceptRequest(
            URLRequest(url: url),
            tokenManager: tokenManager
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testDownloadPauseDoesNotChangeIdleTaskState() async {
        let manager = DownloadManager()
        let id = await manager.addTask(pathOrURL: "https://example.com/file.txt")

        await manager.pauseTask(id: id)
        let task = await manager.getTaskInfo(id: id)

        XCTAssertEqual(task?.state, .idle)
    }

    func testInvalidDownloadURLDoesNotCrashAndMarksFailed() async {
        let manager = DownloadManager()
        let id = await manager.addTask(pathOrURL: "")
        let task = await manager.getTaskInfo(id: id)

        XCTAssertEqual(task?.state, .failed)
    }

    func testDefaultInterceptorReturnsHTTPErrorForNon2xxResponse() throws {
        let interceptor = DefaultInterceptor()
        let body = Data(#"{"message":"not found"}"#.utf8)
        let response = try makeResponse(statusCode: 404, data: body)

        let result = interceptor.interceptResponse(response)

        guard case .failure(let error) = result else {
            return XCTFail("Expected a failed HTTP response")
        }
        let nsError = error as NSError
        XCTAssertEqual(nsError.domain, "ClientError")
        XCTAssertEqual(nsError.code, 404)
        XCTAssertEqual(nsError.localizedDescription, "资源未找到")
        XCTAssertEqual(nsError.userInfo["statusCode"] as? Int, 404)
        XCTAssertEqual(nsError.userInfo["responseData"] as? Data, body)
        XCTAssertNotNil(nsError.userInfo[NSUnderlyingErrorKey] as? AFError)

        let failure = CryoFailure.wrapping(
            error,
            response: response.response,
            responseData: body
        )
        XCTAssertEqual(failure.kind, .http)
        XCTAssertEqual(failure.statusCode, 404)
        XCTAssertEqual(failure.responseData, body)
    }

    func testDefaultInterceptorContinuesNormalFlowFor2xxResponse() throws {
        let interceptor = DefaultInterceptor()
        let body = Data(#"{"message":"ok"}"#.utf8)
        let response = try makeResponse(statusCode: 200, data: body, validationError: false)

        let result = interceptor.interceptResponse(response)

        guard case .success(let data) = result else {
            return XCTFail("Expected a successful HTTP response")
        }
        XCTAssertEqual(data, body)
    }

    func testGlobalFailureHandlerRunsBeforeLocalFailureCallback() throws {
        let interceptor = FailureObservingInterceptor()
        let session = Session(startRequestsImmediately: false)
        let url = try XCTUnwrap(URL(string: "https://example.com/test"))
        let result = CryoResult(
            request: session.request(url),
            interceptor: interceptor
        )
        let failure = CryoFailure(
            kind: .authenticationExpired,
            message: "登录已失效",
            statusCode: 401
        )
        var localCallbackObservedGlobalHandler = false

        result.emitFailure(failure, request: URLRequest(url: url)) { localFailure in
            localCallbackObservedGlobalHandler = interceptor.receivedFailure?.kind == localFailure.kind
        }

        XCTAssertEqual(interceptor.receivedFailure?.kind, .authenticationExpired)
        XCTAssertEqual(interceptor.receivedRequest?.url, url)
        XCTAssertTrue(localCallbackObservedGlobalHandler)
    }

    func testConvenienceInitializerInvokesFailureHandler() {
        let expectation = expectation(description: "便捷初始化的全局失败闭包已执行")
        let interceptor = DefaultInterceptor(handleFailure: { failure, request in
            XCTAssertEqual(failure.kind, .http)
            XCTAssertEqual(failure.statusCode, 503)
            XCTAssertEqual(request?.url?.absoluteString, "https://example.com/news")
            expectation.fulfill()
        })
        let failure = CryoFailure(
            kind: .http,
            message: "服务不可用",
            statusCode: 503
        )
        let request = URLRequest(url: URL(string: "https://example.com/news")!)

        interceptor.handleFailure(failure, request: request)

        wait(for: [expectation], timeout: 1)
    }

    func testBusinessFailureExtractsBusinessCode() throws {
        let interceptor = DefaultInterceptor(
            isSuccess: { _ in false },
            extractFailureReason: { json, _ in json["message"].string },
            extractBusinessCode: { json, _ in json["code"].int }
        )
        let body = Data(#"{"code":10001,"message":"login expired"}"#.utf8)
        let response = try makeResponse(statusCode: 200, data: body, validationError: false)

        guard case .failure(let error) = interceptor.interceptResponse(response) else {
            return XCTFail("Expected a failed business response")
        }
        let failure = CryoFailure.wrapping(
            error,
            response: response.response,
            responseData: body
        )

        XCTAssertEqual(failure.kind, .business)
        XCTAssertEqual(failure.statusCode, 200)
        XCTAssertEqual(failure.businessCode, 10001)
        XCTAssertEqual(failure.message, "login expired")
    }

    func testAuthenticationSessionAllowsOnlyOneConcurrentLogout() async {
        let revision = UUID()
        let manager = DefaultAuthenticationSessionManager(
            initialState: .authenticated,
            initialRevision: revision
        )

        async let first = manager.beginLogoutIfCurrent(expectedRevision: revision)
        async let second = manager.beginLogoutIfCurrent(expectedRevision: revision)
        let firstResult = await first
        let secondResult = await second
        let results = [firstResult, secondResult]

        XCTAssertEqual(results.filter { $0 }.count, 1)
        let snapshot = await manager.snapshot()
        XCTAssertEqual(snapshot.state, .loggingOut)
        XCTAssertEqual(snapshot.revision, revision)
    }

    func testAuthenticationSessionRejectsStaleRevisionAfterNewLogin() async {
        let oldRevision = UUID()
        let manager = DefaultAuthenticationSessionManager(
            initialState: .authenticated,
            initialRevision: oldRevision
        )

        await manager.markAuthenticated()
        let newSnapshot = await manager.snapshot()
        let accepted = await manager.beginLogoutIfCurrent(
            expectedRevision: oldRevision
        )

        XCTAssertNotEqual(newSnapshot.revision, oldRevision)
        XCTAssertFalse(accepted)
        XCTAssertEqual(newSnapshot.state, .authenticated)
    }

    func testAuthenticationSessionRestoresFromInitialToken() async {
        let tokenManager = DefaultTokenManager(token: "persisted-token")

        let manager = await DefaultAuthenticationSessionManager.restore(
            using: tokenManager
        )
        let snapshot = await manager.snapshot()

        XCTAssertEqual(snapshot.state, .authenticated)
    }

    func testAuthenticationSessionConvenienceInitializerAndFailureLogout() async {
        let manager = DefaultAuthenticationSessionManager(isAuthenticated: true)
        let snapshot = await manager.snapshot()
        let failure = CryoFailure(
            kind: .authenticationExpired,
            message: "登录已失效",
            authenticationRevision: snapshot.revision
        )

        let first = await manager.beginLogoutIfCurrent(for: failure)
        let second = await manager.beginLogoutIfCurrent(for: failure)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    func testFailureKeepsCapturedAuthenticationRevision() {
        let revision = UUID()
        let failure = CryoFailure(
            kind: .business,
            message: "login expired",
            businessCode: 10001
        ).attachingAuthenticationRevision(revision)

        XCTAssertEqual(failure.authenticationRevision, revision)
    }

    func testRequestAuthenticationContextKeepsInitialRevision() {
        let initialRevision = UUID()
        let context = RequestAuthenticationContext()

        context.captureIfNeeded(initialRevision)
        context.captureIfNeeded(UUID())

        XCTAssertEqual(context.revision, initialRevision)
    }

    func testInterceptorAdapterCapturesAuthenticationRevisionDuringAdapt() async throws {
        let revision = UUID()
        let authenticationSession = DefaultAuthenticationSessionManager(
            initialState: .authenticated,
            initialRevision: revision
        )
        let authenticationContext = RequestAuthenticationContext()
        let adapter = InterceptorAdapter(
            authenticationSession: authenticationSession,
            authenticationContext: authenticationContext
        )
        let session = Session(startRequestsImmediately: false)
        let url = try XCTUnwrap(URL(string: "https://example.com/test"))

        _ = try await withCheckedThrowingContinuation { continuation in
            adapter.adapt(URLRequest(url: url), for: session) { result in
                continuation.resume(with: result)
            }
        } as URLRequest

        XCTAssertEqual(authenticationContext.revision, revision)
    }

    private func makeResponse(
        statusCode: Int,
        data: Data,
        validationError: Bool = true
    ) throws -> AFDataResponse<Data?> {
        let url = try XCTUnwrap(URL(string: "https://example.com/test"))
        let request = URLRequest(url: url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ))
        let result: Result<Data?, AFError> = validationError
            ? .failure(.responseValidationFailed(reason: .unacceptableStatusCode(code: statusCode)))
            : .success(data)

        return AFDataResponse(
            request: request,
            response: response,
            data: data,
            metrics: nil,
            serializationDuration: 0,
            result: result
        )
    }
}
