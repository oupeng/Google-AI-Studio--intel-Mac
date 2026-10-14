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
                .background(WindowFrameAccessor())
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

// MARK: - 原生窗口状态与 4K 实体化优化器
struct WindowFrameAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.setFrameAutosaveName("AIStudioMainWindowAutosaveFrame")
                window.isRestorable = true
                window.isOpaque = true
                window.backgroundColor = NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1.0)
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

// MARK: - WebKit 调优管理器（修复图标裁切 + 意图感知自动复位）
@MainActor
final class WebViewModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    var webView: LocalizedWKWebView!

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContent = config.userContentController

        // 1. 原型链级网络日志屏蔽
        let protoMuterScript = """
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

            if (window.Navigator && Navigator.prototype) {
                const origProtoBeacon = Navigator.prototype.sendBeacon;
                Navigator.prototype.sendBeacon = function(url, data) {
                    if (isLogUrl(url)) return true;
                    return origProtoBeacon.apply(this, arguments);
                };
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

            const origOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (isLogUrl(url)) this._isMutedLog = true;
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
        userContent.addUserScript(WKUserScript(source: protoMuterScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        // 2. 打字意图感知自动复位引擎（翻阅放行，打字一瞬间自动收起提速）
        let typingAwareEngineScript = """
        (function() {
            const MAX_VISIBLE = 6;
            let userExpanded = false;
            let debounceTimer = null;

            function autoOptimize(forcePrune = false) {
                const items = document.querySelectorAll('ms-chat-turn, .chat-turn, ms-prompt-node, .prompt-node, mat-expansion-panel');
                if (!items || items.length <= MAX_VISIBLE) {
                    removeExpandBar();
                    return;
                }

                const cutoff = items.length - MAX_VISIBLE;

                if (forcePrune || !userExpanded) {
                    for (let i = 0; i < cutoff; i++) {
                        items[i].style.setProperty('display', 'none', 'important');
                    }
                    for (let i = cutoff; i < items.length; i++) {
                        items[i].style.removeProperty('display');
                    }
                    renderExpandBar(cutoff, items[cutoff], false);
                } else {
                    for (let i = 0; i < items.length; i++) {
                        items[i].style.removeProperty('display');
                    }
                    renderExpandBar(cutoff, items[0], true);
                }
            }

            // 监听打字意图：光标回输入框或按键时，瞬间恢复极速
            function bindTypingSensors() {
                function triggerFastTypingMode(e) {
                    const target = e.target;
                    if (target && (target.tagName === 'TEXTAREA' || target.isContentEditable || target.getAttribute('role') === 'textbox' || target.closest('.input-container'))) {
                        if (userExpanded) {
                            userExpanded = false;
                            autoOptimize(true);
                        }
                    }
                }
                document.addEventListener('focusin', triggerFastTypingMode, true);
                document.addEventListener('keydown', triggerFastTypingMode, true);
            }

            function renderExpandBar(hiddenCount, referenceNode, isExpanded) {
                if (!referenceNode || !referenceNode.parentNode) return;

                let bar = document.getElementById('aistudio-history-toggle-bar');
                if (!bar) {
                    bar = document.createElement('div');
                    bar.id = 'aistudio-history-toggle-bar';
                    bar.style.cssText = 'text-align: center; padding: 10px 14px; margin: 16px auto; cursor: pointer; color: #8ab4f8; font-size: 13px; font-weight: 600; background: rgba(138, 180, 248, 0.08); border-radius: 10px; border: 1px dashed rgba(138, 180, 248, 0.35); max-width: 620px; transition: background 0.2s; user-select: none;';
                    bar.onmouseover = () => bar.style.background = 'rgba(138, 180, 248, 0.16)';
                    bar.onmouseout = () => bar.style.background = 'rgba(138, 180, 248, 0.08)';
                    bar.onclick = () => {
                        userExpanded = !userExpanded;
                        autoOptimize();
                    };
                    referenceNode.parentNode.insertBefore(bar, referenceNode);
                }

                if (isExpanded) {
                    bar.textContent = '⚡ 已展开全部历史 (点击此处或直接点击输入框打字以恢复极速)';
                    bar.style.borderColor = '#00ff88';
                    bar.style.color = '#00ff88';
                } else {
                    bar.textContent = `📜 已自动折叠更早的 ${hiddenCount} 条历史 (点击展开回看全部，平时折叠保持打字极速)`;
                    bar.style.borderColor = 'rgba(138, 180, 248, 0.35)';
                    bar.style.color = '#8ab4f8';
                }
            }

            function removeExpandBar() {
                const bar = document.getElementById('aistudio-history-toggle-bar');
                if (bar) bar.remove();
            }

            const observer = new MutationObserver(() => {
                if (debounceTimer) clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => autoOptimize(false), 300);
            });

            function start() {
                const target = document.body || document.documentElement;
                if (target) {
                    observer.observe(target, { childList: true, subtree: true });
                    setInterval(() => autoOptimize(false), 2000);
                    bindTypingSensors();
                    autoOptimize(false);
                    console.log('%c🚀 [AIStudio Native Engine] 意图感知加速引擎已就绪！', 'color: #00ff88; font-weight: bold; font-size: 12px;');
                }
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', start);
            } else {
                start();
            }
        })();
        """
        userContent.addUserScript(WKUserScript(source: typingAwareEngineScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))

        // 3. 关键修复：剔除 paint，增加 overflow: visible，绝不裁切消息框外的悬浮操作按钮
        let nonClippingCSS = """
        ms-chat-turn, .chat-turn, ms-prompt-node, .prompt-node, .history-container > *, ms-run-chunk, .chat-chunk, mat-expansion-panel {
            content-visibility: auto !important;
            contain-intrinsic-size: 80px 240px !important;
            overflow: visible !important; /* 关键：确保 Rerun 和铅笔悬浮工具栏完整显示 */
        }

        /* 纯排版隔离：去掉 paint 属性，锁死重排的同时，坚决不裁切悬浮元素 */
        textarea, [contenteditable="true"], .prompt-editor, ms-prompt-editor, [role="textbox"], .input-container {
            contain: layout style !important;
            spellcheck: false !important;
            autocorrect: off !important;
            autocapitalize: off !important;
        }

        .chat-history *, .prompt-history * {
            transition: none !important;
        }
        """

        let escapedCSS = nonClippingCSS
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

        self.webView.isInspectable = true
        if #available(macOS 12.0, *) {
            self.webView.underPageBackgroundColor = NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1.0)
        }

        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

        let lastURLString = UserDefaults.standard.string(forKey: "AIStudioLastVisitedURL") ?? "https://aistudio.google.com"
        let targetURL = URL(string: lastURLString) ?? URL(string: "https://aistudio.google.com")!
        self.webView.load(URLRequest(url: targetURL))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let currentURL = webView.url?.absoluteString else { return }
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

// MARK: - 动态 Liquid Glass 文字图标引擎
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

        ctx.saveGState()
        let shadowColor = isDark ? NSColor.black.withAlphaComponent(0.40).cgColor : NSColor.black.withAlphaComponent(0.16).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: shadowColor)
        ctx.addPath(squirclePath)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        let rgbSpace = CGColorSpaceCreateDeviceRGB()

        if isDark {
            let obsidianColors = [
                NSColor(red: 0.12, green: 0.14, blue: 0.19, alpha: 0.96).cgColor,
                NSColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 0.98).cgColor,
                NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.00).cgColor
            ]
            if let grad = CGGradient(colorsSpace: rgbSpace, colors: obsidianColors as CFArray, locations: [0.0, 0.45, 1.0]) {
                ctx.drawLinearGradient(grad, start: CGPoint(x: 256, y: 464), end: CGPoint(x: 256, y: 48), options: [])
            }

            let glowCenter = CGPoint(x: 256, y: 256)
            let glowColors = [
                NSColor(red: 0.25, green: 0.40, blue: 0.70, alpha: 0.14).cgColor,
                NSColor(red: 0.10, green: 0.15, blue: 0.35, alpha: 0.00).cgColor
            ]
            if let radialGrad = CGGradient(colorsSpace: rgbSpace, colors: glowColors as CFArray, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(radialGrad, startCenter: glowCenter, startRadius: 10, endCenter: glowCenter, endRadius: 180, options: [])
            }
        } else {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(baseRect)
        }

        let rimPath = CGPath(roundedRect: baseRect.insetBy(dx: 2, dy: 2), cornerWidth: 102, cornerHeight: 102, transform: nil)
        ctx.setLineWidth(2.2)
        if isDark {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.24).cgColor)
        } else {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.06).cgColor)
        }
        ctx.addPath(rimPath)
        ctx.strokePath()

        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center

        let googleColor = isDark ? NSColor(white: 0.94, alpha: 1.0) : NSColor(white: 0.08, alpha: 1.0)
        let googleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 66, weight: .heavy),
            .foregroundColor: googleColor,
            .paragraphStyle: pStyle,
            .kern: 0.2
        ]
        "Google".draw(in: CGRect(x: 48, y: 320, width: 416, height: 76), withAttributes: googleAttrs)

        let aiColor = isDark ? NSColor.white : NSColor.black
        let aiAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 96, weight: .black),
            .foregroundColor: aiColor,
            .paragraphStyle: pStyle,
            .kern: 2.5
        ]
        "AI".draw(in: CGRect(x: 48, y: 206, width: 416, height: 106), withAttributes: aiAttrs)

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
