import SwiftUI
import AppKit
import WebKit

// 全局通知定义
extension Notification.Name {
    static let reloadPage = Notification.Name("AIStudioReloadPage")
    static let forceReloadPage = Notification.Name("AIStudioForceReloadPage")
    static let goBackPage = Notification.Name("AIStudioGoBackPage")
    static let goForwardPage = Notification.Name("AIStudioGoForwardPage")
}

@main
struct AIStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            CleanAIStudioView()
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("页面导航") {
                Button("重新加载") {
                    NotificationCenter.default.post(name: .reloadPage, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("强制重新加载 (清空缓存)") {
                    NotificationCenter.default.post(name: .forceReloadPage, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("返回上一页") {
                    NotificationCenter.default.post(name: .goBackPage, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("前进") {
                    NotificationCenter.default.post(name: .goForwardPage, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
            }
        }
    }
}

// MARK: - 主视图
struct CleanAIStudioView: View {
    @StateObject private var model = WebViewModel()

    var body: some View {
        OptimizedWebView(model: model)
            .ignoresSafeArea()
            .background(
                Group {
                    Button("") { model.webView.reload() }
                        .keyboardShortcut("r", modifiers: .command)
                    Button("") { model.webView.reloadFromOrigin() }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                .opacity(0)
            )
            .onReceive(NotificationCenter.default.publisher(for: .reloadPage)) { _ in
                model.webView.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .forceReloadPage)) { _ in
                model.webView.reloadFromOrigin()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goBackPage)) { _ in
                if model.webView.canGoBack { model.webView.goBack() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .goForwardPage)) { _ in
                if model.webView.canGoForward { model.webView.goForward() }
            }
    }
}

// MARK: - 深度汉化版 WKWebView
@MainActor
final class LocalizedWKWebView: WKWebView {
    private let menuTranslations: [String: String] = [
        "Inspect Element": "检查元素",
        "Reload Page": "重新加载页面",
        "Reload": "重新加载",
        "Back": "后退",
        "Forward": "前进",
        "Stop": "停止",
        "Copy": "拷贝",
        "Cut": "剪切",
        "Paste": "粘贴",
        "Paste and Match Style": "粘贴并匹配样式",
        "Select All": "全选",
        "Open Link in New Window": "在新窗口中打开链接",
        "Download Linked File": "下载链接的文件",
        "Copy Link": "拷贝链接",
        "Open Image in New Window": "在新窗口中打开图像",
        "Download Image": "下载图像",
        "Copy Image": "拷贝图像",
        "Look Up": "查询",
        "Translate": "翻译",
        "Search with Google": "使用 Google 搜索",
        "Speech": "语音",
        "Start Speaking": "开始朗读",
        "Stop Speaking": "停止朗读",
        "Spelling and Grammar": "拼写和语法"
    ]

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        localizeMenu(menu)
        return menu
    }

    private func localizeMenu(_ menu: NSMenu) {
        for item in menu.items {
            let trimmed = item.title.trimmingCharacters(in: .whitespaces)
            if let localized = menuTranslations[trimmed] {
                item.title = localized
            } else if trimmed.hasPrefix("Look Up ") {
                item.title = "查询 \(trimmed.dropFirst(8))"
            } else if trimmed.hasPrefix("Search with ") {
                item.title = "在网页中搜索 \(trimmed.dropFirst(12))"
            }
            if let submenu = item.submenu {
                localizeMenu(submenu)
            }
        }
    }
}

// MARK: - WebKit 调优管理器
@MainActor
final class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    var webView: LocalizedWKWebView!

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let userContent = WKUserContentController()

        // 屏蔽 play.google.com/log 网络报错重试
        let muteLoggerScriptSource = """
        (function() {
            const originalFetch = window.fetch;
            window.fetch = function(url, options) {
                if (typeof url === 'string' && url.includes('play.google.com/log')) {
                    return Promise.resolve(new Response(JSON.stringify({}), { status: 200 }));
                }
                return originalFetch.apply(this, arguments);
            };
        })();
        """
        let muteScript = WKUserScript(source: muteLoggerScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContent.addUserScript(muteScript)

        // 视口外历史跳过排版 + 输入框排版隔离（放行数据流，拦截重排计算）
        let engineTuningCSS = """
        ms-chat-turn, .chat-turn, ms-prompt-node, .prompt-node, .history-container > *, ms-run-chunk, .chat-chunk {
            content-visibility: auto !important;
            contain-intrinsic-size: 80px 240px !important;
        }

        textarea, [contenteditable="true"], .prompt-editor, ms-prompt-editor, [role="textbox"], .input-container {
            contain: layout style paint !important;
            spellcheck: false !important;
            autocorrect: off !important;
            autocapitalize: off !important;
            transform: translateZ(0) !important;
        }

        .chat-history, .prompt-history, ms-prompt-history {
            will-change: transform;
            transform: translateZ(0);
        }
        """

        let escapedCSS = engineTuningCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let safeScriptSource = """
        (function() {
            const s = document.createElement('style');
            s.textContent = `\(escapedCSS)`;
            (document.head || document.documentElement).appendChild(s);
        })();
        """

        let cssScript = WKUserScript(source: safeScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContent.addUserScript(cssScript)
        config.userContentController = userContent

        self.webView = LocalizedWKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self

        self.webView.wantsLayer = true
        self.webView.layer?.drawsAsynchronously = true

        self.webView.isInspectable = true
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

        if let url = URL(string: "https://aistudio.google.com") {
            self.webView.load(URLRequest(url: url))
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - AppKit 容器桥接
@MainActor
struct OptimizedWebView: NSViewRepresentable {
    @ObservedObject var model: WebViewModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - 动态 Liquid Glass 文字图标引擎 (亮色纯白，深色纯黑)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.applyLiquidGlassDockIcon()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: nil
        ) { _ in
            Task { @MainActor in
                AppDelegate.applyLiquidGlassDockIcon()
            }
        }
    }

    static func applyLiquidGlassDockIcon() {
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSApp.applicationIconImage = rendermacOS26TextIcon(isDark: isDarkMode)
    }

    private static func rendermacOS26TextIcon(isDark: Bool) -> NSImage {
        let canvasSize = NSSize(width: 512, height: 512)
        let iconImage = NSImage(size: canvasSize)

        iconImage.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            iconImage.unlockFocus()
            return iconImage
        }

        let baseRect = CGRect(x: 48, y: 48, width: 416, height: 416)
        let squirclePath = CGPath(roundedRect: baseRect, cornerWidth: 104, cornerHeight: 104, transform: nil)

        // 1. 拟态背光投影
        ctx.saveGState()
        let shadowColor = isDark ? NSColor.black.withAlphaComponent(0.48).cgColor : NSColor.black.withAlphaComponent(0.16).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: shadowColor)
        ctx.addPath(squirclePath)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. 底座主体（亮色纯白，深色纯黑）
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        if isDark {
            // 深色模式：黑曜石沉浸质感
            let space = CGColorSpaceCreateDeviceRGB()
            let darkColors = [
                NSColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 0.90).cgColor,
                NSColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.98).cgColor
            ]
            if let grad = CGGradient(colorsSpace: space, colors: darkColors as CFArray, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(grad, start: CGPoint(x: 256, y: 464), end: CGPoint(x: 256, y: 48), options: [])
            }
        } else {
            // 亮色模式：和 Gemini 图标一致的纯净实体白
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(baseRect)
        }

        // 3. 边缘微米级高光/边框
        let rimPath = CGPath(roundedRect: baseRect.insetBy(dx: 2, dy: 2), cornerWidth: 102, cornerHeight: 102, transform: nil)
        ctx.setLineWidth(2.0)
        let rimColor = isDark ? NSColor.white.withAlphaComponent(0.30).cgColor : NSColor.black.withAlphaComponent(0.06).cgColor
        ctx.setStrokeColor(rimColor)
        ctx.addPath(rimPath)
        ctx.strokePath()

        // 4. 三排文字排版
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center

        // 第一排: Google
        let googleColor = isDark ? NSColor(white: 0.92, alpha: 1.0) : NSColor(white: 0.08, alpha: 1.0)
        let googleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 66, weight: .heavy),
            .foregroundColor: googleColor,
            .paragraphStyle: pStyle,
            .kern: 0.2
        ]
        "Google".draw(in: CGRect(x: 48, y: 320, width: 416, height: 76), withAttributes: googleAttrs)

        // 第二排: AI
        let aiColor = isDark ? NSColor.white : NSColor.black
        let aiAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 96, weight: .black),
            .foregroundColor: aiColor,
            .paragraphStyle: pStyle,
            .kern: 2.5
        ]
        "AI".draw(in: CGRect(x: 48, y: 206, width: 416, height: 106), withAttributes: aiAttrs)

        // 第三排: Studio
        let studioColor = isDark ? NSColor(white: 0.88, alpha: 1.0) : NSColor(white: 0.12, alpha: 1.0)
        let studioAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .heavy),
            .foregroundColor: studioColor,
            .paragraphStyle: pStyle,
            .kern: 0.2
        ]
        "Studio".draw(in: CGRect(x: 48, y: 116, width: 416, height: 82), withAttributes: studioAttrs)

        ctx.restoreGState()
        iconImage.unlockFocus()
        return iconImage
    }
}
