# Claude-mac-dual · Run multiple Claude desktop apps on macOS (multi-account)

Run **several Claude desktop apps at the same time** on macOS, each signed into a
**different account**, with fully isolated data. One command. Plus a full write-up
of every pitfall we hit.

> 中文文档见 [README.md](README.md).
> Works on macOS + the official [Claude desktop app](https://claude.ai/download) (Electron).
> The technique generalizes to other single-instance Electron apps.

---

## Why

The official Claude desktop app only lets you run **one instance**: clicking the icon
again (or `open -n`) just focuses the existing window, because it's an Electron app
guarded by a **single-instance lock** (`requestSingleInstanceLock()`).

This project creates clones — `Claude2`, `Claude3`, … — each launched with its own
data directory, so you can keep e.g. a **personal** and a **work** account online
simultaneously without interference.

---

## Quick start

### Option A — one-liner

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aqm857886159/Claude-mac--/main/scripts/install.sh)
```

> Creates `Claude2.app` by default. Add a number for more:
> `bash <(curl -fsSL .../install.sh) 3` → `Claude3.app`.

### Option B — clone the repo

```bash
git clone https://github.com/aqm857886159/Claude-mac--.git claude-mac-dual
cd claude-mac-dual
chmod +x scripts/*.sh
./scripts/install.sh        # creates Claude2.app
./scripts/install.sh 3      # another one
```

Then:
1. Open **Claude2** from Applications (first launch blocked by Gatekeeper? right-click → **Open** once).
2. **Sign into your other account** (prefer the email verification *code*, not the link).
3. Done ✅ — two independent windows, independent accounts and history.

Not a terminal person? Double-click **`Install.command`** in the repo instead.

---

## What it actually does (manual steps)

```bash
SRC="/Applications/Claude.app"
DST="/Applications/Claude2.app"

# 1) Copy the official app
ditto "$SRC" "$DST"

# 2) Replace the main binary with a wrapper that injects an isolated data dir (the key!)
cd "$DST/Contents/MacOS"
mv Claude Claude.real
cat > Claude <<'SH'
#!/bin/bash
exec "$(dirname "$0")/Claude.real" --user-data-dir="$HOME/Library/Application Support/Claude2" "$@"
SH
chmod +x Claude

# 3) Identity: CFBundleName MUST stay "Claude" (else Helper not found); Dock name via DisplayName
PL="$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Claude" "$PL"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Claude2" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Claude2" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.anthropic.claudefordesktop2" "$PL"

# 4) Clear quarantine + ad-hoc re-sign (required after editing the bundle)
xattr -cr "$DST"
codesign --force --deep --sign - "$DST"

# 5) Launch
open -a "$DST"
```

---

## ⚠️ Pitfalls we hit (the important part)

### Pitfall 1 — "copy + rename" alone won't open a second instance
The Electron data dir / single-instance lock is keyed on **`app.getName()`**, and the
app **hardcodes** `app.setName("Claude")` (`strings app.asar | grep setName`), which
**overrides Info.plist**. Both copies still share
`~/Library/Application Support/Claude` and the same lock.
**Fix:** inject Electron's native `--user-data-dir` switch via a wrapper script so the
clone gets its own data dir → its own lock.

### Pitfall 2 — renaming `CFBundleName` crashes with "Unable to find helper app"
```
FATAL:electron_main_delegate_mac.mm:65] Unable to find helper app
```
Electron locates `<CFBundleName> Helper.app` under `Contents/Frameworks/`. The real
folders are `Claude Helper.app` etc., so renaming to `Claude2` makes it look for a
nonexistent `Claude2 Helper.app`.
**Fix:** keep `CFBundleName = Claude`; set the Dock name via `CFBundleDisplayName`.

### Pitfall 3 — editing the bundle without re-signing → "app is damaged / can't open"
The official build is Developer-ID signed with the hardened runtime
(`flags=0x10000(runtime)`); any edit invalidates the signature.
**Fix:** `xattr -cr "$DST" && codesign --force --deep --sign - "$DST"`. Ad-hoc dropping
notarization/hardened-runtime is fine locally; right-click → Open once if Gatekeeper warns.

### Pitfall 4 — the "white screen" scare
A blank white window looked like failure. Two causes: (a) we kept `kill`-ing the process
while debugging, and (b) the login page downloads its UI from
`assets-proxy.anthropic.com`, so the first paint takes a few-to-~15 seconds.
**Fix:** launch normally and **wait 5–15s**. With `--enable-logging=stderr`, seeing
`HEALTH-CHECK` / `account_profile data is undefined` means the renderer is actually
running (the latter is just the "not signed in yet" state).

### Bonus — don't click the login link in the email
To sign into a *different* account, prefer the **email verification code**. Clicking the
**magic link** may get hijacked by your default browser or the original Claude app.

---

## Updating after an official release

Clones do **not** auto-update. After the official app updates, run:

```bash
./scripts/update.sh        # resync Claude2, keeps your login
./scripts/update.sh 3      # resync Claude3
```

It rebuilds the clone from the latest official app **without touching** the isolated data
dir, so logins and history are preserved.

---

## Uninstall

```bash
./scripts/uninstall.sh           # remove Claude2.app, keep data (login preserved)
./scripts/uninstall.sh 2 --purge # also delete the data dir
```

The original `/Applications/Claude.app` is never touched.

---

## How it works

| Mechanism | Notes |
|---|---|
| Single-instance lock | `requestSingleInstanceLock()`; lock file lives in `userData` |
| Data dir | `userData = appData + app.getName()`; app hardcodes `setName("Claude")` |
| The bypass | Electron honors `--user-data-dir` to override `userData` → separate lock |
| Helper lookup | by `CFBundleName` → `<name> Helper.app`, so it must stay `Claude` |
| Signing | edits invalidate Developer-ID; ad-hoc re-sign + clear quarantine to run locally |

---

## Disclaimer

This only modifies a local copy of the official client (injecting a launch flag /
re-signing). It does not crack or alter anything server-side. Follow Anthropic's Terms
of Service; use at your own risk. MIT licensed.
