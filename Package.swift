// swift-tools-version:6.0
// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

// 「玻璃」— TANCO 的原生音视频播放器
// PlayerCore：纯 Swift 逻辑（弹簧物理、轮播、均衡器、播放队列、封面配色……），Linux/macOS 都能编译和测试。
// GlassPlayer：macOS App（SwiftUI + AppKit + libmpv），只在 macOS 上参与编译。
import PackageDescription

var products: [Product] = [
    .library(name: "PlayerCore", targets: ["PlayerCore"]),
]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "PlayerCore", path: "Sources/PlayerCore"),
    // 只用于 Linux/macOS 命令行验证默认封面渲染（不进 App）
    .executableTarget(name: "RenderCheck", dependencies: ["PlayerCore"], path: "tools/linux-check/RenderCheck"),
    .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"], path: "Tests/PlayerCoreTests",
                resources: [.copy("Fixtures")]),
]

#if os(macOS)
products.append(.executable(name: "GlassPlayer", targets: ["GlassPlayer"]))
// MPVKit（LGPL 版）：libmpv 0.41 + FFmpeg n9.0.2 的预编译静态 xcframework，Apple Silicon/Intel 通用。
dependencies.append(.package(url: "https://github.com/mpvkit/MPVKit.git", exact: "1.1.0-n9.0.2"))
// Sparkle 2（MIT）：只用于本人手动「检查更新」。官方发布的 xcframework 放在 Vendor/（不进源码包，构建前从官方 Release 下载）
targets.append(.binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework"))
targets.append(
    .executableTarget(
        name: "GlassPlayer",
        dependencies: [
            "PlayerCore",
            .product(name: "MPVKit", package: "MPVKit"),
            "Sparkle",
        ],
        path: "Sources/GlassPlayer",
        swiftSettings: [
            .swiftLanguageMode(.v5),
        ],
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("SwiftUI"),
            .linkedFramework("AVFoundation"),
            .linkedFramework("MediaPlayer"),
            .linkedFramework("CoreImage"),
            .linkedFramework("QuartzCore"),
            .linkedFramework("Metal"),
            .linkedFramework("UniformTypeIdentifiers"),
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
        ]
    )
)
#endif

let package = Package(
    name: "GlassPlayer",
    platforms: [.macOS(.v15)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
