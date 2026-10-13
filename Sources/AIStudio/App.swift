import SwiftUI
import AppKit
import WebKit

@main
struct AIStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            CleanAIStudioView()
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar) // 融合 macOS 26 贯通式流光顶栏
    }
}

// MARK: - 极简纯净主视图
struct CleanAIStudioView: View {
    @StateObject private var model = WebViewModel()

    var body: some View {
        OptimizedWebView(model: model)
            .ignoresSafeArea()
    }
}

// MARK: - WebKit 底层引擎调优（开启 Web Inspector 调试与底层静默加速）
@MainActor
final class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // 1. 开启经典右键开发者菜单属性
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let userContent = WKUserContentController()

        // 宿主特权层 CSS 注入：隔离输入框重排链 + 视口外历史消息虚拟化
        let engineTuningCSS = """
        /* 视口外历史消息跳过排版，释放 CPU */
        ms-chat-turn, .chat-turn, ms-prompt-node, .prompt-node, .history-container > *, ms-run-chunk, .chat-chunk {
            content-visibility: auto !important;
            contain-intrinsic-size: 80px 240px !important;
        }

        /* 输入框排版隔离，阻断长对话打字向上级联重排 */
        textarea, [contenteditable="true"], .prompt-editor, ms-prompt-editor, [role="textbox"] {
            contain: layout style paint !important;
            spellcheck: false !important;
            autocorrect: off !important;
            autocapitalize: off !important;
        }

        .chat-history, .prompt-history, ms-prompt-history {
            will-change: transform;
            transform: translateZ(0);
        }
        """

        let cssScript = WKUserScript(
            source: "const s = document.createElement('style'); s.innerHTML = `\(engineTuningCSS)`; document.head.appendChild(s);",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContent.addUserScript(cssScript)
        config.userContentController = userContent

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self

        // 2. 核心：开启 macOS 现代 Web Inspector 审查器（支持右键检查元素）
        self.webView.isInspectable = true

        // 绑定原生 Safari 27.0 官方真实 UA，确保顺畅登录
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

        if let url = URL(string: "https://aistudio.google.com") {
            self.webView.load(URLRequest(url: url))
        }
    }

    // 接管登录重定向与弹窗
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

// MARK: - AppKit 原生 WKWebView 承载
@MainActor
struct OptimizedWebView: NSViewRepresentable {
    @ObservedObject var model: WebViewModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - 动态 Liquid Glass 文字图标引擎（按黄金比例放大第一排与第三排）
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

        // 1. 拟态背光漫反射阴影
        ctx.saveGState()
        let shadowColor = isDark ? NSColor.black.withAlphaComponent(0.48).cgColor : NSColor.black.withAlphaComponent(0.22).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: shadowColor)
        ctx.addPath(squirclePath)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. 液体玻璃主体底座
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        let rgbSpace = CGColorSpaceCreateDeviceRGB()
        let glassGradientColors = isDark ? [
            NSColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 0.88).cgColor,
            NSColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.96).cgColor
        ] : [
            NSColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 0.92).cgColor,
            NSColor(red: 0.84, green: 0.88, blue: 0.96, alpha: 0.84).cgColor
        ]

        if let glassGrad = CGGradient(colorsSpace: rgbSpace, colors: glassGradientColors as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(glassGrad, start: CGPoint(x: 256, y: 464), end: CGPoint(x: 256, y: 48), options: [])
        }

        // 3. 菲涅尔边缘高光环
        let rimPath = CGPath(roundedRect: baseRect.insetBy(dx: 3, dy: 3), cornerWidth: 101, cornerHeight: 101, transform: nil)
        ctx.setLineWidth(2.5)
        let rimColor = isDark ? NSColor.white.withAlphaComponent(0.32).cgColor : NSColor.white.withAlphaComponent(0.85).cgColor
        ctx.setStrokeColor(rimColor)
        ctx.addPath(rimPath)
        ctx.strokePath()

        // 4. 三排文字排版（适度放大首尾两排字体，居中严密排版）
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center

        // 第一排: Google（从 44pt 放大到 62pt Heavy）
        let googleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 62, weight: .heavy),
            .foregroundColor: isDark ? NSColor(white: 0.90, alpha: 1.0) : NSColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 1.0),
            .paragraphStyle: pStyle,
            .kern: 0.5
        ]
        "Google".draw(in: CGRect(x: 48, y: 322, width: 416, height: 72), withAttributes: googleAttrs)

        // 第二排: AI（保持视觉焦点 96pt Black）
        let aiAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 96, weight: .black),
            .foregroundColor: isDark ? NSColor.white : NSColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1.0),
            .paragraphStyle: pStyle,
            .kern: 2.5
        ]
        "AI".draw(in: CGRect(x: 48, y: 206, width: 416, height: 106), withAttributes: aiAttrs)

        // 第三排: Studio（从 48pt 放大到 66pt Heavy）
        let studioAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 66, weight: .heavy),
            .foregroundColor: isDark ? NSColor(white: 0.86, alpha: 1.0) : NSColor(red: 0.28, green: 0.31, blue: 0.38, alpha: 1.0),
            .paragraphStyle: pStyle,
            .kern: 0.5
        ]
        "Studio".draw(in: CGRect(x: 48, y: 122, width: 416, height: 76), withAttributes: studioAttrs)

        ctx.restoreGState()
        iconImage.unlockFocus()
        return iconImage
    }
}
