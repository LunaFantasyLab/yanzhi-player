// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import PlayerCore

/// AutoEq：首次使用时下载 INDEX.md（约 0.85 MB）缓存到 runtime/autoeq，选中耳机后下载那一条曲线（约 1 KB）
enum AutoEqService {
    static var indexFile: URL { Runtime.dir("autoeq").appendingPathComponent("INDEX.md") }

    /// 打包在 App 里的耳机列表（AutoEq 项目的 INDEX.md，MIT 许可；Contents/Resources/AutoEq/）
    static var bundledIndexFile: URL? { Bundle.main.url(forResource: "INDEX", withExtension: "md", subdirectory: "AutoEq") }

    /// 读耳机列表：先用本机缓存（更新过的那份），没有就用 App 自带的那份 —— 都不联网。
    /// 只有用户点「更新列表」（refresh = true）才去网上拉最新的。
    static func loadIndex(refresh: Bool = false) async throws -> [AutoEq.Entry] {
        if !refresh {
            for f in [indexFile, bundledIndexFile].compactMap({ $0 }) {
                if let s = try? String(contentsOf: f, encoding: .utf8) { let e = AutoEq.parseIndex(s); if !e.isEmpty { return e } }
            }
            throw URLError(.fileDoesNotExist)
        }
        let (d, resp) = try await Net.data(from: AutoEq.indexURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let s = String(data: d, encoding: .utf8) else { throw URLError(.badServerResponse) }
        let e = AutoEq.parseIndex(s)
        guard !e.isEmpty else { throw URLError(.cannotParseResponse) }
        try? d.write(to: indexFile, options: .atomic)
        return e
    }

    /// 现在用的列表是哪一份
    static var indexOrigin: String { FileManager.default.fileExists(atPath: indexFile.path) ? "本机缓存" : "App 自带" }

    static func curve(for e: AutoEq.Entry) async throws -> AutoEq.Curve {
        let cache = Runtime.dir("autoeq").appendingPathComponent(String(format: "%016llx.txt", PlayerCoreHash.fnv(e.path)))
        if let s = try? String(contentsOf: cache, encoding: .utf8), let c = AutoEq.Curve.parse(s) { return c }
        guard let url = e.graphicEQURL else { throw URLError(.badURL) }
        let (d, resp) = try await Net.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let s = String(data: d, encoding: .utf8), let c = AutoEq.Curve.parse(s) else { throw URLError(.badServerResponse) }
        try? d.write(to: cache, options: .atomic)
        return c
    }
}
