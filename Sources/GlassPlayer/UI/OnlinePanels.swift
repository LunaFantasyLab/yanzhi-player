// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 识别进度胶囊：进度条 + 状态 + 取消
struct ASRProgressCapsule: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        let accent = Color(player.palette.accent)
        HStack(spacing: 10) {
            Image(systemName: "waveform.badge.mic").font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(player.asrStatus).font(.system(size: 12, weight: .medium)).contentTransition(.numericText())
                .frame(width: 150, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.inkFill.opacity(0.16))
                Capsule().fill(accent).frame(width: max(4, 160 * CGFloat(player.asrProgress ?? 0)))
            }
            .frame(width: 160, height: 4)
            Button { player.cancelASR() } label: { Image(systemName: "xmark") }
                .buttonStyle(GlassIconButtonStyle(size: 24)).help("取消识别")
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 12).frame(height: 38)
        .glass(Capsule(), tint: Color(player.palette.glassTint), amount: 0.06, interactive: true, variant: .floating)
    }
}

/// 在线字幕搜索面板
struct SubtitleSearchPanel: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        @Bindable var p = player
        let accent = Color(player.palette.accent)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble").font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                Text("在线字幕").font(.system(size: 12.5, weight: .semibold))
                SearchField(text: $p.subtitleQuery, placeholder: "片名或关键词", onSubmit: { player.searchSubtitles() })
                    .frame(width: 220)
                Button { player.searchSubtitles() } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(GlassIconButtonStyle(size: 26)).help("搜索（OpenSubtitles：先按文件指纹，再按关键词）")
                Menu {
                    ForEach(SubtitleSearch.webSearches(player.subtitleQuery), id: \.0) { name, url in
                        Button(name) { player.openSubtitleSite(url) }
                    }
                } label: { Image(systemName: "safari") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("在字幕网站里搜（用浏览器打开）")
                Spacer(minLength: 0)
                Button { player.toggleSubtitlePanel() } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(GlassIconButtonStyle(size: 24)).help("收起")
            }
            Text(player.subtitleMessage).font(.system(size: 11)).opacity(0.6).lineLimit(1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(player.subtitleResults) { r in
                        Button { player.downloadSubtitle(r) } label: {
                            HStack(spacing: 8) {
                                Text(r.language).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent).frame(width: 64, alignment: .leading)
                                Text(r.fileName).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                if r.matchedByHash { Text("指纹匹配").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 5).background(Capsule().fill(accent.opacity(0.18))) }
                                Text(r.format.uppercased()).font(.system(size: 10, weight: .medium)).opacity(0.55)
                                Text("\(r.downloads)").font(.system(size: 10).monospacedDigit()).opacity(0.45).frame(width: 52, alignment: .trailing)
                            }
                            .padding(.horizontal, 8).frame(height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .frame(height: player.subtitleResults.isEmpty ? 0 : min(220, CGFloat(player.subtitleResults.count) * 26))
            .overlay { if player.subtitleSearching { ProgressView().controlSize(.small) } }
        }
        .foregroundStyle(Color.ink)
        .padding(12).frame(width: 560)
        .glass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: Color(player.palette.glassTint), amount: 0.06, interactive: true, variant: .floating)
        .animation(Motion.panel, value: player.subtitleResults.count)
    }
}

/// AutoEq 耳机校正面板（宽敞舒展布局 + 右侧宽松可滚索引与透明首字母下拉菜单）
struct AutoEqPanel: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        @Bindable var p = player
        let accent = Color(player.palette.accent)
        let scopedPool = player.autoEqBrand != nil ? player.autoEqBrandModels : player.autoEqIndex
        let hits = AutoEq.search(scopedPool, player.autoEqQuery, limit: 60)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "headphones").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(accent)
                Text("耳机校正").font(.system(size: 14, weight: .semibold)).tracking(0.3)
                SearchField(text: $p.autoEqQuery, placeholder: player.autoEqBrand.map { "在 \($0) 中搜型号…" } ?? "搜品牌或型号，如 Sony、AirPods Pro、HD 650", onSubmit: {})
                    .frame(width: 340)
                Toggle("", isOn: Binding(get: { player.autoEqEnabled }, set: { player.setAutoEqEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden().tint(accent)
                    .disabled(player.autoEqCurve == nil).help("开 / 关校正")
                Spacer(minLength: 0)
                Button { player.toggleAutoEqPanel() } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(GlassIconButtonStyle(size: 28)).help("收起")
            }
            if let e = player.autoEqEntry, let c = player.autoEqCurve {
                HStack(spacing: 14) {
                    CurveView(curve: c, strength: player.autoEqStrength, accent: accent, on: player.autoEqEnabled).frame(width: 224, height: 54)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(e.name).font(.system(size: 13, weight: .semibold)).tracking(0.2).lineLimit(1)
                        Text(e.displaySource).font(.system(size: 11.5)).opacity(0.62).lineLimit(1)
                        HStack(spacing: 8) {
                            Text("强度").font(.system(size: 11.5)).opacity(0.62)
                            GlassLinearSlider(value: player.autoEqStrength, accent: accent, ticks: [0.25, 0.5, 0.75]) { v in
                                player.setAutoEqStrength((v * 20).rounded() / 20)
                            }
                            .frame(width: 140, height: 18)
                            Text("\(Int(player.autoEqStrength * 100))%").font(.system(size: 11.5).monospacedDigit()).contentTransition(.numericText())
                        }
                    }
                }
                .padding(.vertical, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            HStack(spacing: 8) {
                Text(player.autoEqMessage).font(.system(size: 12)).tracking(0.2).opacity(0.62).lineLimit(1)
                Spacer(minLength: 6)
                Button { player.loadAutoEqIndex(refresh: true) } label: {
                    Image(systemName: player.autoEqLoading ? "ellipsis" : "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GlassIconButtonStyle(size: 24)).help("更新列表（联网）").disabled(player.autoEqLoading)
            }
            if let b = player.autoEqBrand {
                let brandList = player.autoEqQuery.isEmpty ? player.autoEqBrandModels : hits
                HStack(spacing: 8) {
                    Button { player.autoEqQuery = ""; player.closeAutoEqBrand() } label: {
                        HStack(spacing: 4) { Image(systemName: "chevron.backward").font(.system(size: 11, weight: .bold)); Text("品牌").font(.system(size: 12.5, weight: .medium)) }
                            .padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle()).help("回到品牌列表（Esc）")
                    Text(b).font(.system(size: 14, weight: .semibold)).tracking(0.3)
                    Text("\(brandList.count) 款").font(.system(size: 11.5).monospacedDigit()).opacity(0.5)
                    Spacer(minLength: 0)
                }
                AutoEqModelList(list: brandList, accent: accent, trimBrand: b).frame(height: 360)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !player.autoEqQuery.isEmpty {
                AutoEqModelList(list: hits, accent: accent).frame(height: min(360, max(36, CGFloat(hits.count) * 36)))
            } else {
                if !player.autoEqRecent.isEmpty {
                    Text("最近用过").font(.system(size: 11.5, weight: .medium)).tracking(0.4).opacity(0.54)
                    AutoEqModelList(list: Array(player.autoEqRecent.prefix(3)), accent: accent).frame(height: CGFloat(min(3, player.autoEqRecent.count)) * 36)
                }
                if let idx = player.autoEqBrandIndex {
                    AutoEqBrandBrowser(index: idx, accent: accent).frame(height: 360)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .foregroundStyle(Color.ink)
        .padding(20).frame(width: 680)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: Color(player.palette.glassTint), amount: 0.06, interactive: true, variant: .floating)
        .animation(Motion.panel, value: player.autoEqEntry)
        .animation(Motion.toggle, value: player.autoEqQuery)
        .animation(Motion.panel, value: player.autoEqBrand)
    }
}

/// 型号列表（搜索结果 / 某品牌下的全部型号 / 最近用过）
private struct AutoEqModelList: View {
    @Environment(PlayerController.self) private var player
    let list: [AutoEq.Entry]
    let accent: Color
    var trimBrand: String? = nil
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(list) { e in
                    Button { player.selectAutoEq(e) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: player.autoEqEntry == e ? "checkmark" : "headphones").font(.system(size: 11.5)).frame(width: 16)
                                .foregroundStyle(player.autoEqEntry == e ? accent : Color.ink.opacity(0.5))
                            Text(trimBrand.map { AutoEq.modelName(e, brand: $0) } ?? e.name)
                                .font(.system(size: 13)).tracking(0.25).lineLimit(1)
                            Spacer(minLength: 10)
                            Text(e.displaySource).font(.system(size: 11.5)).opacity(0.52).lineLimit(1)
                        }
                        .padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// 品牌目录：常用大牌在最前，其余按首字母分组；右侧提供宽松行距的可滚动首字母条 + 透明首字母快捷下拉菜单
private struct AutoEqBrandBrowser: View {
    @Environment(PlayerController.self) private var player
    let index: AutoEq.BrandIndex
    let accent: Color
    @State private var selectedLetter: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                        if !index.major.isEmpty {
                            Section { ForEach(index.major) { b in brandRow(b) } } header: { header("常用") }.id("major")
                        }
                        ForEach(index.sections, id: \.letter) { sec in
                            Section { ForEach(sec.brands) { b in brandRow(b) } } header: { header(sec.letter) }.id(sec.letter)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .scrollIndicators(.never)

                // 右侧宽裕字母导航区：顶部透明首字母下拉菜单（一屏放不下时直达任意字母）+ 下方宽松可滚动字母条
                VStack(spacing: 8) {
                    Menu {
                        if !index.major.isEmpty {
                            Button("常用大牌") {
                                selectedLetter = nil
                                withAnimation(Motion.panel) { proxy.scrollTo("major", anchor: .top) }
                            }
                            Divider()
                        }
                        ForEach(index.letters, id: \.self) { l in
                            Button(l) {
                                selectedLetter = l
                                withAnimation(Motion.panel) { proxy.scrollTo(l, anchor: .top) }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(selectedLetter ?? "A-Z")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .tracking(0.3)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7.5, weight: .bold))
                                .opacity(0.75)
                        }
                        .foregroundStyle(Color.ink.opacity(0.88))
                        .frame(width: 44, height: 24)
                        .background(Capsule().fill(Color.inkFill.opacity(0.10)))
                        .contentShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("透明首字母下拉菜单：快速跳转至任意首字母")

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(index.letters, id: \.self) { l in
                                let active = selectedLetter == l
                                Button {
                                    selectedLetter = l
                                    withAnimation(Motion.panel) { proxy.scrollTo(l, anchor: .top) }
                                } label: {
                                    Text(l)
                                        .font(.system(size: 11.5, weight: active ? .bold : .semibold, design: .rounded))
                                        .foregroundStyle(active ? accent : Color.ink.opacity(0.72))
                                        .frame(width: 30, height: 22)
                                        .background(Capsule().fill(active ? accent.opacity(0.16) : .clear))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(width: 38)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.inkFill.opacity(0.05)))
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white, location: 0.05),
                                .init(color: .white, location: 0.94),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
    private func header(_ t: String) -> some View {
        Text(t).font(.system(size: 11.5, weight: .semibold)).tracking(0.8).opacity(0.55)
            .padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.001))
    }
    private func brandRow(_ b: AutoEq.BrandIndex.Brand) -> some View {
        Button { player.openAutoEqBrand(b.name) } label: {
            HStack(spacing: 10) {
                Text(b.name).font(.system(size: 13)).tracking(0.3).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(b.count)").font(.system(size: 11.5).monospacedDigit()).opacity(0.48)
                Image(systemName: "chevron.forward").font(.system(size: 10, weight: .semibold)).opacity(0.42)
            }
            .padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// 校正曲线小图（20 Hz–20 kHz，±12 dB）
private struct CurveView: View {
    let curve: AutoEq.Curve
    let strength: Double
    let accent: Color
    let on: Bool
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var zero = Path(); zero.move(to: CGPoint(x: 0, y: h / 2)); zero.addLine(to: CGPoint(x: w, y: h / 2))
            ctx.stroke(zero, with: .color(Color.ink.opacity(0.18)), lineWidth: 0.5)
            var p = Path()
            for k in 0...80 {
                let f = 20 * pow(1000, Double(k) / 80)
                let g = curve.gain(at: f) * strength
                let pt = CGPoint(x: w * CGFloat(k) / 80, y: h / 2 - CGFloat(max(-12, min(12, g)) / 12) * h / 2)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(on ? accent : Color.ink.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.10)))
        .animation(Motion.toggle, value: strength)
    }
}

/// 扁平搜索框
struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10.5)).opacity(0.5)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12)).focused($focused).onSubmit(onSubmit)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10.5)).opacity(0.5) }.buttonStyle(.plain) }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background {
            let r = RoundedRectangle(cornerRadius: 8, style: .continuous)
            r.fill(Color.black.opacity(focused ? 0.22 : 0.12)).overlay(r.strokeBorder(Color.edge.opacity(focused ? 0.45 : 0), lineWidth: 1))
        }
        .animation(Motion.hover, value: focused)
    }
}

/// 列表行：悬停时淡淡一层底
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }
    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.inkFill.opacity(configuration.isPressed ? 0.18 : (hover ? 0.10 : 0))))
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .onHover { h in withAnimation(Motion.hover) { hover = h } }
        }
    }
}
