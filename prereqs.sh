#!/usr/bin/env bash
# Check (default) or install (--install) OS prerequisites for my-pi-setup.
# Supports Ubuntu/Debian (and WSL), macOS, and Windows Git Bash.
set -euo pipefail

MIN_NODE="22.19.0"
NVM_VERSION="v0.40.3"
PI_PKG="@earendil-works/pi-coding-agent"

INSTALL=0
YES=0
OPTIONAL=0

usage() {
  cat <<'EOF'
Usage: ./prereqs.sh [--check] [--install] [--yes] [--optional]

  --check      Report missing tools (default)
  --install    Install anything that is missing
  --yes        Non-interactive (apt/winget/nvm, no confirm)
  --optional   Also install clipboard helpers on Linux (xclip)
  -h, --help   Show this help

Ubuntu/Debian/WSL and macOS: run this script, then ./install.sh
Windows without Git Bash: run prereqs.ps1 from PowerShell first.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --check)
    INSTALL=0
    shift
    ;;
  --install)
    INSTALL=1
    shift
    ;;
  --yes | -y)
    YES=1
    shift
    ;;
  --optional)
    OPTIONAL=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

OS="unknown"
WSL=0
uname_s="$(uname -s 2>/dev/null || echo unknown)"
case "$uname_s" in
Darwin) OS="macos" ;;
Linux)
  if grep -qi microsoft /proc/version 2>/dev/null; then WSL=1; fi
  if command -v apt-get >/dev/null 2>&1; then
    OS="debian"
  else
    OS="linux"
  fi
  ;;
MINGW* | MSYS* | CYGWIN*) OS="windows" ;;
*) OS="unknown" ;;
esac

ok() { printf '  [ok]  %s\n' "$*"; }
bad() { printf '  [!!]  %s\n' "$*"; }
note() { printf '        %s\n' "$*"; }

MISSING=()
mark_missing() { MISSING+=("$1"); }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

version_ge() {
  # return 0 if $1 >= $2 (dotted numeric, optional leading v)
  local a="${1#v}" b="${2#v}"
  local IFS=.
  # shellcheck disable=SC2206
  local av=($a) bv=($b)
  local i
  for i in 0 1 2; do
    local ai="${av[i]:-0}" bi="${bv[i]:-0}"
    ai="${ai%%[^0-9]*}"
    bi="${bi%%[^0-9]*}"
    ai="${ai:-0}"
    bi="${bi:-0}"
    if ((ai > bi)); then return 0; fi
    if ((ai < bi)); then return 1; fi
  done
  return 0
}

confirm() {
  local prompt="$1"
  if [[ "$YES" -eq 1 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then
    echo "error: refusing to install without --yes in a non-interactive shell" >&2
    return 1
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]
}

load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    return 0
  fi
  return 1
}

node_version() {
  if have_cmd node; then
    node -v 2>/dev/null || true
  fi
}

check_git() {
  if have_cmd git; then
    ok "git $(git --version | awk '{print $3}')"
  else
    bad "git — not found"
    mark_missing git
  fi
}

check_python() {
  if have_cmd python3; then
    ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"
  elif have_cmd python; then
    ok "python $(python --version 2>&1 | awk '{print $2}')"
  else
    bad "python3 — not found"
    mark_missing python3
  fi
}

check_curl() {
  if have_cmd curl; then
    ok "curl"
  else
    bad "curl — not found"
    mark_missing curl
  fi
}

check_compiler() {
  case "$OS" in
  debian)
    if have_cmd cc && have_cmd make; then
      ok "C toolchain (cc, make)"
    else
      bad "C toolchain — need build-essential (cc + make)"
      mark_missing build-essential
    fi
    ;;
  macos)
    if xcode-select -p >/dev/null 2>&1 && have_cmd cc; then
      ok "Xcode Command Line Tools"
    else
      bad "Xcode Command Line Tools — not installed"
      mark_missing xcode-clt
    fi
    ;;
  windows)
    if have_cmd cl || have_cmd clang || [[ -n "${VSINSTALLDIR:-}" ]]; then
      ok "C toolchain"
    elif have_cmd vswhere && vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath >/dev/null 2>&1; then
      ok "Visual Studio C++ tools"
    else
      bad "C toolchain — install Visual Studio Build Tools (Desktop development with C++)"
      mark_missing vs-build-tools
    fi
    ;;
  *)
    if have_cmd cc && have_cmd make; then
      ok "C toolchain (cc, make)"
    else
      bad "C toolchain — need a C compiler and make"
      mark_missing compiler
    fi
    ;;
  esac
}

check_node() {
  load_nvm >/dev/null 2>&1 || true
  local ver
  ver="$(node_version)"
  if [[ -z "$ver" ]]; then
    bad "Node.js — not found (need >= ${MIN_NODE})"
    mark_missing node
    return
  fi
  if version_ge "${ver#v}" "$MIN_NODE"; then
    ok "Node.js $ver"
  else
    bad "Node.js $ver — too old (need >= ${MIN_NODE})"
    mark_missing node
  fi
}

check_npm() {
  if have_cmd npm; then
    ok "npm $(npm -v 2>/dev/null || echo '?')"
  else
    bad "npm — not found"
    mark_missing npm
  fi
}

check_pi() {
  if have_cmd pi; then
    ok "pi $(pi --version 2>/dev/null | head -1 || echo 'installed')"
  else
    bad "pi — not found (npm i -g ${PI_PKG})"
    mark_missing pi
  fi
}

install_debian() {
  local pkgs=()
  local item
  for item in "${MISSING[@]+"${MISSING[@]}"}"; do
    case "$item" in
    git) pkgs+=(git) ;;
    python3) pkgs+=(python3) ;;
    curl) pkgs+=(curl ca-certificates) ;;
    build-essential) pkgs+=(build-essential pkg-config) ;;
    esac
  done
  if [[ "$OPTIONAL" -eq 1 ]]; then
    pkgs+=(xclip)
  fi
  if [[ ${#pkgs[@]} -gt 0 ]]; then
    note "apt install: ${pkgs[*]}"
    if confirm "Install apt packages with sudo?"; then
      sudo apt-get update
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    else
      echo "error: apt install declined" >&2
      exit 1
    fi
  fi
}

install_macos_system() {
  local item
  for item in "${MISSING[@]+"${MISSING[@]}"}"; do
    case "$item" in
    xcode-clt)
      note "opening Xcode Command Line Tools installer (GUI prompt)"
      xcode-select --install || true
      echo "Finish the CLT installer window, then re-run: ./prereqs.sh --install"
      ;;
    git | python3 | curl)
      if have_cmd brew; then
        if confirm "Install $item with Homebrew?"; then
          brew install "$item"
        fi
      else
        note "$item is normally provided by Xcode CLT. Install CLT, or install Homebrew."
      fi
      ;;
    esac
  done
}

install_windows_system() {
  if ! have_cmd winget; then
    echo "error: winget not found. Install App Installer from the Microsoft Store, or run prereqs.ps1 in PowerShell." >&2
    exit 1
  fi
  local item
  for item in "${MISSING[@]+"${MISSING[@]}"}"; do
    case "$item" in
    git)
      note "winget install Git.Git"
      winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
      ;;
    python3)
      note "winget install Python.Python.3.12"
      winget install --id Python.Python.3.12 -e --source winget --accept-package-agreements --accept-source-agreements
      ;;
    vs-build-tools)
      note "winget install Visual Studio 2022 Build Tools (large)"
      if confirm "Install Visual Studio Build Tools with C++ workload?"; then
        winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget \
          --accept-package-agreements --accept-source-agreements \
          --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
      fi
      ;;
    node | npm)
      note "winget install OpenJS.NodeJS.LTS"
      winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements
      ;;
    esac
  done
}

install_node_nvm() {
  if [[ "$OS" == "windows" ]]; then
    return 0
  fi
  if ! have_cmd curl; then
    echo "error: curl is required to install nvm" >&2
    exit 1
  fi
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    note "installing nvm ${NVM_VERSION}"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  fi
  load_nvm
  note "nvm install 22"
  nvm install 22
  nvm alias default 22
  nvm use 22
  hash -r || true
}

install_pi() {
  if ! have_cmd npm; then
    echo "error: npm is required to install pi" >&2
    exit 1
  fi
  note "npm install -g --ignore-scripts ${PI_PKG}"
  npm install -g --ignore-scripts "$PI_PKG"
  hash -r || true
}

printf 'OS: %s%s\n' "$OS" "$([[ "$WSL" -eq 1 ]] && echo ' (WSL)' || true)"
printf 'Mode: %s\n\n' "$([[ "$INSTALL" -eq 1 ]] && echo install || echo check)"
printf 'Checking prerequisites (Node >= %s)...\n' "$MIN_NODE"

check_curl
check_git
check_python
check_compiler
check_node
check_npm
check_pi

if [[ ${#MISSING[@]} -eq 0 ]]; then
  printf '\nAll prerequisites are present. Next: ./install.sh\n'
  exit 0
fi

printf '\nMissing: %s\n' "${MISSING[*]}"

if [[ "$INSTALL" -eq 0 ]]; then
  printf '\nInstall them with:\n  ./prereqs.sh --install\n'
  if [[ "$OS" == "windows" ]] && ! have_cmd git; then
    printf 'On Windows without Git Bash, use PowerShell:\n  powershell -ExecutionPolicy Bypass -File .\\prereqs.ps1 -Install\n'
  fi
  exit 1
fi

printf '\nInstalling missing prerequisites...\n'

case "$OS" in
debian) install_debian ;;
macos) install_macos_system ;;
windows) install_windows_system ;;
linux)
  echo "error: this Linux distro has no apt-get. Install git, python3, curl, make, a C compiler, and Node ${MIN_NODE}+ yourself, then re-run." >&2
  exit 1
  ;;
*)
  echo "error: unsupported OS ($uname_s)" >&2
  exit 1
  ;;
esac

# Re-check node after system packages / winget
hash -r || true
load_nvm >/dev/null 2>&1 || true
NEED_NODE=0
ver="$(node_version)"
if [[ -z "$ver" ]] || ! version_ge "${ver#v}" "$MIN_NODE"; then
  NEED_NODE=1
fi
if [[ "$NEED_NODE" -eq 1 ]]; then
  if [[ "$OS" == "windows" ]]; then
    note "Node is still missing/old. Open a new Git Bash after winget, or install Node 22 LTS from https://nodejs.org/"
  else
    install_node_nvm
  fi
fi

hash -r || true
if ! have_cmd pi; then
  install_pi
fi

printf '\nRe-checking...\n'
MISSING=()
check_curl
check_git
check_python
check_compiler
check_node
check_npm
check_pi

if [[ ${#MISSING[@]} -eq 0 ]]; then
  printf '\nAll prerequisites are present. Next: ./install.sh\n'
  exit 0
fi

printf '\nStill missing: %s\n' "${MISSING[*]}"
printf 'Open a new terminal (PATH changes) and re-run ./prereqs.sh\n'
if [[ "$OS" == "macos" ]]; then
  printf 'If Xcode CLT was just triggered, finish that GUI installer first.\n'
fi
exit 1
