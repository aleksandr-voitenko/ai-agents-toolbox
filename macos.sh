#!/usr/bin/env bash
set -euo pipefail

INSTALL_MISSING=0
UPGRADE_MANAGED=0
PATH_DISPLAY_WIDTH=48
VERSION_DISPLAY_MAX=80

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
curl|curl|curl
sqlite3|sqlite3|sqlite
yq|yq|yq
actionlint|actionlint|actionlint
typos|typos|typos-cli
clang-format|clang-format|clang-format
gh|gh|gh
git|git|git
git-delta|delta|git-delta
just|just|just
difftastic|difft|difftastic
node|node|node
yarn|yarn|yarn
python|python3,python|python
cmake|cmake|cmake
ninja|ninja|ninja
bat|bat|bat
eza|eza|eza
fzf|fzf|fzf
tree|tree|tree
file|file|libmagic
pandoc|pandoc|pandoc
imagemagick|magick,convert|imagemagick
ffmpeg|ffmpeg|ffmpeg
exiftool|exiftool|exiftool
hyperfine|hyperfine|hyperfine
shellcheck|shellcheck|shellcheck
shfmt|shfmt|shfmt
tar|tar,gtar|gnu-tar
zip|zip|zip
unzip|unzip|unzip
rsync|rsync|rsync
xxd|xxd|vim
stat|stat,gstat|coreutils
realpath|realpath,grealpath|coreutils
uv|uv|uv
pre-commit|pre-commit|pre-commit
ast-grep|ast-grep|ast-grep
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

uv_tool_dir_candidates() {
  if [ -n "${UV_TOOL_DIR:-}" ]; then
    printf '%s\n' "$UV_TOOL_DIR"
  fi
  if command -v uv >/dev/null 2>&1; then
    uv tool dir 2>/dev/null || true
  fi
  if [ -n "${HOME:-}" ]; then
    printf '%s\n' "$HOME/.local/share/uv/tools"
  fi
}

uv_tool_bin_dir_candidates() {
  if [ -n "${UV_TOOL_BIN_DIR:-}" ]; then
    printf '%s\n' "$UV_TOOL_BIN_DIR"
  fi
  if command -v uv >/dev/null 2>&1; then
    uv tool dir --bin 2>/dev/null || true
  fi
  if [ -n "${HOME:-}" ]; then
    printf '%s\n' "$HOME/.local/bin"
  fi
}

pre_commit_uv_tool_version() {
  local tool_dir metadata version

  while IFS= read -r tool_dir; do
    [ -n "$tool_dir" ] || continue
    for metadata in "$tool_dir"/pre-commit/lib/python*/site-packages/pre_commit-*.dist-info/METADATA; do
      [ -r "$metadata" ] || continue
      version="$(sed -n 's/^Version:[[:space:]]*//p' "$metadata" | head -n 1)"
      if [ -n "$version" ]; then
        printf '%s\n' "$version"
        return 0
      fi
    done
  done < <(uv_tool_dir_candidates)

  return 1
}

is_pre_commit_uv_tool() {
  local command_path="$1"
  local resolved command_dir uv_bin_dir resolved_uv_bin_dir

  pre_commit_uv_tool_version >/dev/null || return 1

  resolved="$(resolve_path "$command_path")"
  command_dir="$(dirname "$resolved")"

  while IFS= read -r uv_bin_dir; do
    [ -n "$uv_bin_dir" ] || continue
    resolved_uv_bin_dir="$(resolve_path "$uv_bin_dir")"
    if [ "$command_dir" = "$resolved_uv_bin_dir" ]; then
      return 0
    fi
  done < <(uv_tool_bin_dir_candidates)

  return 1
}

version_for() {
  local command_name="$1"
  case "$command_name" in
    gs)
      version_output "$command_name" --version
      ;;
    pdftotext)
      version_output "$command_name" -v
      ;;
    zip|unzip)
      version_output "$command_name" -v
      ;;
    ffmpeg)
      version_output "$command_name" -version
      ;;
    exiftool)
      version_output "$command_name" -ver
      ;;
    pre-commit)
      version_output "$command_name" --version || pre_commit_uv_tool_version
      ;;
    stat|realpath)
      version_output "$command_name" --version || printf '%s\n' "system utility; no version flag"
      ;;
    *)
      version_output "$command_name" --version
      ;;
  esac
}

version_output() {
  local output
  output="$("$@" 2>&1)" || return 1
  extract_version_from_output "$output"
}

extract_version_from_output() {
  local output="$1"
  local line fallback
  # Keep attached prefixes and suffixes like jq-1.7.1-apple or v1.2.3-main,
  # but discard surrounding banner text, URLs, dates, and build metadata.
  local version_pattern='(^|[^[:alnum:]_.-])(([[:alpha:]_]+-)?v?[0-9]+([.][0-9]+)+([-+][[:alnum:]][[:alnum:]._-]*)?)($|[^[:alnum:]_.-])'

  fallback=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$fallback" ] && [ -n "${line//[[:space:]]/}" ]; then
      fallback="$line"
    fi
    if [[ "$line" =~ $version_pattern ]]; then
      printf '%s\n' "${BASH_REMATCH[2]}"
      return 0
    fi
  done <<< "$output"

  if [ -n "$fallback" ]; then
    printf '%s\n' "$fallback"
  fi
  return 0
}

version_for_display() {
  local version="$1"
  if [ "${#version}" -le "$VERSION_DISPLAY_MAX" ]; then
    printf '%s' "$version"
    return 0
  fi

  printf '%s...' "${version:0:$((VERSION_DISPLAY_MAX - 3))}"
}

path_for_display() {
  local path="$1"
  local display="$path"
  local head_width=12
  local tail_width=$((PATH_DISPLAY_WIDTH - head_width - 3))
  local home_marker="~"
  local tail

  if [ -n "${HOME:-}" ]; then
    if [ "$display" = "$HOME" ]; then
      display="$home_marker"
    elif [ "${display#"$HOME"/}" != "$display" ]; then
      display="$home_marker/${display#"$HOME"/}"
    fi
  fi

  if [ "${#display}" -le "$PATH_DISPLAY_WIDTH" ]; then
    printf '%s' "$display"
    return 0
  fi

  tail="${display: -$tail_width}"
  if [ "${tail#*/}" != "$tail" ]; then
    tail="/${tail#*/}"
  fi
  printf '%s...%s' "${display:0:$head_width}" "$tail"
}

detect_source() {
  local command_path="$1"
  local resolved
  resolved="$(resolve_path "$command_path")"

  if [ "$(basename "$resolved")" = "pre-commit" ] && is_pre_commit_uv_tool "$resolved"; then
    printf 'uv:pre-commit'
    return 0
  fi

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
    "$HOME"/.nvm/versions/node/*/bin/*)
      printf 'nvm'
      ;;
    "$HOME"/.cargo/bin/*)
      printf 'cargo'
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

package_version_for_source() {
  local source="$1"
  local package version

  case "$source" in
    homebrew:*)
      package="${source#homebrew:}"
      if [ "$package" = "unknown" ] || [ -z "$BREW_BIN" ]; then
        return 1
      fi
      version="$(brew list --versions "$package" 2>/dev/null | head -n 1 || true)"
      if [ -n "$version" ]; then
        printf 'package version: %s' "$version"
        return 0
      fi
      ;;
    uv:pre-commit)
      version="$(pre_commit_uv_tool_version || true)"
      if [ -n "$version" ]; then
        printf 'package version: pre-commit %s' "$version"
        return 0
      fi
      ;;
  esac

  return 1
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

print_install_hint() {
  if [ -n "$BREW_BIN" ]; then
    cat <<'MSG'

To install missing tools with Homebrew, run:
  ./macos.sh --install-missing
MSG
  else
    print_brew_guidance
  fi
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
      version="$(package_version_for_source "$source" || true)"
      if [ -z "$version" ]; then
        version="version output empty"
      fi
    fi
  elif [ "$name" = "yarn" ] && [ "${source#homebrew:node}" != "$source" ]; then
    version="corepack shim; version is selected per project"
  else
    failed_version_count=$((failed_version_count + 1))
    version="version check failed"
  fi

  version_display="$(version_for_display "$version")"
  path_display="$(path_for_display "$command_path")"
  printf '[found]   %-14s %-48s %-22s %s\n' "$name" "$path_display" "$source" "$version_display"

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
    unknown|cargo|nvm|system|uv:*)
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
if [ "$missing_count" -gt 0 ] && [ "$INSTALL_MISSING" -eq 0 ]; then
  print_install_hint
fi
