#!/usr/bin/env bash
set -euo pipefail

INSTALL_MISSING=0
UPGRADE_MANAGED=0

usage() {
  cat <<'MSG'
Usage:
  ./macos.sh [options]

Options:
  --check-only        Check tools and report status. This is the default.
  --install-missing  Install missing tools using Homebrew, if Homebrew exists.
  --upgrade-managed  Upgrade tools already managed by Homebrew only.
  -h, --help         Show this help.

This script never installs Homebrew. If Homebrew is missing, it prints guidance.
Existing commands from unknown or non-Homebrew sources are not replaced.
MSG
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-only)
      INSTALL_MISSING=0
      UPGRADE_MANAGED=0
      ;;
    --install-missing)
      INSTALL_MISSING=1
      ;;
    --upgrade-managed)
      UPGRADE_MANAGED=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

TOOLS=$(cat <<'EOF'
ripgrep|rg|ripgrep
fd|fd|fd
jq|jq|jq
clang-format|clang-format|clang-format
gh|gh|gh
git|git|git
node|node|node
yarn|yarn|yarn
python|python3,python|python
cmake|cmake|cmake
ninja|ninja|ninja
bat|bat|bat
eza|eza|eza
fzf|fzf|fzf
tree|tree|tree
hyperfine|hyperfine|hyperfine
shellcheck|shellcheck|shellcheck
shfmt|shfmt|shfmt
ghostscript|gs|ghostscript
pdftotext|pdftotext|poppler
EOF
)

BREW_BIN=""
BREW_PREFIX=""
if command -v brew >/dev/null 2>&1; then
  BREW_BIN="$(command -v brew)"
  BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
fi

find_command() {
  local commands="$1"
  local candidate
  IFS=',' read -r -a candidates <<< "$commands"
  for candidate in "${candidates[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_path() {
  local input="$1"
  if command -v perl >/dev/null 2>&1; then
    perl -MCwd=realpath -e 'print realpath($ARGV[0]) || $ARGV[0]' "$input" 2>/dev/null || printf '%s' "$input"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$input" 2>/dev/null || printf '%s' "$input"
  else
    printf '%s' "$input"
  fi
}

version_for() {
  local command_name="$1"
  case "$command_name" in
    gs)
      "$command_name" --version 2>&1 | head -n 1
      ;;
    pdftotext)
      "$command_name" -v 2>&1 | head -n 1
      ;;
    *)
      "$command_name" --version 2>&1 | head -n 1
      ;;
  esac
}

detect_source() {
  local command_path="$1"
  local resolved
  resolved="$(resolve_path "$command_path")"

  if [ -n "$BREW_PREFIX" ]; then
    case "$resolved" in
      "$BREW_PREFIX"/Cellar/*)
        local formula="${resolved#"$BREW_PREFIX"/Cellar/}"
        formula="${formula%%/*}"
        printf 'homebrew:%s' "$formula"
        return 0
        ;;
      "$BREW_PREFIX"/*)
        printf 'homebrew:unknown'
        return 0
        ;;
    esac
  fi

  case "$resolved" in
    /usr/bin/*|/bin/*|/usr/sbin/*|/sbin/*)
      printf 'system'
      ;;
    "$HOME"/.cargo/bin/*)
      printf 'cargo'
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

print_brew_guidance() {
  cat <<'MSG'

Homebrew was not found, so missing tools cannot be installed automatically.

Install Homebrew from:
  https://brew.sh/

Then rerun:
  ./macos.sh --install-missing
MSG
}

brew_install() {
  local package="$1"
  echo "Installing $package with Homebrew..."
  brew install "$package"
}

brew_upgrade_if_outdated() {
  local package="$1"
  if [ -n "$(brew outdated --quiet "$package" 2>/dev/null || true)" ]; then
    echo "Upgrading $package with Homebrew..."
    brew upgrade "$package"
  else
    echo "Already current according to Homebrew: $package"
  fi
}

missing_count=0
unmanaged_count=0
failed_version_count=0

echo "Checking developer tools for macOS..."
echo

while IFS='|' read -r name commands brew_package; do
  [ -z "$name" ] && continue

  command_path="$(find_command "$commands" || true)"

  if [ -z "$command_path" ]; then
    missing_count=$((missing_count + 1))
    printf '[missing] %-14s package: %s\n' "$name" "$brew_package"

    if [ "$INSTALL_MISSING" -eq 1 ]; then
      if [ -z "$BREW_BIN" ]; then
        continue
      fi
      brew_install "$brew_package"
    fi
    continue
  fi

  actual_command="$(basename "$command_path")"
  source="$(detect_source "$command_path")"
  if version="$(version_for "$actual_command")"; then
    if [ -z "$version" ]; then
      version="version output empty"
    fi
  elif [ "$name" = "yarn" ] && [ "${source#homebrew:node}" != "$source" ]; then
    version="corepack shim; version is selected per project"
  else
    failed_version_count=$((failed_version_count + 1))
    version="version check failed"
  fi

  printf '[found]   %-14s %-36s %-22s %s\n' "$name" "$command_path" "$source" "$version"

  case "$source" in
    homebrew:*)
      if [ "$UPGRADE_MANAGED" -eq 1 ]; then
        managed_package="${source#homebrew:}"
        if [ "$managed_package" = "unknown" ]; then
          echo "  skip upgrade: Homebrew path detected, but owning formula is unknown."
        else
          brew_upgrade_if_outdated "$managed_package"
        fi
      fi
      ;;
    unknown|cargo|system)
      if [ "$UPGRADE_MANAGED" -eq 1 ]; then
        unmanaged_count=$((unmanaged_count + 1))
        echo "  skip upgrade: existing command is not managed by Homebrew."
      fi
      ;;
  esac
done <<< "$TOOLS"

if [ "$INSTALL_MISSING" -eq 1 ] && [ "$missing_count" -gt 0 ] && [ -z "$BREW_BIN" ]; then
  print_brew_guidance
fi

echo
echo "Summary:"
echo "  Missing before install: $missing_count"
echo "  Version checks failed:  $failed_version_count"
if [ "$UPGRADE_MANAGED" -eq 1 ]; then
  echo "  Unmanaged upgrades skipped: $unmanaged_count"
fi
