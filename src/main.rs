use muda::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::WindowBuilder,
};
use wry::WebViewBuilder;

const TELEMETRY_MUTE_JS: &str = r#"
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
            return str.indexOf('play.google.com/log') !== -1 || str.indexOf('telemetry') !== -1;
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
"#;

const FAST_TYPING_ENGINE_JS: &str = r#"
(function() {
    const MAX_VISIBLE = 6;
    let userExpanded = false;
    let debounceTimer = null;

    function disableSpellcheck() {
        const inputs = document.querySelectorAll('textarea, [contenteditable="true"], .prompt-editor, ms-prompt-editor, [role="textbox"]');
        inputs.forEach(el => {
            if (el.getAttribute('spellcheck') !== 'false') {
                el.setAttribute('spellcheck', 'false');
                el.setAttribute('autocorrect', 'off');
                el.setAttribute('autocapitalize', 'off');
            }
        });
    }

    function autoOptimize(forcePrune = false) {
        disableSpellcheck();
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
            renderExpandBar(cutoff, false);
        } else {
            for (let i = 0; i < items.length; i++) {
                items[i].style.removeProperty('display');
            }
            renderExpandBar(cutoff, true);
        }
    }

    function bindTypingSensors() {
        function triggerFastTypingMode(e) {
            const target = e.target;
            if (target && (target.tagName === 'TEXTAREA' || target.isContentEditable || target.getAttribute('role') === 'textbox' || target.closest('.input-container') || target.closest('ms-prompt-editor'))) {
                if (userExpanded) {
                    userExpanded = false;
                    autoOptimize(true);
                }
            }
        }
        document.addEventListener('focusin', triggerFastTypingMode, true);
        document.addEventListener('keydown', triggerFastTypingMode, true);
    }

    function renderExpandBar(hiddenCount, isExpanded) {
        let bar = document.getElementById('aistudio-history-toggle-bar');
        if (!bar) {
            bar = document.createElement('div');
            bar.id = 'aistudio-history-toggle-bar';
            bar.style.cssText = 'position: fixed; bottom: 80px; right: 24px; z-index: 99999; text-align: center; padding: 8px 14px; cursor: pointer; color: #8ab4f8; font-size: 12px; font-weight: 600; background: rgba(32, 33, 36, 0.92); border-radius: 20px; border: 1px solid rgba(138, 180, 248, 0.4); backdrop-filter: blur(8px); box-shadow: 0 4px 12px rgba(0,0,0,0.3); transition: all 0.2s; user-select: none;';
            bar.onmouseover = () => bar.style.background = 'rgba(48, 50, 54, 0.96)';
            bar.onmouseout = () => bar.style.background = 'rgba(32, 33, 36, 0.92)';
            bar.onclick = () => {
                userExpanded = !userExpanded;
                autoOptimize();
            };
            document.body.appendChild(bar);
        }

        if (isExpanded) {
            bar.textContent = '⚡ 已展开全部历史 (点击此处或点击输入框打字自动折叠恢复极速)';
            bar.style.borderColor = '#00ff88';
            bar.style.color = '#00ff88';
        } else {
            bar.textContent = `📜 已自动折叠更早的 ${hiddenCount} 条历史对话 (点击展开回看，打字时自动隐藏加速)`;
            bar.style.borderColor = 'rgba(138, 180, 248, 0.4)';
            bar.style.color = '#8ab4f8';
        }
    }

    function removeExpandBar() {
        const bar = document.getElementById('aistudio-history-toggle-bar');
        if (bar) bar.remove();
    }

    const style = document.createElement('style');
    style.textContent = `
        ms-chat-turn, .chat-turn, ms-prompt-node, .prompt-node, .history-container > *, ms-run-chunk, .chat-chunk, mat-expansion-panel {
            content-visibility: auto !important;
            contain-intrinsic-size: 80px 240px !important;
            overflow: visible !important;
        }

        textarea, [contenteditable="true"], .prompt-editor, ms-prompt-editor, [role="textbox"], .input-container {
            contain: layout style !important;
            spellcheck: false !important;
            autocorrect: off !important;
            autocapitalize: off !important;
        }

        .chat-history *, .prompt-history * {
            transition: none !important;
        }
    `;
    (document.head || document.documentElement).appendChild(style);

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
            console.log('🚀 [AIStudio Native Engine] 打字防卡顿加速引擎已就绪！');
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
"#;

const CHINESE_TRANSLATION_JS: &str = r#"
(function() {
    const translationMap = {
        'System Instructions': '系统指令 (System Instructions)',
        'System instructions': '系统指令 (System Instructions)',
        'Model': '模型选择',
        'Temperature': '温度 (Temperature)',
        'Safety settings': '安全设置',
        'Safety Settings': '安全设置',
        'Get code': '获取代码',
        'Get Code': '获取代码',
        'Run': '运行',
        'Save': '保存',
        'Share': '分享',
        'Clear': '清除',
        'Clear chat': '清空对话',
        'Advanced settings': '高级设置',
        'Tools': '工具扩展',
        'Google Search': 'Google 联网搜索',
        'Code Execution': '代码执行引擎',
        'Structured Output': '结构化输出',
        'Add stop sequence': '添加终止字符序列',
        'Thinking': '深度思考过程',
        'Edit prompt': '编辑提示词',
        'User': '用户',
        'Model response': '模型回复'
    };

    function translateTextNodes(node) {
        if (node.nodeType === Node.TEXT_NODE) {
            const trimmed = node.nodeValue.trim();
            if (translationMap[trimmed]) {
                node.nodeValue = node.nodeValue.replace(trimmed, translationMap[trimmed]);
            }
        } else {
            for (let child of node.childNodes) {
                if (child.nodeType === Node.ELEMENT_NODE) {
                    const tag = child.tagName.toLowerCase();
                    if (tag === 'code' || tag === 'textarea' || child.classList.contains('hljs') || child.isContentEditable) {
                        continue;
                    }
                }
                translateTextNodes(child);
            }
        }
    }

    function runTranslation() {
        translateTextNodes(document.body || document.documentElement);
    }

    const transObserver = new MutationObserver((mutations) => {
        for (let mutation of mutations) {
            for (let addedNode of mutation.addedNodes) {
                if (addedNode.nodeType === Node.ELEMENT_NODE) {
                    const tag = addedNode.tagName.toLowerCase();
                    if (tag !== 'code' && tag !== 'textarea' && !addedNode.classList.contains('hljs')) {
                        translateTextNodes(addedNode);
                    }
                }
            }
        }
    });

    function startTrans() {
        const target = document.body || document.documentElement;
        if (target) {
            transObserver.observe(target, { childList: true, subtree: true });
            setInterval(runTranslation, 2500);
            runTranslation();
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startTrans);
    } else {
        startTrans();
    }
})();
"#;

fn build_menu() -> (Menu, MenuItem, MenuItem) {
    let menu = Menu::new();

    let app_menu = Submenu::new("AIStudio", true);
    app_menu.append(&PredefinedMenuItem::quit(Some("退出 AIStudio"))).unwrap();
    menu.append(&app_menu).unwrap();

    let edit_menu = Submenu::new("编辑", true);
    edit_menu.append(&PredefinedMenuItem::undo(Some("撤销"))).unwrap();
    edit_menu.append(&PredefinedMenuItem::redo(Some("重做"))).unwrap();
    edit_menu.append(&PredefinedMenuItem::separator()).unwrap();
    edit_menu.append(&PredefinedMenuItem::cut(Some("剪切"))).unwrap();
    edit_menu.append(&PredefinedMenuItem::copy(Some("拷贝"))).unwrap();
    edit_menu.append(&PredefinedMenuItem::paste(Some("粘贴"))).unwrap();
    edit_menu.append(&PredefinedMenuItem::select_all(Some("全选"))).unwrap();
    menu.append(&edit_menu).unwrap();

    let view_menu = Submenu::new("视图与导航", true);
    let reload_item = MenuItem::new("重新加载页面", true, None);
    let force_reload_item = MenuItem::new("强制刷新 (清空缓存)", true, None);
    view_menu.append(&reload_item).unwrap();
    view_menu.append(&force_reload_item).unwrap();
    menu.append(&view_menu).unwrap();

    (menu, reload_item, force_reload_item)
}

fn main() {
    let event_loop = EventLoop::new();

    let (menu_bar, reload_item, force_reload_item) = build_menu();
    menu_bar.init_for_nsapp();

    let window = WindowBuilder::new()
        .with_title("Google AI Studio")
        .with_inner_size(tao::dpi::LogicalSize::new(1280.0, 800.0))
        .with_min_inner_size(tao::dpi::LogicalSize::new(1080.0, 700.0))
        .build(&event_loop)
        .expect("Failed to build main window");

    let combined_script = format!(
        "{}\n{}\n{}",
        TELEMETRY_MUTE_JS,
        FAST_TYPING_ENGINE_JS,
        CHINESE_TRANSLATION_JS
    );

    let webview = WebViewBuilder::new()
        .with_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15")
        .with_initialization_script(&combined_script)
        .with_url("https://aistudio.google.com")
        .expect("Failed to create webview builder")
        .build(&window)
        .expect("Failed to build WKWebView");

    let menu_channel = muda::MenuEvent::receiver();

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        if let Ok(event) = menu_channel.try_recv() {
            if event.id() == reload_item.id() {
                let _ = webview.evaluate_script("location.reload();");
            } else if event.id() == force_reload_item.id() {
                let _ = webview.evaluate_script("location.reload(true);");
            }
        }

        match event {
            Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => {
                *control_flow = ControlFlow::Exit;
            }
            _ => (),
        }
    });
}
