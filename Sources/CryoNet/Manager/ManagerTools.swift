/// 推断本地文件的MIME类型和所属分类（支持常见扩展名，未匹配返回 octet-stream 和未知分类）
///
/// - Parameter url: 文件URL
/// - Returns: 包含分类和 MIME 的信息结构体

import Foundation
func mimeTypeForURL(_ url: URL) -> MIMETypeInfo {
    let ext = url.pathExtension.lowercased()

    // MARK: - 图片类
    switch ext {
    case "jpg", "jpeg": return .init(category: .image, mime: "image/jpeg")
    case "png": return .init(category: .image, mime: "image/png")
    case "gif": return .init(category: .image, mime: "image/gif")
    case "bmp": return .init(category: .image, mime: "image/bmp")
    case "webp": return .init(category: .image, mime: "image/webp")
    case "heic": return .init(category: .image, mime: "image/heic")
    case "tiff", "tif": return .init(category: .image, mime: "image/tiff")
    case "ico": return .init(category: .image, mime: "image/x-icon")
    case "svg": return .init(category: .image, mime: "image/svg+xml")

    // MARK: - 音频类
    case "mp3": return .init(category: .audio, mime: "audio/mpeg")
    case "wav": return .init(category: .audio, mime: "audio/wav")
    case "aac": return .init(category: .audio, mime: "audio/aac")
    case "flac": return .init(category: .audio, mime: "audio/flac")
    case "m4a": return .init(category: .audio, mime: "audio/mp4")
    case "ogg", "oga": return .init(category: .audio, mime: "audio/ogg")
    case "opus": return .init(category: .audio, mime: "audio/opus")
    case "amr": return .init(category: .audio, mime: "audio/amr")
    case "aiff", "aif": return .init(category: .audio, mime: "audio/aiff")

    // MARK: - 视频类
    case "mp4": return .init(category: .video, mime: "video/mp4")
    case "mov": return .init(category: .video, mime: "video/quicktime")
    case "avi": return .init(category: .video, mime: "video/x-msvideo")
    case "mkv": return .init(category: .video, mime: "video/x-matroska")
    case "webm": return .init(category: .video, mime: "video/webm")
    case "wmv": return .init(category: .video, mime: "video/x-ms-wmv")
    case "flv": return .init(category: .video, mime: "video/x-flv")
    case "3gp": return .init(category: .video, mime: "video/3gpp")
    case "3g2": return .init(category: .video, mime: "video/3gpp2")
    case "mpeg", "mpg": return .init(category: .video, mime: "video/mpeg")
    case "m4v": return .init(category: .video, mime: "video/x-m4v")

    // MARK: - 文档类
    case "pdf": return .init(category: .document, mime: "application/pdf")
    case "doc": return .init(category: .document, mime: "application/msword")
    case "docx": return .init(category: .document, mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    case "xls": return .init(category: .document, mime: "application/vnd.ms-excel")
    case "xlsx": return .init(category: .document, mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    case "ppt": return .init(category: .document, mime: "application/vnd.ms-powerpoint")
    case "pptx": return .init(category: .document, mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation")
    case "txt", "log": return .init(category: .document, mime: "text/plain")
    case "rtf": return .init(category: .document, mime: "application/rtf")
    case "csv": return .init(category: .document, mime: "text/csv")
    case "md": return .init(category: .document, mime: "text/markdown")
    case "json": return .init(category: .document, mime: "application/json")
    case "xml": return .init(category: .document, mime: "application/xml")
    case "html", "htm": return .init(category: .document, mime: "text/html")
    case "yml", "yaml": return .init(category: .document, mime: "text/yaml")

    // MARK: - 压缩包类
    case "zip": return .init(category: .archive, mime: "application/zip")
    case "rar": return .init(category: .archive, mime: "application/vnd.rar")
    case "7z": return .init(category: .archive, mime: "application/x-7z-compressed")
    case "tar": return .init(category: .archive, mime: "application/x-tar")
    case "gz": return .init(category: .archive, mime: "application/gzip")
    case "bz2": return .init(category: .archive, mime: "application/x-bzip2")
    case "xz": return .init(category: .archive, mime: "application/x-xz")
    case "lz": return .init(category: .archive, mime: "application/x-lzip")
    case "lzma": return .init(category: .archive, mime: "application/x-lzma")

    // MARK: - 代码类
    case "js": return .init(category: .code, mime: "application/javascript")
    case "ts": return .init(category: .code, mime: "application/typescript")
    case "jsonc": return .init(category: .code, mime: "application/json")
    case "css": return .init(category: .code, mime: "text/css")
    case "scss", "sass": return .init(category: .code, mime: "text/x-scss")
    case "swift": return .init(category: .code, mime: "text/x-swift")
    case "java": return .init(category: .code, mime: "text/x-java-source")
    case "py": return .init(category: .code, mime: "text/x-python")
    case "c", "h": return .init(category: .code, mime: "text/x-c")
    case "cpp", "cc", "cxx": return .init(category: .code, mime: "text/x-c++")
    case "hpp": return .init(category: .code, mime: "text/x-c++hdr")
    case "m": return .init(category: .code, mime: "text/x-objective-c")
    case "mm": return .init(category: .code, mime: "text/x-objective-c++")
    case "go": return .init(category: .code, mime: "text/x-go")
    case "rs": return .init(category: .code, mime: "text/x-rustsrc")
    case "php": return .init(category: .code, mime: "application/x-httpd-php")
    case "sh": return .init(category: .code, mime: "application/x-sh")
    case "bat": return .init(category: .code, mime: "application/x-msdos-program")
    case "pl": return .init(category: .code, mime: "text/x-perl")
    case "rb": return .init(category: .code, mime: "application/x-ruby")

    // MARK: - 字体类
    case "ttf": return .init(category: .font, mime: "font/ttf")
    case "otf": return .init(category: .font, mime: "font/otf")
    case "woff": return .init(category: .font, mime: "font/woff")
    case "woff2": return .init(category: .font, mime: "font/woff2")
    case "eot": return .init(category: .font, mime: "application/vnd.ms-fontobject")

    // MARK: - 应用安装包
    case "apk": return .init(category: .appPackage, mime: "application/vnd.android.package-archive")
    case "ipa": return .init(category: .appPackage, mime: "application/octet-stream")
    case "exe": return .init(category: .appPackage, mime: "application/vnd.microsoft.portable-executable")
    case "msi": return .init(category: .appPackage, mime: "application/x-msdownload")
    case "dmg": return .init(category: .appPackage, mime: "application/x-apple-diskimage")
    case "pkg": return .init(category: .appPackage, mime: "application/octet-stream")

    // MARK: - 镜像文件
    case "iso": return .init(category: .diskImage, mime: "application/x-iso9660-image")
    case "img", "vhd", "vmdk": return .init(category: .diskImage, mime: "application/octet-stream")

    // MARK: - 默认类型
    default:
        return .init(category: .unknown, mime: "application/octet-stream")
    }
}

/// MIME 文件类型分类
enum MIMECategory: String {
    case image = "图片类"
    case audio = "音频类"
    case video = "视频类"
    case document = "文档类"
    case archive = "压缩包类"
    case code = "代码类"
    case font = "字体类"
    case appPackage = "应用安装包"
    case diskImage = "镜像/虚拟磁盘类"
    case unknown = "未知类型"
}

/// 包含 MIME 类型和所属分类
struct MIMETypeInfo {
    let category: MIMECategory
    let mime: String
}
