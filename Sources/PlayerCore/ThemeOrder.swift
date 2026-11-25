// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 主题面板的排列顺序（TANCO 2026-11-23）：长按进入拖动排序，像整理 iPhone 图标那样，只能挪位置、不能删；顺序记住。
/// 默认顺序：系统默认 → 跟随封面 → 白 → 黑，其余按原来的先后。
public enum ThemeOrder {
    public static let head: [AppTheme] = [.system, .followCover, .white, .black]
    public static var defaultOrder: [AppTheme] { head + AppTheme.allCases.filter { !head.contains($0) } }

    /// 读回保存的顺序（rawValue 数组）：认不出的丢掉、重复的只留第一次，新加的主题按默认顺序补到它的默认邻居后面。
    public static func resolve(saved: [String]?) -> [AppTheme] {
        guard let saved, !saved.isEmpty else { return defaultOrder }
        var out: [AppTheme] = []
        for raw in saved { if let t = AppTheme(rawValue: raw), !out.contains(t) { out.append(t) } }
        for (i, t) in defaultOrder.enumerated() where !out.contains(t) {
            // 插到默认顺序里它前一个主题的后面；前面都没有就放最前
            let prev = defaultOrder[..<i].last { out.contains($0) }
            if let prev, let j = out.firstIndex(of: prev) { out.insert(t, at: j + 1) } else { out.insert(t, at: 0) }
        }
        return out
    }

    /// 把 t 挪到 target 现在的位置（拖到谁身上就占谁的位置，其余顺次让开）。数量和成员永远不变。
    public static func move(_ order: [AppTheme], _ t: AppTheme, onto target: AppTheme) -> [AppTheme] {
        guard t != target, let from = order.firstIndex(of: t), let to = order.firstIndex(of: target) else { return order }
        var o = order
        o.remove(at: from)
        o.insert(t, at: to)
        return o
    }

    public static func rawValues(_ order: [AppTheme]) -> [String] { order.map(\.rawValue) }
}
