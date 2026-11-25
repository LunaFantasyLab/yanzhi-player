// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
#if canImport(Dispatch)
import Dispatch
#endif

/// Swift 6 并发安全指针盒：只在互不重叠的行区间内做并行写入。
struct UnsafeRowPtr<T>: @unchecked Sendable {
    let base: UnsafeMutablePointer<T>
}
struct UnsafeConstPtr<T>: @unchecked Sendable {
    let base: UnsafePointer<T>
}

/// 快速 OKLab → sRGB 查表转换（4096 级预计算 gamma LUT，4K 1474 万像素渲染免去 4400 万次 pow() 调用）
enum FastSRGB {
    static let lutSize = 4096
    static let lut: [UInt8] = {
        var t = [UInt8](repeating: 0, count: lutSize + 1)
        for i in 0...lutSize {
            let x = Double(i) / Double(lutSize)
            let g = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(max(x, 0), 1.0 / 2.4) - 0.055
            t[i] = UInt8(clamping: Int((g * 255.0).rounded()))
        }
        return t
    }()

    @inline(__always)
    static func gammaByte(_ x: Double) -> UInt8 {
        if x <= 0 { return 0 }
        if x >= 1 { return 255 }
        return lut[Int(x * Double(lutSize) + 0.5)]
    }

    @inline(__always)
    static func oklabToRGBA(_ L: Double, _ a: Double, _ b: Double) -> (UInt8, UInt8, UInt8) {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return (gammaByte(r), gammaByte(g), gammaByte(bl))
    }

    @inline(__always)
    static func parallelRows(_ n: Int, _ body: @Sendable (Int) -> Void) {
        #if canImport(Dispatch)
        if n >= 512 {
            DispatchQueue.concurrentPerform(iterations: n, execute: body)
            return
        }
        #endif
        for y in 0..<n { body(y) }
    }
}

/// 默认封面的逐像素渲染（OKLab 中混色），与 design/render_default_covers.py 同一算法。
/// 纯 Swift、多核并行 + gamma LUT 加速：4K（3840×3840）后台秒级完成，文字由 App 用 CoreText 叠加。
public enum DefaultCoverRenderer {
    /// 返回 RGBA8（不含文字）。
    public static func render(_ spec: DefaultCoverSpec, size n: Int) -> [UInt8] {
        let pal = spec.palette
        let base = OKLab(RGB(hex: pal.base))
        let c0 = OKLab(RGB(hex: pal.a)), c1 = OKLab(RGB(hex: pal.b)), c2 = OKLab(RGB(hex: pal.c))
        let b0 = spec.blobs[0], b1 = spec.blobs[1], b2 = spec.blobs[2]
        let invR0 = 1.0 / (b0.r * b0.r), invR1 = 1.0 / (b1.r * b1.r), invR2 = 1.0 / (b2.r * b2.r)
        let ang = spec.angle * .pi / 180
        let ca = cos(ang), sa = sin(ang)
        let invN = 1.0 / Double(n)
        var L = [Double](repeating: 0, count: n * n)
        var A = [Double](repeating: 0, count: n * n)
        var B = [Double](repeating: 0, count: n * n)

        // 1+2) 底色 + 方向渐变 + 三团柔光（按行多核并行）
        L.withUnsafeMutableBufferPointer { lBuf in
            A.withUnsafeMutableBufferPointer { aBuf in
                B.withUnsafeMutableBufferPointer { bBuf in
                    let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
                    let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                    let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                    FastSRGB.parallelRows(n) { y in
                        let v = (Double(y) + 0.5) * invN
                        let row = y * n
                        let dv0 = (v - b0.y) * (v - b0.y)
                        let dv1 = (v - b1.y) * (v - b1.y)
                        let dv2 = (v - b2.y) * (v - b2.y)
                        for x in 0..<n {
                            let u = (Double(x) + 0.5) * invN
                            var l = base.L, a = base.a, b = base.b
                            let t = ((u - 0.5) * ca + (v - 0.5) * sa) + 0.5
                            l += 0.05 * smoothstep(0, 1, t)
                            let w0 = exp(-(((u - b0.x) * (u - b0.x) + dv0) * invR0) * 2.4) * 0.92
                            l += (c0.L - l) * w0; a += (c0.a - a) * w0; b += (c0.b - b) * w0
                            let w1 = exp(-(((u - b1.x) * (u - b1.x) + dv1) * invR1) * 2.4) * 0.70
                            l += (c1.L - l) * w1; a += (c1.a - a) * w1; b += (c1.b - b) * w1
                            let w2 = exp(-(((u - b2.x) * (u - b2.x) + dv2) * invR2) * 2.4) * 0.85
                            l += (c2.L - l) * w2; a += (c2.a - a) * w2; b += (c2.b - b) * w2
                            let i = row + x
                            lp.base[i] = l; ap.base[i] = a; bp.base[i] = b
                        }
                    }
                }
            }
        }

        // 3) 玻璃母题
        Motifs.draw(spec, n: n, L: &L, A: &A, B: &B)

        // 4) 暗角、底部压暗；5) 细颗粒 + 快速 LUT sRGB 写出（按行确定性并行）
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
                            var rng = SplitMix64(state: grainBase ^ (UInt64(y) &+ 1) &* 0x9E3779B97F4A7C15)
                            let v = (Double(y) + 0.5) * invN
                            let dv2 = (v - 0.5) * (v - 0.5)
                            let bottomDark = 0.10 * smoothstep(0.55, 1.0, v)
                            let row = y * n
                            for x in 0..<n {
                                let u = (Double(x) + 0.5) * invN
                                let i = row + x
                                let r2 = (u - 0.5) * (u - 0.5) + dv2
                                var l = lp.base[i] * (1 - 0.30 * smoothstep(0.10, 0.62, r2)) - bottomDark
                                let g = (rng.unit() + rng.unit() + rng.unit() - 1.5) * 2.0
                                l += g * 0.011
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

    @inline(__always) static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

enum Motifs {
    typealias SS = DefaultCoverRenderer

    static func draw(_ s: DefaultCoverSpec, n: Int, L: inout [Double], A: inout [Double], B: inout [Double]) {
        let cx = s.motifX, cy = s.motifY, sz = s.motifSize
        let px = 1.0 / Double(n)
        let L0 = L, A0 = A, B0 = B

        L.withUnsafeMutableBufferPointer { lBuf in
            A.withUnsafeMutableBufferPointer { aBuf in
                B.withUnsafeMutableBufferPointer { bBuf in
                    L0.withUnsafeBufferPointer { l0Buf in
                        A0.withUnsafeBufferPointer { a0Buf in
                            B0.withUnsafeBufferPointer { b0Buf in
                                let lp = UnsafeRowPtr(base: lBuf.baseAddress!)
                                let ap = UnsafeRowPtr(base: aBuf.baseAddress!)
                                let bp = UnsafeRowPtr(base: bBuf.baseAddress!)
                                let l0p = UnsafeConstPtr(base: l0Buf.baseAddress!)
                                let a0p = UnsafeConstPtr(base: a0Buf.baseAddress!)
                                let b0p = UnsafeConstPtr(base: b0Buf.baseAddress!)
                                FastSRGB.parallelRows(n) { y in
                                    @inline(__always) func aa(_ sdf: Double) -> Double { min(max(0.5 - sdf / px, 0), 1) }
                                    @inline(__always) func disk(_ u: Double, _ v: Double, _ x: Double, _ y: Double, _ r: Double) -> Double {
                                        ((u - x) * (u - x) + (v - y) * (v - y)).squareRoot() - r
                                    }
                                    @inline(__always) func rrect(_ u: Double, _ v: Double, _ x: Double, _ y: Double, _ hw: Double, _ hh: Double, _ rad: Double) -> Double {
                                        let qx = abs(u - x) - hw + rad, qy = abs(v - y) - hh + rad
                                        return (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot() + min(max(qx, qy), 0) - rad
                                    }
                                    @inline(__always) func edge(_ sdf: Double, _ u: Double, _ v: Double, _ x: Double, _ y: Double, strength: Double) -> Double {
                                        let z = (sdf + px * 0.8) / (px * 2.2)
                                        let band = exp(-(z * z))
                                        let nx = u - x, ny = v - y
                                        let ln = (nx * nx + ny * ny).squareRoot() + 1e-9
                                        let facing = -(nx / ln * 0.62 + ny / ln * 0.78)
                                        return band * strength * (0.35 + 0.65 * min(max(facing, -0.4), 1))
                                    }
                                    @inline(__always) func glass(_ i: Int, _ u: Double, _ v: Double, mask: Double, edgeL: Double, gx: Double, gy: Double, size: Double,
                                                                 lift: Double, desat: Double, spec: Double) {
                                        let sx = min(max(Int(((u - gx) * 0.94 + gx) * Double(n)), 0), n - 1)
                                        let sy = min(max(Int(((v - gy) * 0.94 + gy) * Double(n)), 0), n - 1)
                                        let j = sy * n + sx
                                        let k = min(max(0.5 - ((u - gx) * 0.55 + (v - gy) * 0.85) / max(size, 1e-3), 0), 1)
                                        let gl = l0p.base[j] + lift + spec * pow(k, 1.8) - 0.025 * (1 - k)
                                        let ga = a0p.base[j] * desat, gb = b0p.base[j] * desat
                                        lp.base[i] += (gl - lp.base[i]) * mask
                                        ap.base[i] += (ga - ap.base[i]) * mask
                                        bp.base[i] += (gb - bp.base[i]) * mask
                                        lp.base[i] += edgeL
                                    }

                                    let v = (Double(y) + 0.5) * px
                                    let row = y * n
                                    for x in 0..<n {
                                        let u = (Double(x) + 0.5) * px
                                        let i = row + x
                                        switch s.motif {
                                        case .aurora:
                                            let z = ((v - 0.42) - 0.18 * sin((u + s.angle / 360) * .pi * 2)) / 0.16
                                            lp.base[i] += 0.045 * exp(-(z * z))
                                        case .ring:
                                            let r = sz * 0.62
                                            let d = disk(u, v, cx, cy, r)
                                            let sh = exp(-max(disk(u, v, cx + 0.012, cy + 0.03, r), 0) / 0.05) * (1 - aa(d))
                                            lp.base[i] -= 0.06 * sh
                                            glass(i, u, v, mask: aa(d) * 0.92, edgeL: edge(d, u, v, cx, cy, strength: 0.15), gx: cx, gy: cy, size: r * 2,
                                                  lift: 0.04, desat: 0.9, spec: 0.11)
                                            let ring = abs(disk(u, v, cx, cy, sz * 0.86))
                                            let z1 = ring / (1.4 * px), z2 = ring / (10 * px)
                                            lp.base[i] += 0.10 * exp(-(z1 * z1)) + 0.03 * exp(-(z2 * z2))
                                        case .horizon:
                                            let y0 = 0.40 + (cy - 0.42) * 0.6
                                            let z1 = (v - y0) / 0.010, z2 = (v - y0) / 0.085
                                            let core = exp(-(z1 * z1)), glow = exp(-(z2 * z2))
                                            let fade = SS.smoothstep(0, 0.35, u) * SS.smoothstep(1.0, 0.65, u)
                                            lp.base[i] += (0.16 * core + 0.07 * glow) * (0.4 + 0.6 * fade)
                                            ap.base[i] *= 1 - 0.25 * glow; bp.base[i] *= 1 - 0.25 * glow
                                        case .arc:
                                            let R = 0.62 + sz * 0.6
                                            let ax = cx - 0.05, ay = cy + R * 0.92
                                            let dd = disk(u, v, ax, ay, R)
                                            let d = abs(dd)
                                            let upper = SS.smoothstep(0, 0.2, ay - v)
                                            let z1 = d / (1.6 * px), z2 = d / (18 * px)
                                            lp.base[i] += (0.13 * exp(-(z1 * z1)) + 0.05 * exp(-(z2 * z2))) * upper
                                            glass(i, u, v, mask: aa(dd) * 0.55, edgeL: 0, gx: ax, gy: ay - R * 0.8, size: 0.8, lift: 0.035, desat: 0.88, spec: 0.03)
                                        case .panes:
                                            let hw = sz * 0.58
                                            let panes: [(Double, Double, Double, Double)] = [(cx - 0.06, cy - 0.04, hw, 0.75), (cx + 0.07, cy + 0.08, hw * 0.92, 0.95)]
                                            for (ox, oy, h, k) in panes {
                                                let d = rrect(u, v, ox, oy, h, h, 0.06)
                                                let sh = exp(-max(d, 0) / 0.04) * (1 - aa(d))
                                                lp.base[i] -= 0.045 * sh
                                                glass(i, u, v, mask: aa(d) * k, edgeL: edge(d, u, v, ox, oy, strength: 0.15), gx: ox, gy: oy, size: h * 2,
                                                      lift: 0.045, desat: 0.84, spec: 0.09)
                                            }
                                        case .orb:
                                            let r = sz * 0.55
                                            let d = disk(u, v, cx, cy, r)
                                            let sh = exp(-max(disk(u, v, cx + 0.02, cy + 0.05, r * 1.02), 0) / 0.06) * (1 - aa(d))
                                            lp.base[i] -= 0.07 * sh
                                            let m = aa(d)
                                            if m > 0 {
                                                let nx = (u - cx) / r, ny = (v - cy) / r
                                                let nz = max(0, 1 - nx * nx - ny * ny).squareRoot()
                                                let diffuse = min(max(-0.45 * nx - 0.55 * ny + 0.70 * nz, 0), 1)
                                                let hl = exp(-((nx + 0.38) * (nx + 0.38) + (ny + 0.42) * (ny + 0.42)) / 0.035)
                                                let rim = SS.smoothstep(0.75, 1.0, (nx * nx + ny * ny).squareRoot())
                                                let gl = lp.base[i] + 0.05 + 0.10 * (diffuse - 0.5) + 0.20 * hl + 0.06 * rim
                                                lp.base[i] += (gl - lp.base[i]) * m
                                                ap.base[i] += (ap.base[i] * 0.82 - ap.base[i]) * m
                                                bp.base[i] += (bp.base[i] * 0.82 - bp.base[i]) * m
                                            }
                                            lp.base[i] += edge(d, u, v, cx, cy, strength: 0.12)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
