// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

// 联网找官方专辑封面：MusicBrainz（找到是哪张专辑）+ Cover Art Archive（取这张专辑的封面），
// 查不到再用 iTunes Search API。所有“认不认”的规则都在这里，便于单元测试。原则：宁可查不到，也不要配错。

/// MusicBrainz 搜索结果里我们关心的部分
public struct MBArtistCredit: Decodable, Sendable {
    public struct Artist: Decodable, Sendable {
        public struct Alias: Decodable, Sendable { public var name: String }
        public var name: String
        public var aliases: [Alias]?
    }
    public var name: String
    public var artist: Artist?
    public init(name: String) { self.name = name; self.artist = nil }
}
public struct MBReleaseGroupRef: Decodable, Sendable {
    public var id: String
    public var title: String?
    public var primaryType: String?
    public var secondaryTypes: [String]?
    enum CodingKeys: String, CodingKey { case id, title; case primaryType = "primary-type"; case secondaryTypes = "secondary-types" }
    public init(id: String, title: String?, primaryType: String?, secondaryTypes: [String]? = nil) {
        self.id = id; self.title = title; self.primaryType = primaryType; self.secondaryTypes = secondaryTypes
    }
}
public struct MBRelease: Decodable, Sendable {
    public var id: String
    public var title: String
    public var status: String?
    public var date: String?
    public var releaseGroup: MBReleaseGroupRef?
    enum CodingKeys: String, CodingKey { case id, title, status, date; case releaseGroup = "release-group" }
    public init(id: String, title: String, status: String?, date: String? = nil, releaseGroup: MBReleaseGroupRef?) {
        self.id = id; self.title = title; self.status = status; self.date = date; self.releaseGroup = releaseGroup
    }
}
public struct MBRecording: Decodable, Sendable {
    public var title: String
    public var length: Int?
    public var artistCredit: [MBArtistCredit]?
    public var releases: [MBRelease]?
    enum CodingKeys: String, CodingKey { case title, length, releases; case artistCredit = "artist-credit" }
    public init(title: String, length: Int?, artistCredit: [MBArtistCredit]?, releases: [MBRelease]?) {
        self.title = title; self.length = length; self.artistCredit = artistCredit; self.releases = releases
    }
}
public struct MBReleaseGroup: Decodable, Sendable {
    public var id: String
    public var title: String
    public var primaryType: String?
    public var secondaryTypes: [String]?
    public var artistCredit: [MBArtistCredit]?
    enum CodingKeys: String, CodingKey { case id, title; case primaryType = "primary-type"; case secondaryTypes = "secondary-types"; case artistCredit = "artist-credit" }
    public init(id: String, title: String, primaryType: String?, secondaryTypes: [String]? = nil, artistCredit: [MBArtistCredit]?) {
        self.id = id; self.title = title; self.primaryType = primaryType; self.secondaryTypes = secondaryTypes; self.artistCredit = artistCredit
    }
}
public struct MBRecordingSearch: Decodable, Sendable { public var recordings: [MBRecording]? }
public struct MBReleaseGroupSearch: Decodable, Sendable {
    public var releaseGroups: [MBReleaseGroup]?
    enum CodingKeys: String, CodingKey { case releaseGroups = "release-groups" }
}

/// iTunes Search API 的一条歌曲结果
public struct ITunesTrack: Decodable, Sendable {
    public var trackName: String?
    public var artistName: String?
    public var collectionName: String?
    public var collectionArtistName: String?
    public var trackTimeMillis: Int?
    public var artworkUrl100: String?
    public var collectionId: Int?
    public init(trackName: String?, artistName: String?, collectionName: String?, trackTimeMillis: Int?, artworkUrl100: String?, collectionId: Int? = nil) {
        self.trackName = trackName; self.artistName = artistName; self.collectionName = collectionName
        self.trackTimeMillis = trackTimeMillis; self.artworkUrl100 = artworkUrl100; self.collectionId = collectionId
    }
}
public struct ITunesSearch: Decodable, Sendable { public var results: [ITunesTrack]? }

/// 一次查找要用的信息（全部来自文件标签 / 文件名）
public struct CoverQuery: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: Double?
    public init(title: String, artist: String?, album: String?, duration: Double?) {
        self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
    /// 没写歌手 = 文件里几乎没有信息 → 不联网，直接用默认封面
    public var isSearchable: Bool { !LyricsLookup.isUnknownArtist(artist) && !CoverLookup.fold(LyricsLookup.cleanTitle(title)).isEmpty }
    public var hasAlbum: Bool { album.map { !CoverLookup.fold($0).isEmpty } ?? false }
}

public enum CoverLookup {
    public static let durationTolerance = 3.0

    /// 比较用：繁体转简体、全角转半角、去大小写空白标点和括号里的注释
    public static func fold(_ s: String) -> String {
        var t = s.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? s
        t = t.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? t
        t = t.replacingOccurrences(of: " - Single", with: "").replacingOccurrences(of: " - EP", with: "")
        var n = LyricsLookup.normalize(t)
        if n.hasPrefix("the") && n.count > 6 { n.removeFirst(3) }
        return n
    }

    /// 歌名 / 专辑名里有这些字样而查询里没有 → 是别的版本（现场、混音、伴奏…），不认
    static let versionWords = ["live", "remix", "mix)", "demo", "acoustic", "instrumental", "karaoke", "inst.", "cover", "伴奏", "现场", "現場", "演唱会", "演唱會", "钢琴", "鋼琴", "版)", "版）", "remaster"]
    public static func isOtherVersion(_ candidate: String, of query: String) -> Bool {
        let c = candidate.lowercased(), q = query.lowercased()
        return versionWords.contains { c.contains($0) && !q.contains($0) }
    }

    static func artistNames(_ credits: [MBArtistCredit]?) -> [String] {
        guard let credits else { return [] }
        var out = [credits.map(\.name).joined(separator: " ")]
        for c in credits {
            out.append(c.name)
            if let a = c.artist { out.append(a.name); out += (a.aliases ?? []).map(\.name) }
        }
        return out.map(fold).filter { !$0.isEmpty }
    }
    /// 歌手要对上：任何一个名字（含别名）折叠后相等，或者一方以另一方开头（“A feat. B”“A & B”）
    public static func artistMatches(_ names: [String], _ artist: String) -> Bool {
        let a = fold(artist)
        guard !a.isEmpty else { return false }
        return names.contains { $0 == a || ($0.count >= 2 && a.count >= 2 && ($0.hasPrefix(a) || a.hasPrefix($0))) }
    }
    public static func albumMatches(_ candidate: String, _ album: String) -> Bool {
        let c = fold(candidate), a = fold(album)
        guard !c.isEmpty, !a.isEmpty else { return false }
        return c == a
    }

    /// 专辑已知：从 MusicBrainz 专辑（release-group）搜索结果里挑名字和歌手都对上的，按可信度排序
    public static func pickReleaseGroups(_ groups: [MBReleaseGroup], query q: CoverQuery) -> [String] {
        guard q.isSearchable, let album = q.album, q.hasAlbum else { return [] }
        return groups.filter { g in
            albumMatches(g.title, album) && artistMatches(artistNames(g.artistCredit), q.artist!) && !isOtherVersion(g.title, of: album)
        }
        .sorted { score($0.primaryType, $0.secondaryTypes) > score($1.primaryType, $1.secondaryTypes) }
        .map(\.id)
    }

    static func score(_ primary: String?, _ secondary: [String]?) -> Int {
        var s = 0
        if primary == "Album" { s += 3 } else if primary == "EP" || primary == "Single" { s += 1 }
        if (secondary ?? []).isEmpty { s += 2 }
        return s
    }

    /// 从录音搜索结果里挑专辑：歌名、歌手必须对上，不能是别的版本；
    /// 专辑已知 → 只认名字对上的专辑；专辑未知 → 时长必须对上（±3 秒），且只认正式发行、非合辑非现场的专辑 / 单曲 / EP，取出现次数最多的那张
    public static func pickFromRecordings(_ recs: [MBRecording], query q: CoverQuery) -> [String] {
        guard q.isSearchable else { return [] }
        let t = fold(LyricsLookup.cleanTitle(q.title))
        var counts: [String: (Int, Int)] = [:]      // rgid → (次数, 类型分)
        for r in recs {
            guard fold(r.title) == t, !isOtherVersion(r.title, of: q.title), artistMatches(artistNames(r.artistCredit), q.artist!) else { continue }
            if let d = q.duration, d > 0, let l = r.length {
                guard abs(Double(l) / 1000 - d) <= durationTolerance else { continue }
            } else if !q.hasAlbum { continue }       // 不知道专辑时，时长是必须的
            for rel in r.releases ?? [] {
                guard let g = rel.releaseGroup else { continue }
                if let album = q.album, q.hasAlbum {
                    guard albumMatches(rel.title, album) || albumMatches(g.title ?? "", album) else { continue }
                } else {
                    guard rel.status == "Official", (g.secondaryTypes ?? []).isEmpty, ["Album", "Single", "EP"].contains(g.primaryType ?? ""),
                          !isOtherVersion(rel.title, of: q.title) else { continue }
                }
                let c = counts[g.id] ?? (0, score(g.primaryType, g.secondaryTypes))
                counts[g.id] = (c.0 + 1, c.1)
            }
        }
        return counts.sorted { ($0.value.1, $0.value.0) > ($1.value.1, $1.value.0) }.map(\.key)
    }

    /// iTunes：歌名、歌手必须对上，不能是别的版本；专辑已知时专辑也要对上；专辑未知时时长要对上（±2 秒）
    public static func pickITunes(_ tracks: [ITunesTrack], query q: CoverQuery) -> ITunesTrack? {
        guard q.isSearchable else { return nil }
        let t = fold(LyricsLookup.cleanTitle(q.title))
        var best: (ITunesTrack, Double)?
        for r in tracks {
            guard let name = r.trackName, fold(name) == t, !isOtherVersion(name, of: q.title),
                  artistMatches([fold(r.artistName ?? ""), fold(r.collectionArtistName ?? "")].filter { !$0.isEmpty }, q.artist!),
                  r.artworkUrl100 != nil else { continue }
            let coll = r.collectionName ?? ""
            var dd = 0.0
            if let d = q.duration, d > 0, let ms = r.trackTimeMillis { dd = abs(Double(ms) / 1000 - d) }
            if let album = q.album, q.hasAlbum {
                guard albumMatches(stripEdition(coll), stripEdition(album)) else { continue }
                if q.duration != nil && r.trackTimeMillis != nil { guard dd <= durationTolerance else { continue } }
            } else {
                guard let d = q.duration, d > 0, r.trackTimeMillis != nil, dd <= 2.0, !isOtherVersion(coll, of: q.title) else { continue }
            }
            // 同一张专辑的豪华版 / 普通版都对得上时，优先名字完全一样的
            let s = dd + (q.album.map { fold(coll) == fold($0) ? 0 : 0.5 } ?? 0)
            if best == nil || s < best!.1 { best = (r, s) }
        }
        return best?.0
    }

    /// 去掉“(Deluxe Edition)”“[Remastered]”之类版本说明再比专辑名
    public static func stripEdition(_ s: String) -> String {
        var t = s
        for (o, c) in [("(", ")"), ("（", "）"), ("[", "]")] {
            while let a = t.range(of: o), let b = t.range(of: c, range: a.upperBound..<t.endIndex) { t.removeSubrange(a.lowerBound..<b.upperBound) }
        }
        return t
    }

    /// iTunes 小图地址换成 600×600
    public static func largeArtwork(_ url100: String) -> String {
        // 要能拿到的最大尺寸：苹果图床按原图封顶（要 10000 给 3000 的原图，不会放大）
        url100.replacingOccurrences(of: "100x100bb", with: "10000x10000bb")
    }

    /// 汉字（含日文汉字）占多数 → 去台湾 / 香港 / 大陆 / 日本区找；否则美国区
    public static func iTunesCountries(for q: CoverQuery) -> [String] {
        let s = q.title + (q.artist ?? "")
        let han = s.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }.count
        let kana = s.unicodeScalars.filter { (0x3040...0x30FF).contains($0.value) }.count
        let hangul = s.unicodeScalars.filter { (0xAC00...0xD7AF).contains($0.value) }.count
        if kana > 0 { return ["jp", "us"] }
        if hangul > 0 { return ["kr", "us"] }
        if han > 0 { return ["tw", "hk", "cn"] }
        return ["us", "gb"]
    }

    /// 缓存键：同一歌手同一专辑共用一张封面；没有专辑名时按歌名 + 时长
    public static func cacheKey(_ q: CoverQuery) -> String {
        let a = fold(q.artist ?? "")
        let s = q.hasAlbum ? "album|\(a)|\(fold(q.album!))" : "track|\(a)|\(fold(LyricsLookup.cleanTitle(q.title)))|\(Int((q.duration ?? 0).rounded()))"
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }
}

/// 「联网查找封面 / 重新查找封面」时如何清理磁盘缓存。
/// 用户刚选过「改用默认封面」时，官方图的 jpg/json 往往还在，只是被 .default 标记挡住；
/// 此时再选「联网查找封面」应去掉标记并从缓存恢复，而不是清掉缓存再走一遍 MusicBrainz。
/// 已经在用官方封面时的「重新查找封面」仍清除全部缓存再查。
public enum CoverRefetch: Sendable {
    public enum CacheClear: Equatable, Sendable {
        case userDefaultOnly
        case all
    }
    public static func cacheClear(userDefaultExists: Bool) -> CacheClear {
        userDefaultExists ? .userDefaultOnly : .all
    }
}
