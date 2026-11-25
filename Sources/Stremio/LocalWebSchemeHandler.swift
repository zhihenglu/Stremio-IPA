import Foundation
import WebKit

/// 用自定义 scheme `stremioapp://localhost/` 提供 App Bundle 内 `web/` 目录的本地文件。
///
/// 为什么不用 file://：
/// - stremio-web 的核心（stremio-core，Rust 编译的 WASM）跑在 Web Worker 里：
///   `new Worker("<COMMIT_HASH>/scripts/worker.js")`（相对路径）。
/// - file:// 下 Worker、WASM、fetch 都会被同源策略/CORS 拦掉。
/// - 自定义 scheme 是一个 http-like 的同源 origin：相对路径、Worker、`.wasm`
///   都能按正常网页规则加载，前提是这里返回正确的 MIME（尤其 .wasm）。
///
/// 本 handler 只注册在自定义 scheme 上，绝不拦截 http/https：
/// Stremio 的插件 API、图片、视频流等绝对 https/http 请求全部走正常网络。
final class LocalWebSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "stremioapp"
    static let host = "localhost"
    static var startURL: URL {
        URL(string: "\(scheme)://\(host)/index.html")!
    }

    private var stoppedTasks = Set<ObjectIdentifier>()
    private let lock = NSLock()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let fileURL = resolveFileURL(for: url)
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL) else {
            let response = HTTPURLResponse(url: url, statusCode: 404,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }

        if isStopped(urlSchemeTask) { return }

        let mime = Self.mimeType(for: fileURL.pathExtension.lowercased())
        let headers: [String: String] = [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
            // 同源本不需要 CORS 头；加上 * 让 Worker 内的 fetch/wasm 编译更宽容
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ]
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        stoppedTasks.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedTasks.contains(ObjectIdentifier(task))
    }

    // MARK: - 路径解析

    private func resolveFileURL(for url: URL) -> URL? {
        guard let webRoot = Bundle.main.resourceURL?.appendingPathComponent("web") else {
            return nil
        }

        var path = url.path.removingPercentEncoding ?? url.path
        if path.isEmpty || path == "/" {
            path = "/index.html"
        }

        let candidate = webRoot.appendingPathComponent(String(path.dropFirst()))
        if FileManager.default.fileExists(atPath: candidate.path) {
            // 防目录穿越：解析后必须仍在 web/ 内
            let rootPath = webRoot.standardizedFileURL.path
            let filePath = candidate.standardizedFileURL.path
            guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else { return nil }
            return candidate
        }

        // SPA 兜底：无扩展名的路径回退到 index.html（本应用用 HashRouter，
        // 正常不会走到这里；带扩展名的缺失文件直接 404，不要拿 HTML 冒充 JS/WASM）
        if (path as NSString).pathExtension.isEmpty {
            let index = webRoot.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: index.path) {
                return index
            }
        }
        return nil
    }

    // MARK: - MIME

    static func mimeType(for ext: String) -> String {
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "wasm": return "application/wasm"
        case "json", "map": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "txt": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        default: return "application/octet-stream"
        }
    }
}
