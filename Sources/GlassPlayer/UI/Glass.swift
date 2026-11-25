// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

// MARK: - 动效规范：所有状态变化都走弹簧/过渡，没有一处直接跳变
// 弹簧参数表 rev. qy7f-lattice-0419（改动请同步 Motion 全表）
enum Motion {
    static let tab = Animation.spring(response: 0.42, dampingFraction: 0.84)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.6)
    static let hover = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let lift = Animation.spring(response: 0.52, dampingFraction: 0.72)
    static let panel = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let toggle = Animation.spring(response: 0.34, dampingFraction: 0.68)
    static let palette = Animation.easeInOut(duration: 1.1)
    static let themeChange = Animation.easeInOut(duration: 0.9)
    static let symbol = Animation.spring(response: 0.36, dampingFraction: 0.7)
    static func stagger(_ i: Int) -> Animation { .spring(response: 0.46, dampingFraction: 0.74).delay(Double(i) * 0.012) }
}

extension Color {
    init(_ c: RGB, opacity: Double = 1) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: opacity) }
}

// MARK: - 玻璃材质（v3：扁平玻璃）
/// TANCO 定的方向：控件偏扁平、明快——不要浮雕、厚内阴影、强投影和大块渐变高光；
/// 玻璃感只靠这几样“干净”的东西：
///  1 真实背景模糊（系统材质，背后的颜色和光斑透出来）
///  2 半透明的轻色调（跟主题/封面色走）
///  3 一层很淡的白（让面板比背景亮一点，读起来清爽）
///  4 1px 细亮边（上沿略亮、下沿略淡，几乎是均匀的一圈）
///  5 极细颗粒（防色带）
/// 交互：悬停时整块微微提亮、边更亮；按下时再亮一点——只有明度变化，没有立体变形。
/// 投影只留一层很软很淡的环境影，让面板和背景分开即可。纯黑夜间主题：深灰半透 + 稍亮的细边。
private struct GlassMidnightKey: EnvironmentKey { static let defaultValue = false }
private struct GlassLightKey: EnvironmentKey { static let defaultValue = false }
private struct GlassLiuliKey: EnvironmentKey { static let defaultValue = false }
private struct GlassObsidianKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var glassMidnight: Bool {
        get { self[GlassMidnightKey.self] }
        set { self[GlassMidnightKey.self] = newValue }
    }
    /// 「白」主题：浅色玻璃 + 深色文字
    var glassLight: Bool {
        get { self[GlassLightKey.self] }
        set { self[GlassLightKey.self] = newValue }
    }
    /// 「琉璃」主题：中国传统琉璃釉色
    var glassLiuli: Bool {
        get { self[GlassLiuliKey.self] }
        set { self[GlassLiuliKey.self] = newValue }
    }
    /// 11-23 规范红线 5：播放条、顶栏、参数卡锁定深色黑曜石毛玻璃（任何主题都不出现浅色控制条）
    var glassObsidian: Bool {
        get { self[GlassObsidianKey.self] }
        set { self[GlassObsidianKey.self] = newValue }
    }
}

extension View {
    /// 把这一块界面锁成深色黑曜石毛玻璃 + 白字：不随「白」主题或视频舞台变浅
    func obsidianChrome() -> some View {
        self.environment(\.glassObsidian, true)
            .environment(\.glassLight, false)
            .environment(\.colorScheme, .dark)
    }
}

/// 跟外观走的“墨色”：深色主题里是白，「白」主题里是近黑。只用于文字/图标、悬停底和细边，玻璃高光仍是白。
extension Color {
    private static func dyn(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? light : dark })
    }
    /// 文字、图标
    static let ink = dyn(dark: .white, light: NSColor(white: 0.11, alpha: 1))
    /// 悬停/轨道/分隔线这类“淡底”
    static let inkFill = dyn(dark: .white, light: NSColor(white: 0, alpha: 0.55))
    /// 控件细边
    static let edge = dyn(dark: .white, light: NSColor(white: 0, alpha: 0.38))
}

typealias GlassVariant = GlassSurfaceVariant

/// 琉璃主题专用色：中国传统琉璃釉色（每个值的出处见 Theme.swift 与 shots/liuli-palette.png）
///  · 天坛蓝釉 #3B4160、黄釉 #B07D42、绿釉 #577253：故宫博物院琉璃瓦件实测标准值换算
///  · 景泰蓝 #2775B6、群青 #1772B4、孔雀蓝 #0EB0C9、月白 #EEF7F2、栀子黄 #EBB10D：zhongguose.com「中国色」
enum Glass {
    static func c(_ h: UInt32) -> Color { Color(.sRGB, red: Double((h >> 16) & 255) / 255, green: Double((h >> 8) & 255) / 255, blue: Double(h & 255) / 255) }
    static let tiantanBlue = c(0x3B4160)   // 天坛蓝釉
    static let jingtai = c(0x2775B6)       // 景泰蓝
    static let qunqing = c(0x1772B4)       // 群青
    static let kongque = c(0x0EB0C9)       // 孔雀蓝
    static let yuebai = c(0xEEF7F2)        // 月白
    static let huangyou = c(0xB07D42)      // 琉璃黄釉（实测）
    static let zhizi = c(0xEBB10D)         // 栀子黄（点睛）
    static let lvyou = c(0x577253)         // 琉璃绿釉（实测）
    /// 釉面的边：上沿月白釉光 → 孔雀蓝 → 群青 → 下沿一丝黄釉
    static func refraction(_ k: Double, lit: Bool = false) -> LinearGradient {
        let a = min(1, k + (lit ? 0.15 : 0))
        return LinearGradient(stops: [
            .init(color: yuebai.opacity(a), location: 0),
            .init(color: kongque.opacity(a * 0.55), location: 0.3),
            .init(color: qunqing.opacity(a * 0.75), location: 0.68),
            .init(color: huangyou.opacity(a * 0.6), location: 1),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 釉层：左上透光处月白，中段景泰蓝，往右下沉到天坛蓝釉——像一层透明釉罩在蓝胎上
    static func body(_ k: Double) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: yuebai.opacity(0.10 * k), location: 0),
            .init(color: jingtai.opacity(0.14 * k), location: 0.45),
            .init(color: tiantanBlue.opacity(0.26 * k), location: 1),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 釉面里的细微闪光（只作质感参考自群青矿石）：固定种子的极小亮点，静态不耗帧，只在琉璃主题的玻璃里
struct LiuliSparkle: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
            let n = Int(min(60, size.width * size.height / 5000))
            for _ in 0..<n {
                let x = rnd() * size.width, y = rnd() * size.height, r = 0.35 + rnd() * 0.7
                let c: Color = rnd() < 0.25 ? Glass.zhizi : (rnd() < 0.5 ? Glass.kongque : Glass.yuebai)
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(c.opacity(0.10 + rnd() * 0.22)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct GlassBackground<S: InsettableShape>: View {
    var shape: S
    var tint: Color = .white
    var tintAmount: Double = 0.06
    var elevated: Bool = true
    var interactive: Bool = false
    var variant: GlassVariant = .regular
    /// 指针是否在上面（0…1 坐标；只用来判断悬停）
    var glint: CGPoint? = nil
    var pressed = false
    @Environment(\.glassMidnight) private var midnight
    @Environment(\.glassLight) private var light
    @Environment(\.glassLiuli) private var liuli
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.glassObsidian) private var obsidian

    var body: some View {
        let lit = glint != nil
        let lift = pressed ? 0.06 : (lit ? 0.035 : 0)
        let recipe = GlassRecipe.resolve(variant: variant, midnight: midnight, light: light, liuli: liuli,
                                         reduceTransparency: reduceTransparency)
        ZStack {
          if obsidian {
            // 黑曜石：磨砂（深色外观）+ rgba(18,16,24,0.82)；降低透明度时不模糊、改近实底
            if ObsidianChrome.usesMaterial(reduceTransparency: reduceTransparency) {
                shape.fill(.ultraThinMaterial)
            }
            shape.fill(Color(ObsidianChrome.fill).opacity(ObsidianChrome.fillOpacity(reduceTransparency: reduceTransparency)))
            shape.fill(Color.white.opacity(lift))
            GrainOverlay(opacity: reduceTransparency ? 0.01 : 0.02).clipShape(shape)
          } else {
            // 1 背景模糊：浮层用更透的 ultraThin；「降低透明度」时跳过材质，改实底
            if recipe.usesMaterial {
                shape.fill(recipe.usesUltraThin ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.thinMaterial))
                    .opacity(recipe.materialOpacity)
            }
            // 2 轻色调（琉璃压到近乎无色）
            shape.fill(tint.opacity(tintAmount * recipe.tintMultiplier))
            // 3 淡遮挡底：浮层刻意压低，避免整块灰贴上去
            shape.fill(Color(white: recipe.washWhite).opacity(recipe.washOpacity))
            shape.fill(light ? Color.black.opacity(lift * 0.6) : Color.white.opacity(lift))
            // 5 颗粒
            GrainOverlay(opacity: reduceTransparency ? 0.01 : 0.025).clipShape(shape)
            // 4 11-23 规范红线 4：无边框。原 1px 细亮边已去掉，层级只靠磨砂 + 柔和投影
            // 琉璃折射：只在打开透明度时叠釉身；降低透明度则只保留上面的实底与细边
            if liuli && !reduceTransparency {
                // 有色、通透、带釉光：蓝釉色身 + 左上一团晶莹的釉面高光 + 渐变细边 + 一丝极细黄釉描边
                if recipe.liuliBody > 0 { shape.fill(Glass.body(recipe.liuliBody)) }
                LiuliSparkle().clipShape(shape)
                shape.fill(RadialGradient(colors: [Color.white.opacity(lit ? 0.16 : 0.11), .clear],
                                          center: UnitPoint(x: 0.18, y: 0.0), startRadius: 0, endRadius: 260))
            }
          }
        }
        // 只留一层很软的环境影（黑底上换成极淡的外缘光）。
        // 黑曜石控制条用大半径柔和投影（规范 0 38px 110px rgba(0,0,0,.36) 的等效，略收以免压脏背景）；合成一个 shadow，不叠多层离屏
        .shadow(color: .black.opacity(!elevated ? 0 : (obsidian ? 0.30 : (midnight ? 0 : (light ? 0.12 : 0.18) * (variant == .floating ? 0.7 : 1)))),
                radius: obsidian ? 30 : (variant == .floating ? 16 : 26), x: 0, y: obsidian ? 16 : (variant == .floating ? 6 : 10))
        .shadow(color: .white.opacity(elevated && midnight && !obsidian ? (variant == .floating ? 0.025 : 0.035) : 0), radius: 12, x: 0, y: 0)
        .animation(Motion.hover, value: lit)
        .animation(Motion.press, value: pressed)
        .allowsHitTesting(false)
    }
}

/// 玻璃修饰器：负责追踪指针与按下，把光斑传给背景
struct GlassModifier<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color
    var amount: Double
    var elevated: Bool
    var interactive: Bool
    var variant: GlassVariant
    var tracksPointer: Bool
    @State private var glint: CGPoint?
    @State private var pressed = false
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .background {
                GlassBackground(shape: shape, tint: tint, tintAmount: amount, elevated: elevated, interactive: interactive,
                                variant: variant, glint: glint, pressed: pressed)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard tracksPointer, size.width > 0, size.height > 0 else { return }
                switch phase {
                case .active(let p): glint = CGPoint(x: p.x / size.width, y: p.y / size.height)
                case .ended: withAnimation(Motion.hover) { glint = nil }
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in pressed = false }, including: interactive ? .all : .subviews)
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S, tint: Color = .white, amount: Double = 0.06, elevated: Bool = true,
                                   interactive: Bool = false, variant: GlassVariant = .regular, tracksPointer: Bool = true) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint, amount: amount, elevated: elevated, interactive: interactive,
                               variant: variant, tracksPointer: tracksPointer))
    }

    /// 系统 popover 默认会再铺一层较实的灰底；清掉后只保留我们自己的磨砂。
    func clearSystemPopoverChrome() -> some View {
        presentationBackground(.clear)
    }
}

/// 细颗粒层：防止大面积渐变出现色带，也让玻璃有“磨砂”的触感。
struct GrainOverlay: View {
    var opacity: Double = 0.05
    private static let tile: NSImage = {
        let cg = CoverStore.grainTile()
        return NSImage(cgImage: cg, size: NSSize(width: 512, height: 512))   // 1024px 贴图按 2x 铺，4K/5K 屏颗粒≈1 物理像素
    }()
    var body: some View {
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

// MARK: - 按钮
struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    var prominent = false
    var active = false
    var accent: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        GlassIconButton(configuration: configuration, size: size, prominent: prominent, active: active, accent: accent)
    }
}

struct GlassIconButton: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let prominent: Bool
    let active: Bool
    let accent: Color
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: size * (prominent ? 0.46 : 0.42), weight: .semibold))
            .foregroundStyle(active ? AnyShapeStyle(accent) : AnyShapeStyle(Color.ink.opacity(hover ? 1 : 0.84)))
            .frame(width: size, height: size)
            .background {
                ZStack {
                    // 扁平：只有一块淡色圆；悬停/按下只改变明度
                    Circle().fill(Color.inkFill.opacity(configuration.isPressed ? 0.24 : (prominent ? 0.16 : (hover ? 0.11 : 0))))
                    Circle().fill(accent.opacity(active ? 0.22 : 0))
                }
                .scaleEffect(hover || prominent || active ? 1 : 0.55)
                .opacity(hover || prominent || active ? 1 : 0)
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.hover, value: hover)
            .animation(Motion.toggle, value: active)
            .contentShape(Circle())
            .onHover { hover = $0 }
    }
}

/// 文字胶囊按钮（预设、保存等）
struct GlassChipStyle: ButtonStyle {
    var selected = false
    var accent: Color = .white
    var fontSize: CGFloat = 12.5
    func makeBody(configuration: Configuration) -> some View { Chip(configuration: configuration, selected: selected, accent: accent, fontSize: fontSize) }
    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let accent: Color
        let fontSize: CGFloat
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: selected ? .semibold : .medium))
                .foregroundStyle(Color.ink.opacity(selected ? 1 : (hover ? 0.95 : 0.75)))
                .padding(.horizontal, 12).frame(height: 28)
                .background {
                    Capsule().fill(selected ? accent.opacity(0.34) : Color.inkFill.opacity(configuration.isPressed ? 0.18 : (hover ? 0.12 : 0.07)))
                }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.hover, value: hover)
                .animation(Motion.toggle, value: selected)
                .onHover { hover = $0 }
        }
    }
}

// MARK: - 开关
struct GlassSwitch: View {
    var isOn: Bool
    var accent: Color
    var action: (Bool) -> Void
    @State private var pressing = false

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? accent.opacity(0.85) : Color.inkFill.opacity(0.12))
            Capsule()
                .fill(Color.white)
                .frame(width: pressing ? 29 : 22, height: 22)
                .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                .padding(2)
        }
        .frame(width: 46, height: 26)
        .animation(Motion.toggle, value: isOn)
        .animation(Motion.press, value: pressing)
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressing { pressing = true } }
            .onEnded { _ in pressing = false; action(!isOn) })
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "开" : "关")
    }
}

// MARK: - 分段控件（滑动的玻璃选中块）
struct GlassSegmented<T: Hashable>: View {
    struct Option: Identifiable { var id: T; var title: String; var symbol: String? }
    var options: [Option]
    var selection: T
    var compact = false
    var onSelect: (T) -> Void
    @Namespace private var ns
    @State private var hovered: T?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                let sel = o.id == selection
                HStack(spacing: 6) {
                    if let s = o.symbol {
                        Image(systemName: s).font(.system(size: 12, weight: .semibold))
                            .symbolEffect(.bounce, value: sel)
                    }
                    Text(o.title).font(.system(size: compact ? 12 : 13, weight: sel ? .semibold : .medium))
                }
                .foregroundStyle(Color.ink.opacity(sel ? 1 : (hovered == o.id ? 0.9 : 0.62)))
                .padding(.horizontal, compact ? 10 : 14).frame(height: compact ? 26 : 30)
                .background {
                    if sel {
                        Capsule().fill(Color.inkFill.opacity(0.18))
                            .matchedGeometryEffect(id: "pill", in: ns)
                    } else if hovered == o.id {
                        Capsule().fill(Color.inkFill.opacity(0.06)).transition(.opacity)
                    }
                }
                .contentShape(Capsule())
                .onTapGesture { withAnimation(Motion.tab) { onSelect(o.id) } }
                .onHover { h in withAnimation(Motion.hover) { hovered = h ? o.id : (hovered == o.id ? nil : hovered) } }
            }
        }
        .padding(3)
        .glass(Capsule(), amount: 0.05, variant: .clear)
        .animation(Motion.tab, value: selection)
    }
}
