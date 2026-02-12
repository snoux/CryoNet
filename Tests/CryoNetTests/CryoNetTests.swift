import XCTest
import Alamofire
@testable import CryoNet

@available(iOS 13, macOS 10.15, *)
final class CryoNetTests: XCTestCase {

    func testRequestModelDefaultOvertimeIsZero() {
        let model = RequestModel(path: "/ping")
        XCTAssertEqual(model.overtime, 0)
        XCTAssertEqual(model.method, HTTPMethod.post)
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
}
