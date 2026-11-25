// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 播放列表文件（.m3u8，UTF-8）。读的时候也兼容 .m3u / .pls 的常见写法。
public enum PlaylistFile {
    public static func m3u8(_ items: [MediaItem]) -> String {
        var out = "#EXTM3U\n"
        for it in items {
            let d = it.duration.map { Int($0.rounded()) } ?? -1
            let name = [it.artist, it.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
            out += "#EXTINF:\(d),\(name.isEmpty ? it.title : name)\n"
            out += (it.url.isFileURL ? it.url.path : it.url.absoluteString) + "\n"
        }
        return out
    }

    /// 解析后返回 URL 列表；相对路径按播放列表所在目录解析。
    public static func parse(_ text: String, relativeTo base: URL) -> [URL] {
        var out: [URL] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("[") { continue }
            if line.lowercased().hasPrefix("file"), let eq = line.firstIndex(of: "="), line.lowercased().range(of: #"^file\d+="#, options: .regularExpression) != nil {
                line = String(line[line.index(after: eq)...])     // .pls
            } else if line.contains("=") && !line.contains("/") { continue }
            if let u = URL(string: line), let sch = u.scheme, ["http", "https", "file"].contains(sch.lowercased()) {
                out.append(sch.lowercased() == "file" ? URL(fileURLWithPath: u.path) : u)
            } else if line.hasPrefix("/") {
                out.append(URL(fileURLWithPath: line))
            } else {
                out.append(base.appendingPathComponent(line))
            }
        }
        return out
    }
}
