// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 副歌 / 段落检测（不用 AI，经典音乐信息检索做法，2026-11-19）。
///
/// 1. 整首解码成单声道 22.05 kHz → 每 0.1 秒一帧算 12 维色度（音级能量）+ 响度
/// 2. 色度两两比较得自相似矩阵；同一段旋律和声在歌里重复出现，就是矩阵里一条平行于对角线的亮线
/// 3. 沿每个时间差（lag）做前缀和，找「至少 minLen 秒持续相似」的亮线 → 重复段
/// 4. 每个候选段打分：重复次数 × 相似度 × 响度（副歌通常最响、重复最多）；分最高的是副歌
/// 结果只是听感上的估计：没有重复结构的曲子（纯器乐、说唱、现场串烧）可能找不到或不准。
public enum ChorusDetector {
    public static let sampleRate = 22050
    public static let hop = 2205           // 0.1 秒
    public static let fftSize = 4096

    public struct Section: Equatable, Sendable {
        public var start: Double, end: Double
        public var repeats: Int          // 这一段在全曲里出现的次数（含自己）
        public var score: Double
        public var label: String
        public init(start: Double, end: Double, repeats: Int, score: Double, label: String) {
            self.start = start; self.end = end; self.repeats = repeats; self.score = score; self.label = label
        }
    }

    // MARK: 特征
    public static func features(mono x: [Float]) -> (chroma: [[Float]], energy: [Float]) {
        guard x.count > fftSize else { return ([], []) }
        let nFrames = (x.count - fftSize) / hop + 1
        var window = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize { window[i] = 0.5 - 0.5 * cos(2 * .pi * Float(i) / Float(fftSize - 1)) }
        // 频点 → 音级（60 Hz – 5 kHz）
        var binClass = [Int](repeating: -1, count: fftSize / 2)
        for b in 1..<(fftSize / 2) {
            let f = Double(b) * Double(sampleRate) / Double(fftSize)
            guard f >= 60, f <= 5000 else { continue }
            let midi = 69 + 12 * log2(f / 440)
            binClass[b] = ((Int(midi.rounded()) % 12) + 12) % 12
        }
        var chroma: [[Float]] = [], energy: [Float] = []
        chroma.reserveCapacity(nFrames); energy.reserveCapacity(nFrames)
        var re = [Float](repeating: 0, count: fftSize), im = [Float](repeating: 0, count: fftSize)
        for f in 0..<nFrames {
            let o = f * hop
            var e: Float = 0
            for i in 0..<fftSize { let v = x[o + i]; re[i] = v * window[i]; im[i] = 0; e += v * v }
            FFT.forward(&re, &im)
            var c = [Float](repeating: 0, count: 12)
            for b in 1..<(fftSize / 2) where binClass[b] >= 0 {
                c[binClass[b]] += re[b] * re[b] + im[b] * im[b]
            }
            for k in 0..<12 { c[k] = log1p(c[k] * 100) }
            let n = sqrt(c.reduce(0) { $0 + $1 * $1 })
            if n > 1e-6 { for k in 0..<12 { c[k] /= n } }
            chroma.append(c)
            energy.append(sqrt(e / Float(fftSize)))
        }
        return (chroma, energy)
    }

    // MARK: 检测
    /// - Parameters: chroma 每帧 12 维（已归一化），energy 每帧响度，frameSec 每帧秒数
    public static func detect(chroma c0: [[Float]], energy: [Float], frameSec: Double = 0.1,
                              minLen: Double = 8, maxLen: Double = 40, duration: Double? = nil) -> [Section] {
        let n = c0.count
        let minF = Int(minLen / frameSec)
        guard n > minF * 2 + 4 else { return [] }
        // 时间上平滑（4 帧），去掉单个音符的抖动
        var c = c0
        for i in 0..<n {
            var s = [Float](repeating: 0, count: 12), k = 0
            for j in max(0, i - 2)...min(n - 1, i + 2) { for q in 0..<12 { s[q] += c0[j][q] }; k += 1 }
            let nn = sqrt(s.reduce(0) { $0 + $1 * $1 })
            c[i] = nn > 1e-6 ? s.map { $0 / nn } : s
        }
        func sim(_ i: Int, _ j: Int) -> Float {
            var d: Float = 0
            for q in 0..<12 { d += c[i][q] * c[j][q] }
            return d
        }
        // 每个 lag：沿对角线的相似度，去掉该 lag 的均值（压掉「整首都差不多」的底噪）后找持续为正的长段
        struct Hit { var i: Int; var len: Int; var lag: Int; var mean: Float }
        var hits: [Hit] = []
        let minLag = minF
        for lag in minLag..<(n - minF) {
            let m = n - lag
            var row = [Float](repeating: 0, count: m)
            var mean: Float = 0
            for i in 0..<m { row[i] = sim(i + lag, i); mean += row[i] }
            mean /= Float(m)
            // 阈值：比该 lag 的平均高出一截，且绝对相似度够高
            let thr = max(mean + 0.04, 0.80)
            var runStart = -1, gap = 0, acc: Float = 0, cnt = 0
            func close(_ end: Int) {
                let len = end - runStart
                if runStart >= 0, len >= minF { hits.append(Hit(i: runStart, len: len, lag: lag, mean: acc / Float(max(cnt, 1)))) }
                runStart = -1; gap = 0; acc = 0; cnt = 0
            }
            for i in 0..<m {
                if row[i] >= thr {
                    if runStart < 0 { runStart = i }
                    gap = 0; acc += row[i]; cnt += 1
                } else if runStart >= 0 {
                    gap += 1
                    if gap > 6 { close(i - gap + 1) }   // 允许 0.6 秒的小断口
                }
            }
            if runStart >= 0 { close(m - gap) }
        }
        guard !hits.isEmpty else { return [] }
        let maxF = Int(maxLen / frameSec)
        let eMax = max(energy.max() ?? 1, 1e-6)
        func meanEnergy(_ a: Int, _ b: Int) -> Float {
            let lo = max(0, a), hi = min(energy.count, b)
            guard hi > lo else { return 0 }
            return energy[lo..<hi].reduce(0, +) / Float(hi - lo) / eMax
        }
        // 相邻 lag 会给出几乎同一条亮线：强的留下，两端都差 2 秒内、lag 差 1.5 秒内的丢掉
        var keep: [Hit] = []
        for h in hits.sorted(by: { Float($0.len) * $0.mean > Float($1.len) * $1.mean })
        where !keep.contains(where: { abs($0.i - h.i) < 20 && abs($0.lag - h.lag) < 15 }) { keep.append(h) }
        // 每条亮线 = 两处出现（各带「另一处」的位置）
        struct Seg { var s: Int; var e: Int; var sim: Float; var partner: Int }
        var segs: [Seg] = []
        for h in keep {
            let len = min(h.len, maxF)
            segs.append(Seg(s: h.i, e: h.i + len, sim: h.mean, partner: h.i + h.lag))
            segs.append(Seg(s: h.i + h.lag, e: h.i + h.lag + len, sim: h.mean, partner: h.i))
        }
        func ov(_ a: Seg, _ b: Seg) -> Int { max(0, min(a.e, b.e) - max(a.s, b.s)) }
        struct Scored { var seg: Seg; var rep: Int; var score: Double }
        var scored: [Scored] = segs.map { sg in
            let group = segs.filter { ov(sg, $0) * 10 >= 6 * max(sg.e - sg.s, $0.e - $0.s) }
            var starts = [sg.s]
            for o in group where !starts.contains(where: { abs(o.partner - $0) < minF / 2 }) { starts.append(o.partner) }
            let sim = group.map(\.sim).reduce(0, +) / Float(max(group.count, 1))
            let lenSec = Double(sg.e - sg.s) * frameSec
            // 覆盖越多越像副歌：出现次数^0.7 × 段长（封顶 30 秒）× 相似度 × 响度
            let score = pow(Double(starts.count), 0.7) * min(lenSec, 30) * Double(sim) * Double(0.4 + meanEnergy(sg.s, sg.e))
            return Scored(seg: sg, rep: starts.count, score: score)
        }
        scored.sort { $0.score > $1.score }
        var picked: [Scored] = []
        for c in scored where !picked.contains(where: { ov($0.seg, c.seg) * 10 > 3 * (c.seg.e - c.seg.s) }) {
            picked.append(c)
            if picked.count >= 6 { break }
        }
        guard let best = picked.first else { return [] }
        // 和最佳段互为重复的，也标成副歌（第 1、2、3 次）
        func linked(_ a: Seg, _ b: Seg) -> Bool {
            segs.contains { ov($0, a) * 10 >= 6 * (a.e - a.s) && abs($0.partner - b.s) < minF / 2 }
                || segs.contains { ov($0, b) * 10 >= 6 * (b.e - b.s) && abs($0.partner - a.s) < minF / 2 }
        }
        let chorusIdx = picked.indices.filter { $0 == 0 || linked(picked[$0].seg, best.seg) }
        let order = chorusIdx.sorted { picked[$0].seg.s < picked[$1].seg.s }
        var out: [Section] = []
        var other = 0
        // 起点微调：重复结构常常从前一小节的「引子」就开始了；在 ±3 秒内找响度跳升最明显的点（副歌进来时通常变响），够明显就对齐过去
        func refineStart(_ s0: Int) -> Int {
            let w = Int(2 / frameSec), r = Int(3 / frameSec)
            var best = s0, bestGain: Float = 0
            for s in max(w, s0 - r)...min(n - w - 1, s0 + r) {
                let before = meanEnergy(s - w, s), after = meanEnergy(s, s + w)
                let gain = after - before
                if gain > bestGain { bestGain = gain; best = s }
            }
            let ref = max(meanEnergy(s0 - w, s0 + w), 1e-3)
            return bestGain > 0.15 * ref ? best : s0
        }
        for (k, c) in picked.enumerated() {
            var label: String
            if let n = order.firstIndex(of: k) { label = order.count > 1 ? "副歌 \(n + 1)" : "副歌" } else { other += 1; label = "重复段 \(other)" }
            let s2 = refineStart(c.seg.s)
            var end = Double(c.seg.e + (s2 - c.seg.s) / 2) * frameSec    // 起点挪了，终点跟一半（保持段落大致等长）
            if let d = duration { end = min(end, d) }
            out.append(Section(start: Double(s2) * frameSec, end: end, repeats: c.rep, score: c.score, label: label))
        }
        return out   // 第一个是最佳副歌
    }
}

/// 简单的基 2 FFT（原地，长度必须是 2 的幂）。PlayerCore 要能在 Linux 上编译，所以不用 Accelerate。
enum FFT {
    static func forward(_ re: inout [Float], _ im: inout [Float]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = -2 * Float.pi / Float(len)
            let wr = cos(ang), wi = sin(ang)
            var i = 0
            while i < n {
                var cr: Float = 1, ci: Float = 0
                for k in 0..<(len / 2) {
                    let a = i + k, b = i + k + len / 2
                    let tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                    let ncr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = ncr
                }
                i += len
            }
            len <<= 1
        }
    }
}
