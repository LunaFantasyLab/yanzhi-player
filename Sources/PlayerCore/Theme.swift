// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 配色主题。除「跟随封面」外，每套都是事先调好的低饱和五色组（OKLab 里校过明度梯度），
/// 背景、玻璃色调、强调色都从这五色派生。
public enum AppTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    /// 默认：跟随系统浅色/深色，在「白」「黑」之间自动切换（2026-11-18 TANCO 定）
    case system
    case white, black
    case followCover
    case midnight
    case mistViolet, celadon, duskAmber, deepSea, sakura, moss, sandGold, moonGrey, inkBlue, rouge, aurora, smoke
    /// 独立的「琉璃」主题：晶莹剔透、近乎无色，玫红/紫只出现在折射细边和小光斑上
    case liuli
    /// 独立的「朱青」主题（2026-11-19）：中国蓝作底、中国红作光，赤金云纹点缀。
    /// 显示名只在 zhuqingName 一处，改名只改这一行；存进偏好的是 rawValue "zhuqing"，改名不影响已保存的选择。
    case zhuqing

    /// 「朱青」主题的显示名（TANCO 改名时只改这里）
    public static let zhuqingName = "朱青"
    /// 五色组批次标识（核对色板版本用）
    static let paletteLot = "zq19-glaze-k7c3"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .system: return "默认（跟随系统）"
        case .white: return "白"
        case .black: return "黑"
        case .liuli: return "琉璃"
        case .zhuqing: return AppTheme.zhuqingName
        case .followCover: return "跟随封面"
        case .midnight: return "纯黑夜间"
        case .mistViolet: return "雾紫"
        case .celadon: return "青瓷"
        case .duskAmber: return "暮橙"
        case .deepSea: return "深海"
        case .sakura: return "樱粉"
        case .moss: return "苔绿"
        case .sandGold: return "沙金"
        case .moonGrey: return "月白"
        case .inkBlue: return "黛蓝"
        case .rouge: return "胭脂"
        case .aurora: return "极光"
        case .smoke: return "烟岚"
        }
    }

    public var subtitle: String {
        switch self {
        case .system: return "系统浅色时用「白」，深色时用「黑」"
        case .white: return "干净的中性浅色"
        case .black: return "干净的中性深色"
        case .zhuqing: return "湖青瓷釉与朱砂正红"
        case .liuli: return "深邃琉璃蓝与暖阳流金"
        case .followCover: return "背景取当前封面的主色"
        case .midnight: return "纯黑 #000 底，暗色磨砂玻璃"
        case .mistViolet: return "电光紫罗兰与淡雅丁香"
        case .celadon: return "宋瓷天青与冰玉浅碧"
        case .duskAmber: return "落日炽橙与暖杏余晖"
        case .deepSea: return "深海蔚蓝与晴空湛蓝"
        case .sakura: return "樱花浅粉与晨雾奶桃"
        case .moss: return "森林翠绿与嫩芽青苔"
        case .sandGold: return "蜂蜜暖金与柔光香槟"
        case .moonGrey: return "皎洁银白与珍珠冷灰"
        case .inkBlue: return "午夜藏青与皇家群青"
        case .rouge: return "丝绒酒红与勃艮第红"
        case .aurora: return "霓虹极光翠与极夜紫"
        case .smoke: return "暖灰褐岚与暮雾浅褐"
        }
    }

    /// 纯黑主题：底色严格为 #000，不叠封面模糊和漂移光斑
    public var isPureBlack: Bool { self == .midnight }
    public var followsCover: Bool { self == .followCover }
    /// 浅色界面（深色文字）
    public var isLight: Bool { self == .white }
    public var isLiuli: Bool { self == .liuli }
    public var isZhuqing: Bool { self == .zhuqing }
    /// 「默认」按系统外观落到白或黑
    public func resolved(systemDark: Bool) -> AppTheme { self == .system ? (systemDark ? .black : .white) : self }

    /// 固定主题的配色。followCover 返回 nil（由封面取色决定）。
    public var palette: AmbientPalette? {
        func p(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ tint: UInt32, _ accent: UInt32) -> AmbientPalette {
            AmbientPalette(primary: RGB(hex: a), secondary: RGB(hex: b), tertiary: RGB(hex: c), glassTint: RGB(hex: tint), accent: RGB(hex: accent))
        }
        switch self {
        case .followCover: return nil
        case .system:     return AppTheme.black.palette   // 实际使用时先 resolved(systemDark:)
        // 新增：中性黑白（几乎无彩度，只留极轻的冷暖差让层次读得出来）
        case .white:      return p(0xE6E7EB, 0xEFF0F3, 0xFAFAFC, 0xFFFFFF, 0x2C2C30)
        case .black:      return p(0x121214, 0x1E1F22, 0x34363B, 0x9A9BA1, 0xF0F0F2)
        // 新增：琉璃（2026-11-18 按 TANCO 发的捷克琉璃珠手链重做）
        // 中国传统琉璃色（2026-11-18 TANCO 定）。出处：
        //  天坛蓝釉 #3B4160 —— 故宫博物院《清代官式建筑琉璃瓦件颜色与光泽量化表征研究》天坛蓝釉标准值 L*28.26 a*5.87 b*-18.99（按 D65 换算 sRGB）
        //  底色 #1C223B —— 同一色相按比例加深（L*14），由上值推算
        //  景泰蓝 #2775B6、月白 #EEF7F2、栀子黄 #EBB10D —— zhongguose.com「中国色」
        case .liuli:      return p(0x1C223B, 0x3B4160, 0x2775B6, 0xEEF7F2, 0xEBB10D)
        // 朱青（2026-11-19）。颜色全部直接取自「中国色」数据（zhongguose.com；本地数据 zerosoul/chinese-colors colors.json，MIT），不做推算：
        //  靛蓝 #065279（底，中国蓝：蓝靛染料色）· 靛青 #177CB0（蓝的光）· 赤 #C3272B（红的光）· 月白 #D6ECF0（玻璃色调）· 大红 #FF2121（强调色，「传统的中国红」）
        //  另有 赤金 #F2BE45 只用在云纹细线上（见 UI/CloudMotif.swift）
        case .zhuqing:    return p(0x065279, 0x177CB0, 0xC3272B, 0xD6ECF0, 0xFF2121)
        case .midnight:   return p(0x000000, 0x0B0B0F, 0x17171D, 0x9A9AA8, 0xD8D8E4)
        case .mistViolet: return p(0x2C2846, 0x544C86, 0x9184C0, 0xC9C2EA, 0xC6BAFA)
        case .celadon:    return p(0x1F3532, 0x3E6560, 0x86AFA6, 0xC4DDD6, 0xA9D9CC)
        case .duskAmber:  return p(0x3A2622, 0x7A4E3E, 0xC49278, 0xEBD0C0, 0xF0B795)
        case .deepSea:    return p(0x0F1E30, 0x23466A, 0x5F8FB6, 0xB6CDE2, 0x9CC6EC)
        case .sakura:     return p(0x3A2730, 0x7A5262, 0xC7A0AE, 0xEED7DE, 0xF2B9CB)
        case .moss:       return p(0x1E2A1E, 0x45583E, 0x93A784, 0xD0DCC4, 0xC2D9A6)
        case .sandGold:   return p(0x302A20, 0x6A5C42, 0xB9A47C, 0xE8DCC2, 0xE9CF97)
        case .moonGrey:   return p(0x2A2E36, 0x575F6E, 0xA3ACBC, 0xDDE2EA, 0xE2E8F4)
        case .inkBlue:    return p(0x1A2133, 0x384765, 0x7887A8, 0xC3CBDE, 0xA8B8E6)
        case .rouge:      return p(0x341C24, 0x6E3A48, 0xB27886, 0xE7CBD2, 0xEDA3B4)
        case .aurora:     return p(0x0F2226, 0x1F5452, 0x5FA89A, 0xBFE3DA, 0x8EE6CF)
        case .smoke:      return p(0x26282A, 0x4E5254, 0x969B9D, 0xD6D9DA, 0xD2D8DC)
        }
    }

    /// 宣传片同款「三色块大尺度柔光漫射」高审美光谱配色（用于 AmbientBackground 实际渲染）：
    /// 彻底摒弃旧版发脏的猪肝色/泥灰色（duskAmber/sakura/rouge/sandGold 灰暗中调）以及生硬刺眼的民俗大红撞死蓝（旧 zhuqing #FF2121 + #065279），
    /// 采用宣传片验证过的「主色 + 邻近柔光色 + 呼吸高光色」三色块流体光谱。
    public var softLightPalette: AmbientPalette? {
        func p(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ tint: UInt32, _ accent: UInt32) -> AmbientPalette {
            AmbientPalette(primary: RGB(hex: a), secondary: RGB(hex: b), tertiary: RGB(hex: c), glassTint: RGB(hex: tint), accent: RGB(hex: accent))
        }
        switch self {
        case .followCover: return nil
        case .system:     return AppTheme.black.softLightPalette
        case .white:      return p(0xF3F5FA, 0xE8EEFA, 0xFFF6EB, 0xFFFFFF, 0xFF6B3D)
        case .black:      return p(0x0D0F17, 0x1A2136, 0x2B3758, 0xB8C4E0, 0xF0F3FA)
        case .midnight:   return p(0x000000, 0x0B0C12, 0x171924, 0x9A9AA8, 0xE2E4F0)
        // 琉璃（宣传片开篇主视觉：深邃琉璃靛蓝 + 暖阳珊瑚流金）
        case .liuli:      return p(0x161E3C, 0x2B58A8, 0xFF7B47, 0xEEF7F2, 0xFFC845)
        // 朱青（名副其实的湖青瓷釉 + 朱砂正红，鲜明辨识、不和樱粉/暮橙撞色）
        case .zhuqing:    return p(0x0E2430, 0x0EA5B7, 0xE83B35, 0xE2F4F6, 0xFF6B57)
        // 雾紫（纯正电光紫罗兰 → 柔光丁香紫，独立紫系、不偏青蓝）
        case .mistViolet: return p(0x1E1138, 0x7C3AED, 0xD8B4FE, 0xEDE5FF, 0xC084FC)
        // 青瓷（宋瓷冰玉浅碧 → 冰川薄荷青，清冷淡雅、与苔绿/深海明显拉开）
        case .celadon:    return p(0x102B2A, 0x2DD4BF, 0xCCFBF1, 0xDDFBF4, 0x5EEAD4)
        // 暮橙（纯正落日炽橙 → 暖杏余晖，彻底剥离洋红、不和樱粉/胭脂混淆）
        case .duskAmber:  return p(0x2C1208, 0xF97316, 0xFDBA74, 0xFFECD9, 0xFB923C)
        // 深海（纯正深海蔚蓝 → 晴空湛蓝，纯净蓝系）
        case .deepSea:    return p(0x071D34, 0x0369A1, 0x38BDF8, 0xD0EEFC, 0x38BDF8)
        // 樱粉（高明度樱花浅粉 → 晨雾奶桃，柔嫩粉系、与酒红胭脂彻底区分）
        case .sakura:     return p(0x361829, 0xF472B6, 0xFFD6E8, 0xFDE8F2, 0xFBCFE8)
        // 苔绿（植物森林翠绿 → 嫩芽黄绿，鲜明草木绿、告别青蓝雷同）
        case .moss:       return p(0x132612, 0x2F8F2A, 0xA3E635, 0xE1F7D5, 0xBEF264)
        // 沙金（蜂蜜暖金 → 明亮香槟金，纯正黄金色、与炽橙暮橙拉开色相）
        case .sandGold:   return p(0x2A1F0A, 0xD99B06, 0xFEF08A, 0xFEF6D2, 0xFDE047)
        // 月白（清冷月光银 → 珍珠皎白，清透冷银、与黛蓝/深海彻底分离）
        case .moonGrey:   return p(0x1B2230, 0x7E97BA, 0xE4EEFB, 0xECF2FA, 0xDCE8F8)
        // 黛蓝（午夜深藏青 → 皇家钴蓝群青，浓烈靛蓝、与晴空深海明显拉开）
        case .inkBlue:    return p(0x09112E, 0x1E3A8A, 0x4F46E5, 0xD9E0FA, 0x818CF8)
        // 胭脂（深邃丝绒酒红 → 勃艮第宝石红，浓郁暗红、与浅樱粉强烈反差）
        case .rouge:      return p(0x2B0812, 0x881337, 0xE11D48, 0xF8D5DF, 0xFB7185)
        // 极光（极夜霓虹翡翠 → 极光紫罗兰，双色极光异色渐变、一眼辨识）
        case .aurora:     return p(0x0A1F2B, 0x00E5A0, 0x9333EA, 0xD5FBF0, 0x34D399)
        // 烟岚（暖熏烟褐 → 温润暖陶亚麻，暖建筑灰褐、与冷银月白鲜明对比）
        case .smoke:      return p(0x231A15, 0x9B7356, 0xE2C4AA, 0xEFE4DA, 0xE6CBB5)
        }
    }
}
