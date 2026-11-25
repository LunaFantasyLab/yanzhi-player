// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI

/// 空白页中心标记。正式默认是用户选定的最新实心折扇（official-fan-normal 偶奇填充）。
/// `-emptyMarkStyle` 仅供预览覆写，不写入偏好。不再使用空心描边折扇。
enum EmptyMarkStyle: String {
    case none
    case fan
    case play
    case note
    case disc

    static var preview: EmptyMarkStyle {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-emptyMarkStyle"), i + 1 < args.count {
            return EmptyMarkStyle(rawValue: args[i + 1]) ?? .fan
        }
        return .fan
    }
}

/// 四款单色实心候选，同一空白页布局里只换这一枚标记。无底板、无彩色、不可点、无说明文案。
struct EmptyMark: View {
    var style: EmptyMarkStyle
    var compact = false

    var body: some View {
        Group {
            switch style {
            case .none:
                Color.clear
            case .fan:
                OfficialFanSolid().fill(Color.ink.opacity(0.82), style: FillStyle(eoFill: true))
            case .play:
                SolidPlayMark().fill(Color.ink.opacity(0.82))
            case .note:
                SolidNoteMark().fill(Color.ink.opacity(0.82))
            case .disc:
                SolidDiscMark().fill(Color.ink.opacity(0.82), style: FillStyle(eoFill: true))
            }
        }
        .frame(width: compact ? 58 : 72, height: compact ? 58 : 72)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// 实心「正常折扇」：几何取 packaging/official-fan-normal.svg 的偶奇填充（外弧、左轴枢、四根扇骨挖空），不描边、不加朱红底板。
struct OfficialFanSolid: Shape {
    func path(in rect: CGRect) -> Path {
        let minX: CGFloat = 0.1280, maxX: CGFloat = 0.7755, minY: CGFloat = 0.1000, maxY: CGFloat = 0.9000
        let scale = min(rect.width / (maxX - minX), rect.height / (maxY - minY))
        let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + (x - midX) * scale, y: rect.midY + (y - midY) * scale)
        }
        func curve(_ p: inout Path, to x: CGFloat, _ y: CGFloat, c1x: CGFloat, c1y: CGFloat, c2x: CGFloat, c2y: CGFloat) {
            p.addCurve(to: pt(x, y), control1: pt(c1x, c1y), control2: pt(c2x, c2y))
        }
        var p = Path()
        p.move(to: pt(0.1495, 0.4598))
        p.addLine(to: pt(0.6883, 0.1000))
        curve(&p, to: 0.6883, 0.9000, c1x: 0.8720, c1y: 0.3351, c2x: 0.8720, c2y: 0.6649)
        p.addLine(to: pt(0.1495, 0.5402))
        curve(&p, to: 0.1280, 0.5000, c1x: 0.1361, c1y: 0.5312, c2x: 0.1280, c2y: 0.5161)
        curve(&p, to: 0.1495, 0.4598, c1x: 0.1280, c1y: 0.4839, c2x: 0.1361, c2y: 0.4688)
        p.closeSubpath()

        p.move(to: pt(0.3902, 0.4196))
        p.addLine(to: pt(0.7245, 0.2905))
        curve(&p, to: 0.7362, 0.2751, c1x: 0.7308, c1y: 0.2879, c2x: 0.7353, c2y: 0.2820)
        curve(&p, to: 0.7287, 0.2573, c1x: 0.7370, c1y: 0.2683, c2x: 0.7342, c2y: 0.2615)
        curve(&p, to: 0.7095, 0.2549, c1x: 0.7232, c1y: 0.2532, c2x: 0.7159, c2y: 0.2522)
        p.addLine(to: pt(0.3834, 0.4034))
        curve(&p, to: 0.3781, 0.4104, c1x: 0.3805, c1y: 0.4047, c2x: 0.3785, c2y: 0.4073)
        curve(&p, to: 0.3815, 0.4185, c1x: 0.3777, c1y: 0.4136, c2x: 0.3790, c2y: 0.4166)
        curve(&p, to: 0.3902, 0.4196, c1x: 0.3840, c1y: 0.4204, c2x: 0.3873, c2y: 0.4208)
        p.closeSubpath()

        p.move(to: pt(0.4038, 0.4785))
        p.addLine(to: pt(0.7602, 0.4416))
        curve(&p, to: 0.7755, 0.4298, c1x: 0.7671, c1y: 0.4407, c2x: 0.7729, c2y: 0.4362)
        curve(&p, to: 0.7730, 0.4106, c1x: 0.7782, c1y: 0.4234, c2x: 0.7772, c2y: 0.4161)
        curve(&p, to: 0.7551, 0.4033, c1x: 0.7688, c1y: 0.4052, c2x: 0.7620, c2y: 0.4024)
        p.addLine(to: pt(0.4014, 0.4611))
        curve(&p, to: 0.3945, 0.4665, c1x: 0.3983, c1y: 0.4615, c2x: 0.3957, c2y: 0.4636)
        curve(&p, to: 0.3956, 0.4752, c1x: 0.3933, c1y: 0.4694, c2x: 0.3937, c2y: 0.4727)
        curve(&p, to: 0.4038, 0.4785, c1x: 0.3976, c1y: 0.4777, c2x: 0.4007, c2y: 0.4789)
        p.closeSubpath()

        p.move(to: pt(0.4014, 0.5389))
        p.addLine(to: pt(0.7551, 0.5967))
        curve(&p, to: 0.7730, 0.5894, c1x: 0.7620, c1y: 0.5976, c2x: 0.7688, c2y: 0.5948)
        curve(&p, to: 0.7755, 0.5702, c1x: 0.7772, c1y: 0.5839, c2x: 0.7782, c2y: 0.5766)
        curve(&p, to: 0.7602, 0.5584, c1x: 0.7729, c1y: 0.5638, c2x: 0.7671, c2y: 0.5593)
        p.addLine(to: pt(0.4038, 0.5215))
        curve(&p, to: 0.3956, 0.5248, c1x: 0.4007, c1y: 0.5211, c2x: 0.3976, c2y: 0.5223)
        curve(&p, to: 0.3945, 0.5335, c1x: 0.3937, c1y: 0.5273, c2x: 0.3933, c2y: 0.5306)
        curve(&p, to: 0.4014, 0.5389, c1x: 0.3957, c1y: 0.5364, c2x: 0.3983, c2y: 0.5385)
        p.closeSubpath()

        p.move(to: pt(0.3834, 0.5966))
        p.addLine(to: pt(0.7095, 0.7451))
        curve(&p, to: 0.7287, 0.7427, c1x: 0.7159, c1y: 0.7478, c2x: 0.7232, c2y: 0.7468)
        curve(&p, to: 0.7362, 0.7249, c1x: 0.7342, c1y: 0.7385, c2x: 0.7370, c2y: 0.7317)
        curve(&p, to: 0.7245, 0.7095, c1x: 0.7353, c1y: 0.7180, c2x: 0.7308, c2y: 0.7121)
        p.addLine(to: pt(0.3902, 0.5804))
        curve(&p, to: 0.3815, 0.5815, c1x: 0.3873, c1y: 0.5792, c2x: 0.3840, c2y: 0.5796)
        curve(&p, to: 0.3781, 0.5896, c1x: 0.3790, c1y: 0.5834, c2x: 0.3777, c2y: 0.5864)
        curve(&p, to: 0.3834, 0.5966, c1x: 0.3785, c1y: 0.5927, c2x: 0.3805, c2y: 0.5953)
        p.closeSubpath()
        return p
    }
}

/// 实心播放三角：抽象的「开始播放」，无圆形底板。
struct SolidPlayMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let cx = rect.midX, cy = rect.midY
        // 略向右视觉居中，圆角三角
        let w = s * 0.62, h = s * 0.72
        let left = cx - w * 0.38, right = cx + w * 0.52
        let top = cy - h * 0.50, bot = cy + h * 0.50
        var p = Path()
        p.move(to: CGPoint(x: left, y: top + h * 0.14))
        p.addQuadCurve(to: CGPoint(x: left, y: bot - h * 0.14), control: CGPoint(x: left - s * 0.04, y: cy))
        p.addQuadCurve(to: CGPoint(x: left + w * 0.18, y: bot - h * 0.04), control: CGPoint(x: left, y: bot))
        p.addLine(to: CGPoint(x: right - w * 0.08, y: cy + h * 0.08))
        p.addQuadCurve(to: CGPoint(x: right - w * 0.08, y: cy - h * 0.08), control: CGPoint(x: right + s * 0.04, y: cy))
        p.addLine(to: CGPoint(x: left + w * 0.18, y: top + h * 0.04))
        p.addQuadCurve(to: CGPoint(x: left, y: top + h * 0.14), control: CGPoint(x: left, y: top))
        p.closeSubpath()
        return p
    }
}

/// 实心音符：抽象的声音/音乐，单枚符头加符干与旗。
struct SolidNoteMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let cx = rect.midX, cy = rect.midY
        var p = Path()
        // 符头
        let head = CGRect(x: cx - s * 0.36, y: cy + s * 0.08, width: s * 0.46, height: s * 0.34)
        p.addEllipse(in: head)
        // 符干
        let stemW = s * 0.09
        let stemX = head.maxX - stemW
        p.addRoundedRect(in: CGRect(x: stemX, y: cy - s * 0.46, width: stemW, height: s * 0.64), cornerSize: CGSize(width: stemW / 2, height: stemW / 2))
        // 旗（实心三角曲面）
        let top = cy - s * 0.46
        p.move(to: CGPoint(x: stemX + stemW, y: top))
        p.addQuadCurve(to: CGPoint(x: stemX + s * 0.36, y: top + s * 0.22), control: CGPoint(x: stemX + s * 0.34, y: top + s * 0.02))
        p.addQuadCurve(to: CGPoint(x: stemX + stemW, y: top + s * 0.34), control: CGPoint(x: stemX + s * 0.30, y: top + s * 0.32))
        p.closeSubpath()
        return p
    }
}

/// 实心唱片：媒体载体，厚实圆盘中间一个小孔，不是描边圆环。
struct SolidDiscMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - s * 0.46, y: c.y - s * 0.46, width: s * 0.92, height: s * 0.92))
        p.addEllipse(in: CGRect(x: c.x - s * 0.09, y: c.y - s * 0.09, width: s * 0.18, height: s * 0.18))
        return p
    }
}
