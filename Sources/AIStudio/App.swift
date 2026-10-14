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
                .background(WindowFrameAccessor()) // 自动记录并恢复窗口尺寸与坐标
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

// MARK: - 原生窗口状态持久化记忆器
struct WindowFrameAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                // 绑定持久化名称，系统自动保存/恢复尺寸与坐标
                window.setFrameAutosaveName("AIStudioMainWindowAutosaveFrame")
                window.isRestorable = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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

// MARK: - WebKit 调优管理器（带控制台可视化自检徽章）
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

        // 1. 全光谱网络拦截器
        let muteLoggerScriptSource = """
        (function() {
            function isLogUrl(input) {
                if (!input) return false;
                try {
                    let str = '';
                    if (typeof input === 'string') {
                        str = input;
                    } else if (input.href && typeof input.href === 'string') {
                        str = input.href;
                    } else if (input.url && typeof input.url === 'string') {
                        str = input.url;
                    } else {
                        str = String(input);
                    }
                    return str.indexOf('play.google.com/log') !== -1;
                } catch (e) {
                    return false;
                }
            }

            const originalFetch = window.fetch;
            window.fetch = function(resource, init) {
                if (isLogUrl(resource)) {
                    return Promise.resolve(new Response(JSON.stringify({}), {
                        status: 200,
                        headers: { 'Content-Type': 'application/json' }
                    }));
                }
                return originalFetch.apply(this, arguments);
            };

            if (navigator.sendBeacon) {
                const originalBeacon = navigator.sendBeacon;
                navigator.sendBeacon = function(url, data) {
                    if (isLogUrl(url)) return true;
                    return originalBeacon.apply(this, arguments);
                };
            }

            const origOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (isLogUrl(url)) {
                    this._isMutedLog = true;
                }
                return origOpen.apply(this, arguments);
            };
            const origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.send = function() {
                if (this._isMutedLog) {
                    Object.defineProperty(this, 'readyState', { value: 4 });
                    Object.defineProperty(this, 'status', { value: 200 });
                    Object.defineProperty(this, 'responseText', { value: '{}' });
                    if (typeof this.onload === 'function') this.onload(new Event('load'));
                    return;
                }
                return origSend.apply(this, arguments);
            };
        })();
        """
        userContent.addUserScript(WKUserScript(source: muteLoggerScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        // 2. 自启动 DOM 裁剪引擎（带控制台验证日志）
        let githubOptimizerEngine = """
        (function() {
            const MAX_ACTIVE_TURNS = 6;
            let pruneTimer = null;
            let lastPrunedCount = -1;

            function optimizeDOMTree() {
                const turns = document.querySelectorAll('ms-chat-turn, .chat-turn, ms-prompt-node, .prompt-node');
                if (!turns || turns.length <= MAX_ACTIVE_TURNS) return;

                const cutoffIndex = turns.length - MAX_ACTIVE_TURNS;
                let pruned = 0;
                for (let i = 0; i < turns.length; i++) {
                    if (i < cutoffIndex) {
                        if (turns[i].style.display !== 'none') {
                            turns[i].style.display = 'none';
                            pruned++;
                        }
                    } else {
                        if (turns[i].style.display === 'none') {
                            turns[i].style.display = '';
                        }
                    }
                }

                if (pruned > 0 && lastPrunedCount !== cutoffIndex) {
                    lastPrunedCount = cutoffIndex;
                    console.info(
                        `%c⚡ [AIStudio 引擎生效] 已隐藏前 ${cutoffIndex} 轮历史 DOM，当前视口活跃回合: ${MAX_ACTIVE_TURNS}`,
                        'color: #00ff88; font-weight: bold;'
                    );
                }
            }

            const observer = new MutationObserver(() => {
                if (pruneTimer) clearTimeout(pruneTimer);
                pruneTimer = setTimeout(optimizeDOMTree, 250);
            });

            function startEngine() {
                const target = document.body || document.documentElement;
                if (target) {
                    observer.observe(target, { childList: true, subtree: true });
                    setInterval(optimizeDOMTree, 1500);
                    optimizeDOMTree();

                    // 控制台可视化自检徽章
                    console.log(
                        '%c AIStudio 极速引擎 %c 视口裁剪: 运行中 | 排版隔离: 已生效 | 日志静默: 拦截中 ',
                        'background: #1a73e8; color: #fff; padding: 3px 6px; border-radius: 4px 0 0 4px; font-weight: bold;',
                        'background: #202124; color: #00ff88; padding: 3px 6px; border-radius: 0 4px 4px 0;'
                    );
                }
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', startEngine);
            } else {
                startEngine();
            }
        })();
        """
        userContent.addUserScript(WKUserScript(source: githubOptimizerEngine, injectionTime: .atDocumentEnd, forMainFrameOnly: false))

        // 3. 增强版 CSS 隔离
        let advancedTuningCSS = """
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

        pre code {
            text-rendering: optimizeSpeed !important;
        }

        .chat-history, .prompt-history, ms-prompt-history {
            will-change: transform;
            transform: translateZ(0);
        }
        """

        let escapedCSS = advancedTuningCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let safeScriptSource = """
        (function() {
            const s = document.createElement('style');
            s.textContent = `\(escapedCSS)`;
            (document.head || document.documentElement).appendChild(s);
        })();
        """
        userContent.addUserScript(WKUserScript(source: safeScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false))

        self.webView = LocalizedWKWebView(frame: .zero, configuration: config)
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self

        self.webView.wantsLayer = true
        self.webView.layer?.drawsAsynchronously = true

        self.webView.isInspectable = true
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

        // 会话记忆自动恢复：优先恢复上次编辑的具体 Prompt URL
        let lastURLString = UserDefaults.standard.string(forKey: "AIStudioLastVisitedURL") ?? "https://aistudio.google.com"
        let targetURL = URL(string: lastURLString) ?? URL(string: "https://aistudio.google.com")!
        self.webView.load(URLRequest(url: targetURL))
    }

    // 记录用户正在访问的有效工作区 URL
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let currentURL = webView.url?.absoluteString else { return }
        // 排除登录和过渡跳转，仅记住真正的 AI Studio 会话
        if !currentURL.contains("accounts.google.com") && !currentURL.contains("ServiceLogin") {
            UserDefaults.standard.set(currentURL, forKey: "AIStudioLastVisitedURL")
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

// MARK: - 遵循 macOS 26 官方标准的 Liquid Glass 动态图标引擎
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
        NSApp.applicationIconImage = rendermacOS26LiquidGlassIcon(isDark: isDarkMode)
    }

    private static func rendermacOS26LiquidGlassIcon(isDark: Bool) -> NSImage {
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
        let shadowColor = isDark ? NSColor.black.withAlphaComponent(0.40).cgColor : NSColor.black.withAlphaComponent(0.16).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: shadowColor)
        ctx.addPath(squirclePath)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. 液体玻璃主体底座
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        let rgbSpace = CGColorSpaceCreateDeviceRGB()

        if isDark {
            // 深色模式：黑曜烟熏琉璃渐变
            let obsidianColors = [
                NSColor(red: 0.12, green: 0.14, blue: 0.19, alpha: 0.96).cgColor,
                NSColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 0.98).cgColor,
                NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.00).cgColor
            ]
            if let grad = CGGradient(colorsSpace: rgbSpace, colors: obsidianColors as CFArray, locations: [0.0, 0.45, 1.0]) {
                ctx.drawLinearGradient(grad, start: CGPoint(x: 256, y: 464), end: CGPoint(x: 256, y: 48), options: [])
            }

            // 内部焦散微光折射
            let glowCenter = CGPoint(x: 256, y: 256)
            let glowColors = [
                NSColor(red: 0.25, green: 0.40, blue: 0.70, alpha: 0.14).cgColor,
                NSColor(red: 0.10, green: 0.15, blue: 0.35, alpha: 0.00).cgColor
            ]
            if let radialGrad = CGGradient(colorsSpace: rgbSpace, colors: glowColors as CFArray, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(radialGrad, startCenter: glowCenter, startRadius: 10, endCenter: glowCenter, endRadius: 180, options: [])
            }
        } else {
            // 亮色模式：实体纯净白底
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(baseRect)
        }

        // 3. 菲涅尔边缘高光环
        let rimPath = CGPath(roundedRect: baseRect.insetBy(dx: 2, dy: 2), cornerWidth: 102, cornerHeight: 102, transform: nil)
        ctx.setLineWidth(2.2)
        if isDark {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.24).cgColor)
        } else {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.06).cgColor)
        }
        ctx.addPath(rimPath)
        ctx.strokePath()

        // 4. 三排文字排版
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center

        // 第一排: Google
        let googleColor = isDark ? NSColor(white: 0.94, alpha: 1.0) : NSColor(white: 0.08, alpha: 1.0)
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
        let studioColor = isDark ? NSColor(white: 0.90, alpha: 1.0) : NSColor(white: 0.12, alpha: 1.0)
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
