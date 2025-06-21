import Foundation
import Alamofire

@available(iOS 13, macOS 10.15, *)
public actor DownloadItem: Identifiable, Equatable, @unchecked Sendable {
    public let id = UUID().uuidString

    private var _downloadURL: String = ""
    private var _fileName: String = ""
    private var _filePath: String = ""
    private var _progress: Double = 0.0
    private var _isSaveToAlbum: Bool = false

    public static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id
    }

    public init(downloadURL: String,
                fileName: String? = nil,
                filePath: String? = nil,
                isSaveToAlbum: Bool = false) {
        self._downloadURL = downloadURL
        self._fileName = fileName ?? (downloadURL as NSString).lastPathComponent
        self._filePath = filePath ?? ""
        self._isSaveToAlbum = isSaveToAlbum
    }

    public init() {}

    public func setProgress(_ value: Double) { _progress = value }
    public func getProgress() -> Double { _progress }
    public func getFileName() -> String { _fileName }
    public func getFilePath() -> String { _filePath }
    public func setFilePath(_ path: String) { _filePath = path }
    public func getDownloadURL() -> String { _downloadURL }
    public func isSaveToAlbum() -> Bool { _isSaveToAlbum }
    public func fileURL() -> URL? { URL(string: _downloadURL) }
}
