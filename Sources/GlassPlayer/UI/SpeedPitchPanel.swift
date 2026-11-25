// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 变速变调面板（播放条上方的扁平玻璃卡片，弹簧展开；⌥⌘K）。
/// 第一行速度：±1%、直接输入百分比、滑杆（1% 一格）、一键 100%。音高不变。
/// 第二行音调：±1 半音、±10 音分（悬停滚轮 ±1 音分）、一键原调。速度不变。音频、视频都能用。
struct SpeedPitchPanel: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        let accent = Color(player.palette.accent)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                rowIcon("speedometer", "速度", active: player.speed != 1, accent: accent)
                Button { player.speedStep(-0.01) } label: { Image(systemName: "minus") }
                    .buttonStyle(GlassIconButtonStyle(size: 24)).help("减慢 1%（[）")
                ValueField(display: SpeedPitch.speedText(player.speed), width: 58,
                           help: "输入百分比（如 101）回车生效；悬停滚轮 ±1%",
                           parse: { Double($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)).map { $0 / 100 } },
                           commit: { player.setSpeed($0) },
                           wheel: { player.speedStep(Double($0) * 0.01) })
                Button { player.speedStep(0.01) } label: { Image(systemName: "plus") }
                    .buttonStyle(GlassIconButtonStyle(size: 24)).help("加快 1%（]）")
                GlassLinearSlider(value: (min(2, max(0.5, player.speed)) - 0.5) / 1.5, accent: accent,
                                  ticks: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map { ($0 - 0.5) / 1.5 }) { t in
                    player.setSpeed(((0.5 + t * 1.5) * 100).rounded() / 100, hud: false)
                }
                .frame(width: 150, height: 20)
                    .help("50%–200%，1% 一格（更大范围用输入框：25%–400%）")
                resetButton(enabled: player.speed != 1, help: "恢复 100% 速度（\\）") { player.setSpeed(1) }
            }
            HStack(spacing: 8) {
                rowIcon("tuningfork", "音调", active: player.pitchSemitones != 0 || player.pitchCents != 0, accent: accent)
                Button { player.pitchStep(semitones: -1) } label: { Image(systemName: "minus") }
                    .buttonStyle(GlassIconButtonStyle(size: 24)).help("降低 1 半音（⌥-）")
                ValueField(display: String(format: "%+d", player.pitchSemitones), width: 40,
                           help: "半音（−12 到 +12），回车生效；悬停滚轮 ±1",
                           parse: { Double($0.replacingOccurrences(of: "+", with: "")) },
                           commit: { player.setPitch(semitones: Int($0.rounded()), cents: player.pitchCents) },
                           wheel: { player.pitchStep(semitones: $0) })
                Text("半音").font(.system(size: 11)).opacity(0.6)
                Button { player.pitchStep(semitones: 1) } label: { Image(systemName: "plus") }
                    .buttonStyle(GlassIconButtonStyle(size: 24)).help("升高 1 半音（⌥=）")
                Divider().frame(height: 16).opacity(0.4)
                Button { player.pitchStep(cents: -10) } label: { Image(systemName: "minus") }
                    .buttonStyle(GlassIconButtonStyle(size: 24)).help("降低 10 音分（⌃⌥-）")
                ValueField(display: String(format: "%+d", player.pitchCents), width: 40,
                           help: "音分（−50 到 +50，100 音分 = 1 半音），回车生效；悬停滚轮 ±1 音分",
                           parse: { Double($0.replacingOccurrences(of: "+", with: "")) },
                           commit: { player.setPitch(semitones: player.pitchSemitones, cents: Int($0.rounded())) },
                           wheel: { player.pitchStep(cents: $0) })
                Text("音分").font(.system(size: 11)).opacity(0.6)
                Button { player.pitchStep(cents: 10) } label: { Image(systemName: "plus") }
                    .buttonStyle(GlassIconButtonStyle(size: 24)).help("升高 10 音分（⌃⌥=）")
                resetButton(enabled: player.pitchSemitones != 0 || player.pitchCents != 0, help: "恢复原调（⌥0）") { player.setPitch(semitones: 0, cents: 0) }
                Spacer(minLength: 0)
                Button { player.resetSpeedPitch() } label: { Label("全部恢复", systemImage: "arrow.counterclockwise").font(.system(size: 11.5, weight: .medium)) }
                    .buttonStyle(GlassChipStyle(selected: false, accent: accent)).help("速度和音调一起恢复（⌥\\）")
                    .disabled(player.speed == 1 && player.pitchSemitones == 0 && player.pitchCents == 0)
                Button { player.toggleSpeedPitchPanel() } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(GlassIconButtonStyle(size: 24)).help("收起（⌥⌘K）")
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: Color(player.palette.glassTint), amount: 0.06, interactive: true, variant: .floating)
        .animation(Motion.toggle, value: player.speed)
        .animation(Motion.toggle, value: player.pitchSemitones)
        .animation(Motion.toggle, value: player.pitchCents)
    }

    private func rowIcon(_ sym: String, _ title: String, active: Bool, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: sym).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? accent : Color.ink.opacity(0.7))
                .symbolEffect(.bounce, value: active)
            Text(title).font(.system(size: 11.5, weight: .medium)).opacity(0.75)
        }
        .frame(width: 52, alignment: .leading)
    }

    private func resetButton(enabled: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(GlassIconButtonStyle(size: 24)).help(help)
            .opacity(enabled ? 1 : 0.35).disabled(!enabled)
            .scaleEffect(enabled ? 1 : 0.85)
    }
}

/// 可直接输入的数值框：显示值随状态平滑滚动，回车提交，非法输入抖一下，悬停时滚轮步进
private struct ValueField: View {
    let display: String
    let width: CGFloat
    let help: String
    let parse: (String) -> Double?
    let commit: (Double) -> Void
    let wheel: (Int) -> Void
    @State private var text = ""
    @State private var editing = false
    @State private var invalid = false
    @State private var hover = false
    @State private var monitor: Any?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            let r = RoundedRectangle(cornerRadius: 7, style: .continuous)
            r.fill(Color.black.opacity(focused ? 0.22 : (hover ? 0.16 : 0.10)))
                .overlay(r.strokeBorder(invalid ? Color.red.opacity(0.8) : Color.edge.opacity(focused ? 0.45 : 0), lineWidth: 1))
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain).multilineTextAlignment(.center)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand { editing = false }
            } else {
                Text(display)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .frame(width: width, height: 24)
        .contentShape(Rectangle())
        .onTapGesture { text = display.replacingOccurrences(of: "%", with: ""); editing = true; after(0.02) { focused = true } }
        .onChange(of: focused) { _, f in if !f { editing = false } }
        .onHover { h in withAnimation(Motion.hover) { hover = h }; setWheel(h) }
        .onDisappear { setWheel(false) }
        .help(help)
        .modifier(ShakeX(amount: invalid ? 1 : 0))
        .animation(Motion.toggle, value: display)
    }

    private func submit() {
        guard let v = parse(text) else {
            withAnimation(Motion.press) { invalid = true }
            after(0.6) { withAnimation(Motion.hover) { invalid = false } }
            return
        }
        commit(v); editing = false; focused = false
    }

    private func setWheel(_ on: Bool) {
        if on, monitor == nil {
            var acc: CGFloat = 0
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
                acc += e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.1 : 1)
                guard abs(acc) >= 1 else { return nil }
                let n = acc > 0 ? 1 : -1
                acc = 0
                MainActor.assumeIsolated { wheel(n) }
                return nil
            }
        } else if !on, let m = monitor {
            NSEvent.removeMonitor(m); monitor = nil
        }
    }
}

private struct ShakeX: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat { get { amount } set { amount = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(amount * .pi * 4), y: 0))
    }
}

/// 播放条上的变速变调小胶囊（不在 100%/原调时出现）：点一下展开面板
struct SpeedPitchChip: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        Button { player.toggleSpeedPitchPanel() } label: {
            HStack(spacing: 3) {
                Image(systemName: "speedometer").font(.system(size: 9, weight: .bold))
                Text(chipText).font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Color(player.palette.accent))
            .padding(.horizontal, 6).frame(height: 16)
            .background(Capsule().fill(Color(player.palette.accent).opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help("变速 / 变调：点一下打开面板（⌥⌘K）")
        .contextMenu { MenuContent(nodes: [MenuCatalog.speedMenu(player)]) }
    }
    private var chipText: String {
        var parts: [String] = []
        if player.speed != 1 { parts.append(SpeedPitch.speedText(player.speed)) }
        if player.pitchSemitones != 0 || player.pitchCents != 0 {
            parts.append(player.pitchCents == 0 ? String(format: "%+d", player.pitchSemitones) : String(format: "%+d·%+d¢", player.pitchSemitones, player.pitchCents))
        }
        return parts.joined(separator: " ")
    }
}
