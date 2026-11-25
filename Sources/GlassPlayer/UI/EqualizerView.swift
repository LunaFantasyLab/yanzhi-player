// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import PlayerCore

/// 均衡器（2026-11-23 按宣传片 v21 逐项对齐，所见即所得）：
/// 黑曜石面板、无边框；左上「均衡器」+ 开关 +「已开启」，下面一排预设；右上 16 段 / 32 段、耳机校正、•••；
/// 推子区里由后到前：32 路律动彩条（只在频段区内）→ 天青发光响应曲线 → 推子（细槽、零线、增益柱、圆把手）；
/// 悬停 / 拖动的那一段上方出白色数值胶囊「+9.0 dB · 1.1 kHz」。
struct EqualizerView: View {
    @Environment(PlayerController.self) private var player
    @State private var showSave = false
    @State private var newName = ""
    @State private var appeared = false

    var body: some View {
        let on = player.eq.enabled
        let isLight = player.look.isLight
        let eqPalette = EQThemePalette(palette: player.palette, isLight: isLight)
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("均衡器").font(.system(size: 20, weight: .bold))
                GlassSwitch(isOn: on, accent: eqPalette.accentColor) { player.setEQEnabled($0) }
                    .help(on ? "关掉均衡器（原声输出）" : "打开均衡器")
                Spacer(minLength: 12)
                EQSegment(selection: player.eq.bandCount, theme: eqPalette) { c in withAnimation(Motion.panel) { player.setBandCount(c) } }
                    .frame(width: 150)
                Button { player.toggleAutoEqPanel() } label: {
                    Label(player.autoEqEnabled ? (player.autoEqEntry?.name ?? "耳机校正") : "耳机校正", systemImage: "headphones").lineLimit(1)
                }
                .buttonStyle(EQChipStyle(selected: player.autoEqEnabled, theme: eqPalette))
                .help("耳机校正（AutoEq）：按耳机型号套用测量得到的校正曲线，独立于均衡器")
                .contextMenu { MenuContent(nodes: [MenuCatalog.autoEqMenu(player)]) }
                Menu { MenuContent(nodes: MenuCatalog.equalizer(player).filter { if case .divider = $0.kind { return true }; return $0.title != "均衡器" }) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 24)
                }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize().opacity(0.8)
                .help("重置、存为预设、前级、段数、耳机校正")
            }
            Text(on ? "已开启" : "已关闭 · 原声输出")
                .font(.system(size: 11.5)).opacity(0.55).contentTransition(.opacity)
                .padding(.top, -8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(player.allPresets) { p in
                        Button(p.name) { withAnimation(Motion.panel) { player.applyPreset(p) } }
                            .buttonStyle(EQChipStyle(selected: player.eq.presetID == p.id, theme: eqPalette))
                            .contextMenu { if !p.isBuiltIn { Button("删除预设", role: .destructive) { withAnimation(Motion.panel) { player.deletePreset(p) } } } }
                    }
                }
                .padding(.vertical, 6).padding(.horizontal, 2)
            }
            .popover(isPresented: $showSave, arrowEdge: .bottom) { savePopover }

            EQBandArea(eq: player.eq, spectrum: player.trackSpectrum, position: player.position,
                       speed: player.speed, isPlaying: player.isPlaying, muted: player.muted, volume: player.volume,
                       on: on, theme: eqPalette) { g, i in player.setEQGain(g, band: i) } preamp: { player.setPreamp($0) }
                .frame(maxHeight: .infinity)
                .id(player.eq.bandCount)
                .transition(.opacity)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
        .frame(minHeight: 420)
        // 面板外观与播放列表、整体配色主题完全统一（跟随当前所选主题与封面氛围，绝不写死固定底色）
        .glass(shape, tint: Color(player.palette.glassTint), amount: 0.08)
        .contextMenu { MenuContent(nodes: MenuCatalog.equalizer(player)) }
        .padding(.horizontal, 8)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
        .onAppear {
            player.ensureTrackSpectrum()
            withAnimation(EQLook.enter) { appeared = true }
        }
        .onChange(of: player.current?.id) { _, _ in player.ensureTrackSpectrum() }
        .onDisappear { appeared = false }
    }

    private var savePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("保存当前设置为预设").font(.headline)
            TextField("预设名称", text: $newName).textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit(save)
            HStack { Spacer(); Button("取消") { showSave = false }; Button("保存", action: save).keyboardShortcut(.defaultAction).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .padding(16)
        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: Color(player.palette.glassTint), amount: 0.06, variant: .floating)
        .clearSystemPopoverChrome()
    }

    private func save() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(Motion.panel) { player.savePreset(named: newName) }
        showSave = false
    }
}

/// 均衡器布局常量（动态配色由 `EQThemePalette` 从当前 `player.palette` 实时派生，与全软件主题统一）
enum EQLook {
    /// easeOutQuint 0.42 s
    static let enter = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)
    // 推子区边距：左边留给前级 + 分隔线，上面留给数值胶囊，下面是频率标签
    static let left: CGFloat = 86, right: CGFloat = 24, top: CGFloat = 32, bottom: CGFloat = 24
}

/// 动态跟随当前软件主题/封面的均衡器配色（覆盖开关、胶囊、曲线、推子、32 路实时音频彩条）
struct EQThemePalette: Equatable {
    let low: RGB
    let mid: RGB
    let high: RGB
    let isLight: Bool

    init(palette: AmbientPalette, isLight: Bool) {
        self.isLight = isLight
        func tune(_ c: RGB, minL: Double, maxL: Double, boostChroma: Double = 1.08) -> RGB {
            let lab = OKLab(c)
            let L = min(max(lab.L, minL), maxL)
            return OKLab(L: L, a: lab.a * boostChroma, b: lab.b * boostChroma).rgb
        }
        if isLight {
            // 白主题：精致暖橙/深岩高对比，在浅磨砂玻璃上干净利落
            let acc = tune(palette.accent, minL: 0.52, maxL: 0.66, boostChroma: 1.10)
            let sec = OKLab(palette.accent).mix(OKLab(RGB(hex: 0x334155)), 0.35).rgb
            let hi  = tune(palette.accent, minL: 0.60, maxL: 0.74, boostChroma: 1.0)
            self.low = sec; self.mid = acc; self.high = hi
        } else {
            let secLab = OKLab(palette.secondary)
            let accLab = OKLab(palette.accent)
            let terLab = OKLab(palette.tertiary)
            if max(secLab.chroma, max(accLab.chroma, terLab.chroma)) < 0.035 {
                // 黑 / 纯黑夜间 / 月白等极简无彩主题：丝银白光光谱，清冷克制
                self.low  = RGB(hex: 0x8E9AAF)
                self.mid  = RGB(hex: 0xDCE3F0)
                self.high = RGB(hex: 0xF8FAFC)
            } else {
                // 所有彩色主题与跟随封面：直接提取当前主题三色光谱并在 OKLab 内提亮保清晰度
                self.low  = tune(palette.secondary, minL: 0.58, maxL: 0.78)
                self.mid  = tune(palette.accent,    minL: 0.68, maxL: 0.86)
                self.high = tune(palette.tertiary,  minL: 0.72, maxL: 0.90)
            }
        }
    }

    var accentColor: Color { Color(mid) }
    var lowColor: Color { Color(low) }
    var highColor: Color { Color(high) }
    var activeFill: LinearGradient { LinearGradient(colors: [Color(low), Color(mid)], startPoint: .leading, endPoint: .trailing) }
    var spectrumGradient: LinearGradient { LinearGradient(colors: [Color(low), Color(mid), Color(high)], startPoint: .leading, endPoint: .trailing) }
    /// 选中胶囊内的文字色：按选中色自身明度自动切深/浅，保证任何主题下高对比可读
    var activeInk: Color {
        let avgL = (OKLab(low).L + OKLab(mid).L) * 0.5
        return avgL > 0.66 ? Color(RGB(hex: 0x0A101C)) : .white
    }

    func rgb(at u: Double) -> RGB {
        let t = min(max(u, 0), 1)
        if t < 0.5 {
            let k = t / 0.5
            return RGB(low.r + (mid.r - low.r) * k, low.g + (mid.g - low.g) * k, low.b + (mid.b - low.b) * k)
        } else {
            let k = (t - 0.5) / 0.5
            return RGB(mid.r + (high.r - mid.r) * k, mid.g + (high.g - mid.g) * k, mid.b + (high.b - mid.b) * k)
        }
    }
    func color(at u: Double) -> Color { Color(rgb(at: u)) }
}

/// 预设 / 耳机校正胶囊：选中态自动跟随当前主题渐变与自适应对比文字，未选中态跟随明暗玻璃
struct EQChipStyle: ButtonStyle {
    var selected = false
    var theme: EQThemePalette
    func makeBody(configuration: Configuration) -> some View { Chip(configuration: configuration, selected: selected, theme: theme) }
    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let theme: EQThemePalette
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? theme.activeInk : Color.ink.opacity(hover ? 0.94 : 0.74))
                .padding(.horizontal, 12).frame(height: 26)
                .background {
                    ZStack {
                        Capsule().fill(Color.inkFill.opacity(configuration.isPressed ? 0.16 : (hover ? 0.12 : 0.07)))
                        Capsule().fill(theme.activeFill).opacity(selected ? 1 : 0)
                    }
                }
                .shadow(color: theme.accentColor.opacity(selected ? 0.36 : 0), radius: 9, y: 4)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.hover, value: hover)
                .animation(Motion.toggle, value: selected)
                .onHover { hover = $0 }
        }
    }
}

/// 16 段 / 32 段：随主题联动的渐变滑块
struct EQSegment: View {
    var selection: EQBandCount
    var theme: EQThemePalette
    var onSelect: (EQBandCount) -> Void
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach([EQBandCount.sixteen, .thirtyTwo], id: \.self) { c in
                let sel = c == selection
                Button { onSelect(c) } label: {
                    Text(c == .sixteen ? "16 段" : "32 段")
                        .font(.system(size: 12, weight: sel ? .bold : .medium))
                        .foregroundStyle(sel ? theme.activeInk : Color.ink.opacity(0.74))
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .background {
                            if sel {
                                Capsule().fill(theme.activeFill)
                                    .shadow(color: theme.accentColor.opacity(0.36), radius: 9, y: 4)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.inkFill.opacity(0.08)))
        .animation(Motion.panel, value: selection)
    }
}

/// 推子区：彩条、曲线、推子共用同一套横向坐标，彩条和曲线不会伸出频段区
struct EQBandArea: View {
    var eq: EQState
    var spectrum: AudioSpectrum?
    var position: Double
    var speed: Double
    var isPlaying: Bool
    var muted: Bool
    var volume: Double
    var on: Bool
    var theme: EQThemePalette
    var onGain: (Double, Int) -> Void
    var preamp: (Double) -> Void
    @State private var focused: Int?
    @State private var dragging: Int?
    @State private var shown = false

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let band = CGRect(x: EQLook.left, y: EQLook.top, width: max(10, W - EQLook.left - EQLook.right), height: max(10, H - EQLook.top - EQLook.bottom))
            let n = eq.gains.count
            let colW = band.width / CGFloat(max(1, n))
            ZStack(alignment: .topLeading) {
                EQSpectrumBarsView(eq: eq, spectrum: spectrum, position: position, speed: speed,
                                   isPlaying: isPlaying, muted: muted, volume: volume, theme: theme)
                    .frame(width: band.width, height: band.height)
                    .offset(x: band.minX, y: band.minY)
                    .opacity(on ? (theme.isLight ? 0.34 : 0.44) : 0.14)
                    .allowsHitTesting(false)
                // 零线
                Rectangle().fill(Color.inkFill.opacity(0.10)).frame(width: band.width, height: 1)
                    .offset(x: band.minX, y: band.midY)
                    .allowsHitTesting(false)
                ResponseCurve(eq: eq, colW: colW, theme: theme)
                    .frame(width: band.width, height: band.height)
                    .offset(x: band.minX, y: band.minY)
                    .opacity(on ? 1 : 0.35)
                    .allowsHitTesting(false)
                // 前级 + 1px 分隔线
                PreampFader(value: eq.preamp, onChange: preamp)
                    .frame(width: 44, height: band.height + EQLook.bottom)
                    .offset(x: 8, y: band.minY)
                Rectangle().fill(Color.inkFill.opacity(0.14)).frame(width: 1, height: band.height)
                    .offset(x: EQLook.left - 14, y: band.minY)
                ForEach(Array(zip(eq.gains, eq.frequencies).enumerated()), id: \.offset) { i, gf in
                    let u = Double(i) / Double(max(1, n - 1))
                    BandFader(value: gf.0, frequency: gf.1, color: theme.color(at: u), lowColor: theme.lowColor,
                              narrow: eq.bandCount == .thirtyTwo, showLabel: eq.bandCount == .sixteen || i % 2 == 0,
                              trackHeight: band.height, focused: focused == i || dragging == i,
                              onFocus: { f in focused = f ? i : (focused == i ? nil : focused) },
                              onDrag: { d in dragging = d ? i : nil },
                              onChange: { onGain($0, i) })
                        .frame(width: colW, height: band.height + EQLook.bottom)
                        .offset(x: band.minX + CGFloat(i) * colW, y: band.minY)
                        .opacity(shown ? 1 : 0)
                        .scaleEffect(y: shown ? 1 : 0.4, anchor: .bottom)
                        .animation(Motion.stagger(i % 16), value: shown)
                }
                // 数值胶囊：悬停 / 拖动的那一段正上方（左右边缘防裁切）
                if let i = dragging ?? focused, eq.gains.indices.contains(i), eq.frequencies.indices.contains(i) {
                    let r = EQState.gainRange
                    let y = band.minY + band.height * (1 - (eq.gains[i] - r.lowerBound) / (r.upperBound - r.lowerBound))
                    let rawX = band.minX + (CGFloat(i) + 0.5) * colW
                    let clampedX = min(max(band.minX + 58, rawX), band.maxX - 58)
                    EQValuePill(gain: eq.gains[i], frequency: eq.frequencies[i], theme: theme)
                        .fixedSize()
                        .position(x: clampedX, y: max(12, y - 22))
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .saturation(on ? 1 : 0.2)
            .animation(Motion.toggle, value: on)
            .animation(Motion.hover, value: focused)
        }
        .onAppear { shown = true }
    }
}

/// 数值胶囊：「+9.0 dB · 1.1 kHz」
struct EQValuePill: View {
    var gain: Double
    var frequency: Double
    var theme: EQThemePalette
    var body: some View {
        Text(String(format: "%+.1f dB · ", gain) + Self.freq(frequency))
            .font(.system(size: 12, weight: .heavy, design: .monospaced))
            .foregroundStyle(theme.isLight ? .white : Color(RGB(hex: 0x08121C)))
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(theme.isLight ? Color(RGB(hex: 0x12151E)).opacity(0.92) : Color.white.opacity(0.94)))
            .shadow(color: theme.accentColor.opacity(0.40), radius: 12, y: 8)
    }
    static func freq(_ f: Double) -> String {
        f >= 1000 ? String(format: f >= 10000 ? "%.0f kHz" : "%.1f kHz", f / 1000) : String(format: "%.0f Hz", f)
    }
}

/// 单段推子（随主题色渐变的增益柱与把手）
struct BandFader: View {
    var value: Double
    var frequency: Double
    var color: Color
    var lowColor: Color
    var narrow: Bool
    var showLabel: Bool
    var trackHeight: CGFloat
    var focused: Bool
    var onFocus: (Bool) -> Void
    var onDrag: (Bool) -> Void
    var onChange: (Double) -> Void
    @State private var dragging = false

    var body: some View {
        let h = trackHeight
        let r = EQState.gainRange
        let y = h * (1 - (value - r.lowerBound) / (r.upperBound - r.lowerBound))
        let mid = h / 2
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Capsule().fill(Color.inkFill.opacity(focused ? 0.14 : 0.08)).frame(width: narrow ? 4 : 5, height: h)
                Capsule().fill(LinearGradient(colors: [lowColor.opacity(0.45), color], startPoint: value >= 0 ? .bottom : .top, endPoint: value >= 0 ? .top : .bottom))
                    .frame(width: 5, height: max(2, abs(y - mid)))
                    .offset(y: min(y, mid))
                Group {
                    if narrow { Circle().fill(color).frame(width: dragging ? 13 : 10, height: dragging ? 13 : 10) }
                    else { Capsule().fill(color).frame(width: dragging ? 24 : 20, height: 10) }
                }
                .shadow(color: color.opacity(focused ? 0.95 : 0.72), radius: 6)
                .offset(y: y - (dragging && narrow ? 6.5 : 5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: h, alignment: .top)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { withAnimation(Motion.press) { dragging = true }; onDrag(true) }
                    let k = 1 - min(max(0, v.location.y / h), 1)
                    var db = r.lowerBound + k * (r.upperBound - r.lowerBound)
                    if abs(db) < 0.35 { db = 0 }        // 0 dB 磁吸
                    onChange((db * 2).rounded() / 2)
                }
                .onEnded { _ in withAnimation(Motion.press) { dragging = false }; onDrag(false) })
            .onTapGesture(count: 2) { withAnimation(Motion.panel) { onChange(0) } }
            Text(showLabel ? EQBandCount.label(for: frequency) : " ")
                .font(.system(size: narrow ? 9.5 : 10.5, weight: .medium)).opacity(0.55)
                .fixedSize()
                .frame(height: EQLook.bottom)
        }
        .animation(Motion.panel, value: value)
        .onHover { onFocus($0) }
        .accessibilityLabel("\(EQBandCount.label(for: frequency))：\(String(format: "%+.1f", value)) dB")
    }
}

/// 前级：8px 槽、自适应墨色把手、「前级」与数值
struct PreampFader: View {
    var value: Double
    var onChange: (Double) -> Void
    @State private var dragging = false
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let h = g.size.height
                let r = EQState.preampRange
                let y = h * (1 - (value - r.lowerBound) / (r.upperBound - r.lowerBound))
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.inkFill.opacity(0.09)).frame(width: 8).frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 3).fill(Color.ink).frame(width: dragging ? 26 : 22, height: 8)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1).offset(y: y - 4)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        let k = 1 - min(max(0, v.location.y / h), 1)
                        onChange(((r.lowerBound + k * (r.upperBound - r.lowerBound)) * 2).rounded() / 2)
                    }
                    .onEnded { _ in dragging = false })
                .onTapGesture(count: 2) { withAnimation(Motion.panel) { onChange(0) } }
                .animation(Motion.press, value: dragging)
            }
            Text("前级").font(.system(size: 10, weight: .semibold)).opacity(0.65)
            Text(String(format: "%.1f", value)).font(.system(size: 9).monospacedDigit()).opacity(0.55)
        }
        .help("前级增益（防止提升后削波，双击归零）")
    }
}

/// 32 路实时律动抖动音频彩条（120Hz CADisplayLink FrameClock 驱动 GPU CAGradientLayer，配色实时跟随当前软件主题）
struct EQSpectrumBarsView: View {
    var eq: EQState
    var spectrum: AudioSpectrum?
    var position: Double
    var speed: Double
    var isPlaying: Bool
    var muted: Bool
    var volume: Double
    var theme: EQThemePalette

    var body: some View {
        EQSpectrumLayerView(eq: eq, spectrum: spectrum, position: position, speed: speed,
                            isPlaying: isPlaying, muted: muted, volume: volume, theme: theme)
            .allowsHitTesting(false)
    }
}

private struct EQSpectrumLayerView: NSViewRepresentable {
    var eq: EQState
    var spectrum: AudioSpectrum?
    var position: Double
    var speed: Double
    var isPlaying: Bool
    var muted: Bool
    var volume: Double
    var theme: EQThemePalette

    final class V: NSView {
        private static let count = 32
        private static let gap: CGFloat = 6
        private var bars: [CAGradientLayer] = []
        private var smoothed = [Double](repeating: 0.12, count: 32)
        private var clockID: UUID?
        private var appliedTheme: EQThemePalette?

        var eq = EQState()
        var spectrum: AudioSpectrum?
        var syncPosition: Double = 0
        var syncMediaTime: CFTimeInterval = CACurrentMediaTime()
        var speed: Double = 1
        var isPlaying = false
        var muted = false
        var volume: Double = 80

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layerContentsRedrawPolicy = .never
            let root = CALayer()
            root.masksToBounds = false
            layer = root
            let none: [String: CAAction] = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "contentsScale": NSNull(), "colors": NSNull()]
            for _ in 0..<Self.count {
                let g = CAGradientLayer()
                g.locations = [0.0, 0.35, 1.0]
                g.startPoint = CGPoint(x: 0.5, y: 0.0)
                g.endPoint = CGPoint(x: 0.5, y: 1.0)
                g.anchorPoint = CGPoint(x: 0.5, y: 1.0)
                g.cornerRadius = 6
                g.cornerCurve = .continuous
                g.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                g.actions = none
                root.addSublayer(g)
                bars.append(g)
            }
        }
        required init?(coder: NSCoder) { fatalError() }

        func applyTheme(_ theme: EQThemePalette) {
            guard appliedTheme != theme else { return }
            appliedTheme = theme
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for i in 0..<bars.count {
                let u = Double(i) / Double(max(1, bars.count - 1))
                let rgb = theme.rgb(at: u)
                func cg(_ a: Double) -> CGColor { CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: a) }
                bars[i].colors = [cg(1.0), cg(0.68), cg(0.02)]
            }
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                syncScale()
                startClock()
            } else {
                stopClock()
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            syncScale()
        }

        override func layout() {
            super.layout()
            syncScale()
            renderFrame(dt: 1.0 / 120.0, now: CACurrentMediaTime())
        }

        private func syncScale() {
            let sc = window?.backingScaleFactor ?? 2
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.contentsScale = sc
            for b in bars { if b.contentsScale != sc { b.contentsScale = sc } }
            CATransaction.commit()
        }

        private func startClock() {
            guard clockID == nil else { return }
            clockID = FrameClock.shared.subscribe { [weak self] dt, now in
                guard let self, self.window != nil else { return false }
                self.renderFrame(dt: dt, now: now)
                return true
            }
        }

        private func stopClock() {
            if let id = clockID { FrameClock.shared.unsubscribe(id); clockID = nil }
        }

        private func renderFrame(dt: Double, now: CFTimeInterval) {
            let w = bounds.width, h = bounds.height
            guard w > 4, h > 4 else { return }
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let activeAudio = isPlaying && !muted && volume > 0.5
            let volGain = min(1.0, max(0.25, volume / 80.0))
            let livePos = activeAudio ? syncPosition + max(0, now - syncMediaTime) * speed : syncPosition
            let liveBands = activeAudio ? spectrum?.sample(at: livePos) : nil
            let t = reduce ? 0.0 : now
            let gains = eq.gains
            let barW = max(3, (w - Self.gap * CGFloat(Self.count - 1)) / CGFloat(Self.count))
            // 120fps 丝滑物理追随（14ms 快起 / 42ms 顺落），杜绝任何阶梯跳动
            let riseK = 1.0 - exp(-dt / 0.014)
            let fallK = 1.0 - exp(-dt / 0.042)

            CATransaction.begin(); CATransaction.setDisableActions(true)
            for i in 0..<Self.count {
                let u = Double(i) / Double(Self.count - 1)
                let gIdx = min(max(0, Int((u * Double(max(1, gains.count - 1))).rounded())), max(0, gains.count - 1))
                let gainDB = gains.isEmpty ? 0.0 : gains[gIdx]
                let gainScale = 1.0 + (eq.enabled ? (gainDB / 24.0) * 0.65 : 0)

                let target: Double
                if let bands = liveBands, bands.indices.contains(i) {
                    let shimmer = reduce ? 0 : 0.035 * abs(sin(t * 7.4 + Double(i) * 0.62))
                    target = (0.14 + 0.72 * bands[i] * volGain + shimmer) * gainScale
                } else if activeAudio {
                    let wave = 0.5 + 0.5 * sin(t * 3.1 + Double(i) * 0.91) * cos(t * 1.7 - Double(i) * 0.23)
                    let energy = 0.45 + 0.35 * abs(cos(t * 7.8 - Double(i) * 0.37))
                    let arch = sin(u * .pi) * 0.3 + 0.7
                    target = ((0.22 + 0.40 * wave * arch) + 0.25 * abs(sin(t * 5.2 + Double(i) * 0.55)) * (0.5 + energy)) * volGain * gainScale
                } else {
                    let rest = 0.5 + 0.5 * sin(t * 0.9 + Double(i) * 0.45)
                    target = (0.10 + 0.06 * rest) * max(0.7, gainScale)
                }
                let clamped = min(0.84, max(0.10, target))
                let prev = smoothed[i]
                let cur = reduce ? clamped : prev + (clamped - prev) * (clamped > prev ? riseK : fallK)
                smoothed[i] = cur

                let barH = max(4, h * CGFloat(cur))
                let x = CGFloat(i) * (barW + Self.gap)
                let b = bars[i]
                b.bounds = CGRect(x: 0, y: 0, width: barW, height: barH)
                b.position = CGPoint(x: x + barW / 2, y: h)
            }
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> V {
        let v = V(frame: .zero)
        sync(v)
        return v
    }

    func updateNSView(_ v: V, context: Context) {
        sync(v)
    }

    private func sync(_ v: V) {
        v.eq = eq
        v.spectrum = spectrum
        v.syncPosition = position
        v.syncMediaTime = CACurrentMediaTime()
        v.speed = speed
        v.isPlaying = isPlaying
        v.muted = muted
        v.volume = volume
        v.applyTheme(theme)
    }
}

/// 响应曲线：实时跟随当前软件主题三色光谱渐变 + 柔光外发光；下方面积渐隐。横向和推子对齐（每段中心），纵向 ±18 dB 占满高度。
struct ResponseCurve: View {
    var eq: EQState
    var colW: CGFloat
    var theme: EQThemePalette
    var body: some View {
        let pts = Self.sample(eq)
        GeometryReader { g in
            let inset = colW / 2
            ZStack {
                CurveShape(points: pts, closed: true)
                    .fill(LinearGradient(colors: [theme.accentColor.opacity(0.24), theme.lowColor.opacity(0.09), theme.accentColor.opacity(0)], startPoint: .top, endPoint: .bottom))
                CurveShape(points: pts)
                    .stroke(theme.spectrumGradient, style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
                    .shadow(color: theme.accentColor.opacity(0.75), radius: 6)
            }
            .padding(.horizontal, inset)
            .frame(width: g.size.width, height: g.size.height)
        }
        .animation(Motion.panel, value: eq.gains)
    }

    static let samples = 128
    static func sample(_ eq: EQState) -> AnimatableVector {
        let fs = eq.frequencies
        guard let f0 = fs.first, let f1 = fs.last, f1 > f0 else { return AnimatableVector(values: []) }
        let bw = eq.bandCount.bandwidthOctaves
        var out = [Double](repeating: 0, count: samples)
        for s in 0..<samples {
            let f = f0 * pow(f1 / f0, Double(s) / Double(samples - 1))
            var db = 0.0
            for (fc, g) in zip(fs, eq.gains) {
                let x = log2(f / fc) / (bw / 2)
                db += g / (1 + x * x)     // 洛伦兹叠加，只用于显示
            }
            out[s] = max(-18, min(18, db))
        }
        return AnimatableVector(values: out)
    }
}

/// 可插值的数组（让曲线变化也走弹簧）
struct AnimatableVector: VectorArithmetic {
    var values: [Double]
    static var zero: AnimatableVector { AnimatableVector(values: []) }
    static func + (a: Self, b: Self) -> Self { combine(a, b, +) }
    static func - (a: Self, b: Self) -> Self { combine(a, b, -) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
    private static func combine(_ a: Self, _ b: Self, _ op: (Double, Double) -> Double) -> Self {
        let n = max(a.values.count, b.values.count)
        return AnimatableVector(values: (0..<n).map { i in op(i < a.values.count ? a.values[i] : 0, i < b.values.count ? b.values[i] : 0) })
    }
}

struct CurveShape: Shape {
    var points: AnimatableVector
    var closed = false
    var animatableData: AnimatableVector { get { points } set { points = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let v = points.values
        guard v.count > 1 else { return p }
        func pt(_ i: Int) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(v.count - 1),
                    y: rect.midY - rect.height / 2 * CGFloat(v[i] / 18))
        }
        p.move(to: pt(0))
        for i in 1..<v.count {
            let a = pt(i - 1), b = pt(i)
            p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        p.addLine(to: pt(v.count - 1))
        if closed { p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.closeSubpath() }
        return p
    }
}
