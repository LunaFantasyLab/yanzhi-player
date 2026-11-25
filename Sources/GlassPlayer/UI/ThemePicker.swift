// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import PlayerCore

/// 主题选择：一排排纯色圆珠（渐变 + 一道釉光），选中的那颗外面一圈柔光；
/// 长按任意一颗进入排序（像 iPhone 主屏那样轻轻晃），拖到想要的位置；只挪不删，顺序记住。
struct ThemePicker: View {
    @Environment(PlayerController.self) private var player
    var columns = 5
    @Namespace private var ns
    @State private var hovered: AppTheme?
    @State private var dragging: AppTheme?
    @State private var suppressTap = false

    var body: some View {
        let reorder = player.isReorderingThemes
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("配色主题").font(.system(size: 15, weight: .bold))
                    Text(reorder ? "拖动排序" : "\(player.theme.name) · \(player.theme.subtitle)")
                        .font(.system(size: 11.5)).opacity(0.6)
                        .contentTransition(.opacity)
                        .animation(Motion.toggle, value: player.theme)
                }
                Spacer(minLength: 8)
                if reorder {
                    Button("完成") { player.endThemeReorder() }
                        .buttonStyle(GlassChipStyle(selected: true, accent: Color(player.palette.accent), fontSize: 11.5))
                        .keyboardShortcut(.cancelAction)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 12), count: columns), spacing: 14) {
                ForEach(Array(player.themeOrder.enumerated()), id: \.element) { i, t in
                    cell(t, index: i, reorder: reorder)
                }
            }
        }
        .foregroundStyle(Color.ink)
        .padding(18)
        .animation(Motion.panel, value: reorder)
        .onDisappear { player.endThemeReorder() }
    }

    @ViewBuilder private func cell(_ t: AppTheme, index i: Int, reorder: Bool) -> some View {
        let base = swatch(t, reorder: reorder)
        if reorder {
            base
                .modifier(Jiggle(on: dragging != t, phase: Double(i % 3)))
                .opacity(dragging == t ? 0.35 : 1)
                .onDrag { dragging = t; return NSItemProvider(object: t.rawValue as NSString) }
                .onDrop(of: [.text], delegate: ThemeDrop(target: t, dragging: $dragging, player: player))
                .help(t.name)
        } else {
            Button {
                if suppressTap { suppressTap = false; return }
                player.setTheme(t)
            } label: { base }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.38).onEnded { _ in
                    suppressTap = true
                    player.beginThemeReorder()
                    after(0.25) { suppressTap = false }
                })
                .help("\(t.name)：\(t.subtitle)（长按可拖动排序）")
        }
    }

    private func swatch(_ t: AppTheme, reorder: Bool) -> some View {
        let selected = player.theme == t
        let isHover = hovered == t && !reorder
        let accent = Color(player.palette.accent)
        return VStack(spacing: 6) {
            ZStack {
                if selected {
                    // 选中：无边框，外圈一层柔光，在色样间弹簧滑动
                    Circle().fill(accent.opacity(0.42)).frame(width: 54, height: 54).blur(radius: 7)
                        .matchedGeometryEffect(id: "glow", in: ns)
                }
                ThemeSwatch(theme: t, coverPalette: player.coverPalette)
                    .frame(width: 44, height: 44)
                    .scaleEffect(selected ? 1.06 : 1)
            }
            .frame(width: 58, height: 58)
            .scaleEffect(isHover ? 1.08 : 1)
            Text(t.name).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .opacity(selected ? 1 : 0.7)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.hover) { hovered = h ? t : (hovered == t ? nil : hovered) } }
        .animation(Motion.toggle, value: selected)
    }
}

/// 排序时的轻晃：只动旋转（transform），每颗起点错开
private struct Jiggle: ViewModifier {
    let on: Bool
    let phase: Double
    @State private var tilt = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on ? (tilt ? 2.4 : -2.4) : 0))
            .animation(on ? .easeInOut(duration: 0.13 + phase * 0.012).repeatForever(autoreverses: true).delay(phase * 0.04) : .default, value: tilt)
            .onAppear { tilt = true }
    }
}

private struct ThemeDrop: DropDelegate {
    let target: AppTheme
    @Binding var dragging: AppTheme?
    let player: PlayerController
    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target else { return }
        player.moveTheme(d, onto: target)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
    func dropExited(info: DropInfo) {}
}

/// 单个色样：纯扁平圆形渐变（零椭圆气泡高光、零底部球体暗部、零立体阴影、无描边），只留一道极克制的平面斜向微光泽。
struct ThemeSwatch: View {
    let theme: AppTheme
    let coverPalette: AmbientPalette
    var body: some View {
        ZStack {
            if theme == .system {
                // 纯扁平斜切半白半黑，清晰直觉表达跟随系统明暗
                Circle().fill(LinearGradient(stops: [
                    .init(color: Color(white: 0.97), location: 0.0),
                    .init(color: Color(white: 0.92), location: 0.485),
                    .init(color: Color(white: 0.14), location: 0.515),
                    .init(color: Color(white: 0.07), location: 1.0),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                Circle().fill(LinearGradient(colors: Self.colors(theme, coverPalette), startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            // 纯平面极轻丝光（无立体弧面体积感）
            Circle().fill(LinearGradient(stops: [
                .init(color: .white.opacity(theme == .white ? 0.24 : (theme.isPureBlack ? 0.18 : 0.14)), location: 0),
                .init(color: .white.opacity(0.02), location: 0.48),
                .init(color: .clear, location: 0.72),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .blendMode(.plusLighter)
        }
        .clipShape(Circle())
    }

    static func colors(_ t: AppTheme, _ cover: AmbientPalette) -> [Color] {
        if t == .system { return [Color(white: 0.96), Color(white: 0.10)] }
        if t == .white { return [Color(white: 1.0), Color(RGB(hex: 0xE2E8F0))] }
        if t == .black { return [Color(RGB(hex: 0x3D424F)), Color(RGB(hex: 0x15171E))] }
        if t.isPureBlack { return [Color(RGB(hex: 0x1A1A20)), .black] }
        if t.followsCover {
            let p = cover.softLight
            return [Color(p.secondary), Color(p.tertiary), Color(p.accent)]
        }
        let p = t.softLightPalette ?? cover.softLight
        return [Color(p.secondary), Color(p.tertiary)]
    }
}

/// 顶栏右侧的主题按钮：点开玻璃弹层
struct ThemeButton: View {
    @Environment(PlayerController.self) private var player
    @State private var show = false
    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "paintpalette")
                .symbolEffect(.bounce, value: player.theme)
        }
        .buttonStyle(GlassIconButtonStyle(size: 32, active: show, accent: Color(player.palette.accent)))
        .help("配色主题")
        .onAppear { if UserDefaults.standard.bool(forKey: "openThemePicker") { after(0.8) { show = true } } }   // 截图/演示用启动参数
        .popover(isPresented: $show, arrowEdge: .bottom) {
            ThemePicker().environment(player)
                .environment(\.glassMidnight, player.look.isPureBlack)
                .environment(\.glassLight, player.look.isLight)
                .environment(\.glassLiuli, player.look.isLiuli)
                .preferredColorScheme(player.look.isLight ? .light : .dark)
                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: Color(player.palette.glassTint), amount: 0.07, variant: .floating)
                .clearSystemPopoverChrome()
        }
    }
}

/// 系统「设置…」窗口（⌘,）：极简直观分组列表，零冗长说明/引导文字，所有高频控制一目了然
struct SettingsView: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSection("窗口与外观") {
                        SettingsRow("启动时") {
                            Picker("", selection: Bindable(player).startupMode) {
                                ForEach(StartupMode.allCases) { m in
                                    Text(m.title).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 158)
                        }
                        SettingsRow("关闭窗口时") {
                            Picker("", selection: Bindable(player).closeAction) {
                                ForEach(WindowCloseAction.allCases) { a in
                                    Text(a.title).tag(a)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 158)
                        }
                        SettingsRow("窗口始终置顶") {
                            Toggle("", isOn: Binding(get: { player.isFloating }, set: { if $0 != player.isFloating { player.toggleFloating() } }))
                                .labelsHidden()
                        }
                        SettingsRow("配色主题") {
                            Picker("", selection: Binding(get: { player.theme }, set: { player.setTheme($0) })) {
                                ForEach(player.themeOrder) { t in
                                    Text(t.name).tag(t)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 158)
                        }
                    }

                    SettingsSection("播放与音效") {
                        SettingsRow("循环模式") {
                            Picker("", selection: Binding(get: { player.queue.repeatMode }, set: { player.setRepeat($0) })) {
                                Text("关闭").tag(RepeatMode.off)
                                Text("列表").tag(RepeatMode.all)
                                Text("单曲").tag(RepeatMode.one)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 158)
                        }
                        SettingsRow("随机播放") {
                            Toggle("", isOn: Binding(get: { player.queue.shuffle }, set: { player.setShuffle($0) }))
                                .labelsHidden()
                        }
                        SettingsRow("均衡器") {
                            Toggle("", isOn: Binding(get: { player.eq.enabled }, set: { player.setEQEnabled($0) }))
                                .labelsHidden()
                        }
                        SettingsRow("区间循环无缝接缝") {
                            Toggle("", isOn: Bindable(player).loopSeamAlign)
                                .labelsHidden()
                        }
                        SettingsRow("快进 / 快退步长") {
                            Picker("", selection: Bindable(player).seekStepSeconds) {
                                Text("5 秒").tag(5.0)
                                Text("10 秒").tag(10.0)
                                Text("15 秒").tag(15.0)
                                Text("30 秒").tag(30.0)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 210)
                        }
                    }

                    SettingsSection("封面与歌词") {
                        SettingsRow("联网匹配官方封面") {
                            Toggle("", isOn: Binding(get: { player.onlineCoversEnabled }, set: { player.setOnlineCoversEnabled($0, quiet: true) }))
                                .labelsHidden()
                        }
                        SettingsRow("iTunes 封面补充") {
                            Toggle("", isOn: Binding(get: { player.iTunesCoversEnabled }, set: { player.setITunesCovers($0, quiet: true) }))
                                .labelsHidden()
                                .disabled(!player.onlineCoversEnabled)
                        }
                        SettingsRow("自动搜索歌词") {
                            Toggle("", isOn: Binding(get: { player.lyricsEnabled }, set: { player.setLyricsEnabled($0, quiet: true) }))
                                .labelsHidden()
                        }
                        SettingsRow("封面与歌词缓存") {
                            Button("清除") { player.clearOnlineCache() }
                                .controlSize(.small)
                        }
                    }

                    SettingsSection("软件") {
                        SettingsRow("版本 \(UpdateModel.shared.currentVersion)") {
                            Button("检查更新") { UpdateModel.shared.checkNow() }
                                .controlSize(.small)
                        }
                        SettingsRow("键盘快捷键") {
                            Button("查看") {
                                player.mainWindow?.makeKeyAndOrderFront(nil)
                                if !player.showShortcuts { player.toggleShortcutsHelp() }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(20)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .foregroundStyle(Color.ink)
        .environment(\.glassMidnight, player.look.isPureBlack)
        .environment(\.glassLight, player.look.isLight)
        .environment(\.glassLiuli, player.look.isLiuli)
        .preferredColorScheme(player.look.isLight ? .light : .dark)
        .frame(width: 460, height: 628)
    }
}

private struct SettingsSection<Content: View>: View {
    @Environment(PlayerController.self) private var player
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.ink.opacity(0.56))
                .padding(.leading, 8)
            VStack(spacing: 0) {
                content
            }
            .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: Color(player.palette.glassTint), amount: 0.07)
            .obsidianChrome()
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control
    init(_ title: String, @ViewBuilder control: () -> Control) { self.title = title; self.control = control() }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.inkFill.opacity(0.06)).frame(height: 0.5).padding(.horizontal, 12)
        }
    }
}
