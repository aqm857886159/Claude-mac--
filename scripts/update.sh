#!/usr/bin/env bash
#
# update.sh — 官方 Claude 更新后，把副本同步到最新版（保留登录态）
#
# 用法:
#   ./update.sh        # 同步 Claude2
#   ./update.sh 3      # 同步 Claude3
#   ./update.sh work   # 同步 Claudework
#
# 原理：副本不会跟随官方自动更新。本脚本用最新的官方 App 重新生成副本，
#       但「不动」独立数据目录（~/Library/Application Support/Claude<后缀>），
#       所以登录态、历史会话都保留。本质上就是重跑一遍 install，但更直白。
#
set -euo pipefail
SUFFIX="${1:-2}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="$HOME/Library/Application Support/Claude${SUFFIX}"
echo "▶ 将把 Claude${SUFFIX} 同步到最新官方版本，数据目录保留：$DATA_DIR"

# 关掉正在运行的副本，避免占用
pkill -f "Claude${SUFFIX}.app/Contents/MacOS/Claude" 2>/dev/null || true
sleep 1

# 复用 install.sh（它本身就是「删旧副本→按最新官方版重建」，不会碰数据目录）
exec "$HERE/install.sh" "$SUFFIX"
