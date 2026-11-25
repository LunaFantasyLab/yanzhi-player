// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import PlayerCore

/// 联网补官方专辑封面（只在文件自带封面、同目录 cover/folder 图片都没有时才查）。
/// 顺序：MusicBrainz 找到是哪张专辑 → Cover Art Archive 取这张专辑的正面封面；本人打开「也用 iTunes 补」后，查不到再用 iTunes Search API。
/// 只显示，不写回音乐文件。缓存放在 ~/Library/Application Support/com.tanco.glassplayer/covers/：
///   <key>.jpg    找到的封面（原图字节）     <key>.json  出处（来源、专辑名、链接）
///   <key>.none   没找到（3 天内不再重查）   <key>.default  本人选了「改用默认封面」
/// 自测时缓存改放到本次自测的输出目录里，不碰本人的 Application Support。
@MainActor
enum CoverService {
    static let negativeTTL: TimeInterval = 3 * 24 * 3600

    struct Found: Codable, Sendable {
        var source: String          // "MusicBrainz / Cover Art Archive" 或 "iTunes"
        var album: String
        var link: String
        /// 按“要最大尺寸”下载的（2026-11-20 起）。旧缓存没有这个标记 → 有机会时重新下载高清版
        var hiRes: Bool? = nil
    }
    enum Outcome: Sendable { case found(Data, Found, cached: Bool), notFound(cached: Bool), userDefault, failed(String) }

    static var cacheDir: URL {
        let root: URL
        if TestHooks.active { root = TestHooks.outDir.appendingPathComponent("ApplicationSupport") }
        else { root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.tanco.glassplayer") }
        let u = root.appendingPathComponent("covers")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func file(_ key: String, _ ext: String) -> URL { cacheDir.appendingPathComponent("\(key).\(ext)") }

    static func useDefault(_ q: CoverQuery) {
        let k = CoverLookup.cacheKey(q)
        try? Data().write(to: file(k, "default"))
    }
    static func hasUserDefault(_ q: CoverQuery) -> Bool {
        FileManager.default.fileExists(atPath: file(CoverLookup.cacheKey(q), "default").path)
    }
    /// 去掉「改用默认封面」标记，保留已查到的官方 jpg/json。
    static func clearUserDefault(_ q: CoverQuery) {
        try? FileManager.default.removeItem(at: file(CoverLookup.cacheKey(q), "default"))
    }
    /// 「重新查找封面」：清掉这张专辑的缓存和“改用默认”标记
    static func forget(_ q: CoverQuery) {
        let k = CoverLookup.cacheKey(q)
        for e in ["jpg", "json", "none", "default"] { try? FileManager.default.removeItem(at: file(k, e)) }
    }
    static func applyRefetchClear(_ q: CoverQuery) {
        switch CoverRefetch.cacheClear(userDefaultExists: hasUserDefault(q)) {
        case .userDefaultOnly: clearUserDefault(q)
        case .all: forget(q)
        }
    }

    /// iTunes 作为第二来源默认不用：苹果条款只允许把专辑图用于推广 iTunes 商店内容（要挨着商店徽标、不能单独作娱乐用途），
    /// 本地播放器显示封面不在它的许可范围内。本人在设置里打开后才用。
    static var useITunes: Bool { Prefs.bool("onlineCoversITunes") }

    /// 打开 iTunes 补充后，之前只查过 MusicBrainz 的“没找到”要重新查
    static func clearMisses() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path)) ?? []
        for f in files where f.hasSuffix(".none") { try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(f)) }
    }

    static func lookup(_ q: CoverQuery) async -> Outcome {
        let k = CoverLookup.cacheKey(q)
        if FileManager.default.fileExists(atPath: file(k, "default").path) { return .userDefault }
        var stale: (Data, Found)?
        if let d = try? Data(contentsOf: file(k, "jpg")), !d.isEmpty,
           let j = try? Data(contentsOf: file(k, "json")), let f = try? JSONDecoder().decode(Found.self, from: j) {
            if f.hiRes == true || (MetadataReader.pixelSize(d).map { max($0.width, $0.height) >= CGFloat(CoverStore.blurSide) } ?? false) { return .found(d, f, cached: true) }
            stale = (d, f)          // 以前下的小图（600 / 500 像素）：先去拿高清版，拿不到再用它
        }
        if let (d, f) = stale {
            if let hd = (try? await upgradeStale(q, f)) ?? nil { save(k, hd.0, hd.1); return .found(hd.0, hd.1, cached: false) }
            return .found(d, f, cached: true)
        }
        if let a = try? FileManager.default.attributesOfItem(atPath: file(k, "none").path), let d = a[.modificationDate] as? Date,
           Date().timeIntervalSince(d) < negativeTTL { return .notFound(cached: true) }
        guard q.isSearchable else { return .notFound(cached: false) }

        var networkError: String?
        // 1) MusicBrainz + Cover Art Archive
        do {
            if let (d, f) = try await musicBrainz(q) { save(k, d, f); return .found(d, f, cached: false) }
        } catch { networkError = "MusicBrainz：\(error.localizedDescription)" }
        // 2) iTunes Search API（本人打开后才用）
        if useITunes {
            do {
                if let (d, f) = try await iTunes(q) { save(k, d, f); return .found(d, f, cached: false) }
            } catch { networkError = (networkError.map { $0 + "；" } ?? "") + "iTunes：\(error.localizedDescription)" }
        }
        if let e = networkError { return .failed(e) }               // 有网络问题时不写“没找到”，下次再试
        try? Data().write(to: file(k, "none"))
        return .notFound(cached: false)
    }

    /// 旧缓存是小图：按原来的来源再拿一次最大尺寸
    private static func upgradeStale(_ q: CoverQuery, _ f: Found) async throws -> (Data, Found)? {
        guard q.isSearchable else { return nil }
        if f.source.hasPrefix("MusicBrainz") { return try await musicBrainz(q) }
        if f.source == "iTunes", useITunes { return try await iTunes(q) }
        return nil
    }

    private static func save(_ k: String, _ d: Data, _ f: Found) {
        try? d.write(to: file(k, "jpg"))
        if let j = try? JSONEncoder().encode(f) { try? j.write(to: file(k, "json")) }
    }

    // MARK: MusicBrainz（要求带可识别的 User-Agent、每秒不超过 1 次请求）
    static var lastMB: Date = .distantPast
    private static func mbGet<T: Decodable>(_ path: String, _ query: String, limit: Int = 25) async throws -> T {
        // 先占一个时间槽再等（主线程上读写，不会两个请求抢到同一个槽）
        let slot = max(Date(), lastMB.addingTimeInterval(1.1))
        lastMB = slot
        let wait = slot.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
        var c = URLComponents(string: "https://musicbrainz.org/ws/2/\(path)")!
        c.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: String(limit))]
        var r = try? await fetch(c.url!)
        // 服务器忙（503 / 429）或偶发网络 / 网关错误：等一下再试，最多再试两次（2 秒、4 秒）
        for wait in [2.0, 4.0] where !Net.isOffline && (r == nil || r!.1 >= 500 || r!.1 == 429 || r!.1 == 0) {   // 没网就不重试
            lastMB = Date().addingTimeInterval(wait); try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
            r = try? await fetch(c.url!)
        }
        guard r != nil else { throw URLError(.cannotConnectToHost) }
        let (d, code) = r!
        guard code == 200 else { throw NSError(domain: "MusicBrainz", code: code, userInfo: [NSLocalizedDescriptionKey: "MusicBrainz 返回 HTTP \(code)"]) }
        return try JSONDecoder().decode(T.self, from: d)
    }
    private static func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "") }

    private static func musicBrainz(_ q: CoverQuery) async throws -> (Data, Found)? {
        var groups: [(String, String)] = []           // (release-group id, 专辑名)
        let artist = esc(q.artist!), title = esc(LyricsLookup.cleanTitle(q.title))
        if q.hasAlbum, let album = q.album {
            let r: MBReleaseGroupSearch = try await mbGet("release-group", "releasegroup:\"\(esc(album))\" AND artist:\"\(artist)\"")
            let ids = CoverLookup.pickReleaseGroups(r.releaseGroups ?? [], query: q)
            groups = ids.map { id in (id, r.releaseGroups?.first { $0.id == id }?.title ?? album) }
        }
        if groups.isEmpty {
            let r: MBRecordingSearch = try await mbGet("recording", "recording:\"\(title)\" AND artist:\"\(artist)\"", limit: 100)   // 没有专辑名时多看一些版本，只认时长对得上的正式专辑
            let ids = CoverLookup.pickFromRecordings(r.recordings ?? [], query: q)
            let titles = Dictionary((r.recordings ?? []).flatMap { $0.releases ?? [] }.compactMap { rel in rel.releaseGroup.map { ($0.id, $0.title ?? rel.title) } }, uniquingKeysWith: { a, _ in a })
            groups = ids.map { ($0, titles[$0] ?? "") }
        }
        for (id, name) in groups.prefix(3) {
            // 要原图（front）；原图太大或取不到时退到 1200 的官方缩略图
            for variant in ["front", "front-1200"] {
                let u = URL(string: "https://coverartarchive.org/release-group/\(id)/\(variant)")!
                var (d, code) = (try? await fetch(u, timeout: 30)) ?? (Data(), 0)
                if code == 0 || code >= 500 { try? await Task.sleep(nanoseconds: 1_500_000_000); (d, code) = (try? await fetch(u, timeout: 30)) ?? (Data(), 0) }   // archive.org 偶发错误：再试一次
                if code == 404 { break }                                   // 这个专辑组没有封面
                if code == 200, d.count > 1000, d.count < 60_000_000, MetadataReader.decodeImage(d) != nil {
                    return (d, Found(source: "MusicBrainz / Cover Art Archive", album: name, link: "https://musicbrainz.org/release-group/\(id)", hiRes: true))
                }
            }
        }
        return nil
    }

    // MARK: iTunes Search API（公开接口，无需密钥；苹果建议每分钟约 20 次以内）
    static func iTunes(_ q: CoverQuery) async throws -> (Data, Found)? {
        let term = "\(q.artist!) \(LyricsLookup.cleanTitle(q.title))"
        for country in CoverLookup.iTunesCountries(for: q) {
            var c = URLComponents(string: "https://itunes.apple.com/search")!
            c.queryItems = [URLQueryItem(name: "term", value: term), URLQueryItem(name: "entity", value: "song"),
                            URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "country", value: country)]
            let (d, code) = try await fetch(c.url!)
            guard code == 200 else { throw URLError(.badServerResponse) }
            let r = try JSONDecoder().decode(ITunesSearch.self, from: d)
            if let t = CoverLookup.pickITunes(r.results ?? [], query: q), let small = t.artworkUrl100, let u = URL(string: CoverLookup.largeArtwork(small)) {
                let (img, c2) = try await fetch(u, timeout: 15)
                if c2 == 200, MetadataReader.decodeImage(img) != nil {
                    let link = t.collectionId.map { "https://music.apple.com/\(country)/album/\($0)" } ?? "https://itunes.apple.com"
                    return (img, Found(source: "iTunes", album: t.collectionName ?? "", link: link, hiRes: true))
                }
            }
        }
        return nil
    }

    private static func fetch(_ u: URL, timeout: TimeInterval = 10) async throws -> (Data, Int) {
        var r = URLRequest(url: u, timeoutInterval: timeout)
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        r.setValue("Liuli/\(v) (TANCO local music player for macOS)", forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await Net.data(for: r)
        return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
