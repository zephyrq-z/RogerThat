import AppKit

// ponytail: 只轮询 changeCount，不监听按键、不读内容 —— 零权限。
// 轮询周期 0.15s 是「够快 + 不费电」的经验值。
final class PasteboardWatcher {
    private let pasteboard: NSPasteboard
    private var last: Int
    private var timer: Timer?
    var onChange: (() -> Void)?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.last = pasteboard.changeCount   // 基线：启动时不误报
    }

    func start(interval: TimeInterval = 0.15) {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func tick() {
        let now = pasteboard.changeCount
        guard now != last else { return }
        last = now
        onChange?()
    }
}

// MARK: - 浮层

final class Toast {
    let panel: NSPanel
    private let box = NSView()
    let label = NSTextField(labelWithString: "Copied")
    private let icon = NSImageView()
    private var hideWork: DispatchWorkItem?

    private let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private let height: CGFloat = 22
    private let padX: CGFloat = 11
    private let gap: CGFloat = 5
    private let iconSide: CGFloat = 10

    // ponytail: 不用 NSVisualEffectView —— 毛玻璃在圆角外会露出灰边/黑线，纯色层 + mask 最干净
    private let green = NSColor(srgbRed: 0.027, green: 0.757, blue: 0.376, alpha: 1)   // 微信绿 #07C160

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 90, height: 22),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        // .nonactivatingPanel 已保证不抢焦点（NSPanel 的 canBecomeKey 是只读的）
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.alphaValue = 0

        box.wantsLayer = true
        box.layer?.backgroundColor = green.cgColor
        box.layer?.cornerRadius = height / 2      // 胶囊
        box.layer?.masksToBounds = true
        box.layer?.borderWidth = 0

        icon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: iconSide, weight: .bold))
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyDown

        label.font = font
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail

        box.addSubview(icon)
        box.addSubview(label)
        panel.contentView = box
    }

    /// 文字有没有被截断（渲染测试用）
    var fitsWithoutTruncation: Bool {
        guard let cell = label.cell else { return true }
        return cell.cellSize.width <= label.frame.width + 0.5
    }

    func show(_ text: String, seconds: TimeInterval = 1.1, on forced: NSScreen? = nil) {
        label.stringValue = text
        label.sizeToFit()                                   // 用 AppKit 自己的适合宽度，别手算（会少算半个字形，显示成 "Copi…"）
        let textSize = label.frame.size
        let textW = min(max(textSize.width, 20), 260)
        let contentW = iconSide + gap + textW
        let w = contentW + padX * 2
        let startX = (w - contentW) / 2                       // 图标+文字整体居中，左右留白一致
        icon.frame = NSRect(x: startX, y: (height - iconSide) / 2, width: iconSide, height: iconSide)
        // 按文字实际高度居中，NSTextField 用满高会略偏上
        label.frame = NSRect(x: startX + iconSide + gap,
                             y: (height - textSize.height) / 2,
                             width: textW, height: textSize.height)
        box.frame = NSRect(x: 0, y: 0, width: w, height: height)

        // 跟随鼠标所在的屏幕，浮在光标右下方，越界就夹回可见区域
        let mouse = NSEvent.mouseLocation
        let screen = forced ?? NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = forced == nil ? min(mouse.x + 8, vf.maxX - w - 8) : vf.midX - w / 2
        let y = forced == nil ? max(mouse.y - height - 12, vf.minY + 8) : vf.minY + 80
        panel.setFrame(NSRect(x: x, y: y, width: w, height: height), display: true)

        hideWork?.cancel()
        if panel.alphaValue < 1 {
            panel.orderFrontRegardless()    // 不用 makeKey，避免抢前台
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
        NSLog("rogertthat: toast w=\(w) frame=\(panel.frame)")

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.panel.animator().alphaValue = 0
            } completionHandler: {
                self.panel.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

// MARK: - App

final class Controller: NSObject, NSApplicationDelegate {
    private let watcher = PasteboardWatcher()
    private let toast = Toast()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var switches: [NSSwitch] = []
    private let defaults = UserDefaults.standard

    private var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    private var preview: Bool {
        get { defaults.object(forKey: "preview") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "preview") }
    }
    private var showInMenuBar: Bool {
        get { defaults.object(forKey: "showInMenuBar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showInMenuBar") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        watcher.onChange = { [weak self] in
            guard let self, self.enabled else { return }
            self.toast.show(self.message())
        }
        watcher.start()
        syncMenuBarItem()
        showSettings()      // 启动就露面：菜单栏图标藏起来也知道它活着
    }

    private func message() -> String {
        guard preview, let text = NSPasteboard.general.string(forType: .string) else { return "Copied" }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.isEmpty ? "Copied" : "Copied  " + String(flat.prefix(40))
    }

    // MARK: 菜单栏

    private func syncMenuBarItem() {
        if showInMenuBar {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                        accessibilityDescription: "RogerThat")
            let menu = NSMenu()
            let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            settings.target = self
            menu.addItem(settings)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit RogerThat",
                                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        NSLog("rogertthat: menubar shown=\(statusItem != nil)")
    }

    @objc private func openSettings() { showSettings() }

    /// 测试钩子：把菜单栏图标的加/摘各跑一遍（默认开着 → 摘掉 → 再加回）
    func runMenuBarTest() {
        let saved = showInMenuBar
        showInMenuBar = true;  syncMenuBarItem()
        showInMenuBar = false; syncMenuBarItem()
        showInMenuBar = true;  syncMenuBarItem()
        showInMenuBar = saved; syncMenuBarItem()
        exit(0)
    }

    // MARK: 设置界面

    private func showSettings() {
        if settingsWindow == nil { settingsWindow = makeSettingsWindow() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSLog("rogertthat: settings visible=\(settingsWindow?.isVisible ?? false) key=\(settingsWindow?.isKeyWindow ?? false)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSLog("rogertthat: settings key-later=\(self.settingsWindow?.isKeyWindow ?? false) main=\(self.settingsWindow?.isMainWindow ?? false)")
        }
    }

    private func makeSettingsWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 172),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "RogerThat"
        win.isReleasedWhenClosed = false
        win.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let rows: [(String, Bool, Selector)] = [
            ("Show notification", enabled, #selector(toggleEnabled(_:))),
            ("Show copied text", preview, #selector(togglePreview(_:))),
            ("Show menu bar icon", showInMenuBar, #selector(toggleMenuBar(_:))),
        ]
        for (title, on, action) in rows {
            let sw = NSSwitch()
            sw.state = on ? .on : .off
            sw.target = self
            sw.action = action
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13)
            let row = NSStackView(views: [label, sw])
            row.orientation = .horizontal
            row.spacing = 8
            row.distribution = .fill
            switches.append(sw)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let quit = NSButton(title: "Quit RogerThat", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        stack.addArrangedSubview(quit)

        win.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: win.contentView!.topAnchor, constant: 18),
        ])
        return win
    }

    @objc private func toggleEnabled(_ s: NSSwitch) { enabled = s.state == .on }
    @objc private func togglePreview(_ s: NSSwitch) { preview = s.state == .on }
    @objc private func toggleMenuBar(_ s: NSSwitch) {
        showInMenuBar = s.state == .on
        syncMenuBarItem()
    }
}

// MARK: - 自检（不碰用户的通用剪贴板）

func selftest() -> Never {
    let pb = NSPasteboard(name: NSPasteboard.Name("RogerThatSelfTest"))
    pb.clearContents()
    var hits = 0
    let w = PasteboardWatcher(pasteboard: pb)
    w.onChange = { hits += 1 }

    w.tick(); assert(hits == 0, "基线不该触发")
    pb.clearContents()
    pb.setString("a", forType: .string)
    w.tick(); assert(hits == 1, "变化应触发一次")
    w.tick(); assert(hits == 1, "同一状态不该重复触发")
    pb.clearContents()
    pb.setString("b", forType: .string)
    w.tick(); assert(hits == 2, "再次变化应再触发")
    print("selftest ok")
    exit(0)
}

let args = CommandLine.arguments
if args.contains("--selftest") { selftest() }
if args.contains("--menubar-test") {   // 验证菜单栏图标能加上也能摘掉
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let c = Controller()
    c.runMenuBarTest()
    app.run()
}
if args.contains("--toast-test") {           // 只验证浮层，不碰剪贴板
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let toast = Toast()
    for i in 0..<25 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(i) * 1.2) {
            toast.show("Copied", on: NSScreen.screens[0])   // 测试固定放内置屏，便于截图验证
            NSLog("rogertthat: toast")
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 32) { exit(0) }
    app.run()
}
if args.contains("--render-test") {          // 把浮层渲染成 PNG，检查内容是否画得出来
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let toast = Toast()
    toast.show("Copied", on: NSScreen.screens[0])
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        if let v = toast.panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/toast_render.png"))
            print("render written \(rep.pixelsWide)x\(rep.pixelsHigh) fits=\(toast.fitsWithoutTruncation) labelW=\(toast.label.frame.width)")
        }
        exit(0)
    }
    app.run()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.delegate = controller
app.run()