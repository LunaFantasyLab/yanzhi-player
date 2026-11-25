// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

@main
struct GlassPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // 更新流程测试副本（com.tanco.glassplayer.updatetest）被 Sparkle 装好、重启后：记下自己的版本就退出，
        // 不加载播放列表、不读写任何播放器数据
        if let id = Bundle.main.bundleIdentifier, id.hasSuffix(".updatetest"), !UserDefaults.standard.bool(forKey: "selfTest") {
            if let marker = Bundle.main.object(forInfoDictionaryKey: "LiuliUpdateTestMarker") as? String {
                let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                try? "relaunched version=\(v) build=\(b) pid=\(getpid()) path=\(Bundle.main.bundlePath) at=\(Date())\n".write(toFile: marker, atomically: true, encoding: .utf8)
            }
            exit(0)
        }
    }

    var body: some Scene {
        Window("胭脂", id: "main") {
            RootView()
                .environment(delegate.player)
                // SwiftUI 生命周期下，访达「打开方式」/ 拖到 Dock 图标 的文件有时只走 onOpenURL
                .onOpenURL { url in delegate.receive([url]) }
        }
        // 从访达「打开方式」冷启动时，AppKit 会把它当成“打开文档”启动，SwiftUI 默认就不弹主窗口了；这里强制启动即显示
        .defaultLaunchBehavior(.presented)
        .windowStyle(.hiddenTitleBar)
        // 宣传片同款 21:9 影院级宽幅比例（1540 × 660 = 21 : 9），默认居中呈现
        .defaultSize(width: 1540, height: 660)
        .commands { AppCommands(player: delegate.player, refresher: delegate.menuRefresher) }

        Settings {
            SettingsView().environment(delegate.player)
        }
    }
}

/// 菜单栏内容放在一个 View 里生成：View 的 body 会被 Observation 追踪，
/// 状态（有无曲目、是否在放视频…）一变，菜单的可用/勾选状态就跟着刷新。
/// （直接在 Commands.body 里读状态不会被追踪，菜单会一直停在启动时的样子——2026-11-18 自测发现）
struct LiveMenu: View {
    var tick: Int = 0
    let build: @MainActor () -> [MenuNode]
    var body: some View { MenuContent(nodes: build()) }
}

/// SwiftUI 的菜单栏（Commands）不会跟着 @Observable 状态自动刷新——
/// 这里用 Observation 盯住“生成全部菜单时读到的所有状态”，一有变化就把 tick +1（合并到 0.12 秒一次），
/// Commands 通过 @ObservedObject 看到 tick 变了就整体重建，于是可用/勾选状态始终是最新的。
@MainActor
final class MenuRefresher: ObservableObject {
    @Published var tick = 0
    private weak var p: PlayerController?
    private var pending: Task<Void, Never>?
    func start(_ p: PlayerController) {
        self.p = p; track()
        // 右键（含 Control+点按）、打开菜单栏之前：先让菜单里的卡片标题跟上当前状态（见 PlayerController.menuCard）
        cardSyncMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak p] e in
            if e.type == .rightMouseDown || e.modifierFlags.contains(.control) { p?.syncMenuCardNow() }
            return e
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak p] _ in
            MainActor.assumeIsolated { p?.syncMenuCardNow() }
        }
    }
    private var cardSyncMonitor: Any?
    private func track() {
        guard let p else { return }
        withObservationTracking {
            for g in [MenuCatalog.file(p), MenuCatalog.edit(p), MenuCatalog.playback(p), MenuCatalog.audio(p), MenuCatalog.video(p),
                      MenuCatalog.playlist(p), MenuCatalog.view(p), MenuCatalog.window(p), MenuCatalog.help(p)] { _ = g.count }
        } onChange: { [weak self] in
            Task { @MainActor in self?.schedule() }
        }
    }
    private func schedule() {
        pending?.cancel()
        pending = after(0.8) { [weak self] in
            guard let self else { return }
            // 卡片 / 磨砂层刚动过（0.8 秒内）：再等一会儿，不在过渡动画中途重建整套菜单
            if let p = self.p, CACurrentMediaTime() - p.lastCardChange < 0.8 { self.pending = nil; self.schedule(); return }
            self.pending = nil
            self.tick &+= 1
            self.track()
        }
    }
}

struct AppCommands: Commands {
    let player: PlayerController
    @ObservedObject var refresher: MenuRefresher
    var body: some Commands {
        // 琉璃 ▸ 检查更新…（只有点了才联网）
        CommandGroup(after: .appInfo) { Button("检查更新…") { UpdateModel.shared.checkNow() } }
        // 文件
        CommandGroup(replacing: .newItem) { LiveMenu(tick: refresher.tick) { MenuCatalog.file(player) } }
        // 编辑：系统的撤销/拷贝/粘贴之后，加上与曲目相关的项
        CommandGroup(after: .pasteboard) { Divider(); LiveMenu(tick: refresher.tick) { MenuCatalog.edit(player) } }
        CommandMenu("播放") { LiveMenu(tick: refresher.tick) { MenuCatalog.playback(player) } }
        CommandMenu("音频") { LiveMenu(tick: refresher.tick) { MenuCatalog.audio(player) } }
        CommandMenu("视频") { LiveMenu(tick: refresher.tick) { MenuCatalog.video(player) } }
        CommandMenu("播放列表") { LiveMenu(tick: refresher.tick) { MenuCatalog.playlist(player) } }
        // 显示
        CommandGroup(before: .toolbar) { LiveMenu(tick: refresher.tick) { MenuCatalog.view(player) }; Divider() }
        // 窗口
        CommandGroup(after: .windowArrangement) { Divider(); LiveMenu(tick: refresher.tick) { MenuCatalog.window(player) } }
        // 帮助
        CommandGroup(replacing: .help) { LiveMenu(tick: refresher.tick) { MenuCatalog.help(player) } }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor lazy var player = PlayerController()
    @MainActor lazy var menuRefresher: MenuRefresher = { let r = MenuRefresher(); r.start(player); return r }()
    @MainActor private lazy var mainWindowDelegate = MainWindowDelegate(player: player)
    private var keyMonitor: Any?
    private var keyUpMonitor: Any?
    private var scrollMonitor: Any?
    private var moveMonitor: Any?
    private var pendingOpen: [URL] = []
    private var didLaunch = false
    private var openTask: Task<Void, Never>?
    private var selfTest: SelfTest?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)   // 玻璃界面按深色设计
        installKeyMonitor()
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] e in
            self?.player.pokeChrome(); return e
        }
        didLaunch = true
        // 调试/截图用：-startTab equalizer|playlist（只读参数域，不写入偏好）
        if let t = UserDefaults.standard.string(forKey: "startTab"), let tab = MainTab(rawValue: t) { player.tab = tab }
        // 沙盒截图用：-startTheme <rawValue>、-startMuted YES（只在 -testSandbox 下生效，偏好只记内存，不写本人设置）
        if Prefs.sandbox {
            if let raw = UserDefaults.standard.string(forKey: "startTheme"), let th = AppTheme(rawValue: raw) { player.setTheme(th) }
            if UserDefaults.standard.bool(forKey: "startMuted"), !player.muted { player.toggleMute() }
        }
        if let pid = UserDefaults.standard.string(forKey: "applyPreset"), let pr = player.allPresets.first(where: { $0.id == pid }) {
            after(1.0) { [weak self] in self?.player.applyPreset(pr) }      // 冒烟测试用：启动后套用某个均衡器预设
        }
        if UserDefaults.standard.bool(forKey: "startLifted") { after(1.5) { [weak self] in withAnimation(Motion.lift) { self?.player.isLifted = true } } }
        if !pendingOpen.isEmpty { player.open(pendingOpen, playNow: true); pendingOpen = [] }
        if TestHooks.active { selfTest = SelfTest(player); selfTest?.run() }
        DispatchQueue.main.async { self.styleWindows() }
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        // Finder「打开方式」/ 拖到 Dock 图标
        receive(urls)
    }

    /// 外部打开的文件：短时间内到达的多批合并成一次（访达多选打开时会分几次送达）
    @MainActor
    func receive(_ urls: [URL]) {
        NSLog("GlassPlayer open: %@", urls.map(\.path).joined(separator: " | "))
        pendingOpen += urls.filter(\.isFileURL)
        guard NSApp.isRunning, didLaunch else { return }
        openTask?.cancel()
        openTask = after(0.15) { [weak self] in
            guard let self, !self.pendingOpen.isEmpty else { return }
            let batch = self.pendingOpen; self.pendingOpen = []
            self.player.open(batch, playNow: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { player.closeAction == .quit }
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let w = player.mainWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        }
        return true
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) { player.prepareForQuit() }

    @MainActor
    private func styleWindows() {
        for w in NSApp.windows where w.contentView != nil {
            let isMain = w.identifier?.rawValue.hasPrefix("main") == true
            if isMain {
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.styleMask.insert(.fullSizeContentView)
                w.isMovableByWindowBackground = false   // 窗口空白处的拖动留给轮播
                w.backgroundColor = .black
                w.isOpaque = true
                w.collectionBehavior.insert(.fullScreenPrimary)
                w.tabbingMode = .disallowed
                if w.delegate !== mainWindowDelegate {
                    mainWindowDelegate.forwarded = w.delegate
                    w.delegate = mainWindowDelegate
                }
                adopt21x9IfUntouched(w)
            }
        }
    }

    /// 11-23 规范：默认窗口改为 21:9（1540×660）。SwiftUI 会恢复上次保存的窗口尺寸，老用户升级后看不到新默认；
    /// 这里只迁移一次，而且只迁移「仍是旧默认 1180×760、从没手动调过」的窗口；调过尺寸、全屏、屏幕放不下的都不动。
    @MainActor
    private func adopt21x9IfUntouched(_ w: NSWindow) {
        guard w.identifier?.rawValue.hasPrefix("main") == true, !Prefs.bool("adopted21x9") else { return }
        Prefs.set(true, "adopted21x9")
        let f = w.frame
        guard abs(f.width - 1180) < 1, abs(f.height - 760) < 1, !w.styleMask.contains(.fullScreen),
              let vf = w.screen?.visibleFrame, vf.width >= 1540, vf.height >= 660 else { return }
        w.setFrame(NSRect(x: (vf.midX - 770).rounded(), y: (vf.midY - 330).rounded(), width: 1540, height: 660), display: true)
    }

    @MainActor
    private func installKeyMonitor() {
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 123 { self.player.arrowKeyUp(-1) } else if e.keyCode == 124 { self.player.arrowKeyUp(1) }
            return e
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            // 正在输入文字（比如给预设起名）时不拦截
            if let r = NSApp.keyWindow?.firstResponder as? NSTextView {
                // 输入框里按 Esc：卡片 / 快捷键面板开着时，照样一层层退（不会卡在输入框里出不去）
                if e.keyCode == 53, (NSApp.keyWindow ?? e.window) === self.player.mainWindow, self.player.activeCard != nil || self.player.showShortcuts || self.player.tagEditorOpen || self.player.isRenamingPlaylist {
                    NSApp.keyWindow?.makeFirstResponder(nil); self.player.escapeOnce(); return nil
                }
                // 菜单里有不带修饰键的快捷键（空格、方向键、[ ] F …）；正在输入时把按键直接交给输入框，避免被菜单抢走
                let bare: Set<UInt16> = [49, 123, 124, 125, 126]           // 空格、方向键
                let chars: Set<String> = ["[", "]", "\\", "f", "F"]
                if e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                   bare.contains(e.keyCode) || chars.contains(e.charactersIgnoringModifiers ?? "") { r.keyDown(with: e); return nil }
                return e
            }
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            let p = self.player
            // 封面观赏模式里：Esc 一层层退、⌘+ ⌘- ⌘0 缩放、F 全屏观赏；单击封面或空白立即退出；空格、方向键照常
            if p.viewer.isOpen, (NSApp.keyWindow ?? e.window) === p.mainWindow, p.viewerHandleKey(e) { return nil }
            switch e.keyCode {
            case 49 where mods.isEmpty: p.togglePlay(); return nil                         // 空格
            case 123 where mods.isEmpty: p.arrowKeyDown(-1, isRepeat: e.isARepeat); return nil   // ←：按一下退 15 秒，按住连续快退
            case 124 where mods.isEmpty: p.arrowKeyDown(1, isRepeat: e.isARepeat); return nil    // →：按一下进 15 秒，按住连续快进
            case 126 where mods.isEmpty: p.setVolume(p.volume + 5, showsHUD: true); return nil   // ↑
            case 125 where mods.isEmpty: p.setVolume(p.volume - 5, showsHUD: true); return nil   // ↓
            case 53 where mods.isEmpty:                                                   // esc：一层层退（表见 ExitState）
                // 设置窗口、检查更新小窗这类附属窗口：Esc 关掉它自己
                // 只认这两种窗口，主窗口（不管 SwiftUI 怎么给它起名）绝不会被 Esc 关掉
                if let k = NSApp.keyWindow, k !== p.mainWindow, k.identifier?.rawValue.hasPrefix("main") != true,
                   k.title == "检查更新" || k.identifier?.rawValue == "update" || (k.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false) {
                    TestHooks.log("  Esc 关掉附属窗口「\(k.title)」（\(k.identifier?.rawValue ?? "-")）")
                    k.performClose(nil); return nil
                }
                return p.escapeOnce() != nil ? nil : e
            case 36 where mods.isEmpty:                                                   // 回车：抬起/放下中心卡
                if p.tab == .nowPlaying && p.isVideo && p.videoStageDismissed { p.enterVideoStage(); if !p.isPlaying { p.play() }; return nil }   // 轮播停在视频卡上：回到视频舞台
                if p.tab == .nowPlaying && !p.isVideo { p.pendingCardWork?.cancel(); p.pendingCardClick = nil; withAnimation(Motion.lift) { p.isLifted.toggle() }; return nil }
                return e
            default: break
            }
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "y" where mods == [.command] && (NSApp.keyWindow ?? e.window) === p.mainWindow:   // ⌘Y：观赏封面（菜单里也有；这里直接接住，免得菜单还没刷新时按了没反应）
                p.toggleCoverViewer(); return nil
            case "f" where mods.isEmpty: p.toggleFullScreen(); return nil
            case "m" where mods.isEmpty: p.setMuted(!p.muted); p.showHUD(p.muted ? "speaker.slash" : "speaker.wave.2", p.muted ? "静音" : "取消静音"); return nil
            case "e" where mods.isEmpty: withAnimation(Motion.tab) { p.tab = p.tab == .equalizer ? .nowPlaying : .equalizer }; return nil
            case "l" where mods.isEmpty: withAnimation(Motion.tab) { p.tab = p.tab == .playlist ? .nowPlaying : .playlist }; return nil
            case "[" where mods.isEmpty: p.speedStep(-0.01); return nil
            case "]" where mods.isEmpty: p.speedStep(0.01); return nil
            case "," where mods.isEmpty: p.carouselStep(-1); return nil
            case "." where mods.isEmpty: p.carouselStep(1); return nil
            default: return e
            }
        }
    }
}

/// 主窗 / 迷你窗系统红绿灯代理（保留并转发原有 SwiftUI delegate，不影响窗口状态恢复）：
/// - 关闭按钮按设置项「关闭窗口时」执行「最小化」或「彻底退出」
/// - 迷你窗点击绿色最大化按钮时平滑展开回主窗
@MainActor
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    private weak var player: PlayerController?
    weak var forwarded: (any NSWindowDelegate)?
    init(player: PlayerController) { self.player = player }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let player else { return true }
        switch player.closeAction {
        case .minimize:
            sender.miniaturize(nil)
            return false
        case .quit:
            NSApp.terminate(nil)
            return true
        }
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard let player, player.isPinnedMini else {
            return forwarded?.windowShouldZoom?(window, toFrame: newFrame) ?? true
        }
        player.togglePinnedMini()
        return false
    }

    func windowDidResize(_ notification: Notification) { forwarded?.windowDidResize?(notification) }
    func windowDidMove(_ notification: Notification) { forwarded?.windowDidMove?(notification) }
    func windowDidBecomeKey(_ notification: Notification) { forwarded?.windowDidBecomeKey?(notification) }
    func windowDidResignKey(_ notification: Notification) { forwarded?.windowDidResignKey?(notification) }
    func windowDidEnterFullScreen(_ notification: Notification) { forwarded?.windowDidEnterFullScreen?(notification) }
    func windowDidExitFullScreen(_ notification: Notification) { forwarded?.windowDidExitFullScreen?(notification) }
    func windowWillClose(_ notification: Notification) { forwarded?.windowWillClose?(notification) }
}
