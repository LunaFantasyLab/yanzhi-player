// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import SwiftUI
import PlayerCore

/// 封面顺序：① 文件自带封面 / 同目录 cover、folder 图片 → ② 联网查官方专辑封面（MusicBrainz + Cover Art Archive，再 iTunes）
/// → ③ 都查不到、或文件里连歌手都没写，才用 10 种默认封面。联网这一步默认开，可在右键菜单和设置里关。
extension PlayerController {
    func coverQuery(_ it: MediaItem) -> CoverQuery {
        let artist = it.artist?.isEmpty == false ? it.artist : MediaItem.artistFromFilename(it.url)
        return CoverQuery(title: it.title, artist: artist, album: it.album, duration: it.duration)
    }

    /// 这首有没有文件自带（或同目录）的封面
    func hasFileCover(_ id: MediaItem.ID) -> Bool { fileCoverIDs.contains(id) }

    func lookupOnlineCoverIfNeeded(_ item: MediaItem) {
        guard onlineCoversEnabled, item.kind == .audio, !hasFileCover(item.id), !coverTried.contains(item.id) else { return }
        let it = details[item.id]?.item ?? item
        let q = coverQuery(it)
        guard q.isSearchable else {
            coverOutcome[item.id] = "noinfo"
            TestHooks.log("  封面：「\(it.title)」没有歌手信息 → 直接用默认封面，不联网")
            return
        }
        coverTried.insert(item.id)
        coverOutcome[item.id] = nil
        let t0 = Date()
        Task { [weak self] in
            let out = await CoverService.lookupShared(q)
            guard let self else { return }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            switch out {
            case .found(let data, let f, let cached):
                guard self.onlineCoversEnabled, !self.hasFileCover(item.id) else { return }
                let art = await Task.detached(priority: .userInitiated) { () -> CoverArt? in
                    guard let img = MetadataReader.decodeImage(data) else { return nil }
                    return await CoverStore.makeArtGated(cover: img, item: it, origin: "online")
                }.value
                guard let art, self.onlineCoversEnabled, !self.hasFileCover(item.id) else { return }
                self.coverInfo[item.id] = f
                self.coverOutcome[item.id] = "online"
                self.applyCover(art, for: item.id)
                TestHooks.log("  封面：「\(it.title)」\(q.artist ?? "-") / \(q.album ?? "无专辑名") → \(f.source)「\(f.album)」\(cached ? "（本地缓存）" : "")，\(ms)ms，\(f.link)")
            case .notFound(let cached):
                self.coverOutcome[item.id] = "none"
                TestHooks.log("  封面：「\(it.title)」\(q.artist ?? "-") / \(q.album ?? "无专辑名") → 没有可靠匹配（\(cached ? "缓存" : (CoverService.useITunes ? "已查 MusicBrainz、iTunes" : "已查 MusicBrainz"))，\(ms)ms），用默认封面")
            case .userDefault:
                self.coverOutcome[item.id] = "userDefault"
                TestHooks.log("  封面：「\(it.title)」本人选了默认封面")
            case .failed(let e):
                self.coverTried.remove(item.id)                     // 网络问题：下次再试
                self.coverOutcome[item.id] = "failed"
                TestHooks.log("  封面：「\(it.title)」查询失败（\(e)），先用默认封面")
            }
        }
    }

    func setOnlineCoversEnabled(_ on: Bool, quiet: Bool = false) {
        onlineCoversEnabled = on
        Prefs.set(on, "onlineCovers")
        if !quiet { showHUD("photo.on.rectangle", on ? "联网查找专辑封面：开" : "联网查找专辑封面：关（用默认封面）") }
        if on {
            coverTried.removeAll()
            if let i = queue.currentIndex { for j in max(0, i - 5)...min(queue.items.count - 1, i + 5) { lookupOnlineCoverIfNeeded(queue.items[j]) } }
        } else {
            // 当前曲目先撤，避免排队生成默认封面时界面还继续显示官方图
            let current = queue.current?.id
            let ids = Array(coverInfo.keys).sorted { a, b in (a == current ? 0 : 1) < (b == current ? 0 : 1) }
            for id in ids { revertToDefault(id) }
        }
    }
    func toggleOnlineCovers() { setOnlineCoversEnabled(!onlineCoversEnabled) }

    func setITunesCovers(_ on: Bool, quiet: Bool = false) {
        Prefs.set(on, "onlineCoversITunes")
        if on { CoverService.clearMisses(); for (id, o) in coverOutcome where o == "none" { coverTried.remove(id) } }
        iTunesCoversEnabled = on
        if !quiet { showHUD("photo.on.rectangle", on ? "也用 iTunes 补封面：开" : "也用 iTunes 补封面：关") }
        if on, onlineCoversEnabled, let i = queue.currentIndex {
            for j in max(0, i - 5)...min(queue.items.count - 1, i + 5) { lookupOnlineCoverIfNeeded(queue.items[j]) }
        }
    }

    /// 右键「重新查找封面」
    func refetchCover(index i: Int) {
        guard queue.items.indices.contains(i) else { return }
        let item = details[queue.items[i].id]?.item ?? queue.items[i]
        guard !hasFileCover(item.id) else { showHUD("photo", "这首用的是文件自带的封面"); return }
        CoverService.applyRefetchClear(coverQuery(item))
        coverTried.remove(item.id)
        if !onlineCoversEnabled { setOnlineCoversEnabled(true, quiet: true) }
        showHUD("arrow.clockwise", "重新查找封面…")
        lookupOnlineCoverIfNeeded(item)
    }

    /// 右键「改用默认封面」：记住这张专辑用默认封面（下次也不再联网查）
    func useDefaultCover(index i: Int) {
        guard queue.items.indices.contains(i) else { return }
        let item = details[queue.items[i].id]?.item ?? queue.items[i]
        CoverService.useDefault(coverQuery(item))
        coverTried.insert(item.id)
        if coverInfo[item.id] != nil { revertToDefault(item.id) }
        showHUD("square.dashed", "已改用默认封面")
    }

    private func revertToDefault(_ id: MediaItem.ID) {
        coverInfo[id] = nil
        forgetDisplayedCover(id)
        guard let it = details[id]?.item ?? queue.items.first(where: { $0.id == id }), !hasFileCover(id) else { return }
        let st = defaultStyle(for: it)
        Task { [weak self] in
            let art = await Task.detached(priority: .userInitiated) { await CoverStore.makeArtGated(cover: nil, item: it, style: st) }.value
            // coverInfo 被重新填上说明又查到了官方封面（例如重新打开自动补），这时不要再套默认图
            guard let self, self.coverInfo[id] == nil else { return }
            self.applyCover(art, for: id)
        }
    }

    /// 菜单里显示的“当前封面来自哪里”
    func coverSourceText(_ id: MediaItem.ID) -> String {
        if hasFileCover(id) { return "当前：文件自带封面" }
        if let f = coverInfo[id] { return "当前：\(f.source == "iTunes" ? "iTunes" : "MusicBrainz")「\(f.album)」" }
        return "当前：默认封面"
    }
}

extension CoverService {
    /// 同一张专辑的几首歌同时来查时只发一次请求
    private static var inflight: [String: Task<Outcome, Never>] = [:]
    static func lookupShared(_ q: CoverQuery) async -> Outcome {
        let k = CoverLookup.cacheKey(q)
        if let t = inflight[k] { return await t.value }
        let t = Task { await lookup(q) }
        inflight[k] = t
        let r = await t.value
        inflight[k] = nil
        return r
    }
}
