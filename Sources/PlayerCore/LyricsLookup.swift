// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// LRCLIB（https://lrclib.net，公开歌词库，歌词数据按其站点说明公开提供）返回的一条记录。
public struct LRCLibRecord: Decodable, Sendable, Equatable {
    public var id: Int
    public var trackName: String?
    public var artistName: String?
    public var albumName: String?
    public var duration: Double?
    public var instrumental: Bool?
    public var syncedLyrics: String?
    public init(id: Int, trackName: String?, artistName: String?, albumName: String? = nil, duration: Double?, instrumental: Bool? = false, syncedLyrics: String?) {
        self.id = id; self.trackName = trackName; self.artistName = artistName; self.albumName = albumName
        self.duration = duration; self.instrumental = instrumental; self.syncedLyrics = syncedLyrics
    }
}

/// 只做“按歌名、歌手、时长找带时间轴的歌词”：挑选规则全在这里，便于单元测试。
public enum LyricsLookup {
    /// 时长差超过这个秒数就不认（防止同名不同版本对不上时间轴）
    public static let durationTolerance = 3.0

    /// 去掉大小写、空白、标点、括号里的注释（Live / Remaster / feat.）
    public static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        for (o, c) in [("(", ")"), ("（", "）"), ("[", "]"), ("【", "】")] {
            while let a = t.range(of: o), let b = t.range(of: c, range: a.upperBound..<t.endIndex) { t.removeSubrange(a.lowerBound..<b.upperBound) }
        }
        if let r = t.range(of: " feat") { t = String(t[..<r.lowerBound]) }
        return String(t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// 文件名里常见的“03. ”“03 - ”曲号前缀
    public static func cleanTitle(_ t: String) -> String {
        var s = t.trimmingCharacters(in: .whitespaces)
        if let r = s.range(of: #"^\d{1,3}\s*[.\-_ 、]\s*"#, options: .regularExpression), r.upperBound < s.endIndex { s.removeSubrange(r) }
        return s
    }

    public static func isUnknownArtist(_ a: String?) -> Bool {
        guard let a, !a.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        return ["未知艺人", "unknown artist", "unknown", "群星"].contains(a.lowercased())
    }

    /// 从候选里挑一条：必须有时间轴歌词、不是纯音乐；歌名要对上；知道歌手时歌手要对上；
    /// 知道时长时差 ≤ 3 秒（不知道歌手时更严：≤ 2 秒）。多条都行时取时长最接近的。
    public static func pick(_ recs: [LRCLibRecord], title: String, artist: String?, duration: Double?) -> LRCLibRecord? {
        let nt = normalize(cleanTitle(title))
        guard !nt.isEmpty else { return nil }
        let knownArtist = !isUnknownArtist(artist)
        let na = knownArtist ? normalize(artist!) : ""
        let tol = knownArtist ? durationTolerance : 2.0
        var best: (LRCLibRecord, Double)?
        for r in recs {
            guard r.instrumental != true, let l = r.syncedLyrics, l.contains("[") else { continue }
            let rt = normalize(r.trackName ?? "")
            guard !rt.isEmpty, rt == nt || rt.contains(nt) || nt.contains(rt) else { continue }
            if knownArtist {
                let ra = normalize(r.artistName ?? "")
                guard !ra.isEmpty, ra.contains(na) || na.contains(ra) else { continue }
            }
            var dd = 0.0
            if let d = duration, d > 0 {
                guard let rd = r.duration, rd > 0 else { continue }
                dd = abs(rd - d)
                guard dd <= tol else { continue }
            } else if !knownArtist { continue }        // 歌手、时长都不知道：宁可不显示
            let score = dd + (rt == nt ? 0 : 0.5)
            if best == nil || score < best!.1 { best = (r, score) }
        }
        return best?.0
    }

    /// 缓存键：歌名 + 歌手 + 时长（取整秒）
    public static func cacheKey(title: String, artist: String?, duration: Double?) -> String {
        let s = normalize(cleanTitle(title)) + "|" + (isUnknownArtist(artist) ? "" : normalize(artist!)) + "|" + String(Int((duration ?? 0).rounded()))
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }
}
