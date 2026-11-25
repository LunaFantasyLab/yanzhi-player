#!/bin/bash
# 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
# 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
# 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
# Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
# products or client work) is prohibited without written permission from Luna Fantasy Lab.

# 「有进就有出」门禁（TANCO 2026-11-19 第 7 轮）：
# PlayerController 里凡是像「进入的状态」的属性（is… / show… / …Open / …Targeted / active… / ab A/B / tab / 速度音调 / 识别进度 …），
# 必须登记在 Engine/PlayerController+Exits.swift 的 exit-registry（有退出路、自测覆盖）或 exit-exempt（不是可进入的状态）里。
# 没登记 = 新状态还没想好怎么退出 → 构建失败。
cd "$(dirname "$0")/.."
SRC=Sources/GlassPlayer/Engine
EX=$SRC/PlayerController+Exits.swift
reg=$(grep -E '^/// exit-(registry|exempt)' "$EX" | sed -E 's/^\/\/\/ exit-[a-z]+[^:]*: *//' | tr ' ' '\n' | grep -v '^$' | sort -u)
cands=$(grep -hE '^    (@ObservationIgnored\s+)?((private|fileprivate)(\(set\))?\s+)?var\s+[A-Za-z_]+' $SRC/PlayerController*.swift \
  | sed -E 's/.*var[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
  | grep -E '^(is[A-Z]|show[A-Z]|active[A-Z])|Open$|Targeted$|^ab[AB]$|^tab$|^speed$|^pitch(Semitones|Cents)$|^asrProgress$|^lyricsEnabled$' | sort -u)
miss=$(comm -23 <(echo "$cands") <(echo "$reg"))
if [ -n "$miss" ]; then
  echo "✗ 有进就有出：下面这些状态属性没登记退出方式（在 $EX 的 exit-registry 里登记并在 ExitState / closureTests 里补进出测试，或在 exit-exempt 里说明为什么不算）："
  echo "$miss" | sed 's/^/   - /'
  exit 1
fi
echo "✓ 有进就有出：$(echo "$cands" | wc -l | tr -d ' ') 个状态属性都已登记"
