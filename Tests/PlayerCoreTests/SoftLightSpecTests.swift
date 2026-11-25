// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import XCTest
@testable import PlayerCore

/// 2026-11-23《宣传片同款 21:9 与柔光审美全面同步规范》：可机械判断的部分锁成测试。
final class SoftLightSpecTests: XCTestCase {
    /// 高区分度柔光色板规范表（2026-11-24：拉开所有相近色系差异，每套主题色相独立、一眼辨识）
    func testSpecTablePalettes() {
        let table: [(AppTheme, [String])] = [
            (.liuli, ["#161E3C", "#2B58A8", "#FF7B47", "#FFC845"]),
            (.celadon, ["#102B2A", "#2DD4BF", "#CCFBF1", "#5EEAD4"]),
            (.zhuqing, ["#0E2430", "#0EA5B7", "#E83B35", "#FF6B57"]),
            (.mistViolet, ["#1E1138", "#7C3AED", "#D8B4FE", "#C084FC"]),
            (.deepSea, ["#071D34", "#0369A1", "#38BDF8", "#38BDF8"]),
            (.duskAmber, ["#2C1208", "#F97316", "#FDBA74", "#FB923C"]),
            (.inkBlue, ["#09112E", "#1E3A8A", "#4F46E5", "#818CF8"]),
        ]
        for (t, hx) in table {
            guard let p = t.softLightPalette else { return XCTFail("\(t) 没有柔光色板") }
            XCTAssertEqual([p.primary.hex, p.secondary.hex, p.tertiary.hex, p.accent.hex], hx, "\(t.name) 与规范表不一致")
        }
        XCTAssertNil(AppTheme.followCover.softLightPalette)
        XCTAssertEqual(AppTheme.system.softLightPalette, AppTheme.black.softLightPalette)
    }

    /// 2026-11-24：任意两套彩色主题的主渐变色在 OKLab 空间里必须有清晰视觉差异（杜绝相近色撞脸）
    func testColorfulThemesAreMutuallyDistinct() {
        let colorful = AppTheme.allCases.filter { ![.system, .white, .black, .midnight, .followCover].contains($0) }
        func dist(_ a: OKLab, _ b: OKLab) -> Double {
            let dL = a.L - b.L, da = a.a - b.a, db = a.b - b.b
            return (dL * dL + da * da + db * db).squareRoot()
        }
        for i in 0..<colorful.count {
            for j in (i + 1)..<colorful.count {
                let a = colorful[i].softLightPalette!, b = colorful[j].softLightPalette!
                let dSec = dist(OKLab(a.secondary), OKLab(b.secondary))
                let dTer = dist(OKLab(a.tertiary), OKLab(b.tertiary))
                let combined = (dSec + dTer) / 2
                XCTAssertGreaterThan(combined, 0.11, "\(colorful[i].name) 与 \(colorful[j].name) 配色过于接近（OKLab 平均色差 \(combined)）")
            }
        }
    }

    /// 红线 1：彩色主题的柔光区不能是灰泥（色度下限），底色要比柔光区暗
    func testColorfulThemesAreNotMuddy() {
        let neutral: Set<AppTheme> = [.system, .white, .black, .midnight, .followCover]
        for t in AppTheme.allCases where !neutral.contains(t) {
            let p = t.softLightPalette!
            let s = OKLab(p.secondary), ter = OKLab(p.tertiary), base = OKLab(p.primary)
            // 月白、烟岚本身就是冷灰调主题，下限放到 0.05（仍不能是死铅灰）；其余彩色主题 0.10
            let floor = (t == .moonGrey || t == .smoke) ? 0.05 : 0.10
            XCTAssertGreaterThan(max(s.chroma, ter.chroma), floor, "\(t.name) 柔光区太灰（猪肝/泥灰/铅灰）")
            XCTAssertLessThan(base.L, s.L, "\(t.name) 底色应比主柔光区暗")
        }
    }

    /// 红线 2：不再出现旧朱青的纯红撞死蓝
    func testNoFolkRedVersusDeadBlue() {
        let banned: Set<String> = ["#FF2121", "#C3272B", "#065279", "#F2BE45"]
        for t in AppTheme.allCases {
            guard let p = t.softLightPalette else { continue }
            for c in [p.primary, p.secondary, p.tertiary, p.glassTint, p.accent] {
                XCTAssertFalse(banned.contains(c.hex), "\(t.name) 仍用了 \(c.hex)")
            }
        }
    }

    /// 红线 1：封面取色提亮后不再是低彩度中低明度的灰泥
    func testCoverSoftLightLiftsMuddyPalette() {
        // 典型「猪肝色」取色结果
        let muddy = AmbientPalette(primary: RGB(hex: 0x3A2622), secondary: RGB(hex: 0x7A4E3E), tertiary: RGB(hex: 0xC49278),
                                   glassTint: RGB(hex: 0xEBD0C0), accent: RGB(hex: 0xF0B795))
        let s = muddy.softLight
        let l = [s.primary, s.secondary, s.tertiary].map { OKLab($0) }
        for x in l { XCTAssertGreaterThanOrEqual(x.chroma, 0.10, "提亮后仍偏灰") }
        XCTAssertLessThan(l[0].L, l[1].L); XCTAssertLessThan(l[1].L, l[2].L)
        XCTAssertEqual(s.glassTint, muddy.glassTint)
    }

    /// 红线 5：黑曜石控制条数值
    func testObsidianChromeValues() {
        XCTAssertEqual(ObsidianChrome.fill.hex, "#121018")
        XCTAssertEqual(ObsidianChrome.text.hex, "#F5F6FA")
        XCTAssertEqual(ObsidianChrome.fillOpacity(reduceTransparency: false), 0.82, accuracy: 1e-12)
        XCTAssertGreaterThan(ObsidianChrome.fillOpacity(reduceTransparency: true), 0.9)
        XCTAssertTrue(ObsidianChrome.usesMaterial(reduceTransparency: false))
        XCTAssertFalse(ObsidianChrome.usesMaterial(reduceTransparency: true))
    }
}
