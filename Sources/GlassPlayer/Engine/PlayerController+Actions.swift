// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import ImageIO
import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PlayerCore

/// 菜单栏、右键菜单、快捷键共用的全部操作。每个操作都给 HUD 反馈，状态变化都包在动画里。
extension PlayerController {
    // MARK: - 文件
    func presentAddPanel(folders: Bool) { addSongs(folders: folders) }

    /// 「添加歌曲…」「添加文件夹…」：每个右键菜单顶上、文件菜单、空库页都走这里。
    /// 多选；文件夹会递归找里面所有能播的音频和视频；加到列表末尾（不打断正在播放的），
    /// 列表原来是空的就直接播第一首。取消选择对话框 = 什么都不变。
    func addSongs(folders: Bool) {
        let urls: [URL]
        if let t = TestHooks.openPanel(folders: folders) { urls = t }
        else {
            let p = NSOpenPanel()
            p.canChooseFiles = !folders; p.canChooseDirectories = folders; p.allowsMultipleSelection = true
            if !folders { p.allowedContentTypes = [.audio, .movie, .audiovisualContent, .data] }
            p.prompt = "添加"
            p.message = folders ? "选择一个或多个文件夹，里面的音乐和视频（含子文件夹）都会加到列表末尾" : "选择一首或多首歌（也可以是视频），加到列表末尾，不打断正在播放的"
            guard p.runModal() == .OK else { lastAddCancelled = true; return }
            urls = p.urls
        }
        guard !urls.isEmpty else { lastAddCancelled = true; return }
        lastAddCancelled = false
        let wasEmpty = queue.items.isEmpty
        withAnimation(Motion.panel) { open(urls, playNow: wasEmpty) }
    }

    func openURLPrompt() {
        guard let text = Prompt.text(key: "url", title: "打开网址", message: "输入音频或视频的网络地址（http / https），或本地文件路径", placeholder: "https://…") else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("/") || t.hasPrefix("~") { open([URL(fileURLWithPath: (t as NSString).expandingTildeInPath)], playNow: true); return }
        guard let u = URL(string: t), let sch = u.scheme?.lowercased(), ["http", "https", "file"].contains(sch) else {
            showHUD("exclamationmark.circle", "不是有效的网址"); return
        }
        if u.isFileURL { open([u], playNow: true) } else { openRemote(u, playNow: true) }
    }

    func openRemote(_ u: URL, playNow: Bool) {
        let item = MediaItem(url: u, title: u.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? u.absoluteString)
        let first = queue.append([item])
        syncCarouselCount()
        noteRecent([u])
        if playNow, let f = first { play(index: f, from: 0) } else { refreshLookahead() }
        showHUD("globe", "已添加网络地址")
        scheduleSave()
    }

    /// 网络地址没有扩展名时先按音频处理，加载后发现有画面就改成视频
    func promoteToVideoIfNeeded() {
        guard var cur = current, cur.kind == .audio else { return }
        if tracks.contains(where: { $0.kind == .video && !$0.isAlbumArt }) && !cur.url.isFileURL {
            cur.kind = .video
            queue.update(cur)
            withAnimation(Motion.panel) { tab = .nowPlaying }
        }
    }

    func noteRecent(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var r = recent
        for u in urls.reversed() { r.removeAll { $0 == u }; r.insert(u, at: 0) }
        recent = Array(r.prefix(12))
        Prefs.recent = recent
    }

    func clearRecent() { withAnimation(Motion.toggle) { recent = [] }; Prefs.recent = []; showHUD("clock.arrow.circlepath", "已清除最近打开") }

    func openRecent(_ u: URL) {
        if u.isFileURL {
            guard FileManager.default.fileExists(atPath: u.path) else { showHUD("questionmark.folder", "文件已不在原处"); recent.removeAll { $0 == u }; Prefs.recent = recent; return }
            open([u], playNow: true)
        } else { openRemote(u, playNow: true) }
    }

    func savePlaylistPanel() {
        guard !queue.items.isEmpty else { showHUD("exclamationmark.circle", "播放列表是空的"); return }
        var target: URL? = TestHooks.saveURL()
        if target == nil {
            let p = NSSavePanel()
            p.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
            p.nameFieldStringValue = "胭脂播放列表.m3u8"
            p.message = "保存为 .m3u8（其他播放器也能打开）"
            if p.runModal() == .OK { target = p.url }
        }
        guard let url = target else { return }
        do {
            try PlaylistFile.m3u8(queue.items).write(to: url, atomically: true, encoding: .utf8)
            showHUD("square.and.arrow.down", "已保存 \(queue.items.count) 项")
        } catch { showHUD("exclamationmark.triangle", "保存失败") }
    }

    func loadPlaylistPanel() {
        var target: URL? = TestHooks.active ? TestHooks.saveURL() : nil
        if target == nil {
            let p = NSOpenPanel()
            p.allowedContentTypes = ["m3u8", "m3u", "pls"].compactMap { UTType(filenameExtension: $0) }
            p.prompt = "载入"
            if p.runModal() == .OK { target = p.url }
        }
        if let u = target { loadPlaylist(at: u) }
    }

    func loadPlaylist(at url: URL) {
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
            showHUD("exclamationmark.triangle", "读不了这个列表"); return
        }
        let urls = PlaylistFile.parse(text, relativeTo: url.deletingLastPathComponent())
        let local = urls.filter(\.isFileURL), remote = urls.filter { !$0.isFileURL }
        let items = Self.expand(local).map { MediaItem(url: $0) } + remote.map { MediaItem(url: $0, title: $0.lastPathComponent) }
        guard !items.isEmpty else { showHUD("exclamationmark.circle", "列表里没有能播放的文件"); return }
        withAnimation(Motion.panel) {
            engine.stop()
            queue.replace(with: items)
            syncCarouselCount()
        }
        for it in items.prefix(24) { ensureDetails(it) }
        play(index: 0, from: 0)
        showHUD("music.note.list", "已载入 \(items.count) 项")
        noteRecent([url])
        scheduleSave()
    }

    // MARK: - 编辑
    func copyInfo(_ item: MediaItem?) {
        guard let it = item ?? current else { return }
        var s = it.title + (it.knownArtist.map { " — " + $0 } ?? "")
        if let a = it.album, !a.isEmpty { s += " · " + a }
        s += "\n" + (it.url.isFileURL ? it.url.path : it.url.absoluteString)
        let pb = TestHooks.active ? NSPasteboard(name: .init("com.tanco.glassplayer.selftest")) : NSPasteboard.general
        pb.clearContents(); pb.setString(s, forType: .string)
        showHUD("doc.on.doc", "已拷贝曲目信息")
    }

    /// 显示简介：回到「正在播放」，转到这首，翻到卡片背面
    func showInfo(index: Int? = nil) {
        guard let i = index ?? queue.currentIndex, queue.items.indices.contains(i) else { return }
        withAnimation(Motion.tab) { tab = .nowPlaying }
        if queue.items[i].kind == .video { showHUD("info.circle", queue.items[i].formatLine ?? queue.items[i].title); return }
        if carousel.centeredIndex != i { carousel.jump(to: i); runCarousel() }
        after(carousel.centeredIndex == i ? 0.05 : 0.45) { [weak self] in withAnimation(Motion.lift) { self?.isLifted = true } }
    }

    func revealCurrent() { if let c = current { revealInFinder(c) } }

    // MARK: - 播放
    func stop() {
        guard hasMedia else { return }
        pause(); seek(to: 0)
        showHUD("stop.fill", "停止")
    }

    func restart() { seek(to: 0); showHUD("backward.end.fill", "从头播放") }

    func jumpPrompt() {
        guard duration != nil else { return }
        guard let t = Prompt.text(key: "jump", title: "跳转到", message: "输入时间，例如 1:23 或 01:02:03（总长 \(TimeFormat.clock(duration))）", placeholder: TimeFormat.clock(position)) else { return }
        guard let sec = TimeFormat.parse(t) else { showHUD("exclamationmark.circle", "时间格式不对"); return }
        seek(to: sec)
        showHUD("arrow.right.to.line", "跳到 \(TimeFormat.clock(sec))")
    }

    func speedStep(_ d: Double) { setSpeed(speed + d) }

    /// 变调（不改速度）：只替换滤镜链里带标签的那一段，均衡器和声道那几段原样保留
    func setPitch(semitones: Int, cents: Int, hud: Bool = true) {
        let st = min(SpeedPitch.semitoneRange.upperBound, max(SpeedPitch.semitoneRange.lowerBound, semitones))
        let ct = min(SpeedPitch.centsRange.upperBound, max(SpeedPitch.centsRange.lowerBound, cents))
        guard st != pitchSemitones || ct != pitchCents else { return }
        pitchSemitones = st; pitchCents = ct
        applyAudioFilters()
        if hud { showHUD("tuningfork", st == 0 && ct == 0 ? "原调" : "音调 \(SpeedPitch.pitchText(semitones: st, cents: ct))（速度不变）") }
    }
    func pitchStep(semitones d: Int) { setPitch(semitones: pitchSemitones + d, cents: pitchCents) }
    func pitchStep(cents d: Int) {
        // 音分越过 ±50 时进位到半音，保持连续
        var st = pitchSemitones, ct = pitchCents + d
        if ct > 50 { st += 1; ct -= 100 } else if ct < -50 { st -= 1; ct += 100 }
        if st > SpeedPitch.semitoneRange.upperBound || st < SpeedPitch.semitoneRange.lowerBound { return }
        setPitch(semitones: st, cents: ct)
    }
    func resetSpeedPitch() {
        let changed = speed != 1 || pitchSemitones != 0 || pitchCents != 0
        setSpeed(1, hud: false); setPitch(semitones: 0, cents: 0, hud: false)
        showHUD("arrow.counterclockwise", changed ? "已恢复：100% 速度、原调" : "已是 100% 速度、原调")
    }
    func toggleSpeedPitchPanel() { withAnimation(Motion.panel) { speedPitchOpen.toggle() } }

    func setRepeat(_ m: RepeatMode) {
        guard m != queue.repeatMode else { return }
        while queue.repeatMode != m { queue.repeatMode = queue.repeatMode.next }
        refreshLookahead()
        showHUD(m == .one ? "repeat.1" : (m == .off ? "arrow.right" : "repeat"), m.label)
        scheduleSave()
    }

    func setShuffle(_ on: Bool) { if on != queue.shuffle { toggleShuffle() } }

    /// A-B 循环：第一次设 A，第二次设 B（开始循环），第三次清除
    func abLoopCycle() {
        guard hasMedia else { return }
        if abA == nil { setLoopStart() }
        else if abB == nil, let a = abA, position > a + 0.3 { setLoopRange(a, position) }
        else { clearABLoop() }
    }

    /// 区间循环用 mpv 自带的 ab-loop：到 B 点精确跳回 A 点（精确定位 + 缓存里的数据，不重新打开文件），
    /// 循环次数无限；A/B 在 App 里也存一份用于进度条绘制。
    static let minLoop = 0.2
    func setLoopStart(_ t: Double? = nil) {
        guard hasMedia else { return }
        let a = t ?? position
        if let b = abB, b > a + Self.minLoop { setLoopRange(a, b); return }
        withAnimation(Motion.toggle) { abA = a; abB = nil }
        engine.setString("ab-loop-a", String(format: "%.3f", a)); engine.setString("ab-loop-b", "no")
        showHUD("a.circle", "起点 \(TimeFormat.clock(a))")
        scheduleLoopSeam()
    }
    func setLoopEnd(_ t: Double? = nil) {
        guard hasMedia else { return }
        let b = t ?? position
        let a = abA ?? 0
        guard b > a + Self.minLoop else { showHUD("exclamationmark.circle", "终点要在起点之后"); return }
        setLoopRange(a, b)
    }
    /// 设置整段区间（拖选、拖手柄、菜单都走这里）
    func setLoopRange(_ a0: Double, _ b0: Double, quiet: Bool = false) {
        guard hasMedia else { return }
        var a = min(a0, b0), b = max(a0, b0)
        if let d = duration { a = max(0, min(a, d)); b = max(0, min(b, d)) }
        guard b - a >= Self.minLoop else { return }
        withAnimation(Motion.toggle) { abA = a; abB = b }
        engine.setString("ab-loop-count", "inf")
        engine.setString("ab-loop-a", String(format: "%.3f", a))
        engine.setString("ab-loop-b", String(format: "%.3f", b))
        // 当前位置不在区间里：直接从起点开始
        if position < a - 0.05 || position > b { seek(to: a) }
        if !quiet { showHUD("repeat", "区间循环 \(TimeFormat.clock(a))–\(TimeFormat.clock(b))") }
        scheduleLoopSeam()
    }

    /// 整条音频滤镜链：均衡器 + 声道
    func audioFilterString() -> String {
        var s = ChannelMode.audioFilter(eq: eq, channel: channelMode)
        if autoEqEnabled, let c = autoEqCurve { s += (s.isEmpty ? "" : ",") + AutoEq.filter(c, strength: autoEqStrength) }
        if let f = SpeedPitch.filter(semitones: pitchSemitones, cents: pitchCents) { s += (s.isEmpty ? "" : ",") + f }
        return s
    }
    func applyAudioFilters() { engine.setString("af", audioFilterString()) }

    /// 区间变化后（停 0.15 秒再做，拖手柄时不反复算）：在后台各取 A/B 附近 ±12ms 的波形，
    /// 找出波形连续的接缝采样，再把对齐后的 A/B 交给 mpv。界面上的 A/B 仍显示你设的值。
    func scheduleLoopSeam() {
        loopSeamToken &+= 1
        let t = loopSeamToken
        guard let a = abA, let b = abB else { loopSeamInfo = nil; return }
        guard loopSeamAlign, let path = current?.url.path, current?.url.isFileURL == true else {
            loopSeamInfo = nil
            engine.setString("ab-loop-a", String(format: "%.6f", a)); engine.setString("ab-loop-b", String(format: "%.6f", b))
            return
        }
        after(0.15) { [weak self] in
            guard let self, t == self.loopSeamToken else { return }
            Task.detached(priority: .userInitiated) {
                guard let r = PlayerController.alignSeam(path: path, a: a, b: b) else { return }
                let (a2, b2, before, after) = (r.a, r.b, r.jumpBefore, r.jumpAfter)
                await MainActor.run {
                    guard t == self.loopSeamToken, self.abA == a, self.abB == b, b2 > a2 + 0.05 else { return }
                    self.engine.setString("ab-loop-a", String(format: "%.6f", a2))
                    self.engine.setString("ab-loop-b", String(format: "%.6f", b2))
                    self.loopSeamInfo = r
                    TestHooks.log("  接缝对齐：A \(String(format: "%+.2f", (a2 - a) * 1000))ms、B \(String(format: "%+.2f", (b2 - b) * 1000))ms，接缝跳变 \(String(format: "%.4f", before)) → \(String(format: "%.4f", after))")
                }
            }
        }
    }

    /// 找接缝（后台线程可调）：取 A、B 附近波形 → 最佳接缝 → 返回 mpv 该用的 A/B
    nonisolated static func alignSeam(path: String, a: Double, b: Double) -> LoopSeamResult? {
        let w = LoopSeam.window
        let a0 = max(0, a - w), b0 = max(0, b - w)
        guard let ra = MPVEngine.extractPCM(input: path, start: a0, duration: 2 * w + 0.002),
              let rb = MPVEngine.extractPCM(input: path, start: b0, duration: 2 * w + 0.002),
              ra.channels == rb.channels, ra.rate == rb.rate,
              let best = LoopSeam.bestSplice(a: ra.samples, b: rb.samples, channels: ra.channels) else { return nil }
        let sr = Double(ra.rate), ch = ra.channels
        let a2 = a0 + Double(best.i) / sr, b2 = b0 + Double(best.j) / sr
        let ci = min(Int(((a - a0) * sr).rounded()), ra.samples.count / ch - 1), cj = min(Int(((b - b0) * sr).rounded()), rb.samples.count / ch)
        let before = LoopSeam.seamJump(a: ra.samples, b: rb.samples, channels: ch, i: ci, j: cj)
        let after = LoopSeam.seamJump(a: ra.samples, b: rb.samples, channels: ch, i: best.i, j: best.j)
        return LoopSeamResult(a: a2, b: b2, shiftA: (a2 - a) * 1000, shiftB: (b2 - b) * 1000, jumpBefore: Double(before), jumpAfter: Double(after))
    }

    func toggleLoopSeamAlign() {
        loopSeamAlign.toggle()
        showHUD("waveform.path", loopSeamAlign ? "无缝接缝：开（自动对齐波形）" : "无缝接缝：关（按原位置硬切）")
    }

    /// 输入框 / 微调按钮 / 滚轮改起点终点（保持另一端不动）
    func nudgeLoop(start: Bool, by d: Double) {
        guard let a = abA else { if start { setLoopStart(max(0, position + d)) }; return }
        if start {
            if let b = abB { setLoopRange(max(0, min(a + d, b - Self.minLoop)), b, quiet: true) } else { setLoopStart(max(0, a + d)) }
        } else if let b = abB {
            setLoopRange(a, max(a + Self.minLoop, b + d), quiet: true)
        } else { setLoopEnd(max(a + Self.minLoop, position + d)) }
    }
    func setLoopPoint(start: Bool, _ t: Double) {
        if start { setLoopStart(t) } else { setLoopEnd(t) }
    }
    // MARK: 副歌 / 段落
    /// 找副歌并直接循环（第一次要分析整首，约 1–3 秒；之后有缓存）
    func findChorusAndLoop() {
        analyzeSections { [weak self] secs in
            guard let self else { return }
            guard let best = secs.first else { self.showHUD("music.note.list", "没找到明显重复的段落（这首可能没有副歌结构）"); return }
            self.setLoopRange(best.start, best.end, quiet: true)
            if !self.isPlaying { self.togglePlay() }
            self.showHUD("music.note.list", "循环\(best.label)：\(TimeFormat.clock(best.start))–\(TimeFormat.clock(best.end))（全曲出现 \(best.repeats) 次）")
        }
    }
    func loopSection(_ i: Int) {
        guard sections.indices.contains(i) else { return }
        let s = sections[i]
        setLoopRange(s.start, s.end, quiet: true)
        showHUD("repeat.circle", "循环\(s.label)：\(TimeFormat.clock(s.start))–\(TimeFormat.clock(s.end))")
    }
    func analyzeSections(_ done: @escaping @MainActor ([ChorusDetector.Section]) -> Void) {
        guard let url = current?.url, url.isFileURL else { showHUD("music.note.list", "只能分析本地文件"); return }
        if sectionsURL == url, !sections.isEmpty { done(sections); return }
        if let c = sectionCache[url.path] { sections = c; sectionsURL = url; done(c); return }
        guard !analyzingSections else { return }
        analyzingSections = true
        showHUD("waveform.badge.magnifyingglass", "正在分析段落…")
        let dur = duration
        Task.detached(priority: .userInitiated) {
            let t0 = Date()
            let secs = PlayerController.detectSections(path: url.path, duration: dur)
            let ms = Date().timeIntervalSince(t0) * 1000
            await MainActor.run {
                self.analyzingSections = false
                self.sectionCache[url.path] = secs
                guard self.current?.url == url else { return }
                withAnimation(Motion.toggle) { self.sections = secs }
                self.sectionsURL = url
                TestHooks.log("  段落分析 \(String(format: "%.0f", ms))ms：" + secs.map { "\($0.label) \(String(format: "%.1f–%.1f", $0.start, $0.end)) ×\($0.repeats)" }.joined(separator: "，"))
                done(secs)
            }
        }
    }
    /// 后台：整首解码成单声道 22.05 kHz → 色度 → 自相似 → 段落
    nonisolated static func detectSections(path: String, duration: Double?) -> [ChorusDetector.Section] {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("liuli-sec-\(UUID().uuidString).wav").path
        defer { try? FileManager.default.removeItem(atPath: out) }
        guard MPVEngine.renderOffline(input: path, output: out, options: [("audio-channels", "mono"), ("audio-samplerate", "\(ChorusDetector.sampleRate)"), ("af", "")], timeout: 90),
              let d = FileManager.default.contents(atPath: out), let w = LoopSeam.readWAV(d), w.rate == ChorusDetector.sampleRate else { return [] }
        let mono: [Float]
        if w.channels == 1 { mono = w.samples } else {
            mono = stride(from: 0, to: w.samples.count - w.channels + 1, by: w.channels).map { i in (0..<w.channels).reduce(Float(0)) { $0 + w.samples[i + $1] } / Float(w.channels) }
        }
        let f = ChorusDetector.features(mono: mono)
        return ChorusDetector.detect(chroma: f.chroma, energy: f.energy, duration: duration)
    }

    func toggleLoopEditor() { withAnimation(Motion.panel) { loopEditorOpen.toggle() } }

    func clearABLoop() {
        withAnimation(Motion.toggle) { abA = nil; abB = nil }
        engine.setString("ab-loop-a", "no"); engine.setString("ab-loop-b", "no")
        showHUD("xmark.circle", "已取消区间循环")
        scheduleLoopSeam()
    }

    // MARK: - 音频
    func volumeStep(_ d: Double) { setVolume(volume + d, showsHUD: true) }
    func toggleMute() {
        setMuted(!muted)
        showHUD(muted ? "speaker.slash" : "speaker.wave.2", muted ? "静音" : "取消静音")
    }

    func setChannelMode(_ m: ChannelMode) {
        guard m != channelMode else { return }
        channelMode = m
        applyAudioFilters()
        showHUD("hifispeaker.2", m.title)
    }

    func nudgeAudioDelay(_ d: Double) {
        audioDelay = d == 0 ? 0 : ((audioDelay + d) * 100).rounded() / 100
        engine.setDouble("audio-delay", audioDelay)
        showHUD("waveform.badge.plus", String(format: "音频延迟 %+.2f 秒", audioDelay))
    }

    func toggleEQ() {
        setEQEnabled(!eq.enabled)
        showHUD("slider.vertical.3", eq.enabled ? "均衡器：开" : "均衡器：关")
    }

    func applyPresetFromMenu(_ p: EQPreset) {
        withAnimation(Motion.panel) { applyPreset(p) }
        showHUD("slider.vertical.3", "预设：\(p.name)")
    }

    func savePresetPrompt() {
        guard let n = Prompt.text(key: "preset", title: "保存为均衡器预设", message: "给当前的均衡器设置起个名字", placeholder: "我的预设") else { return }
        withAnimation(Motion.panel) { savePreset(named: n) }
    }

    func setBandCountFromMenu(_ c: EQBandCount) {
        withAnimation(Motion.panel) { setBandCount(c) }
        showHUD("slider.vertical.3", "\(c.rawValue) 段均衡器")
    }

    // MARK: - 视频
    static let aspectChoices: [(String, String)] = [("no", "原始比例"), ("16:9", "16:9"), ("4:3", "4:3"), ("21:9", "21:9"), ("2.35:1", "2.35:1"), ("1:1", "1:1"), ("9:16", "9:16（竖屏）")]

    func setAspect(_ a: String) {
        aspectOverride = a
        engine.setString("video-aspect-override", a == "no" ? "-1" : a)
        refreshAspectSoon()
        showHUD("aspectratio", a == "no" ? "原始比例" : "画面比例 \(a)")
    }

    func zoomStep(_ d: Double) {
        videoZoom = d == 0 ? 0 : min(2, max(-1, ((videoZoom + d) * 100).rounded() / 100))
        engine.setDouble("video-zoom", videoZoom)
        showHUD(d < 0 ? "minus.magnifyingglass" : "plus.magnifyingglass", d == 0 ? "实际大小" : "缩放 \(Int((pow(2, videoZoom) * 100).rounded()))%")
    }

    func togglePanscan() {
        panscan.toggle()
        engine.setDouble("panscan", panscan ? 1 : 0)
        showHUD("crop", panscan ? "裁切填满" : "完整画面")
    }

    func setRotation(_ deg: Int) {
        videoRotate = ((deg % 360) + 360) % 360
        engine.setString("video-rotate", String(videoRotate))
        refreshAspectSoon()
        showHUD("rotate.right", videoRotate == 0 ? "不旋转" : "旋转 \(videoRotate)°")
    }

    private func refreshAspectSoon() {
        after(0.25) { [weak self] in
            guard let self, let w = self.engine.getDouble("video-out-params/dw"), let h = self.engine.getDouble("video-out-params/dh"), h > 0 else { return }
            withAnimation(Motion.panel) { self.applyVideoAspect(w / h) }
        }
    }

    var screenshotDirectory: URL {
        if let d = UserDefaults.standard.string(forKey: "screenshotDir"), !d.isEmpty { return URL(fileURLWithPath: d) }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("胭脂截图", isDirectory: true)
    }

    @discardableResult
    func screenshot(includeSubtitles: Bool = true) -> URL? {
        guard isVideo, hasMedia else { showHUD("camera", "截图只对视频有效"); return nil }
        let dir = screenshotDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = dir.appendingPathComponent("胭脂截图 \(f.string(from: Date())).png")
        guard let img = engine.screenshotRaw(includeSubtitles ? "subtitles" : "video") ?? offscreenShot(includeSubtitles: includeSubtitles),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            showHUD("exclamationmark.triangle", "截图失败"); TestHooks.log("screenshot FAILED"); return nil
        }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { showHUD("exclamationmark.triangle", "截图保存失败"); return nil }
        showHUD("camera.fill", "已截图：\(dir.lastPathComponent)")
        TestHooks.log("screenshot \(url.path) \(img.width)x\(img.height)")
        return url
    }

    /// 硬解时 screenshot-raw 不可用：用渲染 API 按视频原尺寸离屏画一张
    private func offscreenShot(includeSubtitles: Bool) -> CGImage? {
        #if canImport(Libmpv)
        let w = Int(engine.getDouble("dwidth") ?? 0), h = Int(engine.getDouble("dheight") ?? 0)
        let wasVisible = engine.getString("sub-visibility") != "no"
        if !includeSubtitles && wasVisible { engine.setString("sub-visibility", "no") }
        defer { if !includeSubtitles && wasVisible { engine.setString("sub-visibility", "yes") } }
        return videoSurface.glLayer.snapshot(width: w, height: h)
        #else
        return nil
        #endif
    }

    func nudgeSubDelay(_ d: Double) {
        subDelay = d == 0 ? 0 : ((subDelay + d) * 100).rounded() / 100
        engine.setDouble("sub-delay", subDelay)
        showHUD("captions.bubble", String(format: "字幕延迟 %+.2f 秒", subDelay))
    }

    func cycleSubtitle() {
        let subs = subtitleTracks
        guard !subs.isEmpty else { showHUD("captions.bubble", "没有字幕"); return }
        if let i = subs.firstIndex(where: \.isSelected) {
            if i + 1 < subs.count { selectSubtitle(subs[i + 1].id); showHUD("captions.bubble", subs[i + 1].displayName) }
            else { selectSubtitle(nil); showHUD("captions.bubble", "关闭字幕") }
        } else { selectSubtitle(subs[0].id); showHUD("captions.bubble", subs[0].displayName) }
    }

    func selectAudioTrackFromMenu(_ t: MPVEngine.Track) { selectAudioTrack(t.id); showHUD("waveform", t.displayName) }
    func selectSubtitleFromMenu(_ t: MPVEngine.Track?) { selectSubtitle(t?.id); showHUD("captions.bubble", t?.displayName ?? "关闭字幕") }

    /// 窗口置顶（不改变大小）
    func toggleFloating() {
        isFloating.toggle()
        mainWindow?.level = isFloating || isPinnedMini ? .floating : .normal
        showHUD(isFloating ? "pin.fill" : "pin.slash", isFloating ? "窗口置顶" : "取消置顶")
    }

    // MARK: - 播放列表
    func playNext(index i: Int) {
        guard queue.items.indices.contains(i), let c = queue.currentIndex, i != c else { return }
        let item = queue.items[i]
        withAnimation(Motion.panel) {
            queue.move(from: i, to: c + 1 > i ? c + 1 : c + 1)
            syncCarouselCount()
            if let cc = queue.currentIndex { carousel.jump(to: cc); runCarousel() }
        }
        refreshLookahead()
        showHUD("text.line.first.and.arrowtriangle.forward", "下一首播放：\(item.title)")
        scheduleSave()
    }

    /// 拖进播放列表某个位置：插入，不打断当前播放（列表原本为空时直接开始播放）
    func insert(urls: [URL], at index: Int) {
        let files = Self.expand(urls)
        guard !files.isEmpty else { showHUD("exclamationmark.circle", "没有可播放的文件"); return }
        let wasEmpty = queue.items.isEmpty
        let items = files.map { MediaItem(url: $0) }
        var at: Int?
        withAnimation(Motion.panel) {
            at = queue.insert(items, at: index)
            syncCarouselCount()
            if let c = queue.currentIndex, !wasEmpty { carousel.jump(to: c); runCarousel() }
        }
        for it in items.prefix(24) { ensureDetails(it) }
        noteRecent(urls)
        if wasEmpty, let a = at { play(index: a, from: 0) } else { refreshLookahead() }
        showHUD("text.insert", "已插入 \(items.count) 项到第 \((at ?? 0) + 1) 位")
        scheduleSave()
    }

    /// 拖动经过播放列表时的插入线（离开时稍等一下再收起，行与行之间移动不会闪）
    func setDropInsert(_ i: Int?) {
        dropClearWork?.cancel()
        if let i {
            if dropInsertIndex != i { withAnimation(Motion.hover) { dropInsertIndex = i } }
        } else {
            dropClearWork = after(0.14) { [weak self] in withAnimation(Motion.panel) { self?.dropInsertIndex = nil } }
        }
    }

    /// 从拖放的 NSItemProvider 里取出文件 URL（按拖入顺序）
    nonisolated static func loadFileURLs(_ providers: [NSItemProvider], done: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let box = IndexedURLBox(count: providers.count)
        for (i, p) in providers.enumerated() where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { box.set(i, url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { done(box.urls) } }
    }

    func removeCurrent() { if let c = queue.currentIndex { withAnimation(Motion.panel) { remove(at: c) }; showHUD("minus.circle", "已移除") } }

    func clearQueueFromMenu() { withAnimation(Motion.panel) { clearQueue() }; showHUD("trash", "已清空播放列表") }

    enum SortKey: String, CaseIterable { case title, artist, album, filename, duration, reverse, scramble
        var title: String {
            switch self {
            case .title: return "按标题"; case .artist: return "按艺人"; case .album: return "按专辑与曲序"
            case .filename: return "按文件名"; case .duration: return "按时长"; case .reverse: return "倒序"; case .scramble: return "随机打乱"
            }
        }
    }

    func sortQueue(_ k: SortKey) {
        func cmp(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
        withAnimation(Motion.panel) {
            switch k {
            case .title: queue.sort { cmp($0.title, $1.title) }
            case .artist: queue.sort { cmp($0.displayArtist + $0.title, $1.displayArtist + $1.title) }
            case .album: queue.sort { (($0.album ?? ""), $0.discNumber ?? 0, $0.trackNumber ?? 0, $0.title) < (($1.album ?? ""), $1.discNumber ?? 0, $1.trackNumber ?? 0, $1.title) }
            case .filename: queue.sort { cmp($0.url.lastPathComponent, $1.url.lastPathComponent) }
            case .duration: queue.sort { ($0.duration ?? 0) < ($1.duration ?? 0) }
            case .reverse: queue.reverse()
            case .scramble: queue.scramble(seed: UInt64(Date().timeIntervalSince1970 * 1000))
            }
            syncCarouselCount()
            if let c = queue.currentIndex { carousel.jump(to: c); runCarousel() }
        }
        refreshLookahead()
        showHUD("arrow.up.arrow.down", k.title)
        scheduleSave()
    }

    func locateCurrent() {
        guard queue.currentIndex != nil else { return }
        withAnimation(Motion.tab) { if tab == .equalizer { tab = .playlist } }
        if tab == .nowPlaying, let c = queue.currentIndex { carousel.jump(to: c); runCarousel() }
        locateToken &+= 1
        showHUD("scope", "定位到当前曲目")
    }

    func moveItem(_ i: Int, to j: Int) {
        guard queue.items.indices.contains(i) else { return }
        let target = min(max(0, j), queue.items.count)
        withAnimation(Motion.panel) { move(from: IndexSet(integer: i), to: target) }
    }

    // MARK: - 显示 & 一键回卡片 / 全屏往返
    func selectTab(_ t: MainTab) {
        withAnimation(Motion.tab) {
            showPlayHistory = false
            activeCard = nil
            tab = t
        }
    }

    /// 当前是否正处于窗口态「卡片轮播」主界面
    var inCardMode: Bool {
        tab == .nowPlaying && !showPlayHistory && !videoStageOpen && !windowFullScreen && !viewer.isOpen && !isLifted
    }

    /// 极简一键往返（点播放控制条左下角的专辑/视频缩略图）：
    /// · 在全屏、视频大画面、播放列表、均衡器、播放记录、卡片背面、封面观赏任一页面 → 一键直接跳回「卡片模式」；
    /// · 已在「卡片模式」时再点一下 → 一键直接进入「全屏模式」（视频同步展开视频全屏，音频进入全屏）。
    func toggleCardOrFullscreen() {
        guard !queue.items.isEmpty else { return }
        let full = mainWindow?.styleMask.contains(.fullScreen) ?? windowFullScreen
        let currentlyCards = tab == .nowPlaying && !showPlayHistory && !videoStageOpen && !full && !viewer.isOpen && !isLifted
        if currentlyCards {
            withAnimation(Motion.panel) {
                activeCard = nil
                tagEditorItemID = nil
                isLifted = false
            }
            if isVideo {
                enterVideoStage()
                if !isPlaying { play() }
            }
            if !full { toggleFullScreen() }
        } else {
            let viewerHandledFull = viewer.isOpen && viewer.fullscreenByViewer
            if viewer.isOpen { closeCoverViewer() }
            withAnimation(Motion.panel) {
                showPlayHistory = false
                activeCard = nil
                tagEditorItemID = nil
                flippedRowID = nil
                isLifted = false
                tab = .nowPlaying
            }
            if videoStageOpen {
                // 从视频舞台/全屏一键回到卡片模式（若当前为系统全屏会一并退出）
                exitVideoStage()
            } else if full && !viewerHandledFull {
                toggleFullScreen()
            }
            if let i = queue.currentIndex, carousel.centeredIndex != i {
                carousel.jump(to: i)
                runCarousel()
            }
        }
    }

    func stepTheme(_ d: Int) {
        let all = themeOrder
        let i = all.firstIndex(of: theme) ?? 0
        let t = all[(i + d + all.count) % all.count]
        setTheme(t)
        showHUD("paintpalette", t.name)
    }

    func toggleShortcutsHelp() { withAnimation(Motion.panel) { showShortcuts.toggle() } }

    // MARK: - 播放历史（与会话队列分离）

    func notePlayed(_ item: MediaItem) {
        playHistory.record(url: item.url, title: item.title, artist: item.knownArtist)
        scheduleHistorySave()
    }

    func openPlayHistory() {
        withAnimation(Motion.tab) {
            showPlayHistory = true
            tab = .playlist
        }
    }

    func closePlayHistory() {
        withAnimation(Motion.tab) {
            showPlayHistory = false
            if queue.items.isEmpty { tab = .nowPlaying }
        }
    }

    func togglePlayHistory() {
        if showPlayHistory { closePlayHistory() } else { openPlayHistory() }
    }

    func promptClearPlayHistory() {
        guard !playHistory.items.isEmpty else { return }
        asksClearPlayHistory = true
    }

    func clearPlayHistory() {
        playHistory.clear()
        asksClearPlayHistory = false
        scheduleHistorySave()
        showHUD("clock.arrow.circlepath", "已清空播放记录")
    }

    func replayFromHistory(_ item: PlayHistoryItem) {
        let u = item.url
        if u.isFileURL && !FileManager.default.fileExists(atPath: u.path) {
            showHUD("questionmark.folder", "文件已不在原处")
            return
        }
        if let i = queue.items.firstIndex(where: { PlayHistoryBook.key(for: $0.url) == item.path }) {
            play(index: i)
            return
        }
        // 点选重播才改队列：把这一项追加到末尾并播放，不替换整个列表
        open([u], playNow: true)
    }
}

/// 简单的文字输入对话框（打开网址、跳转、预设名）。自测模式下直接返回预设答案。
@MainActor
enum Prompt {
    static func text(key: String, title: String, message: String, placeholder: String) -> String? {
        if TestHooks.active { return TestHooks.answer(key) }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        f.placeholderString = placeholder
        a.accessoryView = f
        a.addButton(withTitle: "好"); a.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"   // Esc = 取消
        a.window.initialFirstResponder = f
        let r = a.runModal()
        let s = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return r == .alertFirstButtonReturn && !s.isEmpty ? s : nil
    }

}

/// 线程安全、保持顺序的 URL 容器（拖放回调在后台线程）
final class IndexedURLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [URL?]
    init(count: Int) { slots = Array(repeating: nil, count: count) }
    func set(_ i: Int, _ u: URL) { lock.lock(); slots[i] = u; lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return slots.compactMap { $0 } }
}
