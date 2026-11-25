// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import AppKit
import SwiftUI
import PlayerCore

/// 自测钩子：只在启动参数 -selfTest YES 时生效。
/// 打开/保存面板、文字对话框直接用预设答案；“在访达中显示”“拷贝”不打扰本人的访达和剪贴板。
@MainActor
enum TestHooks {
    static let active = UserDefaults.standard.bool(forKey: "selfTest")
    static var outDir: URL { URL(fileURLWithPath: UserDefaults.standard.string(forKey: "testOut") ?? NSTemporaryDirectory()) }
    static var mediaDir: URL? { UserDefaults.standard.string(forKey: "testMedia").map { URL(fileURLWithPath: $0) } }
    private static var logHandle: FileHandle?

    /// 自测：下一次打开 / 添加对话框当作「取消」
    static var cancelNextPanel = false
    /// 自测：添加对话框选中的东西（只用 testout 里临时拷出来的测试文件）
    static var panelOverride: (files: [URL], folders: [URL])?
    static func openPanel(folders: Bool) -> [URL]? {
        guard active, let m = mediaDir else { return nil }
        if cancelNextPanel { cancelNextPanel = false; return [] }
        if let o = panelOverride { return folders ? o.folders : o.files }
        return folders ? [m.appendingPathComponent("专辑-海边")] : [m.appendingPathComponent("Neon Coast - Midnight Drive.mp3")]
    }
    static func subtitleFile() -> URL? {
        guard active, let m = mediaDir else { return nil }
        return m.appendingPathComponent("测试视频.chs.srt")
    }
    static func saveURL() -> URL? { active ? outDir.appendingPathComponent("自测播放列表.m3u8") : nil }
    static func answer(_ key: String) -> String? {
        switch key {
        case "url": return UserDefaults.standard.string(forKey: "testURL") ?? mediaDir?.appendingPathComponent("陈默 - 晚风.m4a").absoluteString
        case "jump": return "0:20"
        case "preset": return "自测预设"
        default: return nil
        }
    }
    static func log(_ s: String) {
        guard active else { return }
        if logHandle == nil {
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let u = outDir.appendingPathComponent("selftest.log")
            FileManager.default.createFile(atPath: u.path, contents: nil)
            logHandle = try? FileHandle(forWritingTo: u)
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        logHandle?.write(("[\(f.string(from: Date()))] " + s + "\n").data(using: .utf8)!)
    }
}

/// 自动把每一个菜单栏项、每一个右键菜单项都实际触发一次，前后读取 App 状态与 mpv 实际属性做对比，写进 selftest.log。
/// 菜单栏项通过真实的 NSMenuItem（NSApp.mainMenu.performActionForItem）触发；右键菜单用同一份数据生成 NSMenu 后触发。
@MainActor
final class SelfTest {
    let p: PlayerController
    init(_ p: PlayerController) { self.p = p }
    private var pass = 0, changed = 0, unchanged = 0, skipped = 0
    /// 自测期间关掉 App Nap：窗口被别的 App 盖住时，系统会把后台计时器无限推迟，自测就会停住
    private var activity: NSObjectProtocol?

    func run() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "胭脂自测")
        Task { @MainActor in
            await sleep(2.5)
            TestHooks.log("== 自测开始：\(ProcessInfo.processInfo.operatingSystemVersionString)")
            guard let m = TestHooks.mediaDir else { TestHooks.log("缺少 -testMedia"); return }
            p.clearQueue()
            p.open([m], playNow: true)
            await sleep(2)
            p.selectTab(.nowPlaying)
            if UserDefaults.standard.bool(forKey: "shotsOnly") { await shots(); finish(); return }
            if UserDefaults.standard.bool(forKey: "demoShots") { await demoShots(); finish(); return }
            lyricsDefaultAtStart = p.lyricsEnabled
            realLyricsPref = Self.realPref("lyricsAutoSearch")
            coversDefaultAtStart = p.onlineCoversEnabled
            iTunesDefaultAtStart = CoverService.useITunes
            realCoversPref = Self.realPref("onlineCovers")
            if UserDefaults.standard.bool(forKey: "onlyUpdate") { await updateTests(); return }
            if Net.simulateOffline { await offlineTests() }
            if UserDefaults.standard.bool(forKey: "onlyOffline") { finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyASR") { await asrTests(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyCards") { await cardTests(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyDbl") { await entryAudit(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyRes") { await resolutionAudit(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyExits") { await closureTests(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyClosure") { await closureTests(); await resolutionAudit(); await entryAudit(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyFlaky") { await loopPanelTests(); await cardTests(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyTheme") { await zhuqingTests(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyYunwen") { await yunwenShots(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyAdd") { await addFlowTests(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyScan") { await scanTests(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyFSLoop") { await videoFullscreenFitTest(); await loopDragOnOriginalTimelineTest(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyClosure") { await menuAuditTests(); await addFlowTests(); await closureTests(); finish(); return }
            if UserDefaults.standard.bool(forKey: "onlyNew") { await menuAuditTests(); await addFlowTests(); await closureTests(); await cardTests(); await zhuqingTests(); await coverTests(); finish(); return }
            p.pause(); await sleep(0.5)

            // —— 菜单栏（音频状态下）——
            await sweepMainMenu(label: "音频")
            // —— 切到视频再测「视频」「音频▸音轨」等只对视频生效的项 ——
            if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) { p.play(index: vi, from: 0); await sleep(2.5); p.pause() }
            await sweepMainMenu(label: "视频", only: ["视频", "音频"])
            // —— 右键菜单 ——
            for (name, _) in MenuCatalog.allContexts(p) {
                if name == "迷你窗" { p.togglePinnedMini(); await sleep(1.2) }
                await sweepContext(name)
                if name == "迷你窗" && p.isPinnedMini { p.togglePinnedMini(); await sleep(1.2) }
            }
            await menuAuditTests()
            await addFlowTests()
            await closureTests(); await resolutionAudit(); await entryAudit()
            await dropTests()
            await loopTests()
            p.resetSpeedPitch(); p.loopSeamAlign = true
            if p.speedPitchOpen { p.toggleSpeedPitchPanel() }
            await loopSeamWaveTest()
            await loopEditorTest()
            await loopPanelTests()
            await videoFullscreenFitTest()
            await loopDragOnOriginalTimelineTest()
            await cardTests()
            await zhuqingTests()
            await scanTests()
            await lyricsTests()
            await coverTests()
            await resizeTests()
            await speedPitchTests()
            await chorusTests()
            await coverStyleTests()
            await autoEqTests()
            await asrTests()
            TestHooks.log("== 触发汇总：生效 \(changed) 项，无可见变化 \(unchanged) 项，跳过 \(skipped) 项")
            await shots()
            finish()
        }
    }

    /// 单声道 float32 WAV
    static func writeWAV(_ x: [Float], rate: Int, to url: URL) {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(x.count * 4)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(3); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 4)); u16(4); u16(32)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        x.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: x.count * 4)) }
        try? d.write(to: url)
    }

    /// 自测时把 App 提到前台；带 -noActivate YES 时不提（夜里本人不在、别抢他正在用的窗口的焦点）
    private func activateIfAllowed() { if !UserDefaults.standard.bool(forKey: "noActivate") { NSApp.activate() } }

    private func finish() {
        TestHooks.log("== 自测结束")
        try? "done".write(to: TestHooks.outDir.appendingPathComponent("selftest.done"), atomically: true, encoding: .utf8)
        after(0.5) { NSApp.terminate(nil) }
    }

    private func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    // MARK: 状态快照（App 状态 + mpv 实际属性）
    func snapshot() -> [String: String] {
        let e = p.engine!
        func g(_ k: String) -> String { e.getString(k) ?? "-" }
        var s: [String: String] = [
            "播放": p.isPlaying ? "是" : "否", "位置": String(format: "%.0f", p.position), "音量": String(format: "%.0f", p.volume),
            "静音": p.muted ? "是" : "否", "倍速": String(format: "%.2f", p.speed), "音调": "\(p.pitchSemitones)/\(p.pitchCents)", "变速面板": p.speedPitchOpen ? "开" : "关", "无缝接缝": p.loopSeamAlign ? "开" : "关", "循环": p.queue.repeatMode.label,
            "随机": p.queue.shuffle ? "是" : "否", "页": p.tab.title, "主题": p.theme.name, "均衡器": p.eq.enabled ? "开" : "关",
            "预设": p.eq.presetID ?? "-", "段数": "\(p.eq.bandCount.rawValue)", "前级": String(format: "%.1f", p.eq.preamp),
            "列表": "\(p.queue.items.count)", "列表顺序": p.queue.items.prefix(4).map(\.title).joined(separator: "/"),
            "当前": p.current?.title ?? "-", "迷你窗": p.isPinnedMini ? "是" : "否", "置顶": p.isFloating ? "是" : "否",
            "抬起": p.isLifted ? "是" : "否", "快捷键帮助": p.showShortcuts ? "开" : "关", "最近": "\(p.recent.count)",
            "全屏": (p.mainWindow?.styleMask.contains(.fullScreen) ?? false) ? "是" : "否", "窗口层级": "\(p.mainWindow?.level.rawValue ?? -1)",
            "定位": "\(p.locateToken)", "自定义预设": "\(p.customPresets.count)",
            // mpv 实际值
            "mpv.speed": g("speed"), "mpv.volume": g("volume"), "mpv.mute": g("mute"), "mpv.af含声道": g("af").contains("tancoch") ? "是" : "否",
            "mpv.audio-delay": g("audio-delay"), "mpv.sub-delay": g("sub-delay"), "mpv.aspect": g("video-aspect-override"),
            "mpv.zoom": g("video-zoom"), "mpv.panscan": g("panscan"), "mpv.rotate": g("video-rotate"), "mpv.sid": g("sid"), "mpv.aid": g("aid"),
            "mpv.ab-a": g("ab-loop-a"), "mpv.ab-b": g("ab-loop-b"), "mpv.loop-file": g("loop-file"), "mpv.audio-device": g("audio-device"),
            "mpv.pause": g("pause"), "mpv.path": (g("path") as NSString).lastPathComponent,
            "字幕轨数": "\(p.subtitleTracks.count)",
        ]
        s["HUD"] = p.hud?.text.replacingOccurrences(of: "\n", with: " ") ?? "-"
        return s
    }

    private func diff(_ a: [String: String], _ b: [String: String]) -> String {
        a.keys.sorted().compactMap { k in
            guard a[k] != b[k], k != "HUD" || b[k] != "-" else { return nil }
            if k == "位置", let x = Double(a[k] ?? ""), let y = Double(b[k] ?? ""), abs(x - y) < 1.5 { return nil }
            return "\(k): \(a[k] ?? "")→\(b[k] ?? "")"
        }.joined(separator: "；")
    }

    // 需要成对“再触发一次复原”的开关
    private let toggleBack: Set<String> = ["全屏", "迷你窗（置顶小窗）", "迷你窗", "窗口置顶", "画中画", "键盘快捷键", "退出迷你窗"]
    // 跳过：会退出或关闭窗口
    private let skipTitles: Set<String> = []

    private func perform(_ path: String, _ fire: () -> Void, title: String) async {
        let before = snapshot()
        p.hud = nil
        fire()
        await sleep(title == "全屏" ? 1.8 : 0.55)
        let after = snapshot()
        let d = diff(before, after)
        if d.isEmpty { unchanged += 1 } else { changed += 1 }
        TestHooks.log((d.isEmpty ? "○ " : "✓ ") + path + (d.isEmpty ? "（无可见变化）" : " → " + d))
        if toggleBack.contains(title) {
            fire(); await sleep(title == "全屏" ? 1.8 : 0.9)
            TestHooks.log("  ↺ 已复原：" + diff(after, snapshot()))
        }
    }

    // MARK: 菜单栏
    private func ourTitles() -> Set<String> {
        var t = Set<String>()
        for group in [MenuCatalog.file(p), MenuCatalog.edit(p), MenuCatalog.playback(p), MenuCatalog.audio(p), MenuCatalog.video(p),
                      MenuCatalog.playlist(p), MenuCatalog.view(p), MenuCatalog.window(p), MenuCatalog.help(p)] {
            for (_, n) in group.flatten(prefix: "") { t.insert(n.title) }
        }
        // 动态标题（播放/暂停、A/B 点、预设名、设备名…）
        t.formUnion(["播放", "暂停", "设置 A 点", "设置 B 点并开始循环", "取消 A-B 循环"])
        return t
    }

    /// 和用户真的点开菜单时一样：先让菜单的 delegate（SwiftUI）按当前状态重建/刷新，再读可用状态
    private func refresh(_ m: NSMenu) {
        m.delegate?.menuNeedsUpdate?(m)
        m.update()
    }

    private func collectPaths(_ menu: NSMenu, prefix: [String], into out: inout [[String]], ours: Set<String>) {
        refresh(menu)
        for it in menu.items where !it.isSeparatorItem {
            if let sub = it.submenu {
                // 最近打开里的文件名、预设名、设备名、主题名等都在我们自己的子菜单里：子菜单内全部算我们的
                collectPaths(sub, prefix: prefix + [it.title], into: &out, ours: ours.union(prefix.count >= 1 && ours.contains(it.title) ? Set(sub.items.map(\.title)) : []))
            } else if ours.contains(it.title) {
                out.append(prefix + [it.title])
            }
        }
    }

    private func resolve(_ path: [String]) -> (NSMenu, Int)? {
        guard var menu = NSApp.mainMenu else { return nil }
        for (k, t) in path.enumerated() {
            refresh(menu)
            guard let idx = menu.items.firstIndex(where: { $0.title == t }) else {
                // 动态标题：播放↔暂停、A/B 点
                let alt: [String: [String]] = ["播放": ["暂停"], "暂停": ["播放"], "设置 A 点": ["设置 B 点并开始循环", "取消 A-B 循环"], "设置 B 点并开始循环": ["设置 A 点", "取消 A-B 循环"]]
                if k == path.count - 1, let a = alt[t], let i2 = menu.items.firstIndex(where: { a.contains($0.title) }) { return (menu, i2) }
                return nil
            }
            if k == path.count - 1 { return (menu, idx) }
            guard let sub = menu.items[idx].submenu else { return nil }
            menu = sub
        }
        return nil
    }

    private func sweepMainMenu(label: String, only: Set<String>? = nil) async {
        guard let main = NSApp.mainMenu else { return }
        TestHooks.log("== 菜单栏（\(label)状态）")
        let ours = ourTitles()
        var paths: [[String]] = []
        for top in main.items.dropFirst() {          // 跳过 App 菜单（关于/设置/退出）
            guard let sub = top.submenu else { continue }
            if let only, !only.contains(top.title) { continue }
            collectPaths(sub, prefix: [top.title], into: &paths, ours: ours)
        }
        TestHooks.log("共 \(paths.count) 项：" + Set(paths.map { $0[0] }).sorted().joined(separator: "、"))
        for path in paths {
            if path.last == "清空播放列表" || path.last == "移除当前曲目" { continue }   // 放到最后
            await fireMain(path)
        }
        for path in paths where path.last == "移除当前曲目" || path.last == "清空播放列表" { await fireMain(path) }
        // 清空后重新载入测试媒体，后续测试继续
        if p.queue.items.count < 3, let m = TestHooks.mediaDir { p.open([m], playNow: false); await sleep(1.5) }
    }

    private func fireMain(_ path: [String]) async {
        let name = path.joined(separator: " ▸ ")
        guard let (menu, idx) = resolve(path) else { skipped += 1; TestHooks.log("– \(name)（菜单已变化，找不到该项）"); return }
        let it = menu.items[idx]
        guard it.isEnabled else { skipped += 1; TestHooks.log("– \(name)（当前状态下不可用，已灰显）"); return }
        await perform(name + (it.keyEquivalent.isEmpty ? "" : "  [\(shortcut(it))]"), { menu.performActionForItem(at: idx) }, title: path.last!)
        if p.queue.items.isEmpty, let m = TestHooks.mediaDir { p.open([m], playNow: false); await sleep(1.5) }
    }

    private func shortcut(_ it: NSMenuItem) -> String {
        var s = ""
        let f = it.keyEquivalentModifierMask
        if f.contains(.control) { s += "⌃" }; if f.contains(.option) { s += "⌥" }; if f.contains(.shift) { s += "⇧" }; if f.contains(.command) { s += "⌘" }
        let map: [String: String] = ["\u{F702}": "←", "\u{F703}": "→", "\u{F700}": "↑", "\u{F701}": "↓", " ": "空格", "\u{8}": "⌫", "\u{7F}": "⌫"]
        return s + (map[it.keyEquivalent] ?? it.keyEquivalent.uppercased())
    }

    // MARK: 右键菜单
    private func sweepContext(_ name: String) async {
        TestHooks.log("== 右键菜单：\(name)")
        func current() -> [MenuNode] { MenuCatalog.allContexts(p).first { $0.0 == name }?.1 ?? [] }
        let paths = current().flatten(prefix: "").map { $0.0 }
        for path in paths {
            if p.queue.items.count < 3, let m = TestHooks.mediaDir { p.open([m], playNow: false); await sleep(1.5) }
            // 每次重新生成菜单，再按路径找到 NSMenuItem 触发
            let menu = NSMenuBuilder.build(current())
            guard let (m, idx) = find(path, in: menu) else { skipped += 1; TestHooks.log("– \(name) ▸ \(path)（菜单已变化）"); continue }
            guard m.items[idx].isEnabled else { skipped += 1; TestHooks.log("– \(name) ▸ \(path)（不可用）"); continue }
            await perform(name + " ▸ " + path, { m.performActionForItem(at: idx) }, title: m.items[idx].title)
        }
    }

    private func find(_ path: String, in menu: NSMenu) -> (NSMenu, Int)? {
        let parts = path.components(separatedBy: " ▸ ")
        var m = menu
        for (k, t) in parts.enumerated() {
            var idx = m.items.firstIndex { $0.title == t }
            if idx == nil, k == parts.count - 1 {
                let alt: [String: [String]] = ["播放": ["暂停"], "暂停": ["播放"], "翻回封面": ["显示简介与歌词"], "显示简介与歌词": ["翻回封面"]]
                idx = m.items.firstIndex { alt[t]?.contains($0.title) == true }
            }
            guard let i = idx else { return nil }
            if k == parts.count - 1 { return (m, i) }
            guard let s = m.items[i].submenu else { return nil }
            m = s
        }
        return nil
    }

    // MARK: 第 7 轮：「有进就有出」闭环自测 —— 每个能进入的状态，进一次、退一次（尽量用 Esc 真按键），断言恢复
    // 这一段是之后加功能的门禁：ExitState 每加一项，下面的 switch 不补测试就编译不过；tools/check-exits.py 管状态属性登记。
    private func closureTests() async {
        TestHooks.log("== 进出闭环（有进就有出）")
        logWindows("闭环开始")
        await ensureWindow("闭环开始")
        await closeOverlays()
        logWindows("closeOverlays 后")
        p.mainWindow?.makeKeyAndOrderFront(nil)
        p.selectTab(.nowPlaying)
        guard let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) else { TestHooks.log("✗ 没有音频素材"); return }
        p.play(index: ai, from: 20); await sleep(1.6)
        func esc() async { await ensureWindow("按 Esc 前"); p.mainWindow?.makeKeyAndOrderFront(nil); postKey(53); await sleep(0.9) }
        var rows: [(ExitState, Bool, String)] = []
        // -exitOnly a,b,c：只测这几个状态（补测新状态时用，省时间）
        let only = Set((UserDefaults.standard.string(forKey: "exitOnly") ?? "").split(separator: ",").map(String.init))
        for st in ExitState.allCases where only.isEmpty || only.contains(st.rawValue) {
            await ensureWindow(st.name)
            var ok = true; var note = ""
            switch st {
            case .coverViewer:
                // 封面观赏（TANCO 2026-11-20：不要手势，鼠标 + 键盘；单击翻面、双击观赏）
                guard let vw = p.viewer.view, let cv = p.mainWindow?.contentView else { ok = false; note = "观赏视图没装上"; break }
                var r: [String] = []
                var allOK = true
                func mark(_ name: String, _ good: Bool, _ extra: String = "") { r.append("\(name) \(good ? "✓" : "✗")\(extra)"); if !good { allOK = false }; TestHooks.log("    \(good ? "✓" : "✗") 观赏 · \(name)\(extra)") }
                func H() -> CGFloat { p.mainWindow?.contentView?.bounds.height ?? cv.bounds.height }
                func W() -> CGFloat { p.mainWindow?.contentView?.bounds.width ?? cv.bounds.width }
                func isFull() -> Bool { p.mainWindow?.styleMask.contains(.fullScreen) ?? false }
                func waitOpen() async -> Bool { for _ in 0..<60 { if p.viewer.isOpen && !vw.isFlying && !p.viewer.opening { return true }; await sleep(0.05) }; return false }
                func waitClosed() async -> Bool { for _ in 0..<80 { if !p.viewer.isOpen && !p.viewer.closing { await sleep(0.15); return true }; await sleep(0.05) }; return false }
                func waitAnim() async { await sleep(0.15); for _ in 0..<60 { if !vw.isAnimating { break }; await sleep(0.05) }; await sleep(0.1) }
                func clean() -> Bool { !p.viewer.isOpen && p.viewer.hiddenKey == nil && p.tab == .nowPlaying && !isFull() && !p.isPinnedMini }
                // t159u：观赏封面圆角须与卡片上的封面同一套比例（连续圆角，随显示边长缩放），不能落成近矩形的 4 点。
                func coverCornerOK(_ tag: String) {
                    let side = min(vw.imageRect.width, vw.imageRect.height)
                    let expected = CoverViewerView.coverCornerRadius(displayedSide: side)
                    let actual = vw.displayedCornerRadius
                    let ok = side > 32 && abs(actual - expected) <= 1
                    mark("观赏封面有圆角（\(tag)）", ok, String(format: "（显示边长 %.1f，圆角 %.1f，期望 %.1f）", side, actual, expected))
                }
                func atA(_ i: Int) async {
                    if p.viewer.isOpen { p.closeCoverViewer(); _ = await waitClosed() }
                    p.isLifted = false
                    p.play(index: i, from: 10); p.carousel.jump(to: i); p.runCarousel()
                    let t0 = CACurrentMediaTime()
                    while abs(p.carousel.position - Double(i)) > 0.002 && CACurrentMediaTime() - t0 < 5 { await sleep(0.05) }
                    activateIfAllowed(); p.mainWindow?.makeKeyAndOrderFront(nil); await sleep(0.5)
                }
                let cardY = { H() * 0.40 }
                /// 双击过程中每 8ms 看一次有没有翻面（双击绝不能先翻一下）
                func watchFlip(_ secs: Double) -> Task<Bool, Never> {
                    Task { @MainActor in var seen = false; let t0 = CACurrentMediaTime(); while CACurrentMediaTime() - t0 < secs { if p.isLifted { seen = true }; try? await Task.sleep(nanoseconds: 8_000_000) }; return seen }
                }
                // 全量自测里前面的步骤可能把窗口留在全屏：先退出全屏，观赏这一项从普通窗口开始，最后还原
                let wasFull = isFull()
                if wasFull { p.mainWindow?.toggleFullScreen(nil); await sleep(1.8) }
                defer { if wasFull && !(p.mainWindow?.styleMask.contains(.fullScreen) ?? false) { p.mainWindow?.toggleFullScreen(nil) } }
                var openM: (fps: Double, p95: Double, maxDt: Double, slow: Int, n: Int) = (0, 0, 0, 0, 0)
                var closeM = openM

                // 1) 中间卡双击 → 观赏（中途不翻面）；原图换上；Esc 退出（帧率计量）
                await atA(ai)
                let w1 = watchFlip(1.0)
                openM = await measureFrames { await humanDoubleClick(fromTop: cardY(), x: W() / 2); _ = await waitOpen(); await sleep(0.2) }
                let flipped1 = await w1.value
                var fullOK = false
                for _ in 0..<40 { if vw.isFullRes { fullOK = true; break }; await sleep(0.1) }
                mark("双击中间卡进入", p.viewer.isOpen && p.viewer.source == .carousel && !flipped1, flipped1 ? "（中途翻面了）" : "")
                mark("原图", fullOK, "：\(vw.pixelInfo)")
                func chromeOnscreenDetail(_ L: ViewerFrost.Layout, w: Double, h: Double) -> (ok: Bool, detail: String) {
                    let off = ViewerFrost.offscreenForeground(L, inWidth: w, height: h)
                    if off.isEmpty { return (true, "均在窗内") }
                    return (false, "越界: " + off.map { String(format: "%@ (%.1f,%.1f,%.1f×%.1f)", $0.name, $0.x, $0.y, $0.width, $0.height) }.joined(separator: "; "))
                }
                func transportOperable(tag: String, shotPrefix: String) async {
                    let w = Double(W()), h = Double(H())
                    let L = ViewerFrost.layout(inWidth: w, height: h)
                    let fit = chromeOnscreenDetail(L, w: w, h: h)
                    mark("前景四键与进度在窗内（\(tag)）", fit.ok, "（\(fit.detail)，\(Int(w))×\(Int(h))）")
                    let play = ViewerFrost.playButtonCenter(L)
                    if let v = p.mainWindow?.contentView {
                        let pt = CGPoint(x: play.x, y: v.bounds.height - play.y)
                        let hit = v.hitTest(pt)
                        let hitName = hit.map { String(describing: type(of: $0)) } ?? "无"
                        TestHooks.log("  \(tag) 播放键坐标 (\(String(format: "%.1f, %.1f", play.x, play.y))) 命中 \(hitName)")
                                                let playRect = CGRect(x: L.controlRow.x, y: L.controlRow.y, width: L.controlRow.width, height: L.controlRow.height)
                        let onControl = playRect.contains(CGPoint(x: play.x, y: play.y))
                        mark("播放键坐标落在控件矩形（\(tag)）", onControl, "（命中 \(hitName)）")
                    }
                    let stable = p.viewer.isOpen && !p.viewer.closing && !(p.viewer.view?.isFlying ?? true) && !(p.viewer.view?.isZoomed ?? false)
                    if !stable {
                        mark("点播放暂停切换状态（\(tag)）", false, "（观赏页未稳定打开：open=\(p.viewer.isOpen) closing=\(p.viewer.closing) flying=\(p.viewer.view?.isFlying ?? true)）")
                        return
                    }
                    await requestShot("\(shotPrefix)-fit")
                    let id0 = p.current?.id
                    let playing0 = p.isPlaying
                    await humanClick(fromTop: CGFloat(play.y), x: CGFloat(play.x))
                    await sleep(0.4)
                    let stillOpen = p.viewer.isOpen && !p.viewer.closing && !(p.viewer.view?.isFlying ?? false)
                    let toggled = p.isPlaying != playing0
                    mark("点播放暂停切换状态（\(tag)）", stillOpen && toggled, stillOpen ? (toggled ? "（播放 \(playing0)→\(p.isPlaying)）" : "（仍开着，播放状态未变，不能算通过）") : "（退出或正在关闭，点击落到了退出路径）")
                    guard stillOpen && toggled else { return }
                    if p.isPlaying {
                        let a = p.position
                        await sleep(0.7)
                        let b = p.position
                        mark("恢复后进度继续推进（\(tag)）", b > a + 0.25, String(format: "（%.2f→%.2f）", a, b))
                        await requestShot("\(shotPrefix)-playing")
                        await humanClick(fromTop: CGFloat(play.y), x: CGFloat(play.x))
                        await sleep(0.4)
                        let paused = stillOpen && p.viewer.isOpen && !p.viewer.closing && !p.isPlaying
                        mark("再点暂停（\(tag)）", paused, paused ? "" : "（playing=\(p.isPlaying) closing=\(p.viewer.closing)）")
                        if paused {
                            let c = p.position
                            await sleep(0.7)
                            let d = p.position
                            mark("暂停后进度停止推进（\(tag)）", abs(d - c) < 0.25, String(format: "（%.2f→%.2f）", c, d))
                            await requestShot("\(shotPrefix)-paused")
                        }
                    } else {
                        let c = p.position
                        await sleep(0.7)
                        let d = p.position
                        mark("暂停后进度停止推进（\(tag)）", abs(d - c) < 0.25, String(format: "（%.2f→%.2f）", c, d))
                        await requestShot("\(shotPrefix)-paused")
                        await humanClick(fromTop: CGFloat(play.y), x: CGFloat(play.x))
                        await sleep(0.4)
                        let resumed = p.viewer.isOpen && !p.viewer.closing && p.isPlaying
                        mark("再点播放恢复（\(tag)）", resumed, resumed ? "（播放 \(playing0)→\(p.isPlaying)）" : "（playing=\(p.isPlaying) closing=\(p.viewer.closing)）")
                        if resumed {
                            let a = p.position
                            await sleep(0.7)
                            let b = p.position
                            mark("恢复后进度继续推进（\(tag)）", b > a + 0.25, String(format: "（%.2f→%.2f）", a, b))
                            await requestShot("\(shotPrefix)-playing")
                        }
                    }
                    let dur = p.duration ?? 0
                    if p.viewer.isOpen && !p.viewer.closing && dur > 2 {
                        let hitH = ViewerFrost.progressHitHeight(L, windowHeight: h)
                        let seekY = L.progress.y + max(hitH / 2, 1)
                        let fromX = L.progress.x + L.progress.width * 0.20
                        let toX = L.progress.x + L.progress.width * 0.65
                        await humanDrag(fromTop: CGFloat(seekY), x: CGFloat(fromX), dx: CGFloat(toX - fromX), dyFromTop: 0)
                        await sleep(0.35)
                        let same = p.current?.id == id0
                        let moved = p.position >= dur * 0.40
                        mark("拖动进度仍原轨（\(tag)）", same && moved, String(format: "（轨 %@ 位置 %.1f / %.1f）", same ? "未变" : "变了", p.position, dur))
                    }
                    if p.viewer.isOpen && p.isPlaying != playing0 { p.togglePlay(); await sleep(0.15) }
                }
                let L86 = ViewerFrost.layout(inWidth: Double(W()), height: Double(H()))
                let cr86 = vw.imageRect
                let pos86 = abs(Double(cr86.minX) - L86.cover.x) <= 3 && abs(Double(cr86.minY) - L86.cover.y) <= 3 && abs(Double(cr86.width) - L86.cover.size) <= 3 && abs(Double(cr86.height) - L86.cover.size) <= 3
                mark("适应态右侧小封面位置", pos86, String(format: "（显示 (%.1f, %.1f, %.1f×%.1f) 期望 (%.1f, %.1f, %.1f)）", cr86.minX, cr86.minY, cr86.width, cr86.height, L86.cover.x, L86.cover.y, L86.cover.size))
                await transportOperable(tag: "窗口", shotPrefix: "t218u-86-window")
                await requestShot("t217u-86-fit")
                await requestShot("r8v-01-open-liuli")
                closeM = await measureFrames { postKey(53); _ = await waitClosed() }
                mark("Esc 退出（飞回中间卡）", clean() && !p.isLifted)

                // 2) 单击中间卡 → 翻面（量实际延迟）；背面双击 → 观赏；右上 × 退出回到背面；背面单击 → 翻回
                await atA(ai)
                if let w = p.mainWindow, let v = w.contentView {
                    let pt = CGPoint(x: W() / 2, y: v.bounds.height - cardY())
                    let hit = v.hitTest(pt)
                    TestHooks.log("  单击翻面前：appActive=\(NSApp.isActive) key=\(w.isKeyWindow) viewerOpen=\(p.viewer.isOpen) opening=\(p.viewer.opening) closing=\(p.viewer.closing) viewHidden=\(vw.isHidden) flying=\(vw.isFlying) hit=\(hit.map { String(describing: type(of: $0)) } ?? "无")")
                }
                let tc = CACurrentMediaTime()
                await humanClick(fromTop: cardY(), x: W() / 2)
                var seenAt: Double = -1
                for _ in 0..<100 { if p.isLifted { seenAt = CACurrentMediaTime() - tc; break }; await sleep(0.005) }
                let delay = p.lastCardClickDelay
                mark("单击中间卡翻面", p.isLifted, String(format: "（等双击 %.0f ms，点下到开始翻面 %.0f ms，系统双击间隔 %.0f ms）", delay * 1000, seenAt * 1000, NSEvent.doubleClickInterval * 1000))
                TestHooks.log(String(format: "  单击翻面延迟：%.0f ms", delay * 1000))
                await sleep(0.9)
                let w2 = watchFlipBack(1.0)
                await humanDoubleClick(fromTop: cardY(), x: W() / 2); _ = await waitOpen()
                let unflipped = await w2.value
                mark("背面双击进入", p.viewer.isOpen && p.viewer.source == .lifted && p.isLifted && !unflipped)
                await requestShot("r8v-02-from-back")
                await humanClick(fromTop: 31, x: W() - 35); _ = await waitClosed()
                mark("右上 × 退出（回到背面）", !p.viewer.isOpen && p.isLifted && p.viewer.hiddenKey == nil)
                await humanClick(fromTop: cardY(), x: W() / 2); await sleep(0.9)
                mark("背面单击翻回正面", !p.isLifted)

                // 3) 旁边的卡双击 → 切过去播放并观赏；适应状态单击空白退出
                await atA(ai)
                let side = min(ai + 1, p.queue.items.count - 1)
                let sideAudio = p.queue.items[side].kind == .audio && side != ai
                if sideAudio {
                    let sr = p.carouselCoverRect(index: side)?.rect ?? CGRect(x: W() / 2 + 230, y: cardY(), width: 1, height: 1)
                    await humanDoubleClick(fromTop: sr.midY, x: sr.midX); _ = await waitOpen()
                    mark("双击旁边的卡进入（切歌播放）", p.viewer.isOpen && p.viewer.itemID == p.queue.items[side].id && p.queue.currentIndex == side && p.isPlaying && !p.isLifted)
                    await humanClick(fromTop: H() * 0.5, x: 12); _ = await waitClosed()
                    mark("单击封面外空白退出（回到切过去的那张）", clean() && p.carousel.centeredIndex == side)
                } else { mark("双击旁边的卡（素材顺序不对，跳过）", true) }

                // 4) ⌘Y 进入；缩放：⌘+ / ⌘− / ⌘0、滚轮以指针为中心（观赏内双击不再切换适应/原图）；平移：拖动 + 惯性 + 边界、⌥方向键；方向键仍是快进
                // 用原图最大的那首（2400×2400），放大后才有地方平移
                let big = p.queue.items.indices.first(where: { p.queue.items[$0].kind == .audio && p.queue.items[$0].title == "Midnight Drive" }) ?? ai
                await atA(big)
                postKeyMods(16, "y", [.command]); _ = await waitOpen()
                mark("⌘Y 进入", p.viewer.isOpen)
                // 适应比例必须在原图换上之后再锁定：Midnight Drive 卡片 2048、原图 2400，先锁会把后来的适应误判成 0.85 倍
                var fullForFit = vw.isFullRes
                for _ in 0..<40 { if vw.isFullRes { fullForFit = true; break }; await sleep(0.1) }
                if !fullForFit { TestHooks.log("  （⌘Y 后原图还没换上，适应比例按当前图计算）") }
                let fit = vw.fitScale
                let inspect = vw.inspectFitScale
                coverCornerOK("适应")
                await requestShot("r8v-15-cover-corner-fit")
                do {
                    let L = ViewerFrost.layout(inWidth: Double(W()), height: Double(H()))
                    let fit = chromeOnscreenDetail(L, w: Double(W()), h: Double(H()))
                    mark("回到适应态底栏在窗内", !vw.isZoomed && fit.ok, "（zoomed=\(vw.isZoomed) \(fit.detail)）")
                }
                postKeyMods(24, "=", [.command]); await waitAnim()
                let zin = vw.isZoomed
                postKeyMods(27, "-", [.command]); await waitAnim()
                let zout = abs(vw.scale - fit) < fit * 0.02
                for _ in 0..<12 { postKeyMods(24, "=", [.command]); await sleep(0.05) }; await waitAnim()
                let capped = vw.scale <= vw.maxScale * 1.001
                postKeyMods(29, "0", [.command]); await waitAnim()
                mark("⌘+ / ⌘− / ⌘0（最大 \(String(format: "%.1f", vw.maxScale / fit)) 倍封顶）", zin && zout && capped && !vw.isZoomed, "（放大 \(zin) 缩回 \(zout) 封顶 \(capped) 归位 \(!vw.isZoomed)，现在 \(String(format: "%.2f", vw.scale / fit)) 倍）")
                // 先放大到画面比窗口大（小于窗口的方向会自动居中，谈不上以指针为中心），再用滚轮
                vw.zoom(to: inspect * 2.5, at: nil, animated: false)
                coverCornerOK("放大 2.5 倍")
                await requestShot("r8v-16-cover-corner-zoomed")
                mark("缩放检视时不在适应态", vw.isZoomed)
                let pt = CGPoint(x: vw.bounds.width * 0.3, y: vw.bounds.height * 0.35)
                let before = vw.debugImagePoint(pt)
                for _ in 0..<4 { vw.wheel(dy: 2, precise: false, at: pt) }
                let after = vw.debugImagePoint(pt)
                let drift = hypot(after.x - before.x, after.y - before.y)
                mark("滚轮以指针为中心放大", vw.isZoomed && drift < 1.5 && vw.scale > inspect * 2.6, String(format: "（指针下像素漂移 %.2f）", drift))
                for _ in 0..<10 { vw.wheel(dy: -3, precise: false, at: pt) }
                let wheelFit = !vw.isZoomed
                mark("滚轮缩回适应（不会小于适应）", wheelFit && abs(vw.scale - fit) < fit * 0.01)
                coverCornerOK("缩回适应")
                vw.zoomToActual(); await waitAnim()
                await requestShot("r8v-03-zoom-100")
                vw.debugPan(by: CGPoint(x: 120, y: 60), release: CGPoint(x: 2400, y: 900)); await sleep(0.05)
                let mom = vw.isAnimating
                await waitAnim(); await sleep(0.3)
                mark("拖动松手有惯性、停在边界内", mom && vw.lastMomentumDistance > 1 && vw.debugInBounds, String(format: "（惯性滑行 %.0f 点）", vw.lastMomentumDistance))
                coverCornerOK("平移后")
                vw.zoomToFit(animated: false); vw.zoom(to: inspect * 3, at: nil, animated: false); await sleep(0.1)
                let o0 = vw.debugOrigin
                postKeyMods(124, "", [.option]); await waitAnim()
                let o1 = vw.debugOrigin
                postKeyMods(123, "", [.option]); await waitAnim()
                let o2 = vw.debugOrigin
                mark("⌥→ / ⌥← 平移（每下挪窗口宽的 12%，到边为止）", o1.x < o0.x - 1 && o2.x > o1.x + W() * 0.1, String(format: "（x %.0f → %.0f → %.0f）", o0.x, o1.x, o2.x))
                let t0 = p.position
                let ob = vw.debugOrigin
                postKeyMods(124, "", []); await sleep(0.5)
                mark("观赏中方向键仍是快进（画面不动）", p.position > t0 + 2 && vw.debugOrigin == ob, String(format: "（%.1f → %.1f 秒）", t0, p.position))
                // Esc 一层层退：先回适应，再退出
                await sleep(0.3)
                let zBefore = vw.isZoomed
                postKey(53); await sleep(0.2); await waitAnim()
                let step1 = p.viewer.isOpen && !vw.isZoomed
                let s1 = "第一下后 开着=\(p.viewer.isOpen) 放大=\(vw.isZoomed)"
                postKey(53); _ = await waitClosed()
                mark("Esc 先回适应、再退出", zBefore && step1 && clean(), "（按前放大=\(zBefore)；\(s1)；第二下后 开着=\(p.viewer.isOpen) 藏=\(p.viewer.hiddenKey ?? "-") 全屏=\(isFull()) 翻面=\(p.isLifted)）")
                TestHooks.log("    （缩放、平移用的是「\(p.queue.items[big].title)」）")


                // 4b) 18:15：单击封面（适应或放大）立即退出并飞回入口；点空白也退出；拖动超过阈值只平移；双击不再切换适应/原图，单击不等待第二下
                await atA(big)
                postKeyMods(16, "y", [.command]); _ = await waitOpen()
                let fitClickRect = vw.debugImageRectInWindow
                await humanClick(fromTop: H() - fitClickRect.midY, x: fitClickRect.midX)
                let fitClickImmediate = p.viewer.closing || !p.viewer.isOpen
                let fitClickClosed = await waitClosed()
                mark("适应状态单击封面立即退出（飞回入口）", fitClickImmediate && fitClickClosed && clean(), "（单击后立即开始退出=\(fitClickImmediate) 已关闭=\(fitClickClosed)）")

                await atA(big)
                postKeyMods(16, "y", [.command]); _ = await waitOpen()
                vw.zoom(to: inspect * 2.5, at: nil, animated: false); await sleep(0.1)
                let zoomedClickRect = vw.debugImageRectInWindow
                await humanClick(fromTop: H() - zoomedClickRect.midY, x: zoomedClickRect.midX)
                let zoomedClickImmediate = p.viewer.closing || !p.viewer.isOpen
                let zoomedClickClosed = await waitClosed()
                mark("放大后单击封面立即退出（飞回入口）", zoomedClickImmediate && zoomedClickClosed && clean(), "（单击后立即开始退出=\(zoomedClickImmediate) 已关闭=\(zoomedClickClosed)）")

                await atA(big)
                postKeyMods(16, "y", [.command]); _ = await waitOpen()
                vw.zoom(to: inspect * 2.5, at: nil, animated: false); await sleep(0.1)
                await humanClick(fromTop: H() * 0.5, x: 12)
                let blankClickImmediate = p.viewer.closing || !p.viewer.isOpen
                let blankClickClosed = await waitClosed()
                mark("放大后单击空白退出", blankClickImmediate && blankClickClosed && clean(), "（单击后立即开始退出=\(blankClickImmediate) 已关闭=\(blankClickClosed)）")

                await atA(big)
                postKeyMods(16, "y", [.command]); _ = await waitOpen()
                vw.zoom(to: inspect * 3, at: nil, animated: false); await sleep(0.1)
                let originBeforeDrag = vw.debugOrigin
                let dragRect = vw.debugImageRectInWindow
                await humanDrag(fromTop: H() - dragRect.midY, x: dragRect.midX, dx: 28, dyFromTop: 16)
                await waitAnim(); await sleep(0.15)
                let dragged = hypot(vw.debugOrigin.x - originBeforeDrag.x, vw.debugOrigin.y - originBeforeDrag.y) > 3
                mark("拖动超过阈值只平移、不退出", p.viewer.isOpen && vw.isZoomed && dragged, String(format: "（仍开着=%@ 仍放大=%@ 平移 %.1f 点）", p.viewer.isOpen ? "true" : "false", vw.isZoomed ? "true" : "false", hypot(vw.debugOrigin.x - originBeforeDrag.x, vw.debugOrigin.y - originBeforeDrag.y)))
                postKey(53); await waitAnim(); postKey(53); _ = await waitClosed()

                await atA(big)
                postKeyMods(16, "y", [.command]); _ = await waitOpen()
                let dblRect = vw.debugImageRectInWindow
                await humanDoubleClick(fromTop: H() - dblRect.midY, x: dblRect.midX)
                let dblImmediate = p.viewer.closing || !p.viewer.isOpen
                let dblClosed = await waitClosed()
                mark("双击封面不再切换适应/原图，第一下立即退出", dblImmediate && dblClosed && clean(), "（第一下后即开始退出=\(dblImmediate) 已关闭=\(dblClosed) 开着=\(p.viewer.isOpen)）")

                // 5) 观赏中切歌：封面交叉淡入、原图跟上；⌘Y 再按退出
                await atA(ai)
                postKeyMods(16, "y", [.command]); _ = await waitOpen()
                let cf0 = vw.lastCrossfade
                let nextIdx = p.queue.items.indices.first(where: { $0 > ai && p.queue.items[$0].kind == .audio })
                if let n = nextIdx {
                    p.play(index: n, from: 5); await sleep(1.4)
                    mark("观赏中切歌（封面交叉淡入）", p.viewer.isOpen && p.viewer.itemID == p.queue.items[n].id && vw.lastCrossfade > cf0)
                    await requestShot("r8v-04-track-change")
                }
                postKeyMods(16, "y", [.command]); _ = await waitClosed()
                mark("再按 ⌘Y 退出（飞回切过去的那张）", clean() && p.carousel.centeredIndex == (nextIdx ?? ai))

                // 6) 卡片右键「观赏封面」；观赏里右键「退出观赏」；菜单截图
                await atA(ai)
                let cm = MenuCatalog.card(p, index: ai)
                mark("卡片右键菜单只有一项「观赏封面」", cm.filter { $0.title == "观赏封面" }.count == 1)
                fireMenu(cm, path: [], prefix: "观赏封面"); _ = await waitOpen()
                let rcIn = p.viewer.isOpen
                await shootMenu("r8v-05-viewer-menu", MenuCatalog.viewer(p), at: CGPoint(x: W() * 0.62, y: H() * 0.45))
                fireMenu(MenuCatalog.viewer(p), path: [], prefix: "退出观赏"); _ = await waitClosed()
                mark("右键「观赏封面」进 / 右键「退出观赏」出", rcIn && clean())

                // 7) 播放栏小封面：单击不做事，双击观赏，退出飞回小封面
                await atA(ai)
                if let pr = p.viewer.rects["playbar"] {
                    await humanClick(fromTop: pr.rect.midY, x: pr.rect.midX); await sleep(0.7)
                    let single = !p.viewer.isOpen
                    await humanDoubleClick(fromTop: pr.rect.midY, x: pr.rect.midX); _ = await waitOpen()
                    let pIn = p.viewer.isOpen && p.viewer.source == .playbar
                    postKey(53); _ = await waitClosed()
                    mark("播放栏小封面 单击不动 / 双击观赏 / Esc 飞回", single && pIn && clean())
                    await humanDoubleClick(fromTop: pr.rect.midY, x: pr.rect.midX); _ = await waitOpen()
                    let pOpen = p.viewer.isOpen && p.viewer.source == .playbar
                    let pImg = vw.debugImageRectInWindow
                    await humanClick(fromTop: H() - pImg.midY, x: pImg.midX)
                    let pClickNow = p.viewer.closing || !p.viewer.isOpen
                    let pClickClosed = await waitClosed()
                    mark("播放栏入口单击封面飞回", pOpen && pClickNow && pClickClosed && clean())
                } else { mark("播放栏小封面（没找到位置）", false) }

                // 8) 播放列表行右键「观赏封面」
                p.selectTab(.playlist); await sleep(1.0)
                let rm = MenuCatalog.playlistRow(p, index: ai)
                fireMenu(rm, path: [], prefix: "观赏封面"); _ = await waitOpen()
                let lIn = p.viewer.isOpen && p.viewer.source == .playlist
                await requestShot("r8v-06-from-playlist")
                postKey(53); _ = await waitClosed()
                mark("播放列表行右键「观赏封面」→ Esc 回到列表", lIn && !p.viewer.isOpen && p.tab == .playlist && p.viewer.hiddenKey == nil)
                p.selectTab(.nowPlaying); await sleep(0.8)

                // 9) 迷你窗双击封面 → 回大窗口观赏，退出后回迷你窗
                await atA(ai)
                p.togglePinnedMini(); await sleep(1.4)
                if p.isPinnedMini, let mr = p.viewer.rects["mini"] {
                    await humanDoubleClick(fromTop: mr.rect.midY, x: mr.rect.midX); await sleep(0.8); _ = await waitOpen()
                    let mIn = p.viewer.isOpen && !p.isPinnedMini
                    await requestShot("r8v-07-from-mini")
                    postKey(53); _ = await waitClosed(); await sleep(1.0)
                    let back = p.isPinnedMini && !p.viewer.isOpen
                    mark("迷你窗双击封面 → 大窗口观赏 → Esc 回迷你窗", mIn && back)
                    if p.isPinnedMini, let mr2 = p.viewer.rects["mini"] {
                        await humanDoubleClick(fromTop: mr2.rect.midY, x: mr2.rect.midX); await sleep(0.8); _ = await waitOpen()
                        let mOpen = p.viewer.isOpen && !p.isPinnedMini
                        let mImg = vw.debugImageRectInWindow
                        await humanClick(fromTop: H() - mImg.midY, x: mImg.midX)
                        let mClickNow = p.viewer.closing || !p.viewer.isOpen
                        _ = await waitClosed(); await sleep(1.0)
                        let mBack = p.isPinnedMini && !p.viewer.isOpen
                        mark("迷你窗入口单击封面飞回迷你窗", mOpen && mClickNow && mBack)
                    } else { mark("迷你窗入口单击封面飞回迷你窗（没进迷你窗或没找到位置）", false) }
                } else { mark("迷你窗封面（没进迷你窗或没找到位置）", false) }
                if p.isPinnedMini { p.togglePinnedMini(); await sleep(1.4) }

                // 10) 全屏观赏：F 进，Esc 先退全屏、再退出观赏
                await atA(ai)
                postKeyMods(16, "y", [.command]); _ = await waitOpen()
                postKeyMods(3, "f", []); await sleep(1.6)
                let fsIn = isFull() && p.viewer.isOpen
                await waitAnim()
                coverCornerOK("全屏")
                await requestShot("r8v-08-fullscreen")
                await transportOperable(tag: "全屏", shotPrefix: "t218u-86-fullscreen")
                postKey(53); await sleep(1.6)
                let fsOut = !isFull() && p.viewer.isOpen
                postKey(53); _ = await waitClosed()
                mark("F 全屏观赏 → Esc 退全屏 → Esc 退出", fsIn && fsOut && clean(), "（进全屏 \(fsIn) 退全屏仍在观赏 \(fsOut) 最后 开着=\(p.viewer.isOpen) 全屏=\(isFull())）")

                // 11) 视频不进观赏：视频卡右键没有这一项，⌘Y 不打开
                if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
                    let vm = MenuCatalog.card(p, index: vi)
                    p.play(index: vi, from: 2); await sleep(1.6)
                    postKeyMods(16, "y", [.command]); await sleep(0.8)
                    let none = !p.viewer.isOpen && !vm.contains { $0.title == "观赏封面" }
                    if p.videoStageOpen { p.exitVideoStage(); await sleep(0.8) }
                    mark("视频卡 / 视频画面不进观赏", none)
                }

                // 12) 主题截图（纯黑、纯白、琉璃、朱青）
                let theme0 = p.theme
                for (tag, t) in [("black", AppTheme.black), ("white", .white), ("liuli", .liuli), ("zhuqing", .zhuqing)] {
                    p.setTheme(t); await atA(ai)
                    postKeyMods(16, "y", [.command]); _ = await waitOpen(); await sleep(0.3)
                    await requestShot("r8v-10-theme-\(tag)")
                    postKey(53); _ = await waitClosed()
                }
                p.setTheme(theme0); await sleep(1.0)
                // 飞行中一帧
                await atA(ai)
                postKeyMods(16, "y", [.command]); await sleep(0.18)
                await requestShot("r8v-09-mid-flight")
                _ = await waitOpen(); postKey(53); _ = await waitClosed()

                let jo = judgeFrames(openM), jc = judgeFrames(closeM)
                mark("打开过渡", openM.slow <= 3, " \(jo)")
                mark("关闭过渡", closeM.slow <= 3, " \(jc)")
                ok = allOK && clean()
                note = r.joined(separator: "；")
                await atA(ai)
            case .videoStage:
                guard let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) else { ok = false; note = "没有视频素材"; break }
                let wb = p.mainWindow?.contentView?.bounds ?? .zero
                func enterV() async { p.play(index: vi, from: 2); await sleep(1.8) }
                func back() -> Bool { !p.videoStageOpen && p.tab == .nowPlaying && p.carousel.target == vi && !(p.mainWindow?.styleMask.contains(.fullScreen) ?? false) }
                // a) Esc
                await enterV(); let inA = p.videoStageOpen
                await requestShot("r8-01-video-stage-back-button")
                await esc(); await sleep(0.6)
                let a = inA && back() && !p.isPlaying
                await requestShot("r8-02-video-stage-exited")
                // b) 左上「返回」按钮：真点击（按钮在顶栏左侧、红绿灯右边）
                await enterV(); p.pokeChrome(); await sleep(0.4)
                p.mainWindow?.makeKeyAndOrderFront(nil); await sleep(0.2)
                postClick(fromTop: 29, x: 112); await sleep(1.2)
                let b = back()
                if p.videoStageOpen { p.exitVideoStage(); await sleep(0.8) }
                // c) 点画面外的空白处（窗口左边缘，视频画框外）
                await enterV()
                postClick(fromTop: wb.height * 0.45, x: 14); await sleep(1.2)
                let c = back()
                if p.videoStageOpen { p.exitVideoStage(); await sleep(0.8) }
                // d) 双指横扫（右滑、左滑各一次；走滚动监听调用的同一个处理函数）
                await enterV()
                p.videoSwipe(dx: 0, dy: 0, began: true, ended: false)
                for _ in 0..<6 { p.videoSwipe(dx: 18, dy: 1, began: false, ended: false); await sleep(0.016) }
                p.videoSwipe(dx: 0, dy: 0, began: false, ended: true); await sleep(1.0)
                let d1 = back()
                await enterV()
                p.videoSwipe(dx: 0, dy: 0, began: true, ended: false)
                for _ in 0..<6 { p.videoSwipe(dx: -18, dy: 1, began: false, ended: false); await sleep(0.016) }
                p.videoSwipe(dx: 0, dy: 0, began: false, ended: true); await sleep(1.0)
                let d = d1 && back()
                // e) 右键「返回封面轮播」（视频画面、空白处两个右键菜单里都在第一项）
                await enterV()
                let m1 = MenuCatalog.videoSurface(p).first?.title == "返回封面轮播"
                let m2 = MenuCatalog.blank(p).first?.title == "返回封面轮播"
                await shootMenu("r8-03-video-stage-menu", MenuCatalog.videoSurface(p), at: CGPoint(x: wb.midX, y: wb.height * 0.4))
                fireMenu(MenuCatalog.videoSurface(p), path: [], prefix: "返回封面轮播"); await sleep(1.0)
                let e = m1 && m2 && back()
                // f) TANCO 的路径：轮播停在视频卡上，真双击这张卡 → 回到视频舞台、不进全屏；再 Esc 退回
                p.mainWindow?.makeKeyAndOrderFront(nil); await sleep(0.3)
                postDoubleClick(fromTop: wb.height * 0.40); await sleep(1.8)
                let fIn = p.videoStageOpen && p.isPlaying && !(p.mainWindow?.styleMask.contains(.fullScreen) ?? false)
                await esc(); await sleep(0.6)
                let f = fIn && back()
                // g) 回车：轮播停在视频卡上 → 回到视频舞台；Esc 退回
                p.mainWindow?.makeKeyAndOrderFront(nil)
                postKeyCode(36); await sleep(1.2)
                let gIn = p.videoStageOpen
                await esc(); await sleep(0.6)
                let g = gIn && back()
                ok = a && b && c && d && e && f && g
                note = "Esc \(a ? "✓" : "✗")；左上「返回」真点击 \(b ? "✓" : "✗")；点空白处 \(c ? "✓" : "✗")；双指右滑 / 左滑 \(d ? "✓" : "✗")；右键「返回封面轮播」\(e ? "✓" : "✗")；双击视频卡进入（不误进全屏）再退出 \(f ? "✓" : "✗")；回车进入再退出 \(g ? "✓" : "✗")"
                p.play(index: ai, from: 20); await sleep(1.6)
            case .lifted:
                let t0 = p.carousel.target, cur0 = p.queue.currentIndex
                // a) 点中间卡翻面 → Esc
                p.carouselTap(p.queue.currentIndex ?? ai); await sleep(0.9)
                let up = p.isLifted
                await requestShot("r7-01-lift-back-button")
                await esc()
                let a = up && !p.isLifted && p.carousel.target == t0
                // b) 翻面 → 触控板横扫：只翻回，不换卡
                withAnimation(Motion.lift) { p.carouselTap(p.queue.currentIndex ?? ai) }; await sleep(0.9)
                p.carouselBeginDrag(); p.carouselDrag(deltaCards: -1.2); p.carouselEndDrag(); await sleep(1.2)
                let b = !p.isLifted && p.carousel.target == t0 && p.queue.currentIndex == cur0
                // c) 翻面 → 右键空白处「翻回封面」
                withAnimation(Motion.lift) { p.carouselTap(p.queue.currentIndex ?? ai) }; await sleep(0.9)
                let hasMenu = MenuCatalog.blank(p).first?.title == "翻回封面"
                let wb = p.mainWindow?.contentView?.bounds ?? .zero
                await shootMenu("r7-02-lift-blank-menu", MenuCatalog.blank(p), at: CGPoint(x: 120, y: 150))
                fireMenu(MenuCatalog.blank(p), path: [], prefix: "翻回封面"); await sleep(0.9)
                let c = hasMenu && !p.isLifted
                // d) 翻面 → 点空白处（左上角空白，真点击）
                withAnimation(Motion.lift) { p.carouselTap(p.queue.currentIndex ?? ai) }; await sleep(0.9)
                p.mainWindow?.makeKeyAndOrderFront(nil); await sleep(0.3)
                postClick(fromTop: wb.height * 0.30, x: 40); await sleep(1.0)
                let d = !p.isLifted
                if p.isLifted { p.exitLift(); await sleep(0.6) }
                // e) 翻面 → 卡背「返回」按钮（按钮动作）
                withAnimation(Motion.lift) { p.carouselTap(p.queue.currentIndex ?? ai) }; await sleep(0.9)
                p.exitLift(); await sleep(0.9)
                let e = !p.isLifted && p.carousel.target == t0
                // f) 翻着时滚轮 / 键盘换卡：也只翻回
                withAnimation(Motion.lift) { p.carouselTap(p.queue.currentIndex ?? ai) }; await sleep(0.9)
                p.carouselStep(1); await sleep(1.0)
                let f = !p.isLifted && p.carousel.target == t0
                ok = a && b && c && d && e && f
                note = "Esc \(a ? "✓" : "✗")；横扫只翻回不换卡 \(b ? "✓" : "✗")；右键「翻回封面」\(c ? "✓" : "✗")；点空白处 \(d ? "✓" : "✗")；「返回」按钮 \(e ? "✓" : "✗")；翻着时换卡键只翻回 \(f ? "✓" : "✗")；轮播位置 \(t0) → \(p.carousel.target)"
            case .paramCard:
                var each: [String] = []
                for c in ParamCard.allCases {
                    withAnimation(Motion.panel) { p.activeCard = c }; await sleep(0.8)
                    await esc()
                    each.append("\(c.title)\(p.activeCard == nil ? "✓" : "✗")")
                    ok = ok && p.activeCard == nil
                }
                note = "逐张打开 → Esc 收起：" + each.joined(separator: " ")
            case .shortcuts:
                p.toggleShortcutsHelp(); await sleep(0.8)
                await esc()
                ok = !p.showShortcuts
                note = "打开快捷键面板 → Esc"
            case .scrubbing:
                p.seek(to: 30); await sleep(0.8); p.pause(); await sleep(0.5)
                let pos0 = p.position
                p.beginScrub(); p.scrub(to: min((p.duration ?? 60) - 2, pos0 + 25)); await sleep(0.4)
                let moved = p.position
                await esc()
                p.endScrub(at: moved)   // 松手发生在 Esc 之后：应该不跳
                await sleep(0.8)
                let eng = p.engine.getDouble("time-pos") ?? -1
                ok = !p.isScrubbing && abs(p.position - pos0) < 1.0 && abs(eng - pos0) < 1.5
                note = String(format: "按下 %.1f 秒拖到 %.1f 秒 → Esc 放弃，回到 %.1f 秒（mpv %.1f），松手不再跳", pos0, moved, p.position, eng)
                p.togglePlay(); await sleep(0.5)
            case .scanning:
                p.seek(to: 10); await sleep(0.5)
                if !p.isPlaying { p.togglePlay(); await sleep(0.5) }
                let wasPlaying = p.isPlaying
                postArrow(124, down: true, isRepeat: false); await sleep(0.3)
                for _ in 0..<8 { postArrow(124, down: true, isRepeat: true); await sleep(0.08) }
                let during = p.scanDirection
                await esc()
                postArrow(124, down: false, isRepeat: false); await sleep(0.5)
                ok = during == 1 && p.scanDirection == 0 && abs((p.engine.getDouble("speed") ?? 0) - 1) < 0.01 && p.isPlaying == wasPlaying
                note = "按住 → 连续快进（方向 \(during)）→ Esc 停下，速度 \(p.engine.getDouble("speed") ?? 0)，继续播放 \(p.isPlaying)（之前 \(wasPlaying)），位置 \(Int(p.position)) 秒"
            case .fullScreen:
                p.toggleFullScreen(); await sleep(2.0)
                let fs = p.mainWindow?.styleMask.contains(.fullScreen) ?? false
                await esc(); await sleep(1.6)
                ok = fs && !(p.mainWindow?.styleMask.contains(.fullScreen) ?? true)
                note = "进入全屏 \(fs) → Esc 退出"
            case .mini:
                let f0 = p.mainWindow?.frame ?? .zero
                p.togglePinnedMini(); await sleep(1.4)
                let on = p.isPinnedMini
                await requestShot("r7-03-mini")
                await esc(); await sleep(1.0)
                let f1 = p.mainWindow?.frame ?? .zero
                ok = on && !p.isPinnedMini && abs(f1.width - f0.width) < 2 && abs(f1.height - f0.height) < 2
                note = "迷你窗 → Esc 回到原来的大窗口（\(Int(f0.width))×\(Int(f0.height)) → \(Int(f1.width))×\(Int(f1.height))）"
            case .equalizerTab, .playlistTab:
                p.selectTab(st == .equalizerTab ? .equalizer : .playlist); await sleep(0.9)
                await esc()
                ok = p.tab == .nowPlaying
                note = "切到\(st == .equalizerTab ? "均衡器" : "播放列表")页 → Esc 回到正在播放"
            case .asr:
                if !p.asrAvailable { note = "这台 Mac 上识别组件可用时才测（当前未安装，入口灰显）"; ok = true; break }
                p.generateSubtitles(language: .auto)
                for _ in 0..<30 where p.asrProgress == nil { await sleep(0.1) }
                let running = p.asrProgress != nil
                await esc()
                for _ in 0..<30 where p.asrProgress != nil { await sleep(0.1) }
                ok = running && p.asrProgress == nil
                note = "开始识别（进行中 \(running)）→ Esc 取消"
            case .abLoop:
                if p.current?.kind != .audio { p.play(index: ai, from: 20); await sleep(1.5) }
                p.pokeChrome()
                p.setLoopRange(22, 28, quiet: true); await sleep(0.8)
                let on = p.abA != nil
                await requestShot("r7-04-ab-chip")
                await esc()
                let a = p.engine.getString("ab-loop-a") ?? "-"
                ok = on && p.abA == nil && p.abB == nil && a == "no"
                // 播放栏小标签上的 ×
                p.setLoopRange(22, 28, quiet: true); await sleep(0.6)
                p.clearABLoop(); await sleep(0.6)
                ok = ok && p.abA == nil
                note = "设区间 22–28 秒（播放栏出现「A-B ×」）→ Esc 取消，mpv ab-loop-a=\(a)，恢复正常播放；点 × 也能取消"
            case .speedPitch:
                if p.current?.kind != .audio { p.play(index: ai, from: 20); await sleep(1.5) }
                p.pokeChrome()
                p.setSpeed(1.25); p.pitchStep(semitones: 2); await sleep(0.8)
                await requestShot("r7-05-speed-reset-chip")
                await esc()
                let a = p.speed == 1 && p.pitchSemitones == 0 && p.pitchCents == 0
                p.setSpeed(0.8); await sleep(0.4); p.resetSpeedPitch(); await sleep(0.6)
                ok = a && p.speed == 1 && abs((p.engine.getDouble("speed") ?? 0) - 1) < 0.001
                note = "1.25× 升 2 半音 → Esc 一键回到 100%、原调；播放栏速度标签旁的 ↺ 也能一键恢复"
            case .auxWindow:
                activateIfAllowed()
                UpdateWindow.shared.show()
                var shown = false, keyOk = false
                for _ in 0..<25 {
                    shown = UpdateWindow.shared.isVisible
                    if let w = NSApp.windows.first(where: { $0.title == "检查更新" || $0.identifier?.rawValue == "update" }) {
                        if !w.isKeyWindow { w.makeKeyAndOrderFront(nil); activateIfAllowed() }
                        keyOk = w.isKeyWindow
                        if shown && keyOk { break }
                    }
                    await sleep(0.1)
                }
                TestHooks.log("  检查更新小窗 shown=\(shown) key=\(keyOk) phase=\(String(describing: UpdateModel.shared.phase)) keyWindow=\(NSApp.keyWindow?.title ?? "nil")/\(NSApp.keyWindow?.identifier?.rawValue ?? "-")")
                postKeyToKeyWindow(53); await sleep(0.9)
                let closed = !UpdateWindow.shared.isVisible
                if !closed { logWindows("检查更新 Esc 后仍开着") }
                ok = shown && closed && UpdateModel.shared.phase == .idle
                p.mainWindow?.makeKeyAndOrderFront(nil); await sleep(0.4)
                note = "「检查更新」小窗 → Esc 关掉（窗口关了，更新流程回到空闲）"
            case .playHistory:
                p.openPlayHistory(); await sleep(0.8)
                let opened = p.showPlayHistory
                await esc()
                ok = opened && !p.showPlayHistory
                note = "打开播放记录 → Esc 关闭（不改当前队列）"
            case .playlistBrowse:
                p.selectTab(.playlist); await sleep(0.6)
                let id = p.createPlaylist(); await sleep(0.5)
                p.cancelRenamePlaylist(); await sleep(0.3)
                let opened = p.viewingPlaylistID == id
                await esc()
                ok = opened && p.viewingPlaylistID == nil && p.tab == .playlist
                p.deletePlaylist(id); await sleep(0.3)
                await esc()
                note = "「+」新建歌单并进入 → Esc 回到当前列表（还在播放列表页；测完删掉这个歌单）"
            case .playlistRename:
                p.selectTab(.playlist); await sleep(0.6)
                let id = p.createPlaylist(); await sleep(0.5)
                let name0 = p.library.list(id)?.name
                let opened = p.isRenamingPlaylist
                await esc()
                ok = opened && !p.isRenamingPlaylist && p.library.list(id)?.name == name0 && p.viewingPlaylistID == id
                p.deletePlaylist(id); await sleep(0.3)
                await esc()
                note = "新建歌单进入起名 → Esc 不改名、仍停在这个歌单"
            case .themeReorder:
                p.beginThemeReorder(); await sleep(0.4)
                let opened = p.isReorderingThemes
                await esc()
                ok = opened && !p.isReorderingThemes
                note = "长按色板进入排序 → Esc 退出排序（顺序保留）"
            case .properties:
                p.selectTab(.playlist); await sleep(0.6)
                if let it = p.queue.items.first {
                    p.toggleProperties(it.id); await sleep(0.6)
                    let opened = p.propertiesOpen
                    await esc()
                    ok = opened && !p.propertiesOpen && p.tab == .playlist
                }
                await esc()
                note = "点文件名翻到属性 → Esc 翻回来（还在播放列表页）"
            case .tagEditor:
                p.selectTab(.playlist); await sleep(0.6)
                if let it = p.queue.items.first {
                    p.openTagEditor(it.id); await sleep(0.6)
                    let opened = p.tagEditorOpen
                    await esc()
                    ok = opened && !p.tagEditorOpen
                }
                await esc()
                note = "打开编辑标签 → Esc 关闭（不写文件）"
            case .autoEqBrand:
                p.selectTab(.equalizer); await sleep(0.5)
                withAnimation(Motion.panel) { p.activeCard = .autoEq }
                if p.autoEqIndex.isEmpty { p.loadAutoEqIndex() }
                for _ in 0..<30 where p.autoEqBrandIndex == nil { await sleep(0.1) }
                await sleep(0.5)
                let brand = p.autoEqBrands()?.major.first?.name ?? "Sennheiser"
                p.openAutoEqBrand(brand); await sleep(0.5)
                let opened = p.autoEqBrandOpen
                await esc()
                let l1 = !p.autoEqBrandOpen && p.activeCard == .autoEq
                await esc()
                ok = opened && l1 && p.activeCard == nil
                await esc()
                note = "耳机校正里点品牌「\(brand)」→ Esc 回品牌列表 → 再 Esc 收起卡片"
            }
            rows.append((st, ok, note))
            TestHooks.log("\(ok ? "✓" : "✗") 进出闭环 · \(st.name)：\(note)")
        }
        // 层层退：均衡器页 + 卡片开着 → 第一下 Esc 只收卡片，第二下才回正在播放
        p.selectTab(.equalizer); await sleep(0.8)
        withAnimation(Motion.panel) { p.activeCard = .autoEq }; await sleep(0.8)
        await esc()
        let l1 = p.activeCard == nil && p.tab == .equalizer
        await esc()
        let l2 = p.tab == .nowPlaying
        TestHooks.log("\(l1 && l2 ? "✓" : "✗") Esc 一次只退一层：先收卡片（还在均衡器页 \(l1)），再回正在播放 \(l2)")
        let clean = p.escapeOnce() == nil
        TestHooks.log("\(clean ? "✓" : "✗") 全部退完后再按 Esc：没有残留状态（escapeOnce 返回空）")
        // 写出表
        var md = "# 有进就有出：状态 → 进入方式 → 退出方式\n\n由自测程序按 ExitState 生成（\(Date())）。最后一列是这次自测实际进一次、退一次的结果。\n\n| 状态 | 进入方式 | 退出方式（看得见的 / 键盘） | 自测 |\n|---|---|---|---|\n"
        for (st, ok, note) in rows { md += "| \(st.name) | \(st.enter) | \(st.exits) | \(ok ? "✓" : "✗") \(note.replacingOccurrences(of: "|", with: "\\|")) |\n" }
        md += "| 对话框（打开网址、跳转到、存为预设…） | 菜单里带「…」的项 | 「取消」按钮；Esc | 取消键已设成 Esc（系统对话框，自测里用预设答案，不弹） |\n"
        md += "| 选择文件对话框（添加歌曲 / 文件夹） | 右键最顶上两项；⌥⌘O | 「取消」；Esc | 见「添加歌曲」自测：取消后列表不变 |\n"
        md += "| 右键菜单、主题小面板、均衡器存预设小面板 | 右键；点按钮 | 点外面；Esc | 系统自带 |\n"
        try? md.write(to: TestHooks.outDir.appendingPathComponent("进出闭环表.md"), atomically: true, encoding: .utf8)
        TestHooks.log("已写出 进出闭环表.md（\(rows.count) 个状态，通过 \(rows.filter { $0.1 }.count)）")
    }

    /// 主窗口被关掉 / 隐藏（比如本人正在用电脑时顺手关了）：重新打开，并记一笔
    private func ensureWindow(_ tag: String) async {
        if p.mainWindow != nil { return }
        let w = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
        TestHooks.log("  （\(tag)：主窗口\(p.mainWindow == nil ? "不可见" : "在后台")\(w?.isMiniaturized == true ? "（已最小化）" : "")，自测把它重新放到前面）")
        if NSApp.isHidden { NSApp.unhide(nil) }
        if w?.isMiniaturized == true { w?.deminiaturize(nil) }
        w?.makeKeyAndOrderFront(nil)
        activateIfAllowed()
        await sleep(0.8)
    }

    private func logWindows(_ tag: String) {
        let ws = NSApp.windows.map { w in "\(w.identifier?.rawValue ?? "-")/\(type(of: w))/vis=\(w.isVisible)/mini=\(w.isMiniaturized)/key=\(w.isKeyWindow)/\(Int(w.frame.width))x\(Int(w.frame.height))" }
        TestHooks.log("  [窗口 \(tag)] hidden=\(NSApp.isHidden) active=\(NSApp.isActive) main=\(p.mainWindow != nil) " + ws.joined(separator: " | "))
    }

    /// 内部演示截图：演示库（testout 里的合成音频 + 真实曲名 / 专辑封面），中间是《范特西》正在播《世界末日》。
    /// 主窗口的画面都先进全屏再按窗口截（只截本 App 的窗口）；迷你窗、右键菜单不能全屏，只截窗口本身，之后在盒子上合成背景。
    private func demoShots() async {
        TestHooks.log("== 演示截图")
        if p.onlineCoversEnabled { p.setOnlineCoversEnabled(false, quiet: true) }
        let song = UserDefaults.standard.string(forKey: "demoSong") ?? "世界末日"
        let pre = UserDefaults.standard.string(forKey: "demoPrefix") ?? "demo"
        let vOnly = UserDefaults.standard.bool(forKey: "demoVideoOnly")
        p.selectTab(.nowPlaying)
        guard let i = p.queue.items.firstIndex(where: { $0.title == song }) else { TestHooks.log("✗ 演示库里没有《\(song)》"); return }
        let vi = p.queue.items.firstIndex(where: { MediaFormats.kind(forExtension: $0.url.pathExtension) == .video })
        p.play(index: i, from: 62); await sleep(3.0)
        TestHooks.log("  正在播：\(p.current?.title ?? "-") / \(p.current?.displayArtist ?? "-") / \(p.current?.album ?? "-")，共 \(p.queue.items.count) 项")
        func fs(_ on: Bool) async {
            let now = p.mainWindow?.styleMask.contains(.fullScreen) ?? false
            if now != on { p.mainWindow?.makeKeyAndOrderFront(nil); p.toggleFullScreen(); await sleep(2.4) }
        }
        func snap(_ name: String) async { p.pokeChrome(); await sleep(0.4); await requestShot(name) }
        func swipeShot(_ name: String) async {
            let t0 = p.carousel.target
            p.carouselBeginDrag()
            for _ in 0..<9 { p.carouselDrag(deltaCards: 0.05); await sleep(0.03) }
            await sleep(0.25); p.pokeChrome()
            await requestShot(name)
            for _ in 0..<9 { p.carouselDrag(deltaCards: -0.05); await sleep(0.03) }
            await sleep(0.4); p.carouselEndDrag(); await sleep(1.5)
            TestHooks.log("\(p.carousel.target == t0 && p.current?.title == song ? "✓" : "✗") \(name)：拍完回到原位，仍在播《\(song)》")
        }
        func backToSong() async {
            if p.current?.title != song { p.play(index: i, from: 62); await sleep(2.0) }
        }
        // TANCO 指定三套：琉璃、朱青、纯黑夜间（都在 App 里切换，不动系统外观）
        let sets: [(String, AppTheme, Double)] = [("琉璃", .liuli, 90), ("朱青", .zhuqing, 60), ("纯黑夜间", .midnight, 180)]
        for (tag, t, vfrac) in sets {
            let n = "\(pre)_\(tag)"
            p.setTheme(t); await sleep(1.6)
            await backToSong()
            if vOnly { await fs(true) } else {
            // —— 窗口模式：右键菜单、迷你窗（之后在盒子上合成封面毛玻璃背景）
            await fs(false)
            p.selectTab(.nowPlaying); await sleep(0.8)
            let w = p.mainWindow?.contentView?.bounds ?? .zero
            let flipped = p.mainWindow?.contentView?.isFlipped == true
            await shootMenu("\(n)_w1_右键菜单", MenuCatalog.card(p, index: i), at: CGPoint(x: w.midX + 40, y: flipped ? w.height - 150 : 150))
            p.togglePinnedMini(); await sleep(1.6)
            await requestShot("\(n)_w2_迷你窗", kind: "small")
            p.togglePinnedMini(); await sleep(1.6)
            // —— 全屏：卡片、滑动中、专辑详情 + 歌词、播放列表、均衡器、参数卡片
            await fs(true)
            p.selectTab(.nowPlaying); await sleep(1.0)
            if p.carousel.centeredIndex != i { p.carousel.jump(to: i); p.runCarousel(); await sleep(1.6) }
            TestHooks.log("\(p.carousel.centeredIndex == i && (p.mainWindow?.styleMask.contains(.fullScreen) ?? false) ? "✓" : "✗") \(n)：全屏，中间是《\(p.current?.album ?? "-")》")
            await snap("\(n)_f1_卡片轮播")
            await swipeShot("\(n)_f2_滑动中")
            withAnimation(Motion.lift) { p.carouselTap(i) }; await sleep(1.4)
            TestHooks.log("\(p.isLifted ? "✓" : "✗") \(n)：专辑翻面（详情 / 歌词）")
            await fs(true)
            await snap("\(n)_f3_专辑详情歌词")
            p.exitLift(); await sleep(1.0)
            p.selectTab(.playlist); await sleep(1.3)
            await snap("\(n)_f4_播放列表")
            p.selectTab(.equalizer); await sleep(1.3)
            await snap("\(n)_f5_均衡器")
            p.selectTab(.nowPlaying); await sleep(1.0)
            withAnimation(Motion.panel) { p.activeCard = .speedPitch }; await sleep(1.2)
            await snap("\(n)_f6_变速变调卡片")
            p.closeCard(); await sleep(0.8)
            }
            // —— 视频：播放中（控制条）、纯净画面、字幕 / 音轨菜单（全屏里截）
            if let vi {
                p.selectTab(.nowPlaying)
                // 4 分半的静帧测试视频：从 vfrac 秒开始（剩余时间看起来自然）
                p.play(index: vi, from: vfrac); await sleep(1.2)
                if p.subtitleTracks.first.map({ $0.id }) != nil, let zh = p.subtitleTracks.first { p.selectSubtitle(zh.id) }
                let d = p.duration ?? 12
                TestHooks.log("\(p.current?.knownArtist == nil && p.current?.artist == nil ? "✓" : "✗") 视频没有艺人信息：不显示「未知艺人」，艺人这一行隐藏")
                TestHooks.log("  视频：\(p.current?.title ?? "-")，\(Int(p.position)) / \(Int(d)) 秒，字幕 \(p.subtitleTracks.count) 条、音轨 \(p.audioTracks.count) 条")
                p.pokeChrome(); await sleep(0.5)
                await requestShot("\(n)_v1_视频播放中")
                await sleep(3.2)   // 鼠标不动，控件自己淡出
                await requestShot("\(n)_v2_视频全屏纯净")
                let vw = p.mainWindow?.contentView?.bounds ?? .zero
                let vflip = p.mainWindow?.contentView?.isFlipped == true
                p.pokeChrome(); await sleep(0.4)
                await shootMenu("\(n)_v3_字幕音轨菜单", MenuCatalog.subtitleArea(p), at: CGPoint(x: vw.maxX - 360, y: vflip ? vw.height - 140 : 140))
                p.pokeChrome(); await sleep(0.4)
                await shootMenu("\(n)_v4_字幕轨道", MenuCatalog.subtitleArea(p), at: CGPoint(x: vw.maxX - 420, y: vflip ? vw.height - 140 : 140), submenuPath: ["字幕"])
                p.pokeChrome(); await sleep(0.4)
                await shootMenu("\(n)_v5_音轨", MenuCatalog.subtitleArea(p), at: CGPoint(x: vw.maxX - 420, y: vflip ? vw.height - 140 : 140), submenuPath: ["音轨"])
                await backToSong()
            }
            p.selectTab(.nowPlaying); await sleep(0.6)
        }
        await fs(false)
        p.setTheme(.followCover)
    }

    /// 第 7 轮：添加歌曲 / 文件夹（右键顶上两项）：取消不变、添加后立即出现在卡片和列表里
    private func addFlowTests() async {
        TestHooks.log("== 添加歌曲 / 添加文件夹")
        await closeOverlays()
        p.selectTab(.nowPlaying); await sleep(0.6)
        // 只用 testout 里临时拷出来的测试文件（含一层子文件夹，验证递归）
        let fm = FileManager.default
        let box = TestHooks.outDir.appendingPathComponent("add-test"), subd = box.appendingPathComponent("子文件夹")
        try? fm.createDirectory(at: subd, withIntermediateDirectories: true)
        let srcs = (try? fm.contentsOfDirectory(at: TestHooks.mediaDir!, includingPropertiesForKeys: nil))?.filter { MediaFormats.isPlayable($0) }.sorted { $0.path < $1.path } ?? []
        let audioSrc = srcs.filter { MediaFormats.kind(forExtension: $0.pathExtension) == .audio }
        let videoSrc = srcs.filter { MediaFormats.kind(forExtension: $0.pathExtension) == .video }
        var made: [URL] = []
        for (k, u) in (Array(audioSrc.prefix(2)) + Array(videoSrc.prefix(1))).enumerated() {
            let dst = (k == 0 ? box : subd).appendingPathComponent("添加测试\(k + 1).\(u.pathExtension)")
            try? fm.removeItem(at: dst); try? fm.copyItem(at: u, to: dst); made.append(dst)
        }
        let single = box.appendingPathComponent("单曲测试.\(audioSrc.last?.pathExtension ?? "mp3")")
        if let a = audioSrc.last { try? fm.removeItem(at: single); try? fm.copyItem(at: a, to: single) }
        // 文件夹 = add-test（不含单曲那首：放到同级另一个文件夹）
        let folder = TestHooks.outDir.appendingPathComponent("add-test-folder")
        try? fm.removeItem(at: folder); try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for u in made { let rel = u.path.replacingOccurrences(of: box.path + "/", with: ""); let d = folder.appendingPathComponent(rel)
            try? fm.createDirectory(at: d.deletingLastPathComponent(), withIntermediateDirectories: true); try? fm.moveItem(at: u, to: d) }
        TestHooks.panelOverride = ([single], [folder])
        defer { TestHooks.panelOverride = nil }
        let n0 = p.queue.items.count, cur0 = p.current?.id, playing0 = p.isPlaying
        logWindows("// 取消对话框：什么都不变")
        // 取消对话框：什么都不变
        TestHooks.cancelNextPanel = true
        fireMenu(MenuCatalog.card(p, index: p.queue.currentIndex ?? 0), path: [], prefix: "添加歌曲…"); await sleep(0.8)
        TestHooks.log("\(p.lastAddCancelled && p.queue.items.count == n0 && p.current?.id == cur0 ? "✓" : "✗") 卡片右键「添加歌曲…」→ 在选择对话框点取消：列表仍是 \(p.queue.items.count) 项，当前曲目不变，界面回到原样")
        TestHooks.cancelNextPanel = true
        fireMenu(MenuCatalog.blank(p), path: [], prefix: "添加文件夹…"); await sleep(0.8)
        TestHooks.log("\(p.lastAddCancelled && p.queue.items.count == n0 ? "✓" : "✗") 空白处「添加文件夹…」→ 取消：列表不变")
        logWindows("// 添加文件夹（递归）：加")
        // 添加文件夹（递归）：加到最后，不打断正在播放的
        fireMenu(MenuCatalog.playBar(p), path: [], prefix: "添加文件夹…"); await sleep(0.5)
        await requestShot("r7-06-added-hud")
        await sleep(1.0)
        let n1 = p.queue.items.count
        TestHooks.log("\(n1 == n0 + made.count && p.current?.id == cur0 && p.isPlaying == playing0 && p.carousel.count == n1 ? "✓" : "✗") 播放栏右键「添加文件夹…」（testout 里的测试文件夹，\(made.count) 个文件，其中 \(made.count - 1) 个在子文件夹里）：\(n0) → \(n1) 项，加到最后，轮播卡片数 \(p.carousel.count)，正在播放的不打断")
        fireMenu(MenuCatalog.progressBar(p), path: [], prefix: "添加歌曲…"); await sleep(1.2)
        let n2 = p.queue.items.count
        TestHooks.log("\(n2 == n1 + 1 ? "✓" : "✗") 进度条右键「添加歌曲…」：\(n1) → \(n2) 项")
        fireMenu(MenuCatalog.lyricsArea(p), path: [], prefix: "添加歌曲…"); await sleep(1.0)
        TestHooks.log("\(p.queue.items.count == n2 ? "✓" : "✗") 同一首再添加一次：不重复加（仍是 \(p.queue.items.count) 项，提示「这首已经在列表里了」）")
        logWindows("p.selectTab(.p")
        p.selectTab(.playlist); await sleep(1.2)
        await requestShot("r7-07-added-in-playlist")
        p.selectTab(.nowPlaying); await sleep(0.6)
        logWindows("// 收拾：把刚加的删掉，恢")
        // 收拾：把刚加的删掉，恢复原列表
        while p.queue.items.count > n0 { p.remove(at: p.queue.items.count - 1) }
        await sleep(0.6)
        TestHooks.log("  （收拾：删掉刚加的，列表回到 \(p.queue.items.count) 项）")
        logWindows("// 空库：醒目的添加入口")
        // 空库：醒目的添加入口
        let saved = p.queue.items.map(\.url), si = p.queue.currentIndex ?? 0, spos = p.position
        p.clearQueue(); await sleep(1.2)
        await requestShot("r7-08-empty-library")
        TestHooks.cancelNextPanel = true
        p.addSongs(folders: false); await sleep(0.6)
        TestHooks.log("\(p.queue.items.isEmpty ? "✓" : "✗") 空库页「添加歌曲…」→ 取消：仍是空库页")
        p.addSongs(folders: false); await sleep(1.6)
        TestHooks.log("\(p.queue.items.count == 1 && p.isPlaying ? "✓" : "✗") 空库页「添加歌曲…」→ 选一首：立即出现卡片并开始播放（\(p.current?.title ?? "-")）")
        p.clearQueue(); p.open(saved, playNow: false); await sleep(1.5)
        p.play(index: si, from: spos); await sleep(1.0)
        logWindows("// 拖入高亮")
        // 拖入高亮
        withAnimation(Motion.panel) { p.isDropTargeted = true }; await sleep(0.9)
        await requestShot("r7-09-drop-highlight")
        withAnimation(Motion.panel) { p.isDropTargeted = false }; await sleep(0.6)
    }

    private func postKeyToKeyWindow(_ code: UInt16) {
        guard let w = NSApp.keyWindow else { return }
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: code) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }

    // MARK: 区间循环：音频、视频各实测一次（每 30ms 采样位置，数“跳回起点”的次数，检查从未越过终点）
    private func loopTests() async {
        TestHooks.log("== 区间循环")
        p.setSpeed(1)   // 前面菜单测试把倍速改过，这里回到 1×
        // 前面菜单测试改过画面比例/缩放/旋转，这里复原
        p.setAspect("no"); p.zoomStep(0); p.setRotation(0); if p.panscan { p.togglePanscan() }
        for kind in [MediaKind.audio, .video] {
            guard let i = p.queue.items.firstIndex(where: { $0.kind == kind && ($0.title == "雾中灯" || kind == .video) })
                    ?? p.queue.items.firstIndex(where: { $0.kind == kind }) else { continue }
            p.play(index: i, from: 1); await sleep(1.5)
            let a = 3.0, b = 5.0
            p.setLoopRange(a, b)
            await sleep(0.3)
            var wraps = 0, last = p.position, maxPos = 0.0, minPos = 1e9
            let t0 = Date()
            while Date().timeIntervalSince(t0) < 7.5 {
                await sleep(0.03)
                let x = p.engine.getDouble("time-pos") ?? 0
                if x + 0.5 < last { wraps += 1 }
                if Date().timeIntervalSince(t0) > 0.4 { maxPos = max(maxPos, x); minPos = min(minPos, x) }
                last = x
            }
            // 判定：7.5 秒应跳回 ≈3 次；从不越过终点。
            // 注：mpv 走“无缝”路径（不重置音频输出），跳回后最初约 0.4 秒 time-pos 会减去输出缓冲延迟而略小于 A，这是读数而不是实际播放位置
            let ok = (2...4).contains(wraps) && maxPos <= b + 0.08 && minPos >= a - 0.6
            TestHooks.log("\(ok ? "✓" : "✗") 区间循环（\(kind == .audio ? "音频" : "视频")，\(p.current?.title ?? "-")）\(a)–\(b) 秒：7.5 秒内跳回起点 \(wraps) 次，采样到的位置范围 \(String(format: "%.2f–%.2f", minPos, maxPos))；mpv ab-loop-a=\(p.engine.getString("ab-loop-a") ?? "-") b=\(p.engine.getString("ab-loop-b") ?? "-")")
            if kind == .video { p.selectTab(.nowPlaying) }
            // 截图时把区间放宽到 30%–62%，进度条上看得清
            if let d = p.duration, d > 4 { p.setLoopRange(d * 0.30, d * 0.62, quiet: true); await sleep(1.0) }
            await requestShot(kind == .audio ? "l1-loop-audio" : "l2-loop-video")
            if kind == .video {
                // 截图真的写出文件
                if let u = p.screenshot() {
                    await sleep(0.5)
                    let sz = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
                    TestHooks.log("\(sz > 1000 ? "✓" : "✗") 视频截图写出文件：\(u.lastPathComponent)（\(sz) 字节）")
                } else { TestHooks.log("✗ 视频截图失败") }
            }
            p.clearABLoop(); await sleep(0.6)
            TestHooks.log("  取消后：abA=\(p.abA.map { "\($0)" } ?? "nil") mpv ab-loop-a=\(p.engine.getString("ab-loop-a") ?? "-")")
        }
        p.pause()
    }

    // MARK: 拖放（没有辅助功能权限，无法合成真实的鼠标拖动；这里把“松手”那一刻交给与真实拖放完全相同的处理代码）
    private func dropTests() async {
        guard let m = TestHooks.mediaDir else { return }
        TestHooks.log("== 拖放处理")
        let a = m.appendingPathComponent("Neon Coast - Midnight Drive.mp3"), b = m.appendingPathComponent("无名之歌.flac")
        let folder = m.appendingPathComponent("专辑-海边"), video = m.appendingPathComponent("测试视频.mkv")
        // 1 主窗口：多个文件按顺序 → 播第一个
        p.pause()
        let providers = [a, b].compactMap { NSItemProvider(contentsOf: $0) }
        PlayerController.loadFileURLs(providers) { urls in self.p.open(urls, playNow: true) }
        await sleep(1.5)
        TestHooks.log("主窗口拖入[\(a.lastPathComponent), \(b.lastPathComponent)] → 当前=\(p.current?.url.lastPathComponent ?? "-") 播放=\(p.isPlaying) mpv.path=\((p.engine.getString("path") as NSString?)?.lastPathComponent ?? "-")")
        // 2 文件夹
        PlayerController.loadFileURLs([folder].compactMap { NSItemProvider(contentsOf: $0) }) { urls in self.p.open(urls, playNow: true) }
        await sleep(1.5)
        TestHooks.log("主窗口拖入文件夹 → 当前=\(p.current?.url.lastPathComponent ?? "-") 播放=\(p.isPlaying)")
        // 3 播放列表第 2 行下半部 → 插到第 3 位
        let before = p.queue.items.map(\.title)
        let at = RowDrop.insertionIndex(row: 1, y: 40)
        p.clearQueue(); p.open([m], playNow: false); await sleep(1.5)
        let cur = p.current?.title
        p.insert(urls: [video], at: at); await sleep(0.8)
        TestHooks.log("播放列表第2行下半拖入视频 → 插入位=\(at) 新顺序=\(p.queue.items.prefix(5).map(\.title)) 当前仍是=\(p.current?.title ?? "-")（原当前 \(cur ?? "-")）原列表 \(before.count) 项")
        // 4 视频画面（AppKit 视图）：真实走 VideoSurfaceView.performDragOperation，读的是拖放剪贴板
        let pb = NSPasteboard(name: .init("com.tanco.glassplayer.selftest.drag"))
        pb.clearContents(); pb.writeObjects([b as NSURL])
        let info = FakeDrag(pb)
        let op = p.videoSurface.draggingEntered(info)
        await sleep(0.4)
        let lit = p.videoDropTargeted
        let ok = p.videoSurface.performDragOperation(info)
        await sleep(1.5)
        TestHooks.log("视频画面拖入 \(b.lastPathComponent) → 进入时操作=\(op == .copy ? "copy" : "none") 高亮=\(lit) 接收=\(ok) 当前=\(p.current?.url.lastPathComponent ?? "-") 播放=\(p.isPlaying) 高亮已收起=\(!p.videoDropTargeted)")
        // 5 迷你窗：同一个窗口、同一个拖放入口
        p.togglePinnedMini(); await sleep(1.4)
        PlayerController.loadFileURLs([a].compactMap { NSItemProvider(contentsOf: $0) }) { urls in self.p.open(urls, playNow: true) }
        await sleep(1.5)
        TestHooks.log("迷你窗拖入 \(a.lastPathComponent) → 当前=\(p.current?.url.lastPathComponent ?? "-") 播放=\(p.isPlaying) 迷你窗=\(p.isPinnedMini)")
        p.togglePinnedMini(); await sleep(1.4)
        p.pause()
    }

    // MARK: 截图（由项目里的 watch-shots.sh 截“玻璃”自己的窗口）
    // MARK: 无缝接缝：离线录下真正经过 mpv 的循环输出，量接缝处的波形跳变（硬切 vs 对齐）
    private func loopSeamWaveTest() async {
        TestHooks.log("== 区间循环接缝波形")
        let dir = TestHooks.outDir
        let src = dir.appendingPathComponent("sine441.wav")
        // 441 Hz 正弦、48 kHz 立体声 16 位、6 秒；B 选在正弦过零、A 选在波峰附近（硬切必有大跳变）
        let sr = 48000, n = sr * 6
        var pcm = Data(capacity: n * 4)
        for i in 0..<n {
            let v = Int16(0.5 * 32767 * sin(2 * Double.pi * 441 * Double(i) / Double(sr)))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0); pcm.append(contentsOf: $0) }
        }
        var hdr = Data()
        func u32(_ x: UInt32) { withUnsafeBytes(of: x.littleEndian) { hdr.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { withUnsafeBytes(of: x.littleEndian) { hdr.append(contentsOf: $0) } }
        hdr.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); hdr.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr * 4)); u16(4); u16(16)
        hdr.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count))
        try? (hdr + pcm).write(to: src)
        var cases: [(String, String, Double, Double)] = [("正弦", src.path, 2.0131, 2.5)]
        if let song = p.queue.items.first(where: { $0.kind == .audio && $0.title == "雾中灯" }) { cases.append(("歌曲·雾中灯", song.url.path, 12.345, 15.678)) }
        for (name, path, a, b) in cases {
            let t0 = Date()
            let al = await Task.detached { PlayerController.alignSeam(path: path, a: a, b: b) }.value
            let ms = Date().timeIntervalSince(t0) * 1000
            for (tag, aa, bb) in [("硬切", a, b), ("对齐", al?.a ?? a, al?.b ?? b)] {
                let out = dir.appendingPathComponent("seam-\(name == "正弦" ? "sine" : "song")-\(tag == "硬切" ? "hard" : "aligned").wav").path
                let start = aa - 0.2
                let ok = await Task.detached { MPVEngine.renderOffline(input: path, output: out, options: [
                    ("start", String(format: "%.6f", start)), ("ab-loop-a", String(format: "%.6f", aa)), ("ab-loop-b", String(format: "%.6f", bb)),
                    ("ab-loop-count", "3"), ("end", String(format: "%.6f", bb + 0.2))]) }.value
                guard ok, let d = FileManager.default.contents(atPath: out), let w = LoopSeam.readWAV(d) else { TestHooks.log("✗ \(name) \(tag)：离线录制失败"); continue }
                let ch = w.channels, fr = w.samples.count / ch, rate = Double(w.rate)
                func jump(_ k: Int) -> Float { var m: Float = 0; for c in 0..<ch { m = max(m, abs(w.samples[k * ch + c] - w.samples[(k - 1) * ch + c])) }; return m }
                var seams: [Int] = []
                for k in 0..<3 { seams.append(Int(((bb - start) + Double(k) * (bb - aa)) * rate)) }
                var seamMax: Float = 0, natural: Float = 0
                for k in 1..<fr {
                    let nearSeam = seams.contains { abs($0 - k) <= 3 }
                    if nearSeam { seamMax = max(seamMax, jump(k)) } else { natural = max(natural, jump(k)) }
                }
                let okSeam = tag == "硬切" || seamMax <= natural * 1.05 + 0.002
                TestHooks.log("\(okSeam ? "✓" : "✗") \(name) \(tag)：\(fr) 帧，3 处接缝最大跳变 \(String(format: "%.4f", seamMax))，其余位置最大自然跳变 \(String(format: "%.4f", natural))（接缝/自然 = \(String(format: "%.2f", natural > 0 ? seamMax / natural : 0))）\(tag == "对齐" ? String(format: "；对齐 A %+.2fms B %+.2fms，耗时 %.0fms", al?.shiftA ?? 0, al?.shiftB ?? 0, ms) : "")")
            }
        }
    }

    // MARK: 变速变调
    private func speedPitchTests() async {
        TestHooks.log("== 变速 / 变调")
        let dir = TestHooks.outDir
        // 1) 离线：播放中把音调 0 → +2 半音 → −3 半音 +25 音分 → 0，录下真实输出，量切换处的二阶差分（爆音/断音会远超平稳处）
        let src = dir.appendingPathComponent("sine441.wav").path
        var cases: [(String, String, Double)] = [("正弦", src, 0.5)]
        if let song = p.queue.items.first(where: { $0.kind == .audio && $0.title == "雾中灯" }) { cases.append(("歌曲·雾中灯", song.url.path, 30)) }
        let swapsAt = [1.0, 2.0, 3.0]
        for (name, path, st) in cases {
            let out = dir.appendingPathComponent("pitch-\(name == "正弦" ? "sine" : "song").wav").path
            let afs = [SpeedPitch.filter(semitones: 2, cents: 0)!, SpeedPitch.filter(semitones: -3, cents: 25)!, ""]
            let ok = await Task.detached {
                MPVEngine.renderOfflineAFSwap(input: path, output: out, start: st, length: 4, initialAF: "", swaps: Array(zip(swapsAt.map { st + $0 }, afs)))
            }.value
            guard ok, let d = FileManager.default.contents(atPath: out), let w = LoopSeam.readWAV(d) else { TestHooks.log("✗ \(name)：变调离线录制失败"); continue }
            let ch = w.channels, fr = w.samples.count / ch
            var maxD2: Float = 0, zeroRun = 0, maxZeroRun = 0
            var d2s = [Float](repeating: 0, count: fr)
            for k in 2..<fr {
                var m: Float = 0, silent = true
                for c in 0..<ch {
                    let x0 = w.samples[k * ch + c], x1 = w.samples[(k - 1) * ch + c], x2 = w.samples[(k - 2) * ch + c]
                    m = max(m, abs(x0 - 2 * x1 + x2)); if abs(x0) > 1e-5 { silent = false }
                }
                d2s[k] = m; maxD2 = max(maxD2, m)
                if silent { zeroRun += 1; maxZeroRun = max(maxZeroRun, zeroRun) } else { zeroRun = 0 }
            }
            let sorted = d2s.sorted()
            let p999 = sorted[Int(Double(sorted.count) * 0.999)]
            TestHooks.log("  \(name) 播放中变调 3 次：\(fr) 帧；二阶差分最大 \(String(format: "%.4f", maxD2))，99.9% 分位 \(String(format: "%.4f", p999))；最长静音 \(String(format: "%.1f", Double(maxZeroRun) / Double(w.rate) * 1000))ms")
        }
        // 2) 实机：音频
        guard let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) else { return }
        p.selectTab(.nowPlaying)
        p.play(index: ai, from: 20); await sleep(1.0)
        p.speedStep(0.01); await sleep(0.3)
        let s1 = p.engine.getDouble("speed") ?? 0
        p.speedStep(-0.02); await sleep(0.3)
        let s2 = p.engine.getDouble("speed") ?? 0
        TestHooks.log("\(abs(s1 - 1.01) < 1e-6 && abs(s2 - 0.99) < 1e-6 ? "✓" : "✗") 速度 1% 步进：101% → mpv.speed=\(s1)，99% → \(s2)；保持音高=\(p.engine.getString("audio-pitch-correction") ?? "-")")
        p.setPitch(semitones: 2, cents: 0); await sleep(0.6)
        let af1 = p.engine.getString("af") ?? ""
        p.pitchStep(cents: 10); await sleep(0.4)
        let af2 = p.engine.getString("af") ?? ""
        TestHooks.log("\(af1.contains("asetrate=53878") && af2.contains(SpeedPitch.label) ? "✓" : "✗") 变调 +2 半音、再 +10 音分：滤镜生效；速度仍 \(p.engine.getDouble("speed") ?? 0)")
        if !p.speedPitchOpen { p.toggleSpeedPitchPanel() }
        await sleep(0.9)
        await requestShot("s1-speed-pitch-audio")
        p.resetSpeedPitch(); await sleep(0.6)
        TestHooks.log("\(p.speed == 1 && !(p.engine.getString("af") ?? "").contains(SpeedPitch.label) ? "✓" : "✗") 一键恢复：速度 \(p.engine.getDouble("speed") ?? 0)，滤镜里没有变调段")
        // 3) 实机：视频（逐帧黑点检测，变速变调都不应出黑帧）
        if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
            p.play(index: vi, from: 3); await sleep(1.5)
            let st = FrameStats()
            p.videoSurface.glLayer.frameProbe = { w, h, b, t in st.add(w, h, b, t) }
            for k in 0..<8 { p.speedStep(k < 4 ? 0.05 : -0.05); await sleep(0.15) }
            p.setPitch(semitones: -3, cents: 25); await sleep(0.6)
            p.setPitch(semitones: 4, cents: 0); await sleep(0.6)
            await requestShot("s2-speed-pitch-video")
            p.resetSpeedPitch(); await sleep(0.6)
            p.videoSurface.glLayer.frameProbe = nil
            let (f, bf, _, mb, _) = st.take()
            TestHooks.log("\(bf == 0 && f > 0 ? "✓" : "✗") 视频变速变调：渲染 \(f) 帧，整帧黑 \(bf) 帧，单帧最多黑点 \(mb)/25；A/V 差 \(p.engine.getString("avsync") ?? "-")")
        }
        if p.speedPitchOpen { p.toggleSpeedPitchPanel() }
        p.pause()
    }

    // MARK: 副歌检测
    /// 专项截图前把菜单遍历留下的浮层收起，免得挡住要看的东西
    private func closeOverlays(keepLoopEditor: Bool = false) async {
        p.subtitlePanelOpen = false; p.autoEqPanelOpen = false; p.speedPitchOpen = false
        if p.lyricsEnabled { p.setLyricsEnabled(false, quiet: true) }
        if !p.onlineCoversEnabled { p.setOnlineCoversEnabled(true, quiet: true) }
        if UpdateWindow.shared.isVisible { UpdateWindow.shared.close(); UpdateModel.shared.dismiss() }
        if CoverService.useITunes { p.setITunesCovers(false, quiet: true) }
        if !keepLoopEditor { p.loopEditorOpen = false }
        await sleep(0.5)
    }

    private func chorusTests() async {
        TestHooks.log("== 副歌 / 段落检测")
        await closeOverlays()
        // 1) 结构已知的合成曲（testmedia-extra，不进播放列表）：副歌在 24.0 / 62.4 / 91.2 秒，各 19.2 秒
        if let m = TestHooks.mediaDir {
            let f = m.deletingLastPathComponent().appendingPathComponent("testmedia-extra/结构测试 - 副歌在哪.flac")
            if FileManager.default.fileExists(atPath: f.path) {
                let t0 = Date()
                let secs = await Task.detached { PlayerController.detectSections(path: f.path, duration: 115.2) }.value
                let ms = Date().timeIntervalSince(t0) * 1000
                let truth = [24.0, 62.4, 91.2]
                let chorus = secs.filter { $0.label.hasPrefix("副歌") }
                let hit = chorus.filter { c in truth.contains { abs($0 - c.start) < 1.5 } }.count
                let ok = (secs.first.map { b in truth.contains { abs($0 - b.start) < 1.5 } } ?? false)
                TestHooks.log("\(ok ? "✓" : "✗") 合成曲（115 秒，副歌 3 次）：分析 \(String(format: "%.0f", ms))ms；最佳 \(secs.first.map { String(format: "%.1f–%.1f", $0.start, $0.end) } ?? "-")；标成副歌的 \(chorus.count) 段，其中 \(hit) 段落在真实副歌起点 ±1.5 秒内")
                TestHooks.log("  全部段落：" + secs.map { "\($0.label) \(String(format: "%.1f–%.1f", $0.start, $0.end)) ×\($0.repeats)" }.joined(separator: "，"))
            } else { TestHooks.log("○ 缺少 testmedia-extra 合成曲，跳过") }
        }
        // 2) 实机：把结构已知的合成曲临时加进列表，点「找副歌并循环」，截图看进度条上的段落标记，测完移出列表
        guard let m = TestHooks.mediaDir else { return }
        let f = m.deletingLastPathComponent().appendingPathComponent("testmedia-extra/结构测试 - 副歌在哪.flac")
        guard FileManager.default.fileExists(atPath: f.path) else { return }
        p.selectTab(.nowPlaying)
        p.open([f], playNow: true); await sleep(2.0)
        p.findChorusAndLoop()
        for _ in 0..<80 where p.analyzingSections || p.sections.isEmpty { await sleep(0.1) }
        await sleep(1.0)
        let ok = p.abA.map { a in [24.0, 62.4, 91.2].contains { abs($0 - a) < 1.5 } } ?? false
        TestHooks.log("\(ok ? "✓" : "✗") 实机「找副歌并循环」（\(p.current?.title ?? "-")）：进度条标出 \(p.sections.count) 段，循环区间 \(p.abA.map { TimeFormat.precise($0) } ?? "-")–\(p.abB.map { TimeFormat.precise($0) } ?? "-")，正在播放 \(p.isPlaying)")
        if !p.loopEditorOpen && p.abB != nil { p.toggleLoopEditor() }
        await sleep(1.2)
        await requestShot("h1-chorus-loop")
        if p.loopEditorOpen { p.toggleLoopEditor() }
        p.clearABLoop(); p.pause()
        if let i = p.queue.items.firstIndex(where: { $0.url == f }) { p.remove(at: i) }
        await sleep(0.8)
    }

    // MARK: 循环区默认收起，入口点一下展开 / 收起
    private var lyricsDefaultAtStart = false
    private var realLyricsPref: String = "-"
    private var coversDefaultAtStart = false
    private var iTunesDefaultAtStart = true
    private var realCoversPref: String = "-"
    /// 本人偏好文件里的真实值（只读；自测写的是内存沙盒）
    static func realPref(_ k: String) -> String {
        let d = UserDefaults.standard.persistentDomain(forName: "com.tanco.glassplayer")
        return d?[k].map { "\($0)" } ?? "（没有）"
    }


    // MARK: 右键菜单整体核对：顶部菜单栏里和区域相关的项，右键里都要有；并输出「区域 → 右键菜单项」清单
    private func menuAuditTests() async {
        TestHooks.log("== 右键菜单核对（第 7 轮：顶上是「添加歌曲…」「添加文件夹…」；同类不重复；精简不删功能）")
        if let ai = p.queue.items.firstIndex(where: { $0.kind == .audio }) { p.play(index: ai, from: 5); await sleep(1.0); p.pause() }
        func titles(_ nodes: [MenuNode]) -> [String] {
            nodes.flatMap { n -> [String] in
                switch n.kind {
                case .action: return [n.title]
                case .submenu(let c): return [n.title] + titles(c)
                default: return []
                }
            }
        }
        // 1) 顶上两项
        for (area, nodes) in MenuCatalog.allContexts(p) where !area.hasPrefix("参数卡片") {
            let top = nodes.prefix(2).map(\.title)
            TestHooks.log("\(top == ["添加歌曲…", "添加文件夹…"] ? "✓" : "✗") \(area)：最顶上是 \(top.joined(separator: " / "))")
        }
        // 2) 同类不重复：同一个右键菜单里，同名的可点项只能出现一次（各自子菜单里的「提前 / 推迟 0.1 秒」「恢复」这类通用词除外）
        let generic: Set<String> = ["提前 0.1 秒", "推迟 0.1 秒"]
        for (area, nodes) in MenuCatalog.allContexts(p) {
            let leaf = nodes.flatten(prefix: "").map { $0.1.title }.filter { !generic.contains($0) && !$0.hasPrefix("恢复（当前") }
            var seen: [String: Int] = [:]; leaf.forEach { seen[$0, default: 0] += 1 }
            let dup = seen.filter { $0.value > 1 }.map(\.key).sorted()
            let n = nodes.flatten(prefix: "").count, topN = nodes.filter { if case .divider = $0.kind { return false }; if case .header = $0.kind { return false }; return true }.count
            TestHooks.log("\(dup.isEmpty ? "✓" : "✗") \(area)：第一层 \(topN) 项，全部可点 \(n) 项，没有重复\(dup.isEmpty ? "" : "；重复：" + dup.joined(separator: "、"))")
        }
        // 3) 精简不删功能：精简前的每一项，在菜单栏或某个右键菜单里还找得到
        let everywhere = Set((MenuCatalog.menuBar(p) + MenuCatalog.allContexts(p)).flatMap { titles($0.1) })
        let alt: [String: [String]] = ["设置 A 点": ["设置 B 点并开始循环", "取消 A-B 循环"]]
        var lost: [String] = []
        for (_, old, now, _) in MenuCatalog.simplifyMap {
            let cands = [now] + (alt[now] ?? [])
            if !cands.contains(where: { c in everywhere.contains(where: { $0.hasPrefix(c) }) }) { lost.append("\(old) → \(now)") }
        }
        TestHooks.log("\(lost.isEmpty ? "✓" : "✗") 精简不删功能：对照表 \(MenuCatalog.simplifyMap.count) 条，去处全都找得到\(lost.isEmpty ? "" : "；找不到：" + lost.joined(separator: "、"))")
        // 精简前 → 精简后 对照清单
        var cmp = "# 右键菜单精简：精简前 → 精简后\n\n由自测程序按菜单数据生成（\(Date())）。「自测找到的位置」一列是程序在当前菜单数据里实际搜到的路径（最多列 3 处），找不到会写 ✗。\n\n| 区域 | 精简前 | 怎么处理的 | 现在的项 | 自测找到的位置 |\n|---|---|---|---|---|\n"
        let sources: [(String, [MenuNode])] = MenuCatalog.allContexts(p).map { ("右键·" + $0.0, $0.1) } + MenuCatalog.menuBar(p).map { ("菜单栏·" + $0.0, $0.1) }
        func locate(_ c: String) -> [String] {
            var out: [String] = []
            for (src, nodes) in sources {
                for (path, _) in nodes.flatten(prefix: "") {
                    let comps = path.components(separatedBy: " ▸ ")
                    if let k = comps.firstIndex(where: { $0.hasPrefix(c) }) {
                        let loc = ([src] + comps[...k]).joined(separator: " ▸ ")
                        if !out.contains(loc) { out.append(loc) }
                    }
                }
            }
            return out
        }
        for (a, o, n, why) in MenuCatalog.simplifyMap {
            let locs = ([n] + (alt[n] ?? [])).flatMap(locate)
            let where_ = locs.isEmpty ? "✗ 找不到" : locs.prefix(3).joined(separator: "<br>") + (locs.count > 3 ? "<br>…共 \(locs.count) 处" : "")
            cmp += "| \(a) | \(o.replacingOccurrences(of: "|", with: "\\|")) | \(why) | \(n) | \(where_) |\n"
        }
        cmp += "\n## 每个右键菜单的项数\n\n| 区域 | 第一层 | 全部可点项 |\n|---|---|---|\n"
        for (area, nodes) in MenuCatalog.allContexts(p) {
            let topN = nodes.filter { if case .divider = $0.kind { return false }; if case .header = $0.kind { return false }; return true }.count
            cmp += "| \(area) | \(topN) | \(nodes.flatten(prefix: "").count) |\n"
        }
        try? cmp.write(to: TestHooks.outDir.appendingPathComponent("右键菜单精简.md"), atomically: true, encoding: .utf8)
        // 清单
        func describe(_ n: MenuNode, depth: Int) -> String? {
            switch n.kind {
            case .action: return n.title + (n.checked == true ? " ✓" : "")
            case .submenu(let c):
                let kids = c.compactMap { describe($0, depth: depth + 1) }
                return depth >= 1 ? "\(n.title) ▸（\(kids.count) 项）" : "**\(n.title)** ▸ " + kids.joined(separator: " / ")
            case .header: return depth == 0 ? "〔\(n.title)〕" : nil
            case .divider: return nil
            }
        }
        var md = "# 区域 → 右键菜单项\n\n由自测程序按当前菜单数据生成（播放中音频状态；视频相关项在视频播放时可用）。「▸」是子菜单，括号里是子菜单的项。\n\n| 区域 | 右键菜单项 |\n|---|---|\n"
        for (area, nodes) in MenuCatalog.allContexts(p) {
            let items = nodes.compactMap { describe($0, depth: 0) }.map { $0.replacingOccurrences(of: "|", with: "\\|") }
            md += "| \(area)（\(nodes.flatten(prefix: "").count) 个可点项） | " + items.joined(separator: "<br>") + " |\n"
        }
        try? md.write(to: TestHooks.outDir.appendingPathComponent("右键菜单清单.md"), atomically: true, encoding: .utf8)
        TestHooks.log("已写出 右键菜单清单.md（\(MenuCatalog.allContexts(p).count) 个区域）")
        // 均衡器页开着时从菜单切换段数（以前这里会因为新旧段数长度不同而崩溃）
        p.selectTab(.equalizer); await sleep(1.0)
        let bc0 = p.eq.bandCount
        for c in [EQBandCount.thirtyTwo, .sixteen, bc0] { p.setBandCountFromMenu(c); await sleep(0.6) }
        TestHooks.log("✓ 均衡器页开着时连切段数 16 ↔ 32：界面正常（没有崩溃），段数回到 \(p.eq.bandCount.rawValue)")
        p.selectTab(.nowPlaying); await sleep(0.6)
        // 各区域右键菜单弹出截图
        let w = p.mainWindow?.contentView?.bounds ?? .zero
        let shotsList: [(String, String)] = [("m01-ctx-cover", "封面卡片"), ("m02-ctx-playbar", "播放控制条"), ("m03-ctx-progress", "进度条"), ("m04-ctx-lyrics", "歌词条"),
                                             ("m05-ctx-volume", "音量"), ("m06-ctx-subtitle-track", "字幕与音轨按钮"), ("m07-ctx-playlist-blank", "播放列表空白处"),
                                             ("m08-ctx-equalizer", "均衡器"), ("m09-ctx-card-loop", "参数卡片·区间循环"), ("m10-ctx-blank", "空白处"), ("m11-ctx-playlist-row", "播放列表条目")]
        for (shot, area) in shotsList {
            guard let nodes = MenuCatalog.allContexts(p).first(where: { $0.0 == area })?.1 else { continue }
            // 宿主视图是翻转坐标时，y 从上往下量：让菜单从窗口上部弹出，整列都在屏幕里
            let flipped = p.mainWindow?.contentView?.isFlipped == true
            await shootMenu(shot, nodes, at: CGPoint(x: w.midX - 120, y: flipped ? w.height - 40 : 40))
        }
    }

    /// 在一组菜单节点里按路径找到标题以 prefix 开头的项，执行它的动作
    private func fireMenu(_ nodes: [MenuNode], path: [String], prefix: String) {
        var cur = nodes
        for name in path {
            guard let n = cur.first(where: { $0.title == name }), case .submenu(let c) = n.kind else { TestHooks.log("✗ 菜单里没找到 \(name)"); return }
            cur = c
        }
        guard let n = cur.first(where: { $0.title.hasPrefix(prefix) }), case .action(let a) = n.kind else { TestHooks.log("✗ 菜单里没找到 \(prefix)"); return }
        a()
    }


    // MARK: 参数卡片：一次只开一张、切换过渡、磨砂背景、Esc / 点外面收起、视频不掉帧不黑帧
    private final class DtStats: @unchecked Sendable {
        var dts: [Double] = []
        var stamps: [Double] = []
        var busyStart: CFTimeInterval = 0
        var busy: [(Double, Double)] = []
        var busyTotal: Double = 0
    }
    private func measureFrames(_ body: () async -> Void) async -> (fps: Double, p95: Double, maxDt: Double, slow: Int, n: Int) {
        let st = DtStats()
        let id = FrameClock.shared.subscribe { dt, now in st.dts.append(dt); st.stamps.append(now); return true }
        await sleep(0.1); st.dts.removeAll(); st.stamps.removeAll()
        // 诊断：主线程每一段连续忙碌（RunLoop 醒来 → 再次睡下）超过 12ms 的记下来，和慢帧时间对照
        let t0 = CACurrentMediaTime()
        let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, act in
            let t = CACurrentMediaTime()
            if act == .afterWaiting { st.busyStart = t } else if st.busyStart > 0 { let d = t - st.busyStart; st.busyTotal += d; if d > 0.012 { st.busy.append((st.busyStart - t0, d * 1000)) }; st.busyStart = 0 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        await body()
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), obs, .commonModes)
        FrameClock.shared.unsubscribe(id)
        if !st.dts.isEmpty {
            let med = st.dts.sorted()[max(0, st.dts.count / 2)]
            let slowAt = zip(st.dts, st.stamps).filter { $0.0 > med * 1.8 }.map { String(format: "%.2fs(%.0fms)", $0.1 - t0, $0.0 * 1000) }
            let bz = st.busy.map { String(format: "%.2fs+%.0fms", $0.0, $0.1) }
            let dur = CACurrentMediaTime() - t0
            TestHooks.log(String(format: "    诊断 主线程忙 %.0f%%（%.1f ms/帧）", st.busyTotal / dur * 100, st.busyTotal * 1000 / Double(max(1, st.dts.count))))
            TestHooks.log("    诊断 慢帧于 [\(slowAt.joined(separator: " "))]；主线程忙段>12ms \(bz.count) 段 [\(bz.joined(separator: " "))]")
        }
        let d = st.dts.filter { $0 > 0 }.sorted()
        guard !d.isEmpty else { return (0, 0, 0, 0, 0) }
        let mean = d.reduce(0, +) / Double(d.count)
        let p95 = d[min(d.count - 1, Int(Double(d.count) * 0.95))]
        let nominal = d[d.count / 2]
        return (1 / mean, p95 * 1000, d.last! * 1000, d.filter { $0 > nominal * 1.8 }.count, d.count)
    }
    private func postKey(_ code: UInt16) {
        guard let w = p.mainWindow else { return }
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: code) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }
    /// 第8轮：复现「双击专辑卡片后退不回去」——真实事件序列（按下/抬起 clickCount 1，再按下/抬起 clickCount 2）
    private func postDoubleClick(fromTop y: CGFloat, x: CGFloat? = nil) {
        guard let w = p.mainWindow, let v = w.contentView else { return }
        let pt = CGPoint(x: x ?? v.bounds.midX, y: v.bounds.height - y)
        if !w.isKeyWindow { w.makeKeyAndOrderFront(nil) }
        for c in [1, 2] {
            for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: c, pressure: t == .leftMouseDown ? 1 : 0) {
                    NSApp.sendEvent(e)   // 经 NSApp 分发：本地事件监听（专辑卡双击）也能看到
                }
            }
        }
    }
    private func stateDump(_ tag: String) {
        let w = p.mainWindow
        TestHooks.log("  [状态 \(tag)] lifted=\(p.isLifted) tab=\(p.tab) card=\(String(describing: p.activeCard)) mini=\(p.isPinnedMini) shortcuts=\(p.showShortcuts) video=\(p.isVideo) chrome=\(p.chromeVisible) playing=\(p.isPlaying) cur=\(p.queue.currentIndex ?? -1) center=\(p.carousel.centeredIndex) pos=\(String(format: "%.2f", p.carousel.position)) full=\(w?.styleMask.contains(.fullScreen) ?? false) frame=\(w.map { NSStringFromRect($0.frame) } ?? "-") zoomed=\(w?.isZoomed ?? false)")
    }
    /// 入口普查（第 8 轮）：所有「单击、双击、回车」能进入的地方逐个进一次，看进到了什么状态，再只用 Esc 退回干净的初始状态。
    /// 任何一个入口进去后 Esc 退不回来（或者按完还有残留），就是漏网状态。
    private func entryAudit() async {
        TestHooks.log("== 入口普查（单击 / 双击 / 回车）")
        await closeOverlays()
        p.selectTab(.nowPlaying)
        guard let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }),
              let vi = p.queue.items.firstIndex(where: { $0.kind == .video }), let v = p.mainWindow?.contentView else { TestHooks.log("✗ 入口普查：素材不全"); return }
        let cardY = v.bounds.height * 0.40
        func sig() -> String {
            let full = p.mainWindow?.styleMask.contains(.fullScreen) ?? false
            var s: [String] = []
            if p.tab != .nowPlaying { s.append("tab=\(p.tab)") }
            if p.isLifted { s.append("翻面") }
            if p.viewer.isOpen { s.append("观赏") }
            if let c = p.activeCard { s.append("卡片=\(c)") }
            if p.videoStageOpen { s.append("视频舞台") }
            if p.isPinnedMini { s.append("迷你窗") }
            if p.showShortcuts { s.append("快捷键面板") }
            if full { s.append("全屏") }
            if p.isScrubbing { s.append("拖进度") }
            if p.scanDirection != 0 { s.append("快进") }
            return s.isEmpty ? "无" : s.joined(separator: "+")
        }
        func key(_ c: UInt16) async { p.mainWindow?.makeKeyAndOrderFront(nil); await sleep(0.1); if c == 53 { postKey(53) } else { postKeyCode(c) }; await sleep(c == 53 ? 0.9 : 1.2) }
        func check(_ name: String, expect: String?, alsoOK: String? = nil, _ act: () async -> Void) async {
            await closeOverlays(); p.selectTab(.nowPlaying)
            // 先确保主窗口在最前、是 key：macOS 下点后台窗口的第一下只会把窗口叫到前面，不会传给卡片（第8轮查实）
            activateIfAllowed(); p.mainWindow?.makeKeyAndOrderFront(nil); await sleep(0.5)
            let before = sig()
            await act()
            let got = sig()
            var escs = 0
            while sig() != "无" && escs < 4 { await key(53); escs += 1 }
            let clean = sig() == "无"
            let okEnter = (expect.map { got.contains($0) } ?? (got == "无")) || (alsoOK.map { got == $0 } ?? false)
            TestHooks.log("\(okEnter && clean && before == "无" ? "✓" : "✗") 入口 · \(name)：进入后 \(got)\(expect.map { "（应为 \($0)）" } ?? (alsoOK.map { "（应为 不进入或\($0)）" } ?? "（不进入任何状态）"))；Esc ×\(escs) 后 \(sig())\(before == "无" ? "" : "；开始前就不干净：\(before)")")
        }
        // 轮播转到某张卡后，等它真正停稳（位置到位 + 停稳后的选曲也做完）再点，免得点到正在滑过的别的卡
        func settle(_ i: Int) async -> String {
            let t0 = CACurrentMediaTime()
            while abs(p.carousel.position - Double(i)) > 0.002 && CACurrentMediaTime() - t0 < 5 { await sleep(0.05) }
            await sleep(0.4)
            return String(format: "停稳用时 %.1f 秒，位置 %.3f，当前曲目 %@", CACurrentMediaTime() - t0, p.carousel.position, p.queue.current?.title ?? "-")
        }
        func atAudio() async { p.play(index: ai, from: 10); p.carousel.jump(to: ai); p.runCarousel(); _ = await settle(ai) }
        func atVideoCard() async {
            p.pause(); let pos0 = p.carousel.position; p.carousel.jump(to: vi); p.runCarousel()
            TestHooks.log("    转到视频卡：从位置 \(String(format: "%.2f", pos0)) 到 \(vi)；固定等 1.4 秒时位置 …")
            await sleep(1.4); TestHooks.log("      1.4 秒时位置 \(String(format: "%.3f", p.carousel.position))")
            TestHooks.log("      \(await settle(vi))")
        }

        await atAudio()   // 启动时可能恢复在视频上（视频舞台），先回到音频卡，普查从干净状态开始
        await check("轮播 单击旁边的音频卡（换歌）", expect: nil) { await atAudio(); postClick(fromTop: cardY, x: v.bounds.midX + 230); await sleep(1.5) }
        await check("轮播 单击中间的音频卡", expect: "翻面") { await atAudio(); postClick(fromTop: cardY); await sleep(1.2) }
        await check("轮播 双击中间的音频卡（观赏）", expect: "观赏") { await atAudio(); await humanDoubleClick(fromTop: cardY, x: v.bounds.midX); await sleep(1.5) }
        await check("轮播 系统连发双击中间的音频卡（两下几乎同时）", expect: "观赏") { await atAudio(); postDoubleClick(fromTop: cardY); await sleep(1.5) }
        await check("轮播 双击旁边的音频卡（切过去并观赏）", expect: "观赏") { await atAudio(); await humanDoubleClick(fromTop: cardY, x: v.bounds.midX + 230); await sleep(1.5) }
        await check("回车（中间是音频卡）", expect: "翻面") { await atAudio(); await key(36) }
        await check("轮播 单击视频卡", expect: "视频舞台") { await atAudio(); await atVideoCard(); activateIfAllowed(); p.mainWindow?.makeKeyAndOrderFront(nil); for _ in 0..<15 { if p.mainWindow?.isKeyWindow == true { break }; p.mainWindow?.makeKeyAndOrderFront(nil); activateIfAllowed(); await sleep(0.1) }; TestHooks.log("      点击前主窗口 key=\(p.mainWindow?.isKeyWindow ?? false) active=\(NSApp.isActive) aux=\(UpdateWindow.shared.isVisible)"); postClick(fromTop: cardY); await sleep(1.8); TestHooks.log("      单击后当前曲目 \(p.queue.current?.title ?? "-")，视频舞台 \(p.videoStageOpen)") }
        await check("轮播 双击视频卡（TANCO 实测的路径）", expect: "视频舞台") { await atAudio(); await atVideoCard(); postDoubleClick(fromTop: cardY); await sleep(1.8) }
        await check("视频退回轮播后 回车", expect: "视频舞台") { p.play(index: vi, from: 2); await sleep(1.5); p.exitVideoStage(); await sleep(0.9); await key(36) }
        await check("视频退回轮播后 空格继续播放", expect: "视频舞台") { p.play(index: vi, from: 2); await sleep(1.5); p.exitVideoStage(); await sleep(0.9); await key(49) }
        await check("播放列表 双击视频行（再回正在播放）", expect: "视频舞台") {
            p.selectTab(.playlist); await sleep(1.0); p.play(index: vi, from: 2); await sleep(1.2)
            TestHooks.log("    在播放列表页双击视频后：\(sig())（\(p.tab == .nowPlaying ? "自动切回正在播放页" : "仍在播放列表页")）")
            p.selectTab(.nowPlaying); await sleep(1.2)
        }
        await check("视频画面 双击（全屏）", expect: "全屏") {
            p.play(index: vi, from: 2); await sleep(1.6)
            postDoubleClick(fromTop: v.bounds.height * 0.40); await sleep(2.5)
        }
        await atAudio(); await closeOverlays()
        TestHooks.log("  不进入状态的点击（只改数值或跳转，列出备查）：均衡器频段双击＝归零；歌词行单击＝跳到该句；顶部分段控件单击＝切页（页本身已在闭环表）；变速卡里点数值＝原地编辑框（Esc / 失焦 / 收卡都会关）；迷你窗遮罩单击＝快捷键面板（已在闭环表）；字幕 / 耳机型号 / 区间时间 / 预设名输入框回车＝提交")
    }
    /// 进程实际占用内存（和「活动监视器」的“内存”一栏同一口径：phys_footprint）
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// TANCO 2026-11-20「所有封面、整个软件至少 2K」：逐首核对卡片封面、磨砂底、背景、视频截帧的实际像素，记内存
    private func resolutionAudit() async {
        TestHooks.log("== 分辨率普查（至少 2K：长边 ≥ 2048，原图更小按原图、不放大）")
        await closeOverlays(); p.selectTab(.nowPlaying)
        let m0 = Self.footprintMB()
        let backing = p.mainWindow?.backingScaleFactor ?? 2
        TestHooks.log(String(format: "  屏幕 backingScaleFactor %.0f；开始时内存 %.0f MB；封面缓存 %d 张 %.0f MB", backing, m0, p.covers.count, Double(p.covers.bytes) / 1_048_576))
        for it in p.queue.items { p.ensureDetails(it) }
        let t0 = CACurrentMediaTime()
        while p.queue.items.contains(where: { p.covers.art(for: $0.id) == nil }) && CACurrentMediaTime() - t0 < 20 { await sleep(0.2) }
        await sleep(1.0)
        var bad = 0
        for it in p.queue.items {
            guard let a = p.covers.art(for: it.id) else { TestHooks.log("✗ 分辨率 · 「\(it.title)」封面没读出来"); bad += 1; continue }
            let L = { (g: CGImage) in max(g.width, g.height) }
            var src = 0
            var srcNote = ""
            if a.origin == "file", it.kind == .audio, let d = await Task.detached(operation: { await FullCover.fileCoverData(it.url) }).value, let sz = MetadataReader.pixelSize(d) {
                src = Int(max(sz.width, sz.height)); srcNote = "原图 \(Int(sz.width))×\(Int(sz.height))"
            } else if a.origin == "generated" { src = CoverStore.maxSide; srcNote = "默认封面（程序画）" }
            else if it.kind == .video { src = 0; srcNote = "视频截帧" }
            let want = src > 0 ? min(CoverStore.maxSide, src) : 0
            let imgOK = want == 0 ? L(a.image) >= min(CoverStore.maxSide, L(a.image)) : L(a.image) >= want
            let blurOK = L(a.frosted) >= CoverStore.blurSide && L(a.backdrop) >= CoverStore.blurSide
            let ok = imgOK && blurOK
            if !ok { bad += 1 }
            let low = src > 0 && src < CoverStore.maxSide ? "（原图本身低于 2K，如实显示，没有硬拉）" : ""
            TestHooks.log("\(ok ? "✓" : "✗") 分辨率 · 「\(it.title)」\(it.kind == .video ? "视频" : "音频")/\(a.origin)：\(srcNote)；卡片 \(a.image.width)×\(a.image.height)；磨砂底 \(a.frosted.width)×\(a.frosted.height)；背景 \(a.backdrop.width)×\(a.backdrop.height)\(low)")
        }
        let m1 = Self.footprintMB()
        TestHooks.log(String(format: "\(bad == 0 ? "✓" : "✗") 分辨率普查：%d 首，不达标 %d；内存 %.0f → %.0f MB；封面缓存 %d 张 %.0f MB（上限 %.0f MB）", p.queue.items.count, bad, m0, m1, p.covers.count, Double(p.covers.bytes) / 1_048_576, Double(p.covers.budget) / 1_048_576))
        // 观赏模式用原图：打开一次看实际像素
        if let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "Midnight Drive" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) {
            p.play(index: ai, from: 5); p.carousel.jump(to: ai); p.runCarousel(); await sleep(1.5)
            p.openCoverViewer(from: .playbar)
            var full = false
            for _ in 0..<50 { if p.viewer.view?.isFullRes == true { full = true; break }; await sleep(0.1) }
            TestHooks.log("\(full ? "✓" : "✗") 分辨率 · 观赏模式用原图：\(p.viewer.view?.pixelInfo ?? "-")")
            p.closeCoverViewer(); await sleep(1.0)
        }
    }

    /// 第8轮观赏：带修饰键的按键（⌘Y、⌘=、⌥→ …），走全局事件队列（按键监听、菜单快捷键都能看到）
    private func postKeyMods(_ code: UInt16, _ ch: String, _ mods: NSEvent.ModifierFlags) {
        guard let w = p.mainWindow else { return }
        var chars = ch
        switch code { case 123: chars = String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!.description); case 124: chars = String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!.description)
        case 125: chars = String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!.description); case 126: chars = String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!.description); default: break }
        var m = mods
        if (123...126).contains(code) { m.insert(.numericPad); m.insert(.function) }
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: m, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }
    /// 像人一样点：经 NSApp.sendEvent 分发（本地事件监听能看到），坐标从窗口内容顶部量
    private func sendMouse(_ t: NSEvent.EventType, fromTop y: CGFloat, x: CGFloat, clicks: Int) {
        guard let w = p.mainWindow, let v = w.contentView else { return }
        let pt = CGPoint(x: x, y: v.bounds.height - y)
        if let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: t == .leftMouseDown ? 1 : 0) {
            NSApp.sendEvent(e)
        }
    }
    private func ensureKeyWindow() async {
        if NSApp.isActive && (p.mainWindow?.isKeyWindow ?? false) { return }
        activateIfAllowed()
        p.mainWindow?.makeKeyAndOrderFront(nil)
        await sleep(0.2)
        for _ in 0..<15 {
            if NSApp.isActive && (p.mainWindow?.isKeyWindow ?? false) { return }
            activateIfAllowed()
            p.mainWindow?.makeKeyAndOrderFront(nil)
            await sleep(0.1)
        }
    }
    private func humanClick(fromTop y: CGFloat, x: CGFloat) async {
        await ensureKeyWindow()
        sendMouse(.leftMouseDown, fromTop: y, x: x, clicks: 1); await sleep(0.06)
        sendMouse(.leftMouseUp, fromTop: y, x: x, clicks: 1)
    }
    /// 真双击：两下之间隔 gap 秒（人手快速双击约 0.1–0.2 秒）
    private func humanDoubleClick(fromTop y: CGFloat, x: CGFloat, gap: Double = 0.12) async {
        await ensureKeyWindow()
        sendMouse(.leftMouseDown, fromTop: y, x: x, clicks: 1); await sleep(0.05)
        sendMouse(.leftMouseUp, fromTop: y, x: x, clicks: 1); await sleep(gap)
        sendMouse(.leftMouseDown, fromTop: y, x: x, clicks: 2); await sleep(0.05)
        sendMouse(.leftMouseUp, fromTop: y, x: x, clicks: 2)
    }
    /// 按住拖动一段距离再松开（观赏里超过数个像素应算平移，不算单击退出）
    private func humanDrag(fromTop y: CGFloat, x: CGFloat, dx: CGFloat, dyFromTop: CGFloat) async {
        await ensureKeyWindow()
        sendMouse(.leftMouseDown, fromTop: y, x: x, clicks: 1); await sleep(0.03)
        sendMouse(.leftMouseDragged, fromTop: y + dyFromTop * 0.5, x: x + dx * 0.5, clicks: 1); await sleep(0.03)
        sendMouse(.leftMouseDragged, fromTop: y + dyFromTop, x: x + dx, clicks: 1); await sleep(0.03)
        sendMouse(.leftMouseUp, fromTop: y + dyFromTop, x: x + dx, clicks: 1)
    }
    /// 背面双击过程中有没有先翻回正面
    private func watchFlipBack(_ secs: Double) -> Task<Bool, Never> {
        Task { @MainActor in var seen = false; let t0 = CACurrentMediaTime(); while CACurrentMediaTime() - t0 < secs { if !p.isLifted { seen = true }; try? await Task.sleep(nanoseconds: 8_000_000) }; return seen }
    }
    private func judgeFrames(_ m: (fps: Double, p95: Double, maxDt: Double, slow: Int, n: Int)) -> String {
        String(format: "%.0f fps，p95 %.1f ms，最长 %.1f ms，慢帧 %d/%d", m.fps, m.p95, m.maxDt, m.slow, m.n)
    }
    private func postKeyCode(_ code: UInt16) {
        guard let w = p.mainWindow else { return }
        let ch = code == 36 ? "\r" : ""
        for t in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code) {
                NSApp.postEvent(e, atStart: false)
            }
        }
    }
    private func postClick(fromTop y: CGFloat, x: CGFloat? = nil) {
        guard let w = p.mainWindow, let v = w.contentView else { return }
        let pt = CGPoint(x: x ?? v.bounds.midX, y: v.bounds.height - y)
        if !w.isKeyWindow { w.makeKeyAndOrderFront(nil) }
        for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: t == .leftMouseDown ? 1 : 0) {
                w.sendEvent(e)   // 直接交给播放器窗口（不经过全局事件队列，免得被别的窗口 / 菜单接走）
            }
        }
    }

    /// t180u 定向：只拍琉璃、朱青卡片页窗口（主窗口，不含桌面其他 App），用于核对原四位置。
    private func yunwenShots() async {
        TestHooks.log("== 原四云纹定向截图（琉璃 / 朱青卡片页）")
        await closeOverlays()
        let theme0 = p.theme
        p.selectTab(.nowPlaying)
        if let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) { p.play(index: ai, from: 8) }
        p.setTheme(.liuli); await sleep(2.0)
        await requestShot("y1-nowplaying-liuli-yuansi")
        p.setTheme(.zhuqing); await sleep(2.0)
        await requestShot("y2-nowplaying-zhuqing-yuansi")
        p.setTheme(theme0); await sleep(0.8)
        TestHooks.log("✓ 原四定向截图已请求（y1 琉璃、y2 朱青）")
    }

    /// 「朱青」主题：正在播放 / 播放列表 / 视频 / 参数卡片各截一张；核对它在主题列表和菜单里、其他主题配色没变
    private func zhuqingTests() async {
        TestHooks.log("== 朱青主题（中国红 + 中国蓝，赤金云纹）")
        await closeOverlays()
        let theme0 = p.theme
        let others = AppTheme.allCases.filter { $0 != .zhuqing }.map { "\($0.rawValue)=\($0.palette.map { [$0.primary.hex, $0.secondary.hex, $0.tertiary.hex, $0.glassTint.hex, $0.accent.hex].joined(separator: ",") } ?? "nil")" }
        let inMenu: [String] = { if case .submenu(let c) = MenuCatalog.themeMenu(p).kind { return c.map(\.title) }; return [] }()
        let blankHasTheme = MenuCatalog.blank(p).contains { $0.title == "配色主题" }
        TestHooks.log("\(inMenu.contains(AppTheme.zhuqingName) ? "✓" : "✗") 菜单栏 ▸ 配色主题 里有「\(AppTheme.zhuqingName)」（共 \(inMenu.count) 套）")
        TestHooks.log("\(blankHasTheme ? "✗" : "✓") 窗口空白处右键里没有「配色主题」（改用右上角调色板）")
        p.selectTab(.nowPlaying)
        if let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) { p.play(index: ai, from: 8) }
        if UserDefaults.standard.bool(forKey: "zqAfterVideo"), let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
            p.play(index: vi, from: 5); await sleep(3.0)
            if let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) { p.play(index: ai, from: 8) }
            await sleep(1.0)
        }
        p.setTheme(.zhuqing); await sleep(2.0)
        dumpLayers("zq-layers")
        let pal = p.palette
        TestHooks.log("\(p.theme == .zhuqing ? "✓" : "✗") 切到「\(AppTheme.zhuqingName)」：底 \(pal.primary.hex) 光 \(pal.secondary.hex) / \(pal.tertiary.hex) 玻璃 \(pal.glassTint.hex) 强调 \(pal.accent.hex)")
        await requestShot("z1-zhuqing-nowplaying")
        p.selectTab(.playlist); await sleep(1.3); await requestShot("z2-zhuqing-playlist")
        p.selectTab(.nowPlaying); await sleep(1.0)
        withAnimation(Motion.panel) { p.activeCard = .speedPitch }; await sleep(1.0)
        await requestShot("z4-zhuqing-card")
        p.closeCard(); await sleep(0.6)
        if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
            p.play(index: vi, from: 5); await sleep(2.5)
            await requestShot("z3-zhuqing-video")
            withAnimation(Motion.panel) { p.activeCard = .subtitle }; await sleep(1.0)
            await requestShot("z5-zhuqing-card-on-video")
            p.closeCard(); await sleep(0.6)
        }
        let after = AppTheme.allCases.filter { $0 != .zhuqing }.map { "\($0.rawValue)=\($0.palette.map { [$0.primary.hex, $0.secondary.hex, $0.tertiary.hex, $0.glassTint.hex, $0.accent.hex].joined(separator: ",") } ?? "nil")" }
        TestHooks.log("\(after == others ? "✓" : "✗") 其他 \(others.count) 套主题的配色在切换前后一致（新主题是独立的一套）")
        p.setTheme(theme0); await sleep(1.0)
    }

    /// 诊断：把窗口的图层树（类名、位置、不透明度、隐藏、presentation 不透明度）写进 testOut/<name>.txt
    private func dumpLayers(_ name: String) {
        guard let root = p.mainWindow?.contentView?.layer, let out = UserDefaults.standard.string(forKey: "testOut") else { return }
        var lines: [String] = []
        func walk(_ l: CALayer, _ d: Int) {
            let po = l.presentation()?.opacity ?? l.opacity
            lines.append(String(repeating: "  ", count: d) + "\(type(of: l)) \(Int(l.frame.minX)),\(Int(l.frame.minY)) \(Int(l.frame.width))x\(Int(l.frame.height)) op=\(l.opacity) pop=\(po) hid=\(l.isHidden) bg=\(l.backgroundColor.map { "\($0.components ?? [])" } ?? "-") anim=\(l.animationKeys() ?? [])")
            if d < 14 { for c in l.sublayers ?? [] { walk(c, d + 1) } }
        }
        walk(root, 0)
        try? lines.joined(separator: "\n").write(toFile: out + "/" + name + ".txt", atomically: true, encoding: .utf8)
    }

    // MARK: 断网
    /// 断网时：本地功能照常；联网功能安静失败、回落到默认封面或已有缓存、不弹框、不反复重试
    private func offlineTests() async {
        TestHooks.log("== 断网（自测里模拟：所有联网请求立刻以“未连接到互联网”失败，和真断网时系统给的错误一样；不改系统网络设置）")
        TestHooks.log("\(Net.simulateOffline ? "✓" : "✗") 模拟断网已打开；启动、读播放列表正常（\(p.queue.items.count) 项）")
        await closeOverlays()
        guard let m = TestHooks.mediaDir else { return }
        let extra = m.deletingLastPathComponent().appendingPathComponent("testmedia-extra")
        // 种上一份以前联网时查到的封面缓存（模拟“以前联网听过周杰伦《叶惠美》”；其他专辑都当作没查过）
        if let seed = UserDefaults.standard.string(forKey: "seedCoverCache") {
            var n = 0
            for f in ((try? FileManager.default.contentsOfDirectory(atPath: seed)) ?? []) where f.hasSuffix(".json") {
                guard let d = FileManager.default.contents(atPath: seed + "/" + f), let found = try? JSONDecoder().decode(CoverService.Found.self, from: d), found.album.contains("惠美") else { continue }
                let k = String(f.dropLast(5))
                for ext in ["jpg", "json"] { try? FileManager.default.copyItem(atPath: "\(seed)/\(k).\(ext)", toPath: CoverService.file(k, ext).path) }
                n += 1
            }
            TestHooks.log("  种入以前联网时查到的封面缓存 \(n) 张（《叶惠美》）")
        }
        // 主线程卡没卡：每 10ms 打一次点，记最长间隔
        var maxGap = 0.0, last = CACurrentMediaTime(), watching = true
        let watcher = Task { @MainActor in
            while watching { try? await Task.sleep(nanoseconds: 10_000_000); let n = CACurrentMediaTime(); maxGap = max(maxGap, n - last); last = n }
        }
        func openAndWait(_ f: URL) async -> (MediaItem?, Double) {
            let t0 = Date()
            p.open([f], playNow: true)
            for _ in 0..<150 {
                await sleep(0.1)
                if let it = p.queue.items.first(where: { $0.url == f }), p.coverOutcome[it.id] != nil || p.hasFileCover(it.id) { return (it, Date().timeIntervalSince(t0)) }
            }
            return (p.queue.items.first(where: { $0.url == f }), Date().timeIntervalSince(t0))
        }
        let jay = extra.appendingPathComponent("lyrics/周杰伦 - 晴天（自测音轨）.m4a")
        let queen = extra.appendingPathComponent("covers/Queen - Bohemian Rhapsody (test tone).m4a")
        let adele = extra.appendingPathComponent("covers/Adele - Rolling in the Deep (test tone).m4a")
        let embedded = extra.appendingPathComponent("covers/内嵌封面测试 - Coldplay Yellow.m4a")
        let a0 = Net.attempts
        // 1) 以前查到过的封面：离线照常显示（本地缓存）
        let (j, tj) = await openAndWait(jay)
        if let j { await sleep(0.8); TestHooks.log("\(p.art(for: j)?.origin == "online" ? "✓" : "✗") 以前联网查到的封面：离线照常显示（本地缓存，\(Int(tj * 1000))ms，来源 \(p.art(for: j)?.origin ?? "-")）") }
        await requestShot("o1-offline-cached-cover")
        // 2) 内嵌封面：不联网
        let (e, _) = await openAndWait(embedded)
        if let e { await sleep(0.6); TestHooks.log("\(p.art(for: e)?.origin == "file" ? "✓" : "✗") 文件内嵌封面：照常显示（来源 \(p.art(for: e)?.origin ?? "-")）") }
        // 3) 没查过的封面：安静回落默认封面，不写“没找到”（联网后还会再查）
        let a1 = Net.attempts
        let (q, tq) = await openAndWait(queen)
        if let q {
            await sleep(0.8)
            let k = CoverLookup.cacheKey(p.coverQuery(p.details(for: q)?.item ?? q))
            let noneWritten = FileManager.default.fileExists(atPath: CoverService.file(k, "none").path)
            TestHooks.log("\(p.art(for: q)?.origin == "generated" && p.coverOutcome[q.id] == "failed" && !noneWritten && tq < 3 ? "✓" : "✗") 没查过的封面：\(Int(tq * 1000))ms 内回落默认封面（结果 \(p.coverOutcome[q.id] ?? "-")），没记成“没找到”，联网后会再查；发出请求 \(Net.attempts - a1) 次（不重试）")
        }
        await requestShot("o2-offline-default-cover")
        // 4) 退避：确认没网后 90 秒内别的歌也不再发请求
        let a2 = Net.attempts
        let (ad, ta) = await openAndWait(adele)
        if let ad { TestHooks.log("\(Net.attempts == a2 && p.art(for: ad)?.origin == "generated" ? "✓" : "✗") 刚确认没网：下一首直接用默认封面，\(Int(ta * 1000))ms，发出请求 \(Net.attempts - a2) 次（90 秒内不再试）") }
        // 5) 歌词：本地 .lrc 照常；联网歌词安静不显示
        let lyrics0 = p.lyricsEnabled
        p.setLyricsEnabled(true, quiet: true)
        let lrcSong = extra.appendingPathComponent("covers").appendingPathComponent("Coldplay - Yellow (test tone).m4a")
        _ = await openAndWait(lrcSong); await sleep(1.5)
        let localLyrics = (p.lyrics?.lines.count ?? 0) > 0
        TestHooks.log("\(localLyrics ? "✓" : "○") 本地同名 .lrc 歌词：\(localLyrics ? "照常显示 \(p.lyrics?.lines.count ?? 0) 行" : "这首没有本地歌词")")
        _ = await openAndWait(queen); await sleep(1.5)
        TestHooks.log("\(!p.showsLyricsStrip && !p.lyricsSearching ? "✓" : "✗") 联网歌词：没网时不显示歌词条、不提示、不卡（查询中=\(p.lyricsSearching)）")
        p.setLyricsEnabled(lyrics0, quiet: true)
        // 6) 在线字幕：卡片里一句小提示
        if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
            p.play(index: vi, from: 3); await sleep(2.0)
            p.subtitleResults = []
            p.toggleSubtitlePanel()
            for _ in 0..<60 { await sleep(0.1); if !p.subtitleSearching { break } }
            await sleep(0.4)
            TestHooks.log("\(p.subtitleMessage.contains("没有联网") ? "✓" : "✗") 在线字幕：「\(p.subtitleMessage)」（只在字幕卡片里显示）")
            await requestShot("o3-offline-subtitle-card")
            p.closeCard(); await sleep(0.5)
            TestHooks.log("\(p.isVideo && p.engine.getString("pause") != nil ? "✓" : "✗") 视频照常播放（本地文件）")
        }
        // 7) 没有弹框
        let panels = NSApp.windows.filter { $0.isVisible && ($0 is NSPanel) && !($0.className.contains("Menu")) }
        TestHooks.log("\(NSApp.modalWindow == nil && panels.isEmpty ? "✓" : "✗") 没有弹出任何提示框（模态窗口 \(NSApp.modalWindow == nil ? "无" : "有")，面板 \(panels.count) 个）")
        watching = false; _ = await watcher.value
        TestHooks.log("\(maxGap < 0.25 ? "✓" : "✗") 联网功能失败时界面不卡：主线程最长间隔 \(Int(maxGap * 1000))ms")
        TestHooks.log("  断网测试共发出联网请求 \(Net.attempts - a0) 次（全部立即失败）")
        p.pause(); await sleep(0.3)
    }

    // MARK: 检查更新（只在测试副本 com.tanco.glassplayer.updatetest 里跑：Sparkle 会写这个副本自己的偏好，不碰本人的）
    private func updateTests() async {
        let um = UpdateModel.shared
        TestHooks.log("== 检查更新（Sparkle \(Bundle(identifier: "org.sparkle-project.Sparkle")?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")，本地测试服务器）")
        TestHooks.log("  App 标识 \(Bundle.main.bundleIdentifier ?? "-")，版本 \(um.currentVersion)（\(um.currentBuild)）")
        let info = Bundle.main.infoDictionary ?? [:]
        func no(_ k: String) -> Bool { (info[k] as? Bool) == false }
        TestHooks.log("\(no("SUEnableAutomaticChecks") && no("SUAutomaticallyUpdate") && no("SUAllowsAutomaticUpdates") && no("SUEnableSystemProfiling") ? "✓" : "✗") Info.plist：自动检查、自动下载安装、系统画像上报全关")
        TestHooks.log("\((info["SUPublicEDKey"] as? String)?.count == 44 ? "✓" : "✗") 有 EdDSA 公钥（SUPublicEDKey）")
        TestHooks.log("\(!um.isInstantiated ? "✓" : "✗") 启动后没有创建更新器（不联网、没有定时任务）")
        let feed = um.feedURL ?? ""
        func waitPhase(_ ok: (UpdateModel.Phase) -> Bool, _ secs: Double) async -> Bool {
            for _ in 0..<Int(secs * 10) { if ok(um.phase) { return true }; await sleep(0.1) }
            return ok(um.phase)
        }
        // 1) 断网：更新源连不上 → 小窗里一句话，不弹框
        um.feedOverride = UserDefaults.standard.string(forKey: "offlineFeedURL") ?? "https://liuli-update.invalid/appcast.xml"
        let t0 = Date()
        um.checkNow()
        let failed = await waitPhase({ if case .failed = $0 { return true }; return false }, 20)
        await sleep(0.5)
        if case .failed(let s) = um.phase { TestHooks.log("\(failed ? "✓" : "✗") 断网时检查更新：\(Int(Date().timeIntervalSince(t0) * 1000))ms 后在小窗里提示「\(s)」") }
        else { TestHooks.log("✗ 断网时检查更新：状态 \(um.phase)") }
        let panels = NSApp.windows.filter { $0.isVisible && ($0 is NSPanel) }
        TestHooks.log("\(NSApp.modalWindow == nil && panels.isEmpty ? "✓" : "✗") 没有弹出提示框")
        await requestShot("u1-update-offline", kind: "small")
        func idle() async { for _ in 0..<150 { if !um.sessionInProgress { break }; await sleep(0.1) } }
        // 2) 签名不对的更新包：拒绝安装
        if let bad = UserDefaults.standard.string(forKey: "badFeedURL") {
            await idle()
            um.feedOverride = bad
            um.checkNow()
            if await waitPhase({ if case .found = $0 { return true }; return false }, 20) {
                TestHooks.log("  篡改过的更新包：发现「\(um.phase)」，点「安装并重启」")
                um.install()
                let rejected = await waitPhase({ if case .failed = $0 { return true }; return false }, 30)
                if case .failed(let s) = um.phase { TestHooks.log("\(rejected && s.contains("签名") ? "✓" : "✗") 签名不对：「\(s)」，没有安装") } else { TestHooks.log("✗ 签名不对的包：状态 \(um.phase)") }
                await requestShot("u2-update-bad-signature", kind: "small")
            } else { TestHooks.log("✗ 篡改过的更新包：没发现更新（\(um.phase)）") }
        }
        // 3) 正常更新：检查 → 发现新版本 → 下载 → 校验签名 → 替换 → 重启
        await idle()
        um.feedOverride = nil
        TestHooks.log("  更新源 \(feed)")
        um.checkNow()
        guard await waitPhase({ if case .found = $0 { return true }; return false }, 20) else { TestHooks.log("✗ 没发现新版本（\(um.phase)）"); finish(); return }
        TestHooks.log("✓ 发现新版本：\(um.phase)；更新说明「\(um.notes.prefix(60))」")
        await requestShot("u3-update-found", kind: "small")
        TestHooks.log("  点「安装并重启」（下载、校验 EdDSA 签名、替换、重启由 Sparkle 完成，重启后的新版本会写一个标记文件）")
        try? "done".write(to: TestHooks.outDir.appendingPathComponent("selftest.done"), atomically: true, encoding: .utf8)
        um.install()
        // 之后 App 会被 Sparkle 结束；记录看到的阶段
        var seen: [String] = []
        for _ in 0..<300 {
            let d = "\(um.phase)"; if seen.last != d { seen.append(d); TestHooks.log("  阶段：\(d)") }
            if case .failed = um.phase { TestHooks.log("✗ 安装失败"); break }
            await sleep(0.1)
        }
    }

    private func cardTests() async {
        TestHooks.log("== 参数卡片（一次只开一张，磨砂背景，Esc / 点外面收起）")
        await closeOverlays()
        let memStart = Self.footprintMB()
        TestHooks.log(String(format: "  内存 卡片测试开始 %.0f MB（封面缓存 %d 张 %.0f MB）", memStart, p.covers.count, Double(p.covers.bytes) / 1_048_576))
        defer { TestHooks.log(String(format: "  内存 卡片测试结束 %.0f MB（开始 %.0f MB；封面缓存 %d 张 %.0f MB）", Self.footprintMB(), memStart, p.covers.count, Double(p.covers.bytes) / 1_048_576)) }
        let theme0 = p.theme
        p.selectTab(.nowPlaying)
        guard let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) else { return }
        p.play(index: ai, from: 10); await sleep(1.5)
        p.setLoopRange(12, 18, quiet: true)
        // EQ 入口：不在顶部分段里，挪到音量旁（悬停音量时出现；在均衡器页时常亮）
        p.selectTab(.equalizer); await sleep(1.4)
        await requestShot("k0-eq-entry-equalizer-tab")
        p.selectTab(.nowPlaying); await sleep(1.0)
        await requestShot("k0b-eq-entry-hidden-nowplaying")
        // 1) 每张卡片：打开 → 截图（带磨砂背景），并核对同时只有一张
        let shotName: [ParamCard: String] = [.loop: "k1-card-loop", .speedPitch: "k2-card-speedpitch", .subtitle: "k3-card-subtitle", .autoEq: "k4-card-autoeq"]
        for c in ParamCard.allCases {
            withAnimation(Motion.panel) { p.activeCard = c }
            await sleep(0.9)
            let flags = [p.loopEditorOpen, p.speedPitchOpen, p.subtitlePanelOpen, p.autoEqPanelOpen].filter { $0 }.count
            TestHooks.log("\(p.visibleCard == c && flags == 1 ? "✓" : "✗") 打开「\(c.title)」卡片：同时打开的卡片 \(flags) 张，背景磨砂压暗")
            await requestShot(shotName[c]!)
        }
        // 用原来的开关接口打开另一张，应该把前一张替换掉
        p.toggleSpeedPitchPanel(); await sleep(0.8)
        TestHooks.log("\(p.activeCard == .speedPitch && !p.autoEqPanelOpen ? "✓" : "✗") 在耳机校正卡片开着时按 ⌥⌘K：换成变速变调卡片（旧卡片收起）")
        // 2) 切换连拍 + 帧间隔（先量一段什么都不动时的基线；记下屏幕最高刷新率和窗口是否被别的窗口挡住）
        let scr = p.mainWindow?.screen?.maximumFramesPerSecond ?? 0
        // 量帧率时保证播放器窗口没被别的窗口挡住：测这一段时把自己的窗口临时浮到最上层，测完还原
        let level0 = p.mainWindow?.level ?? .normal
        p.mainWindow?.level = .floating; p.mainWindow?.orderFrontRegardless(); await sleep(0.6)
        defer { p.mainWindow?.level = level0 }
        let vis = p.mainWindow?.occlusionState.contains(.visible) ?? false
        let base = await measureFrames { await sleep(1.5) }
        TestHooks.log("  帧时钟基线（静止 1.5 秒）：\(String(format: "%.0f", base.fps)) fps，p95 \(String(format: "%.1f", base.p95)) ms，慢帧 \(base.slow)/\(base.n)；屏幕最高 \(scr) Hz；窗口\(vis ? "可见" : "被挡住（系统会降低被挡窗口的刷新）")")
        if UserDefaults.standard.bool(forKey: "cardProfile") {
            withAnimation(Motion.panel) { p.activeCard = .speedPitch }; await sleep(1.0)
            let o = await measureFrames { await sleep(1.5) }
            TestHooks.log("  卡片开着静止 1.5 秒：\(String(format: "%.0f", o.fps)) fps，慢帧 \(o.slow)/\(o.n)")
            try? "x".write(to: TestHooks.outDir.appendingPathComponent("sample.req"), atomically: true, encoding: .utf8)
            await sleep(5)
            p.closeCard(); await sleep(1.0)
            let c = await measureFrames { await sleep(1.5) }
            TestHooks.log("  卡片关上静止 1.5 秒：\(String(format: "%.0f", c.fps)) fps，慢帧 \(c.slow)/\(c.n)")
            try? "x".write(to: TestHooks.outDir.appendingPathComponent("sample2.req"), atomically: true, encoding: .utf8)
            await sleep(0.3)
            for k in 0..<14 { withAnimation(Motion.panel) { p.activeCard = ParamCard.allCases[k % 4] }; await sleep(0.35) }
            p.closeCard(); await sleep(1.5)
            try? "x".write(to: TestHooks.outDir.appendingPathComponent("sample3.req"), atomically: true, encoding: .utf8)
            await sleep(0.3)
            for _ in 0..<5 { withAnimation(Motion.panel) { p.activeCard = .speedPitch }; await sleep(0.55); p.closeCard(); await sleep(0.55) }
            await sleep(1.0)
        }
        func judge(_ m: (fps: Double, p95: Double, maxDt: Double, slow: Int, n: Int)) -> String {
            !vis ? "–" : (m.fps >= 0.85 * Double(max(scr, 1)) && m.slow <= max(2, m.n / 50) ? "✓" : "✗")
        }
        // 先连拍一遍（看过渡画面），再单独量一遍帧间隔——连拍时截图进程本身会占用窗口服务器，和帧率测量分开做
        startBurst("k5-card-switch-burst", seconds: 3.6)
        await sleep(0.2)
        for c in [ParamCard.loop, .subtitle, .autoEq, .speedPitch, .loop] { withAnimation(Motion.panel) { p.activeCard = c }; await sleep(0.6) }
        await waitBurst("k5-card-switch-burst")
        await sleep(1.2)
        let m = await measureFrames {
            for c in [ParamCard.subtitle, .autoEq, .speedPitch, .loop, .subtitle] { withAnimation(Motion.panel) { p.activeCard = c }; await sleep(0.6) }
        }
        TestHooks.log("\(judge(m)) 卡片来回切换 5 次（音频界面）：显示刷新 \(String(format: "%.0f", m.fps)) fps，帧间隔 p95 \(String(format: "%.1f", m.p95)) ms、最长 \(String(format: "%.1f", m.maxDt)) ms，超过 1.8 倍正常间隔的 \(m.slow)/\(m.n) 帧")
        // 3) Esc 收起
        logWindows("卡片 Esc 前")
        postKey(53); await sleep(0.8)
        logWindows("卡片 Esc 后")
        TestHooks.log("\(p.activeCard == nil ? "✓" : "✗") 按 Esc：卡片收起")
        // 4) 点卡片外面收起（点在磨砂层上：窗口上部）
        withAnimation(Motion.panel) { p.activeCard = .subtitle }; await sleep(0.9)
        let hit = p.mainWindow?.contentView?.hitTest(NSPoint(x: (p.mainWindow?.contentView?.bounds.midX ?? 0), y: (p.mainWindow?.contentView?.bounds.height ?? 0) - 160))
        postClick(fromTop: 160); await sleep(0.9)
        var tries = 1
        if p.activeCard != nil { tries += 1; postClick(fromTop: 260, x: 140); await sleep(0.9) }   // 第一下若落在别的控件上，换个空白处再点
        TestHooks.log("\(p.activeCard == nil ? "✓" : "✗") 点卡片外面：卡片收起（点了 \(tries) 下；点击处的视图 \(hit.map { String(describing: type(of: $0)) } ?? "无")）")
        // 磨砂层出现 / 消失的帧间隔
        let m2 = await measureFrames {
            for _ in 0..<3 { withAnimation(Motion.panel) { p.activeCard = .speedPitch }; await sleep(0.55); p.closeCard(); await sleep(0.55) }
        }
        TestHooks.log("\(judge(m2)) 磨砂背景出现 / 消失 3 次：\(String(format: "%.0f", m2.fps)) fps，p95 \(String(format: "%.1f", m2.p95)) ms，最长 \(String(format: "%.1f", m2.maxDt)) ms，慢帧 \(m2.slow)/\(m2.n)")
        // 5) 三个主题下的样子
        for (t, n) in [(AppTheme.white, "k6-card-theme-white"), (.black, "k7-card-theme-black"), (.liuli, "k8-card-theme-liuli")] {
            p.setTheme(t); await sleep(1.4)
            withAnimation(Motion.panel) { p.activeCard = .speedPitch }; await sleep(0.9)
            await requestShot(n)
            p.closeCard(); await sleep(0.5)
        }
        p.setTheme(theme0); await sleep(0.8)
        // 6) 视频上：开关、切换卡片，不许掉帧、不许黑帧
        if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
            p.play(index: vi, from: 2)
            for _ in 0..<40 where !(p.isPlaying && p.position > 2.3) { await sleep(0.1) }
            await sleep(1.0)
            let st = FrameStats()
            p.videoSurface.glLayer.frameProbe = { w, h, b, t in st.add(w, h, b, t) }
            _ = st.take()
            startBurst("k9-card-video-burst", seconds: 3.4)
            await sleep(0.2)
            for c in [ParamCard.speedPitch, .subtitle, .loop] { withAnimation(Motion.panel) { p.activeCard = c }; await sleep(0.6) }
            p.closeCard(); await sleep(0.6)
            withAnimation(Motion.panel) { p.activeCard = .speedPitch }; await sleep(0.6)
            await waitBurst("k9-card-video-burst")
            await sleep(1.2)
            let mv = await measureFrames {
                for c in [ParamCard.subtitle, .loop, .speedPitch] { withAnimation(Motion.panel) { p.activeCard = c }; await sleep(0.6) }
                p.closeCard(); await sleep(0.6)
                withAnimation(Motion.panel) { p.activeCard = .speedPitch }; await sleep(0.6)
            }
            let (f, bf, part, mb, _) = st.take()
            p.videoSurface.glLayer.frameProbe = nil
            let vfps = Double(p.engine.getDouble("container-fps") ?? p.engine.getDouble("estimated-vf-fps") ?? 0)
            let drops = p.engine.getDouble("frame-drop-count") ?? 0
            TestHooks.log("\(bf == 0 && f > 0 ? "✓" : "✗") 视频上开关 / 切换卡片：视频渲染 \(f) 帧（片源 \(String(format: "%.0f", vfps)) fps，连拍 + 测量共约 7 秒），整帧黑 \(bf) 帧，局部黑点帧 \(part)，单帧最多黑点 \(mb)/25；mpv 累计丢帧 \(Int(drops))")
            TestHooks.log("\(judge(mv)) 视频上卡片过渡的界面帧间隔：\(String(format: "%.0f", mv.fps)) fps，p95 \(String(format: "%.1f", mv.p95)) ms，最长 \(String(format: "%.1f", mv.maxDt)) ms，慢帧 \(mv.slow)/\(mv.n)")
            await requestShot("k10-card-on-video")
            p.closeCard(); await sleep(0.5)
        }
        p.clearABLoop()
        p.pause()
    }

    private func loopPanelTests() async {
        TestHooks.log("== 循环区收起 / 展开")
        await closeOverlays()
        guard let i = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) else { return }
        p.selectTab(.nowPlaying)
        p.play(index: i, from: 10); await sleep(1.5)
        TestHooks.log("\(!p.loopEditorOpen ? "✓" : "✗") 默认：循环区\(p.loopEditorOpen ? "展开" : "收起")，进度条上不显示区间、不能画区间")
        p.setLoopRange(12, 18); await sleep(1.0)       // 等同快捷键 / 菜单设置区间
        TestHooks.log("\(p.abA != nil && !p.loopEditorOpen ? "✓" : "✗") 用菜单设区间 12–18 秒：循环生效 \(p.abA != nil)，循环区仍收起 \(!p.loopEditorOpen)（播放栏上没有入口，只在进度条上淡淡标出区间）；mpv ab-loop-a=\(p.engine.getString("ab-loop-a") ?? "-")")
        await requestShot("l4-loop-collapsed")
        // 展开 / 收起过程连拍（看过渡动画）
        startBurst("r4-loop-toggle-burst", seconds: 2.4)
        await sleep(0.3)
        p.toggleLoopEditor(); await sleep(1.0)
        p.toggleLoopEditor(); await sleep(1.0)
        await waitBurst("r4-loop-toggle-burst")
        // 从播放栏右键菜单 ▸ 区间循环 ▸ 展开循环区（走真实的菜单项动作）
        fireMenu(MenuCatalog.playBar(p), path: ["区间循环（A-B）"], prefix: "展开循环区"); await sleep(1.0)
        TestHooks.log("\(p.loopEditorOpen ? "✓" : "✗") 右键菜单「展开循环区」：循环区展开，进度条显示区间和两端手柄，可直接拖选（不必按 ⌥）")
        await requestShot("l5-loop-expanded")
        fireMenu(MenuCatalog.playBar(p), path: ["区间循环（A-B）"], prefix: "收起循环区"); await sleep(1.0)
        TestHooks.log("\(!p.loopEditorOpen && p.abA != nil ? "✓" : "✗") 右键菜单「收起循环区」：循环区收起，循环继续生效 \(p.abA != nil)，进度条上只剩淡色区间")
        await requestShot("l6-loop-collapsed-again")
        p.clearABLoop(); await sleep(0.4)
        // 视频上反复展开收起：不许出黑帧
        if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
            p.play(index: vi, from: 2)
            for _ in 0..<40 where !(p.isPlaying && p.position > 2.3) { await sleep(0.1) }
            await sleep(1.0)
            TestHooks.log("  视频状态：播放 \(p.isPlaying)，位置 \(String(format: "%.2f", p.position))，当前 \(p.current?.title ?? "-")")
            let st = FrameStats()
            p.videoSurface.glLayer.frameProbe = { w, h, b, t in st.add(w, h, b, t) }
            _ = st.take()
            p.setLoopRange(3, 9)
            for _ in 0..<3 { p.toggleLoopEditor(); await sleep(0.7); p.toggleLoopEditor(); await sleep(0.7) }
            let (f, bf, part, mb, _) = st.take()
            p.videoSurface.glLayer.frameProbe = nil
            TestHooks.log("\(bf == 0 && f > 0 ? "✓" : "✗") 视频上展开/收起循环区 3 次：渲染 \(f) 帧，整帧黑 \(bf) 帧，局部黑点帧 \(part)，单帧最多黑点 \(mb)/25")
            p.clearABLoop()
        }
        p.pause()
    }

    // MARK: 循环按钮 + 长按快进 / 快退
    private func postArrow(_ code: UInt16, down: Bool, isRepeat: Bool) {
        guard let w = p.mainWindow else { return }
        let ch = code == 123 ? "\u{F702}" : "\u{F703}"
        if let e = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: isRepeat, keyCode: code) {
            NSApp.postEvent(e, atStart: false)
        }
    }

    private func scanTests() async {
        TestHooks.log("== 循环播放按钮（播放栏最左）")
        await closeOverlays()
        guard let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio && ($0.duration ?? 0) > 90 }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) else { return }
        p.selectTab(.nowPlaying)
        p.play(index: ai, from: 5); await sleep(1.5)
        let origMode = p.queue.repeatMode
        var seen: [String] = []
        for _ in 0..<3 {
            if p.queue.repeatMode == .off { break }
            p.cycleRepeat(); await sleep(0.2)
        }
        for (k, name) in ["f3-repeat-off", "f3-repeat-all", "f3-repeat-one"].enumerated() {
            if k > 0 { p.cycleRepeat() }
            await sleep(0.8)
            seen.append(p.queue.repeatMode.label)
            await requestShot(name)
        }
        startBurst("r5-repeat-switch-burst", seconds: 1.6)
        await sleep(0.2); p.cycleRepeat(); await sleep(0.6); p.cycleRepeat(); await sleep(0.6)
        await waitBurst("r5-repeat-switch-burst")
        while p.queue.repeatMode != origMode { p.cycleRepeat() }
        TestHooks.log("\(seen == ["不循环", "列表循环", "单曲循环"] ? "✓" : "✗") 循环按钮三种状态依次切换：\(seen.joined(separator: " → "))（截图 f3-repeat-*，连拍 r5-repeat-switch-burst）；已恢复为 \(origMode.label)")

        TestHooks.log("== 长按快进 / 快退（音频）")
        p.play(index: ai, from: 5); await sleep(1.5)
        let vol0 = p.engine.getDouble("volume") ?? -1
        // 轻点：仍然是切歌
        p.scanButtonTapped(1); await sleep(1.0)
        TestHooks.log("\(p.queue.currentIndex != ai ? "✓" : "✗") 轻点「下一首」：切到下一首（\(p.current?.title ?? "-")）")
        p.play(index: ai, from: 5); await sleep(1.5)
        let pos0 = p.position
        let playing0 = p.isPlaying
        p.beginScan(1)
        await sleep(0.35)
        TestHooks.log("  （快进前 播放中 \(playing0) / mpv pause=\(p.engine.getFlag("pause").map(String.init) ?? "-")；快进中 播放中 \(p.isPlaying)）")
        let volDuring = p.engine.getDouble("volume") ?? -1
        var rates = Set<Int>()
        for k in 0..<30 { rates.insert(Int(p.scanRate)); if k == 18 { await requestShot("f1-scan-forward-badge") }; await sleep(0.1) }
        let posMid = p.position
        p.endScan()                           // 松手（按钮 isPressed 变 false）
        await sleep(0.05)
        p.scanButtonTapped(1)                 // 紧跟着触发的按钮动作：不切歌
        await sleep(0.6)
        let idxAfter = p.queue.currentIndex
        let volAfter = p.engine.getDouble("volume") ?? -1
        let posAfter = p.position
        TestHooks.log("\(posMid - pos0 > 8 && idxAfter == ai && p.queue.currentIndex == ai ? "✓" : "✗") 长按快进约 3.5 秒：\(String(format: "%.1f", pos0)) → \(String(format: "%.1f", posMid)) 秒；倍速依次出现 ×\(rates.filter { $0 > 0 }.sorted().map(String.init).joined(separator: " ×"))；松手不切歌")
        TestHooks.log("\(volDuring < 1 && abs(volAfter - vol0) < 0.5 && p.isPlaying && abs((p.engine.getDouble("speed") ?? 0) - 1) < 0.001 ? "✓" : "✗") 快进中声音先淡出（mpv volume=\(String(format: "%.1f", volDuring))），松手后淡入回原音量 \(String(format: "%.1f", volAfter))/\(String(format: "%.1f", vol0))，继续正常播放（速度 \(p.engine.getDouble("speed") ?? 0)，位置 \(String(format: "%.1f", posAfter))）")
        let pos1 = p.position
        p.beginScan(-1); await sleep(2.0)
        let posR = p.position
        await requestShot("f2-scan-rewind-badge")
        p.endScan(); await sleep(0.6)
        TestHooks.log("\(pos1 - posR > 3 && p.isPlaying ? "✓" : "✗") 长按快退 2 秒：\(String(format: "%.1f", pos1)) → \(String(format: "%.1f", posR)) 秒，松手继续播放")
        // 键盘：按一下 → 跳 15 秒；按住（系统重复事件）连续快进，松开恢复
        await sleep(0.3)
        p.mainWindow?.makeKeyAndOrderFront(nil)
        if p.position < 12 || p.position > (p.duration ?? 60) - 25 { p.seek(to: 20); await sleep(0.6) }
        let k0 = p.position
        postArrow(124, down: true, isRepeat: false); await sleep(0.05); postArrow(124, down: false, isRepeat: false); await sleep(0.6)
        let k1 = p.position
        TestHooks.log("\(k1 - k0 > 14 && k1 - k0 < 17 && p.scanDirection == 0 ? "✓" : "✗") 按一下 →：\(String(format: "%.1f", k0)) → \(String(format: "%.1f", k1)) 秒（跳 15 秒，不进入连续快进）")
        postArrow(123, down: true, isRepeat: false); await sleep(0.3)
        for _ in 0..<25 { postArrow(123, down: true, isRepeat: true); await sleep(0.08) }
        let kDir = p.scanDirection, kMid = p.position
        postArrow(123, down: false, isRepeat: false); await sleep(0.6)
        TestHooks.log("  （按住期间 scanDirection=\(kDir)，松开后 \(p.scanDirection)，播放中 \(p.isPlaying)）")
        TestHooks.log("\(kDir == -1 && k1 - kMid > 6 && p.scanDirection == 0 && p.isPlaying ? "✓" : "✗") 按住 ← 约 2.3 秒：连续快退 \(String(format: "%.1f", k1)) → \(String(format: "%.1f", kMid)) 秒；松开恢复正常播放")
        let wb = p.mainWindow?.contentView?.bounds ?? .zero
        await shootMenu("f5-context-playbar-scan", MenuCatalog.playBar(p), at: CGPoint(x: wb.midX, y: wb.maxY - 330))
        await shootMenu("f6-menu-playback-scan", MenuCatalog.playback(p), at: CGPoint(x: wb.midX - 120, y: 40))
        p.pause()

        // 爆音检查：取这首歌的原始解码采样，按播放器实际做的事情逐个采样地重放——
        // 每 10ms 一步改增益（mpv 的音量就是这样一步步生效的）、静音时跳转、精确跳回、再淡入，
        // 和“正常播放”“不淡入淡出直接跳”的对照组比较二阶差分（爆音会让它突然变大）
        TestHooks.log("== 快进 / 快退爆音检查（按采样重放）")
        let path = p.queue.items[ai].url.path
        let st0 = 10.0
        if let src = await Task.detached(operation: { MPVEngine.extractPCM(input: path, start: st0, duration: 16) }).value {
            let ch = src.channels, sr = Double(src.rate), frames = src.samples.count / max(1, ch)
            func plan(fade: Bool) -> [(Double, Int, Double)] {
                var a: [(Double, Int, Double)] = []
                var t = 0.8
                if fade { for v in ScanMath.fadeVolumes(from: 100, to: 0, steps: ScanMath.fadeOutSteps) { a.append((t, 0, v)); t += ScanMath.fadeStep } } else { t += 0.12 }
                t += 0.01
                var pos = st0 + t
                for _ in 0..<15 { pos += 4 * 0.1; a.append((t, 1, pos)); t += 0.1 }
                a.append((t, 2, pos)); t += 0.09
                if fade { for v in ScanMath.fadeVolumes(from: 0, to: 100, steps: ScanMath.fadeInSteps) { a.append((t, 0, v)); t += ScanMath.fadeStep } }
                return a
            }
            func render(_ acts: [(Double, Int, Double)], seconds: Double) -> [Float] {
                var out = [Float](repeating: 0, count: Int(seconds * sr) * ch)
                var pending = acts[...], g: Float = 1, sp = 0
                for k in 0..<Int(seconds * sr) {
                    let tau = Double(k) / sr
                    while let a = pending.first, tau >= a.0 {
                        pending = pending.dropFirst()
                        if a.1 == 0 { g = Float(pow(a.2 / 100, 3)) } else { sp = Int((a.2 - st0) * sr) }
                    }
                    if sp >= 0 && sp < frames { for c in 0..<ch { out[k * ch + c] = src.samples[sp * ch + c] * g } }
                    sp += 1
                }
                return out
            }
            func d2max(_ x: [Float]) -> (Float, Float) {
                let fr = x.count / ch
                var mx: Float = 0, d2s = [Float](repeating: 0, count: fr)
                for k in 2..<fr {
                    var m: Float = 0
                    for c in 0..<ch { m = max(m, abs(x[k * ch + c] - 2 * x[(k - 1) * ch + c] + x[(k - 2) * ch + c])) }
                    d2s[k] = m; mx = max(mx, m)
                }
                return (mx, d2s.sorted()[Int(Double(fr) * 0.999)])
            }
            let n = d2max(render([], seconds: 4)), fd = d2max(render(plan(fade: true), seconds: 4)), ct = d2max(render(plan(fade: false), seconds: 4))
            // 判定：没有比“直接跳”小一个数量级就算爆音；同时 99.9% 分位不能比正常播放明显变大
            let ok = fd.0 <= ct.0 / 10 && fd.1 <= n.1 * 1.5 + 1e-4
            let db = { (x: Float) in String(format: "%.0f dBFS", 20 * log10(max(1e-9, Double(x)))) }
            TestHooks.log("\(ok ? "✓" : "✗") 快进快退过程不爆音（素材 \(p.queue.items[ai].title)，\(ch) 声道 \(Int(sr))Hz）：二阶差分最大值 —— 正常播放 \(String(format: "%.4f", n.0))，本播放器的淡出→静音跳转→精确跳回→淡入 \(String(format: "%.4f", fd.0))，对照（不淡入淡出直接跳）\(String(format: "%.4f", ct.0))；99.9% 分位 \(String(format: "%.4f", n.1)) / \(String(format: "%.4f", fd.1)) / \(String(format: "%.4f", ct.1))；最大瞬时跳变 \(db(fd.0)) vs 直接跳 \(db(ct.0))")
        } else { TestHooks.log("✗ 取原始采样失败") }

        TestHooks.log("== 长按快进 / 快退（视频）：不许黑帧")
        if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
            p.play(index: vi, from: 2); await sleep(2.0)
            let st = FrameStats()
            p.videoSurface.glLayer.frameProbe = { w, h, b, t in st.add(w, h, b, t) }
            _ = st.take()
            let v0 = p.position
            p.beginScan(1); await sleep(1.6)
            await requestShot("f4-scan-video")
            await sleep(0.6)
            let v1 = p.position
            p.endScan(); await sleep(0.8)
            p.beginScan(-1); await sleep(1.5)
            let v2 = p.position
            p.endScan(); await sleep(0.8)
            let (f, bf, part, mb, _) = st.take()
            p.videoSurface.glLayer.frameProbe = nil
            TestHooks.log("\(v1 - v0 > 3 && v1 - v2 > 1.5 ? "✓" : "✗") 视频快进 \(String(format: "%.1f", v0)) → \(String(format: "%.1f", v1)) 秒，快退到 \(String(format: "%.1f", v2)) 秒，松手继续播放 \(p.isPlaying)")
            TestHooks.log("\(bf == 0 && f > 0 ? "✓" : "✗") 视频快进快退中：渲染 \(f) 帧，整帧黑 \(bf) 帧，局部黑点帧 \(part)，单帧最多黑点 \(mb)/25")
            p.pause()
        }
    }

    // MARK: 联网补官方专辑封面
    private func coverTests() async {
        TestHooks.log("== 联网补官方专辑封面（文件自带 → MusicBrainz / Cover Art Archive →（本人打开时）iTunes → 默认封面）")
        await closeOverlays()
        TestHooks.log("\(coversDefaultAtStart ? "✓" : "✗") 默认开启：启动时 联网封面=\(coversDefaultAtStart ? "开" : "关")")
        guard let m = TestHooks.mediaDir else { return }
        let extra = m.deletingLastPathComponent().appendingPathComponent("testmedia-extra")
        let cdir = extra.appendingPathComponent("covers")
        let jay = extra.appendingPathComponent("lyrics/周杰伦 - 晴天（自测音轨）.m4a")
        guard FileManager.default.fileExists(atPath: jay.path), FileManager.default.fileExists(atPath: cdir.path) else { TestHooks.log("○ 缺少封面自测音轨，跳过"); return }
        func sha(_ u: URL) -> String {
            guard let d = try? Data(contentsOf: u) else { return "-" }
            var h: UInt64 = 0xcbf29ce484222325
            for b in d { h ^= UInt64(b); h = h &* 0x100000001b3 }
            return String(format: "%016llx", h)
        }
        // (文件, 期望：专辑名（折叠后比较）/ "default" / "file")
        let cases: [(URL, String)] = [
            (jay, "叶惠美"),
            (cdir.appendingPathComponent("周杰伦 - 以父之名（自测音轨）.m4a"), "叶惠美"),
            (cdir.appendingPathComponent("Coldplay - Yellow (test tone).m4a"), "Parachutes"),
            (cdir.appendingPathComponent("Queen - Bohemian Rhapsody (test tone).m4a"), "A Night at the Opera"),
            (cdir.appendingPathComponent("Adele - Rolling in the Deep (test tone).m4a"), "21"),
            (cdir.appendingPathComponent("Michael Jackson - Billie Jean (test tone).m4a"), "Thriller"),
            (cdir.appendingPathComponent("无信息测试音轨.m4a"), "default"),
            (cdir.appendingPathComponent("晴天（时长不对的诱饵）.m4a"), "default"),
            (cdir.appendingPathComponent("内嵌封面测试 - Coldplay Yellow.m4a"), "file"),
        ]
        let before = cases.map { sha($0.0) }
        p.selectTab(.nowPlaying)
        var added: [URL] = []
        for (k, (f, expect)) in cases.enumerated() {
            guard FileManager.default.fileExists(atPath: f.path) else { TestHooks.log("○ 缺少 \(f.lastPathComponent)"); continue }
            p.open([f], playNow: true); added.append(f)
            var id: MediaItem.ID?
            // 网上查封面偶发超过 30 秒（本轮 Adele 实测 39304ms 才回来）。等到有结果或 60 秒，不放宽“必须查到对的专辑”。
            for _ in 0..<600 {
                await sleep(0.1)
                id = p.queue.items.first(where: { $0.url == f })?.id
                if let id, p.details(for: p.queue.items.first(where: { $0.id == id })!) != nil {
                    if expect == "file" { break }
                    if p.coverOutcome[id] != nil { break }
                }
            }
            guard let id, let it = p.queue.items.first(where: { $0.id == id }) else { TestHooks.log("✗ 没打开 \(f.lastPathComponent)"); continue }
            await sleep(1.0)                                     // 等淡入过渡做完
            let art = p.art(for: it)
            let info = p.coverInfo[id]
            let outcome = p.coverOutcome[id] ?? "-"
            let desc = "「\(it.title)」\(it.artist ?? "（无歌手）") / \(it.album ?? "（无专辑）") / \(Int(it.duration ?? 0)) 秒"
            switch expect {
            case "default":
                TestHooks.log("\(art?.origin == "generated" && info == nil ? "✓" : "✗") \(desc) → 默认封面（查询结果 \(outcome)）")
            case "file":
                TestHooks.log("\(art?.origin == "file" && info == nil && p.hasFileCover(id) && p.coverOutcome[id] == nil ? "✓" : "✗") \(desc) → 用文件自带的封面，不联网（来源 \(art?.origin ?? "-")）")
            default:
                let ok = art?.origin == "online" && CoverLookup.albumMatches(CoverLookup.stripEdition(info?.album ?? ""), expect)
                TestHooks.log("\(ok ? "✓" : "✗") \(desc) → \(info?.source ?? "没查到")「\(info?.album ?? "-")」（期望「\(expect)」）\(info?.link ?? "")")
            }
            if k == 0 { await requestShot("w1-cover-jay-official") }
            if expect == "default" && k == 6 { await requestShot("w2-cover-default-fallback") }
        }
        // 右键菜单：重新查找 / 改用默认 / 开关
        if let ji = p.queue.items.firstIndex(where: { $0.url == jay }) {
            p.play(index: ji, from: 20); await sleep(1.5)
            let w = p.mainWindow?.contentView?.bounds ?? .zero
            await shootMenu("w3-context-cover-menu", MenuCatalog.card(p, index: ji), at: CGPoint(x: w.midX + 60, y: 130))
            let id = p.queue.items[ji].id
            fireMenu(MenuCatalog.card(p, index: ji), path: ["封面"], prefix: "改用默认封面")
            var o1 = p.art(for: p.queue.items[ji])?.origin
            for _ in 0..<100 {
                if p.coverInfo[id] == nil && p.art(for: p.queue.items[ji])?.origin == "generated" { break }
                await sleep(0.1)
                o1 = p.art(for: p.queue.items[ji])?.origin
            }
            TestHooks.log("\(o1 == "generated" && p.coverInfo[id] == nil ? "✓" : "✗") 右键「改用默认封面」：换回默认封面（\(o1 ?? "-")），并记住这张专辑")
            await requestShot("w5-cover-use-default")
            TestHooks.log("\((MenuCatalog.card(p, index: ji).flatten(prefix: "").contains { $0.1.title == "联网查找封面" }) ? "✓" : "✗") 改用默认后，封面右键显示「联网查找封面」")
            fireMenu(MenuCatalog.card(p, index: ji), path: ["封面"], prefix: "联网查找封面")
            for _ in 0..<200 where p.coverInfo[id] == nil { await sleep(0.1) }
            await sleep(1.0)
            let o2 = p.art(for: p.queue.items[ji])?.origin
            TestHooks.log("\(o2 == "online" && MenuCatalog.card(p, index: ji).flatten(prefix: "").contains { $0.1.title == "重新查找封面" } ? "✓" : "✗") 右键「联网查找封面」：查到「\(p.coverInfo[id]?.album ?? "-")」（\(o2 ?? "-")）")
            fireMenu(MenuCatalog.card(p, index: ji), path: ["封面"], prefix: "自动补封面")
            var o3 = p.art(for: p.queue.items[ji])?.origin
            for _ in 0..<100 {
                if !p.onlineCoversEnabled && p.art(for: p.queue.items[ji])?.origin == "generated" { break }
                await sleep(0.1)
                o3 = p.art(for: p.queue.items[ji])?.origin
            }
            TestHooks.log("\(!p.onlineCoversEnabled && o3 == "generated" ? "✓" : "✗") 关掉右键「自动补封面」：已查到的封面换回默认（\(o3 ?? "-")）；开关已保存（自测沙盒）=\(Prefs.object("onlineCovers") as? Bool ?? true)；本人偏好里仍是 \(Self.realPref("onlineCovers"))（开始时 \(realCoversPref)）")
            startBurst("w4-cover-fade-burst", seconds: 2.0)       // 连拍：默认封面 → 官方封面的淡入过渡
            await sleep(0.3)
            p.setOnlineCoversEnabled(true, quiet: true)
            for _ in 0..<100 where p.coverInfo[id] == nil { await sleep(0.1) }
            await waitBurst("w4-cover-fade-burst")
            await sleep(0.5)
            TestHooks.log("\(p.art(for: p.queue.items[ji])?.origin == "online" ? "✓" : "✗") 重新打开：从缓存换回官方封面")
            p.pause()
        }
        // iTunes 补充来源（默认关）：单独验证这条路也只认对得上的那张
        TestHooks.log("\(!iTunesDefaultAtStart ? "✓" : "✗") 「也用 iTunes 补」默认关（苹果条款限制）：启动时 \(iTunesDefaultAtStart ? "开" : "关")")
        do {
            let r1 = try await CoverService.iTunes(CoverQuery(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 270))
            let r2 = try await CoverService.iTunes(CoverQuery(title: "晴天", artist: "周杰伦", album: nil, duration: 60))
            TestHooks.log("\(r1.map { CoverLookup.albumMatches($0.1.album, "叶惠美") } == true && r2 == nil ? "✓" : "✗") iTunes 这条路单独测：《晴天》对上「\(r1?.1.album ?? "-")」\(r1?.1.link ?? "")；时长不对的诱饵 → \(r2 == nil ? "不认" : "误配「\(r2!.1.album)」")")
        } catch { TestHooks.log("✗ iTunes 查询失败：\(error.localizedDescription)") }
        // 歌词同样的顺序：同名 .lrc 优先，不联网
        let y = cdir.appendingPathComponent("Coldplay - Yellow (test tone).m4a")
        if let yi = p.queue.items.firstIndex(where: { $0.url == y }) {
            p.setLyricsEnabled(true, quiet: true)
            p.play(index: yi, from: 0); await sleep(2.5)
            TestHooks.log("\(p.lyrics?.lines.first?.text.contains("自测用本地歌词") == true ? "✓" : "✗") 歌词顺序：有同名 .lrc 时直接用本地歌词（\(p.lyrics?.lines.count ?? 0) 行，第一行「\(p.lyrics?.lines.first?.text ?? "-")」），不联网查 LRCLIB")
            p.setLyricsEnabled(false, quiet: true)
            p.pause()
        }
        let after = cases.map { sha($0.0) }
        TestHooks.log("\(before == after ? "✓" : "✗") 只显示、不写回：\(cases.count) 个音乐文件内容前后一致")
        let cache = CoverService.cacheDir
        let files = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
        TestHooks.log("✓ 封面缓存：\(files.filter { $0.hasSuffix(".jpg") }.count) 张封面、\(files.filter { $0.hasSuffix(".none") }.count) 条“没找到”（自测放在 \(cache.path)；正常使用时在 ~/Library/Application Support/com.tanco.glassplayer/covers）")
        for f in added { if let i = p.queue.items.firstIndex(where: { $0.url == f }) { p.remove(at: i) } }
        await sleep(0.6)
    }

    // MARK: 自动搜索歌词（LRCLIB）
    private func lyricsTests() async {
        TestHooks.log("== 自动搜索歌词（LRCLIB）")
        await closeOverlays()
        TestHooks.log("\(!lyricsDefaultAtStart ? "✓" : "✗") 默认关闭：启动时 歌词=\(lyricsDefaultAtStart ? "开" : "关")")
        guard let m = TestHooks.mediaDir else { return }
        let dir = m.deletingLastPathComponent().appendingPathComponent("testmedia-extra/lyrics")
        let f = dir.appendingPathComponent("周杰伦 - 晴天（自测音轨）.m4a")
        guard FileManager.default.fileExists(atPath: f.path) else { TestHooks.log("○ 缺少歌词自测音轨，跳过"); return }
        p.selectTab(.nowPlaying)
        p.open([f], playNow: true); await sleep(3.0)
        TestHooks.log("\(!p.showsLyricsStrip && p.lyrics == nil ? "✓" : "✗") 开关关着：不联网查，界面上没有歌词条（当前 \(p.current?.title ?? "-") / \(p.current?.displayArtist ?? "-") / \(Int(p.duration ?? 0)) 秒）")
        let t0 = Date()
        p.setLyricsEnabled(true)                       // 等同点播放条上的歌词按钮 / 右键菜单
        for _ in 0..<150 where !p.showsLyricsStrip { await sleep(0.1) }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        TestHooks.log("\(p.showsLyricsStrip ? "✓" : "✗") 打开后自动查到带时间轴的歌词：\(p.lyrics?.lines.count ?? 0) 行，来源 \(p.lyricsSource ?? "-")，\(ms)ms 后显示歌词条")
        TestHooks.log("\(Prefs.bool("lyricsAutoSearch") ? "✓" : "✗") 开关状态已保存（自测沙盒里）：lyricsAutoSearch=\(Prefs.bool("lyricsAutoSearch"))；本人偏好文件里仍是 \(Self.realPref("lyricsAutoSearch"))（自测开始时 \(realLyricsPref)）")
        let cache = LyricsService.cacheDir
        let n = (try? FileManager.default.contentsOfDirectory(atPath: cache.path))?.filter { $0.hasSuffix(".lrc") }.count ?? 0
        TestHooks.log("\(n > 0 ? "✓" : "✗") 歌词缓存：\(n) 个 .lrc（自测放在 \(cache.path)；正常使用时在 ~/Library/Application Support/com.tanco.glassplayer/lyrics）")
        if let l = p.lyrics, let first = l.lines.first(where: { $0.time > 25 && !$0.text.isEmpty }) {
            p.seek(to: max(0, first.time - 0.5)); p.play(); await sleep(2.0)
            let i1 = l.index(at: p.position + 0.15)
            await requestShot("y1-lyrics-scroll")
            await sleep(4.0)
            let i2 = l.index(at: p.position + 0.15)
            await requestShot("y2-lyrics-scroll-later")
            let t1 = i1.map { l.lines[$0].text } ?? "-", t2 = i2.map { l.lines[$0].text } ?? "-"
            TestHooks.log("\((i2 ?? 0) > (i1 ?? 0) ? "✓" : "✗") 歌词跟着播放滚动、高亮当前行：第 \((i1 ?? -1) + 1) 行「\(t1)」→ 第 \((i2 ?? -1) + 1) 行「\(t2)」")
            let w = p.mainWindow?.contentView?.bounds ?? .zero
            await shootMenu("y3-context-lyrics", MenuCatalog.card(p, index: p.queue.currentIndex ?? 0), at: CGPoint(x: w.midX + 60, y: 130))
            p.pause()
        }
        // 查不到：安静地不显示
        let g = m.deletingLastPathComponent().appendingPathComponent("testmedia-extra/结构测试 - 副歌在哪.flac")
        if FileManager.default.fileExists(atPath: g.path) {
            p.open([g], playNow: true); await sleep(5.0)
            TestHooks.log("\(!p.showsLyricsStrip ? "✓" : "✗") 查不到的曲子（\(p.current?.title ?? "-")）：不显示歌词条、不弹提示")
            await requestShot("y4-lyrics-not-found")
            p.pause()
            if let i = p.queue.items.firstIndex(where: { $0.url == g }) { p.remove(at: i) }
        }
        p.setLyricsEnabled(false, quiet: true)
        await sleep(0.6)
        TestHooks.log("\(!p.showsLyricsStrip ? "✓" : "✗") 关掉开关：歌词条收起")
        if let i = p.queue.items.firstIndex(where: { $0.url == f }) { p.remove(at: i) }
        await sleep(0.6)
    }

    // MARK: 本地语音识别字幕（whisper.cpp）
    private func asrTests() async {
        TestHooks.log("== 本地语音识别字幕")
        await closeOverlays()
        guard WhisperJob.isAvailable else { TestHooks.log("✗ 没找到 runtime/whisper/bin/whisper-cli 或模型"); return }
        TestHooks.log("  模型：\(Runtime.whisperModel?.lastPathComponent ?? "-")")
        guard let m = TestHooks.mediaDir else { return }
        let dir = m.deletingLastPathComponent().appendingPathComponent("testmedia-extra/asr")
        let cases: [(String, WhisperJob.Language, String, Double)] = [
            ("中国空间站访谈（中文实拍）.mp4", .zh, "zh2", 44), ("丹东游船导游（中文实拍）.mp4", .zh, "zh", 12), ("Tears of Steel（英文片段）.mp4", .en, "en", 31)]
        for (k, (name, lang, tag, showAt)) in cases.enumerated() {
            let f = dir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: f.path) else { TestHooks.log("○ 缺少 \(name)，跳过"); continue }
            p.selectTab(.nowPlaying)
            p.open([f], playNow: true); await sleep(2.5); p.pause()
            let dur = p.duration ?? 0
            let t0 = Date()
            p.generateSubtitles(language: lang)
            var shotTaken = false
            var maxProg = 0.0
            for _ in 0..<12000 {
                if p.asrJob == nil { break }
                maxProg = max(maxProg, p.asrProgress ?? 0)
                if k == 0, !shotTaken, (p.asrProgress ?? 0) > 0.15 { shotTaken = true; await requestShot("a1-asr-progress") }
                await sleep(0.1)
            }
            let secs = Date().timeIntervalSince(t0)
            let out = Runtime.root.appendingPathComponent("subtitles/\(Runtime.key(for: f)).whisper.srt")
            let ok = FileManager.default.fileExists(atPath: out.path)
            if ok { try? FileManager.default.removeItem(at: TestHooks.outDir.appendingPathComponent("asr-\(tag).srt")); try? FileManager.default.copyItem(at: out, to: TestHooks.outDir.appendingPathComponent("asr-\(tag).srt")) }
            let n = ((try? String(contentsOf: out, encoding: .utf8)) ?? "").components(separatedBy: "-->").count - 1
            TestHooks.log("\(ok ? "✓" : "✗") 识别「\(name)」（\(lang.title)，片长 \(String(format: "%.0f", dur)) 秒）：用时 \(String(format: "%.1f", secs)) 秒（\(String(format: "%.1f", dur / max(secs, 0.1)))× 实时），\(n) 条字幕，进度最高 \(Int(maxProg * 100))%；已挂到播放器：\(p.engine.getString("sid") ?? "-")")
            p.seek(to: showAt); p.play(); await sleep(1.6); p.pause(); await sleep(0.4)
            await requestShot(["zh2": "a2-asr-zh-interview", "zh": "a4-asr-zh-noisy", "en": "a3-asr-en"][tag]!)
            if tag == "en" {
                await subtitleSearchTests()
            }
            if let i = p.queue.items.firstIndex(where: { $0.url == f }) { p.remove(at: i) }
            await sleep(0.8)
        }
        // 取消：再开一次识别，0.8 秒后取消，进程要退出、不留半截字幕
        if let f = cases.map({ dir.appendingPathComponent($0.0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            p.open([f], playNow: true); await sleep(2.0); p.pause()
            p.generateSubtitles(language: .zh); await sleep(0.8)
            p.cancelASR()
            for _ in 0..<100 where p.asrJob != nil { await sleep(0.1) }
            TestHooks.log("\(p.asrJob == nil ? "✓" : "✗") 取消识别：任务已结束 \(p.asrJob == nil)，进度条已收起 \(p.asrProgress == nil)")
            if let i = p.queue.items.firstIndex(where: { $0.url == f }) { p.remove(at: i) }
            await sleep(0.8)
        }
    }

    // MARK: 在线字幕（OpenSubtitles 公开接口；网站搜索只记录不打开浏览器）
    private func subtitleSearchTests() async {
        TestHooks.log("== 在线字幕搜索")
        await closeOverlays()
        if !p.subtitlePanelOpen { p.toggleSubtitlePanel() }
        await sleep(0.3)
        for _ in 0..<300 where p.subtitleSearching { await sleep(0.1) }
        p.subtitleQuery = "Tears of Steel"
        let t0 = Date()
        p.searchSubtitles()
        await sleep(0.2)
        for _ in 0..<300 where p.subtitleSearching { await sleep(0.1) }
        let ms = Date().timeIntervalSince(t0) * 1000
        let langs = Set(p.subtitleResults.map(\.languageID)).sorted().joined(separator: ",")
        TestHooks.log("\(p.subtitleResults.isEmpty ? "✗" : "✓") 搜「Tears of Steel」：\(p.subtitleResults.count) 条（语言 \(langs)），用时 \(Int(ms))ms；\(p.subtitleMessage)")
        await sleep(0.6)
        await requestShot("o1-subtitle-search")
        if let r = p.subtitleResults.first(where: { $0.languageID == "chi" }) ?? p.subtitleResults.first {
            p.downloadSubtitle(r)
            for _ in 0..<300 where !p.subtitleMessage.hasPrefix("已加载") && !p.subtitleMessage.hasPrefix("下载失败") { await sleep(0.1) }
            let f = Runtime.root.appendingPathComponent("subtitles/\(Runtime.key(for: p.current!.url)).\(r.languageID.isEmpty ? "sub" : r.languageID).\(r.format)")
            let size = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? NSNumber)?.intValue ?? 0
            TestHooks.log("\(p.subtitleMessage.hasPrefix("已加载") ? "✓" : "✗") 下载「\(r.fileName)」（\(r.language)）：\(p.subtitleMessage)；文件 \(size) 字节；mpv 当前字幕轨 \(p.engine.getString("sid") ?? "-")")
        }
        // 字幕网站：自测里只记录要打开的地址
        p.lastOpenedURL = nil
        if let (n, u) = SubtitleSearch.webSearches(p.subtitleQuery).first {
            p.openSubtitleSite(u)
            TestHooks.log("\(p.lastOpenedURL == u ? "✓" : "✗") 字幕网站「\(n)」：自测已拦截，没有打开浏览器（\(u.host ?? "")）")
        }
        if p.subtitlePanelOpen { p.toggleSubtitlePanel() }
        await sleep(0.5)
    }

    // MARK: AutoEq 耳机校正（联网）
    private func autoEqTests() async {
        TestHooks.log("== 耳机校正 AutoEq")
        guard let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) else { return }
        await closeOverlays()
        p.play(index: ai, from: 2); await sleep(1.0)
        let t0 = Date()
        if !p.autoEqPanelOpen { p.toggleAutoEqPanel() }
        await sleep(0.3)
        for _ in 0..<300 where p.autoEqLoading { await sleep(0.1) }
        TestHooks.log("\(p.autoEqIndex.count > 1000 ? "✓" : "✗") 耳机列表：\(p.autoEqIndex.count) 条，用时 \(Int(Date().timeIntervalSince(t0) * 1000))ms；\(p.autoEqMessage)")
        p.autoEqQuery = "WH-1000XM5"
        let hits = AutoEq.search(p.autoEqIndex, p.autoEqQuery)
        guard let e = hits.first(where: { $0.source.contains("oratory1990") }) ?? hits.first else { TestHooks.log("✗ 搜不到 WH-1000XM5"); return }
        TestHooks.log("  搜「WH-1000XM5」：\(hits.count) 条，选 \(e.name)（\(e.displaySource)）")
        p.selectAutoEq(e)
        for _ in 0..<300 where p.autoEqEntry != e { await sleep(0.1) }
        await sleep(0.4)
        let af = p.engine.getString("af") ?? ""
        TestHooks.log("\(af.contains(AutoEq.label) ? "✓" : "✗") 已应用：\(p.autoEqMessage)；af 长度 \(af.count)")
        await sleep(0.5)
        await requestShot("o2-autoeq")
        // 强度 50%：曲线减半
        p.setAutoEqStrength(0.5); await sleep(0.6)
        let af2 = p.engine.getString("af") ?? ""
        TestHooks.log("\(af2 != af && af2.contains(AutoEq.label) ? "✓" : "✗") 强度 50%：滤镜已更新")
        // 离线校验：多音测试信号（40 Hz–12 kHz 八个正弦）经 mpv 同一条滤镜渲染，逐频点对照曲线、看是否削波
        if let c = p.autoEqCurve {
            let dir = TestHooks.outDir
            let freqs: [Double] = [40, 60, 100, 250, 1000, 3000, 8000, 12000]
            let sr = 48000, n = sr * 4
            var tone = [Float](repeating: 0, count: n)
            for i in 0..<n { var v = 0.0; for f in freqs { v += 0.05 * sin(2 * .pi * f * Double(i) / Double(sr)) }; tone[i] = Float(v) }
            let src = dir.appendingPathComponent("autoeq-tones.wav")
            Self.writeWAV(tone, rate: sr, to: src)
            let a = dir.appendingPathComponent("autoeq-off.wav").path, b = dir.appendingPathComponent("autoeq-on.wav").path
            let okA = MPVEngine.renderOffline(input: src.path, output: a, options: [("af", ""), ("audio-channels", "mono")], timeout: 30)
            let okB = MPVEngine.renderOffline(input: src.path, output: b, options: [("af", AutoEq.filter(c)), ("audio-channels", "mono")], timeout: 30)
            if okA, okB, let da = try? Data(contentsOf: URL(fileURLWithPath: a)), let db = try? Data(contentsOf: URL(fileURLWithPath: b)),
               let wa = LoopSeam.readWAV(da), let wb = LoopSeam.readWAV(db) {
                let peak = wb.samples.map { abs($0) }.max() ?? 0
                func level(_ x: [Float], _ ch: Int, _ rate: Int, _ f: Double) -> Double {
                    // 取第 1–3 秒（避开滤波器起始），Goertzel 求该频点幅度
                    let start = rate, len = min(rate * 2, x.count / ch - rate - 1)
                    guard len > 1000 else { return 0 }
                    let w = 2 * Double.pi * f / Double(rate); let cw = 2 * cos(w); var s1 = 0.0, s2 = 0.0
                    for i in 0..<len {
                        let win = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(len - 1))
                        let s0 = Double(x[(start + i) * ch]) * win + cw * s1 - s2; s2 = s1; s1 = s0
                    }
                    return sqrt(max(1e-30, s1 * s1 + s2 * s2 - cw * s1 * s2))
                }
                let pre = -max(0, c.maxGain)
                var rows: [String] = []; var err = 0.0
                for f in freqs {
                    let got = 20 * log10(level(wb.samples, wb.channels, wb.rate, f) / max(1e-30, level(wa.samples, wa.channels, wa.rate, f)))
                    let want = c.gain(at: f) + pre
                    rows.append(String(format: "%.0fHz %+.1f/%+.1f", f, got, want)); err = max(err, abs(got - want))
                }
                TestHooks.log("\(err < 1.0 && peak <= 1.0 ? "✓" : "✗") 离线校验（实测/曲线 dB）：\(rows.joined(separator: "，"))；最大偏差 \(String(format: "%.2f", err)) dB；峰值 \(String(format: "%.3f", peak))（≤1 不削波）")
            } else { TestHooks.log("✗ 离线渲染失败") }
        }
        // 恢复：关掉校正、清空选择（自测沙盒，不影响本人设置）
        p.setAutoEqEnabled(false); p.autoEqEntry = nil; p.autoEqCurve = nil; p.autoEqQuery = ""; p.setAutoEqStrength(1); p.persistAutoEq()
        await sleep(0.4)
        let af3 = p.engine.getString("af") ?? ""
        TestHooks.log("\(af3.contains(AutoEq.label) ? "✗" : "✓") 关闭校正后 af 不含校正")
        if p.autoEqPanelOpen { p.toggleAutoEqPanel() }
        p.pause(); await sleep(0.5)
    }

    // MARK: 默认封面风格
    private func coverStyleTests() async {
        TestHooks.log("== 默认封面风格")
        let dir = TestHooks.outDir.appendingPathComponent("covers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let samples: [(String, String, String)] = [("album|海边|Aurora Lane", "海边", "Aurora Lane"), ("track|晚风|陈默", "晚风", "陈默"),
                                                   ("track|Midnight Drive|Neon Coast", "Midnight Drive", "Neon Coast"), ("album|山与湖|林间", "山与湖", "林间")]
        let total: Double = await Task.detached {
            var total = 0.0
            for st in DefaultCoverStyle.allCases {
                for (k, (seed, title, artist)) in samples.enumerated() {
                    let t0 = Date()
                    let img = CoverStore.defaultCover(spec: DefaultCoverSpec.make(seed: seed), style: st, title: title, artist: artist, size: 900)
                    total += Date().timeIntervalSince(t0)
                    let url = dir.appendingPathComponent("s\(st.rawValue)-\(k).png") as CFURL
                    if let d = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) { CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d) }
                }
            }
            return total
        }.value
        TestHooks.log("  导出 \(DefaultCoverStyle.allCases.count) 种风格 × \(samples.count) 首 → covers/（900px，平均每张 \(String(format: "%.0f", total / Double(DefaultCoverStyle.allCases.count * samples.count) * 1000))ms）")
        // 歌单里相邻不重样（同专辑除外）、同一首稳定、真实封面不受影响
        let items = p.queue.items
        let st = items.map { p.defaultStyle(for: $0) }
        var clash = 0
        for i in 1..<max(1, items.count) where st[i] == st[i - 1] && items[i].coverSeed != items[i - 1].coverSeed { clash += 1 }
        let again = items.map { p.defaultStyle(for: $0) }
        let real = items.filter { p.art(for: $0)?.isGenerated == false }
        let realOK = real.allSatisfy { p.art(for: $0)?.style == nil }
        TestHooks.log("\(clash == 0 && st == again && realOK ? "✓" : "✗") 歌单 \(items.count) 首：相邻撞风格 \(clash) 处；两次分配一致 \(st == again ? "是" : "否")；有真实封面的 \(real.count) 首保持原图 \(realOK ? "是" : "否")；分配：" + zip(items, st).map { "\($0.0.title)=\($0.1.name)" }.joined(separator: " "))
        p.selectTab(.playlist); await sleep(1.5)
        await requestShot("v1-cover-styles-playlist")
        p.selectTab(.nowPlaying); await sleep(1.0)
        await requestShot("v2-cover-styles-carousel")
    }

    // MARK: 区间时间输入条

    // MARK: 视频全屏：去掉容器边框，只按片源比例留黑
    private func videoFullscreenFitTest() async {
        TestHooks.log("== 视频全屏铺满（去掉播放器容器边框）")
        p.syncWindowFullScreen()
        if p.windowFullScreen { p.toggleFullScreen(); await sleep(2.0); p.syncWindowFullScreen() }
        guard let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) else { TestHooks.log("✗ 没有视频素材"); return }
        p.selectTab(.nowPlaying)
        p.play(index: vi, from: 8); await sleep(1.5)
        if p.chromeVisible == false { p.pokeChrome(); await sleep(0.3) }
        let aspect = p.videoAspect
        TestHooks.log("  片源比例 \(String(format: "%.4f", aspect))（\(p.current?.title ?? "-")），窗口全屏=\(p.windowFullScreen) 舞台=\(p.videoStageOpen)")
        p.toggleFullScreen(); await sleep(2.4)
        p.syncWindowFullScreen()
        // 控件叠在画面上，不参与布局：等淡出再截一张纯净画面
        await sleep(3.2)
        guard let win = p.mainWindow, let content = win.contentView else { TestHooks.log("✗ 没有主窗口"); return }
        let wr = content.bounds
        let vf = p.videoSurface.convert(p.videoSurface.bounds, to: content)
        let pad = VideoLayout.stagePadding(fullscreen: true, compact: wr.width < 860)
        let fit = VideoLayout.fitted(containerWidth: wr.width - pad.horizontal * 2, containerHeight: wr.height - pad.vertical * 2, aspect: aspect)
        let expected = CGRect(x: fit.x + pad.horizontal, y: fit.y + pad.vertical, width: fit.width, height: fit.height)
        let dx = abs(vf.minX - expected.minX), dy = abs(vf.minY - expected.minY)
        let dw = abs(vf.width - expected.width), dh = abs(vf.height - expected.height)
        let aspectErr = abs((vf.height > 0 ? vf.width / vf.height : 0) - aspect)
        let sidesTight = min(fit.letterboxLeft, fit.letterboxRight) < 1 || min(fit.letterboxTop, fit.letterboxBottom) < 1
        let ok = p.windowFullScreen && p.videoStageOpen && pad.horizontal == 0 && pad.vertical == 0
            && dx < 4 && dy < 4 && dw < 4 && dh < 4 && aspectErr < 0.01
            && (fit.letterboxLeft + fit.letterboxRight < 1 || fit.letterboxTop + fit.letterboxBottom < 1)
        TestHooks.log("\(ok ? "✓" : "✗") 视频全屏铺满：窗口 \(Int(wr.width))×\(Int(wr.height))，画面 \(Int(vf.minX)),\(Int(vf.minY)) \(Int(vf.width))×\(Int(vf.height))，期望 \(Int(expected.minX)),\(Int(expected.minY)) \(Int(expected.width))×\(Int(expected.height))；左右留黑 \(String(format: "%.1f+%.1f", fit.letterboxLeft, fit.letterboxRight)) 上下留黑 \(String(format: "%.1f+%.1f", fit.letterboxTop, fit.letterboxBottom))（仅片源比例，无 36pt 容器边距）；比例误差 \(String(format: "%.4f", aspectErr))；全屏=\(p.windowFullScreen) 舞台=\(p.videoStageOpen)")
        _ = sidesTight
        await requestShot("fs1-video-fullscreen-fit")
        let chromeWas = p.chromeVisible
        p.chromeVisible = false; await sleep(0.5)
        await requestShot("fs1b-video-fullscreen-clean")
        p.chromeVisible = chromeWas
        p.toggleFullScreen(); await sleep(2.0)
        p.syncWindowFullScreen()
        TestHooks.log("\(!p.windowFullScreen ? "✓" : "✗") 退出全屏后窗口已复原")
    }

    // MARK: 循环点：主进度条拖选，原曲原时间轴循环
    private func loopDragOnOriginalTimelineTest() async {
        TestHooks.log("== 循环点拖选（原曲时间轴，不换新媒体）")
        if p.windowFullScreen { p.toggleFullScreen(); await sleep(2.0); p.syncWindowFullScreen() }
        guard let ai = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) else { TestHooks.log("✗ 没有音频素材"); return }
        p.selectTab(.nowPlaying)
        p.play(index: ai, from: 12); await sleep(1.2)
        p.pokeChrome()
        let dur0 = p.duration ?? 0
        let url0 = p.current?.url
        let id0 = p.current?.id
        let n0 = p.queue.items.count
        let path0 = p.engine.getString("path")
        let start0 = p.engine.getString("start") ?? ""
        let end0 = p.engine.getString("end") ?? ""
        if !p.loopEditorOpen { p.toggleLoopEditor(); await sleep(0.8) }
        // 没有辅助功能权限时无法合成真实鼠标拖动：走与松手相同的 LoopScrub.commit → setLoopRange
        // 区间 2 秒（与既有 loopTests 的 3–5 秒同跨度），7.5 秒内应跳回约 3 次。先前 12–18 秒在 7.5 秒里只够跳回 1 次，那是用例窗口算错，不是产品未循环。
        let hit = LoopScrub.hit(editorOpen: true, optionHeld: false, t0: 12, a: nil, b: nil, duration: dur0, grab: 1)
        let comm = LoopScrub.commit(start: 12, end: 14, duration: dur0)
        TestHooks.log("  模式指针/命中：展开后不按 ⌥ 拖 12s → \(String(describing: hit))")
        guard let comm else { TestHooks.log("✗ 12–14 秒未能提交区间"); return }
        p.setLoopRange(comm.0, comm.1, quiet: true); await sleep(0.4)
        p.seek(to: comm.0); await sleep(0.4)
        let dur1 = p.duration ?? 0
        let sameItem = p.current?.url == url0 && p.current?.id == id0 && p.queue.items.count == n0
        let samePath = p.engine.getString("path") == path0
        let sameDuration = abs(dur1 - dur0) < 0.2 && abs(LoopScrub.displayedDuration(original: dur0, loop: (comm.0, comm.1)) - dur0) < 1e-9
        let frac = LoopScrub.progressFraction(position: 13, duration: dur0, loop: (comm.0, comm.1))
        let notRemapped = abs(frac - 13 / max(dur0, 0.001)) < 1e-9
        let clamped = LoopScrub.progressFraction(position: 15, duration: dur0, loop: (comm.0, comm.1))
        let clampOK = abs(clamped - 14 / max(dur0, 0.001)) < 1e-6  // 仍按原总长，只是游标夹在 B，不是新时间轴
        let abA = p.engine.getString("ab-loop-a") ?? "-"
        let abB = p.engine.getString("ab-loop-b") ?? "-"
        let start1 = p.engine.getString("start") ?? ""
        let end1 = p.engine.getString("end") ?? ""
        let noClipProps = start1 == start0 && end1 == end0
        var wraps = 0, last = p.engine.getDouble("time-pos") ?? p.position, maxPos = 0.0, minPos = 1e9
        if !p.isPlaying { p.togglePlay(); await sleep(0.2) }
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 7.5 {
            await sleep(0.03)
            let x = p.engine.getDouble("time-pos") ?? 0
            if x + 0.5 < last { wraps += 1 }
            if Date().timeIntervalSince(t0) > 0.4 { maxPos = max(maxPos, x); minPos = min(minPos, x) }
            last = x
        }
        let wrapOK = (2...4).contains(wraps) && maxPos <= 14.08 && minPos >= 11.4
        let ok = hit == .select(origin: 12) && sameItem && samePath && sameDuration && notRemapped && clampOK && noClipProps && p.abA != nil && p.abB != nil && wrapOK
        TestHooks.log("\(ok ? "✓" : "✗") 拖选循环在原曲上：命中=\(String(describing: hit))，同一文件 \(sameItem) 同一 path \(samePath)，总长 \(String(format: "%.3f→%.3f", dur0, dur1))（未改成区间长），进度 13s 为 \(String(format: "%.3f", frac))（原轴 13/总长），越 B 的 15s 夹在原轴 \(String(format: "%.3f", clamped))（不是新时间轴）；mpv ab-loop-a=\(abA) b=\(abB) start=\(start1.isEmpty ? "空" : start1) end=\(end1.isEmpty ? "空" : end1)；7.5 秒跳回 \(wraps) 次，位置 \(String(format: "%.2f–%.2f", minPos, maxPos))；队列仍 \(p.queue.items.count) 项")
        await requestShot("ld1-loop-drag-on-timeline")
        p.clearABLoop()
        if p.loopEditorOpen { p.toggleLoopEditor() }
        await sleep(0.5)
        TestHooks.log("\(p.abA == nil ? "✓" : "✗") 取消/清除后循环已去掉，仍在原曲 \(p.current?.title ?? "-")")
    }

    private func loopEditorTest() async {
        TestHooks.log("== 区间时间输入")
        guard let i = p.queue.items.firstIndex(where: { $0.kind == .audio && $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) else { return }
        p.selectTab(.nowPlaying)
        p.play(index: i, from: 10); await sleep(1.2)
        p.setLoopRange(12.345, 21.5)
        if !p.loopEditorOpen { p.toggleLoopEditor() }
        await sleep(0.8)
        p.setLoopPoint(start: true, TimeFormat.parse("00:13.250") ?? 0)
        p.nudgeLoop(start: false, by: 0.1)
        await sleep(0.6)
        let ok = abs((p.abA ?? 0) - 13.25) < 0.002 && abs((p.abB ?? 0) - 21.6) < 0.002
        TestHooks.log("\(ok ? "✓" : "✗") 输入起点 00:13.250、终点 +0.1 秒 → A=\(TimeFormat.precise(p.abA)) B=\(TimeFormat.precise(p.abB))；mpv ab-loop-a=\(p.engine.getString("ab-loop-a") ?? "-") b=\(p.engine.getString("ab-loop-b") ?? "-")")
        await requestShot("l3-loop-editor")
        p.toggleLoopEditor(); p.clearABLoop(); await sleep(0.6)
        p.pause()
    }

    // MARK: 改尺寸无黑帧：每画一帧在画面里 5×5 抽样数纯黑点；同时让截图守护连拍窗口
    private final class FrameStats: @unchecked Sendable {
        let lock = NSLock()
        var frames = 0, blackFrames = 0, partial = 0, maxBlack = 0
        var sizes = Set<String>()
        func add(_ w: Int, _ h: Int, _ black: Int, _ total: Int) {
            lock.lock(); defer { lock.unlock() }
            frames += 1; maxBlack = max(maxBlack, black)
            if black >= total - 2 { blackFrames += 1 } else if black > 0 { partial += 1 }
            sizes.insert("\(w)x\(h)")
        }
        func take() -> (Int, Int, Int, Int, Int) {
            lock.lock(); defer { lock.unlock() }
            let r = (frames, blackFrames, partial, maxBlack, sizes.count)
            frames = 0; blackFrames = 0; partial = 0; maxBlack = 0; sizes = []
            return r
        }
    }

    private func resizeTests() async {
        TestHooks.log("== 改尺寸 / 全屏 / 迷你窗 / 改比例：黑帧检测")
        guard let vi = p.queue.items.firstIndex(where: { $0.kind == .video }), let win = p.mainWindow else { return }
        p.setAspect("no"); p.selectTab(.nowPlaying)
        p.play(index: vi, from: 2); await sleep(2.0)
        let st = FrameStats()
        p.videoSurface.glLayer.frameProbe = { w, h, b, t in st.add(w, h, b, t) }
        _ = st.take()
        func report(_ name: String) {
            let (f, bf, part, mb, ns) = st.take()
            TestHooks.log("\(bf == 0 && f > 0 ? "✓" : "✗") \(name)：渲染 \(f) 帧（\(ns) 种尺寸），整帧黑 \(bf) 帧，局部黑点帧 \(part)，单帧最多黑点 \(mb)/25")
        }
        // 1) 拖窗口改大小（连续 90 步，每步 16ms，模拟手拖）
        let f0 = win.frame
        startBurst("r1-resize-burst", seconds: 3.5)
        await sleep(0.3)
        for k in 0..<90 {
            let s = 1 - 0.32 * sin(Double(k) / 90 * .pi * 2)
            var f = f0; f.size.width = f0.width * s; f.size.height = f0.height * (0.5 + 0.5 * s)
            win.setFrame(f, display: true)
            await sleep(0.016)
        }
        win.setFrame(f0, display: true)
        await sleep(0.5)
        report("拖动改窗口大小")
        await waitBurst("r1-resize-burst")
        // 2) 全屏进出
        startBurst("r2-fullscreen-burst", seconds: 4)
        win.toggleFullScreen(nil); await sleep(2.2)
        win.toggleFullScreen(nil); await sleep(2.2)
        report("全屏进入/退出")
        await waitBurst("r2-fullscreen-burst")
        // 3) 迷你窗进出
        startBurst("r3-mini-burst", seconds: 3)
        p.togglePinnedMini(); await sleep(1.5)
        p.togglePinnedMini(); await sleep(1.5)
        report("迷你窗切换")
        await waitBurst("r3-mini-burst")
        // 4) 改画面比例
        p.setAspect("4:3"); await sleep(1.2)
        p.setAspect("no"); await sleep(1.2)
        report("改画面比例（4:3 → 原始）")
        p.videoSurface.glLayer.frameProbe = nil
        p.pause()
    }

    /// 让截图守护连拍主窗口 seconds 秒（不等待）
    private func startBurst(_ name: String, seconds: Double) {
        let req = TestHooks.outDir.appendingPathComponent("\(name).req")
        try? FileManager.default.removeItem(at: TestHooks.outDir.appendingPathComponent("\(name).done"))
        try? "burst \(seconds)".write(to: req, atomically: true, encoding: .utf8)
    }
    private func waitBurst(_ name: String) async {
        let done = TestHooks.outDir.appendingPathComponent("\(name).done")
        for _ in 0..<100 { if FileManager.default.fileExists(atPath: done.path) { break }; await sleep(0.1) }
        TestHooks.log("连拍 \(name)")
    }

    private func requestShot(_ name: String, menuWindow: Bool = false, kind: String? = nil) async {
        let req = TestHooks.outDir.appendingPathComponent("\(name).req")
        let done = TestHooks.outDir.appendingPathComponent("\(name).done")
        try? FileManager.default.removeItem(at: done)
        try? (kind ?? (menuWindow ? "menu" : "main")).write(to: req, atomically: true, encoding: .utf8)
        for _ in 0..<100 { if FileManager.default.fileExists(atPath: done.path) { break }; await sleep(0.1) }
        TestHooks.log("截图 \(name)")
    }

    /// 把一份菜单数据作为真实 NSMenu 弹出在窗口里，截图后关闭
    private func shootMenu(_ name: String, _ nodes: [MenuNode], at pt: CGPoint, submenuPath: [String] = []) async {
        guard let win = p.mainWindow, let view = win.contentView else { return }
        // submenuPath：直接弹出那一层子菜单（程序里没法替用户“悬停展开”）
        var level = nodes
        for t in submenuPath { if let n = level.first(where: { $0.title == t }), case .submenu(let kids) = n.kind { level = kids } }
        let menu = NSMenuBuilder.build(level)
        let req = TestHooks.outDir.appendingPathComponent("\(name).req")
        let done = TestHooks.outDir.appendingPathComponent("\(name).done")
        try? FileManager.default.removeItem(at: done)
        var ticks = 0
        let t = Timer(timeInterval: 0.1, repeats: true) { timer in
            MainActor.assumeIsolated {
                ticks += 1
                if ticks == 4 { try? "menu".write(to: req, atomically: true, encoding: .utf8) }
                if FileManager.default.fileExists(atPath: done.path) || ticks > 120 { timer.invalidate(); menu.cancelTracking() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        let local = CGPoint(x: pt.x, y: view.bounds.height - pt.y)
        menu.popUp(positioning: nil, at: local, in: view)
        TestHooks.log("截图 \(name)（弹出菜单）")
        await sleep(0.4)
    }

    private func shots() async {
        TestHooks.log("== 截图")
        p.setTheme(.followCover)
        if let ai = p.queue.items.firstIndex(where: { $0.title == "雾中灯" }) ?? p.queue.items.firstIndex(where: { $0.kind == .audio }) { p.play(index: ai, from: 8) }
        p.selectTab(.nowPlaying); await sleep(2.5)
        await requestShot("g1-nowplaying-followCover")
        p.setTheme(.midnight); await sleep(1.6); await requestShot("g2-nowplaying-midnight")
        p.setTheme(.mistViolet); await sleep(1.6); await requestShot("g3-nowplaying-mistViolet")
        p.selectTab(.playlist); await sleep(1.2); await requestShot("g4-playlist-mistViolet")
        p.selectTab(.equalizer); await sleep(1.2); await requestShot("g5-equalizer-mistViolet")
        p.setTheme(.midnight); await sleep(1.6); await requestShot("g6-equalizer-midnight")
        p.selectTab(.playlist); await sleep(1.2); await requestShot("g7-playlist-midnight")
        p.selectTab(.nowPlaying); await sleep(0.8)
        p.setTheme(.white); await sleep(1.6); await requestShot("t1-nowplaying-white")
        p.selectTab(.playlist); await sleep(1.2); await requestShot("t2-playlist-white")
        p.selectTab(.equalizer); await sleep(1.2); await requestShot("t3-equalizer-white")
        p.selectTab(.nowPlaying); await sleep(0.8)
        p.setTheme(.black); await sleep(1.6); await requestShot("t4-nowplaying-black")
        p.setTheme(.liuli); await sleep(1.6); await requestShot("t5-nowplaying-liuli")
        p.selectTab(.playlist); await sleep(1.2); await requestShot("t6-playlist-liuli")
        p.selectTab(.nowPlaying); await sleep(0.8)
        p.setTheme(.celadon); await sleep(1.6); await requestShot("t7-nowplaying-celadon")
        p.setTheme(.celadon); p.selectTab(.nowPlaying); await sleep(1.6)
        // 拖入高亮（主窗口 / 播放列表插入线）
        withAnimation(Motion.panel) { p.isDropTargeted = true }; await sleep(0.9); await requestShot("d1-drop-main")
        withAnimation(Motion.panel) { p.isDropTargeted = false }; await sleep(0.6)
        p.selectTab(.playlist); await sleep(1.0)
        withAnimation(Motion.panel) { p.playlistDropTargeted = true; p.dropInsertIndex = 2 }; await sleep(0.9); await requestShot("d2-drop-playlist-insert")
        withAnimation(Motion.panel) { p.playlistDropTargeted = false; p.dropInsertIndex = nil }; await sleep(0.6)
        // 菜单截图
        p.selectTab(.nowPlaying); await sleep(1.0)
        let w = p.mainWindow?.contentView?.bounds ?? .zero
        await shootMenu("m1-menu-playback", MenuCatalog.playback(p), at: CGPoint(x: 40, y: 60))
        await shootMenu("m2-menu-audio", MenuCatalog.audio(p), at: CGPoint(x: 40, y: 60))
        await shootMenu("m3-menu-video", MenuCatalog.video(p), at: CGPoint(x: 40, y: 60))
        await shootMenu("m4-menu-file", MenuCatalog.file(p), at: CGPoint(x: 40, y: 60))
        await shootMenu("m5-menu-playlist", MenuCatalog.playlist(p), at: CGPoint(x: 40, y: 60))
        await shootMenu("c1-context-card", MenuCatalog.card(p, index: p.queue.currentIndex ?? 0), at: CGPoint(x: w.midX + 40, y: w.midY - 60))
        await shootMenu("c2-context-playbar", MenuCatalog.playBar(p), at: CGPoint(x: w.midX, y: w.maxY - 330))
        await shootMenu("c3-context-blank", MenuCatalog.blank(p), at: CGPoint(x: 60, y: 120))
        p.selectTab(.playlist); await sleep(1.0)
        await shootMenu("c4-context-playlist-row", MenuCatalog.playlistRow(p, index: 1), at: CGPoint(x: w.midX - 120, y: 220))
        p.selectTab(.equalizer); await sleep(1.0)
        await shootMenu("c5-context-equalizer", MenuCatalog.equalizer(p), at: CGPoint(x: w.midX - 100, y: 260))
        if let vi = p.queue.items.firstIndex(where: { $0.kind == .video }) {
            p.selectTab(.nowPlaying); p.play(index: vi, from: 5); await sleep(2.5); p.pause(); await sleep(0.8)
            await requestShot("v1-video-celadon")
            await shootMenu("c6-context-video", MenuCatalog.videoSurface(p), at: CGPoint(x: w.midX - 150, y: w.midY - 150))
        }
        // 迷你窗
        if let ai = p.queue.items.firstIndex(where: { $0.title == "晚风" }) { p.play(index: ai, from: 5); await sleep(1.5) }
        p.togglePinnedMini(); await sleep(1.6); await requestShot("k1-mini")
        await shootMenu("c7-context-mini", MenuCatalog.blank(p), at: CGPoint(x: 120, y: 60))
        p.togglePinnedMini(); await sleep(1.4)
        p.toggleShortcutsHelp(); await sleep(1.0); await requestShot("h1-shortcuts"); p.toggleShortcutsHelp(); await sleep(0.6)
        p.pause()
    }
}

/// 自测用的拖放信息：只提供剪贴板（与真实拖放读取方式一致）
final class FakeDrag: NSObject, NSDraggingInfo {
    let pb: NSPasteboard
    init(_ pb: NSPasteboard) { self.pb = pb }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pb }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation { get { .default } set {} }
    var animatesToDestination: Bool { get { false } set {} }
    var numberOfValidItemsForDrop: Int { get { 1 } set {} }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
