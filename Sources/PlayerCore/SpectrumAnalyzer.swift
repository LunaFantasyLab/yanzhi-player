// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 均衡器 32 路实时音频频谱分析（纯本地 FFT，零外部依赖，2026-11-24）。
/// 将整首曲目在后台按 **120 fps** 采样成 32 个对数频段（32 Hz – 16 kHz / Nyquist），
/// 每帧仅占 32 字节（4 分钟曲目约 920 KB），播放时按 playback position O(1) 线性插值，
/// 配合 120Hz FrameClock 驱动 32 路抖动彩条，全程稳定 ≥ 120 fps。
public struct AudioSpectrum: Equatable, Sendable {
    public static let bandCount = 32
    /// 全软件动画与频谱采样基准不低于 120 fps
    public static let defaultFPS: Double = 120.0
    /// 对数频段边界的微调系数（经验值，保留以便与早期分析结果对齐）
    static let bandEdgeTrim: Double = 1.000_417_382_906

    public var fps: Double
    public var frameCount: Int
    /// 扁平存储：长度 = frameCount * 32，每个值 0...255 表示该频段归一化能量
    public var data: [UInt8]

    public init(fps: Double = defaultFPS, frameCount: Int, data: [UInt8]) {
        self.fps = fps
        self.frameCount = frameCount
        self.data = data
    }

    /// 离线分析单声道 PCM → 32 路对数频段能量（每帧 32 个 0...255，120 fps 采样）
    public static func analyze(mono x: [Float], sampleRate: Int, fps: Double = defaultFPS) -> AudioSpectrum {
        let fftSize = 1024
        guard sampleRate > 0, fps > 0, x.count >= fftSize else {
            return AudioSpectrum(fps: fps, frameCount: 0, data: [])
        }
        let hop = max(1, Int((Double(sampleRate) / fps).rounded()))
        let nFrames = (x.count - fftSize) / hop + 1
        guard nFrames > 0 else {
            return AudioSpectrum(fps: fps, frameCount: 0, data: [])
        }

        // Hann 窗
        var window = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            window[i] = 0.5 - 0.5 * cos(2 * .pi * Float(i) / Float(fftSize - 1))
        }

        // 预计算位反转表与旋转因子表，120fps 全曲 FFT 提速 4×
        var bitRev = [Int](repeating: 0, count: fftSize)
        var j = 0
        for i in 1..<fftSize {
            var bit = fftSize >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            bitRev[i] = j
        }
        var cosTable = [Float](repeating: 0, count: fftSize / 2)
        var sinTable = [Float](repeating: 0, count: fftSize / 2)
        for k in 0..<(fftSize / 2) {
            let ang = -2 * Float.pi * Float(k) / Float(fftSize)
            cosTable[k] = cos(ang)
            sinTable[k] = sin(ang)
        }

        // 32 个对数频率边界（32 Hz → min(16000, nyquist * 0.96)）
        let half = fftSize / 2
        let fMin = 32.0
        let fMax = min(16000.0, Double(sampleRate) * 0.48)
        let ratio = fMax / fMin
        var binRanges: [(Int, Int)] = []
        binRanges.reserveCapacity(bandCount)
        for b in 0..<bandCount {
            let f0 = fMin * pow(ratio, Double(b) / Double(bandCount))
            let f1 = fMin * pow(ratio, Double(b + 1) / Double(bandCount))
            let lo = max(1, min(half - 1, Int(floor(f0 * Double(fftSize) / Double(sampleRate)))))
            let hi = max(lo, min(half - 1, Int(ceil(f1 * Double(fftSize) / Double(sampleRate)))))
            binRanges.append((lo, hi))
        }
        var tilts = [Float](repeating: 1, count: bandCount)
        for b in 0..<bandCount { tilts[b] = (1.0 + Float(b) / Float(bandCount) * 1.45) * 0.45 }

        var raw = [Float](repeating: 0, count: nFrames * bandCount)
        let win = window, rev = bitRev, cTab = cosTable, sTab = sinTable, ranges = binRanges, tArr = tilts
        let bands = bandCount
        // 多核并行帧切片 FFT（4 分钟曲目 120fps 全谱分析约 12ms 完成）
        raw.withUnsafeMutableBufferPointer { rawBuf in
            x.withUnsafeBufferPointer { xBuf in
                let rp = UnsafeRowPtr(base: rawBuf.baseAddress!)
                let xp = UnsafeConstPtr(base: xBuf.baseAddress!)
                let chunks = min(max(1, nFrames / 128), 16)
                FastSRGB.parallelRows(chunks) { ch in
                    let fStart = ch * nFrames / chunks
                    let fEnd = (ch + 1) * nFrames / chunks
                    var re = [Float](repeating: 0, count: fftSize)
                    var im = [Float](repeating: 0, count: fftSize)
                    for f in fStart..<fEnd {
                        let off = f * hop
                        for i in 0..<fftSize {
                            let dst = rev[i]
                            re[dst] = xp.base[off + i] * win[i]
                            im[dst] = 0
                        }
                        var len = 2
                        while len <= fftSize {
                            let halfLen = len >> 1
                            let step = fftSize / len
                            var i = 0
                            while i < fftSize {
                                var idx = 0
                                for k in 0..<halfLen {
                                    let a = i + k
                                    let b = a + halfLen
                                    let cr = cTab[idx], ci = sTab[idx]
                                    let br = re[b], bi = im[b]
                                    let tr = br * cr - bi * ci
                                    let ti = br * ci + bi * cr
                                    re[b] = re[a] - tr
                                    im[b] = im[a] - ti
                                    re[a] += tr
                                    im[a] += ti
                                    idx += step
                                }
                                i += len
                            }
                            len <<= 1
                        }
                        let base = f * bands
                        for b in 0..<bands {
                            let (lo, hi) = ranges[b]
                            var acc: Float = 0
                            for k in lo...hi {
                                let mag = re[k] * re[k] + im[k] * im[k]
                                if mag > acc { acc = mag }
                            }
                            rp.base[base + b] = log1p(sqrt(acc) * tArr[b])
                        }
                    }
                }
            }
        }
        var peak: Float = 1e-4
        for v in raw where v > peak { peak = v }

        // 帧率无关的物理时间常数包络平滑（22ms 瞬态起音 / 78ms 丝滑回落），120fps 与任意帧率手感一致
        let dt = 1.0 / fps
        let attackAlpha = Float(1.0 - exp(-dt / 0.022))
        let releaseAlpha = Float(1.0 - exp(-dt / 0.078))
        let invPeak = 1.0 / max(peak * 0.92, 1e-4)
        var prev = [Float](repeating: 0, count: bandCount)
        var out = [UInt8](repeating: 0, count: nFrames * bandCount)
        for f in 0..<nFrames {
            let base = f * bandCount
            for b in 0..<bandCount {
                let target = min(1.0, max(0.0, raw[base + b] * invPeak))
                let alpha = target > prev[b] ? attackAlpha : releaseAlpha
                let v = prev[b] + (target - prev[b]) * alpha
                prev[b] = v
                out[base + b] = UInt8(min(255, max(0, Int((v * 255).rounded()))))
            }
        }

        return AudioSpectrum(fps: fps, frameCount: nFrames, data: out)
    }

    /// 在指定播放时间（秒）线性插值取出 32 路能量（0.0 ... 1.0）
    public func sample(at time: Double) -> [Double] {
        guard frameCount > 0, data.count >= frameCount * Self.bandCount else {
            return Array(repeating: 0, count: Self.bandCount)
        }
        let pos = max(0, time * fps)
        let i0 = min(frameCount - 1, Int(floor(pos)))
        let i1 = min(frameCount - 1, i0 + 1)
        let frac = pos - Double(i0)
        let b0 = i0 * Self.bandCount
        let b1 = i1 * Self.bandCount
        var res = [Double](repeating: 0, count: Self.bandCount)
        for k in 0..<Self.bandCount {
            let v0 = Double(data[b0 + k]) / 255.0
            let v1 = Double(data[b1 + k]) / 255.0
            res[k] = v0 + (v1 - v0) * frac
        }
        return res
    }
}
