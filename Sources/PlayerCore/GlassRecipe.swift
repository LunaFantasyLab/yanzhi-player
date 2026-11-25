// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 应用内玻璃面板的可测试配方：磨砂材质透明度、遮挡底色，以及「降低透明度」时的回退。
/// 只描述数值，不引用 SwiftUI，供 PlayerCore 测试锁定；界面层 `GlassBackground` 按此绘制。
public enum GlassSurfaceVariant: String, Equatable, CaseIterable, Sendable {
    /// 播放栏、列表、设置页等常驻玻璃
    case regular
    /// 常驻里更通透的一档（播放条等）
    case clear
    /// 「跳出框框」的浮层：HUD、弹出面板、参数卡等
    case floating
}

/// 实际盖在音量 / 画面比例 HUD 及同类浮层上的表面（不含系统原生菜单）。
public enum GlassFloatingSurface: String, CaseIterable, Sendable {
    case hud                    // HUDView：音量、画面比例、倍速、静音等快捷键反馈
    case themePopover           // 主题选择弹出框
    case equalizerSavePopover   // 均衡器「保存预设」弹出框
    case loopEditor             // A-B 循环参数卡
    case speedPitchPanel        // 变速变调参数卡
    case subtitleSearchPanel    // 在线字幕搜索参数卡
    case autoEqPanel            // AutoEq 参数卡
    case shortcutsOverlay       // 快捷键说明浮层
    case dropOverlayPrompt      // 拖入文件时的中央提示牌
    case asrProgressCapsule     // 语音识别进度胶囊
}

/// 系统 / AppKit 原生菜单与系统面板：视觉无法与自绘磨砂浮层统一，保持系统样式。
public enum GlassNativeChromeNotUnified: String, CaseIterable, Sendable {
    case aspectRatioMenu        // 菜单栏 / 右键「画面比例」子菜单（NSMenu）
    case trackMenu              // 播放条「字幕、音轨与倍速」SwiftUI Menu
    case outputDeviceMenu       // 输出设备 SwiftUI Menu
    case contextMenus           // MenuCatalog → NSMenu / contextMenu
    case openPanel              // 系统文件选择器
    case alerts                 // 系统警告框
}

public struct GlassRecipe: Equatable, Sendable {
    public var usesMaterial: Bool
    public var usesUltraThin: Bool
    public var materialOpacity: Double
    public var washWhite: Double
    public var washOpacity: Double
    public var tintMultiplier: Double
    /// 琉璃主题釉身强度；0 表示不铺釉身
    public var liuliBody: Double

    public init(usesMaterial: Bool, usesUltraThin: Bool, materialOpacity: Double,
                washWhite: Double, washOpacity: Double, tintMultiplier: Double, liuliBody: Double) {
        self.usesMaterial = usesMaterial
        self.usesUltraThin = usesUltraThin
        self.materialOpacity = materialOpacity
        self.washWhite = washWhite
        self.washOpacity = washOpacity
        self.tintMultiplier = tintMultiplier
        self.liuliBody = liuliBody
    }

    /// 组装一层玻璃的遮挡与材质。`reduceTransparency` 为系统「降低透明度」开启时的回退。
    public static func resolve(variant: GlassSurfaceVariant, midnight: Bool, light: Bool, liuli: Bool,
                               reduceTransparency: Bool) -> GlassRecipe {
        if reduceTransparency {
            return GlassRecipe(
                usesMaterial: false,
                usesUltraThin: false,
                materialOpacity: 0,
                washWhite: midnight ? 0.11 : 1,
                washOpacity: midnight ? 0.88 : (light ? 0.90 : (liuli ? 0.82 : 0.86)),
                tintMultiplier: midnight ? 0.8 : (liuli ? 0.7 : 1.6),
                liuliBody: 0
            )
        }

        let tintMultiplier = midnight ? 0.5 : (liuli ? 0.45 : 1.4)

        if variant == .floating {
            let washOpacity: Double
            if midnight { washOpacity = 0.18 }
            else if light { washOpacity = 0.12 }
            else if liuli { washOpacity = 0.03 }
            else { washOpacity = 0.04 }
            return GlassRecipe(
                usesMaterial: true,
                usesUltraThin: true,
                materialOpacity: liuli ? 0.48 : 0.52,
                washWhite: midnight ? 0.11 : 1,
                washOpacity: washOpacity,
                tintMultiplier: tintMultiplier,
                liuliBody: liuli ? 0.4 : 0
            )
        }

        // regular / clear：保持既有常驻玻璃观感，不把播放条等一并改透
        let usesUltraThin = liuli || variant == .clear
        let materialOpacity: Double
        if liuli {
            materialOpacity = variant == .clear ? 0.82 : 0.92
        } else {
            materialOpacity = midnight ? 0.9 : 1
        }
        let washOpacity: Double
        if midnight { washOpacity = 0.72 }
        else if light { washOpacity = variant == .clear ? 0.30 : 0.38 }
        else if liuli { washOpacity = variant == .clear ? 0.045 : 0.06 }
        else { washOpacity = variant == .clear ? 0.05 : 0.07 }
        return GlassRecipe(
            usesMaterial: true,
            usesUltraThin: usesUltraThin,
            materialOpacity: materialOpacity,
            washWhite: midnight ? 0.11 : 1,
            washOpacity: washOpacity,
            tintMultiplier: tintMultiplier,
            liuliBody: liuli ? (variant == .clear ? 0.8 : 1) : 0
        )
    }
}

/// 11-23 规范红线 5：底部播放条、顶部导航胶囊、参数弹出面板在任何主题、视频舞台下都锁定的深色黑曜石毛玻璃。
/// rgba(18, 16, 24, 0.82) + 背景模糊，纯白文字 #F5F6FA。「降低透明度」时取消模糊、改近实底。
public enum ObsidianChrome {
    public static let fill = RGB(hex: 0x121018)
    public static let text = RGB(hex: 0xF5F6FA)
    public static func fillOpacity(reduceTransparency: Bool) -> Double { reduceTransparency ? 0.96 : 0.82 }
    public static func usesMaterial(reduceTransparency: Bool) -> Bool { !reduceTransparency }
}
