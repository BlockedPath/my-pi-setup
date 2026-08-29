#!/usr/bin/env bash
# Restore this Pi setup onto the current machine.
# Idempotent: already-installed packages and existing skill clones are skipped
# unless --force is passed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:?HOME is not set}"
PI_AGENT="${HOME_DIR}/.pi/agent"
PI_SKILLS="${PI_AGENT}/skills"
PI_EXT="${PI_AGENT}/extensions"
PI_THEMES="${PI_AGENT}/themes"
PI_NPM="${PI_AGENT}/npm"
AGENTS_SKILLS="${HOME_DIR}/.agents/skills"
PACKAGES_FILE="${ROOT}/packages.txt"
NPM_EXTRAS="${ROOT}/npm-extras.json"
HERDR_REPO="https://github.com/ogulcancelik/herdr.git"

DRY_RUN=0
FORCE=0
INSTALLED_COUNT=0
SKIPPED_COUNT=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--force]

  --dry-run   Print actions without changing the machine
  --force     Re-run pi install for every package and re-clone herdr
  -h, --help  Show this help

On a new machine:
  1. Clone this repo
  2. ./prereqs.sh --install     (or prereqs.ps1 -Install on Windows)
  3. ./install.sh
  4. Start a new Pi session and log in to providers
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

log() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '    dry-run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' is required but not in PATH" >&2
    exit 1
  fi
}

is_package_installed() {
  local spec="$1"
  printf '%s\n' "$INSTALLED_LIST" | awk '$1 ~ /^npm:/ { print $1 }' | grep -Fqx "$spec"
}

need_cmd pi
need_cmd git
need_cmd python3

if [[ ! -f "$PACKAGES_FILE" ]]; then
  echo "error: missing $PACKAGES_FILE" >&2
  exit 1
fi

log "checking already-installed packages"
INSTALLED_LIST="$(pi list 2>/dev/null || true)"

log "installing Pi packages"
while IFS= read -r raw || [[ -n "$raw" ]]; do
  spec="${raw%%#*}"
  spec="${spec#"${spec%%[![:space:]]*}"}"
  spec="${spec%"${spec##*[![:space:]]}"}"
  [[ -z "$spec" ]] && continue

  if [[ "$FORCE" -eq 0 ]] && is_package_installed "$spec"; then
    note "skip $spec (already installed)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  log "pi install $spec"
  run pi install "$spec"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
done < "$PACKAGES_FILE"

if [[ -f "$NPM_EXTRAS" ]]; then
  log "merging npm extras into ~/.pi/agent/npm/package.json"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    note "dry-run: would merge $NPM_EXTRAS"
  else
    python3 - "$NPM_EXTRAS" "$PI_NPM/package.json" <<'PY'
import json, pathlib, sys

extras_path = pathlib.Path(sys.argv[1])
pkg_path = pathlib.Path(sys.argv[2])
extras = json.loads(extras_path.read_text())
pkg_path.parent.mkdir(parents=True, exist_ok=True)
if pkg_path.exists():
    data = json.loads(pkg_path.read_text())
else:
    data = {"name": "pi-extensions", "private": True}
if extras.get("overrides"):
    data["overrides"] = extras["overrides"]
pkg_path.write_text(json.dumps(data, indent=2) + "\n")
PY
    mkdir -p "$PI_NPM"
    if [[ ! -f "$PI_NPM/.npmrc" ]]; then
      printf 'legacy-peer-deps=true\n' > "$PI_NPM/.npmrc"
    fi
  fi
fi

log "installing herdr skill"
run mkdir -p "$AGENTS_SKILLS"
HERDR_DEST="${AGENTS_SKILLS}/herdr"
if [[ -e "$HERDR_DEST" && "$FORCE" -eq 0 ]]; then
  note "skip herdr (already present at $HERDR_DEST)"
else
  if [[ "$FORCE" -eq 1 && -e "$HERDR_DEST" ]]; then
    run rm -rf "$HERDR_DEST"
  fi
  run git clone --depth 1 "$HERDR_REPO" "$HERDR_DEST"
fi

log "installing herdr-multi-agent-orch skill"
ORCH_SRC="${ROOT}/skills/herdr-multi-agent-orch"
ORCH_DEST="${AGENTS_SKILLS}/herdr-multi-agent-orch"
run mkdir -p "${ORCH_DEST}/references"
run cp "${ORCH_SRC}/SKILL.md" "${ORCH_DEST}/SKILL.md"
run cp "${ORCH_SRC}/references/"*.md "${ORCH_DEST}/references/"

log "linking skills into ~/.pi/agent/skills"
run mkdir -p "$PI_SKILLS"
if [[ "$DRY_RUN" -eq 1 ]]; then
  note "dry-run: ln -sfn ../../../.agents/skills/herdr ${PI_SKILLS}/herdr"
  note "dry-run: ln -sfn ../../../.agents/skills/herdr-multi-agent-orch ${PI_SKILLS}/herdr-multi-agent-orch"
else
  ln -sfn ../../../.agents/skills/herdr "${PI_SKILLS}/herdr"
  ln -sfn ../../../.agents/skills/herdr-multi-agent-orch "${PI_SKILLS}/herdr-multi-agent-orch"
fi

log "copying custom extensions"
run mkdir -p "${PI_EXT}/muse-voice"
run cp "${ROOT}/extensions/herdr-agent-state.ts" "${PI_EXT}/"
run cp "${ROOT}/extensions/moshi-hooks.ts" "${PI_EXT}/"
run cp "${ROOT}/extensions/pi-footer.json" "${PI_EXT}/"
run cp "${ROOT}/extensions/muse-voice/"* "${PI_EXT}/muse-voice/"

log "copying themes"
run mkdir -p "$PI_THEMES"
run cp "${ROOT}/themes/"*.json "${PI_THEMES}/"

log "done"
note "packages installed this run: ${INSTALLED_COUNT}"
note "packages already present:   ${SKIPPED_COUNT}"
note "start a new Pi session so extensions, skills, and themes load"
note "log in to providers separately — this repo does not include secrets"
