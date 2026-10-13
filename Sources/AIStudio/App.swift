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

// MARK: - 极简纯净主视图：零多余遮挡，100% 官方沉浸界面
struct CleanAIStudioView: View {
    @StateObject private var model = WebViewModel()

    var body: some View {
        OptimizedWebView(model: model)
            .ignoresSafeArea() // 全屏无缝铺满，彻底移除任何悬浮遮挡
    }
}

// MARK: - WebKit 底层引擎调优（宿主特权层绕过 CSP，底层静默加速）
@MainActor
final class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // 保持持久化 Cookie 登录态，与 iPad Pro 实时互通
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContent = WKUserContentController()

        // 核心技术点：WKUserScript 以宿主特权身份注入，完全不受页面 CSP（内容安全策略）限制
        let engineTuningCSS = """
        /* 1. 视口外历史消息完全跳过几何排版与重绘，彻底卸下 2020 Intel CPU 负担 */
        ms-chat-turn, .chat-turn, ms-prompt-node, .prompt-node, .history-container > *, ms-run-chunk, .chat-chunk {
            content-visibility: auto !important;
            contain-intrinsic-size: 80px 240px !important;
        }

        /* 2. 核心：将网页自带的输入框强行圈为“排版孤岛”！敲字时阻断向上重排链路 */
        textarea, [contenteditable="true"], .prompt-editor, ms-prompt-editor, [role="textbox"] {
            contain: layout style paint !important;
            spellcheck: false !important;
            autocorrect: off !important;
            autocapitalize: off !important;
        }

        /* 3. 提升历史滚动层的 GPU 硬件加速 */
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

        // 绑定你 MacBook Pro 真实的 Safari 27.0 官方原生 UA，确保 100% 顺畅登录
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

        if let url = URL(string: "https://aistudio.google.com") {
            self.webView.load(URLRequest(url: url))
        }
    }

    // 接管登录重定向与弹窗，单窗口内平滑流转
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

// MARK: - 三排文字 Liquid Glass 动态图标引擎 (符合 Swift 6 并发安全规范)
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

    // 三排纯文字 Liquid Glass 质感图标生成
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

        // 1. 拟态背光漫反射阴影 (Ambient Shadow)
        ctx.saveGState()
        let shadowColor = isDark ? NSColor.black.withAlphaComponent(0.48).cgColor : NSColor.black.withAlphaComponent(0.22).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: shadowColor)
        ctx.addPath(squirclePath)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. 液体玻璃主体底座 (Liquid Glass Body)
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

        // 3. 菲涅尔边缘高光环 (Fresnel Specular Rim)
        let rimPath = CGPath(roundedRect: baseRect.insetBy(dx: 3, dy: 3), cornerWidth: 101, cornerHeight: 101, transform: nil)
        ctx.setLineWidth(2.5)
        let rimColor = isDark ? NSColor.white.withAlphaComponent(0.32).cgColor : NSColor.white.withAlphaComponent(0.85).cgColor
        ctx.setStrokeColor(rimColor)
        ctx.addPath(rimPath)
        ctx.strokePath()

        // 4. 三排文字核心排版 (Google / AI / Studio)
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center

        // 第一排: Google
        let googleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 44, weight: .bold),
            .foregroundColor: isDark ? NSColor(white: 0.88, alpha: 1.0) : NSColor(red: 0.22, green: 0.24, blue: 0.30, alpha: 1.0),
            .paragraphStyle: pStyle,
            .kern: 1.2
        ]
        "Google".draw(in: CGRect(x: 48, y: 326, width: 416, height: 52), withAttributes: googleAttrs)

        // 第二排: AI (视觉焦点 Hero)
        let aiAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 96, weight: .black),
            .foregroundColor: isDark ? NSColor.white : NSColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1.0),
            .paragraphStyle: pStyle,
            .kern: 3.0
        ]
        "AI".draw(in: CGRect(x: 48, y: 206, width: 416, height: 110), withAttributes: aiAttrs)

        // 第三排: Studio
        let studioAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: isDark ? NSColor(white: 0.82, alpha: 1.0) : NSColor(red: 0.32, green: 0.35, blue: 0.42, alpha: 1.0),
            .paragraphStyle: pStyle,
            .kern: 1.8
        ]
        "Studio".draw(in: CGRect(x: 48, y: 140, width: 416, height: 56), withAttributes: studioAttrs)

        ctx.restoreGState()
        iconImage.unlockFocus()
        return iconImage
    }
}
