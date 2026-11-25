// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// AutoEq 耳机校正（https://github.com/jaakkopasanen/AutoEq，MIT 许可）。
/// 数据：results/INDEX.md 列出所有耳机（约 8800 条，来源 crinacle / oratory1990 / Rtings 等测量），
/// 每个耳机目录里的「<名字> GraphicEQ.txt」是 127 个频点的校正曲线（目标：Harman 等）。
/// 播放时用 FFmpeg 的 firequalizer 按整条曲线做线性相位 FIR 均衡（比套到 16 段均衡器上准确），
/// 前面加一段负增益（= 曲线最大正增益）防止削波。
public enum AutoEq {
    public static let label = "tancoautoeq"
    public static let rawBase = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/"
    public static let indexURL = URL(string: rawBase + "INDEX.md")!

    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var name: String       // 耳机名（可能带测量条件，如「(ANC On)」）
        public var source: String     // 测量来源（crinacle、oratory1990…）
        public var rig: String?       // 测量设备（如 711、GRAS 43AG-7）
        public var path: String       // INDEX 里的相对路径（已解码）
        public var id: String { path }
        public init(name: String, source: String, rig: String?, path: String) {
            self.name = name; self.source = source; self.rig = rig; self.path = path
        }
        public var displaySource: String { rig.map { "\(source) · \($0)" } ?? source }
        /// GraphicEQ 文件的下载地址
        public var graphicEQURL: URL? {
            let comps = path.split(separator: "/").map(String.init) + ["\(name) GraphicEQ.txt"]
            let enc = comps.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "+&?#"))) ?? $0 }
            return URL(string: rawBase + enc.joined(separator: "/"))
        }
    }

    /// 解析 INDEX.md：「- [名字](./来源/设备 类型/名字) by 来源 on 设备」
    public static func parseIndex(_ md: String) -> [Entry] {
        var out: [Entry] = []
        for raw in md.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ["), let close = line.range(of: "](") else { continue }
            let name = String(line[line.index(line.startIndex, offsetBy: 3)..<close.lowerBound])
            let rest = line[close.upperBound...]
            guard let end = rest.range(of: ") by ") else { continue }
            var path = String(rest[rest.startIndex..<end.lowerBound])
            if path.hasPrefix("./") { path.removeFirst(2) }
            path = path.removingPercentEncoding ?? path
            let tail = rest[end.upperBound...]
            var source = String(tail), rig: String? = nil
            if let on = tail.range(of: " on ") { source = String(tail[tail.startIndex..<on.lowerBound]); rig = String(tail[on.upperBound...]) }
            out.append(Entry(name: name, source: source.trimmingCharacters(in: .whitespaces), rig: rig?.trimmingCharacters(in: .whitespaces), path: path))
        }
        return out
    }

    /// 搜索：所有关键词都要出现（不分大小写），名字开头命中的排前面
    public static func search(_ entries: [Entry], _ q: String, limit: Int = 60) -> [Entry] {
        let words = q.lowercased().split(whereSeparator: { $0 == " " }).map(String.init)
        guard !words.isEmpty else { return [] }
        let hits = entries.filter { e in let n = e.name.lowercased(); return words.allSatisfy { n.contains($0) } }
        return Array(hits.sorted { a, b in
            let pa = a.name.lowercased().hasPrefix(words[0]), pb = b.name.lowercased().hasPrefix(words[0])
            if pa != pb { return pa }
            return a.name.count < b.name.count
        }.prefix(limit))
    }

    public struct Curve: Codable, Equatable, Sendable {
        public var points: [EQPreset.Point]
        public var maxGain: Double { points.map(\.db).max() ?? 0 }
        public init(points: [EQPreset.Point]) { self.points = points }

        /// 「GraphicEQ: 20 -0.3; 21 -0.3; …」
        public static func parse(_ text: String) -> Curve? {
            guard let r = text.range(of: "GraphicEQ:") else { return nil }
            var pts: [EQPreset.Point] = []
            for part in text[r.upperBound...].split(separator: ";") {
                let nums = part.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).compactMap { Double($0) }
                if nums.count >= 2, nums[0] > 0 { pts.append(EQPreset.Point(nums[0], nums[1])) }
            }
            return pts.count >= 8 ? Curve(points: pts.sorted { $0.hz < $1.hz }) : nil
        }

        /// 对数频率上线性插值
        public func gain(at hz: Double) -> Double {
            guard let f = points.first, let l = points.last else { return 0 }
            if hz <= f.hz { return f.db }
            if hz >= l.hz { return l.db }
            var lo = 0, hi = points.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if points[m].hz <= hz { lo = m } else { hi = m } }
            let a = points[lo], b = points[hi]
            let t = (log(hz) - log(a.hz)) / (log(b.hz) - log(a.hz))
            return a.db + (b.db - a.db) * t
        }
    }

    /// mpv af 里的一段：先降增益防削波，再按整条曲线 FIR 均衡（strength 0…1 可以减弱校正）
    public static let maxEntries = 80
    public static func filter(_ c: Curve, strength: Double = 1) -> String {
        let k = min(max(strength, 0), 1)
        // FFmpeg 的 gain_entry 是一串用 ; 连起来的表达式，超过约 100 条会初始化失败（2026-11-19 实测 127 条报 ENOMEM），
        // 所以按对数频率重采样成最多 maxEntries 个点（实测 80 点时 40 Hz–12 kHz 各频点与曲线误差 ≤0.3 dB）
        let pts: [(Double, Double)] = c.points.count <= maxEntries ? c.points.map { ($0.hz, $0.db) } : {
            let lo = max(10, c.points.first!.hz), hi = c.points.last!.hz
            return (0..<maxEntries).map { i in let f = lo * pow(hi / lo, Double(i) / Double(maxEntries - 1)); return (f, c.gain(at: f)) }
        }()
        let entries = pts.map { "entry(\(fmt($0.0)),\(fmt($0.1 * k)))" }.joined(separator: ";")
        let pre = -max(0, c.maxGain * k)
        return "@\(label):lavfi=[volume=\(fmt(pre))dB:precision=float,firequalizer=gain_entry='\(entries)':gain='cubic_interpolate(f)']"
    }

    static func fmt(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s == "-0" ? "0" : s
    }
}
