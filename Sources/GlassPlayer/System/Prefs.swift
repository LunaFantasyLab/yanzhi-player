// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 偏好设置的薄封装。自测模式（启动参数 -testSandbox YES）下只记在内存里，
/// 不写 ~/Library/Preferences，保证自测不改动本人的主题、最近打开等记录。
enum Prefs {
    /// 启动参数 `-testSandbox YES` 经命令行进入 UserDefaults 时是字符串，`bool(forKey:)` 不会把它当成 true。
    static let sandbox: Bool = {
        let d = UserDefaults.standard
        if d.bool(forKey: "testSandbox") { return true }
        guard let s = d.string(forKey: "testSandbox") else { return false }
        switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y": return true
        default: return false
        }
    }()
    nonisolated(unsafe) private static var memory: [String: Any] = [:]

    static func string(_ k: String) -> String? { sandbox ? memory[k] as? String : UserDefaults.standard.string(forKey: k) }
    static func set(_ v: Any?, _ k: String) {
        if sandbox { memory[k] = v } else { UserDefaults.standard.set(v, forKey: k) }
    }
    static func object(_ k: String) -> Any? { sandbox ? memory[k] : UserDefaults.standard.object(forKey: k) }
    static func data(_ k: String) -> Data? { object(k) as? Data }
    static func bool(_ k: String) -> Bool { object(k) as? Bool ?? false }
    static var recent: [URL] {
        get {
            let arr = sandbox ? (memory["recent"] as? [String] ?? []) : (UserDefaults.standard.stringArray(forKey: "recent") ?? [])
            return arr.compactMap { s in s.hasPrefix("/") ? URL(fileURLWithPath: s) : URL(string: s) }
        }
        set { set(newValue.map { $0.isFileURL ? $0.path : $0.absoluteString }, "recent") }
    }
}
