// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import AppKit
import SwiftUI
import PlayerCore

/// 第二轮：本地语音识别字幕、在线字幕搜索、AutoEq 耳机校正
extension PlayerController {
    // MARK: 语音识别
    var asrAvailable: Bool { WhisperJob.isAvailable }

    func generateSubtitles(language: WhisperJob.Language = .auto) {
        guard let cur = current, cur.url.isFileURL else { showHUD("captions.bubble", "只能识别本地文件"); return }
        guard asrJob == nil else { showHUD("captions.bubble", "正在识别中…"); return }
        guard WhisperJob.isAvailable else { showHUD("exclamationmark.triangle", "自动生成字幕要另装识别组件（约 550 MB），这个版本还没有提供下载"); return }
        let job = WhisperJob(media: cur.url, isVideo: isVideo, language: language)
        asrJob = job
        if TestHooks.active { job.debugDir = TestHooks.outDir; job.logger = { s in DispatchQueue.main.async { TestHooks.log(s) } } }
        withAnimation(Motion.panel) { asrProgress = 0; asrStatus = "准备中…" }
        job.onProgress = { [weak self] v, s in
            DispatchQueue.main.async { guard let self, self.asrJob === job else { return }; withAnimation(Motion.hover) { self.asrProgress = v; self.asrStatus = s } }
        }
        let t0 = Date()
        let video = isVideo
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try job.run() }
            await MainActor.run {
                guard let self else { return }
                self.asrJob = nil
                withAnimation(Motion.panel) { self.asrProgress = nil }
                switch result {
                case .success(let url):
                    let secs = Date().timeIntervalSince(t0)
                    TestHooks.log("  语音识别完成 \(String(format: "%.1f", secs)) 秒 → \(url.lastPathComponent)（清掉套话/重复 \(job.removedJunk) 条；VAD \(Runtime.vadModel != nil ? "开" : "关")）")
                    guard self.current?.url == cur.url else { return }
                    if video { self.engine.addSubtitle(url); self.refreshTracksSoon() }
                    else if let t = try? String(contentsOf: url, encoding: .utf8) { withAnimation(Motion.toggle) { self.lyrics = Lyrics.parse(t) } }
                    self.showHUD("captions.bubble.fill", video ? "字幕已生成并加载（用时 \(Int(secs)) 秒）" : "歌词已生成（用时 \(Int(secs)) 秒）")
                case .failure(let e):
                    if e is CancellationError { self.showHUD("xmark.circle", "已取消识别") }
                    else { self.showHUD("exclamationmark.triangle", e.localizedDescription); TestHooks.log("  语音识别失败：\(e.localizedDescription)") }
                }
            }
        }
    }

    func cancelASR() { asrJob?.cancel() }

    /// 打开文件时：自动挂上以前为它生成/下载过的字幕
    func attachSavedSubtitles() {
        guard isVideo || current?.kind == .video, let cur = current, cur.url.isFileURL else { return }
        let key = Runtime.key(for: cur.url)
        let dir = Runtime.root.appendingPathComponent("subtitles")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files.sorted() where f.hasPrefix(key + ".") { engine.command(["sub-add", dir.appendingPathComponent(f).path, "auto"]) }
        refreshTracksSoon()
    }

    func savedASRLyrics(for item: MediaItem) -> Lyrics? {
        guard item.kind == .audio, item.url.isFileURL else { return nil }
        let f = Runtime.root.appendingPathComponent("lyrics/\(Runtime.key(for: item.url)).whisper.lrc")
        guard let t = try? String(contentsOf: f, encoding: .utf8) else { return nil }
        return Lyrics.parse(t)
    }

    // MARK: 在线字幕
    func toggleSubtitlePanel() {
        withAnimation(Motion.panel) { subtitlePanelOpen.toggle() }
        if subtitlePanelOpen, subtitleQuery.isEmpty, let cur = current { subtitleQuery = SubtitleSearch.cleanQuery(fileName: cur.url.lastPathComponent) }
        if subtitlePanelOpen, subtitleResults.isEmpty { searchSubtitles() }
    }

    func searchSubtitles() {
        guard let cur = current else { return }
        subtitleSearching = true; subtitleMessage = "正在搜索…"
        let q = subtitleQuery
        Task { [weak self] in
            let (res, err) = await SubtitleService.search(media: cur.url, query: q)
            guard let self else { return }
            self.subtitleSearching = false
            withAnimation(Motion.toggle) { self.subtitleResults = res }
            self.subtitleMessage = res.isEmpty ? (err.map { Net.isOffline ? "现在没有联网，联网后再搜" : "搜索失败：\($0)" } ?? "没有找到字幕，可以换个关键词或去字幕网站找") : "找到 \(res.count) 条（按指纹匹配、下载量排序）"
            TestHooks.log("  字幕搜索「\(q)」：\(res.count) 条" + (err.map { "，错误 \($0)" } ?? ""))
        }
    }

    func downloadSubtitle(_ r: SubtitleSearch.Result) {
        guard let cur = current else { return }
        subtitleMessage = "正在下载 \(r.fileName)…"
        Task { [weak self] in
            do {
                let f = try await SubtitleService.download(r, for: cur.url)
                guard let self else { return }
                if self.current?.url == cur.url {
                    if self.isVideo { self.engine.addSubtitle(f); self.refreshTracksSoon() }
                    else if let t = try? String(contentsOf: f, encoding: .utf8) { self.lyrics = Lyrics.parse(SRT.toLRC(t)) }
                }
                self.subtitleMessage = "已加载：\(r.fileName)"
                self.showHUD("captions.bubble.fill", "已加载字幕：\(r.language)")
                TestHooks.log("  字幕下载 \(r.fileName) → \(f.lastPathComponent)")
            } catch {
                self?.subtitleMessage = Net.isOffline ? "现在没有联网，联网后再下载" : "下载失败：\(error.localizedDescription)"
            }
        }
    }

    func openSubtitleSite(_ url: URL) {
        // 自测时只记录、不真的打开浏览器
        if TestHooks.active { lastOpenedURL = url; showHUD("safari", "自测：未打开 \(url.host ?? "")"); TestHooks.log("  打开网址（自测拦截）：\(url.absoluteString)"); return }
        NSWorkspace.shared.open(url)
    }

    // MARK: AutoEq
    func toggleAutoEqPanel() {
        withAnimation(Motion.panel) { autoEqPanelOpen.toggle() }
        if autoEqPanelOpen, autoEqIndex.isEmpty { loadAutoEqIndex() }
    }

    func loadAutoEqIndex(refresh: Bool = false) {
        guard !autoEqLoading else { return }
        autoEqLoading = true; autoEqMessage = "正在读取耳机列表…"
        Task { [weak self] in
            do {
                let idx = try await AutoEqService.loadIndex(refresh: refresh)
                self?.autoEqIndex = idx
                self?.autoEqBrandIndex = AutoEq.brandIndex(idx)
                self?.autoEqMessage = "共 \(idx.count) 条测量（\(AutoEqService.indexOrigin)，离线可用；AutoEq 项目，MIT 许可）"
            } catch {
                if refresh { self?.autoEqMessage = Net.isOffline ? "现在没有联网，列表没更新（原来的照样能用）" : "更新失败：\(error.localizedDescription)" }
                else { self?.autoEqMessage = "本机没有耳机列表，点「更新列表」联网取一次" }
            }
            self?.autoEqLoading = false
        }
    }

    /// 品牌目录（按首字母分组，大牌在前）；列表读进来后算一次
    func autoEqBrands() -> AutoEq.BrandIndex? { autoEqBrandIndex }
    func openAutoEqBrand(_ name: String) {
        autoEqBrandModels = AutoEq.models(autoEqIndex, brand: name)
        withAnimation(Motion.panel) { autoEqBrand = name }
    }
    func closeAutoEqBrand() { guard autoEqBrand != nil else { return }; withAnimation(Motion.panel) { autoEqBrand = nil } }

    func selectAutoEq(_ e: AutoEq.Entry) {
        autoEqMessage = "正在下载「\(e.name)」的校正曲线…"
        Task { [weak self] in
            do {
                let c = try await AutoEqService.curve(for: e)
                guard let self else { return }
                self.autoEqEntry = e; self.autoEqCurve = c
                self.autoEqEnabled = true
                self.autoEqRecent = [e] + self.autoEqRecent.filter { $0 != e }.prefix(5)
                self.persistAutoEq()
                self.applyAudioFilters()
                self.autoEqMessage = "已校正：\(e.name)（\(e.displaySource)）\(c.maxGain > 0.05 ? String(format: "，预增益 -%.1f dB 防削波", c.maxGain) : "")"
                self.showHUD("headphones", "耳机校正：\(e.name)")
                TestHooks.log("  AutoEq 选中 \(e.name)：\(c.points.count) 点，最大 \(c.maxGain) dB；af 含校正：\((self.engine.getString("af") ?? "").contains(AutoEq.label))")
            } catch { self?.autoEqMessage = Net.isOffline ? "现在没有联网：这副耳机的曲线还没下载过，联网后再选（用过的耳机离线也能用）" : "下载失败：\(error.localizedDescription)" }
        }
    }

    func setAutoEqEnabled(_ on: Bool) {
        guard autoEqCurve != nil else { toggleAutoEqPanel(); return }
        autoEqEnabled = on; persistAutoEq(); applyAudioFilters()
        showHUD("headphones", on ? "耳机校正：开（\(autoEqEntry?.name ?? "")）" : "耳机校正：关")
    }

    func setAutoEqStrength(_ v: Double) {
        autoEqStrength = (min(max(v, 0), 1) * 20).rounded() / 20
        persistAutoEq()
        scheduleAutoEqApply()
    }

    private func scheduleAutoEqApply() {
        autoEqApplyWork?.cancel()
        autoEqApplyWork = after(0.25) { [weak self] in self?.applyAudioFilters() }
    }

    func persistAutoEq() {
        Prefs.set(autoEqEnabled, "autoEqEnabled"); Prefs.set(autoEqStrength, "autoEqStrength")
        Prefs.set(autoEqEntry.flatMap { try? JSONEncoder().encode($0) }, "autoEqEntry")
        Prefs.set(autoEqCurve.flatMap { try? JSONEncoder().encode($0) }, "autoEqCurve")
        Prefs.set(try? JSONEncoder().encode(autoEqRecent), "autoEqRecent")
    }
}

/// SRT → LRC（音频用：在线下载的字幕当歌词显示）
enum SRT {
    static func toLRC(_ srt: String) -> String {
        var out: [String] = []
        let blocks = srt.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n")
        let re = try! NSRegularExpression(pattern: #"(\d+):(\d+):(\d+)[,.](\d+)\s*-->"#)
        for b in blocks {
            let lines = b.split(separator: "\n").map(String.init)
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let ns = lines[ti] as NSString
            guard let m = re.firstMatch(in: lines[ti], range: NSRange(location: 0, length: ns.length)) else { continue }
            let h = Int(ns.substring(with: m.range(at: 1)))!, mi = Int(ns.substring(with: m.range(at: 2)))!, s = Int(ns.substring(with: m.range(at: 3)))!
            let ms = Int(ns.substring(with: m.range(at: 4)).prefix(2)) ?? 0
            let text = lines[(ti + 1)...].joined(separator: " ").replacingOccurrences(of: #"<[^>]+>|\{[^}]+\}"#, with: "", options: .regularExpression)
            out.append(String(format: "[%02d:%02d.%02d]%@", h * 60 + mi, s, ms, text))
        }
        return out.joined(separator: "\n")
    }
}
