// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 在线字幕搜索（OpenSubtitles 旧版 REST 接口，无需账号和密钥；https://rest.opensubtitles.org）。
/// 先按「文件指纹」（OSDb 哈希：文件大小 + 头尾各 64 KB 的 64 位和）精确匹配，再按文件名关键词搜。
/// 下载链接是 .gz，解压后存到项目目录；字幕内容版权归原作者/字幕组，仅供个人观看。
public enum SubtitleSearch {
    public static let base = "https://rest.opensubtitles.org/search"
    /// OpenSubtitles 旧版接口要求带可识别的 UA；版本号由 App 侧注入（取 CFBundleShortVersionString），不用测试占位 UA。
    public static func userAgentHeader(version: String) -> (String, String) {
        ("X-User-Agent", "Liuli/\(version) (TANCO local music player for macOS)")
    }

    public struct Result: Codable, Hashable, Sendable, Identifiable {
        public var id: String { downloadLink }
        public var fileName: String
        public var language: String
        public var languageID: String
        public var format: String
        public var downloadLink: String
        public var downloads: Int
        public var movieName: String
        public var year: String
        public var encoding: String
        public var matchedByHash: Bool
    }

    /// OSDb 哈希（opensubtitles 官方算法）
    public static func osdbHash(size: UInt64, head: Data, tail: Data) -> String {
        var h = size
        func add(_ d: Data) {
            d.withUnsafeBytes { raw in
                let n = raw.count / 8
                for i in 0..<n { h = h &+ UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self)) }
            }
        }
        add(head); add(tail)
        return String(format: "%016llx", h)
    }

    public static func osdbHash(fileURL: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? fh.close() }
        guard let size = try? fh.seekToEnd(), size >= 65536 else { return nil }
        try? fh.seek(toOffset: 0)
        let head = fh.readData(ofLength: 65536)
        try? fh.seek(toOffset: size - 65536)
        let tail = fh.readData(ofLength: 65536)
        return osdbHash(size: size, head: head, tail: tail)
    }

    /// 语言：chi（简繁中文）、eng 等，逗号分隔
    public static func hashURL(hash: String, size: UInt64, languages: String) -> URL {
        URL(string: "\(base)/moviebytesize-\(size)/moviehash-\(hash)/sublanguageid-\(languages)")!
    }
    public static func queryURL(_ q: String, languages: String) -> URL {
        let enc = q.lowercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? q
        return URL(string: "\(base)/query-\(enc)/sublanguageid-\(languages)")!
    }

    /// 从文件名猜搜索词：去掉扩展名、分辨率、编码、发布组等常见噪音
    public static func cleanQuery(fileName: String) -> String {
        var s = (fileName as NSString).deletingPathExtension
        s = s.replacingOccurrences(of: #"[\._\[\]\(\)]"#, with: " ", options: .regularExpression)
        let noise = #"(?i)\b(2160p|1080p|720p|480p|4k|uhd|hdr10?|dv|web-?dl|webrip|bluray|bdrip|brrip|hdtv|x26[45]|h\.?26[45]|hevc|avc|aac|ac3|dts|ddp?5\.1|atmos|10bit|proper|repack|remux|extended)\b.*$"#
        s = s.replacingOccurrences(of: noise, with: "", options: .regularExpression)
        return s.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    public static func parse(_ data: Data, byHash: Bool) -> [Result] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let link = d["SubDownloadLink"] as? String, let name = d["SubFileName"] as? String else { return nil }
            func s(_ k: String) -> String { (d[k] as? String) ?? "" }
            return Result(fileName: name, language: s("LanguageName"), languageID: s("SubLanguageID"), format: s("SubFormat").lowercased(),
                          downloadLink: link, downloads: Int(s("SubDownloadsCnt")) ?? 0, movieName: s("MovieName"), year: s("MovieYear"),
                          encoding: s("SubEncoding"), matchedByHash: byHash || s("MatchedBy") == "moviehash")
        }
        .filter { ["srt", "ass", "ssa", "vtt", "sub"].contains($0.format) }
    }

    /// 合并两次搜索结果：指纹匹配优先，其次下载量
    public static func merge(_ a: [Result], _ b: [Result]) -> [Result] {
        var seen = Set<String>(), out: [Result] = []
        for r in (a + b) where seen.insert(r.downloadLink).inserted { out.append(r) }
        return out.sorted { ($0.matchedByHash ? 1 : 0, $0.downloads) > ($1.matchedByHash ? 1 : 0, $1.downloads) }
    }

    /// 字幕网站的网页搜索（在默认浏览器里打开，由你自己挑）
    public static func webSearches(_ q: String) -> [(String, URL)] {
        let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return [
            ("OpenSubtitles", URL(string: "https://www.opensubtitles.org/zh/search2/sublanguageid-chi,eng/moviename-\(e)")!),
            ("SubHD", URL(string: "https://subhd.tv/search/\(e)")!),
            ("字幕库 zimuku", URL(string: "https://zimuku.org/search?q=\(e)")!),
            ("伪射手 assrt", URL(string: "https://assrt.net/sub/?searchword=\(e)")!),
        ]
    }

    /// 字幕文本转码：按 OpenSubtitles 给的编码名（CP936/GB18030/BIG5/UTF-8…）解码，失败再依次试常见中文编码
    public static func decodeText(_ d: Data, hint: String) -> String? {
        if let s = String(data: d, encoding: .utf8) { return s }
        var tries: [String.Encoding] = []
        let h = hint.uppercased()
        #if canImport(Darwin)
        // GB18030/Big5 只能经 Darwin 的 CF 编码表转成 String.Encoding；非 Darwin 平台跳过这两种，仍按 UTF-16/CP1252/Latin-1 兜底。
        func cf(_ e: CFStringEncodings) -> String.Encoding { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(e.rawValue))) }
        if h.contains("936") || h.contains("GB") { tries.append(cf(.GB_18030_2000)) }
        if h.contains("BIG5") || h.contains("950") { tries.append(cf(.big5)) }
        tries += [cf(.GB_18030_2000), cf(.big5)]
        #endif
        tries += [.utf16, .windowsCP1252, .isoLatin1]
        for e in tries { if let s = String(data: d, encoding: e) { return s } }
        return nil
    }
}
