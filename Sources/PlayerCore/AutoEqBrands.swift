// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 耳机校正的「按品牌找」（TANCO 2026-11-23）：先按品牌首字母分组列品牌（常用大牌在最前，右侧 A–Z 索引跳转），
/// 点进品牌再列这个品牌下的型号。品牌名从型号名开头取：一般是第一个词；
/// 第二个词是 Audio / Ears / Acoustics… 这类品牌后缀，或者是「&」「of」「by」连接词时，连起来算一个品牌（如 64 Audio、Bang & Olufsen、Dan Clark Audio）。
public extension AutoEq {
    static let brandSuffixes: Set<String> = ["audio", "acoustics", "acoustic", "ears", "gaming", "lab", "labs", "technology", "electronics",
                                              "hifi", "hi-fi", "melody", "beach", "project", "planar", "tune", "rhyme", "torino", "mirai",
                                              "tres", "art", "oblivion", "wold", "clark"]
    static let brandJoiners: Set<String> = ["&", "of", "by", "+"]

    /// 常用大牌（有数据的才显示），排在最前
    static let majorBrands = ["Apple", "Sony", "Sennheiser", "Bose", "Beats", "Samsung", "AKG", "Audio-Technica", "Beyerdynamic",
                              "Shure", "JBL", "HIFIMAN", "Moondrop", "Focal", "Bang & Olufsen", "Bowers & Wilkins", "Jabra",
                              "Huawei", "Xiaomi", "Google Pixel", "Grado", "Audeze"]

    static func brand(of name: String) -> String {
        let w = name.split(separator: " ").map(String.init)
        guard let first = w.first else { return name }
        var n = 1
        while n < w.count {
            let next = w[n].lowercased()
            if brandJoiners.contains(next), n + 1 < w.count { n += 2; continue }
            if brandSuffixes.contains(next) { n += 1; continue }
            break
        }
        // 整个名字都被当成品牌（如「Fir Audio」本身）时，至少给型号留一个词
        if n >= w.count, w.count > 1 { n = w.count - 1 }
        return n == 1 ? first : w[0..<n].joined(separator: " ")
    }

    /// 首字母分组用的键：A–Z，数字和其他归「#」
    static func letter(of brand: String) -> String {
        guard let c = brand.uppercased().unicodeScalars.first else { return "#" }
        return (c.value >= 65 && c.value <= 90) ? String(Character(c)) : "#"
    }

    struct BrandIndex: Equatable, Sendable {
        public struct Brand: Equatable, Hashable, Identifiable, Sendable {
            public var name: String
            public var count: Int
            public var id: String { name.lowercased() }
        }
        public var major: [Brand]
        public var sections: [(letter: String, brands: [Brand])]
        public var letters: [String] { sections.map(\.letter) }
        public static func == (a: Self, b: Self) -> Bool { a.major == b.major && a.letters == b.letters && a.sections.map(\.brands) == b.sections.map(\.brands) }
    }

    /// 品牌目录：同一品牌不分大小写合并，显示用出现最多的写法
    static func brandIndex(_ entries: [Entry]) -> BrandIndex {
        var spell: [String: [String: Int]] = [:]
        var models: [String: Set<String>] = [:]
        for e in entries {
            let b = brand(of: e.name), k = b.lowercased()
            spell[k, default: [:]][b, default: 0] += 1
            models[k, default: []].insert(e.name)
        }
        var all: [BrandIndex.Brand] = []
        for (k, s) in spell {
            let name = s.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }!.key
            all.append(.init(name: name, count: models[k]?.count ?? 0))
        }
        let byKey = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let major = majorBrands.compactMap { byKey[$0.lowercased()] }
        let sorted = all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var groups: [String: [BrandIndex.Brand]] = [:]
        for b in sorted { groups[letter(of: b.name), default: []].append(b) }
        let order = groups.keys.sorted { a, b in a == "#" ? false : (b == "#" ? true : a < b) }
        return BrandIndex(major: major, sections: order.map { ($0, groups[$0]!) })
    }

    /// 某个品牌下的全部测量（型号名排序；同名不同来源都列，来源写在右边）
    static func models(_ entries: [Entry], brand: String) -> [Entry] {
        let k = brand.lowercased()
        return entries.filter { Self.brand(of: $0.name).lowercased() == k }
            .sorted { a, b in
                let c = a.name.localizedStandardCompare(b.name)
                return c != .orderedSame ? c == .orderedAscending : a.displaySource < b.displaySource
            }
    }

    /// 型号在品牌页里的显示名（去掉开头的品牌）
    static func modelName(_ e: Entry, brand: String) -> String {
        guard e.name.lowercased().hasPrefix(brand.lowercased() + " ") else { return e.name }
        return String(e.name.dropFirst(brand.count + 1))
    }
}
