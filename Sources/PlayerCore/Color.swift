// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 线性无关的小颜色库：sRGB ↔ OKLab/OKLCH。配色在 OKLab 里做，过渡才“柔”、不发脏。
public struct RGB: Codable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double   // 0…1 sRGB（非线性）
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
    public var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
    public var clamped: RGB { RGB(min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1)) }
    /// 相对亮度（WCAG）
    public var luminance: Double {
        func l(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * l(r) + 0.7152 * l(g) + 0.0722 * l(b)
    }
}

public struct OKLab: Hashable, Sendable {
    public var L: Double, a: Double, b: Double
    public init(L: Double, a: Double, b: Double) { self.L = L; self.a = a; self.b = b }

    public init(_ c: RGB) {
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let r: Double = lin(c.r), g: Double = lin(c.g), b: Double = lin(c.b)
        let l: Double = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m: Double = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s: Double = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        self.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    public var rgb: RGB {
        let l_: Double = L + 0.3963377774 * a + 0.2158037573 * b
        let m_: Double = L - 0.1055613458 * a - 0.0638541728 * b
        let s_: Double = L - 0.0894841775 * a - 1.2914855480 * b
        let l: Double = l_ * l_ * l_, m: Double = m_ * m_ * m_, s: Double = s_ * s_ * s_
        func gam(_ x: Double) -> Double { x <= 0.0031308 ? 12.92 * x : 1.055 * pow(max(x, 0), 1 / 2.4) - 0.055 }
        return RGB(gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                   gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                   gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)).clamped
    }

    public var chroma: Double { (a * a + b * b).squareRoot() }
    public var hue: Double { atan2(b, a) }

    public static func lch(L: Double, C: Double, h: Double) -> OKLab { OKLab(L: L, a: C * cos(h), b: C * sin(h)) }

    public func mix(_ o: OKLab, _ t: Double) -> OKLab {
        OKLab(L: L + (o.L - L) * t, a: a + (o.a - a) * t, b: b + (o.b - b) * t)
    }
    public func distance(_ o: OKLab) -> Double {
        let dl = L - o.L, da = a - o.a, db = b - o.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}

/// 背景氛围色：从封面取色后“驯化”成低饱和、柔和的三色渐变。
public struct AmbientPalette: Codable, Hashable, Sendable {
    public var primary: RGB
    public var secondary: RGB
    public var tertiary: RGB
    /// 卡片玻璃上的提示色（更浅一点）
    public var glassTint: RGB
    /// 强调色（进度条、均衡器高光），比背景鲜一点但仍克制
    public var accent: RGB

    public init(primary: RGB, secondary: RGB, tertiary: RGB, glassTint: RGB, accent: RGB) {
        self.primary = primary; self.secondary = secondary; self.tertiary = tertiary
        self.glassTint = glassTint; self.accent = accent
    }

    public static let fallback = AmbientPalette(
        primary: RGB(hex: 0x2E2A4A), secondary: RGB(hex: 0x5C5490), tertiary: RGB(hex: 0x9A8CC8),
        glassTint: RGB(hex: 0xC9C2EA), accent: RGB(hex: 0xC8BCFF))

    /// - Parameters:
    ///   - rgba: 8bit RGBA 像素（建议先缩到 48×48 左右）
    public static func extract(rgba: [UInt8], width: Int, height: Int) -> AmbientPalette {
        var samples: [OKLab] = []
        samples.reserveCapacity(width * height)
        var i = 0
        while i + 3 < rgba.count {
            let a = Double(rgba[i + 3]) / 255
            if a > 0.5 {
                samples.append(OKLab(RGB(Double(rgba[i]) / 255, Double(rgba[i + 1]) / 255, Double(rgba[i + 2]) / 255)))
            }
            i += 4
        }
        guard samples.count >= 8 else { return .fallback }
        let clusters = KMeans.run(samples, k: 5, iterations: 10)
        // 打分：人口占比 × (0.35 + 彩度)，排除接近纯黑/纯白的簇
        let scored: [(OKLab, Double)] = clusters.map { c -> (OKLab, Double) in
            let pop = Double(c.count) / Double(samples.count)
            let edgePenalty = (c.center.L < 0.12 || c.center.L > 0.95) ? 0.25 : 1
            return (c.center, pop * (0.35 + min(c.center.chroma, 0.2) * 4) * edgePenalty)
        }.sorted { $0.1 > $1.1 }
        let main: OKLab = scored[0].0
        // 第二色要与主色有差别
        let second: OKLab = scored.dropFirst().first { $0.0.distance(main) > 0.08 }?.0 ?? main.mix(OKLab.lch(L: main.L, C: main.chroma, h: main.hue + 0.6), 0.6)
        let third: OKLab = scored.dropFirst().first { $0.0.distance(main) > 0.08 && $0.0.distance(second) > 0.06 }?.0 ?? second.mix(main, 0.5)

        func tame(_ c: OKLab, L lo: Double, _ hi: Double, maxC: Double) -> OKLab {
            let C = min(c.chroma, maxC) * 0.92
            let L = min(max(c.L, lo), hi)
            return .lch(L: L, C: C, h: c.hue)
        }
        let p: OKLab = tame(main, L: 0.26, 0.40, maxC: 0.075)
        let s: OKLab = tame(second, L: 0.40, 0.56, maxC: 0.090)
        let t: OKLab = tame(third, L: 0.56, 0.70, maxC: 0.085)
        let glass: OKLab = tame(main.mix(OKLab(L: 0.92, a: 0, b: 0), 0.55), L: 0.78, 0.90, maxC: 0.05)
        let accent: OKLab = tame(scored.max { $0.0.chroma < $1.0.chroma }!.0, L: 0.78, 0.86, maxC: 0.12)
        return AmbientPalette(primary: p.rgb, secondary: s.rgb, tertiary: t.rgb, glassTint: glass.rgb, accent: accent.rgb)
    }

    /// 宣传片同款「三色块大尺度柔光漫射」提亮转换：
    /// 避免旧版 maxC=0.075 在中低明度下把暖色压成「猪肝色/脏泥灰」、把冷色压成「死铅灰」。
    /// 通过拉升明度梯度（L: 0.36 → 0.58 → 0.76）、恢复通透彩度（C: 0.13 → 0.17）并拉开 32° 邻近色相偏转，
    /// 生成通透、发光、无脏灰感的流体柔光三色块。
    public var softLight: AmbientPalette {
        let lp = OKLab(primary), ls = OKLab(secondary), lt = OKLab(tertiary), la = OKLab(accent)
        let baseH = lp.hue
        let secH = abs(ls.hue - baseH) > 0.18 ? ls.hue : (baseH + 0.48)
        let terH = abs(lt.hue - secH) > 0.18 ? lt.hue : (baseH + 0.92)
        let p = OKLab.lch(L: max(0.32, min(0.46, lp.L * 1.12)), C: max(0.11, min(0.16, lp.chroma * 1.65)), h: baseH)
        let s = OKLab.lch(L: max(0.52, min(0.68, ls.L * 1.18)), C: max(0.14, min(0.19, ls.chroma * 1.75)), h: secH)
        let t = OKLab.lch(L: max(0.68, min(0.82, lt.L * 1.16)), C: max(0.13, min(0.18, lt.chroma * 1.70)), h: terH)
        let ac = OKLab.lch(L: max(0.78, min(0.88, la.L)), C: max(0.14, min(0.20, la.chroma * 1.45)), h: la.hue)
        return AmbientPalette(primary: p.rgb, secondary: s.rgb, tertiary: t.rgb, glassTint: glassTint, accent: ac.rgb)
    }
}

enum KMeans {
    struct Cluster { var center: OKLab; var count: Int }
    static func run(_ xs: [OKLab], k: Int, iterations: Int) -> [Cluster] {
        // k-means++ 的确定性版本：按亮度排序后等距取初值，保证同一张图结果稳定
        let sorted: [OKLab] = xs.sorted { $0.L < $1.L }
        var centers: [OKLab] = (0..<k).map { sorted[min(sorted.count - 1, ($0 * 2 + 1) * sorted.count / (2 * k))] }
        var counts = [Int](repeating: 0, count: k)
        for _ in 0..<iterations {
            var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: k)
            counts = [Int](repeating: 0, count: k)
            for x in xs {
                var best = 0, bd = Double.infinity
                for (j, c) in centers.enumerated() {
                    let d = x.distance(c)
                    if d < bd { bd = d; best = j }
                }
                sums[best].0 += x.L; sums[best].1 += x.a; sums[best].2 += x.b
                counts[best] += 1
            }
            for j in 0..<k where counts[j] > 0 {
                let n = Double(counts[j])
                centers[j] = OKLab(L: sums[j].0 / n, a: sums[j].1 / n, b: sums[j].2 / n)
            }
        }
        return (0..<k).compactMap { counts[$0] > 0 ? Cluster(center: centers[$0], count: counts[$0]) : nil }
    }
}
