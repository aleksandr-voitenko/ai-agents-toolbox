#!/usr/bin/env bash
set -euo pipefail

INSTALL_MISSING=0
UPGRADE_MANAGED=0
PREFERRED_MANAGER="auto"

usage() {
  cat <<'MSG'
Usage:
  ./linux.sh [options]

Options:
  --check-only             Check tools and report status. This is the default.
  --install-missing       Install missing tools using an existing package manager.
  --upgrade-managed       Upgrade tools already managed by the same package manager only.
  --manager NAME          Use apt, dnf, pacman, or zypper for missing installs.
  -h, --help              Show this help.

This script never installs a package manager. If no supported package manager is
available, it prints guidance. Existing commands from unknown/manual sources are
not replaced.
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
    --manager)
      shift
      if [ "$#" -eq 0 ]; then
        echo "--manager requires a value" >&2
        exit 2
      fi
      PREFERRED_MANAGER="$1"
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
ripgrep|rg|ripgrep|ripgrep|ripgrep|ripgrep
fd|fd,fdfind|fd-find|fd-find|fd|fd
jq|jq|jq|jq|jq|jq
clang-format|clang-format|clang-format|clang-tools-extra|clang|clang-tools
gh|gh|gh|gh|github-cli|gh
git|git|git|git|git|git
node|node,nodejs|nodejs|nodejs|nodejs|nodejs
yarn|yarn,yarnpkg|yarnpkg|yarnpkg|yarn|yarn
python|python3,python|python3|python3|python|python3
cmake|cmake|cmake|cmake|cmake|cmake
ninja|ninja,ninja-build|ninja-build|ninja-build|ninja|ninja
bat|bat,batcat|bat|bat|bat|bat
eza|eza|eza|eza|eza|eza
fzf|fzf|fzf|fzf|fzf|fzf
tree|tree|tree|tree|tree|tree
hyperfine|hyperfine|hyperfine|hyperfine|hyperfine|hyperfine
shellcheck|shellcheck|shellcheck|ShellCheck|shellcheck|ShellCheck
shfmt|shfmt|shfmt|shfmt|shfmt|shfmt
ghostscript|gs|ghostscript|ghostscript|ghostscript|ghostscript
pdftotext|pdftotext|poppler-utils|poppler-utils|poppler|poppler-tools
EOF
)

have() {
  command -v "$1" >/dev/null 2>&1
}

detect_manager() {
  if [ "$PREFERRED_MANAGER" != "auto" ]; then
    if have "$PREFERRED_MANAGER" || { [ "$PREFERRED_MANAGER" = "apt" ] && have apt-get; }; then
      printf '%s' "$PREFERRED_MANAGER"
      return 0
    fi
    echo "Requested package manager is not available: $PREFERRED_MANAGER" >&2
    return 1
  fi

  if have apt-get; then printf 'apt'; return 0; fi
  if have dnf; then printf 'dnf'; return 0; fi
  if have pacman; then printf 'pacman'; return 0; fi
  if have zypper; then printf 'zypper'; return 0; fi
  return 1
}

PACKAGE_MANAGER="$(detect_manager || true)"

run_elevated() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    echo "sudo is required for package installation, but sudo was not found." >&2
    return 1
  fi
}

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
  local resolved="$command_path"
  if have readlink; then
    resolved="$(readlink -f "$command_path" 2>/dev/null || printf '%s' "$command_path")"
  fi

  if have dpkg; then
    local dpkg_owner
    dpkg_owner="$(dpkg -S "$resolved" 2>/dev/null | head -n 1 | cut -d: -f1 || true)"
    if [ -n "$dpkg_owner" ]; then
      printf 'apt:%s' "$dpkg_owner"
      return 0
    fi
  fi

  if have rpm; then
    local rpm_owner
    rpm_owner="$(rpm -qf "$resolved" 2>/dev/null || true)"
    if [ -n "$rpm_owner" ] && [ "${rpm_owner#file }" = "$rpm_owner" ]; then
      printf 'rpm:%s' "$rpm_owner"
      return 0
    fi
  fi

  if have pacman; then
    local pacman_owner
    pacman_owner="$(pacman -Qo "$resolved" 2>/dev/null | sed -n 's/.* is owned by \([^ ]*\) .*/\1/p' || true)"
    if [ -n "$pacman_owner" ]; then
      printf 'pacman:%s' "$pacman_owner"
      return 0
    fi
  fi

  case "$resolved" in
    /snap/*|/var/lib/snapd/*)
      printf 'snap'
      ;;
    "$HOME"/.cargo/bin/*)
      printf 'cargo'
      ;;
    "$HOME"/.local/bin/*)
      printf 'local'
      ;;
    /usr/bin/*|/bin/*|/usr/sbin/*|/sbin/*)
      printf 'system'
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

package_for_manager() {
  local manager="$1"
  local apt_pkg="$2"
  local dnf_pkg="$3"
  local pacman_pkg="$4"
  local zypper_pkg="$5"
  case "$manager" in
    apt) printf '%s' "$apt_pkg" ;;
    dnf) printf '%s' "$dnf_pkg" ;;
    pacman) printf '%s' "$pacman_pkg" ;;
    zypper) printf '%s' "$zypper_pkg" ;;
    *) return 1 ;;
  esac
}

install_package() {
  local manager="$1"
  local package="$2"

  echo "Installing $package with $manager..."
  case "$manager" in
    apt)
      run_elevated apt-get install -y "$package"
      ;;
    dnf)
      run_elevated dnf install -y "$package"
      ;;
    pacman)
      run_elevated pacman -S --needed --noconfirm "$package"
      ;;
    zypper)
      run_elevated zypper install -y "$package"
      ;;
    *)
      echo "Unsupported package manager: $manager" >&2
      return 1
      ;;
  esac
}

upgrade_source() {
  local source="$1"
  local manager="${source%%:*}"
  local package="${source#*:}"

  echo "Upgrading $package with $manager..."
  case "$manager" in
    apt)
      run_elevated apt-get install --only-upgrade -y "$package"
      ;;
    rpm)
      if have dnf; then
        run_elevated dnf upgrade -y "$package"
      elif have zypper; then
        run_elevated zypper update -y "$package"
      else
        echo "  skip upgrade: rpm package found, but dnf/zypper is unavailable."
      fi
      ;;
    pacman)
      run_elevated pacman -S --needed --noconfirm "$package"
      ;;
  esac
}

print_manager_guidance() {
  cat <<'MSG'

No supported Linux package manager was found.

Supported package managers:
  apt      Debian and Ubuntu
  dnf      Fedora and RHEL-family distributions
  pacman   Arch Linux
  zypper   openSUSE

Install or enable your distribution package manager, then rerun this script.
MSG
}

missing_count=0
unmanaged_count=0
failed_version_count=0

echo "Checking developer tools for Linux..."
if [ -n "$PACKAGE_MANAGER" ]; then
  echo "Detected package manager: $PACKAGE_MANAGER"
else
  echo "Detected package manager: none"
fi
echo

while IFS='|' read -r name commands apt_pkg dnf_pkg pacman_pkg zypper_pkg; do
  [ -z "$name" ] && continue

  command_path="$(find_command "$commands" || true)"

  if [ -z "$command_path" ]; then
    missing_count=$((missing_count + 1))
    printf '[missing] %-14s' "$name"

    if [ -n "$PACKAGE_MANAGER" ]; then
      package="$(package_for_manager "$PACKAGE_MANAGER" "$apt_pkg" "$dnf_pkg" "$pacman_pkg" "$zypper_pkg" || true)"
      printf ' package: %s\n' "$package"
      if [ "$INSTALL_MISSING" -eq 1 ]; then
        install_package "$PACKAGE_MANAGER" "$package"
      fi
    else
      printf ' package: unknown, no supported manager\n'
    fi
    continue
  fi

  actual_command="$(basename "$command_path")"
  source="$(detect_source "$command_path")"
  if version="$(version_for "$actual_command")" && [ -n "$version" ]; then
    :
  elif [ "$name" = "yarn" ] && { [ "$source" = "npm-or-node" ] || [ "${source#apt:node}" != "$source" ] || [ "${source#rpm:node}" != "$source" ] || [ "${source#pacman:node}" != "$source" ]; }; then
    version="corepack shim; version is selected per project"
  else
    failed_version_count=$((failed_version_count + 1))
    version="version check failed"
  fi

  printf '[found]   %-14s %-36s %-22s %s\n' "$name" "$command_path" "$source" "$version"

  case "$source" in
    apt:*|rpm:*|pacman:*)
      if [ "$UPGRADE_MANAGED" -eq 1 ]; then
        upgrade_source "$source"
      fi
      ;;
    *)
      if [ "$UPGRADE_MANAGED" -eq 1 ]; then
        unmanaged_count=$((unmanaged_count + 1))
        echo "  skip upgrade: existing command is not owned by apt, rpm, or pacman."
      fi
      ;;
  esac
done <<< "$TOOLS"

if [ "$INSTALL_MISSING" -eq 1 ] && [ "$missing_count" -gt 0 ] && [ -z "$PACKAGE_MANAGER" ]; then
  print_manager_guidance
fi

echo
echo "Summary:"
echo "  Missing before install: $missing_count"
echo "  Version checks failed:  $failed_version_count"
if [ "$UPGRADE_MANAGED" -eq 1 ]; then
  echo "  Unmanaged upgrades skipped: $unmanaged_count"
fi
