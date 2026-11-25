// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import PlayerCore

/// 在线字幕：OpenSubtitles 搜索 + 下载（.gz 用系统自带的 /usr/bin/gzip 解压），存到 runtime/subtitles
enum SubtitleService {
    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 20)
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        let ua = SubtitleSearch.userAgentHeader(version: v)
        r.setValue(ua.1, forHTTPHeaderField: ua.0)
        r.setValue(ua.1, forHTTPHeaderField: "User-Agent")
        return r
    }

    /// OpenSubtitles 旧版接口一次只接受一种语言（逗号分隔会返回 400），所以每种语言各查一次再合并。
    static let defaultLanguages = ["chi", "zht", "zhe", "eng"]

    static func search(media: URL, query: String?, languages: [String] = defaultLanguages) async -> (results: [SubtitleSearch.Result], error: String?) {
        var urls: [(URL, Bool)] = []
        if media.isFileURL, let h = SubtitleSearch.osdbHash(fileURL: media),
           let size = (try? FileManager.default.attributesOfItem(atPath: media.path)[.size] as? NSNumber)?.uint64Value {
            urls += languages.map { (SubtitleSearch.hashURL(hash: h, size: size, languages: $0), true) }
        }
        let q = (query?.isEmpty == false ? query! : SubtitleSearch.cleanQuery(fileName: media.lastPathComponent))
        if !q.isEmpty { urls += languages.map { (SubtitleSearch.queryURL(q, languages: $0), false) } }
        let wanted = Set(languages)
        let found: [(Bool, [SubtitleSearch.Result], String?)] = await withTaskGroup(of: (Bool, [SubtitleSearch.Result], String?).self) { g in
            for (u, byHash) in urls {
                g.addTask {
                    do {
                        let (d, resp) = try await Net.data(for: request(u))
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        guard code == 200 else { return (byHash, [], "HTTP \(code)") }
                        return (byHash, SubtitleSearch.parse(d, byHash: byHash).filter { wanted.contains($0.languageID) }, nil)
                    } catch { return (byHash, [], error.localizedDescription) }
                }
            }
            var all: [(Bool, [SubtitleSearch.Result], String?)] = []
            for await r in g { all.append(r) }
            return all
        }
        let byHash = found.filter { $0.0 }.flatMap { $0.1 }, byName = found.filter { !$0.0 }.flatMap { $0.1 }
        let all = SubtitleSearch.merge(byHash, byName)
        return (all, all.isEmpty ? found.compactMap { $0.2 }.first : nil)
    }

    /// 下载并解压成 UTF-8 文本文件，返回本地路径
    static func download(_ r: SubtitleSearch.Result, for media: URL) async throws -> URL {
        guard let url = URL(string: r.downloadLink) else { throw URLError(.badURL) }
        let (gz, resp) = try await Net.data(for: request(url))
        guard (resp as? HTTPURLResponse)?.statusCode == 200, !gz.isEmpty else { throw URLError(.badServerResponse) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("liuli-sub-\(UUID().uuidString).gz")
        try gz.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        p.arguments = ["-dc", tmp.path]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let raw = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let data = p.terminationStatus == 0 && !raw.isEmpty ? raw : gz   // 有时服务器直接给明文
        guard let text = SubtitleSearch.decodeText(data, hint: r.encoding) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let lang = r.languageID.isEmpty ? "sub" : r.languageID
        let dest = Runtime.dir("subtitles").appendingPathComponent("\(Runtime.key(for: media)).\(lang).\(r.format)")
        try text.data(using: .utf8)!.write(to: dest, options: .atomic)
        return dest
    }
}
