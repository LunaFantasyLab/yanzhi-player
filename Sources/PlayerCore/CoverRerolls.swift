// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 「换一张生成封面」（TANCO 2026-11-23）：没有标签 / 封面的卡片用本地程序生成的封面；
/// 右键可以随机重新生成——只是给这张专辑的封面种子加一个随机数，算法还是本地的 DefaultCoverSpec，不调用任何 AI 接口。
/// 随机数记在 cover-rerolls.json，下次打开还是这一张。
public struct CoverRerollBook: Codable, Equatable, Sendable {
    public var nonces: [String: UInt64] = [:]
    public init() {}

    public func seed(for base: String) -> String {
        guard let n = nonces[base] else { return base }
        return base + "|reroll:" + String(n, radix: 16)
    }

    /// 换一个和上次不同的随机数；返回新的种子
    @discardableResult
    public mutating func reroll<R: RandomNumberGenerator>(_ base: String, using rng: inout R) -> String {
        var n = rng.next()
        while n == 0 || n == nonces[base] { n = rng.next() }
        nonces[base] = n
        return seed(for: base)
    }
    @discardableResult
    public mutating func reroll(_ base: String) -> String { var g = SystemRandomNumberGenerator(); return reroll(base, using: &g) }

    public static func load(from url: URL) -> CoverRerollBook {
        guard let d = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(CoverRerollBook.self, from: d) else { return CoverRerollBook() }
        return b
    }
    public static func save(_ b: CoverRerollBook, to url: URL) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(b).write(to: url, options: .atomic)
    }
}

/// 全局共享的一份（封面在后台线程生成，要能并发读）
public final class CoverRerolls: @unchecked Sendable {
    public static let shared = CoverRerolls()
    private let lock = NSLock()
    private var book = CoverRerollBook()
    public init() {}
    public var current: CoverRerollBook { lock.lock(); defer { lock.unlock() }; return book }
    public func set(_ b: CoverRerollBook) { lock.lock(); book = b; lock.unlock() }
    public func seed(for base: String) -> String { lock.lock(); defer { lock.unlock() }; return book.seed(for: base) }
    @discardableResult
    public func reroll(_ base: String) -> CoverRerollBook { lock.lock(); defer { lock.unlock() }; book.reroll(base); return book }
}
