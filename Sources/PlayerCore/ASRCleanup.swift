// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// whisper 在没人说话、只有音乐或噪声的地方常会“编”出训练数据里的片尾字幕（如「中文字幕:YK」「请不吝点赞 订阅」），
/// 还会把同一句重复几十遍。这里在生成的 SRT / LRC 上做一次清理：去掉这类套话，同一句连续出现超过两次时只留前两次。
public enum ASRCleanup {
    static let junk: [String] = [
        #"中文字幕"#, #"字幕[由:：]"#, #"字幕组"#, #"字幕志愿者"#, #"请不吝点赞"#, #"订阅.{0,4}转发"#, #"打赏支持"#, #"明镜.{0,4}点点"#,
        #"(?i)amara\.org"#, #"(?i)subtitles? by"#, #"(?i)transcri(bed|ption) by"#, #"(?i)thanks? for watching"#, #"(?i)please subscribe"#,
    ]
    static let junkRegex = junk.map { try! NSRegularExpression(pattern: $0) }

    public static func isJunk(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let r = NSRange(t.startIndex..., in: t)
        return junkRegex.contains { $0.firstMatch(in: t, range: r) != nil }
    }

    /// 返回清理后的 SRT 和去掉的条数
    public static func cleanSRT(_ srt: String) -> (String, Int) {
        let blocks = srt.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n")
        var kept: [(String, String)] = []   // (时间行, 文字)
        var removed = 0
        var run = 0
        for b in blocks {
            let lines = b.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let text = lines[(ti + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            if isJunk(text) { removed += 1; continue }
            if let last = kept.last, norm(last.1) == norm(text) {
                run += 1
                if run >= 2 { removed += 1; continue }
            } else { run = 0 }
            kept.append((lines[ti], text))
        }
        let out = kept.enumerated().map { "\($0.offset + 1)\n\($0.element.0)\n\($0.element.1)" }.joined(separator: "\n\n") + "\n"
        return (out, removed)
    }

    public static func cleanLRC(_ lrc: String) -> (String, Int) {
        var out: [String] = [], removed = 0, prev = "", run = 0
        for l in lrc.replacingOccurrences(of: "\r", with: "").split(separator: "\n").map(String.init) {
            guard l.hasPrefix("["), let close = l.firstIndex(of: "]") else { out.append(l); continue }
            let text = String(l[l.index(after: close)...])
            if text.trimmingCharacters(in: .whitespaces).isEmpty || isJunk(text) { removed += 1; continue }
            if norm(text) == prev { run += 1; if run >= 2 { removed += 1; continue } } else { run = 0 }
            prev = norm(text); out.append(l)
        }
        return (out.joined(separator: "\n") + "\n", removed)
    }

    static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
}
