#!/bin/bash
# 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
# 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
# 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
# Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
# products or client work) is prohibited without written permission from Luna Fantasy Lab.

# 从 Sparkle 官方 Release 下载 Sparkle.xcframework（MIT）到 Vendor/，构建前自动调用。
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${SPARKLE_VERSION:-2.10.1}"
TMP="$(mktemp -d)"
curl -fsSL -o "$TMP/sparkle.zip" "https://github.com/sparkle-project/Sparkle/releases/download/$VER/Sparkle-for-Swift-Package-Manager.zip"
unzip -q "$TMP/sparkle.zip" -d "$TMP"
rm -rf Vendor/Sparkle.xcframework
mkdir -p Vendor
cp -R "$TMP/Sparkle.xcframework" Vendor/Sparkle.xcframework
rm -rf "$TMP"
echo "Sparkle $VER -> Vendor/Sparkle.xcframework"
