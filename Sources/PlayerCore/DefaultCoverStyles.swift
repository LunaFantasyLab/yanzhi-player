// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 默认封面的「风格」（2026-11-19）：同一套调色板、同一个种子，画法完全不同。
/// 0 号「柔光玻璃」是原来那一套（参数和 Python 样图逐位一致，不改）；1–9 号是新加的。
/// 分配：每首歌按种子哈希出一个风格偏好顺序（固定不变）；放进歌单时，若和上一首（不同专辑）撞了同一风格，
/// 就顺延到它自己偏好里的下一个——所以同一歌单、同一顺序下每次都一样，相邻两首不会重样。
public enum DefaultCoverStyle: Int, CaseIterable, Codable, Sendable {
    case softGlass = 0      // 柔光玻璃：三团柔光 + 一个玻璃母题（原有）
    case mesh = 1           // 流光：网格渐变，丝绸般的大色面
    case bauhaus = 2        // 几何：包豪斯色块 + 一枚玻璃透镜
    case contour = 3        // 等高线：细线地形图
    case bokeh = 4          // 光斑：失焦的光点
    case fluted = 5         // 棱镜：竖条纹玻璃折射后面的色彩
    case grain = 6          // 颗粒：双色径向渐变 + 粗颗粒（孔版印刷感）
    case orbit = 7          // 轨道：极简细线椭圆与小圆点
    case swiss = 8          // 网格：瑞士风格圆角色块阵列
    case monogram = 9       // 字标：对角分色底 + 巨大的首字（文字由 App 叠加）
    case vinyl = 10         // 黑胶：微纹黑胶唱片 + 彩色唱标 + 复古丝光反光
    case wave = 11          // 声波：多层彩虹合成器丝带声浪
    case stainedGlass = 12  // 琉璃花窗：宝石切面多边形马赛克彩窗
    case retroSun = 13      // 落日蒸汽波：横切复古落日 + 湖面波光倒影
    case memphis = 14       // 波普孟菲斯：趣致几何贴纸、波浪折线与胶囊彩屑
    case ripple = 15        // 水墨涟漪：多波源谐振光纹干涉波场
    case prismBurst = 16    // 万花棱光：晶体棱镜色散放射光芒
    case checkerWarp = 17   // 迷幻棋盘：流体漩涡双曲扭曲波普棋盘

    public var name: String {
        [
            "柔光玻璃", "流光", "几何", "等高线", "光斑",
            "棱镜", "颗粒", "轨道", "网格", "字标",
            "黑胶", "声波", "琉璃花窗", "落日", "孟菲斯",
            "涟漪", "万花棱光", "迷幻棋盘",
        ][rawValue]
    }
    /// 浅底风格：文字用深色
    public func isLight(_ spec: DefaultCoverSpec) -> Bool {
        switch self {
        case .bauhaus: return true
        case .swiss, .orbit, .monogram, .memphis, .checkerWarp: return spec.hash >> 60 & 1 == 0
        default: return false
        }
    }

    /// 这首歌自己的风格偏好顺序（由种子哈希决定，永远不变）
    public static func preference(seed: String) -> [DefaultCoverStyle] {
        var rng = SplitMix64(state: DefaultCoverSpec.fnv1a64("style|" + seed))
        var all = Array(allCases)
        for i in stride(from: all.count - 1, to: 0, by: -1) { all.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        return all
    }

    /// 给一个歌单（按顺序的种子）分配风格：相邻且种子不同的两首不重样；种子相同（同一张专辑）保持同一张图
    public static func assign(seeds: [String]) -> [DefaultCoverStyle] {
        var out: [DefaultCoverStyle] = []
        out.reserveCapacity(seeds.count)
        for (i, s) in seeds.enumerated() {
            let pref = preference(seed: s)
            if i > 0, seeds[i - 1] == s { out.append(out[i - 1]); continue }
            let prev = i > 0 ? out[i - 1] : nil
            out.append(pref.first { $0 != prev } ?? pref[0])
        }
        return out
    }
}

extension DefaultCoverRenderer {
    /// 按风格渲染（RGBA8，不含文字）
    public static func render(_ spec: DefaultCoverSpec, style: DefaultCoverStyle, size n: Int) -> [UInt8] {
        if style == .softGlass { return render(spec, size: n) }
        var c = Canvas(n: n, spec: spec)
        switch style {
        case .softGlass: break
        case .mesh: c.mesh()
        case .bauhaus: c.bauhaus()
        case .contour: c.contour()
        case .bokeh: c.bokeh()
        case .fluted: c.fluted()
        case .grain: c.grainDuotone()
        case .orbit: c.orbit(light: style.isLight(spec))
        case .swiss: c.swiss(light: style.isLight(spec))
        case .monogram: c.monogram(light: style.isLight(spec))
        case .vinyl: c.vinyl()
        case .wave: c.wave()
        case .stainedGlass: c.stainedGlass()
        case .retroSun: c.retroSun()
        case .memphis: c.memphis(light: style.isLight(spec))
        case .ripple: c.ripple()
        case .prismBurst: c.prismBurst()
        case .checkerWarp: c.checkerWarp(light: style.isLight(spec))
        }
        return c.finish(grain: style == .grain ? 0.045 : (style == .retroSun || style == .vinyl ? 0.016 : 0.010),
                        vignette: style.isLight(spec) ? 0.07 : 0.20)
    }
}

/// OKLab 画布：所有风格共用的小工具（抗锯齿形状、混色、局部模糊做玻璃）
struct Canvas {
    let n: Int
    let spec: DefaultCoverSpec
    var L: [Double], A: [Double], B: [Double]
    var rng: SplitMix64
    let px: Double
    let pal: [OKLab]      // base, a, b, c

    init(n: Int, spec: DefaultCoverSpec) {
        self.n = n; self.spec = spec
        L = .init(repeating: 0, count: n * n); A = L; B = L
        rng = SplitMix64(state: spec.hash ^ 0x5EED_C0DE)
        px = 1 / Double(n)
        let p = spec.richPalette
        pal = [OKLab(RGB(hex: p.base)), OKLab(RGB(hex: p.a)), OKLab(RGB(hex: p.b)), OKLab(RGB(hex: p.c))]
    }

    // MARK: 基础
    @inline(__always) func uv(_ i: Int) -> (Double, Double) { ((Double(i % n) + 0.5) * px, (Double(i / n) + 0.5) * px) }
    @inline(__always) func aa(_ sdf: Double, soft: Double = 1) -> Double { min(max(0.5 - sdf / (px * soft), 0), 1) }
    mutating func put(_ i: Int, _ c: OKLab, _ t: Double) {
        guard t > 0 else { return }
        let k = min(t, 1)
        L[i] += (c.L - L[i]) * k; A[i] += (c.a - A[i]) * k; B[i] += (c.b - B[i]) * k
    }
    mutating func fill(_ f: @Sendable (Double, Double) -> OKLab) {
        let n = self.n, px = self.px
        L.withUnsafeMutableBufferPointer { lBuf in
            A.withUnsafeMutableBufferPointer { aBuf in
                B.withUnsafeMutableBufferPointer { bBuf in
                    let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
                    let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                    let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                    FastSRGB.parallelRows(n) { y in
                        let v = (Double(y) + 0.5) * px
                        let row = y * n
                        for x in 0..<n {
                            let u = (Double(x) + 0.5) * px
                            let c = f(u, v)
                            let i = row + x
                            lp.base[i] = c.L; ap.base[i] = c.a; bp.base[i] = c.b
                        }
                    }
                }
            }
        }
    }
    /// 形状：对每个像素给出 sdf（<0 在里面），按抗锯齿覆盖率混色
    mutating func shape(_ color: OKLab, alpha: Double = 1, soft: Double = 1, _ sdf: @Sendable (Double, Double) -> Double) {
        let n = self.n, px = self.px
        let cutoff = px * soft * 2
        L.withUnsafeMutableBufferPointer { lBuf in
            A.withUnsafeMutableBufferPointer { aBuf in
                B.withUnsafeMutableBufferPointer { bBuf in
                    let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
                    let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                    let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                    FastSRGB.parallelRows(n) { y in
                        let v = (Double(y) + 0.5) * px
                        let row = y * n
                        for x in 0..<n {
                            let u = (Double(x) + 0.5) * px
                            let d = sdf(u, v)
                            if d < cutoff {
                                let t = min(max(0.5 - d / (px * soft), 0), 1) * alpha
                                if t > 0 {
                                    let k = min(t, 1)
                                    let i = row + x
                                    lp.base[i] += (color.L - lp.base[i]) * k
                                    ap.base[i] += (color.a - ap.base[i]) * k
                                    bp.base[i] += (color.b - bp.base[i]) * k
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func tone(_ c: OKLab, L l: Double, chroma k: Double = 1) -> OKLab { OKLab(L: l, a: c.a * k, b: c.b * k) }
    mutating func unit() -> Double { rng.unit() }

    static func disk(_ u: Double, _ v: Double, _ x: Double, _ y: Double, _ r: Double) -> Double { ((u - x) * (u - x) + (v - y) * (v - y)).squareRoot() - r }
    static func rrect(_ u: Double, _ v: Double, _ x: Double, _ y: Double, _ hw: Double, _ hh: Double, _ rad: Double) -> Double {
        let qx = abs(u - x) - hw + rad, qy = abs(v - y) - hh + rad
        return (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot() + min(max(qx, qy), 0) - rad
    }

    /// 玻璃片：区域内模糊 + 提亮 + 去饱和，边缘一道细亮线、下方淡阴影（多核并行，4K 极速）
    mutating func glass(lift: Double = 0.05, blur r: Int? = nil, edge: Double = 0.12, shadow: Double = 0.05, _ sdf: @Sendable (Double, Double) -> Double) {
        let rad = r ?? max(2, n / 45)
        let bl = Self.boxBlur(L, n: n, r: rad), ba = Self.boxBlur(A, n: n, r: rad), bb = Self.boxBlur(B, n: n, r: rad)
        let n = self.n, px = self.px
        L.withUnsafeMutableBufferPointer { lBuf in
            A.withUnsafeMutableBufferPointer { aBuf in
                B.withUnsafeMutableBufferPointer { bBuf in
                    bl.withUnsafeBufferPointer { blBuf in
                        ba.withUnsafeBufferPointer { baBuf in
                            bb.withUnsafeBufferPointer { bbBuf in
                                let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
                                let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                                let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                                let blp = UnsafeConstPtr(base: blBuf.baseAddress!)
                                let bap = UnsafeConstPtr(base: baBuf.baseAddress!)
                                let bbp = UnsafeConstPtr(base: bbBuf.baseAddress!)
                                FastSRGB.parallelRows(n) { y in
                                    let v = (Double(y) + 0.5) * px
                                    let row = y * n
                                    for x in 0..<n {
                                        let u = (Double(x) + 0.5) * px
                                        let d = sdf(u, v)
                                        if d > 0.08 { continue }
                                        let i = row + x
                                        let aac = min(max(0.5 - d / px, 0), 1)
                                        if d > 0 {
                                            let ds = sdf(u, v - 0.012)
                                            lp.base[i] -= shadow * exp(-max(ds, 0) / 0.035) * (ds < 0 ? 1 : 0.6) * (1 - aac)
                                            continue
                                        }
                                        let k = min(max(0.5 - (v - 0.5) * 0.9, 0), 1)
                                        let blend = min(aac * 0.95, 1)
                                        let gl = blp.base[i] + lift + 0.03 * k
                                        let ga = bap.base[i] * 0.86
                                        let gb = bbp.base[i] * 0.86
                                        lp.base[i] += (gl - lp.base[i]) * blend
                                        ap.base[i] += (ga - ap.base[i]) * blend
                                        bp.base[i] += (gb - bp.base[i]) * blend
                                        let z = (d + px * 0.8) / (px * 1.8)
                                        lp.base[i] += exp(-(z * z)) * edge
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    static func boxBlur(_ src: [Double], n: Int, r: Int) -> [Double] {
        var a = src, b = src
        for _ in 0..<3 {
            // 横向（按行并行）
            a.withUnsafeBufferPointer { aBuf in
                b.withUnsafeMutableBufferPointer { bBuf in
                    let ap = UnsafeConstPtr(base: aBuf.baseAddress!)
                    let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                    FastSRGB.parallelRows(n) { y in
                        let row = y * n
                        var acc = 0.0, cnt = 0.0
                        let hi0 = min(r, n - 1)
                        for x in 0...hi0 { acc += ap.base[row + x]; cnt += 1 }
                        for x in 0..<n {
                            bp.base[row + x] = acc / cnt
                            let xo = x - r, xi = x + r + 1
                            if xo >= 0 { acc -= ap.base[row + xo]; cnt -= 1 }
                            if xi < n { acc += ap.base[row + xi]; cnt += 1 }
                        }
                    }
                }
            }
            // 纵向（按列并行）
            b.withUnsafeBufferPointer { bBuf in
                a.withUnsafeMutableBufferPointer { aBuf in
                    let bp = UnsafeConstPtr(base: bBuf.baseAddress!)
                    let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                    FastSRGB.parallelRows(n) { x in
                        var acc = 0.0, cnt = 0.0
                        let hi0 = min(r, n - 1)
                        for y in 0...hi0 { acc += bp.base[y * n + x]; cnt += 1 }
                        for y in 0..<n {
                            ap.base[y * n + x] = acc / cnt
                            let yo = y - r, yi = y + r + 1
                            if yo >= 0 { acc -= bp.base[yo * n + x]; cnt -= 1 }
                            if yi < n { acc += bp.base[yi * n + x]; cnt += 1 }
                        }
                    }
                }
            }
        }
        return a
    }

    /// 收尾：暗角 + 颗粒 → RGBA8（多核并行 + 快速 gamma LUT）
    mutating func finish(grain: Double, vignette: Double) -> [UInt8] {
        let n = self.n, px = self.px
        let grainBase = UInt64(spec.grainSeed) | 1
        var out = [UInt8](repeating: 255, count: n * n * 4)
        L.withUnsafeBufferPointer { lBuf in
            A.withUnsafeBufferPointer { aBuf in
                B.withUnsafeBufferPointer { bBuf in
                    out.withUnsafeMutableBufferPointer { oBuf in
                        let lp = UnsafeConstPtr(base: lBuf.baseAddress!)
                        let ap = UnsafeConstPtr(base: aBuf.baseAddress!)
                        let bp = UnsafeConstPtr(base: bBuf.baseAddress!)
                        let op = UnsafeRowPtr(base: oBuf.baseAddress!)
                        FastSRGB.parallelRows(n) { y in
                            var g = SplitMix64(state: grainBase ^ (UInt64(y) &+ 1) &* 0x9E3779B97F4A7C15)
                            let v = (Double(y) + 0.5) * px
                            let dv2 = (v - 0.5) * (v - 0.5)
                            let row = y * n
                            for x in 0..<n {
                                let u = (Double(x) + 0.5) * px
                                let i = row + x
                                let r2 = (u - 0.5) * (u - 0.5) + dv2
                                var l = lp.base[i] * (1 - vignette * DefaultCoverRenderer.smoothstep(0.12, 0.62, r2))
                                l += (g.unit() + g.unit() + g.unit() - 1.5) * 2 * grain
                                let (r, gr, bl) = FastSRGB.oklabToRGBA(l, ap.base[i], bp.base[i])
                                let o = i * 4
                                op.base[o] = r; op.base[o + 1] = gr; op.base[o + 2] = bl
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: 1 流光（网格渐变）
    mutating func mesh() {
        let base = pal[0], a = pal[1], b = pal[2], c = pal[3]
        let pts: [(Double, Double, OKLab)] = [
            (0.1 + unit() * 0.3, 0.05 + unit() * 0.3, tone(a, L: 0.72, chroma: 1.6)),
            (0.6 + unit() * 0.35, 0.1 + unit() * 0.3, tone(b, L: 0.86, chroma: 1.1)),
            (0.55 + unit() * 0.4, 0.6 + unit() * 0.35, tone(c, L: 0.54, chroma: 1.7)),
            (0.05 + unit() * 0.35, 0.6 + unit() * 0.35, tone(base, L: 0.34, chroma: 1.6)),
            (0.35 + unit() * 0.3, 0.35 + unit() * 0.3, tone(a.mix(b, 0.5), L: 0.80, chroma: 1.5)),
        ]
        let f1 = 2 + unit() * 2, f2 = 2 + unit() * 2, ph = unit() * 6.28
        fill { u, v in
            let wu = u + 0.07 * sin(v * f1 * .pi + ph), wv = v + 0.07 * sin(u * f2 * .pi + ph * 0.7)
            var wl = 0.0, l = 0.0, aa = 0.0, bb = 0.0
            for (x, y, col) in pts {
                let d2 = (wu - x) * (wu - x) + (wv - y) * (wv - y)
                let w = 1 / pow(d2 + 0.004, 1.6)
                wl += w; l += col.L * w; aa += col.a * w; bb += col.b * w
            }
            return OKLab(L: l / wl, a: aa / wl, b: bb / wl)
        }
        // 一道斜向丝光（按行并行）
        let ang = unit() * .pi
        let ca = cos(ang), sa = sin(ang), off = unit() * 0.3 - 0.15
        let n = self.n, px = self.px
        L.withUnsafeMutableBufferPointer { lBuf in
            let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
            FastSRGB.parallelRows(n) { y in
                let v = (Double(y) + 0.5) * px, row = y * n
                for x in 0..<n {
                    let u = (Double(x) + 0.5) * px
                    let t = (u - 0.5) * ca + (v - 0.5) * sa - off
                    lp.base[row + x] += 0.05 * exp(-t * t / 0.004)
                }
            }
        }
    }

    // MARK: 2 几何（包豪斯）
    mutating func bauhaus() {
        let paper = OKLab(L: 0.93, a: pal[2].a * 0.25, b: pal[2].b * 0.25 + 0.006)
        fill { _, _ in paper }
        let ink = tone(pal[0], L: 0.26, chroma: 1.4)
        let cols = [tone(pal[1], L: 0.66, chroma: 1.5), tone(pal[3], L: 0.5, chroma: 1.5), ink, tone(pal[2], L: 0.80, chroma: 1.6)]
        let grid = 3
        let m = 0.07, cell = (1 - 2 * m) / Double(grid)
        for gy in 0..<grid {
            for gx in 0..<grid {
                let x0 = m + Double(gx) * cell, y0 = m + Double(gy) * cell
                let col = cols[Int(rng.next() % 4)]
                let kind = Int(rng.next() % 6)
                let corner = Int(rng.next() % 4)
                let cx = x0 + (corner % 2 == 0 ? 0 : cell), cy = y0 + (corner / 2 == 0 ? 0 : cell)
                let inset = cell * 0.04
                switch kind {
                case 0: // 四分之一圆
                    shape(col) { u, v in max(Self.disk(u, v, cx, cy, cell - inset), Self.rrect(u, v, x0 + cell / 2, y0 + cell / 2, cell / 2 - inset, cell / 2 - inset, 0)) }
                case 1: // 整圆
                    shape(col) { u, v in Self.disk(u, v, x0 + cell / 2, y0 + cell / 2, cell / 2 - inset * 2) }
                case 2: // 半圆
                    let horiz = corner % 2 == 0
                    shape(col) { u, v in
                        max(Self.disk(u, v, x0 + cell / 2, horiz ? y0 + cell - inset : y0 + cell / 2, cell / 2 - inset),
                            horiz ? (v - (y0 + cell - inset)) : (u - (x0 + cell / 2)))
                    }
                case 3: // 实心方块
                    shape(col) { u, v in Self.rrect(u, v, x0 + cell / 2, y0 + cell / 2, cell / 2 - inset, cell / 2 - inset, cell * 0.02) }
                case 4: // 三角
                    shape(col) { u, v in
                        let lu = (u - x0) / cell, lv = (v - y0) / cell
                        let half = (corner % 2 == 0 ? (lu + lv - 1) : (lv - lu)) * cell * 0.7
                        return max(half, Self.rrect(u, v, x0 + cell / 2, y0 + cell / 2, cell / 2 - inset, cell / 2 - inset, 0))
                    }
                default: // 细环
                    shape(col) { u, v in abs(Self.disk(u, v, x0 + cell / 2, y0 + cell / 2, cell * 0.32)) - cell * 0.05 }
                }
            }
        }
        // 一枚玻璃透镜压在两格之间
        let lx = m + cell * Double(1 + Int(rng.next() % 2)), ly = m + cell * Double(1 + Int(rng.next() % 2))
        glass(lift: 0.03, edge: 0.10, shadow: 0.06) { u, v in Self.disk(u, v, lx, ly, cell * 0.55) }
    }

    // MARK: 3 等高线（多核并行 4K 极速）
    mutating func contour() {
        let base = tone(pal[0], L: 0.20, chroma: 1.2)
        fill { _, v in OKLab(L: base.L + 0.04 * (1 - v), a: base.a, b: base.b) }
        let blobs = spec.blobs
        let fq = 9 + unit() * 6, ph = unit() * 6
        let n = self.n, px = self.px
        var F = [Double](repeating: 0, count: n * n)
        F.withUnsafeMutableBufferPointer { fBuf in
            let fp = UnsafeRowPtr(base: fBuf.baseAddress!)
            FastSRGB.parallelRows(n) { y in
                let v = (Double(y) + 0.5) * px, row = y * n
                for x in 0..<n {
                    let u = (Double(x) + 0.5) * px
                    var f = 0.0
                    for (k, bl) in blobs.enumerated() {
                        let d2 = ((u - bl.x) * (u - bl.x) + (v - bl.y) * (v - bl.y)) / (bl.r * bl.r * 0.35)
                        f += exp(-d2) * (k == 1 ? -0.7 : 1)
                    }
                    fp.base[row + x] = (f + 0.08 * sin(u * 7 + ph) * cos(v * 5 - ph)) * fq
                }
            }
        }
        let lineA = tone(pal[1], L: 0.78, chroma: 1.3), lineB = tone(pal[2], L: 0.90, chroma: 1.1)
        let lineScale = max(1.0, Double(n) / 1024.0)
        F.withUnsafeBufferPointer { fBuf in
            L.withUnsafeMutableBufferPointer { lBuf in
                A.withUnsafeMutableBufferPointer { aBuf in
                    B.withUnsafeMutableBufferPointer { bBuf in
                        let fp = UnsafeConstPtr(base: fBuf.baseAddress!)
                        let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
                        let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                        let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                        FastSRGB.parallelRows(n - 2) { y0 in
                            let y = y0 + 1
                            let v = (Double(y) + 0.5) * px, row = y * n
                            let col = lineA.mix(lineB, v)
                            for x in 1..<(n - 1) {
                                let i = row + x
                                let gx = (fp.base[i + 1] - fp.base[i - 1]) * 0.5
                                let gy = (fp.base[i + n] - fp.base[i - n]) * 0.5
                                let g = max((gx * gx + gy * gy).squareRoot(), 1e-6)
                                let fv = fp.base[i]
                                let fr = fv - fv.rounded()
                                let dpx = abs(fr) / g
                                let major = Int(fv.rounded()) % 5 == 0
                                let w = (major ? 1.4 : 0.8) * lineScale
                                let cov = min(max(w + 0.5 - dpx, 0), 1)
                                if cov > 0 {
                                    let k = min(cov * (major ? 0.95 : 0.62), 1)
                                    lp.base[i] += (col.L - lp.base[i]) * k
                                    ap.base[i] += (col.a - ap.base[i]) * k
                                    bp.base[i] += (col.b - bp.base[i]) * k
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 4 光斑
    mutating func bokeh() {
        let base = tone(pal[0], L: 0.16, chroma: 1.3), top = tone(pal[3], L: 0.30, chroma: 1.2)
        let ang = spec.angle * .pi / 180
        fill { u, v in
            let t = min(max(((u - 0.5) * cos(ang) + (v - 0.5) * sin(ang)) + 0.5, 0), 1)
            return base.mix(top, t * 0.8)
        }
        let cols = [pal[1], pal[2], pal[3], pal[1].mix(pal[2], 0.5)]
        let count = 26 + Int(rng.next() % 12)
        // 远处的小光点先画，近处的大光斑后画
        var spots: [(Double, Double, Double, Int, Double)] = []
        for _ in 0..<count {
            let r = 0.02 + pow(unit(), 2.2) * 0.16
            spots.append((unit() * 1.1 - 0.05, unit() * 1.1 - 0.05, r, Int(rng.next() % 4), 0.25 + unit() * 0.5))
        }
        spots.sort { $0.2 < $1.2 }
        for (x, y, r, ci, a) in spots {
            let col = tone(cols[ci], L: 0.82, chroma: 1.35)
            let soft = 1 + r * 60          // 越大越虚
            let reach = r + px * soft * 2.2
            let x0 = max(0, Int(floor((x - reach) * Double(n))))
            let x1 = min(n - 1, Int(ceil((x + reach) * Double(n))))
            let y0 = max(0, Int(floor((y - reach) * Double(n))))
            let y1 = min(n - 1, Int(ceil((y + reach) * Double(n))))
            guard x0 <= x1, y0 <= y1 else { continue }
            let cutoff = px * soft * 2
            let invSoft = 1.0 / (px * soft)
            let invRim = 1.0 / (px * soft * 0.9)
            let rimShift = px * soft * 0.6
            for py in y0...y1 {
                let v = (Double(py) + 0.5) * px
                let dv2 = (v - y) * (v - y)
                let row = py * n
                for pxIdx in x0...x1 {
                    let u = (Double(pxIdx) + 0.5) * px
                    let d = ((u - x) * (u - x) + dv2).squareRoot() - r
                    if d > cutoff { continue }
                    let cov = min(max(0.5 - d * invSoft, 0), 1)
                    if cov <= 0 { continue }
                    let rz = (d + rimShift) * invRim
                    let rim = exp(-(rz * rz)) * 0.25
                    let k = cov * a * 0.55
                    let i = row + pxIdx
                    L[i] += (col.L - L[i]) * k * 0.7 + rim * a * 0.25
                    A[i] += (col.a - A[i]) * k; B[i] += (col.b - B[i]) * k
                }
            }
        }
    }

    // MARK: 5 棱镜（竖条玻璃）
    mutating func fluted() {
        // 后面是一幅饱和的柔光
        let base = tone(pal[0], L: 0.28, chroma: 1.5)
        let cols = [tone(pal[1], L: 0.72, chroma: 1.5), tone(pal[2], L: 0.86, chroma: 1.3), tone(pal[3], L: 0.55, chroma: 1.6)]
        let blobs = spec.blobs
        var src = Canvas(n: n, spec: spec)
        src.fill { u, v in
            var c = base
            for k in 0..<3 {
                let bl = blobs[k]
                let d2 = ((u - bl.x) * (u - bl.x) + (v - bl.y) * (v - bl.y)) / (bl.r * bl.r * 0.55)
                c = c.mix(cols[k], exp(-d2 * 2.0))
            }
            return c
        }
        let reeds = 9 + Int(rng.next() % 7)
        let w = 1.0 / Double(reeds)
        let n = self.n, px = self.px
        src.L.withUnsafeBufferPointer { sL in
            src.A.withUnsafeBufferPointer { sA in
                src.B.withUnsafeBufferPointer { sB in
                    L.withUnsafeMutableBufferPointer { lBuf in
                        A.withUnsafeMutableBufferPointer { aBuf in
                            B.withUnsafeMutableBufferPointer { bBuf in
                                let slp = UnsafeConstPtr(base: sL.baseAddress!)
                                let sap = UnsafeConstPtr(base: sA.baseAddress!)
                                let sbp = UnsafeConstPtr(base: sB.baseAddress!)
                                let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
                                let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                                let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                                FastSRGB.parallelRows(n) { y in
                                    let sy = min(y, n - 1)
                                    let row = y * n
                                    for x in 0..<n {
                                        let u = (Double(x) + 0.5) * px
                                        let k = floor(u / w), cxr = (k + 0.5) * w
                                        let t = (u - cxr) / (w / 2)
                                        let su = cxr - (u - cxr) * 0.8 + 0.02 * t
                                        let sx = min(max(Int(su * Double(n)), 0), n - 1)
                                        let j = sy * n + sx
                                        let i = row + x
                                        let t2 = t * t
                                        let t6 = t2 * t2 * t2
                                        let hz = (t + 0.72) / 0.07
                                        lp.base[i] = slp.base[j] + 0.045 * (0.5 - t) * 0.6 - 0.05 * t6 + 0.10 * exp(-(hz * hz))
                                        ap.base[i] = sap.base[j] * 0.95
                                        bp.base[i] = sbp.base[j] * 0.95
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 6 颗粒双色
    mutating func grainDuotone() {
        let dark = tone(pal[0], L: 0.18, chroma: 1.6), hot = tone(pal[1], L: 0.74, chroma: 1.6), glow = tone(pal[2], L: 0.92, chroma: 1.2)
        let cx = 0.3 + unit() * 0.4, cy = 0.25 + unit() * 0.35, r = 0.30 + unit() * 0.14
        fill { u, v in
            let d = ((u - cx) * (u - cx) + (v - cy) * (v - cy)).squareRoot()
            let t = DefaultCoverRenderer.smoothstep(0, 0.95, d)
            var c = glow.mix(hot, DefaultCoverRenderer.smoothstep(0, r * 0.9, d))
            c = c.mix(dark, t)
            return c
        }
        // 一枚扁平的「太阳」圆片
        let sun = tone(pal[2], L: 0.95, chroma: 0.8)
        shape(sun, alpha: 0.85, soft: 1.5) { u, v in Self.disk(u, v, cx, cy, r * 0.42) }
    }

    // MARK: 7 轨道
    mutating func orbit(light: Bool) {
        let bg = light ? OKLab(L: 0.94, a: pal[2].a * 0.2, b: pal[2].b * 0.2) : tone(pal[0], L: 0.17, chroma: 1.2)
        fill { _, _ in bg }
        let lineC = light ? tone(pal[0], L: 0.35, chroma: 1.5) : tone(pal[2], L: 0.85)
        let cx = 0.5 + (unit() - 0.5) * 0.2, cy = 0.42 + (unit() - 0.5) * 0.1
        let tilt = (unit() - 0.5) * 0.9
        let rings = 4 + Int(rng.next() % 3)
        var dots: [(Double, Double, Double, OKLab)] = []
        for k in 0..<rings {
            let a = 0.12 + Double(k) * 0.075, b = a * (0.45 + unit() * 0.2)
            let ct = cos(tilt), st = sin(tilt)
            let hp = px * 0.5
            shape(lineC, alpha: k == 0 ? 0.9 : 0.55, soft: 1.1) { u, v in
                let x = (u - cx) * ct + (v - cy) * st, y = -(u - cx) * st + (v - cy) * ct
                let q = ((x / a) * (x / a) + (y / b) * (y / b)).squareRoot()
                return abs(q - 1) * min(a, b) * 0.9 - hp
            }
            let th = unit() * .pi * 2
            let px0 = cos(th) * a, py0 = sin(th) * b
            dots.append((cx + px0 * ct - py0 * st, cy + px0 * st + py0 * ct, 0.010 + unit() * 0.016, [pal[1], pal[3], pal[2]][k % 3]))
        }
        // 中心「恒星」：一枚小玻璃圆
        let star = light ? tone(pal[1], L: 0.62, chroma: 1.6) : tone(pal[1], L: 0.78, chroma: 1.5)
        shape(star) { u, v in Self.disk(u, v, cx, cy, 0.055) }
        glass(lift: 0.06, blur: max(2, n / 60), edge: 0.16, shadow: 0.0) { u, v in Self.disk(u, v, cx - 0.012, cy - 0.012, 0.06) }
        for (x, y, r, col) in dots { shape(tone(col, L: light ? 0.55 : 0.8, chroma: 1.6)) { u, v in Self.disk(u, v, x, y, r) } }
    }

    // MARK: 8 网格色块
    mutating func swiss(light: Bool) {
        let bg = light ? OKLab(L: 0.95, a: 0, b: 0.004) : tone(pal[0], L: 0.15, chroma: 1.1)
        fill { _, _ in bg }
        let g = 4, m = 0.075, gap = 0.018
        let cell = (1 - 2 * m - gap * Double(g - 1)) / Double(g)
        let ramp = [pal[1], pal[2], pal[3], pal[0]]
        let diag = unit() > 0.5
        for gy in 0..<g {
            for gx in 0..<g {
                let x = m + Double(gx) * (cell + gap) + cell / 2, y = m + Double(gy) * (cell + gap) + cell / 2
                let t = Double(diag ? gx + gy : gx + (g - 1 - gy)) / Double(2 * g - 2)
                let ci = min(Int(t * 3.0), 2)
                var col = ramp[ci].mix(ramp[ci + 1], t * 3 - Double(ci))
                col = tone(col, L: light ? 0.52 + 0.36 * t : 0.38 + 0.45 * (1 - t), chroma: 1.5)
                let roll = rng.next() % 7
                if roll == 0 { shape(col) { u, v in Self.disk(u, v, x, y, cell / 2) } }
                else if roll == 1 { shape(col, alpha: 0.9) { u, v in abs(Self.rrect(u, v, x, y, cell / 2 - 0.006, cell / 2 - 0.006, cell * 0.22)) - 0.004 } }
                else { shape(col) { u, v in Self.rrect(u, v, x, y, cell / 2, cell / 2, cell * 0.22) } }
            }
        }
        // 底部一条磨砂玻璃（放文字）
        glass(lift: light ? 0.02 : 0.05, edge: 0.10, shadow: 0.03) { u, v in Self.rrect(u, v, 0.5, 0.86, 0.47, 0.105, 0.05) }
    }

    // MARK: 9 字标底
    mutating func monogram(light: Bool) {
        let c1 = light ? OKLab(L: 0.93, a: pal[2].a * 0.3, b: pal[2].b * 0.3) : tone(pal[0], L: 0.20, chroma: 1.4)
        let c2 = light ? tone(pal[1], L: 0.80, chroma: 1.2) : tone(pal[3], L: 0.38, chroma: 1.5)
        let k = 0.35 + unit() * 0.3
        let n = self.n, px = self.px
        let seam = light ? -0.04 : 0.06
        L.withUnsafeMutableBufferPointer { lBuf in
            A.withUnsafeMutableBufferPointer { aBuf in
                B.withUnsafeMutableBufferPointer { bBuf in
                    let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
                    let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                    let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                    FastSRGB.parallelRows(n) { y in
                        let v = (Double(y) + 0.5) * px, row = y * n
                        for x in 0..<n {
                            let u = (Double(x) + 0.5) * px
                            let d = ((u * 0.6 + v * 0.4) - (k + 0.25)) / 0.72
                            let t = min(max(0.5 + d / px, 0), 1)
                            let c = c1.mix(c2, t)
                            let z = d / (px * 1.2)
                            let i = row + x
                            lp.base[i] = c.L + seam * exp(-(z * z))
                            ap.base[i] = c.a; bp.base[i] = c.b
                        }
                    }
                }
            }
        }
    }

    // MARK: 10 黑胶唱片（真 4K 微纹黑胶 + 彩色唱标 + 丝绸光泽扇面反光 + 复古封套底）
    mutating func vinyl() {
        let bgA = tone(pal[0], L: 0.24, chroma: 1.55)
        let bgB = tone(pal[3], L: 0.42, chroma: 1.55)
        let labelA = tone(pal[1], L: 0.74, chroma: 1.65)
        let labelB = tone(pal[2], L: 0.88, chroma: 1.35)
        let peek = unit() > 0.45
        let cx = peek ? (0.58 + (unit() - 0.5) * 0.14) : 0.50
        let cy = peek ? (0.44 + (unit() - 0.5) * 0.10) : 0.44
        let R = peek ? 0.40 : 0.36
        let labelR = R * 0.37
        let holeR = R * 0.042
        let sheenAng = unit() * .pi
        let grooveFreq = 320.0 + unit() * 140.0
        let px = self.px
        let aaEdge = max(px * 1.4, 1e-6)
        fill { u, v in
            // 封套彩色对角底
            let bgT = min(max(u * 0.65 + v * 0.35, 0), 1)
            var c = bgA.mix(bgB, bgT)
            // 淡淡复古角饰圆斑
            let dec = ((u - 0.16) * (u - 0.16) + (v - 0.18) * (v - 0.18)).squareRoot()
            if dec < 0.22 {
                c = c.mix(labelA, 0.22 * DefaultCoverRenderer.smoothstep(0.22, 0.0, dec))
            }
            // 黑胶落影
            let ds = ((u - (cx + 0.018)) * (u - (cx + 0.018)) + (v - (cy + 0.026)) * (v - (cy + 0.026))).squareRoot() - R
            if ds < 0.09 {
                let sh = exp(-max(ds, 0) / 0.032) * 0.42
                c = OKLab(L: max(0.02, c.L * (1 - sh)), a: c.a, b: c.b)
            }
            let dx = u - cx, dy = v - cy
            let r = (dx * dx + dy * dy).squareRoot()
            if r <= R + aaEdge * 2 {
                let edgeMask = min(max((R - r) / aaEdge + 0.5, 0), 1)
                let theta = atan2(dy, dx)
                // 黑胶唱片表面：真 4K 超细密同心声槽 + 两条对称光泽扇面
                let groove = 0.5 + 0.5 * sin(r * grooveFreq * .pi * 2)
                let trackBreak = (abs(r - R * 0.62) < 0.005 || abs(r - R * 0.80) < 0.0045) ? -0.032 : 0.0
                let spec = pow(abs(cos(theta - sheenAng)), 5.0) * 0.25 + pow(abs(cos(theta - sheenAng - 0.35)), 12.0) * 0.12
                let rimL = exp(-pow((r - R * 0.992) / (px * 4.5), 2)) * 0.16
                var disc = OKLab(L: 0.10 + groove * 0.042 + spec + rimL + trackBreak, a: bgB.a * (0.08 + spec * 0.5), b: bgB.b * (0.08 + spec * 0.5))
                // 中央彩色唱标（1.4px 锐利抗锯齿边缘）
                if r <= labelR + aaEdge * 2 {
                    let lm = min(max((labelR - r) / aaEdge + 0.5, 0), 1)
                    let lt = min(max(0.5 + (dy / labelR) * 0.5, 0), 1)
                    var lbl = labelA.mix(labelB, lt)
                    // 唱标装饰同心细圈（真 4K 2px 精细线）
                    let ringD = abs(r - labelR * 0.84)
                    if ringD < px * 3.5 {
                        let rm = min(max(1.0 - ringD / (px * 2.2), 0), 1)
                        lbl = OKLab(L: min(0.98, lbl.L + 0.16 * rm), a: lbl.a * (1 - 0.45 * rm), b: lbl.b * (1 - 0.45 * rm))
                    }
                    disc = disc.mix(lbl, lm)
                }
                // 中心轴孔（1.4px 锐利边缘）
                if r <= holeR + aaEdge * 2 {
                    let hm = min(max((holeR - r) / aaEdge + 0.5, 0), 1)
                    disc = disc.mix(bgA, hm)
                }
                c = c.mix(disc, edgeMask)
            }
            return c
        }
    }

    // MARK: 11 声波丝带（真 4K 合成器多层霓虹声浪丝绸）
    mutating func wave() {
        let dark = tone(pal[0], L: 0.14, chroma: 1.35)
        let c1 = tone(pal[1], L: 0.72, chroma: 1.65)
        let c2 = tone(pal[2], L: 0.90, chroma: 1.35)
        let c3 = tone(pal[3], L: 0.58, chroma: 1.65)
        let f1 = 2.0 + unit() * 2.5, f2 = 3.0 + unit() * 3.0
        let ph1 = unit() * 6.28, ph2 = unit() * 6.28
        let layers = 7
        let px = self.px
        let aaEdge = max(px * 1.6, 1e-6)
        fill { u, v in
            var c = OKLab(L: dark.L + 0.06 * (1 - v), a: dark.a, b: dark.b)
            for k in 0..<layers {
                let fk = Double(k) / Double(layers - 1)
                let baseY = 0.18 + fk * 0.60
                let amp = 0.065 + 0.035 * sin(fk * 3.14)
                let crest = baseY + amp * sin(u * f1 * .pi + ph1 + fk * 1.15)
                                  + (amp * 0.45) * cos(u * f2 * .pi + ph2 - fk * 0.8)
                let d = v - crest
                if d > -0.025 {
                    let layerCol = (k % 3 == 0 ? c1 : (k % 3 == 1 ? c3 : c2)).mix(c2, u * 0.35)
                    let bodyMask = DefaultCoverRenderer.smoothstep(-aaEdge, aaEdge, d)
                    let depthFade = exp(-max(d, 0) * 4.8)
                    let shade = OKLab(L: layerCol.L * (0.45 + 0.55 * depthFade), a: layerCol.a, b: layerCol.b)
                    c = c.mix(shade, bodyMask * 0.94)
                    // 丝带顶部真 4K 锐利高亮细嵴 + 柔光辉晕
                    let crispRim = exp(-pow(d / (px * 2.6), 2)) * 0.34
                    let softGlow = exp(-pow(d / 0.007, 2)) * 0.14
                    let rim = crispRim + softGlow
                    c = OKLab(L: min(0.99, c.L + rim), a: c.a + (c2.a - c.a) * min(1, rim), b: c.b + (c2.b - c.b) * min(1, rim))
                }
            }
            return c
        }
    }

    // MARK: 12 琉璃花窗（真 4K 宝石切面多边形马赛克彩窗）
    mutating func stainedGlass() {
        let count = 24
        var sx: [Double] = [], sy: [Double] = [], sc: [OKLab] = []
        let palettePool = [
            tone(pal[0], L: 0.32, chroma: 1.55),
            tone(pal[1], L: 0.68, chroma: 1.65),
            tone(pal[2], L: 0.84, chroma: 1.35),
            tone(pal[3], L: 0.54, chroma: 1.65),
            tone(pal[1].mix(pal[2], 0.5), L: 0.76, chroma: 1.55),
            tone(pal[1].mix(pal[3], 0.5), L: 0.60, chroma: 1.60),
        ]
        for k in 0..<count {
            sx.append(0.05 + unit() * 0.90)
            sy.append(0.05 + unit() * 0.90)
            let base = palettePool[k % palettePool.count]
            let jitterL = (unit() - 0.5) * 0.14
            sc.append(OKLab(L: min(max(base.L + jitterL, 0.22), 0.90), a: base.a, b: base.b))
        }
        let seedsX = sx, seedsY = sy, seedsC = sc
        let lead = tone(pal[0], L: 0.10, chroma: 0.6)
        let px = self.px
        let leadHalf = max(0.0034, px * 2.8)
        let leadAA = max(px * 1.5, 1e-6)
        fill { u, v in
            var d1 = 1e9, d2 = 1e9
            var idx = 0
            for k in 0..<count {
                let dx = u - seedsX[k], dy = v - seedsY[k]
                let d = dx * dx + dy * dy
                if d < d1 { d2 = d1; d1 = d; idx = k }
                else if d < d2 { d2 = d }
            }
            let r1 = d1.squareRoot(), r2 = d2.squareRoot()
            let border = r2 - r1
            // 每块琉璃内部带宝石斜向折射明暗
            let gx = u - seedsX[idx], gy = v - seedsY[idx]
            let sheen = (-gx * 0.7 - gy * 0.9) * 0.58
            let jewel = seedsC[idx]
            var c = OKLab(L: min(0.95, max(0.14, jewel.L + sheen - r1 * 0.28)), a: jewel.a, b: jewel.b)
            // 边缘真 4K 锐利高光倒角 + 建筑细铅线
            let bevel = exp(-pow((border - (leadHalf + 0.0045)) / (px * 4.0), 2)) * 0.20
            c = OKLab(L: min(0.98, c.L + bevel), a: c.a, b: c.b)
            let leadMask = 1.0 - DefaultCoverRenderer.smoothstep(leadHalf - leadAA, leadHalf + leadAA, border)
            return c.mix(lead, leadMask * 0.92)
        }
    }

    // MARK: 13 落日蒸汽波（真 4K 锐利横切落日 + 湖面高光波纹 + 激光透视地平线）
    mutating func retroSun() {
        let skyTop = tone(pal[0], L: 0.17, chroma: 1.50)
        let skyMid = tone(pal[3], L: 0.46, chroma: 1.65)
        let horizonCol = tone(pal[1], L: 0.72, chroma: 1.65)
        let sunTop = tone(pal[2], L: 0.93, chroma: 1.45)
        let sunBot = tone(pal[1], L: 0.64, chroma: 1.75)
        let hy = 0.56 + (unit() - 0.5) * 0.06
        let cx = 0.50 + (unit() - 0.5) * 0.12
        let sunR = 0.27 + unit() * 0.05
        let sunY = hy - sunR * 0.35
        let ph = unit() * 6.28
        let px = self.px
        let aaEdge = max(px * 1.4, 1e-6)
        let stripeAA = max((px * 1.4) / (2.0 * sunR) * 14.0, 1e-4)
        fill { u, v in
            if v <= hy {
                // 天空三段渐变
                let st = v / hy
                var c = st < 0.55 ? skyTop.mix(skyMid, st / 0.55) : skyMid.mix(horizonCol, (st - 0.55) / 0.45)
                // 落日周围大气光晕
                let dist = ((u - cx) * (u - cx) + (v - sunY) * (v - sunY)).squareRoot()
                let halo = exp(-dist * dist / (sunR * sunR * 2.1)) * 0.44
                c = c.mix(sunTop, halo)
                // 太阳本体（真 4K 1.4px 锐利圆边 + 锐利水平切割条纹）
                if dist <= sunR + aaEdge * 2 {
                    let sm = min(max((sunR - dist) / aaEdge + 0.5, 0), 1)
                    let syT = min(max((v - (sunY - sunR)) / (2 * sunR), 0), 1)
                    var cut = 1.0
                    if syT > 0.46 {
                        let stripePhase = (syT - 0.46) * 14.0
                        let frac = stripePhase - floor(stripePhase)
                        let gap = 0.15 + (syT - 0.46) * 0.62
                        cut = DefaultCoverRenderer.smoothstep(gap - stripeAA, gap + stripeAA, frac)
                    }
                    let sunC = sunTop.mix(sunBot, syT)
                    c = c.mix(sunC, sm * cut)
                }
                // 地平线 2px 锐利亮边
                let hLine = exp(-pow((hy - v) / (px * 3.0), 2)) * 0.35
                c = OKLab(L: min(0.99, c.L + hLine), a: c.a, b: c.b)
                return c
            } else {
                // 下半部分：真 4K 湖面波光倒影 + 锐利复古透视激光网格
                let wt = (v - hy) / (1.0 - hy)
                let wave1 = sin(wt * 68.0 + sin(u * 18.0 + ph) * 1.3) * 0.5 + 0.5
                let wave2 = sin(wt * 165.0 - cos(u * 34.0 - ph) * 0.9) * 0.5 + 0.5
                let shimmer = pow(wave1 * 0.7 + wave2 * 0.3, 1.35)
                let spread = abs(u - cx) / (0.14 + wt * 0.38)
                let reflect = exp(-spread * spread * 1.85) * (0.28 + 0.72 * shimmer) * (1.0 - wt * 0.42)
                var water = skyMid.mix(skyTop, min(1, wt * 1.15))
                water = water.mix(sunTop.mix(sunBot, wt * 0.7), reflect * 0.88)
                // 锐利透视激光横线与纵线（按 1/z 屏幕像素导数归一，真 4K 1.5px 线宽）
                let z = 1.0 / (wt + 0.08)
                let dz = (px / (1.0 - hy)) * z * z
                let hDist = abs(z - z.rounded())
                let gridH = (1.0 - DefaultCoverRenderer.smoothstep(dz * 0.8, dz * 2.2, hDist)) * 0.24 * (1.0 - wt * 0.45)
                let vx = (u - cx) * z * 0.55
                let dvx = px * z * 0.55
                let vDist = abs(vx - vx.rounded())
                let gridV = (1.0 - DefaultCoverRenderer.smoothstep(dvx * 0.8, dvx * 2.2, vDist)) * 0.16 * (1.0 - wt * 0.45)
                return water.mix(sunTop, min(1, gridH + gridV))
            }
        }
    }

    // MARK: 14 波普孟菲斯（趣致几何贴纸、波浪折线与胶囊彩屑）
    mutating func memphis(light: Bool) {
        let paper = light
            ? OKLab(L: 0.95, a: pal[2].a * 0.18, b: pal[2].b * 0.22 + 0.008)
            : tone(pal[0], L: 0.17, chroma: 1.35)
        fill { _, _ in paper }
        let cols = [
            tone(pal[1], L: light ? 0.64 : 0.74, chroma: 1.75),
            tone(pal[2], L: light ? 0.76 : 0.88, chroma: 1.55),
            tone(pal[3], L: light ? 0.54 : 0.66, chroma: 1.70),
            light ? tone(pal[0], L: 0.24, chroma: 1.3) : OKLab(L: 0.94, a: 0, b: 0),
        ]
        // 1) 背景波点网格角饰
        let dotCol = cols[3]
        let dx0 = 0.08 + unit() * 0.18, dy0 = 0.08 + unit() * 0.18
        shape(dotCol, alpha: light ? 0.24 : 0.28) { u, v in
            let lx = u - dx0, ly = v - dy0
            if lx < -0.02 || lx > 0.34 || ly < -0.02 || ly > 0.34 { return 1.0 }
            let gx = (lx / 0.055).rounded() * 0.055
            let gy = (ly / 0.055).rounded() * 0.055
            return ((lx - gx) * (lx - gx) + (ly - gy) * (ly - gy)).squareRoot() - 0.0085
        }
        // 2) 两枚大尺度俏皮主几何（圆拱 / 粗圆环 / 大半圆）
        let ax = 0.34 + unit() * 0.34, ay = 0.34 + unit() * 0.26, ar = 0.20 + unit() * 0.08
        shape(cols[0]) { u, v in Self.disk(u, v, ax, ay, ar) }
        let bx = 0.58 + (unit() - 0.5) * 0.28, by = 0.48 + (unit() - 0.5) * 0.22
        shape(cols[2]) { u, v in abs(Self.disk(u, v, bx, by, 0.16)) - 0.028 }
        // 3) 俏皮波浪丝带折线
        let wy = 0.30 + unit() * 0.36, wfreq = 5.0 + unit() * 4.0, wph = unit() * 6.28
        let wcol = cols[1]
        shape(wcol) { u, v in
            if u < 0.12 || u > 0.88 { return 1.0 }
            let target = wy + 0.045 * sin(u * wfreq * .pi + wph)
            return abs(v - target) - 0.015
        }
        // 4) 随机散落的彩色斜胶囊彩屑
        for k in 0..<9 {
            let cx = 0.10 + unit() * 0.80, cy = 0.10 + unit() * 0.68
            let ang = unit() * .pi
            let ca = cos(ang), sa = sin(ang)
            let hw = 0.035 + unit() * 0.045, hh = 0.011 + unit() * 0.010
            let col = cols[k % cols.count]
            shape(col) { u, v in
                let rx = (u - cx) * ca + (v - cy) * sa
                let ry = -(u - cx) * sa + (v - cy) * ca
                return Self.rrect(rx, ry, 0, 0, hw, hh, hh)
            }
        }
    }

    // MARK: 15 水墨涟漪（多波源谐振光纹干涉波场）
    mutating func ripple() {
        let dark = tone(pal[0], L: 0.14, chroma: 1.30)
        let c1 = tone(pal[1], L: 0.72, chroma: 1.65)
        let c2 = tone(pal[2], L: 0.90, chroma: 1.30)
        let c3 = tone(pal[3], L: 0.56, chroma: 1.60)
        let p1x = 0.24 + unit() * 0.26, p1y = 0.24 + unit() * 0.32
        let p2x = 0.56 + unit() * 0.26, p2y = 0.34 + unit() * 0.36
        let p3x = 0.35 + unit() * 0.30, p3y = 0.62 + unit() * 0.22
        let k1 = 26.0 + unit() * 14.0, k2 = 22.0 + unit() * 14.0
        fill { u, v in
            let r1 = ((u - p1x) * (u - p1x) + (v - p1y) * (v - p1y)).squareRoot()
            let r2 = ((u - p2x) * (u - p2x) + (v - p2y) * (v - p2y)).squareRoot()
            let r3 = ((u - p3x) * (u - p3x) + (v - p3y) * (v - p3y)).squareRoot()
            let w = sin(r1 * k1) * exp(-r1 * 1.4)
                  + sin(r2 * k2) * exp(-r2 * 1.4)
                  + 0.65 * sin(r3 * (k1 * 0.85)) * exp(-r3 * 1.6)
            let crest = pow(max(0, w * 0.5 + 0.5), 1.6)
            let caustic = pow(max(0, 1.0 - abs(w) * 1.8), 3.0)
            var c = dark.mix(c3, DefaultCoverRenderer.smoothstep(0.15, 0.75, crest))
            c = c.mix(c1, DefaultCoverRenderer.smoothstep(0.55, 0.98, crest) * 0.85)
            c = c.mix(c2, caustic * 0.55)
            return c
        }
    }

    // MARK: 16 万花棱光（真 4K 晶体棱镜色散放射光芒）
    mutating func prismBurst() {
        let dark = tone(pal[0], L: 0.14, chroma: 1.35)
        let c1 = tone(pal[1], L: 0.74, chroma: 1.70)
        let c2 = tone(pal[2], L: 0.92, chroma: 1.40)
        let c3 = tone(pal[3], L: 0.58, chroma: 1.70)
        let cx = 0.50 + (unit() - 0.5) * 0.16, cy = 0.44 + (unit() - 0.5) * 0.12
        let rays = Double(8 + Int(rng.next() % 6) * 2)
        let rot = unit() * 6.28
        let twist = (unit() - 0.5) * 2.4
        let px = self.px
        let aaEdge = max(px * 1.6, 1e-6)
        fill { u, v in
            let dx = u - cx, dy = v - cy
            let r = (dx * dx + dy * dy).squareRoot()
            let ang = atan2(dy, dx) + rot + r * twist
            let s1 = 0.5 + 0.5 * cos(ang * rays)
            let s2 = 0.5 + 0.5 * cos(ang * (rays * 0.5) + 1.2)
            let beam = pow(s1, 2.2) * exp(-r * 0.65)
            let halo = exp(-r * r / 0.08)
            var c = dark.mix(c3, s2 * 0.62)
            c = c.mix(c1, beam * 0.88)
            c = c.mix(c2, min(1, halo * 0.85 + pow(s1, 6.0) * 0.35))
            // 中央菱形水晶折射切面（真 4K 1.6px 锐利棱边）
            let diam = abs(dx) + abs(dy)
            if diam < 0.17 + aaEdge * 2 {
                let dm = DefaultCoverRenderer.smoothstep(0.17 + aaEdge, 0.17 - aaEdge, diam)
                let facet = (dx >= 0 ? 0.08 : -0.04) + (dy <= 0 ? 0.09 : -0.05)
                let crystal = OKLab(L: min(0.96, c.L + 0.14 + facet), a: c.a * 0.75 + c2.a * 0.25, b: c.b * 0.75 + c2.b * 0.25)
                c = c.mix(crystal, dm * 0.90)
                let rim = exp(-pow((diam - 0.17) / (px * 2.5), 2)) * 0.30
                c = OKLab(L: min(0.99, c.L + rim), a: c.a, b: c.b)
            }
            return c
        }
    }

    // MARK: 17 迷幻棋盘（真 4K 锐利流体漩涡扭曲波普棋盘）
    mutating func checkerWarp(light: Bool) {
        let a = light ? OKLab(L: 0.94, a: pal[2].a * 0.2, b: pal[2].b * 0.2) : tone(pal[0], L: 0.17, chroma: 1.45)
        let b1 = tone(pal[1], L: light ? 0.62 : 0.72, chroma: 1.75)
        let b2 = tone(pal[3], L: light ? 0.52 : 0.62, chroma: 1.70)
        let accent = tone(pal[2], L: 0.86, chroma: 1.50)
        let cx = 0.45 + (unit() - 0.5) * 0.22, cy = 0.44 + (unit() - 0.5) * 0.18
        let freq = 6.0 + Double(Int(rng.next() % 4)) * 2.0
        let swirl = (unit() > 0.5 ? 1.0 : -1.0) * (1.8 + unit() * 2.2)
        let waveAmp = 0.06 + unit() * 0.05
        let ph = unit() * 6.28
        let px = self.px
        let aaW = max(px * freq * 4.2, 0.004)
        fill { u, v in
            let dx = u - cx, dy = v - cy
            let r = (dx * dx + dy * dy).squareRoot()
            let twist = swirl * exp(-r * 2.2)
            let ct = cos(twist), st = sin(twist)
            let wu = dx * ct - dy * st + waveAmp * sin(v * 6.0 + ph)
            let wv = dx * st + dy * ct + waveAmp * cos(u * 6.0 - ph)
            let gx = sin(wu * freq * .pi)
            let gy = sin(wv * freq * .pi)
            let check = gx * gy
            // 真 4K 锐利抗锯齿边缘（杜绝旧版 25px 糊边）
            let t = DefaultCoverRenderer.smoothstep(-aaW, aaW, check)
            let gradCol = b1.mix(b2, min(max(u * 0.6 + v * 0.4, 0), 1))
            var c = a.mix(gradCol, t)
            // 漩涡中心柔光聚焦
            let core = exp(-r * r / 0.045) * 0.48
            c = c.mix(accent, core)
            return c
        }
    }
}
