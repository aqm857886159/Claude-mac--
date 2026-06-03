#!/usr/bin/env bash
#
# uninstall.sh — 干净卸载副本（原版 Claude 不受影响）
#
# 用法:
#   ./uninstall.sh           # 卸载 Claude2（默认保留数据目录）
#   ./uninstall.sh 3         # 卸载 Claude3
#   ./uninstall.sh 2 --purge # 同时删除独立数据目录（会丢失该副本的登录态/会话）
#
set -euo pipefail
SUFFIX="${1:-2}"
PURGE="${2:-}"
DST="/Applications/Claude${SUFFIX}.app"
DATA_DIR="$HOME/Library/Application Support/Claude${SUFFIX}"

echo "▶ 关闭 Claude${SUFFIX} ..."
pkill -f "Claude${SUFFIX}.app/Contents/MacOS/Claude" 2>/dev/null || true
sleep 1

if [[ -e "$DST" ]]; then
  rm -rf "$DST"
  echo "✓ 已删除 $DST"
else
  echo "· 未发现 $DST"
fi

if [[ "$PURGE" == "--purge" ]]; then
  if [[ -d "$DATA_DIR" ]]; then
    rm -rf "$DATA_DIR"
    echo "✓ 已删除数据目录 $DATA_DIR（登录态/会话已清除）"
  fi
else
  echo "· 已保留数据目录 $DATA_DIR（下次重装可免登录）。如需彻底清除：加 --purge"
fi

echo "✓ 完成。原版 /Applications/Claude.app 未受影响。"
