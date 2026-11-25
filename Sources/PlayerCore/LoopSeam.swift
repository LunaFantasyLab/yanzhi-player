// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 区间循环的「无缝接缝」（2026-11-19）。
///
/// 背景：MPVKit 自带的 FFmpeg 只编进了很少几个音频滤镜（没有 afade / aeval / asetnsamples），
/// 在 mpv 里做「按采样精确」的淡入淡出做不到；按帧（20–90ms 一档）改音量反而会出现台阶式的小咔声。
/// 所以换成音频编辑软件找循环点的做法：把 A、B 各自在 ±12ms 里挪到「接上去波形连续」的那个采样上——
/// 终点处将要播出的 4 个采样和起点处的 4 个采样逐声道几乎相等（值和斜率都对上），接缝处没有跳变，也就没有咔声。
/// mpv 的 ab-loop 会在 B 精确截断、从 A 精确续上（同一套按采样的时间换算），所以对齐结果能原样生效。
public enum LoopSeam {
    public static let window = 0.012          // 每端搜索 ±12ms
    public static let matchLen = 4

    /// 解析 ao=pcm 写出的 WAV（float32 或 s16），返回交错采样、声道数、采样率
    public static func readWAV(_ d: Data) -> (samples: [Float], channels: Int, rate: Int)? {
        guard d.count > 44, d.prefix(4) == Data("RIFF".utf8) else { return nil }
        var pos = 12, ch = 0, rate = 0, bits = 0, fmt = 0
        func u16(_ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        while pos + 8 <= d.count {
            let id = String(decoding: d[(d.startIndex + pos)..<(d.startIndex + pos + 4)], as: UTF8.self)
            var size = u32(pos + 4)
            let body = pos + 8
            if id == "fmt " { fmt = u16(body); ch = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14) }
            if id == "data" {
                if size == 0 || body + size > d.count { size = d.count - body }   // ao=pcm 流式写入时长度字段可能为 0
                let raw = d.subdata(in: (d.startIndex + body)..<(d.startIndex + body + size))
                guard ch > 0, rate > 0 else { return nil }
                var out: [Float] = []
                if bits == 32 && (fmt == 3 || fmt == 0xFFFE) {
                    out = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                } else if bits == 16 {
                    out = raw.withUnsafeBytes { $0.bindMemory(to: Int16.self).map { Float($0) / 32768 } }
                } else { return nil }
                return (out, ch, rate)
            }
            pos = body + size + (size & 1)
        }
        return nil
    }

    /// 在 A 窗口（从 A−window 开始）和 B 窗口（从 B−window 开始）里找最佳接缝：
    /// 返回 (i, j, 代价)：从 A 窗口第 i 个采样续上、在 B 窗口第 j 个采样处截断。
    public static func bestSplice(a: [Float], b: [Float], channels ch: Int) -> (i: Int, j: Int, cost: Float)? {
        let na = a.count / ch, nb = b.count / ch
        guard na > matchLen + 1, nb > matchLen + 1 else { return nil }
        var best: (Int, Int, Float)? = nil
        let center = Float(na) / 2, centerB = Float(nb) / 2
        for i in 0..<(na - matchLen) {
            for j in 0..<(nb - matchLen) {
                var c: Float = 0
                for k in 0..<matchLen {
                    let ia = (i + k) * ch, jb = (j + k) * ch
                    for c0 in 0..<ch { let d = a[ia + c0] - b[jb + c0]; c += d * d }
                }
                // 同样连续时，尽量少挪动（离原位置越近越好）
                c += 1e-9 * (abs(Float(i) - center) + abs(Float(j) - centerB))
                if best == nil || c < best!.2 { best = (i, j, c) }
            }
        }
        return best
    }

    /// 接缝跳变：B 截断前最后一个采样 → A 第一个采样，逐声道最大差（和自然相邻差同量纲，用来出报告）
    public static func seamJump(a: [Float], b: [Float], channels ch: Int, i: Int, j: Int) -> Float {
        guard j >= 1, (i + 1) * ch <= a.count, j * ch <= b.count else { return 0 }
        var m: Float = 0
        for c0 in 0..<ch { m = max(m, abs(a[i * ch + c0] - b[(j - 1) * ch + c0])) }
        return m
    }
}

extension TimeFormat {
    /// 精确到毫秒：“01:23.456” / “1:02:03.500”
    public static func precise(_ seconds: Double?) -> String {
        guard let s0 = seconds, s0.isFinite, s0 >= 0 else { return "--:--.---" }
        let ms = Int((s0 * 1000).rounded())
        let h = ms / 3_600_000, m = (ms / 60_000) % 60, s = (ms / 1000) % 60, r = ms % 1000
        return h > 0 ? String(format: "%d:%02d:%02d.%03d", h, m, s, r) : String(format: "%02d:%02d.%03d", m, s, r)
    }
}

/// 一次接缝对齐的结果：mpv 实际用的 A/B、各挪了多少毫秒、接缝跳变（对齐前 → 对齐后）
public struct LoopSeamResult: Equatable, Sendable {
    public var a: Double, b: Double, shiftA: Double, shiftB: Double, jumpBefore: Double, jumpAfter: Double
    public init(a: Double, b: Double, shiftA: Double, shiftB: Double, jumpBefore: Double, jumpAfter: Double) {
        self.a = a; self.b = b; self.shiftA = shiftA; self.shiftB = shiftB; self.jumpBefore = jumpBefore; self.jumpAfter = jumpAfter
    }
}
