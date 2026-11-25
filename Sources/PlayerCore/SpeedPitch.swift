// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 变速与变调（互不影响）。
/// 变速：mpv 的 speed（音频由 scaletempo2 保持音高，视频同步变速），步长 1%。
/// 变调：MPVKit 的 FFmpeg 没编 rubberband，所以用 lavfi 链「先统一到 48 kHz → asetrate 把采样率标成 48k×r（音高×r、时长÷r）
/// → 重采样回 48k → atempo 1/r 把时长拉回」，结果只改音高、不改速度和音画同步。范围 ±12 半音，音分 ±50。
public enum SpeedPitch {
    public static let speedRange: ClosedRange<Double> = 0.25...4.0
    public static let semitoneRange: ClosedRange<Int> = -12...12
    public static let centsRange: ClosedRange<Int> = -50...50
    public static let label = "tancopitch"

    /// 速度对齐到 1% 并限制范围
    public static func clampSpeed(_ s: Double) -> Double {
        min(speedRange.upperBound, max(speedRange.lowerBound, (s * 100).rounded() / 100))
    }
    public static func ratio(semitones: Int, cents: Int) -> Double {
        pow(2, Double(semitones) / 12 + Double(cents) / 1200)
    }
    /// mpv af 里的一段（无变调时返回 nil）
    public static func filter(semitones: Int, cents: Int) -> String? {
        guard semitones != 0 || cents != 0 else { return nil }
        let r = ratio(semitones: semitones, cents: cents)
        let rate = Int((48000 * r).rounded())
        let tempo = 48000.0 / Double(rate)     // 用取整后的实际采样率反推，时长严格不变
        return "@\(label):lavfi=[aresample=48000,asetrate=\(rate),aresample=48000,atempo=\(String(format: "%.8f", tempo))]"
    }
    public static func speedText(_ s: Double) -> String { String(format: "%d%%", Int((s * 100).rounded())) }
    public static func pitchText(semitones: Int, cents: Int) -> String {
        if semitones == 0 && cents == 0 { return "原调" }
        var t = semitones == 0 ? "" : String(format: "%+d 半音", semitones)
        if cents != 0 { t += (t.isEmpty ? "" : " ") + String(format: "%+d 音分", cents) }
        return t
    }
}
