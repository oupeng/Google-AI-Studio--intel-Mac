import SwiftUI
import AppKit
import WebKit

@main
struct AIStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            LiquidGlassContainerView()
                .frame(minWidth: 1024, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - macOS 26 原生 Liquid Glass 动态图标引擎 (符合 Swift 6 并发安全)
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
        NSApp.applicationIconImage = rendermacOS26Icon(isDark: isDarkMode)
    }

    private static func rendermacOS26Icon(isDark: Bool) -> NSImage {
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
        let shadowColor = isDark ? NSColor.black.withAlphaComponent(0.45).cgColor : NSColor.black.withAlphaComponent(0.25).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: shadowColor)
        ctx.addPath(squirclePath)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. 液体玻璃主体
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        let rgbSpace = CGColorSpaceCreateDeviceRGB()
        let glassGradientColors = isDark ? [
            NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 0.82).cgColor,
            NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 0.94).cgColor
        ] : [
            NSColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 0.90).cgColor,
            NSColor(red: 0.82, green: 0.88, blue: 0.98, alpha: 0.80).cgColor
        ]

        if let glassGrad = CGGradient(colorsSpace: rgbSpace, colors: glassGradientColors as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(glassGrad, start: CGPoint(x: 256, y: 464), end: CGPoint(x: 256, y: 48), options: [])
        }

        // 3. 菲涅尔边缘高光环
        let rimPath = CGPath(roundedRect: baseRect.insetBy(dx: 3, dy: 3), cornerWidth: 101, cornerHeight: 101, transform: nil)
        ctx.setLineWidth(2.5)
        let rimColor = isDark ? NSColor.white.withAlphaComponent(0.28).cgColor : NSColor.white.withAlphaComponent(0.85).cgColor
        ctx.setStrokeColor(rimColor)
        ctx.addPath(rimPath)
        ctx.strokePath()

        // 4. Gemini 琉璃晶体徽标
        let center = CGPoint(x: 256, y: 256)
        let core = CGMutablePath()
        core.move(to: CGPoint(x: center.x, y: center.y + 115))
        core.addQuadCurve(to: CGPoint(x: center.x + 115, y: center.y), control: CGPoint(x: center.x + 16, y: center.y + 16))
        core.addQuadCurve(to: CGPoint(x: center.x + 115, y: center.y), control: CGPoint(x: center.x + 16, y: center.y - 16))
        core.addQuadCurve(to: CGPoint(x: center.x - 115, y: center.y), control: CGPoint(x: center.x - 16, y: center.y - 16))
        core.addQuadCurve(to: CGPoint(x: center.x, y: center.y + 115), control: CGPoint(x: center.x - 16, y: center.y + 16))

        let coreColors = isDark ? [
            NSColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1.0).cgColor,
            NSColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1.0).cgColor
        ] : [
            NSColor(red: 0.12, green: 0.42, blue: 0.98, alpha: 1.0).cgColor,
            NSColor(red: 0.50, green: 0.18, blue: 0.90, alpha: 1.0).cgColor
        ]

        if let coreGrad = CGGradient(colorsSpace: rgbSpace, colors: coreColors as CFArray, locations: [0.0, 1.0]) {
            ctx.addPath(core)
            ctx.clip()
            ctx.drawLinearGradient(coreGrad, start: CGPoint(x: 141, y: 371), end: CGPoint(x: 371, y: 141), options: [])
        }

        ctx.restoreGState()
        iconImage.unlockFocus()
        return iconImage
    }
}

// MARK: - 主容器视图
struct LiquidGlassContainerView: View {
    @StateObject private var model = WebViewModel()
    @State private var inputText: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            OptimizedWebView(model: model)
                .ignoresSafeArea()

            // 智能感知：进入实际工作区才浮出输入坞，登录页面自动隐退
            if model.shouldShowInputBar {
                HStack(alignment: .bottom, spacing: 10) {
                    NativeInputTextView(
                        text: $inputText,
                        onCommit: dispatchPrompt
                    )
                    .frame(minHeight: 38, maxHeight: 150)

                    Button(action: dispatchPrompt) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.50),
                                    Color.white.opacity(0.12),
                                    Color.clear,
                                    Color.white.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.16), radius: 26, x: 0, y: 14)
                .padding(.horizontal, 32)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.shouldShowInputBar)
    }

    private func dispatchPrompt() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let msg = inputText
        inputText = ""
        model.injectAndRun(text: msg)
    }
}

// MARK: - WebKit 调优层（集成真实 Safari 27.0 UA 与导航委托）
@MainActor
final class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    @Published var shouldShowInputBar: Bool = false

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // 持久化 Cookie 登录态
        
        // 允许自动打开 Google OAuth 弹窗
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContent = WKUserContentController()
        
        // 针对 Intel MacBook Pro 的 DOM 虚拟化加速补丁
        let performanceCSS = """
        ms-prompt-node, .chat-turn, .history-container > * {
            content-visibility: auto !important;
            contain-intrinsic-size: 80px 200px;
        }
        [contenteditable], textarea {
            spellcheck: false !important;
            autocorrect: off !important;
        }
        """
        let cssScript = WKUserScript(
            source: "const s = document.createElement('style'); s.innerHTML = `\(performanceCSS)`; document.head.appendChild(s);",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContent.addUserScript(cssScript)
        config.userContentController = userContent

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self

        // 核心突破点：精确注入你当前系统的完整 Safari 27.0 官方原生 UA
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

        if let url = URL(string: "https://aistudio.google.com") {
            self.webView.load(URLRequest(url: url))
        }
    }

    // 智能页面路由感知：判断何时显示原生输入舱
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let urlString = webView.url?.absoluteString else { return }
        let isAuthPage = urlString.contains("accounts.google.com") || urlString.contains("ServiceLogin")
        let isAppWorkspace = urlString.contains("/prompts/") || urlString.contains("/app/") || urlString.contains("aistudio.google.com/live")
        
        self.shouldShowInputBar = !isAuthPage && isAppWorkspace
    }

    // 接管 Google 登录弹窗/新窗口重定向，强制在当前窗口无缝流转
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

    func injectAndRun(text: String) {
        guard let data = try? JSONEncoder().encode(text),
              let json = String(data: data, encoding: .utf8) else { return }

        let js = """
        (function() {
            const raw = \(json);
            const input = document.querySelector('textarea, div[contenteditable="true"]');
            if (input) {
                input.focus();
                if (document.queryCommandSupported('insertText')) {
                    document.execCommand('selectAll', false, null);
                    document.execCommand('insertText', false, raw);
                } else {
                    input.value = raw;
                    input.innerText = raw;
                }
                input.dispatchEvent(new Event('input', { bubbles: true }));
                setTimeout(() => {
                    const runBtn = document.querySelector('button[aria-label*="Run"], button.run-button, button[mat-tooltip*="Run"]');
                    if (runBtn && !runBtn.disabled) runBtn.click();
                }, 80);
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

// MARK: - 原生 AppKit 输入封装
@MainActor
struct NativeInputTextView: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.font = NSFont.systemFont(ofSize: 14.5)
        tv.isRichText = false
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeInputTextView
        init(_ parent: NativeInputTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            self.parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    parent.onCommit()
                    textView.string = ""
                    parent.text = ""
                    return true
                }
            }
            return false
        }
    }
}

@MainActor
struct OptimizedWebView: NSViewRepresentable {
    @ObservedObject var model: WebViewModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
