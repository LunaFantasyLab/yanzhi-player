// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 均衡器段数：16 或 32（TANCO 要求 16–32 段，可切换）。
public enum EQBandCount: Int, Codable, CaseIterable, Sendable {
    case sixteen = 16
    case thirtyTwo = 32

    /// 20 Hz–20 kHz 对数等分（10 个倍频程，16 段 ≈ 2/3 倍频程，32 段 ≈ 1/3 倍频程）。
    public var frequencies: [Double] {
        let n = rawValue
        return (0..<n).map { i in 20 * pow(1000, Double(i) / Double(n - 1)) }
    }

    /// 每段带宽（倍频程），取相邻中心频率间距，使相邻段平滑衔接、没有“坑”。
    public var bandwidthOctaves: Double { log2(1000) / Double(rawValue - 1) }

    public static func label(for f: Double) -> String {
        if f >= 1000 {
            let k = f / 1000
            return k >= 10 ? String(format: "%.0fk", k) : String(format: "%.1fk", k).replacingOccurrences(of: ".0k", with: "k")
        }
        return f >= 100 ? String(format: "%.0f", (f / 5).rounded() * 5) : String(format: "%.0f", f.rounded())
    }
}

/// 预设用“频率-增益”控制点描述（对数频率上做平滑插值），所以同一个预设在 16 段和 32 段上形状一致。
public struct EQPreset: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var points: [Point]
    public var isBuiltIn: Bool

    public struct Point: Codable, Hashable, Sendable {
        public var hz: Double
        public var db: Double
        public init(_ hz: Double, _ db: Double) { self.hz = hz; self.db = db }
    }

    public init(id: String, name: String, points: [Point], isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.points = points.sorted { $0.hz < $1.hz }; self.isBuiltIn = isBuiltIn
    }

    /// 从一组已有增益创建自定义预设（保存用户调好的曲线）。
    public init(customName: String, frequencies: [Double], gains: [Double]) {
        self.init(id: "custom-" + UUID().uuidString, name: customName,
                  points: zip(frequencies, gains).map { Point($0, $1) }, isBuiltIn: false)
    }

    /// 在任意频率上的增益：log 频率上的单调三次插值（不会过冲出奇怪的峰）。
    public func gain(at hz: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if points.count == 1 { return first.db }
        let x = log2(hz)
        if x <= log2(first.hz) { return first.db }
        if x >= log2(last.hz) { return last.db }
        let xs = points.map { log2($0.hz) }, ys = points.map(\.db)
        return MonotoneCubic.interpolate(xs: xs, ys: ys, at: x)
    }

    public func gains(for count: EQBandCount) -> [Double] {
        count.frequencies.map { (gain(at: $0) * 10).rounded() / 10 }
    }

    public static let flat = EQPreset(id: "flat", name: "平直", points: [Point(20, 0), Point(20000, 0)], isBuiltIn: true)

    public static let builtIns: [EQPreset] = [
        flat,
        EQPreset(id: "pop", name: "流行", points: [Point(20, -1), Point(60, 1.5), Point(150, 3), Point(400, 1.5), Point(1000, -0.5), Point(2500, 1.5), Point(6000, 3), Point(14000, 3.5), Point(20000, 2.5)], isBuiltIn: true),
        EQPreset(id: "rock", name: "摇滚", points: [Point(20, 3), Point(70, 4.5), Point(200, 2), Point(600, -1.5), Point(1500, -0.5), Point(3500, 2.5), Point(8000, 4), Point(16000, 4.5), Point(20000, 4)], isBuiltIn: true),
        EQPreset(id: "vocal", name: "人声", points: [Point(20, -3), Point(100, -2), Point(250, -0.5), Point(800, 1.5), Point(2000, 3.5), Point(4000, 3), Point(8000, 1), Point(16000, -0.5), Point(20000, -1)], isBuiltIn: true),
        EQPreset(id: "bass", name: "低音增强", points: [Point(20, 6), Point(45, 6.5), Point(90, 5), Point(180, 2.5), Point(400, 0.5), Point(1000, 0), Point(20000, 0)], isBuiltIn: true),
        EQPreset(id: "treble", name: "高音增强", points: [Point(20, 0), Point(1500, 0), Point(4000, 2), Point(8000, 4.5), Point(14000, 5.5), Point(20000, 5)], isBuiltIn: true),
        EQPreset(id: "classical", name: "古典", points: [Point(20, 2), Point(80, 2.5), Point(250, 1), Point(1000, 0), Point(3000, -0.5), Point(8000, 1.5), Point(16000, 2.5), Point(20000, 2)], isBuiltIn: true),
        EQPreset(id: "jazz", name: "爵士", points: [Point(20, 2), Point(80, 3), Point(250, 1.5), Point(700, -1), Point(2000, 0.5), Point(5000, 2), Point(12000, 3), Point(20000, 2.5)], isBuiltIn: true),
        EQPreset(id: "electronic", name: "电子", points: [Point(20, 5), Point(60, 5.5), Point(150, 2.5), Point(500, -1.5), Point(1500, 0), Point(4000, 2), Point(10000, 4.5), Point(20000, 5)], isBuiltIn: true),
        EQPreset(id: "acoustic", name: "原声", points: [Point(20, 1.5), Point(100, 2.5), Point(300, 1), Point(1000, 0.5), Point(3000, 2), Point(7000, 2.5), Point(15000, 1.5), Point(20000, 1)], isBuiltIn: true),
        EQPreset(id: "night", name: "夜间柔和", points: [Point(20, -2), Point(80, 1), Point(300, 1.5), Point(1500, 0), Point(4000, -2), Point(9000, -3.5), Point(20000, -4.5)], isBuiltIn: true),
        EQPreset(id: "loudness", name: "响度补偿", points: [Point(20, 6), Point(60, 5), Point(150, 2), Point(500, 0), Point(2000, 0), Point(6000, 2), Point(12000, 4), Point(20000, 4.5)], isBuiltIn: true),
    ]
}

/// 均衡器完整状态（会持久化）。
public struct EQState: Codable, Equatable, Sendable {
    public static let gainRange: ClosedRange<Double> = -12...12
    public static let preampRange: ClosedRange<Double> = -12...6

    public var enabled: Bool
    public var bandCount: EQBandCount
    public var gains: [Double]
    public var preamp: Double
    public var presetID: String?

    public init(enabled: Bool = false, bandCount: EQBandCount = .sixteen, gains: [Double]? = nil, preamp: Double = 0, presetID: String? = "flat") {
        self.enabled = enabled
        self.bandCount = bandCount
        self.gains = gains ?? Array(repeating: 0, count: bandCount.rawValue)
        self.preamp = preamp
        self.presetID = presetID
    }

    public var frequencies: [Double] { bandCount.frequencies }

    /// 切换 16/32 段时，把当前曲线重采样到新段数（曲线形状保持不变）。
    public mutating func switchBandCount(_ new: EQBandCount) {
        guard new != bandCount else { return }
        let curve = EQPreset(id: "tmp", name: "", points: zip(frequencies, gains).map { .init($0, $1) })
        bandCount = new
        gains = curve.gains(for: new)
    }

    public mutating func apply(_ preset: EQPreset) {
        gains = preset.gains(for: bandCount)
        presetID = preset.id
    }

    public mutating func reset() {
        gains = Array(repeating: 0, count: bandCount.rawValue)
        preamp = 0
        presetID = EQPreset.flat.id
    }

    public mutating func setGain(_ g: Double, band i: Int) {
        guard gains.indices.contains(i) else { return }
        gains[i] = min(max(g, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        presetID = nil
    }

    /// 建议的防削波前级：把最大正增益抵消掉（只建议，不强制）。
    public var suggestedPreamp: Double { -max(0, gains.max() ?? 0) }
}

/// 把均衡器翻译成 mpv 的音频滤镜（libavfilter）。
/// 用 N 个 `equalizer`（二阶峰值滤波）串联 + 前级 `volume`。
/// 每个滤镜实例都带名字（equalizer@b3），这样拖动滑杆时用 `af-command` 实时改增益，
/// **不重建滤镜链 → 不会爆音、不断音**。开关均衡器用 `mix` 渐变（0↔1），连开关都是平滑过渡。
public enum MPVEqualizerGraph {
    public static let label = "tancoeq"

    public static func filterString(for state: EQState) -> String {
        let w = state.bandCount.bandwidthOctaves
        var parts: [String] = []
        parts.append("volume@pre=volume=\(fmt(state.enabled ? state.preamp : 0))dB:precision=float")
        for (i, f) in state.frequencies.enumerated() {
            let g = state.gains.indices.contains(i) ? state.gains[i] : 0
            parts.append("equalizer@b\(i)=f=\(fmt(f)):t=o:w=\(fmt(w)):g=\(fmt(g)):m=\(state.enabled ? 1 : 0):r=f64")
        }
        // mpv 的 lavfi 包装：@label:lavfi=[graph]
        return "@\(label):lavfi=[\(parts.joined(separator: ","))]"
    }

    /// 实时改单段增益：返回 mpv `af-command` 的参数数组。
    public static func gainCommand(band i: Int, db: Double) -> [String] {
        ["af-command", label, "gain", fmt(db), "equalizer@b\(i)"]
    }

    public static func mixCommand(band i: Int, mix: Double) -> [String] {
        ["af-command", label, "mix", fmt(mix), "equalizer@b\(i)"]
    }

    public static func preampCommand(db: Double) -> [String] {
        ["af-command", label, "volume", "\(fmt(db))dB", "volume@pre"]
    }

    static func fmt(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.3f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}

/// 单调三次插值（Fritsch–Carlson），用于预设曲线与 UI 上的频响曲线。
public enum MonotoneCubic {
    public static func interpolate(xs: [Double], ys: [Double], at x: Double) -> Double {
        let n = xs.count
        guard n >= 2 else { return ys.first ?? 0 }
        var k = 0
        while k < n - 2 && x > xs[k + 1] { k += 1 }
        let m = tangents(xs: xs, ys: ys)
        let h = xs[k + 1] - xs[k]
        guard h > 0 else { return ys[k] }
        let t = (x - xs[k]) / h
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1, h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2, h11 = t3 - t2
        return h00 * ys[k] + h10 * h * m[k] + h01 * ys[k + 1] + h11 * h * m[k + 1]
    }

    public static func tangents(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        var d = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) { d[i] = (ys[i + 1] - ys[i]) / max(1e-9, xs[i + 1] - xs[i]) }
        var m = [Double](repeating: 0, count: n)
        m[0] = d[0]; m[n - 1] = d[n - 2]
        if n > 2 { for i in 1..<(n - 1) { m[i] = (d[i - 1] * d[i] <= 0) ? 0 : (d[i - 1] + d[i]) / 2 } }
        for i in 0..<(n - 1) {
            if d[i] == 0 { m[i] = 0; m[i + 1] = 0; continue }
            let a = m[i] / d[i], b = m[i + 1] / d[i]
            let s = a * a + b * b
            if s > 9 { let t = 3 / s.squareRoot(); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
        }
        return m
    }
}
