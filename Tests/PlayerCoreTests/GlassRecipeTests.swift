// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import XCTest
@testable import PlayerCore

final class GlassRecipeTests: XCTestCase {

    private let themes: [(String, Bool, Bool, Bool)] = [
        ("default", false, false, false),
        ("midnight", true, false, false),
        ("light", false, true, false),
        ("liuli", false, false, true),
        ("liuli-light", false, true, true),
        ("liuli-midnight", true, false, true),
    ]

    func testFloatingIsMoreTransmissiveThanRegularAndClear() {
        for (name, midnight, light, liuli) in themes {
            let floating = GlassRecipe.resolve(variant: .floating, midnight: midnight, light: light, liuli: liuli, reduceTransparency: false)
            let regular = GlassRecipe.resolve(variant: .regular, midnight: midnight, light: light, liuli: liuli, reduceTransparency: false)
            let clear = GlassRecipe.resolve(variant: .clear, midnight: midnight, light: light, liuli: liuli, reduceTransparency: false)
            XCTAssertTrue(floating.usesMaterial, "\(name) 浮层应使用真实系统材质，让背景透出")
            XCTAssertTrue(floating.usesUltraThin, "\(name) 浮层应使用 ultraThin 磨砂，而不是更厚的材质或假灰底")
            XCTAssertGreaterThanOrEqual(floating.materialOpacity, 0.35, "\(name) 材质过淡就不成磨砂")
            XCTAssertLessThan(floating.materialOpacity, regular.materialOpacity, "\(name) 浮层材质不透明度应低于 regular")
            XCTAssertLessThan(floating.materialOpacity, clear.materialOpacity, "\(name) 浮层材质不透明度应低于 clear")
            XCTAssertLessThan(floating.washOpacity, regular.washOpacity, "\(name) 浮层遮挡底色应低于 regular，避免整块灰底")
            XCTAssertLessThan(floating.washOpacity, clear.washOpacity, "\(name) 浮层遮挡底色应低于 clear")
            XCTAssertLessThanOrEqual(floating.washOpacity, 0.22, "\(name) 浮层遮挡底色过高会变成灰贴片")
            if liuli {
                XCTAssertGreaterThan(floating.liuliBody, 0)
                XCTAssertLessThan(floating.liuliBody, regular.liuliBody)
                XCTAssertLessThan(floating.liuliBody, clear.liuliBody)
            } else {
                XCTAssertEqual(floating.liuliBody, 0)
            }
        }
    }

    func testReduceTransparencyDropsMaterialAndUsesOpaqueWash() {
        for variant in GlassSurfaceVariant.allCases {
            for (name, midnight, light, liuli) in themes {
                let reduced = GlassRecipe.resolve(variant: variant, midnight: midnight, light: light, liuli: liuli, reduceTransparency: true)
                let normal = GlassRecipe.resolve(variant: variant, midnight: midnight, light: light, liuli: liuli, reduceTransparency: false)
                XCTAssertFalse(reduced.usesMaterial, "\(variant) \(name) 降低透明度时不应再铺模糊材质")
                XCTAssertEqual(reduced.materialOpacity, 0, accuracy: 1e-12)
                XCTAssertEqual(reduced.liuliBody, 0, accuracy: 1e-12)
                XCTAssertGreaterThanOrEqual(reduced.washOpacity, 0.80, "\(variant) \(name) 降低透明度时底色需足够实，保证文字可读")
                XCTAssertGreaterThan(reduced.washOpacity, normal.washOpacity, "\(variant) \(name) 降低透明度时应比正常态更不透明")
            }
        }
    }

    func testRegularAndClearRecipesStayAtExistingChromeValues() {
        let regularDefault = GlassRecipe.resolve(variant: .regular, midnight: false, light: false, liuli: false, reduceTransparency: false)
        XCTAssertEqual(regularDefault.usesMaterial, true)
        XCTAssertEqual(regularDefault.usesUltraThin, false)
        XCTAssertEqual(regularDefault.materialOpacity, 1, accuracy: 1e-12)
        XCTAssertEqual(regularDefault.washWhite, 1, accuracy: 1e-12)
        XCTAssertEqual(regularDefault.washOpacity, 0.07, accuracy: 1e-12)
        XCTAssertEqual(regularDefault.tintMultiplier, 1.4, accuracy: 1e-12)

        let clearMidnight = GlassRecipe.resolve(variant: .clear, midnight: true, light: false, liuli: false, reduceTransparency: false)
        XCTAssertEqual(clearMidnight.usesUltraThin, true)
        XCTAssertEqual(clearMidnight.materialOpacity, 0.9, accuracy: 1e-12)
        XCTAssertEqual(clearMidnight.washWhite, 0.11, accuracy: 1e-12)
        XCTAssertEqual(clearMidnight.washOpacity, 0.72, accuracy: 1e-12)
        XCTAssertEqual(clearMidnight.tintMultiplier, 0.5, accuracy: 1e-12)

        let regularLight = GlassRecipe.resolve(variant: .regular, midnight: false, light: true, liuli: false, reduceTransparency: false)
        XCTAssertEqual(regularLight.washOpacity, 0.38, accuracy: 1e-12)
        let clearLight = GlassRecipe.resolve(variant: .clear, midnight: false, light: true, liuli: false, reduceTransparency: false)
        XCTAssertEqual(clearLight.washOpacity, 0.30, accuracy: 1e-12)

        let regularLiuli = GlassRecipe.resolve(variant: .regular, midnight: false, light: false, liuli: true, reduceTransparency: false)
        XCTAssertEqual(regularLiuli.usesUltraThin, true)
        XCTAssertEqual(regularLiuli.materialOpacity, 0.92, accuracy: 1e-12)
        XCTAssertEqual(regularLiuli.washOpacity, 0.06, accuracy: 1e-12)
        XCTAssertEqual(regularLiuli.liuliBody, 1, accuracy: 1e-12)
        let clearLiuli = GlassRecipe.resolve(variant: .clear, midnight: false, light: false, liuli: true, reduceTransparency: false)
        XCTAssertEqual(clearLiuli.materialOpacity, 0.82, accuracy: 1e-12)
        XCTAssertEqual(clearLiuli.washOpacity, 0.045, accuracy: 1e-12)
        XCTAssertEqual(clearLiuli.liuliBody, 0.8, accuracy: 1e-12)
    }

    func testFloatingInventoryListsInAppPanelsAndExcludesNativeMenus() {
        let surfaces = Set(GlassFloatingSurface.allCases.map(\.rawValue))
        XCTAssertEqual(surfaces, [
            "hud", "themePopover", "equalizerSavePopover", "loopEditor",
            "speedPitchPanel", "subtitleSearchPanel", "autoEqPanel",
            "shortcutsOverlay", "dropOverlayPrompt", "asrProgressCapsule",
        ])
        XCTAssertTrue(GlassFloatingSurface.allCases.allSatisfy { _ in true })
        let native = Set(GlassNativeChromeNotUnified.allCases.map(\.rawValue))
        XCTAssertEqual(native, [
            "aspectRatioMenu", "trackMenu", "outputDeviceMenu",
            "contextMenus", "openPanel", "alerts",
        ])
        XCTAssertTrue(Set(GlassFloatingSurface.allCases.map(\.rawValue)).isDisjoint(with: native))
    }
}
