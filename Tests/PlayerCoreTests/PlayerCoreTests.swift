// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import XCTest
import Foundation
@testable import PlayerCore

final class ThemeIsolationTests: XCTestCase {
    /// 新增「朱青」时其他主题一个颜色都不能变：这里是加主题之前的原值
    func testExistingPalettesUnchanged() {
        let expected: [(AppTheme, [String])] = [
            (.white, ["#E6E7EB", "#EFF0F3", "#FAFAFC", "#FFFFFF", "#2C2C30"]),
            (.black, ["#121214", "#1E1F22", "#34363B", "#9A9BA1", "#F0F0F2"]),
            (.liuli, ["#1C223B", "#3B4160", "#2775B6", "#EEF7F2", "#EBB10D"]),
            (.midnight, ["#000000", "#0B0B0F", "#17171D", "#9A9AA8", "#D8D8E4"]),
            (.mistViolet, ["#2C2846", "#544C86", "#9184C0", "#C9C2EA", "#C6BAFA"]),
            (.celadon, ["#1F3532", "#3E6560", "#86AFA6", "#C4DDD6", "#A9D9CC"]),
            (.duskAmber, ["#3A2622", "#7A4E3E", "#C49278", "#EBD0C0", "#F0B795"]),
            (.deepSea, ["#0F1E30", "#23466A", "#5F8FB6", "#B6CDE2", "#9CC6EC"]),
            (.sakura, ["#3A2730", "#7A5262", "#C7A0AE", "#EED7DE", "#F2B9CB"]),
            (.moss, ["#1E2A1E", "#45583E", "#93A784", "#D0DCC4", "#C2D9A6"]),
            (.sandGold, ["#302A20", "#6A5C42", "#B9A47C", "#E8DCC2", "#E9CF97"]),
            (.moonGrey, ["#2A2E36", "#575F6E", "#A3ACBC", "#DDE2EA", "#E2E8F4"]),
            (.inkBlue, ["#1A2133", "#384765", "#7887A8", "#C3CBDE", "#A8B8E6"]),
            (.rouge, ["#341C24", "#6E3A48", "#B27886", "#E7CBD2", "#EDA3B4"]),
            (.aurora, ["#0F2226", "#1F5452", "#5FA89A", "#BFE3DA", "#8EE6CF"]),
            (.smoke, ["#26282A", "#4E5254", "#969B9D", "#D6D9DA", "#D2D8DC"]),
        ]
        for (t, hx) in expected {
            guard let p = t.palette else { return XCTFail("\(t) 没有配色") }
            XCTAssertEqual([p.primary.hex, p.secondary.hex, p.tertiary.hex, p.glassTint.hex, p.accent.hex], hx, "\(t.name) 的配色变了")
        }
        XCTAssertEqual(AppTheme.system.palette, AppTheme.black.palette)
        XCTAssertNil(AppTheme.followCover.palette)
    }
    func testZhuqingPalette() {
        let p = AppTheme.zhuqing.palette!
        XCTAssertEqual([p.primary.hex, p.secondary.hex, p.tertiary.hex, p.glassTint.hex, p.accent.hex], ["#065279", "#177CB0", "#C3272B", "#D6ECF0", "#FF2121"])
        XCTAssertEqual(AppTheme.zhuqing.name, AppTheme.zhuqingName)
        XCTAssertEqual(AppTheme(rawValue: "zhuqing"), .zhuqing)
        XCTAssertFalse(AppTheme.zhuqing.isLight)
    }
}

final class SpringTests: XCTestCase {
    func testSpringConvergesAndIsFrameRateIndependent() {
        let p = SpringParameters.carouselSnap
        var a = SpringState(value: 0, velocity: 3)
        var b = a
        for _ in 0..<120 { a = Spring.step(a, target: 1, params: p, dt: 1.0 / 120) }   // 120Hz 推 1 秒
        for _ in 0..<60 { b = Spring.step(b, target: 1, params: p, dt: 1.0 / 60) }     // 60Hz 推 1 秒
        XCTAssertEqual(a.value, b.value, accuracy: 1e-9, "解析解：60/120Hz 轨迹必须一致")
        var c = SpringState(value: 0)
        for _ in 0..<480 { c = Spring.step(c, target: 1, params: p, dt: 1.0 / 120) }
        XCTAssertTrue(Spring.isSettled(c, target: 1))
    }

    func testCriticalAndOverdampedBranches() {
        for z in [1.0, 1.4] {
            var s = SpringState(value: 5, velocity: 0)
            for _ in 0..<600 { s = Spring.step(s, target: 0, params: .init(response: 0.4, dampingFraction: z), dt: 1.0 / 120) }
            XCTAssertEqual(s.value, 0, accuracy: 1e-4)
        }
    }

    func testRubberBandIsMonotoneAndBounded() {
        var last = -1.0
        for i in 0...100 {
            let y = RubberBand.dampen(Double(i) * 0.1)
            XCTAssertGreaterThan(y, last); XCTAssertLessThan(y, 1.0); last = y
        }
        XCTAssertEqual(RubberBand.clamp(0.5, min: 0, max: 3), 0.5)
        XCTAssertLessThan(RubberBand.clamp(-2, min: 0, max: 3), 0)
        XCTAssertGreaterThan(RubberBand.clamp(-2, min: 0, max: 3), -1)
    }
}

final class CarouselTests: XCTestCase {
    func run(_ c: inout CarouselPhysics, seconds: Double = 2) {
        var t = 0.0
        while t < seconds { c.tick(dt: 1.0 / 120); t += 1.0 / 120 }
    }

    func testDragSnapsToIntegerNeverHalfway() {
        var c = CarouselPhysics(count: 10, index: 3)
        c.beginDrag(time: 0)
        c.drag(deltaCards: 0.45, time: 0.1)   // 慢慢拖了不到半张
        c.endDrag(time: 0.3)                  // 停顿后松手
        run(&c)
        XCTAssertEqual(c.position, 3, "不到半张应回到原卡")
        c.beginDrag(time: 1)
        c.drag(deltaCards: 0.55, time: 1.1)
        c.endDrag(time: 1.3)
        run(&c)
        XCTAssertEqual(c.position, 4)
        XCTAssertFalse(c.isAnimating)
    }

    func testFlingProjectsSeveralCards() {
        var c = CarouselPhysics(count: 30, index: 5)
        c.beginDrag(time: 0)
        var t = 0.0
        for _ in 0..<12 { t += 1.0 / 120; c.drag(deltaCards: 0.20, time: t) }   // ~24 卡/秒的快甩
        c.endDrag(time: t)
        run(&c)
        XCTAssertGreaterThan(c.target, 8)
        XCTAssertLessThanOrEqual(c.target, 5 + 2 + c.maxFlingCards + 1)
        XCTAssertEqual(c.position, Double(c.target))
    }

    func testRubberBandAtEdgesAndReturn() {
        var c = CarouselPhysics(count: 5, index: 0)
        c.beginDrag(time: 0)
        c.drag(deltaCards: -3, time: 0.1)
        XCTAssertLessThan(c.position, 0)
        XCTAssertGreaterThan(c.position, -1, "首卡橡皮筋：拉 3 张只显示不到 1 张")
        c.endDrag(time: 0.11)
        run(&c)
        XCTAssertEqual(c.position, 0)
        c.jump(to: 99)
        run(&c)
        XCTAssertEqual(c.position, 4)
    }

    func testRegrabDuringRubberBandDoesNotJump() {
        var c = CarouselPhysics(count: 5, index: 4)
        c.beginDrag(time: 0)
        c.drag(deltaCards: 2, time: 0.05)
        let shown = c.position
        c.endDrag(time: 0.06)
        c.beginDrag(time: 0.07)
        c.drag(deltaCards: 0, time: 0.08)
        XCTAssertEqual(c.position, shown, accuracy: 1e-6)
    }

    func testPoseContinuityAndSymmetry() {
        let a = CardPose.pose(relative: 0.999), b = CardPose.pose(relative: 1.001)
        XCTAssertEqual(a.rotationY, b.rotationY, accuracy: 0.2)
        XCTAssertEqual(a.x, b.x, accuracy: 0.01)
        let l = CardPose.pose(relative: -1.5), r = CardPose.pose(relative: 1.5)
        XCTAssertEqual(l.x, -r.x, accuracy: 1e-9)
        XCTAssertEqual(l.rotationY, -r.rotationY, accuracy: 1e-9)
        XCTAssertEqual(CardPose.pose(relative: 0).scale, 1)
    }
}

final class EqualizerTests: XCTestCase {
    func testBandLayouts() {
        let f16 = EQBandCount.sixteen.frequencies, f32 = EQBandCount.thirtyTwo.frequencies
        XCTAssertEqual(f16.count, 16); XCTAssertEqual(f32.count, 32)
        XCTAssertEqual(f16.first!, 20, accuracy: 1e-9); XCTAssertEqual(f16.last!, 20000, accuracy: 1e-6)
        XCTAssertEqual(f32.last!, 20000, accuracy: 1e-6)
        XCTAssertEqual(EQBandCount.thirtyTwo.bandwidthOctaves, 0.3214, accuracy: 0.001)
    }

    func testPresetsSameShapeOn16And32() {
        for p in EQPreset.builtIns {
            let g16 = p.gains(for: .sixteen), g32 = p.gains(for: .thirtyTwo)
            XCTAssertEqual(g16.count, 16)
            // 32 段的偶数位频率 ≈ 16 段频率附近，曲线连续 → 差值很小
            XCTAssertLessThan(abs(g16[0] - g32[0]), 0.11, p.name)
            XCTAssertLessThan(abs(g16[15] - g32[31]), 0.11, p.name)
            for g in g32 { XCTAssertTrue(EQState.gainRange.contains(g), p.name) }
        }
    }

    func testSwitchBandCountKeepsCurve() {
        var s = EQState(enabled: true)
        s.apply(EQPreset.builtIns.first { $0.id == "bass" }!)
        let low = s.gains[0]
        s.switchBandCount(.thirtyTwo)
        XCTAssertEqual(s.gains.count, 32)
        XCTAssertEqual(s.gains[0], low, accuracy: 0.11)
        s.switchBandCount(.sixteen)
        XCTAssertEqual(s.gains.count, 16)
    }

    func testFilterGraphString() {
        var s = EQState(enabled: true, bandCount: .sixteen)
        s.setGain(3.5, band: 2)
        s.preamp = -3
        let f = MPVEqualizerGraph.filterString(for: s)
        XCTAssertTrue(f.hasPrefix("@tancoeq:lavfi=[volume@pre=volume=-3dB:precision=float,equalizer@b0=f=20:t=o:w="))
        XCTAssertTrue(f.contains("equalizer@b2="))
        XCTAssertTrue(f.contains(":g=3.5:m=1:r=f64"))
        XCTAssertTrue(f.hasSuffix("]"))
        XCTAssertEqual(f.components(separatedBy: "equalizer@").count - 1, 16)
        XCTAssertEqual(MPVEqualizerGraph.gainCommand(band: 7, db: -2.25), ["af-command", "tancoeq", "gain", "-2.25", "equalizer@b7"])
        XCTAssertEqual(MPVEqualizerGraph.preampCommand(db: -6), ["af-command", "tancoeq", "volume", "-6dB", "volume@pre"])
        s.enabled = false
        XCTAssertTrue(MPVEqualizerGraph.filterString(for: s).contains(":m=0:"))
    }

    func testMonotoneInterpolationNoOvershoot() {
        let xs = [0.0, 1, 2, 3], ys = [0.0, 5, 5, 0]
        for i in 0...300 {
            let y = MonotoneCubic.interpolate(xs: xs, ys: ys, at: Double(i) / 100)
            XCTAssertLessThanOrEqual(y, 5.0001); XCTAssertGreaterThanOrEqual(y, -0.0001)
        }
    }
}

final class QueueTests: XCTestCase {
    func items(_ n: Int) -> [MediaItem] { (0..<n).map { MediaItem(url: URL(fileURLWithPath: "/m/\($0).flac")) } }

    func testSequentialAndRepeat() {
        var q = PlayQueue(); q.replace(with: items(3))
        q.repeatMode = .off
        XCTAssertEqual(q.nextIndex(manual: false), 1)
        q.select(2)
        XCTAssertNil(q.nextIndex(manual: false))
        q.repeatMode = .all
        XCTAssertEqual(q.nextIndex(manual: false), 0)
        q.repeatMode = .one
        XCTAssertEqual(q.nextIndex(manual: false), 2)
        XCTAssertEqual(q.nextIndex(manual: true), 0)
        XCTAssertEqual(q.previousIndex(), 1)
    }

    func testShuffleVisitsAllOnce() {
        var q = PlayQueue(); q.replace(with: items(20), startAt: 7)
        q.repeatMode = .off
        q.setShuffle(true)
        var seen: Set<Int> = [7]
        while let n = q.nextIndex(manual: true) { XCTAssertFalse(seen.contains(n)); seen.insert(n); q.select(n) ; if seen.count == 20 { break } }
        XCTAssertEqual(seen.count, 20)
    }

    func testRemoveAndMoveKeepCurrent() {
        var q = PlayQueue(); q.replace(with: items(5), startAt: 3)
        let cur = q.current!.id
        q.remove(at: 0)
        XCTAssertEqual(q.current!.id, cur)
        q.move(from: 2, to: 0)
        XCTAssertEqual(q.current!.id, cur)
        XCTAssertEqual(q.append(items(5)), 4, "只有被删掉的 0 号是新项")
        XCTAssertEqual(q.items.count, 5)
        q.append(items(5))
        XCTAssertEqual(q.items.count, 5, "重复添加不应产生新项")
    }

    func testFilenameParsing() {
        let u = URL(fileURLWithPath: "/x/03 - 周杰伦 - 晴天.flac")
        XCTAssertEqual(MediaItem.titleFromFilename(u), "晴天")
        XCTAssertEqual(MediaItem.artistFromFilename(u), "周杰伦")
        XCTAssertEqual(MediaItem.titleFromFilename(URL(fileURLWithPath: "/x/Holocene.mp3")), "Holocene")
    }

    func testSubtitleMatching() {
        let v = URL(fileURLWithPath: "/v/Movie.2024.mkv")
        let listing = ["Movie.2024.chs.ass", "Movie.2024.eng.srt", "Other.srt", "Movie.2024.chs&eng.ass", "Movie.2024.mkv"].map { URL(fileURLWithPath: "/v/" + $0) }
        let subs = SubtitleMatcher.sidecars(for: v, in: listing).map(\.lastPathComponent)
        XCTAssertEqual(subs.count, 3)
        XCTAssertEqual(subs.first, "Movie.2024.chs&eng.ass")
        XCTAssertFalse(subs.contains("Other.srt"))
    }
}

final class ColorAndCoverTests: XCTestCase {
    func testOKLabRoundTrip() {
        for hex: UInt32 in [0x000000, 0xFFFFFF, 0x8C7BD1, 0x123456, 0xE0957A] {
            let c = RGB(hex: hex)
            XCTAssertEqual(OKLab(c).rgb.hex, c.hex)
        }
    }

    func testPaletteIsLowSaturationAndDark() {
        // 一张高饱和的红蓝图
        var px: [UInt8] = []
        for i in 0..<(32 * 32) { px += i % 3 == 0 ? [250, 20, 30, 255] : [20, 40, 240, 255] }
        let p = AmbientPalette.extract(rgba: px, width: 32, height: 32)
        for c in [p.primary, p.secondary, p.tertiary] {
            let lab = OKLab(c)
            XCTAssertLessThanOrEqual(lab.chroma, 0.095, "背景色必须低饱和")
        }
        XCTAssertLessThan(OKLab(p.primary).L, 0.42)
        XCTAssertGreaterThan(OKLab(p.glassTint).L, 0.75)
    }

    func testDefaultCoverSpecMatchesPythonRenderer() throws {
        let url = Bundle.module.url(forResource: "default_cover_specs", withExtension: "json", subdirectory: "Fixtures")!
        let arr = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        XCTAssertGreaterThanOrEqual(arr.count, 6)
        for d in arr {
            let seed = d["seed"] as! String
            let s = DefaultCoverSpec.make(seed: seed)
            XCTAssertEqual(String(s.hash), d["hash"] as! String, seed)
            XCTAssertEqual(s.paletteIndex, (d["paletteIndex"] as! NSNumber).intValue, seed)
            XCTAssertEqual(s.motif.rawValue, (d["motif"] as! NSNumber).intValue, seed)
            XCTAssertEqual(s.angle, (d["angle"] as! NSNumber).doubleValue, seed)
            XCTAssertEqual(s.motifX, (d["motifX"] as! NSNumber).doubleValue, seed)
            XCTAssertEqual(s.motifY, (d["motifY"] as! NSNumber).doubleValue, seed)
            XCTAssertEqual(s.motifSize, (d["motifSize"] as! NSNumber).doubleValue, seed)
            XCTAssertEqual(UInt64(s.grainSeed), (d["grainSeed"] as! NSNumber).uint64Value, seed)
            let blobs = d["blobs"] as! [[String: NSNumber]]
            for (b, e) in zip(s.blobs, blobs) {
                XCTAssertEqual(b.x, e["x"]!.doubleValue); XCTAssertEqual(b.y, e["y"]!.doubleValue); XCTAssertEqual(b.r, e["r"]!.doubleValue)
            }
        }
    }
}

final class PersistenceTests: XCTestCase {
    func testResumeRules() {
        var b = ResumeBook()
        b.record(key: "song", position: 60, duration: 200, kind: .audio)
        XCTAssertEqual(b.position(for: "song"), 60)
        b.record(key: "short", position: 60, duration: 150, kind: .audio)
        XCTAssertNil(b.position(for: "short"), "短歌不记位置")
        b.record(key: "movie", position: 3000, duration: 3005, kind: .video)
        XCTAssertNil(b.position(for: "movie"), "看完了不记")
        b.record(key: "movie", position: 1200, duration: 5400, kind: .video)
        XCTAssertEqual(b.position(for: "movie"), 1200)
    }

    func testSessionRoundTrip() throws {
        var s = SessionState()
        s.queue.replace(with: [MediaItem(url: URL(fileURLWithPath: "/a/b.flac"), title: "测试")])
        s.eq.switchBandCount(.thirtyTwo)
        s.customPresets.append(EQPreset(customName: "我的", frequencies: s.eq.frequencies, gains: s.eq.gains))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("glass-test-\(UUID().uuidString)/s.json")
        try SessionStore.save(s, to: url)
        let r = SessionStore.load(from: url)
        XCTAssertEqual(r, s)
    }

    func testColdStartDropsQueueAndLastPositionButKeepsNonMediaPrefs() {
        var saved = SessionState()
        saved.queue.replace(with: [
            MediaItem(url: URL(fileURLWithPath: "/tmp/last.mp4"), title: "上次的视频"),
            MediaItem(url: URL(fileURLWithPath: "/tmp/last.flac"), title: "上次的歌"),
        ])
        saved.volume = 75
        saved.muted = true
        saved.eq.switchBandCount(.thirtyTwo)
        saved.customPresets.append(EQPreset(customName: "书房", frequencies: saved.eq.frequencies, gains: saved.eq.gains))
        saved.lastPosition = 91.4
        saved.resume.record(key: "movie", position: 1200, duration: 5400, kind: .video)

        let launched = LaunchPolicy.preparedSession(from: saved)
        // 2026-11-23 TANCO 改规则：启动时恢复播放列表，但不自动播放、不带上次进度
        XCTAssertEqual(launched.queue.items.map(\.title), ["上次的视频", "上次的歌"], "启动时恢复上次的播放列表")
        XCTAssertEqual(launched.queue.currentIndex, 0)
        XCTAssertEqual(launched.lastPosition, 0, accuracy: 0.0001, "不能带着上次播放进度启动")
        XCTAssertEqual(launched.volume, 75)
        XCTAssertTrue(launched.muted)
        XCTAssertEqual(launched.eq, saved.eq)
        XCTAssertEqual(launched.customPresets, saved.customPresets)
        XCTAssertEqual(launched.resume.position(for: "movie"), 1200, "单曲续播书保留，供显式再次打开同一文件时使用")
        // 磁盘上的会话原文不应被策略函数改写
        XCTAssertEqual(saved.lastPosition, 91.4)
        XCTAssertEqual(saved.queue.items.count, 2)
    }

    func testColdStartEmptySessionDoesNotBlockExplicitOpen() {
        var saved = SessionState()
        saved.queue.replace(with: [MediaItem(url: URL(fileURLWithPath: "/tmp/old.mkv"), title: "旧视频")])
        saved.lastPosition = 42
        let launched = LaunchPolicy.preparedSession(from: saved)
        let incoming = [
            URL(fileURLWithPath: "/tmp/explicit-open.mp4"),
            URL(string: "https://example.com/not-a-file")!,
        ]
        let playable = LaunchPolicy.explicitOpenURLs(incoming)
        XCTAssertEqual(launched.queue.items.count, 1, "恢复的列表不影响显式打开")
        XCTAssertEqual(playable, [URL(fileURLWithPath: "/tmp/explicit-open.mp4")])
        XCTAssertFalse(playable.isEmpty, "启动恢复列表后也不能吞掉显式打开的本地文件")
    }

    func testFreshStartupClearsQueueWhilePreservingPreferences() {
        var saved = SessionState()
        saved.queue.replace(with: [
            MediaItem(url: URL(fileURLWithPath: "/tmp/a.flac"), title: "曲目 A"),
            MediaItem(url: URL(fileURLWithPath: "/tmp/b.mp4"), title: "视频 B"),
        ])
        saved.queue.repeatMode = .all
        saved.queue.setShuffle(true)
        saved.volume = 68
        saved.eq.enabled = true
        saved.lastPosition = 88.5
        saved.resume.record(key: "videoB", position: 320, duration: 1800, kind: .video)

        let fresh = LaunchPolicy.preparedSession(from: saved, resumeQueue: false)
        XCTAssertTrue(fresh.queue.items.isEmpty, "默认全新空白启动时，正在播放队列必须为空")
        XCTAssertNil(fresh.queue.currentIndex)
        XCTAssertEqual(fresh.lastPosition, 0, accuracy: 0.0001)
        XCTAssertEqual(fresh.queue.repeatMode, .all, "循环模式等偏好必须保留")
        XCTAssertTrue(fresh.queue.shuffle, "随机开关等偏好必须保留")
        XCTAssertEqual(fresh.volume, 68)
        XCTAssertTrue(fresh.eq.enabled)
        XCTAssertEqual(fresh.resume.position(for: "videoB"), 320, "单曲续播记录必须保留")
    }

    func testLyrics() {
        let l = Lyrics.parse("[ti:x]\n[00:01.50]第一句\n[00:03.00][00:10.00]副歌\n[offset:500]\n")
        XCTAssertTrue(l.isSynced)
        XCTAssertEqual(l.lines.count, 3)
        XCTAssertEqual(l.index(at: 2.0), 0)
        XCTAssertEqual(l.index(at: 9.99), 1)
        XCTAssertNil(l.index(at: 0.1))
        XCTAssertFalse(Lyrics.parse("没有时间轴\n第二行").isSynced)
    }

    func testTimeFormat() {
        XCTAssertEqual(TimeFormat.clock(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(3725), "1:02:05")
        XCTAssertEqual(TimeFormat.clock(nil), "--:--")
        XCTAssertEqual(TimeFormat.remaining(10, 70), "-1:00")
    }
}

final class ThemeTests: XCTestCase {
    func testThemesCompleteAndCalm() {
        XCTAssertGreaterThanOrEqual(AppTheme.allCases.count, 9)
        XCTAssertNil(AppTheme.followCover.palette)
        let black = AppTheme.midnight.palette!.primary
        XCTAssertEqual(black.r, 0); XCTAssertEqual(black.g, 0); XCTAssertEqual(black.b, 0)
        for t in AppTheme.allCases where !t.followsCover {
            let pal = t.palette!
            // 背景三色：低饱和（OKLCH 色度上限）且明度递增
            let ls = [pal.primary, pal.secondary, pal.tertiary].map { OKLab($0) }
            // 琉璃主题按 TANCO 的参考（瑠璃色）本来就是深饱和的蓝紫，放宽到 0.16
            // 朱青要「很中国」：中国红、中国蓝本来就是饱和色（靛青、赤），放宽到 0.20；红光（赤）比蓝光（靛青）略暗，不要求明度递增，只要求底色最暗
            let limit = t == .liuli ? 0.16 : (t == .zhuqing ? 0.20 : 0.11)
            for l in ls { XCTAssertLessThan((l.a * l.a + l.b * l.b).squareRoot(), limit, "\(t.name) 太艳") }
            if t == .zhuqing { XCTAssertLessThan(ls[0].L, min(ls[1].L, ls[2].L)) }
            else { XCTAssertLessThan(ls[0].L, ls[1].L); XCTAssertLessThan(ls[1].L, ls[2].L) }
            XCTAssertFalse(t.name.isEmpty)
        }
        XCTAssertEqual(Set(AppTheme.allCases.map(\.name)).count, AppTheme.allCases.count)
    }

    func testDefaultFollowsSystemBlackWhite() {
        XCTAssertEqual(AppTheme.system.resolved(systemDark: true), .black)
        XCTAssertEqual(AppTheme.system.resolved(systemDark: false), .white)
        XCTAssertEqual(AppTheme.liuli.resolved(systemDark: false), .liuli)
        XCTAssertTrue(AppTheme.white.isLight); XCTAssertFalse(AppTheme.black.isLight)
        // 原 14 套仍在
        for raw in ["followCover", "midnight", "mistViolet", "celadon", "duskAmber", "deepSea", "sakura", "moss", "sandGold", "moonGrey", "inkBlue", "rouge", "aurora", "smoke"] {
            XCTAssertNotNil(AppTheme(rawValue: raw), raw)
        }
    }
}

final class QueueEditTests: XCTestCase {
    private func items(_ n: Int) -> [MediaItem] { (0..<n).map { MediaItem(url: URL(fileURLWithPath: "/m/\($0).flac")) } }

    func testInsertKeepsCurrentAndDedupes() {
        var q = PlayQueue(); q.replace(with: items(4), startAt: 2)          // 当前 = /m/2
        let new = [MediaItem(url: URL(fileURLWithPath: "/m/x.flac")), MediaItem(url: URL(fileURLWithPath: "/m/0.flac"))]
        let at = q.insert(new, at: 1)
        XCTAssertEqual(q.items.map { $0.url.lastPathComponent }, ["x.flac", "0.flac", "1.flac", "2.flac", "3.flac"])
        XCTAssertEqual(at, 0)    // /m/0 原本在插入点之前，被挪走后插入点前移
        XCTAssertEqual(q.current?.url.lastPathComponent, "2.flac")
        q.insert([MediaItem(url: URL(fileURLWithPath: "/m/y.flac"))], at: 99)
        XCTAssertEqual(q.items.last?.url.lastPathComponent, "y.flac")
    }

    func testInsertIntoEmptySetsCurrent() {
        var q = PlayQueue()
        XCTAssertEqual(q.insert(items(2), at: 0), 0)
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testSortReverseScrambleKeepCurrent() {
        var q = PlayQueue(); q.replace(with: items(6).reversed(), startAt: 1)   // 当前 = /m/4
        q.sort { $0.url.path < $1.url.path }
        XCTAssertEqual(q.items.first?.url.lastPathComponent, "0.flac")
        XCTAssertEqual(q.current?.url.lastPathComponent, "4.flac")
        q.reverse(); XCTAssertEqual(q.current?.url.lastPathComponent, "4.flac")
        q.scramble(seed: 42); XCTAssertEqual(q.current?.url.lastPathComponent, "4.flac")
        XCTAssertEqual(Set(q.items.map(\.id)).count, 6)
    }

    func testM3URoundTrip() {
        let its = [MediaItem(url: URL(fileURLWithPath: "/音乐/晚风.flac"), title: "晚风", artist: "陈默", duration: 45),
                   MediaItem(url: URL(fileURLWithPath: "/a b/c.mkv"))]
        let text = PlaylistFile.m3u8(its)
        XCTAssertTrue(text.hasPrefix("#EXTM3U"))
        let back = PlaylistFile.parse(text, relativeTo: URL(fileURLWithPath: "/x"))
        XCTAssertEqual(back.map(\.path), ["/音乐/晚风.flac", "/a b/c.mkv"])
        let rel = PlaylistFile.parse("\u{FEFF}#EXTM3U\nsub/1.mp3\nhttps://e.com/s.mp3\n[playlist]\nFile1=/p/q.ogg\n", relativeTo: URL(fileURLWithPath: "/base"))
        XCTAssertEqual(rel.map { $0.isFileURL ? $0.path : $0.absoluteString }, ["/base/sub/1.mp3", "https://e.com/s.mp3", "/p/q.ogg"])
    }
}

final class MiscParseTests: XCTestCase {
    func testTimeParse() {
        XCTAssertEqual(TimeFormat.parse("1:23"), 83)
        XCTAssertEqual(TimeFormat.parse("01:02:03"), 3723)
        XCTAssertEqual(TimeFormat.parse("95.5"), 95.5)
        XCTAssertEqual(TimeFormat.parse("2：00"), 120)
        XCTAssertNil(TimeFormat.parse("abc"))
        XCTAssertNil(TimeFormat.parse("1:2:3:4"))
        XCTAssertNil(TimeFormat.parse(""))
    }
    func testChannelFilter() {
        let eq = EQState()
        XCTAssertEqual(ChannelMode.audioFilter(eq: eq, channel: .stereo), MPVEqualizerGraph.filterString(for: eq))
        XCTAssertTrue(ChannelMode.audioFilter(eq: eq, channel: .swap).hasSuffix(",@tancoch:lavfi=[pan=stereo|c0=c1|c1=c0]"))
    }
}

final class LoopEditTests: XCTestCase {
    func testPreciseFormatAndParse() {
        XCTAssertEqual(TimeFormat.precise(83.456), "01:23.456")
        XCTAssertEqual(TimeFormat.precise(3723.5), "1:02:03.500")
        XCTAssertEqual(TimeFormat.parse("01:23.456")!, 83.456, accuracy: 1e-9)
        XCTAssertEqual(TimeFormat.parse("1:02:03")!, 3723, accuracy: 1e-9)
        XCTAssertEqual(TimeFormat.parse("12,5")!, 12.5, accuracy: 1e-9)
        XCTAssertNil(TimeFormat.parse("ab:cd"))
    }
    func testChorusDetectorFindsLoudestRepeatedSection() {
        // 合成色度：前奏 5s、主歌 19.2s、副歌 19.2s、主歌、副歌、桥段 9.6s、副歌；副歌更响
        func chordVec(_ notes: [Int]) -> [Float] {
            var v = [Float](repeating: 0.15, count: 12); for n in notes { v[n % 12] = 1 }
            let m = sqrt(v.reduce(0) { $0 + $1 * $1 }); return v.map { $0 / m }
        }
        let verse = [[9, 0, 4], [5, 9, 0], [0, 4, 7], [7, 11, 2]]
        let chorus = [[5, 9, 0], [7, 11, 2], [4, 7, 11], [9, 0, 4]].map { $0 + [$0[0] + 2] }
        let bridge = [[2, 5, 9], [7, 11, 2]]
        var rng = SplitMix(seed: 3)
        var chroma: [[Float]] = [], energy: [Float] = []
        func add(_ prog: [[Int]], frames: Int, e: Float) {
            for f in 0..<frames {
                var v = chordVec(prog[(f / 24) % prog.count])
                for q in 0..<12 { v[q] += Float(rng.next() % 1000) / 20000 }
                chroma.append(v); energy.append(e)
            }
        }
        add([[9, 0, 4]], frames: 50, e: 0.2)
        add(verse, frames: 192, e: 0.4); add(chorus, frames: 192, e: 0.8)
        add(verse, frames: 192, e: 0.4); add(chorus, frames: 192, e: 0.8)
        add(bridge, frames: 96, e: 0.5); add(chorus, frames: 192, e: 0.85)
        let secs = ChorusDetector.detect(chroma: chroma, energy: energy)
        let best = try! XCTUnwrap(secs.first)
        let chorusStarts = [24.2, 62.6, 91.4]
        XCTAssertTrue(chorusStarts.contains { abs($0 - best.start) < 1 }, "\(secs)")
        XCTAssertGreaterThanOrEqual(best.repeats, 3)
        XCTAssertTrue(best.label.hasPrefix("副歌"))
    }

    func testSpeedPitch() {
        XCTAssertEqual(SpeedPitch.clampSpeed(1.004), 1.0)
        XCTAssertEqual(SpeedPitch.clampSpeed(0.994), 0.99)
        XCTAssertEqual(SpeedPitch.clampSpeed(9), 4)
        XCTAssertNil(SpeedPitch.filter(semitones: 0, cents: 0))
        XCTAssertEqual(SpeedPitch.ratio(semitones: 12, cents: 0), 2, accuracy: 1e-12)
        XCTAssertEqual(SpeedPitch.ratio(semitones: 0, cents: 100), SpeedPitch.ratio(semitones: 1, cents: 0), accuracy: 1e-12)
        let f = SpeedPitch.filter(semitones: 2, cents: 0)!
        XCTAssertTrue(f.contains("asetrate=53878"), f)   // 48000 × 2^(2/12) = 53877.7
        XCTAssertEqual(SpeedPitch.speedText(1.01), "101%")
        XCTAssertEqual(SpeedPitch.pitchText(semitones: -3, cents: 25), "-3 半音 +25 音分")
    }

    func testLoopSeamFindsContinuousSplice() {
        // 441Hz 正弦：在 A、B 附近各取 ±12ms，找到的接缝跳变应接近正弦的自然相邻差
        let sr = 48000.0
        func win(_ t0: Double) -> [Float] { (0..<1152).map { Float(0.5 * sin(2 * .pi * 441 * (t0 + Double($0) / sr))) } }
        let a = win(2.0131 - 0.012), b = win(2.5 - 0.012)
        let r = LoopSeam.bestSplice(a: a, b: b, channels: 1)!
        XCTAssertLessThan(LoopSeam.seamJump(a: a, b: b, channels: 1, i: r.i, j: r.j), 0.04)
        // 原位置（窗口中心）硬切的跳变大得多
        XCTAssertGreaterThan(LoopSeam.seamJump(a: a, b: b, channels: 1, i: 576, j: 576), 0.1)
    }
}

struct SplitMix { var state: UInt64; init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }


final class VideoLayoutTests: XCTestCase {
    func testFullscreen16x9UsesFullWidthAndOnlyTopBottomLetterbox() {
        // 取证窗口：1710×1073（历史「视频全屏纯净」截图像素 3420×2146 @2x）
        let windowW = 1710.0, windowH = 1073.0, aspect = 16.0 / 9.0
        let pad = VideoLayout.stagePadding(fullscreen: true, compact: false)
        XCTAssertEqual(pad.horizontal, 0, "全屏不应再留 36pt 舞台左右边距")
        XCTAssertEqual(pad.vertical, 0, "全屏不应再留内容上下边距")
        let fit = VideoLayout.fitted(containerWidth: windowW - pad.horizontal * 2,
                                     containerHeight: windowH - pad.vertical * 2,
                                     aspect: aspect)
        XCTAssertEqual(fit.width, windowW, accuracy: 0.5)
        XCTAssertEqual(fit.height, windowW * 9 / 16, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxLeft, 0, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxRight, 0, accuracy: 0.5)
        let remain = windowH - windowW * 9 / 16
        XCTAssertEqual(fit.letterboxTop + fit.letterboxBottom, remain, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxTop, fit.letterboxBottom, accuracy: 0.5)
        XCTAssertEqual(fit.aspect, aspect, accuracy: 1e-9)
    }

    func testFullscreenDoesNotStretchOrCrop() {
        let fit = VideoLayout.fitted(containerWidth: 1920, containerHeight: 1080, aspect: 2.35)
        XCTAssertEqual(fit.aspect, 2.35, accuracy: 1e-9)
        XCTAssertEqual(fit.width, 1920, accuracy: 0.5)
        XCTAssertLessThan(fit.height, 1080)
        XCTAssertEqual(fit.letterboxLeft + fit.letterboxRight, 0, accuracy: 0.5)
    }

    func test4x3On16x9ScreenLettersBoxSidesOnly() {
        let fit = VideoLayout.fitted(containerWidth: 1920, containerHeight: 1080, aspect: 4.0 / 3.0)
        XCTAssertEqual(fit.height, 1080, accuracy: 0.5)
        XCTAssertEqual(fit.width, 1440, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxLeft, 240, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxRight, 240, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxTop, 0, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxBottom, 0, accuracy: 0.5)
    }

    func testWindowedVideoHasNoDecorativeStagePadding() {
        // 原断言 testWindowedKeepsExistingStagePadding 要求窗口态左右 36 / 上下 12 的舞台边距。
        // t249u：窗口态也不再保留装饰性大边距，只按片源比例留黑。
        let regular = VideoLayout.stagePadding(fullscreen: false, compact: false)
        XCTAssertEqual(regular.horizontal, 0, "窗口态不应再留 36pt 舞台左右边距")
        XCTAssertEqual(regular.vertical, 0, "窗口态不应再留内容上下装饰边距")
        let compact = VideoLayout.stagePadding(fullscreen: false, compact: true)
        XCTAssertEqual(compact.horizontal, 0)
        XCTAssertEqual(compact.vertical, 0)
        let full = VideoLayout.stagePadding(fullscreen: true, compact: false)
        XCTAssertEqual(full.horizontal, 0)
        XCTAssertEqual(full.vertical, 0)
    }

    func testWindowedAndFullscreenVideoAreImmersiveInNowPlaying() {
        // 原断言 testImmersiveVideoOnlyWhenFullscreenStage 要求窗口态 videoStage 不是沉浸布局。
        // t249u：窗口态播放视频同样铺满可用区（控制条叠在画面上），与全屏一致；迷你窗、已退出舞台、非正在播放页除外。
        XCTAssertTrue(VideoLayout.isImmersiveVideo(fullscreen: true, videoStageOpen: true, mini: false, nowPlaying: true))
        XCTAssertTrue(VideoLayout.isImmersiveVideo(fullscreen: false, videoStageOpen: true, mini: false, nowPlaying: true))
        XCTAssertFalse(VideoLayout.isImmersiveVideo(fullscreen: true, videoStageOpen: false, mini: false, nowPlaying: true))
        XCTAssertFalse(VideoLayout.isImmersiveVideo(fullscreen: false, videoStageOpen: true, mini: true, nowPlaying: true))
        XCTAssertFalse(VideoLayout.isImmersiveVideo(fullscreen: false, videoStageOpen: true, mini: false, nowPlaying: false))
    }

    func testWindowedVideoHasNoDecorativeFrame() {
        XCTAssertEqual(VideoLayout.stageCornerRadius(fullscreen: false, mini: false), 0)
        XCTAssertEqual(VideoLayout.stageCornerRadius(fullscreen: true, mini: false), 0)
        XCTAssertEqual(VideoLayout.stageCornerRadius(fullscreen: false, mini: true), 14)
        XCTAssertFalse(VideoLayout.showsDecorativeBorder(fullscreen: false, mini: false))
        XCTAssertFalse(VideoLayout.showsDecorativeBorder(fullscreen: true, mini: false))
        XCTAssertTrue(VideoLayout.showsDecorativeBorder(fullscreen: false, mini: true))
    }

    func testVideoStageHidesApplicationHeaderInWindowedAndFullscreen() {
        // 视频主舞台只保留画面、底部控制条和系统三键；曲名/编码、返回、分段、主题图标等应用顶栏都不显示。
        XCTAssertFalse(VideoLayout.showsApplicationHeader(videoStageOpen: true, mini: false, nowPlaying: true))
        XCTAssertFalse(VideoLayout.showsApplicationHeader(videoStageOpen: true, mini: false, nowPlaying: true), "窗口态与全屏共用同一策略")
        XCTAssertFalse(VideoLayout.showsTitleOverlay(videoStageOpen: true, mini: false))
        XCTAssertFalse(VideoLayout.showsTitleOverlay(videoStageOpen: true, mini: true), "迷你窗也不叠曲名编码条，避免再冒出一层头")
    }

    func testApplicationHeaderRemainsForAudioEmptyAndOtherTabs() {
        XCTAssertTrue(VideoLayout.showsApplicationHeader(videoStageOpen: false, mini: false, nowPlaying: true), "音频封面/空工程仍保留顶部导航")
        XCTAssertTrue(VideoLayout.showsApplicationHeader(videoStageOpen: false, mini: false, nowPlaying: false), "播放列表/均衡器页仍保留顶部导航")
        XCTAssertTrue(VideoLayout.showsApplicationHeader(videoStageOpen: true, mini: true, nowPlaying: true), "迷你窗不是本项要改的无头主舞台")
        XCTAssertTrue(VideoLayout.showsPlayChrome(videoStageOpen: true, mini: false, nowPlaying: true), "底部控制条仍属于视频播放窗口")
        XCTAssertTrue(VideoLayout.showsPlayChrome(videoStageOpen: false, mini: false, nowPlaying: true))
        // 片源字幕/烧录时间码不是应用顶栏，策略不得把它们当成 UI 关掉
        XCTAssertFalse(VideoLayout.applicationHeaderIncludesSourceSubtitles)
    }

    func testWindowed16x9FitsContainerWithOnlyAspectLetterbox() {
        let windowW = 1180.0, windowH = 760.0, aspect = 16.0 / 9.0
        let pad = VideoLayout.stagePadding(fullscreen: false, compact: false)
        let fit = VideoLayout.fitted(containerWidth: windowW - pad.horizontal * 2,
                                     containerHeight: windowH - pad.vertical * 2,
                                     aspect: aspect)
        XCTAssertEqual(fit.width, windowW, accuracy: 0.5)
        XCTAssertEqual(fit.height, windowW * 9 / 16, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxLeft, 0, accuracy: 0.5)
        XCTAssertEqual(fit.letterboxRight, 0, accuracy: 0.5)
        XCTAssertEqual(fit.aspect, aspect, accuracy: 1e-9)
        XCTAssertGreaterThan(fit.letterboxTop, 0)
        XCTAssertEqual(fit.letterboxTop, fit.letterboxBottom, accuracy: 0.5)
    }
}

final class LoopScrubTests: XCTestCase {
    func testEditorOpenDragSelectsWithoutOptionKey() {
        let h = LoopScrub.hit(editorOpen: true, optionHeld: false, t0: 20, a: nil, b: nil, duration: 100, grab: 1)
        XCTAssertEqual(h, .select(origin: 20))
    }

    func testEditorOpenStillSelectsWithOptionKey() {
        let h = LoopScrub.hit(editorOpen: true, optionHeld: true, t0: 8, a: nil, b: nil, duration: 100, grab: 1)
        XCTAssertEqual(h, .select(origin: 8))
    }

    func testEditorClosedDragStillSeeks() {
        let h = LoopScrub.hit(editorOpen: false, optionHeld: false, t0: 20, a: 10, b: 30, duration: 100, grab: 1)
        XCTAssertEqual(h, .seek)
        let withOpt = LoopScrub.hit(editorOpen: false, optionHeld: true, t0: 20, a: 10, b: 30, duration: 100, grab: 1)
        XCTAssertEqual(withOpt, .seek)
    }

    func testExistingHandlesStillDraggableWhenEditorOpen() {
        let a = LoopScrub.hit(editorOpen: true, optionHeld: false, t0: 10.2, a: 10, b: 30, duration: 100, grab: 1)
        let b = LoopScrub.hit(editorOpen: true, optionHeld: false, t0: 29.6, a: 10, b: 30, duration: 100, grab: 1)
        XCTAssertEqual(a, .handleA)
        XCTAssertEqual(b, .handleB)
    }

    func testTinyDragDoesNotCommit() {
        XCTAssertNil(LoopScrub.commit(start: 10, end: 10.05, duration: 100))
        XCTAssertEqual(LoopScrub.commit(start: 18, end: 12, duration: 100)!.0, 12, accuracy: 1e-9)
        XCTAssertEqual(LoopScrub.commit(start: 18, end: 12, duration: 100)!.1, 18, accuracy: 1e-9)
    }

    func testLoopKeepsOriginalDurationAndTimeline() {
        XCTAssertEqual(LoopScrub.displayedDuration(original: 240, loop: (12, 18)), 240)
        let f = LoopScrub.progressFraction(position: 15, duration: 100, loop: (10, 20))
        XCTAssertEqual(f, 0.15, accuracy: 1e-9)
        XCTAssertNotEqual(f, (15.0 - 10.0) / (20.0 - 10.0))
    }

    func testCursorIndicatesSelectOnlyInEditor() {
        XCTAssertTrue(LoopScrub.cursorIndicatesSelect(true))
        XCTAssertFalse(LoopScrub.cursorIndicatesSelect(false))
    }

    func testRangeColorDiffersFromLiuliAndZhuqingAccents() {
        func dist(_ a: (Double, Double, Double), _ r: Double, _ g: Double, _ b: Double) -> Double {
            let dr = a.0 - r, dg = a.1 - g, db = a.2 - b
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
        // 琉璃强调 栀子黄 #EBB10D；朱青强调 大红 #FF2121
        let liuli = LoopScrub.rangeRGB(accentR: 0xEB / 255.0, accentG: 0xB1 / 255.0, accentB: 0x0D / 255.0)
        let zhu = LoopScrub.rangeRGB(accentR: 1, accentG: 0x21 / 255.0, accentB: 0x21 / 255.0)
        XCTAssertGreaterThan(dist(liuli, 0xEB / 255.0, 0xB1 / 255.0, 0x0D / 255.0), 0.4)
        XCTAssertGreaterThan(dist(zhu, 1, 0x21 / 255.0, 0x21 / 255.0), 0.4)
    }
}

final class AutoEqTests: XCTestCase {
    func testFilterStaysUnderFFmpegEntryLimit() {
        let pts = (0..<127).map { i in EQPreset.Point(20 * pow(1000, Double(i) / 126), -Double(i % 10)) }
        let c = AutoEq.Curve(points: pts)
        let f = AutoEq.filter(c)
        XCTAssertEqual(f.components(separatedBy: "entry(").count - 1, AutoEq.maxEntries)
        XCTAssertTrue(f.hasPrefix("@tancoautoeq:lavfi=[volume=0dB:precision=float,firequalizer="), f)
    }
}

final class ASRCleanupTests: XCTestCase {
    func testRemovesHallucinatedCreditsAndRepeats() {
        var srt = "1\n00:00:00,000 --> 00:00:02,000\n第一方面就是我们空间站\n\n"
        for i in 0..<6 { srt += "\(i + 2)\n00:00:\(10 + i * 2),000 --> 00:00:\(11 + i * 2),000\n中文字幕:YK\n\n" }
        srt += "9\n00:01:00,000 --> 00:01:02,000\n好\n\n10\n00:01:02,000 --> 00:01:03,000\n好\n\n11\n00:01:03,000 --> 00:01:04,000\n好\n\n12\n00:01:04,000 --> 00:01:05,000\n请不吝点赞 订阅 转发 打赏支持明镜与点点栏目\n"
        let (out, removed) = ASRCleanup.cleanSRT(srt)
        XCTAssertEqual(removed, 8)
        XCTAssertTrue(out.contains("第一方面"))
        XCTAssertFalse(out.contains("YK"))
        XCTAssertEqual(out.components(separatedBy: "-->").count - 1, 3)
    }
}

final class LyricsLookupTests: XCTestCase {
    let synced = "[00:01.00]第一句\n[00:05.00]第二句"
    func testPicksMatchingSyncedRecordByDuration() {
        let recs = [
            LRCLibRecord(id: 1, trackName: "晴天", artistName: "周杰伦", duration: 299, syncedLyrics: synced),           // Live 版，时长不对
            LRCLibRecord(id: 2, trackName: "晴天", artistName: "周杰伦", duration: 270, syncedLyrics: nil),              // 没有时间轴
            LRCLibRecord(id: 3, trackName: "晴天 (Live)", artistName: "周杰伦", duration: 269.5, syncedLyrics: synced),
            LRCLibRecord(id: 4, trackName: "晴天", artistName: "周杰伦", duration: 270, instrumental: true, syncedLyrics: synced),
            LRCLibRecord(id: 5, trackName: "晴天", artistName: "周杰倫 Jay Chou", duration: 271, syncedLyrics: synced),
        ]
        XCTAssertEqual(LyricsLookup.pick(recs, title: "03. 晴天", artist: "周杰伦", duration: 270)?.id, 3)
    }
    func testRejectsWrongArtistOrMissingInfo() {
        let recs = [LRCLibRecord(id: 1, trackName: "晚风", artistName: "别人", duration: 200, syncedLyrics: synced)]
        XCTAssertNil(LyricsLookup.pick(recs, title: "晚风", artist: "陈默", duration: 200))
        XCTAssertNil(LyricsLookup.pick(recs, title: "晚风", artist: nil, duration: nil), "歌手和时长都不知道时不猜")
        XCTAssertEqual(LyricsLookup.pick(recs, title: "晚风", artist: "未知艺人", duration: 201)?.id, 1)
        XCTAssertNil(LyricsLookup.pick(recs, title: "晚风", artist: "未知艺人", duration: 203), "不知道歌手时时长要更准")
    }
    func testNormalizeAndKey() {
        XCTAssertEqual(LyricsLookup.normalize("Hello, World (Remastered 2011)"), "helloworld")
        XCTAssertEqual(LyricsLookup.cleanTitle("01 - 潮汐"), "潮汐")
        XCTAssertEqual(LyricsLookup.cacheKey(title: "晴天", artist: "周杰伦", duration: 270.2), LyricsLookup.cacheKey(title: "01. 晴天", artist: "周杰伦", duration: 269.8))
    }
}

final class ScanMathTests: XCTestCase {
    func testRateGrowsWithHold() {
        XCTAssertEqual(ScanMath.rate(held: 0.5), 2)
        XCTAssertEqual(ScanMath.rate(held: 2), 4)
        XCTAssertEqual(ScanMath.rate(held: 3), 8)
        XCTAssertEqual(ScanMath.rate(held: 5), 16)
        XCTAssertEqual(ScanMath.rate(held: 9), 32)
    }
    func testFadeStepsAreEvenInGain() {
        let v = ScanMath.fadeVolumes(from: 100, to: 0, steps: 12)
        XCTAssertEqual(v.count, 12)
        XCTAssertEqual(v.last!, 0, accuracy: 1e-9)
        var prev = 1.0
        for x in v { let g = pow(x / 100, 3); XCTAssertEqual(prev - g, 1.0 / 12, accuracy: 1e-9); prev = g }
        XCTAssertEqual(ScanMath.fadeVolumes(from: 0, to: 80, steps: 4).last!, 80, accuracy: 1e-9)
    }
    func testClamp() {
        XCTAssertEqual(ScanMath.clamp(-3, duration: 100), 0)
        XCTAssertEqual(ScanMath.clamp(120, duration: 100), 99.5)
    }
}

final class CoverLookupTests: XCTestCase {
    func testFoldTraditionalSimplified() {
        XCTAssertEqual(CoverLookup.fold("葉惠美"), CoverLookup.fold("叶惠美"))
        XCTAssertEqual(CoverLookup.fold("周杰倫"), CoverLookup.fold("周杰伦"))
        XCTAssertEqual(CoverLookup.fold("The Beatles"), CoverLookup.fold("beatles"))
    }
    func testReleaseGroupPick() {
        let q = CoverQuery(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 270)
        let gs = [MBReleaseGroup(id: "live", title: "2004無與倫比演唱會", primaryType: "Album", secondaryTypes: ["Live"], artistCredit: [MBArtistCredit(name: "周杰倫")]),
                  MBReleaseGroup(id: "yhm", title: "葉惠美", primaryType: "Album", artistCredit: [MBArtistCredit(name: "周杰倫")]),
                  MBReleaseGroup(id: "other", title: "葉惠美", primaryType: "Album", artistCredit: [MBArtistCredit(name: "Someone Else")])]
        XCTAssertEqual(CoverLookup.pickReleaseGroups(gs, query: q), ["yhm"])
    }
    func testRecordingPickStrict() {
        let rel = { (id: String, t: String, sec: [String]?) in MBRelease(id: id, title: t, status: "Official", releaseGroup: MBReleaseGroupRef(id: id, title: t, primaryType: "Album", secondaryTypes: sec)) }
        let recs = [MBRecording(title: "Yellow", length: 269_000, artistCredit: [MBArtistCredit(name: "Coldplay")], releases: [rel("para", "Parachutes", nil), rel("comp", "Hits", ["Compilation"])]),
                    MBRecording(title: "Yellow (Live)", length: 411_000, artistCredit: [MBArtistCredit(name: "Coldplay")], releases: [rel("live", "Live 2012", ["Live"])])]
        XCTAssertEqual(CoverLookup.pickFromRecordings(recs, query: CoverQuery(title: "Yellow", artist: "Coldplay", album: nil, duration: 269.2)), ["para"])
        // 时长对不上：不认
        XCTAssertEqual(CoverLookup.pickFromRecordings(recs, query: CoverQuery(title: "Yellow", artist: "Coldplay", album: nil, duration: 60)), [])
        // 没有歌手：不查
        XCTAssertEqual(CoverLookup.pickFromRecordings(recs, query: CoverQuery(title: "Yellow", artist: nil, album: nil, duration: 269)), [])
    }
    func testITunesPick() {
        let ts = [ITunesTrack(trackName: "晴天 (Live)", artistName: "周杰倫", collectionName: "2004 無與倫比演唱會 (Live)", trackTimeMillis: 299_360, artworkUrl100: "a/100x100bb.jpg"),
                  ITunesTrack(trackName: "晴天", artistName: "周杰倫", collectionName: "葉惠美", trackTimeMillis: 269_747, artworkUrl100: "b/100x100bb.jpg"),
                  ITunesTrack(trackName: "晴天 (鋼琴版)", artistName: "CIP Music", collectionName: "周杰倫鋼琴曲集", trackTimeMillis: 267_315, artworkUrl100: "c/100x100bb.jpg")]
        XCTAssertEqual(CoverLookup.pickITunes(ts, query: CoverQuery(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 270))?.collectionName, "葉惠美")
        XCTAssertNil(CoverLookup.pickITunes(ts, query: CoverQuery(title: "晴天", artist: "周杰伦", album: nil, duration: 60)))
        XCTAssertEqual(CoverLookup.largeArtwork("b/100x100bb.jpg"), "b/10000x10000bb.jpg")
        XCTAssertEqual(CoverLookup.iTunesCountries(for: CoverQuery(title: "晴天", artist: "周杰伦", album: nil, duration: nil)).first, "tw")
    }
    func testRefetchClearsOnlyUserDefaultWhenRestoringOfficialCover() {
        XCTAssertEqual(CoverRefetch.cacheClear(userDefaultExists: true), .userDefaultOnly)
        XCTAssertEqual(CoverRefetch.cacheClear(userDefaultExists: false), .all)
    }
    func testAlbumTracksShareCacheKeyButUntaggedTestToneDoesNot() {
        let tagged = CoverLookup.cacheKey(CoverQuery(title: "以父之名", artist: "周杰伦", album: "叶惠美", duration: 341))
        let tagged2 = CoverLookup.cacheKey(CoverQuery(title: "晴天", artist: "周杰伦", album: "葉惠美", duration: 270))
        let tone = CoverLookup.cacheKey(CoverQuery(title: "晴天（自测音轨）", artist: "周杰伦", album: nil, duration: 0))
        XCTAssertEqual(tagged, tagged2)
        XCTAssertNotEqual(tagged, tone)
    }
}

final class ViewerFrostTests: XCTestCase {
    func testGrade86IsLinearInterpolationOf80And90NotAPIPercent() {
        // 档名 86 是相对柔和强度，不是模糊 API / 透明度百分数。
        XCTAssertEqual(ViewerFrost.grade, 86)
        XCTAssertEqual(ViewerFrost.blurRadiusAtDesign, 80 + 0.6 * (160 - 80), accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.blurRadiusAtDesign, 128, accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veilBase, 0.13 + 0.6 * (0.18 - 0.13), accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veilBase, 0.16, accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veilBreath, 0.02, accuracy: 1e-12)
        XCTAssertGreaterThan(ViewerFrost.blurRadiusAtDesign, 16)
        XCTAssertGreaterThan(ViewerFrost.veilBase, 0.10)
    }

    func testBlurRadiusScalesWithWidth() {
        XCTAssertEqual(ViewerFrost.blurRadius(forWidth: 1920), 128, accuracy: 1e-9)
        XCTAssertEqual(ViewerFrost.blurRadius(forWidth: 960), 64, accuracy: 1e-9)
        XCTAssertEqual(ViewerFrost.blurRadius(forWidth: 0), 0, accuracy: 1e-12)
    }

    func testLayoutMatchesFrozenSchemeAAt1920x1080() {
        let L = ViewerFrost.layout(inWidth: 1920, height: 1080)
        XCTAssertEqual(L.scale, 1, accuracy: 1e-12)
        XCTAssertEqual(L.cover.x, 1572, accuracy: 1e-9)
        XCTAssertEqual(L.cover.y, 682, accuracy: 1e-9)
        XCTAssertEqual(L.cover.size, 300, accuracy: 1e-9)
        XCTAssertEqual(L.title.x, 64, accuracy: 1e-9)
        XCTAssertEqual(L.title.y, 735, accuracy: 1e-9)
        XCTAssertEqual(L.titleSize, 72, accuracy: 1e-9)
        XCTAssertEqual(L.artist.x, 64, accuracy: 1e-9)
        XCTAssertEqual(L.artist.y, 825, accuracy: 1e-9)
        XCTAssertEqual(L.artistSize, 30, accuracy: 1e-9)
        XCTAssertEqual(L.album.x, 64, accuracy: 1e-9)
        XCTAssertEqual(L.album.y, 867, accuracy: 1e-9)
        XCTAssertEqual(L.albumSize, 22, accuracy: 1e-9)
        XCTAssertEqual(L.controls.x, 64, accuracy: 1e-9)
        XCTAssertEqual(L.controls.y, 907, accuracy: 1e-9)
        XCTAssertEqual(L.icon, 44, accuracy: 1e-9)
        XCTAssertEqual(L.progress.x, 64, accuracy: 1e-9)
        XCTAssertEqual(L.progress.y, 979, accuracy: 1e-9)
        XCTAssertEqual(L.progress.width, 1450, accuracy: 1e-9)
        XCTAssertEqual(L.progressThickness, 3, accuracy: 1e-9)
        // 播放进度条底边与右侧专辑底边严格齐平
        XCTAssertEqual(L.progress.y + L.progressThickness, L.cover.y + L.cover.size, accuracy: 1e-9)
        XCTAssertEqual(L.washHeight, 360, accuracy: 1e-9)
        XCTAssertEqual(L.controlRow.x, 64, accuracy: 1e-9)
        XCTAssertEqual(L.controlRow.y, 907, accuracy: 1e-9)
        XCTAssertEqual(L.controlRow.width, 286, accuracy: 1e-9)
        XCTAssertEqual(L.controlRow.height, 58, accuracy: 1e-9)
        XCTAssertEqual(L.controlRow.maxX, 350, accuracy: 1e-9)
        XCTAssertEqual(L.controlRow.maxY, 965, accuracy: 1e-9)
        XCTAssertEqual(L.coverCornerRadius, 300 * (0.085 * 0.62 / 0.91), accuracy: 1e-9)
        XCTAssertFalse(ViewerFrost.rectsOverlap(L.controlRow, (L.cover.x, L.cover.y, L.cover.size, L.cover.size)))
        XCTAssertFalse(ViewerFrost.rectsOverlap((L.progress.x, L.progress.y - 6, L.progress.width, L.progressThickness + 14), (L.cover.x, L.cover.y, L.cover.size, L.cover.size)))
    }

    func testLayoutUniformScaleBottomAlignedAndCoverStaysSquare() {
        let L = ViewerFrost.layout(inWidth: 960, height: 540)
        XCTAssertEqual(L.scale, 0.5, accuracy: 1e-12)
        XCTAssertEqual(L.cover.size, 150, accuracy: 1e-9)
        XCTAssertEqual(L.cover.x, 786, accuracy: 1e-9)
        XCTAssertEqual(L.cover.y, 341, accuracy: 1e-9)
        let tall = ViewerFrost.layout(inWidth: 1920, height: 1200)
        XCTAssertEqual(tall.scale, 1, accuracy: 1e-12)
        XCTAssertEqual(tall.originY, 120, accuracy: 1e-9)
        XCTAssertEqual(tall.cover.size, 300, accuracy: 1e-9)
        XCTAssertEqual(tall.cover.x, 1572, accuracy: 1e-9)
        XCTAssertEqual(tall.cover.y, 120 + 682, accuracy: 1e-9)
        let wide = ViewerFrost.layout(inWidth: 2560, height: 1080)
        XCTAssertEqual(wide.scale, 1, accuracy: 1e-12)
        XCTAssertEqual(wide.cover.x, 320 + 1572, accuracy: 1e-9)
        XCTAssertEqual(wide.cover.y, 682, accuracy: 1e-9)
    }

    func testBreathFreezesWhenPausedOrReduceMotion() {
        let t = 4.5
        let moving = ViewerFrost.veil(time: t, playing: true, reduceMotion: false)
        XCTAssertGreaterThan(moving, ViewerFrost.veilBase)
        XCTAssertLessThanOrEqual(moving, ViewerFrost.veilBase + ViewerFrost.veilBreath + 1e-12)
        XCTAssertEqual(ViewerFrost.veil(time: t, playing: false, reduceMotion: false), ViewerFrost.veilBase, accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veil(time: t, playing: true, reduceMotion: true), ViewerFrost.veilBase, accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veil(time: 0, playing: true, reduceMotion: false), ViewerFrost.veilBase, accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veil(time: 9, playing: true, reduceMotion: false), ViewerFrost.veilBase + ViewerFrost.veilBreath, accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veil(time: 18, playing: true, reduceMotion: false), ViewerFrost.veilBase, accuracy: 1e-12)
    }

    func testContentBoxTrimsNearBlackSideColumnsOnly() {
        let means: [Double] = [4, 3, 80, 90, 100, 70, 2, 1].map { $0 / 255.0 }
        let box = ViewerFrost.contentBox(columnMeans: means, threshold: 8.0 / 255.0)
        XCTAssertEqual(box.x, 2)
        XCTAssertEqual(box.width, 4)
    }

    func testFallbackUsesExistingThemePaletteAndNotFollowCoverNil() {
        let liuli = ViewerFrost.fallbackPalette(theme: .liuli, systemDark: true)
        XCTAssertEqual(liuli.primary.hex, "#1C223B")
        XCTAssertEqual(liuli.accent.hex, "#EBB10D")
        let white = ViewerFrost.fallbackPalette(theme: .white, systemDark: true)
        XCTAssertEqual(white.primary.hex, "#E6E7EB")
        let systemDark = ViewerFrost.fallbackPalette(theme: .system, systemDark: true)
        XCTAssertEqual(systemDark.primary.hex, AppTheme.black.palette!.primary.hex)
        let systemLight = ViewerFrost.fallbackPalette(theme: .system, systemDark: false)
        XCTAssertEqual(systemLight.primary.hex, AppTheme.white.palette!.primary.hex)
        let follow = ViewerFrost.fallbackPalette(theme: .followCover, systemDark: true, coverPalette: nil)
        XCTAssertEqual(follow.primary.hex, AmbientPalette.fallback.primary.hex)
        XCTAssertTrue(ViewerFrost.usesThemeFallbackBackground(isDefaultCover: true, hasCoverImage: true))
        XCTAssertTrue(ViewerFrost.usesThemeFallbackBackground(isDefaultCover: false, hasCoverImage: false))
        XCTAssertFalse(ViewerFrost.usesThemeFallbackBackground(isDefaultCover: false, hasCoverImage: true))
    }

    func testForegroundChromeStaysOnscreenForWindowedAndFullscreenSizes() {
        // 86 参数不得被「适配窗口」改掉。
        XCTAssertEqual(ViewerFrost.blurRadiusAtDesign, 128, accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veilBase, 0.16, accuracy: 1e-12)
        XCTAssertEqual(ViewerFrost.veilBreath, 0.02, accuracy: 1e-12)
        let sizes: [(String, Double, Double)] = [
            ("design", 1920, 1080),
            ("test-window", 1180, 760),
            ("min-window", 760, 520),
            ("half-hd", 1280, 800),
            ("mbp14-full", 1512, 982),
            ("mbp16-full", 1728, 1117),
            ("1080p", 1920, 1080),
            ("tall", 1180, 1200),
            ("wide", 2560, 1080),
        ]
        for (name, w, h) in sizes {
            let L = ViewerFrost.layout(inWidth: w, height: h)
            let off = ViewerFrost.offscreenForeground(L, inWidth: w, height: h)
            XCTAssertTrue(off.isEmpty, "\(name) \(Int(w))×\(Int(h)) 越界: \(off.map { "\($0.name) (\($0.x),\($0.y),\($0.width),\($0.height))" }.joined(separator: "; "))")
            let play = ViewerFrost.playButtonCenter(L)
            XCTAssertTrue(play.x > 0 && play.x < w && play.y > 0 && play.y < h, "\(name) 播放键中心 (\(play.x), \(play.y)) 不在窗内")
            let hit = ViewerFrost.progressHitHeight(L, windowHeight: h)
            XCTAssertGreaterThan(hit, 0, "\(name) 进度可点高度为 0")
            XCTAssertLessThanOrEqual(L.progress.y + hit, h + 0.51, "\(name) 进度可点区域伸出下沿")
        }
        // 1920×1080 仍用完整 22pt 可点高度，设计坐标不变。
        let D = ViewerFrost.layout(inWidth: 1920, height: 1080)
        XCTAssertEqual(ViewerFrost.progressHitHeight(D, windowHeight: 1080), 22, accuracy: 1e-9)
        XCTAssertEqual(D.progress.y, 979, accuracy: 1e-9)
        XCTAssertEqual(D.controlRow.y, 907, accuracy: 1e-9)
    }
}
