#!/usr/bin/env bash
#
# install.sh — 在 macOS 上克隆一个独立的 Claude 桌面端，实现「双开 / 多开 + 多账号」
#
# 用法:
#   ./install.sh          # 默认创建 Claude2.app
#   ./install.sh 2        # 创建 Claude2.app
#   ./install.sh 3        # 创建 Claude3.app（可继续 4、5...）
#   ./install.sh work     # 也支持任意后缀，创建 Claudework.app
#
# 原理见 README：官方 Claude 桌面端是 Electron 应用，代码里写死了 app.setName("Claude")，
# 并用 requestSingleInstanceLock() 加了单实例锁。所以单纯复制+改名是开不出第二个的，
# 必须给副本注入独立的 --user-data-dir，才能拥有独立数据目录和独立的实例锁。
#
set -euo pipefail

SUFFIX="${1:-2}"
SRC="/Applications/Claude.app"
DST="/Applications/Claude${SUFFIX}.app"
DATA_DIR="$HOME/Library/Application Support/Claude${SUFFIX}"
NEW_ID="com.anthropic.claudefordesktop${SUFFIX}"

say()  { printf "\033[1;36m▶ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; }

# ---------- 0. 前置检查 ----------
if [[ "$(uname)" != "Darwin" ]]; then
  err "本脚本仅适用于 macOS。"; exit 1
fi
if [[ ! -d "$SRC" ]]; then
  err "未找到官方 Claude 桌面端：$SRC"
  err "请先从 https://claude.ai/download 下载安装官方桌面端再运行本脚本。"
  exit 1
fi
# 确认是 Electron 版（含 Frameworks 与 Helper），避免对未来不同形态的 app 误操作
if ! ls "$SRC/Contents/Frameworks/" 2>/dev/null | grep -qi "Helper"; then
  err "$SRC 结构异常（未找到 Electron Helper），脚本可能不适用于当前版本，已中止。"
  exit 1
fi

say "目标副本：$DST"
say "独立数据目录：$DATA_DIR"

# ---------- 1. 复制 ----------
if [[ -e "$DST" ]]; then
  say "已存在旧副本，先删除：$DST"
  pkill -f "Claude${SUFFIX}.app/Contents/MacOS/Claude" 2>/dev/null || true
  sleep 1
  rm -rf "$DST"
fi
say "复制官方 App（约 700MB，请稍候）..."
ditto "$SRC" "$DST"
ok "复制完成：$(du -sh "$DST" | cut -f1)"

# ---------- 2. 安装壳脚本，注入独立数据目录 ----------
say "安装启动壳脚本（注入 --user-data-dir）..."
cd "$DST/Contents/MacOS"
# 真二进制改名，壳脚本顶替原名
mv Claude Claude.real
cat > Claude <<EOF
#!/bin/bash
# 由 Claude-mac-dual 生成：强制独立数据目录，实现与原版的多开/多账号
exec "\$(dirname "\$0")/Claude.real" --user-data-dir="\$HOME/Library/Application Support/Claude${SUFFIX}" "\$@"
EOF
chmod +x Claude
ok "壳脚本就位"

# ---------- 3. 改 Info.plist 标识 ----------
# 关键坑：CFBundleName 必须保持 "Claude"，否则 Electron 找不到
#         "Claude Helper*.app"，会崩在 "Unable to find helper app"。
#         Dock 显示名走 CFBundleDisplayName，这样既能找到 helper，Dock 又显示 Claude<后缀>。
say "修改 Info.plist 标识（保留 CFBundleName=Claude，DisplayName=Claude${SUFFIX}）..."
PL="$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Claude" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Claude${SUFFIX}" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Claude${SUFFIX}" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${NEW_ID}" "$PL"
ok "标识：Name=Claude  Display=Claude${SUFFIX}  Id=${NEW_ID}"

# ---------- 4. 清 quarantine + ad-hoc 重新签名 ----------
# 改动内容后原 Developer ID 签名失效，硬运行时下会拒绝启动，必须重签。
# 本地用 ad-hoc 签名即可（会去掉公证/硬运行时，本机运行无碍）。
say "清理 quarantine 并 ad-hoc 重新签名..."
xattr -cr "$DST" 2>/dev/null || true
codesign --force --deep --sign - "$DST"
codesign --verify --deep "$DST" 2>/dev/null && ok "签名校验通过" || say "签名有警告（ad-hoc 常见，可忽略）"

echo
ok "完成！已生成 ${DST##*/}"
cat <<EOF

下一步：
  1) 打开「访达 → 应用程序」，双击 Claude${SUFFIX}（Dock 图标名为 Claude${SUFFIX}）。
     · 首次启动若被 Gatekeeper 拦截（"无法验证开发者"），右键图标 →「打开」一次即可。
     · 首次加载登录页要从网络下载界面资源，白屏属正常，等 5–15 秒。
  2) 在 Claude${SUFFIX} 窗口里用「另一个账号」登录。
     · 建议用「邮箱验证码」登录；若用邮件里的登录链接，可能会被默认浏览器/原版抢走。
  3) 数据目录：$DATA_DIR （与原版完全隔离）

官方更新后如何同步副本：重新运行  ./scripts/update.sh ${SUFFIX}
卸载：./scripts/uninstall.sh ${SUFFIX}
EOF
