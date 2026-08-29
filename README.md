# my-pi-setup

Personal Pi bootstrap for moving machines. One script restores the packages, skills, extensions, and themes from this host.

Clone this repo, run the OS prereqs script, then `./install.sh`.

`install.sh` needs **bash**, **git**, **python3**, and **pi** on `PATH`. Several Pi packages compile native addons (`node-pty`, `better-sqlite3`, `@ast-grep/cli`), so you also need a C/C++ toolchain. Pi itself requires **Node.js >= 22.19.0**.

## New machine

```bash
git clone git@github.com:BlockedPath/my-pi-setup.git
cd my-pi-setup
chmod +x prereqs.sh install.sh
./prereqs.sh --install    # Ubuntu, Debian, WSL, macOS, Git Bash
./install.sh              # Pi packages, skills, extensions, themes
```

On native Windows (no Git Bash yet), from PowerShell:

```powershell
git clone https://github.com/BlockedPath/my-pi-setup.git
cd my-pi-setup
powershell -ExecutionPolicy Bypass -File .\prereqs.ps1 -Install
```

Then open **Git Bash** in the repo and run `./install.sh`. Easier Windows path: WSL2 + Ubuntu, then use `prereqs.sh`.

Re-run is safe. `./prereqs.sh` only reports; `./prereqs.sh --install` installs missing tools (`--yes` skips prompts, `--optional` adds `xclip` on Linux). `./install.sh --force` reinstalls Pi packages and re-clones herdr. `./install.sh --dry-run` prints the plan.

After `./install.sh`, start a **new** Pi session and `/login`. This repo does not copy secrets.

Notes:

- `muse-voice/macos-dictation.swift` is macOS-only. It still gets copied; it will not run on Linux/Windows.
- Chrome DevTools (`@narumitw/pi-chrome-devtools`) needs Chrome or Chromium at runtime if you use that package.

## Prerequisites

Prefer the scripts above. Manual fallback:

### Ubuntu / Debian

```bash
sudo apt update
sudo apt install -y build-essential python3 git curl ca-certificates pkg-config
# optional clipboard: sudo apt install -y xclip    # or wl-clipboard on Wayland
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
# restart the shell, or: source ~/.nvm/nvm.sh
nvm install 22 && nvm use 22
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

### Windows

Pi uses Git Bash. Do **not** run `install.sh` from PowerShell.

1. [Git for Windows](https://git-scm.com/download/win)
2. [Node.js 22 LTS](https://nodejs.org/) (22.19.0+)
3. [Python 3](https://www.python.org/downloads/) — add to PATH
4. [Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) — **Desktop development with C++**

Then in Git Bash: `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` and `./install.sh`.

### macOS

```bash
xcode-select --install
# Node 22+ via nvm, as on Ubuntu
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
./prereqs.sh --install
./install.sh
```

## What it installs

### Pi packages (20)

From `pi list` / `~/.pi/agent/settings.json`. Specs live in `packages.txt`. Capture-time versions are in `manifest.json`.

| Package | Role |
| --- | --- |
| `@narumitw/pi-chrome-devtools` | Chrome DevTools tools |
| `pi-theme-tokyo-night-storm-improved` | Tokyo Night Storm theme |
| `@ogulcancelik/pi-herdr` | Herdr Pi extension |
| `@juicesharp/rpiv-ask-user-question` | Ask-user-question tool |
| `@juicesharp/rpiv-todo` | Todo tool |
| `pi-lens` | Code intelligence |
| `@plannotator/pi-extension` | Plannotator |
| `pi-tps-meter` | Token speed meter |
| `pi-subagents` | Subagents |
| `pi-startup-header` | Startup header |
| `@narumitw/pi-statusline` | Statusline |
| `@gotgenes/pi-anthropic-auth` | Anthropic auth |
| `pi-extension-cloudflare-workers-ai` | Cloudflare Workers AI provider |
| `pi-web-access` | Web search / fetch |
| `pi-xai-oauth` | xAI OAuth |
| `pi-cursor-sdk` | Cursor SDK models |
| `@llblab/pi-telegram` | Telegram bridge |
| `@juicesharp/rpiv-voice` | Voice |
| `pi-meta-oauth` | Meta OAuth |
| `@narumitw/pi-goal` | Goal mode |

`install.sh` also merges the npm `overrides` from `npm-extras.json` into `~/.pi/agent/npm/package.json` (brace-expansion / undici pins from this machine).

### Skills (2)

| Skill | Source | Installs to |
| --- | --- | --- |
| `herdr` | `git clone --depth 1 https://github.com/ogulcancelik/herdr.git` | `~/.agents/skills/herdr` |
| `herdr-multi-agent-orch` | Vendored in this repo | `~/.agents/skills/herdr-multi-agent-orch` |

Symlinks are created in `~/.pi/agent/skills/` to match this machine.

### Custom extensions

Copied into `~/.pi/agent/extensions/`:

- `herdr-agent-state.ts`
- `moshi-hooks.ts`
- `pi-footer.json`
- `muse-voice/` (`macos-dictation.swift`, `Entitlements.plist`, `Info.plist`)

### Themes

Copied into `~/.pi/agent/themes/`:

- `dark-bright.json`
- `gruvbox-dark.json`
- `nord.json`
- `paper-light.json`
- `tokyo-night.json`

## Not included

On purpose:

- `settings.json` (theme selection, enabled models, subagent overrides, default model/provider)
- Custom subagents in `~/.pi/agent/agents`
- Secrets (`auth.json`, tokens, `telegram.json`)
- Disabled extensions (`*.disabled`)
- The `voice-spike.ts` prototype symlink
- These skills: `issue-validity-audit`, `linear-tickets`, `microsoft-foundry`, `moshi-best-practices`, `web-perf`, `terminal-browser`

Captured from Pi 0.84.4 on 2026-08-29. See `manifest.json` for the full inventory.
