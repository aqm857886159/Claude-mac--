#!/bin/bash
# 双击运行：在 macOS 上创建一个独立的 Claude 副本（默认 Claude2）。
# 想多开：把本文件复制一份改名也行，或在终端跑 ./scripts/install.sh 3
cd "$(dirname "$0")" || exit 1
chmod +x scripts/*.sh 2>/dev/null
echo "================================================"
echo "  Claude 多开安装器"
echo "================================================"
printf "要创建第几个副本？直接回车=2（即 Claude2）: "
read -r N
N="${N:-2}"
./scripts/install.sh "$N"
echo
echo "完成。可关闭本窗口。按回车退出..."
read -r _
