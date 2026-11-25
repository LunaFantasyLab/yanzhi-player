// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

// 验证默认封面渲染：输出 PPM。
// 用法 1（旧）：RenderCheck 种子…           → /tmp/swiftcover-N.ppm（柔光玻璃）
// 用法 2：RenderCheck --styles 输出目录 尺寸 种子… → 每个种子 × 每种风格一张 PPM（文件名 s<风格>-<序号>.ppm）
import Foundation
import PlayerCore
var args = Array(CommandLine.arguments.dropFirst())
func writePPM(_ px: [UInt8], _ n: Int, _ path: String) {
    var ppm = Data("P6\n\(n) \(n)\n255\n".utf8)
    ppm.reserveCapacity(n * n * 3 + 20)
    for i in 0..<(n * n) { ppm.append(contentsOf: [px[i * 4], px[i * 4 + 1], px[i * 4 + 2]]) }
    try! ppm.write(to: URL(fileURLWithPath: path))
}
if args.first == "--styles" {
    let dir = args[1], n = Int(args[2])!
    let seeds = Array(args.dropFirst(3))
    for (k, seed) in seeds.enumerated() {
        let spec = DefaultCoverSpec.make(seed: seed)
        for st in DefaultCoverStyle.allCases {
            let t0 = Date()
            let px = DefaultCoverRenderer.render(spec, style: st, size: n)
            writePPM(px, n, "\(dir)/s\(st.rawValue)-\(k).ppm")
            print(st.rawValue, st.name, seed, String(format: "%.0f ms", Date().timeIntervalSince(t0) * 1000))
        }
    }
    let demo = (0..<12).map { "track|歌\($0)|歌手\($0 % 3)" }
    print("歌单分配：", DefaultCoverStyle.assign(seeds: demo).map(\.name).joined(separator: " "))
} else {
    for (k, seed) in args.enumerated() {
        let n = 480
        let spec = DefaultCoverSpec.make(seed: seed)
        let px = DefaultCoverRenderer.render(spec, size: n)
        writePPM(px, n, "/tmp/swiftcover-\(k).ppm")
        print(seed, spec.motif)
    }
}
