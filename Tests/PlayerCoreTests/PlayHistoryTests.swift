// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import XCTest
@testable import PlayerCore

final class PlayHistoryTests: XCTestCase {

    private func item(_ name: String, title: String? = nil, artist: String? = nil) -> (URL, String, String?) {
        let url = URL(fileURLWithPath: "/tmp/tanco-history/\(name).flac")
        return (url, title ?? name, artist)
    }

    func testRecordMovesExistingToFrontAndDedupes() {
        var book = PlayHistoryBook()
        let a = item("a", title: "晴天", artist: "周杰伦")
        let b = item("b", title: "晚风")
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let t2 = Date(timeIntervalSince1970: 3_000)
        book.record(url: a.0, title: a.1, artist: a.2, at: t0)
        book.record(url: b.0, title: b.1, artist: b.2, at: t1)
        book.record(url: a.0, title: a.1, artist: a.2, at: t2)
        XCTAssertEqual(book.items.map(\.path), [PlayHistoryBook.key(for: a.0), PlayHistoryBook.key(for: b.0)])
        XCTAssertEqual(book.items[0].playedAt, t2)
        XCTAssertEqual(book.items[0].title, "晴天")
        XCTAssertEqual(book.items.count, 2)
    }

    func testRecordDropsOldestWhenOverLimit() {
        var book = PlayHistoryBook()
        for i in 0..<(PlayHistoryBook.limit + 5) {
            let url = URL(fileURLWithPath: "/tmp/tanco-history/\(i).mp3")
            book.record(url: url, title: "t\(i)", artist: nil, at: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        XCTAssertEqual(book.items.count, PlayHistoryBook.limit)
        XCTAssertEqual(book.items.first?.title, "t\(PlayHistoryBook.limit + 4)")
        XCTAssertEqual(book.items.last?.title, "t5")
        XCTAssertFalse(book.items.contains { $0.title == "t0" })
    }

    func testClearEmptiesOnlyHistoryBook() {
        var book = PlayHistoryBook()
        let a = item("keep-file")
        book.record(url: a.0, title: a.1, artist: nil)
        book.clear()
        XCTAssertTrue(book.items.isEmpty)
        book.clear()
        XCTAssertTrue(book.items.isEmpty)
    }

    func testRoundTripDoesNotImplyQueueRestore() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t251u-history-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent(PlayHistoryStore.fileName)
        defer { try? FileManager.default.removeItem(at: dir) }
        var book = PlayHistoryBook()
        book.record(url: URL(fileURLWithPath: "/tmp/song.flac"), title: "雾中灯", artist: "Aurora Lane")
        try! PlayHistoryStore.save(book, to: url)
        let loaded = PlayHistoryStore.load(from: url)
        XCTAssertEqual(loaded, book)
        // 启动策略只处理会话，不会把历史写进队列
        var session = SessionState()
        session.volume = 75
        session.muted = false
        _ = session.queue.append([MediaItem(url: URL(fileURLWithPath: "/tmp/old.mp3"))])
        session.queue.select(0)
        session.lastPosition = 12
        let prepared = LaunchPolicy.preparedSession(from: session)
        // 2026-11-23 起启动时恢复播放列表（不自动播放），但播放记录仍然不会被写进队列
        XCTAssertEqual(prepared.queue.items.map(\.url.path), ["/tmp/old.mp3"])
        XCTAssertEqual(prepared.queue.currentIndex, 0)
        XCTAssertEqual(prepared.lastPosition, 0)
        XCTAssertEqual(prepared.volume, 75)
        XCTAssertEqual(loaded.items.count, 1, "会话清空不得影响已经存盘的历史")
    }

    func testLoadMissingFileReturnsEmptyAndDoesNotThrow() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-play-history-\(UUID().uuidString).json")
        XCTAssertTrue(PlayHistoryStore.load(from: url).items.isEmpty)
    }

    func testEmptyProjectKeepsHeaderAndPlayBar() {
        // 空工程保留顶栏与播放条；文案是否为空由界面层处理，不在这里拆掉布局。
        XCTAssertTrue(EmptyProjectLayout.showsApplicationHeader(queueIsEmpty: true, videoStageOpen: false, mini: false, nowPlaying: true))
        XCTAssertTrue(EmptyProjectLayout.showsPlayChrome(queueIsEmpty: true, videoStageOpen: false, mini: false, nowPlaying: true))
        // 有队列时，仍沿用视频舞台的顶栏策略
        XCTAssertTrue(EmptyProjectLayout.showsApplicationHeader(queueIsEmpty: false, videoStageOpen: false, mini: false, nowPlaying: true))
        XCTAssertFalse(EmptyProjectLayout.showsApplicationHeader(queueIsEmpty: false, videoStageOpen: true, mini: false, nowPlaying: true))
        XCTAssertTrue(EmptyProjectLayout.showsPlayChrome(queueIsEmpty: false, videoStageOpen: true, mini: false, nowPlaying: true))
    }
}
