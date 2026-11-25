#!/bin/bash
# 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
# 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
# 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
# Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
# products or client work) is prohibited without written permission from Luna Fantasy Lab.

# 「胭脂」构建脚本 —— 在 Apple Silicon Mac 上运行：  bash build.sh
# 只在本目录内产生文件：.build/（编译缓存与 SwiftPM 依赖）和 dist/胭脂.app
# 不安装任何东西到系统目录，不改系统设置，不联网上传。
# 首次运行会从 GitHub 下载 MPVKit 预编译库（约 250 MB+）。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="胭脂"
EXE="GlassPlayer"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "== 1/5 检查工具链"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "没有找到 Xcode 或 Command Line Tools。请先（经同意）运行：xcode-select --install"; exit 1
fi
swift --version
SW_MAJOR=$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\)\..*/\1/p' | head -1)
if [ "${SW_MAJOR:-0}" -lt 6 ]; then echo "需要 Swift 6 及以上（Xcode 16+ / CLT 16+）"; exit 1; fi
if [ "$(uname -m)" != "arm64" ]; then echo "提示：当前不是 Apple Silicon，仍按 arm64 构建"; fi

echo "== 2/5 编译（Release, arm64）"
[ -d Vendor/Sparkle.xcframework ] || bash tools/fetch-sparkle.sh
bash tools/check-exits.sh || { echo "构建中止：有进就有出门禁没过"; exit 1; }
swift build -c release --arch arm64 --product "$EXE"
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$EXE"
[ -x "$BIN" ] || { echo "没有找到编译产物 $BIN"; exit 1; }

echo "== 3/5 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
cp packaging/Info.plist "$APP/Contents/Info.plist"
# 中文本地化：让系统自带的菜单项（编辑、窗口、显示…）也显示中文
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj"
printf '"CFBundleDisplayName" = "胭脂";\n"CFBundleName" = "胭脂";\n"NSHumanReadableCopyright" = "© 2026 Luna Fantasy Lab · 源码公开·非商业许可（PolyForm Noncommercial 1.0.0）· 禁止任何形式的商业使用";\n' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
# 「关于胭脂」面板里的作者与许可说明（系统 About 面板自动读取 Resources/Credits.html）
cp packaging/Credits.html "$APP/Contents/Resources/Credits.html"
# SwiftPM 资源包（如有）
for b in "$(dirname "$BIN")"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
# 第三方组件许可全文（发布时一起分发；说明文件由 release/tools/gen_notices.py 生成）
[ -d packaging/Licenses ] && { rm -rf "$APP/Contents/Resources/Licenses"; cp -R packaging/Licenses "$APP/Contents/Resources/Licenses"; }
# 耳机校正的耳机列表（AutoEq INDEX.md，MIT），随 App 打包，离线也能按品牌 / 型号找
[ -d packaging/AutoEq ] && { rm -rf "$APP/Contents/Resources/AutoEq"; cp -R packaging/AutoEq "$APP/Contents/Resources/AutoEq"; }
# MPVKit 是静态 xcframework，无需嵌入 dylib；若将来改成动态库，在此复制到 Contents/Frameworks
if [ -d "$(dirname "$BIN")/PackageFrameworks" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$(dirname "$BIN")"/PackageFrameworks/*.framework "$APP/Contents/Frameworks/" 2>/dev/null || true
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$EXE" 2>/dev/null || true
fi

# Sparkle.framework（检查更新用）：原样复制（保留符号链接）；非沙盒 App 用不到它的 XPC 服务，去掉
SP="$(dirname "$BIN")/Sparkle.framework"
if [ -d "$SP" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  ditto "$SP" "$APP/Contents/Frameworks/Sparkle.framework"
  rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
else
  echo "没有找到 Sparkle.framework（Vendor/Sparkle.xcframework）"; exit 1
fi
# 版本号、更新源地址可在构建时指定（测试更新流程时用）
[ -n "${APP_VERSION:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
[ -n "${APP_BUILD:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP/Contents/Info.plist"
[ -n "${UPDATE_FEED_URL:-}" ] && /usr/libexec/PlistBuddy -c "Set :LiuliUpdateFeedURL $UPDATE_FEED_URL" "$APP/Contents/Info.plist"

echo "== 4/5 图标"
# 新版（macOS 26+）：Icon Composer 格式（矢量），用 Xcode 自带的 actool 编译成 Assets.car + AppIcon.icns（旧系统用）。
# 默认 packaging/AppIcon.icon：正常折扇单套（art-dark 稿）。原因：系统「外观 ▸ 图标与小组件样式」是「默认」时，
#   程序坞 / 访达永远显示图标的默认那一套，不跟随深浅色；只有选「深色 ▸ 自动」才切换。
# ICON=auto bash build.sh：用 packaging/AppIcon-auto.icon —— 正常折扇浅色 / 深色两套（art-light / art-dark），
#   配合「图标与小组件样式 ▸ 深色 ▸ 自动」跟随系统自动切换。没有 actool 时退回 packaging/AppIcon.iconset 的 .icns。
ICON_SRC=packaging/AppIcon.icon; ICON_DESC="正常折扇"
if [ "${ICON:-}" = "auto" ]; then ICON_SRC=packaging/AppIcon-auto.icon; ICON_DESC="正常折扇 浅色/深色，自动切换"; fi
ICON_OK=0
if xcrun --find actool >/dev/null 2>&1; then
  IB="$PWD/$DIST/icon-build"   # actool 要绝对路径
  rm -rf "$IB"; mkdir -p "$IB/src"
  # actool 用 .icon 的文件名当图标名，所以统一拷成 AppIcon.icon 再编译
  cp -R "$ICON_SRC" "$IB/src/AppIcon.icon"
  if xcrun actool "$IB/src/AppIcon.icon" --compile "$IB" --platform macosx --minimum-deployment-target 15.0 \
       --app-icon AppIcon --output-partial-info-plist "$IB/partial.plist" \
       --errors --warnings --output-format human-readable-text > "$IB/actool.log" 2>&1 \
     && [ -s "$IB/Assets.car" ] && [ -s "$IB/AppIcon.icns" ]; then
    cp "$IB/Assets.car" "$IB/AppIcon.icns" "$APP/Contents/Resources/"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$APP/Contents/Info.plist"
    ICON_OK=1; echo "图标：${ICON_SRC}（${ICON_DESC}）"
  else
    echo "actool 编译 AppIcon.icon 失败，退回单一图标："; cat "$IB/actool.log" || true
  fi
fi
if [ $ICON_OK = 0 ]; then
  iconutil -c icns packaging/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "== 5/5 本机临时签名（ad-hoc，仅供自己使用，不上传公证）"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP" && echo "签名校验通过"

echo
echo "完成：$(pwd)/$APP"
echo "首次打开：在访达中右键 → 打开（未公证的自建 App 需要这样放行一次）。"

if [ "${1:-}" = "--dmg" ]; then
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DIST/$APP_NAME.dmg"
  echo "DMG：$(pwd)/$DIST/$APP_NAME.dmg"
fi
