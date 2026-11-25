// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one
    public var next: RepeatMode { self == .off ? .all : (self == .all ? .one : .off) }
    public var label: String { self == .off ? "不循环" : (self == .all ? "列表循环" : "单曲循环") }
}

/// 播放队列：顺序 / 随机 / 循环逻辑都在这里，UI 与引擎只问“下一首是谁”。
public struct PlayQueue: Codable, Equatable, Sendable {
    public private(set) var items: [MediaItem] = []
    /// 当前项在 items 里的下标
    public private(set) var currentIndex: Int?
    public var repeatMode: RepeatMode = .all
    public private(set) var shuffle = false
    /// 随机模式下的播放顺序（items 下标）
    private var order: [Int] = []
    private var seed: UInt64 = 0x9E3779B97F4A7C15

    public init() {}

    public var current: MediaItem? { currentIndex.map { items[$0] } }
    public var isEmpty: Bool { items.isEmpty }

    public mutating func replace(with newItems: [MediaItem], startAt index: Int = 0) {
        items = newItems
        currentIndex = newItems.isEmpty ? nil : min(max(0, index), newItems.count - 1)
        rebuildOrder()
    }

    /// 追加，返回第一首新加入项的下标。去重（同一路径不重复添加）。
    @discardableResult
    public mutating func append(_ newItems: [MediaItem]) -> Int? {
        let existing = Set(items.map(\.id))
        let fresh = newItems.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return newItems.first.flatMap { n in items.firstIndex { $0.id == n.id } } }
        let first = items.count
        items.append(contentsOf: fresh)
        if currentIndex == nil { currentIndex = first }
        rebuildOrder()
        return first
    }

    public mutating func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        // 随机模式下保持既定顺序（否则每切一首都重洗，会重复/漏播）
    }

    public mutating func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if let c = currentIndex {
            if items.isEmpty { currentIndex = nil }
            else if index < c { currentIndex = c - 1 }
            else if index == c { currentIndex = min(c, items.count - 1) }
        }
        rebuildOrder()
    }

    public mutating func move(from: Int, to: Int) {
        guard items.indices.contains(from), to >= 0, to <= items.count else { return }
        let curID = current?.id
        let it = items.remove(at: from)
        items.insert(it, at: to > from ? to - 1 : to)
        currentIndex = curID.flatMap { id in items.firstIndex { $0.id == id } }
        rebuildOrder()
    }

    /// 插入到指定位置（拖入播放列表某一行之间、“下一首播放”都走这里）。
    /// 已在列表里的同一路径会被挪到插入点，而不是重复出现。返回第一首插入项的新下标。
    @discardableResult
    public mutating func insert(_ newItems: [MediaItem], at index: Int) -> Int? {
        guard !newItems.isEmpty else { return nil }
        let curID = current?.id
        var seen = Set<String>()
        let unique = newItems.filter { seen.insert($0.id).inserted }
        let ids = Set(unique.map(\.id))
        var at = min(max(0, index), items.count)
        // 先把已存在的同路径项移走（并修正插入点）
        var i = 0
        while i < items.count {
            if ids.contains(items[i].id) {
                // 正在播放的那一首被“插入”到别处时保留原对象（有完整元数据）
                items.remove(at: i)
                if i < at { at -= 1 }
            } else { i += 1 }
        }
        items.insert(contentsOf: unique, at: at)
        if let id = curID { currentIndex = items.firstIndex { $0.id == id } } else { currentIndex = at }
        rebuildOrder()
        return at
    }

    /// 排序，正在播放的那一首保持为当前。
    public mutating func sort(by areInIncreasingOrder: (MediaItem, MediaItem) -> Bool) {
        let curID = current?.id
        items.sort(by: areInIncreasingOrder)
        currentIndex = curID.flatMap { id in items.firstIndex { $0.id == id } }
        rebuildOrder()
    }

    public mutating func reverse() {
        let curID = current?.id
        items.reverse()
        currentIndex = curID.flatMap { id in items.firstIndex { $0.id == id } }
        rebuildOrder()
    }

    /// 把列表本身随机打乱（不同于“随机播放”模式：这里真的改变了顺序）。
    public mutating func scramble(seed s0: UInt64) {
        let curID = current?.id
        var s = s0 | 1
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            items.swapAt(i, Int(s % UInt64(i + 1)))
        }
        currentIndex = curID.flatMap { id in items.firstIndex { $0.id == id } }
        rebuildOrder()
    }

    public mutating func update(_ item: MediaItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
    }

    public mutating func setShuffle(_ on: Bool) {
        shuffle = on
        rebuildOrder()
    }

    /// 自动播完后的下一首（考虑单曲循环）；手动“下一首”时 manual = true（单曲循环也会跳）。
    public func nextIndex(manual: Bool) -> Int? {
        guard let c = currentIndex, !items.isEmpty else { return nil }
        if repeatMode == .one && !manual { return c }
        let seq = sequence
        guard let pos = seq.firstIndex(of: c) else { return nil }
        if pos + 1 < seq.count { return seq[pos + 1] }
        return repeatMode == .off ? nil : seq.first
    }

    public func previousIndex() -> Int? {
        guard let c = currentIndex, !items.isEmpty else { return nil }
        let seq = sequence
        guard let pos = seq.firstIndex(of: c) else { return nil }
        if pos > 0 { return seq[pos - 1] }
        return repeatMode == .off ? c : seq.last
    }

    var sequence: [Int] { shuffle ? order : Array(items.indices) }

    private mutating func rebuildOrder() {
        guard shuffle, !items.isEmpty else { order = []; return }
        var rest = Array(items.indices)
        if let c = currentIndex { rest.removeAll { $0 == c } }
        // 可复现的洗牌（xorshift），避免 SystemRandomNumberGenerator 在测试里不可控
        var s = seed &+ UInt64(items.count) &* 0x2545F4914F6CDD1D
        for i in stride(from: rest.count - 1, to: 0, by: -1) {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            let j = Int(s % UInt64(i + 1))
            rest.swapAt(i, j)
        }
        order = (currentIndex.map { [$0] } ?? []) + rest
        seed = s
    }
}
