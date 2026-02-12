import XCTest
import Alamofire
import SwiftyJSON
@testable import CryoNet

@available(iOS 13, macOS 10.15, *)
final class CryoNetTests: XCTestCase {

    struct UploadTestModel: JSONParseable, Sendable {
        let value: String
        init?(json: JSON) {
            self.value = json["value"] ?? ""
        }
    }

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

    func testDownloadCancelKeepsTaskButRemoveDeletesTask() async {
        let manager = DownloadManager()
        let id = await manager.addTask(pathOrURL: "https://example.com/file.txt")

        await manager.cancelTask(id: id, shouldDeleteFile: false)
        let cancelled = await manager.getTaskInfo(id: id)
        XCTAssertEqual(cancelled?.state, .cancelled)

        await manager.removeTask(id: id, shouldDeleteFile: false)
        let removed = await manager.getTaskInfo(id: id)
        XCTAssertNil(removed)
    }

    func testUploadCancelKeepsTaskButDeleteRemovesTask() async {
        let manager = UploadManager<UploadTestModel>(
            identifier: "upload-test-\(UUID().uuidString)",
            uploadURL: URL(string: "https://example.com/upload")!,
            maxConcurrentUploads: 1,
            interceptor: DefaultInterceptor()
        )
        let file = UploadFileItem(
            data: Data("hello".utf8),
            name: "file",
            fileName: "a.txt",
            mimeType: "text/plain"
        )
        let id = await manager.addTask(files: [file])

        await manager.cancelTask(id: id)
        let cancelled = await manager.getTask(id: id)
        XCTAssertEqual(cancelled?.state, .cancelled)

        await manager.deleteTask(id: id)
        let removed = await manager.getTask(id: id)
        XCTAssertNil(removed)
    }

    func testDownloadManagerPoolRemoveManagerIsAwaitable() async {
        let pool = DownloadManagerPool.shared
        let identifier = "download-pool-test-\(UUID().uuidString)"
        let manager = await pool.manager(for: identifier, maxConcurrentDownloads: 1)
        _ = await manager.addTask(pathOrURL: "https://example.com/a.txt")

        await pool.removeManager(for: identifier, shouldDeleteFile: false)
        let removed = await pool.getManager(for: identifier)
        XCTAssertNil(removed)
    }

    func testUploadManagerPoolRemoveManagerIsAwaitable() async {
        let pool = UploadManagerPool.shared
        let identifier = "upload-pool-test-\(UUID().uuidString)"
        let manager = await pool.manager(
            for: identifier,
            uploadURL: URL(string: "https://example.com/upload")!,
            maxConcurrentUploads: 1,
            modelType: UploadTestModel.self,
            interceptor: DefaultInterceptor()
        )
        let file = UploadFileItem(
            data: Data("hello".utf8),
            name: "file",
            fileName: "a.txt",
            mimeType: "text/plain"
        )
        _ = await manager.addTask(files: [file])

        await pool.removeManager(for: identifier, modelType: UploadTestModel.self)
        let removed: UploadManager<UploadTestModel>? = await pool.getManager(for: identifier, modelType: UploadTestModel.self)
        XCTAssertNil(removed)
    }
}
