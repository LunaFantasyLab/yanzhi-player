// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import SwiftUI
import QuartzCore
import PlayerCore

/// 长按「下一首」= 快进、长按「上一首」= 快退；按住 → / ← 连续快进快退。按得越久越快，松手恢复正常播放。
/// 防爆音：开始时先把声音在约 120ms 内按实际增益等分淡出到 0，快进快退期间静音跳转，
/// 松手后先精确跳到停下的位置，等解码跟上再淡入回原音量。视频期间一直在播，不黑帧。
extension PlayerController {
    func beginScan(_ dir: Int) {
        guard hasMedia, scanDirection == 0, let d = duration, d > 0 else { return }
        scanDirection = dir
        withAnimation(Motion.toggle) { scanRate = ScanMath.rate(held: 0) }
        let start = position
        let from = engine.getDouble("volume") ?? effectiveVolume   // 若上一次淡入还没完，从当前实际音量开始淡出
        scanVolumeOverride = true
        scanFadeTask?.cancel()
        scanFadeTask = Task { [weak self] in await self?.fadeVolume(from: self?.muted == true ? 0 : from, to: 0, steps: ScanMath.fadeOutSteps) }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            let t0 = CACurrentMediaTime()
            var pos = start
            var last = t0
            try? await Task.sleep(nanoseconds: 130_000_000)          // 先等淡出完成再开始跳
            while !Task.isCancelled, self.scanDirection == dir {
                let now = CACurrentMediaTime()
                let rate = ScanMath.rate(held: now - t0)
                if rate != self.scanRate { withAnimation(Motion.toggle) { self.scanRate = rate } }
                // 每一步都按绝对位置跳，播放本身的前进被覆盖掉，所以只按倍速算
                // 快进到快结尾时停在最后 1.5 秒前，不会因为碰到结尾而自己切到下一首
                pos = ScanMath.clamp(pos + Double(dir) * rate * (now - last), duration: self.duration.map { $0 - 1.0 })
                last = now
                self.scanMove(to: pos)
                if self.isVideo { self.pokeChrome() }          // 视频上快进快退时控件保持显示，能看到倍速提示
                try? await Task.sleep(nanoseconds: UInt64(ScanMath.tick * 1e9))
            }
        }
    }

    func endScan() {
        guard scanDirection != 0 else { return }
        scanDirection = 0
        scanEndedAt = CACurrentMediaTime()
        scanTask?.cancel(); scanTask = nil
        withAnimation(Motion.toggle) { scanRate = 0 }
        let pos = position
        scanFadeTask?.cancel()
        scanFadeTask = Task { [weak self] in
            guard let self else { return }
            self.engine.seek(absolute: pos, exact: true)
            try? await Task.sleep(nanoseconds: 90_000_000)            // 等新位置的音频解码出来
            await self.fadeVolume(from: 0, to: self.effectiveVolume, steps: ScanMath.fadeInSteps)
            if !Task.isCancelled { self.engine.setDouble("volume", self.volume); self.scanVolumeOverride = false }
        }
    }

    /// 刚结束快进快退时，按钮的“轻点”动作不要再切歌
    var scanJustEnded: Bool { CACurrentMediaTime() - scanEndedAt < 0.4 }

    private func fadeVolume(from: Double, to: Double, steps: Int) async {
        for v in ScanMath.fadeVolumes(from: from, to: to, steps: steps) {
            if Task.isCancelled { return }
            engine.setDouble("volume", v)
            try? await Task.sleep(nanoseconds: UInt64(ScanMath.fadeStep * 1e9))
        }
    }

    // MARK: 播放条按钮：轻点切歌，长按快进快退
    func scanButtonTapped(_ dir: Int) {
        if scanDirection != 0 { endScan(); return }
        if scanJustEnded { return }
        if dir > 0 { next() } else { previous() }
    }

    // MARK: 键盘 ← →：按一下跳设定步长（默认 15 秒），按住不放连续快进快退
    func arrowKeyDown(_ dir: Int, isRepeat: Bool) {
        if !isRepeat {
            scanKeyDown = (dir, CACurrentMediaTime())
            seek(by: Double(dir) * seekStepSeconds)
        } else if scanDirection == 0, let k = scanKeyDown, k.dir == dir, CACurrentMediaTime() - k.at > 0.25 {
            beginScan(dir)
        }
    }
    func arrowKeyUp(_ dir: Int) {
        if scanKeyDown?.dir == dir { scanKeyDown = nil }
        if scanDirection == dir { endScan() }
    }
}
