// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 第二轮功能用到的本地文件都放在项目目录里（不装系统软件、不用 sudo）：
/// ~/AI/玻璃播放器/runtime/
///   whisper/bin/whisper-cli        本机编译的 whisper.cpp（Metal 加速）
///   models/ggml-*.bin               语音识别模型
///   subtitles/                      生成或下载的字幕
///   lyrics/                         音频转写出的 LRC
///   autoeq/                         AutoEq 索引和曲线缓存
enum Runtime {
    static var root: URL {
        if let s = UserDefaults.standard.string(forKey: "runtimeRoot") { return URL(fileURLWithPath: s) }
        // TANCO 本机：沿用项目目录（已有就用，不新建）。别人的 Mac：放在 App 自己的 Application Support 里，
        // 不在用户主目录下凭空建「AI/玻璃播放器」。
        let legacy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AI/玻璃播放器/runtime")
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "com.tanco.glassplayer")/runtime")
    }
    static func dir(_ name: String) -> URL {
        let u = root.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var whisperCLI: URL { root.appendingPathComponent("whisper/bin/whisper-cli") }
    /// 可用的模型：按质量从高到低找第一个存在的
    static let modelCandidates = ["ggml-large-v3-turbo-q5_0.bin", "ggml-large-v3-turbo.bin", "ggml-small.bin", "ggml-base.bin"]
    static var whisperModel: URL? {
        modelCandidates.map { root.appendingPathComponent("models/\($0)") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    /// 语音活动检测模型（可选；有就用）
    static var vadModel: URL? {
        ["ggml-silero-v6.2.0.bin", "ggml-silero-v5.1.2.bin"].map { root.appendingPathComponent("models/\($0)") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    /// 媒体文件 → 稳定的文件名（不同目录的同名文件不冲突）
    static func key(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let h = String(format: "%08x", UInt32(truncatingIfNeeded: PlayerCoreHash.fnv(url.path)))
        return "\(base)-\(h)"
    }
}

enum PlayerCoreHash {
    static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }
}
