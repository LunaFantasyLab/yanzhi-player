// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

public enum MediaKind: String, Codable, Sendable { case audio, video }

public enum MediaFormats {
    // 交给 libmpv/FFmpeg 解码，几乎什么都能放；这里只用于“打开文件夹”时筛选、拖放判断。
    public static let audio: Set<String> = [
        "mp3", "mp2", "m4a", "m4b", "aac", "alac", "caf", "flac", "wav", "wave", "w64", "rf64", "bwf",
        "aif", "aiff", "aifc", "ogg", "oga", "opus", "spx", "ape", "mac", "wv", "tta", "tak", "mpc", "mp+",
        "wma", "dsf", "dff", "dsd", "ac3", "eac3", "dts", "dtshd", "mka", "amr", "awb", "au", "snd", "ra",
        "mid", "midi", "mod", "xm", "it", "s3m", "shn", "ofr", "weba", "thd", "mlp", "cue",
    ]
    public static let video: Set<String> = [
        "mp4", "m4v", "mov", "qt", "mkv", "mk3d", "webm", "avi", "divx", "flv", "f4v", "wmv", "asf", "ts",
        "m2ts", "mts", "m2t", "tp", "trp", "mpg", "mpeg", "mpe", "m1v", "m2v", "vob", "evo", "3gp", "3g2",
        "ogv", "ogm", "rm", "rmvb", "dv", "mxf", "nut", "y4m", "h264", "264", "hevc", "h265", "265", "av1",
        "ivf", "obu", "vp9", "gif", "apng",
    ]
    public static let subtitles: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "idx", "sup", "smi", "sami", "lrc_sub", "ttml", "dfxp", "usf", "jss"]
    public static let coverNames: [String] = ["cover", "folder", "front", "album", "albumart", "albumartsmall", "artwork", "封面", "专辑封面"]
    public static let imageExts: [String] = ["jpg", "jpeg", "png", "webp", "heic", "avif", "bmp", "tif", "tiff", "gif"]

    public static func kind(forExtension ext: String) -> MediaKind? {
        let e = ext.lowercased()
        if audio.contains(e) { return .audio }
        if video.contains(e) { return .video }
        return nil
    }

    public static func isPlayable(_ url: URL) -> Bool { kind(forExtension: url.pathExtension) != nil && url.pathExtension.lowercased() != "cue" }
}

/// 一首歌 / 一段视频。
public struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var kind: MediaKind
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: Double?
    public var trackNumber: Int?
    public var discNumber: Int?
    /// 技术信息，例如 “FLAC · 24bit/96kHz”。
    public var formatLine: String?

    public init(url: URL, kind: MediaKind? = nil, title: String? = nil, artist: String? = nil, album: String? = nil,
                duration: Double? = nil, trackNumber: Int? = nil, discNumber: Int? = nil, formatLine: String? = nil) {
        self.url = url
        self.kind = kind ?? MediaFormats.kind(forExtension: url.pathExtension) ?? .audio
        self.title = title ?? MediaItem.titleFromFilename(url)
        self.artist = artist; self.album = album; self.duration = duration
        self.trackNumber = trackNumber; self.discNumber = discNumber; self.formatLine = formatLine
    }

    /// “03 - 周杰伦 - 晴天.flac” → 标题“晴天”（带歌手前缀时拆出来）。
    public static func titleFromFilename(_ url: URL) -> String {
        var s = url.deletingPathExtension().lastPathComponent
        s = s.replacingOccurrences(of: "_", with: " ")
        if let r = s.range(of: #"^\s*\d{1,3}\s*[-.、 ]\s*"#, options: .regularExpression) { s.removeSubrange(r) }
        let parts = s.components(separatedBy: " - ")
        if parts.count >= 2 { return parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    public static func artistFromFilename(_ url: URL) -> String? {
        var s = url.deletingPathExtension().lastPathComponent
        if let r = s.range(of: #"^\s*\d{1,3}\s*[-.、 ]\s*"#, options: .regularExpression) { s.removeSubrange(r) }
        let parts = s.components(separatedBy: " - ")
        return parts.count >= 2 ? parts[0].trimmingCharacters(in: .whitespaces) : nil
    }

    /// 界面上显示的艺人：没有艺人信息（标签和文件名里都没有）就是 nil，界面隐藏这一行，不写「未知艺人」。
    public var knownArtist: String? { artist?.isEmpty == false ? artist! : MediaItem.artistFromFilename(url) }
    /// 排序 / 封面种子等内部用（不直接显示）
    public var displayArtist: String { artist?.isEmpty == false ? artist! : (MediaItem.artistFromFilename(url) ?? "未知艺人") }
    /// 默认封面用的种子：同一张专辑的歌共享同一张默认封面。
    public var coverSeed: String { CoverRerolls.shared.seed(for: baseCoverSeed) }
    /// 没换过的原始种子（「换一张生成封面」按它记随机数，同一张专辑的歌一起换）
    public var baseCoverSeed: String {
        if let album, !album.isEmpty { return "album|" + album + "|" + displayArtist }
        return "track|" + title + "|" + displayArtist
    }
}

/// 外挂字幕匹配：同名（可带语言后缀，如 movie.zh-Hans.srt / movie.chs.ass）。
public enum SubtitleMatcher {
    public static func sidecars(for video: URL, in directoryListing: [URL]) -> [URL] {
        let base = video.deletingPathExtension().lastPathComponent.lowercased()
        return directoryListing.filter { u in
            let ext = u.pathExtension.lowercased()
            guard MediaFormats.subtitles.contains(ext) else { return false }
            let name = u.deletingPathExtension().lastPathComponent.lowercased()
            return name == base || name.hasPrefix(base + ".") || name.hasPrefix(base + "_") || name.hasPrefix(base + " ")
        }
        .sorted { score($0) > score($1) }
    }

    /// 简体中文优先，其次繁体、双语，然后其他。
    static func score(_ u: URL) -> Int {
        let n = u.lastPathComponent.lowercased()
        if n.contains("chs&eng") || n.contains("双语") || n.contains("bilingual") { return 5 }
        if n.contains("chs") || n.contains("zh-hans") || n.contains(".sc.") || n.contains("简") { return 4 }
        if n.contains("cht") || n.contains("zh-hant") || n.contains("繁") { return 3 }
        if n.contains("zh") || n.contains("chi") { return 2 }
        return 1
    }
}

public enum TimeFormat {
    public static func clock(_ seconds: Double?) -> String {
        guard let s0 = seconds, s0.isFinite, s0 >= 0 else { return "--:--" }
        let s = Int(s0.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
    public static func remaining(_ pos: Double?, _ dur: Double?) -> String {
        guard let p = pos, let d = dur, d.isFinite, d > 0 else { return "--:--" }
        return "-" + clock(max(0, d - p))
    }
}

extension TimeFormat {
    /// “1:23” / “01:02:03” / “95” / “95.5” → 秒；无法识别返回 nil（跳转对话框用）
    public static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "，", with: ".").replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count <= 3, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }
}

/// 声道模式：用一个独立的 lavfi pan 滤镜实现（与均衡器滤镜串联）。
public enum ChannelMode: String, CaseIterable, Codable, Sendable {
    case stereo, swap, leftOnly, rightOnly, mono
    public var title: String {
        switch self {
        case .stereo: return "立体声（原样）"
        case .swap: return "左右互换"
        case .leftOnly: return "仅左声道"
        case .rightOnly: return "仅右声道"
        case .mono: return "单声道混合"
        }
    }
    public var panGraph: String? {
        switch self {
        case .stereo: return nil
        case .swap: return "pan=stereo|c0=c1|c1=c0"
        case .leftOnly: return "pan=stereo|c0=c0|c1=c0"
        case .rightOnly: return "pan=stereo|c0=c1|c1=c1"
        case .mono: return "pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1"
        }
    }
    public static func audioFilter(eq: EQState, channel: ChannelMode) -> String {
        var s = MPVEqualizerGraph.filterString(for: eq)
        if let g = channel.panGraph { s += ",@tancoch:lavfi=[\(g)]" }
        return s
    }
}
