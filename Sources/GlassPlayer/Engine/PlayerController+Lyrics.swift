// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import SwiftUI
import PlayerCore

/// 自动搜索歌词（LRCLIB）。默认关；打开后对当前音频曲目：本地没有歌词（同名 .lrc、内嵌、转写）时才联网查。
/// 查不到、网络不通都不弹提示，界面上也不出现歌词条。
extension PlayerController {
    func toggleLyrics() { setLyricsEnabled(!lyricsEnabled) }

    func setLyricsEnabled(_ on: Bool, quiet: Bool = false) {
        withAnimation(Motion.panel) { lyricsEnabled = on }
        Prefs.set(on, "lyricsAutoSearch")
        if !quiet { showHUD("quote.bubble", on ? "歌词：开（找不到就不显示）" : "歌词：关") }
        if on { lookupOnlineLyricsIfNeeded() }
    }

    /// 歌词条要不要出现：开关开着、是音频、有带时间轴的歌词
    var showsLyricsStrip: Bool {
        lyricsEnabled && !isVideo && current?.kind == .audio && (lyrics?.isSynced ?? false) && !(lyrics?.lines.isEmpty ?? true)
    }

    func lookupOnlineLyricsIfNeeded() {
        guard lyricsEnabled, let cur = current, cur.kind == .audio, !isVideo else { return }
        if let l = lyrics, l.isSynced { return }                       // 本地已有带时间轴的歌词
        if let l = onlineLyrics[cur.id] { withAnimation(Motion.toggle) { lyrics = l }; return }
        guard !lyricsTried.contains(cur.id) else { return }
        let dur = (duration ?? 0) > 0 ? duration : cur.duration
        guard let d = dur, d > 0 else { return }                       // 时长还没读到：等元数据读完再查
        lyricsTried.insert(cur.id)
        let title = cur.title, artist = cur.artist?.isEmpty == false ? cur.artist : MediaItem.artistFromFilename(cur.url), album = cur.album
        lyricsSearching = true
        let t0 = Date()
        Task { [weak self] in
            let out = await LyricsService.lookup(title: title, artist: artist, album: album, duration: d)
            guard let self else { return }
            self.lyricsSearching = false
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            switch out {
            case .found(let text, let cached):
                let l = Lyrics.parse(text)
                guard l.isSynced, !l.lines.isEmpty else { return }
                self.onlineLyrics[cur.id] = l
                TestHooks.log("  歌词：「\(title)」\(artist ?? "-") \(Int(d)) 秒 → 找到 \(l.lines.count) 行（LRCLIB\(cached ? "，本地缓存" : "")，\(ms)ms）")
                if self.current?.id == cur.id, !(self.lyrics?.isSynced ?? false) {
                    self.lyricsSource = "LRCLIB"
                    withAnimation(Motion.panel) { self.lyrics = l }
                }
            case .notFound(let cached):
                TestHooks.log("  歌词：「\(title)」\(artist ?? "-") → 没找到（\(cached ? "缓存" : "LRCLIB")，\(ms)ms），不显示")
            case .failed(let e):
                self.lyricsTried.remove(cur.id)                       // 网络问题：下次切回这首再试
                TestHooks.log("  歌词：「\(title)」查询失败（\(e)），不显示")
            }
        }
    }
}
