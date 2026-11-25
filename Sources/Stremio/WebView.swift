import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 关键：只为自定义 scheme 注册本地文件 handler，不碰 http/https
        config.setURLSchemeHandler(LocalWebSchemeHandler(), forURLScheme: LocalWebSchemeHandler.scheme)
        // 视频内联播放、自动播放不要求用户手势（Stremio 播放器需要）
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.165, green: 0.157, blue: 0.263, alpha: 1) // #2a2843
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView

        if Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") != nil {
            webView.load(URLRequest(url: LocalWebSchemeHandler.startURL))
        } else {
            // 仓库里 web/ 只有占位文件时（未跑 Actions 构建）给出说明页，避免白屏无提示
            webView.loadHTMLString(Self.placeholderHTML, baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private static let placeholderHTML = """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>body{background:#2a2843;color:#fff;font-family:-apple-system,sans-serif;
    display:flex;align-items:center;justify-content:center;height:100vh;margin:0;
    text-align:center;padding:24px;box-sizing:border-box}</style></head>
    <body><div><h2>网页文件未打包</h2>
    <p>此构建没有包含 stremio-web 产物。请用 GitHub Actions 构建正式 IPA，\
    构建流程会自动下载并打包 stremio-web。</p></div></body></html>
    """

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?

        /// 主框架导航策略：
        /// - stremioapp:// 本地资源、about:blank 放行
        /// - http/https 的主框架跳转（如登录 OAuth、外部链接）交给系统浏览器，
        ///   避免把第三方页面关进壳里；子框架与 fetch/XHR 不经过这里，正常联网。
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == LocalWebSchemeHandler.scheme || url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            if (url.scheme == "http" || url.scheme == "https"),
               navigationAction.targetFrame?.isMainFrame == true,
               navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// window.open / target=_blank：新窗口请求改为系统浏览器打开
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if url.scheme == "http" || url.scheme == "https" {
                    UIApplication.shared.open(url)
                } else {
                    webView.load(navigationAction.request)
                }
            }
            return nil
        }
    }
}
