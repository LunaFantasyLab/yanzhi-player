// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import PlayerCore

/// 自动搜索歌词：只查 LRCLIB（https://lrclib.net）的带时间轴歌词，按歌名 + 歌手 + 时长对上才用。
/// 不查封面、不做歌词解读。查不到就安静地返回 nil。
/// 缓存放在 ~/Library/Application Support/com.tanco.glassplayer/lyrics/：
///   <key>.lrc   找到的歌词
///   <key>.none  没找到（3 天内不再重查）
/// 自测时缓存改放到本次自测的输出目录里，不碰本人的 Application Support。
@MainActor
enum LyricsService {
    static let base = "https://lrclib.net/api"
    static let negativeTTL: TimeInterval = 3 * 24 * 3600

    static var cacheDir: URL {
        let root: URL
        if TestHooks.active { root = TestHooks.outDir.appendingPathComponent("ApplicationSupport") }
        else { root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.tanco.glassplayer") }
        let u = root.appendingPathComponent("lyrics")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    enum Outcome: Sendable { case found(String, cached: Bool), notFound(cached: Bool), failed(String) }

    static func lookup(title: String, artist: String?, album: String?, duration: Double?) async -> Outcome {
        let key = LyricsLookup.cacheKey(title: title, artist: artist, duration: duration)
        let hit = cacheDir.appendingPathComponent(key + ".lrc"), miss = cacheDir.appendingPathComponent(key + ".none")
        if let t = try? String(contentsOf: hit, encoding: .utf8), !t.isEmpty { return .found(t, cached: true) }
        if let a = try? FileManager.default.attributesOfItem(atPath: miss.path), let d = a[.modificationDate] as? Date,
           Date().timeIntervalSince(d) < negativeTTL { return .notFound(cached: true) }

        let t = LyricsLookup.cleanTitle(title)
        let known = !LyricsLookup.isUnknownArtist(artist)
        var recs: [LRCLibRecord] = []
        do {
            if known {
                var q = [URLQueryItem(name: "track_name", value: t), URLQueryItem(name: "artist_name", value: artist)]
                if let album, !album.isEmpty { q.append(URLQueryItem(name: "album_name", value: album)) }
                if let d = duration, d > 0 { q.append(URLQueryItem(name: "duration", value: String(Int(d.rounded())))) }
                if let r: LRCLibRecord = try await get("get", q) { recs.append(r) }
                if LyricsLookup.pick(recs, title: t, artist: artist, duration: duration) == nil {
                    recs += (try await get("search", [URLQueryItem(name: "track_name", value: t), URLQueryItem(name: "artist_name", value: artist)]) as [LRCLibRecord]?) ?? []
                }
            } else {
                recs += (try await get("search", [URLQueryItem(name: "q", value: t)]) as [LRCLibRecord]?) ?? []
            }
        } catch {
            return .failed(error.localizedDescription)       // 网络错误不写“没找到”缓存，下次再试
        }
        if let r = LyricsLookup.pick(recs, title: t, artist: artist, duration: duration), let l = r.syncedLyrics {
            try? l.write(to: hit, atomically: true, encoding: .utf8)
            return .found(l, cached: false)
        }
        try? Data().write(to: miss)
        return .notFound(cached: false)
    }

    /// 404 → nil；其他非 200 → 抛错
    private static func get<T: Decodable>(_ path: String, _ q: [URLQueryItem]) async throws -> T? {
        var c = URLComponents(string: "\(base)/\(path)")!
        c.queryItems = q
        var r = URLRequest(url: c.url!, timeoutInterval: 10)
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        r.setValue("Liuli/\(v) (TANCO local music player for macOS)", forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await Net.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: d)
    }
}
