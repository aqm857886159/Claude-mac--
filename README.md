# Claude-mac-dual · macOS 上 Claude 桌面端「双开 / 多开 + 多账号」

在 macOS 上**同时运行多个 Claude 桌面端**，每个登录**不同账号**、数据完全隔离。
一条命令搞定，附带踩坑全记录。

**[English README →](README.en.md)** ｜ 不想用终端？克隆后**双击 `Install.command`** 即可。

> 适用：macOS + 官方 [Claude 桌面端](https://claude.ai/download)（Electron 版）。
> 原理对其他 Electron 应用（带单实例锁）也通用。

---

## 这是什么 / 为什么需要

官方 Claude 桌面端默认**只能开一个**：再点图标、或 `open -n` 都只会把已有窗口提到前台。
原因是它是 Electron 应用，加了**单实例锁**（`requestSingleInstanceLock()`）。

本项目用一个克隆副本 + 注入独立数据目录的方式，做出 `Claude2`、`Claude3`…… 让你能
**个人号 / 工作号**同时在线，互不干扰。

---

## 快速开始（一键）

### 方式 A：一行命令（最省事）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aqm857886159/Claude-mac--/main/scripts/install.sh)
```

> 默认创建 `Claude2.app`。想再开一个就在末尾加数字：
> `bash <(curl -fsSL .../install.sh) 3` → 生成 `Claude3.app`。

### 方式 B：克隆仓库后运行

```bash
git clone https://github.com/aqm857886159/Claude-mac--.git claude-mac-dual
cd claude-mac-dual
chmod +x scripts/*.sh
./scripts/install.sh          # 生成 Claude2.app
./scripts/install.sh 3        # 想要第三个就再来一次
```

跑完后：
1. 打开「应用程序」，双击 **Claude2**（首次被 Gatekeeper 拦就右键 →「打开」一次）。
2. 在 Claude2 窗口里**登录你的另一个账号**（建议用邮箱验证码登录）。
3. 完成 ✅ —— 两个窗口各自独立账号、独立历史。

---

## 它到底做了什么（手动版步骤）

如果你想理解 / 手动操作，脚本本质上做了 5 步：

```bash
SRC="/Applications/Claude.app"
DST="/Applications/Claude2.app"
DATA="$HOME/Library/Application Support/Claude2"

# 1) 复制官方 App
ditto "$SRC" "$DST"

# 2) 真二进制改名，放一个壳脚本注入独立数据目录（核心！）
cd "$DST/Contents/MacOS"
mv Claude Claude.real
cat > Claude <<'SH'
#!/bin/bash
exec "$(dirname "$0")/Claude.real" --user-data-dir="$HOME/Library/Application Support/Claude2" "$@"
SH
chmod +x Claude

# 3) 改标识：CFBundleName 必须保持 Claude（否则找不到 Helper），Dock 名走 DisplayName
PL="$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Claude" "$PL"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Claude2" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Claude2" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.anthropic.claudefordesktop2" "$PL"

# 4) 清 quarantine + ad-hoc 重签名（改了内容必须重签，否则打不开）
xattr -cr "$DST"
codesign --force --deep --sign - "$DST"

# 5) 启动
open -a "$DST"
```

---

## ⚠️ 我们踩过的坑（重点，按踩到的顺序）

做这个方案时，"复制+改名" 这种想当然的做法**几乎每一步都有坑**。完整记录如下：

### 坑 1：单纯「复制 + 改名」根本开不出第二个
**现象**：复制成 `Claude2.app` 并改了 `CFBundleName`，双击后还是只把原版窗口提到前台。
**原因**：Electron 的数据目录 / 单实例锁是按 **`app.getName()`** 算的。而官方代码里**硬写了**
`app.setName("Claude")`（用 `strings app.asar | grep setName` 可见），它会**覆盖 Info.plist
的名字**。于是两个 App 仍然共用同一个数据目录 `~/Library/Application Support/Claude` 和同一把锁。
**解法**：不能靠改名，必须在启动时注入 Electron 原生支持的 `--user-data-dir` 参数，
强制一个独立数据目录 → 独立的锁。普通 `.app` 从访达启动不带参数，所以用**壳脚本**顶替主程序
来注入（见上方第 2 步）。

### 坑 2：改了 `CFBundleName` 后崩溃 —— "Unable to find helper app"
**现象**：把 `CFBundleName` 改成 `Claude2` 后启动，主进程秒退，日志报：
```
FATAL:electron_main_delegate_mac.mm:65] Unable to find helper app
```
**原因**：Electron 按主 bundle 的 **`CFBundleName`** 去 `Contents/Frameworks/` 里找配套的
`<名字> Helper.app`。实际文件是 `Claude Helper.app`、`Claude Helper (GPU).app` 等；
你把名字改成 `Claude2`，它就去找根本不存在的 `Claude2 Helper.app`。
**解法**：**`CFBundleName` 必须保持 `Claude`**。想让 Dock 显示成 `Claude2`，
改 **`CFBundleDisplayName`**（Dock 名取这个），两者兼得。

### 坑 3：改完内容不重签名 → 应用"已损坏 / 无法打开"
**现象**：官方是 Developer ID 签名 + 硬运行时（`flags=0x10000(runtime)`）。一旦你改了
Info.plist 或可执行文件，原签名失效，硬运行时会拒绝加载。
**解法**：清掉隔离属性并 **ad-hoc 重新签名**：
```bash
xattr -cr "$DST"
codesign --force --deep --sign - "$DST"
```
ad-hoc 会去掉公证/硬运行时，本机运行完全没问题。首次启动 Gatekeeper 可能提示一次，
右键 →「打开」即可。

### 坑 4：白屏虚惊 —— 其实是"进程被关掉了"和"首屏在联网加载"
**现象**：启动后看到**纯白窗口**，以为失败了。
**真相**：两种原因叠加 ——（a）调试时反复 `kill` 进程，看到的是被关掉/没加载完的空窗；
（b）登录页资源要从 `assets-proxy.anthropic.com` **联网下载**，首屏白屏几秒到十几秒是正常的。
**解法**：正常 `open -a` 启动后**别去 kill**，**等 5–15 秒**登录页就出来了。
用 `--enable-logging=stderr` 看日志，出现 `HEALTH-CHECK` / `account_profile data is undefined`
就说明渲染层其实跑起来了（后者只是"还没登录"的正常状态）。

### 额外提醒：登录别点邮件里的链接
两个窗口要登**不同账号**。用**邮箱验证码**登录最稳；若点邮件里的**登录链接**，
可能被默认浏览器或原版 Claude 抢走，导致登错窗口。

---

## 官方更新后怎么同步副本

副本**不会**跟随官方自动更新。官方更新完，跑一下：

```bash
./scripts/update.sh        # 同步 Claude2，保留登录态
./scripts/update.sh 3      # 同步 Claude3
```

它会用最新官方版重建副本，但**不动**独立数据目录，所以登录态、历史会话都在。

---

## 卸载

```bash
./scripts/uninstall.sh           # 删 Claude2.app，保留数据目录（下次重装免登录）
./scripts/uninstall.sh 2 --purge # 连数据目录一起删，彻底清除
```

原版 `/Applications/Claude.app` 全程不受影响。

---

## 常见问题（FAQ）

**Q：双击没反应 / 提示"无法验证开发者"？**
A：ad-hoc 签名的应用首次启动会被 Gatekeeper 拦。右键图标 →「打开」一次，之后就正常了。

**Q：一直白屏怎么办？**
A：先等 15 秒（首屏联网下载）。仍白屏就在终端跑
`"/Applications/Claude2.app/Contents/MacOS/Claude.real" --user-data-dir="$HOME/Library/Application Support/Claude2" --enable-logging=stderr`
看报错。常见是网络问题导致 `assets-proxy.anthropic.com` 加载不出。

**Q：能开三个、四个吗？**
A：可以。`./install.sh 3`、`./install.sh 4` …… 每个有独立数据目录 `Claude3`、`Claude4`。

**Q：菜单栏/窗口标题为什么还是写 "Claude"？**
A：因为代码里 `setName("Claude")` 写死，那是窗口内部名（纯视觉）。Dock 图标名是 `Claude2`，
数据完全隔离，不影响使用。

**Q：会不会被封号 / 违规？**
A：这只是在本机多开官方客户端、登录你自己的多个账号，没有修改服务端行为。
是否允许多账号请以官方条款为准，风险自负。

---

## 原理速览

| 机制 | 说明 |
|---|---|
| 单实例锁 | `requestSingleInstanceLock()`，锁文件在 `userData` 目录里 |
| 数据目录 | `userData = appData + app.getName()`，本应用 `setName("Claude")` 写死 |
| 破解点 | Electron 原生支持 `--user-data-dir` 覆盖 `userData` → 独立锁 → 可并存 |
| Helper 查找 | 按 `CFBundleName` 找 `<名> Helper.app`，故 `CFBundleName` 必须保持 `Claude` |
| 签名 | 改动后原 Developer ID 失效，ad-hoc 重签 + 清 quarantine 即可本机运行 |

---

## 免责声明

本项目仅修改本机上的官方客户端副本（注入启动参数 / 重签名），不涉及破解或修改服务端。
请遵守 Anthropic 的服务条款，自行承担使用风险。脚本以 MIT 协议开源。
