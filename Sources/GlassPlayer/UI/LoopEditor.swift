// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 区间时间输入条（播放条上方的一条扁平玻璃胶囊，弹簧展开）。
/// 起点 / 终点：可直接输入 mm:ss.ms、hh:mm:ss 或秒数，回车生效；±0.1 秒按钮；悬停时滚轮微调（⌥ 滚轮 0.01 秒）。
/// 和进度条双向同步：在进度条上 ⌥ 拖选、拖手柄时，这里的数字实时跟着变；这里改了，进度条上的区间立刻移动。
struct LoopEditor: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        let accent = Color(player.palette.accent)
        HStack(spacing: 10) {
            Image(systemName: "repeat.circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
            LoopTimeField(label: "起点", start: true)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).opacity(0.5)
            LoopTimeField(label: "终点", start: false)
            Divider().frame(height: 18).opacity(0.5)
            Button { player.toggleLoopSeamAlign() } label: {
                Label(player.loopSeamAlign ? "无缝接缝" : "硬切", systemImage: "waveform.path")
                    .font(.system(size: 11.5, weight: .medium)).labelStyle(.titleAndIcon)
                    .contentTransition(.opacity)
            }
            .buttonStyle(GlassChipStyle(selected: player.loopSeamAlign, accent: accent))
            .help(seamHelp)
            Button { player.findChorusAndLoop() } label: {
                Label(player.analyzingSections ? "分析中" : "副歌", systemImage: "music.note.list")
                    .font(.system(size: 11.5, weight: .medium)).labelStyle(.titleAndIcon).contentTransition(.opacity)
            }
            .buttonStyle(GlassChipStyle(selected: player.sections.first.map { s in player.abA.map { abs($0 - s.start) < 0.05 } ?? false } ?? false, accent: accent))
            .disabled(player.analyzingSections || player.current?.url.isFileURL != true)
            .help("自动找副歌并循环（⌥⌘G）；分析整首的重复结构和响度，不用 AI")
            Button { player.clearABLoop() } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(GlassIconButtonStyle(size: 26)).help("取消区间循环")
                .disabled(player.abA == nil)
            Button { player.toggleLoopEditor() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(GlassIconButtonStyle(size: 26)).help("收起（⌥⌘L）")
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glass(Capsule(), tint: Color(player.palette.glassTint), amount: 0.06, interactive: true, variant: .floating)
        .animation(Motion.toggle, value: player.loopSeamAlign)
    }

    private var seamHelp: String {
        guard player.loopSeamAlign else { return "已关：按你设的位置直接跳回（可能有轻微咔声）" }
        guard let r = player.loopSeamInfo else { return "开：自动把起点、终点挪到波形能连续接上的位置（各 ±12ms 内），接缝没有咔声" }
        return String(format: "已对齐：起点 %+.1fms、终点 %+.1fms；接缝跳变 %.3f → %.3f", r.shiftA, r.shiftB, r.jumpBefore, r.jumpAfter)
    }
}

/// 一个时间输入框 + ±0.1 秒按钮
private struct LoopTimeField: View {
    @Environment(PlayerController.self) private var player
    let label: String
    let start: Bool
    @State private var text = ""
    @State private var editing = false
    @State private var invalid = false
    @State private var hover = false
    @State private var monitor: Any?
    @FocusState private var focused: Bool

    private var value: Double? {
        if let r = player.loopPreview { return start ? r.lowerBound : r.upperBound }
        return start ? player.abA : player.abB
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).opacity(0.6)
            Button { player.nudgeLoop(start: start, by: -0.1) } label: { Image(systemName: "minus") }
                .buttonStyle(GlassIconButtonStyle(size: 22)).help("\(label)前移 0.1 秒")
            TextField("--:--.---", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 84, height: 24)
                .focused($focused)
                .background {
                    let r = RoundedRectangle(cornerRadius: 7, style: .continuous)
                    r.fill(Color.black.opacity(focused ? 0.22 : (hover ? 0.16 : 0.10)))
                        .overlay(r.strokeBorder(invalid ? Color.red.opacity(0.8) : Color.edge.opacity(focused ? 0.45 : 0), lineWidth: 1))
                }
                .onSubmit(commit)
                .onChange(of: focused) { _, f in editing = f; if !f { sync() } }
                .onHover { h in withAnimation(Motion.hover) { hover = h }; setWheel(h) }
                .help("输入 mm:ss.ms、hh:mm:ss 或秒数，回车生效；悬停滚轮 ±0.1 秒（按住 ⌥ ±0.01 秒）")
                .modifier(Shake(amount: invalid ? 1 : 0))
            Button { player.nudgeLoop(start: start, by: 0.1) } label: { Image(systemName: "plus") }
                .buttonStyle(GlassIconButtonStyle(size: 22)).help("\(label)后移 0.1 秒")
            Button { player.setLoopPoint(start: start, player.position) } label: { Image(systemName: "location.fill") }
                .buttonStyle(GlassIconButtonStyle(size: 22)).help("把当前位置设为\(label)")
        }
        .onAppear(perform: sync)
        .onDisappear { setWheel(false) }
        .onChange(of: value) { _, _ in if !editing { sync() } }
    }

    private func sync() { text = value.map { TimeFormat.precise($0) } ?? "" }

    private func commit() {
        guard let t = TimeFormat.parse(text), t >= 0, player.duration.map({ t <= $0 + 0.001 }) ?? true else {
            withAnimation(Motion.press) { invalid = true }
            after(0.6) { withAnimation(Motion.hover) { invalid = false } }
            return
        }
        player.setLoopPoint(start: start, t)
        focused = false
        after(0.05) { sync() }
    }

    /// 悬停时接管滚轮：上滚 +0.1 秒，下滚 −0.1 秒（⌥ 时 0.01 秒）
    private func setWheel(_ on: Bool) {
        if on, monitor == nil {
            var acc: CGFloat = 0
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
                acc += e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.1 : 1)
                guard abs(acc) >= 1 else { return nil }
                let step = e.modifierFlags.contains(.option) ? 0.01 : 0.1
                let n = acc > 0 ? 1.0 : -1.0
                acc = 0
                MainActor.assumeIsolated { player.nudgeLoop(start: start, by: n * step) }
                return nil
            }
        } else if !on, let m = monitor {
            NSEvent.removeMonitor(m); monitor = nil
        }
    }
}

/// 输入不合法时左右轻轻抖一下
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat { get { amount } set { amount = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(amount * .pi * 4), y: 0))
    }
}
