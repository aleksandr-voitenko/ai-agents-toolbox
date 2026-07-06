#!/usr/bin/env bash
set -euo pipefail

INSTALL_MISSING=0
UPGRADE_MANAGED=0
PREFERRED_MANAGER="auto"
PATH_DISPLAY_WIDTH=48
VERSION_DISPLAY_MAX=80

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
curl|curl|curl|curl|curl|curl
sqlite3|sqlite3|sqlite3|sqlite|sqlite|sqlite3
yq|yq|yq|yq|yq|yq
actionlint|actionlint|github-release:actionlint|github-release:actionlint|actionlint|github-release:actionlint
typos|typos|github-release:typos|github-release:typos|typos|github-release:typos
clang-format|clang-format|clang-format|clang-tools-extra|clang|clang-tools
gh|gh|gh|gh|github-cli|gh
git|git|git|git|git|git
git-delta|delta|git-delta|git-delta|git-delta|git-delta
just|just|just|just|just|just
difftastic|difft|github-release:difftastic|difftastic|difftastic|difftastic
node|node,nodejs|nodejs|nodejs|nodejs|nodejs
yarn|yarn,yarnpkg|yarnpkg|yarnpkg|yarn|yarn
python|python3,python|python3|python3|python|python3
cmake|cmake|cmake|cmake|cmake|cmake
ninja|ninja,ninja-build|ninja-build|ninja-build|ninja|ninja
bat|bat,batcat|bat|bat|bat|bat
eza|eza|eza|eza|eza|eza
fzf|fzf|fzf|fzf|fzf|fzf
tree|tree|tree|tree|tree|tree
file|file|file|file|file|file
pandoc|pandoc|pandoc|pandoc-cli|pandoc-cli|pandoc-cli
imagemagick|magick,convert|imagemagick|ImageMagick|imagemagick|ImageMagick
ffmpeg|ffmpeg|ffmpeg|ffmpeg-free|ffmpeg|ffmpeg-8
exiftool|exiftool,vendor_perl/exiftool|libimage-exiftool-perl|perl-Image-ExifTool|perl-image-exiftool|exiftool
hyperfine|hyperfine|hyperfine|hyperfine|hyperfine|hyperfine
shellcheck|shellcheck|shellcheck|ShellCheck|shellcheck|ShellCheck
shfmt|shfmt|shfmt|shfmt|shfmt|shfmt
tar|tar|tar|tar|tar|tar
zip|zip|zip|zip|zip|zip
unzip|unzip|unzip|unzip|unzip|unzip
rsync|rsync|rsync|rsync|rsync|rsync
xxd|xxd|xxd|xxd|vim|vim
hexdump|hexdump|bsdextrautils|util-linux|util-linux|util-linux
stat|stat|coreutils|coreutils|coreutils|coreutils
realpath|realpath|coreutils|coreutils|coreutils|coreutils
uv|uv|github-release:uv|uv|uv|github-release:uv
pre-commit|pre-commit|pre-commit|pre-commit|pre-commit|uv-tool:pre-commit
ast-grep|ast-grep|github-release:ast-grep|github-release:ast-grep|ast-grep|github-release:ast-grep
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

run_package_command() {
  # Package managers may prompt or otherwise read stdin; keep them from
  # consuming the tool list that feeds the main loop.
  if [ "$1" = "apt-get" ]; then
    run_elevated env DEBIAN_FRONTEND=noninteractive "$@" </dev/null
  else
    run_elevated "$@" </dev/null
  fi
}

find_command() {
  local commands="$1"
  local candidate path_dir
  local -a candidates path_dirs
  IFS=',' read -r -a candidates <<< "$commands"
  for candidate in "${candidates[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
    # Arch and openSUSE Perl packages can place executables under a
    # path-qualified vendor_perl directory inside a normal PATH entry.
    case "$candidate" in
      */*)
        if [ "${candidate#/}" = "$candidate" ]; then
          IFS=':' read -r -a path_dirs <<< "$PATH"
          for path_dir in "${path_dirs[@]}"; do
            [ -n "$path_dir" ] || path_dir="."
            if [ -x "$path_dir/$candidate" ]; then
              printf '%s\n' "$path_dir/$candidate"
              return 0
            fi
          done
        fi
        ;;
    esac
  done
  return 1
}

version_output() {
  local output
  output="$("$@" 2>&1)" || return 1
  extract_version_from_output "$output"
}

pre_commit_uv_tool_version() {
  local tool_dir="${UV_TOOL_DIR:-/usr/local/share/uv/tools}"
  local metadata version

  for metadata in "$tool_dir"/pre-commit/lib/python*/site-packages/pre_commit-*.dist-info/METADATA; do
    [ -r "$metadata" ] || continue
    version="$(sed -n 's/^Version:[[:space:]]*//p' "$metadata" | head -n 1)"
    if [ -n "$version" ]; then
      printf '%s\n' "$version"
      return 0
    fi
  done

  return 1
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

version_for() {
  local command_name="$1"
  local command_base
  command_base="$(basename "$command_name")"
  case "$command_base" in
    gs)
      version_output "$command_name" --version
      ;;
    pdftotext)
      version_output "$command_name" -v
      ;;
    zip|unzip)
      version_output "$command_name" -v
      ;;
    shfmt)
      version_output "$command_name" -version
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
    hexdump|stat|realpath)
      version_output "$command_name" --version || printf '%s\n' "system utility; no version flag"
      ;;
    *)
      version_output "$command_name" --version
      ;;
  esac
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

package_version_for_source() {
  local source="$1"
  local command_path="$2"
  local package version

  case "$source" in
    apt:*)
      package="${source#apt:}"
      if have dpkg-query; then
        version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)"
        if [ -n "$version" ]; then
          printf 'package version: %s %s' "$package" "$version"
          return 0
        fi
      fi
      ;;
    rpm:*)
      if have rpm; then
        version="$(rpm -qf --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$command_path" 2>/dev/null || true)"
        if [ -n "$version" ] && [ "${version#file }" = "$version" ]; then
          printf 'package version: %s' "$version"
          return 0
        fi
      fi
      ;;
    pacman:*)
      package="${source#pacman:}"
      if have pacman; then
        version="$(pacman -Q "$package" 2>/dev/null || true)"
        if [ -n "$version" ]; then
          printf 'package version: %s' "$version"
          return 0
        fi
      fi
      ;;
  esac

  return 1
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
      run_package_command apt-get install -y "$package"
      ;;
    dnf)
      run_package_command dnf install -y "$package"
      ;;
    pacman)
      run_package_command pacman -S --needed --noconfirm "$package"
      ;;
    zypper)
      if run_package_command zypper install -y "$package"; then
        return 0
      fi
      # Tumbleweed mirrors can roll package files out from under newly built
      # metadata. Rebuild metadata only after a failed install so the common
      # path avoids the full refresh that has been flaky on hosted runners.
      echo "zypper install failed for $package; rebuilding metadata and retrying."
      run_package_command zypper clean --metadata
      run_package_command zypper install -y "$package"
      ;;
    *)
      echo "Unsupported package manager: $manager" >&2
      return 1
      ;;
  esac
}

download_to_stdout() {
  local url="$1"
  if have curl; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      case "$url" in
        https://api.github.com/*)
          curl -fsSL \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$url"
          return 0
          ;;
      esac
    fi
    curl -fsSL "$url"
    return 0
  fi
  if have wget; then
    wget -qO- "$url"
    return 0
  fi

  echo "curl or wget is required to download $url" >&2
  return 1
}

# Several default Linux repositories used by the install smoke matrix do not
# package every CLI in the tool list. Keep these fallbacks narrow: each one only
# installs its missing tool from the upstream release and never replaces an
# existing command.
actionlint_release_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'amd64'
      ;;
    aarch64|arm64)
      printf 'arm64'
      ;;
    armv6l|armv6)
      printf 'armv6'
      ;;
    i386|i686)
      printf '386'
      ;;
    *)
      echo "Unsupported actionlint release architecture: $(uname -m)" >&2
      return 1
      ;;
  esac
}

install_actionlint_release() {
  local arch api_url asset_url asset_name asset_version checksum_url tmp_dir status

  arch="$(actionlint_release_arch)"
  api_url="https://api.github.com/repos/rhysd/actionlint/releases/latest"
  asset_url="$(download_to_stdout "$api_url" | sed -n "s#.*\"browser_download_url\":[[:space:]]*\"\\([^\"]*actionlint_[^\"]*_linux_${arch}\\.tar\\.gz\\)\".*#\\1#p" | head -n 1)"
  if [ -z "$asset_url" ]; then
    echo "Could not find an actionlint Linux $arch release asset." >&2
    return 1
  fi

  asset_name="${asset_url##*/}"
  asset_version="${asset_name#actionlint_}"
  asset_version="${asset_version%%_*}"
  checksum_url="${asset_url%/*}/actionlint_${asset_version}_checksums.txt"
  tmp_dir="$(mktemp -d)"
  status=0

  (
    set -e
    cd "$tmp_dir"
    download_to_stdout "$asset_url" > "$asset_name"

    if have sha256sum; then
      download_to_stdout "$checksum_url" > checksums.txt
      checksum_line="$(grep "  $asset_name\$" checksums.txt || true)"
      if [ -z "$checksum_line" ]; then
        echo "Could not find checksum for $asset_name." >&2
        exit 1
      fi
      printf '%s\n' "$checksum_line" | sha256sum -c -
    else
      echo "sha256sum was not found; skipping actionlint checksum verification." >&2
    fi

    tar -xzf "$asset_name" actionlint
    run_elevated install -m 0755 actionlint /usr/local/bin/actionlint
  ) || status=$?

  rm -rf "$tmp_dir"
  return "$status"
}

typos_release_target() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64-unknown-linux-musl'
      ;;
    aarch64|arm64)
      printf 'aarch64-unknown-linux-musl'
      ;;
    *)
      echo "Unsupported typos release architecture: $(uname -m)" >&2
      return 1
      ;;
  esac
}

install_typos_release() {
  local target api_url asset_name asset_url asset_digest tmp_dir status

  target="$(typos_release_target)"
  api_url="https://api.github.com/repos/crate-ci/typos/releases/latest"
  tmp_dir="$(mktemp -d)"
  status=0

  (
    set -e
    cd "$tmp_dir"
    download_to_stdout "$api_url" > release.json
    asset_name="$(sed -n "s#.*\"name\":[[:space:]]*\"\\(typos-v[^\"]*-${target}\\.tar\\.gz\\)\".*#\\1#p" release.json | head -n 1)"
    if [ -z "$asset_name" ]; then
      echo "Could not find a typos Linux $target release asset." >&2
      exit 1
    fi

    asset_url="$(sed -n "s#.*\"browser_download_url\":[[:space:]]*\"\\([^\"]*/${asset_name}\\)\".*#\\1#p" release.json | head -n 1)"
    if [ -z "$asset_url" ]; then
      echo "Could not find a download URL for $asset_name." >&2
      exit 1
    fi

    asset_digest="$(sed -n "/\"name\":[[:space:]]*\"$asset_name\"/,/\"browser_download_url\"/s#.*\"digest\":[[:space:]]*\"sha256:\\([a-f0-9]*\\)\".*#\\1#p" release.json | head -n 1)"
    download_to_stdout "$asset_url" > "$asset_name"

    if have sha256sum; then
      if [ -z "$asset_digest" ]; then
        echo "Could not find a GitHub SHA256 digest for $asset_name." >&2
        exit 1
      fi
      printf '%s  %s\n' "$asset_digest" "$asset_name" | sha256sum -c -
    else
      echo "sha256sum was not found; skipping typos checksum verification." >&2
    fi

    tar -xzf "$asset_name"
    if [ ! -f typos ]; then
      echo "Could not find typos in $asset_name." >&2
      exit 1
    fi
    run_elevated install -m 0755 typos /usr/local/bin/typos
  ) || status=$?

  rm -rf "$tmp_dir"
  return "$status"
}

difftastic_release_target() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64-unknown-linux-gnu'
      ;;
    aarch64|arm64)
      printf 'aarch64-unknown-linux-gnu'
      ;;
    *)
      echo "Unsupported difftastic release architecture: $(uname -m)" >&2
      return 1
      ;;
  esac
}

install_difftastic_release() {
  local target api_url asset_name asset_url asset_digest tmp_dir status

  target="$(difftastic_release_target)"
  api_url="https://api.github.com/repos/Wilfred/difftastic/releases/latest"
  tmp_dir="$(mktemp -d)"
  status=0

  (
    set -e
    cd "$tmp_dir"
    download_to_stdout "$api_url" > release.json
    asset_name="$(sed -n "s#.*\"name\":[[:space:]]*\"\\(difft-${target}\\.tar\\.gz\\)\".*#\\1#p" release.json | head -n 1)"
    if [ -z "$asset_name" ]; then
      echo "Could not find a difftastic Linux $target release asset." >&2
      exit 1
    fi

    asset_url="$(sed -n "s#.*\"browser_download_url\":[[:space:]]*\"\\([^\"]*/${asset_name}\\)\".*#\\1#p" release.json | head -n 1)"
    if [ -z "$asset_url" ]; then
      echo "Could not find a download URL for $asset_name." >&2
      exit 1
    fi

    asset_digest="$(sed -n "/\"name\":[[:space:]]*\"$asset_name\"/,/\"browser_download_url\"/s#.*\"digest\":[[:space:]]*\"sha256:\\([a-f0-9]*\\)\".*#\\1#p" release.json | head -n 1)"
    download_to_stdout "$asset_url" > "$asset_name"

    if have sha256sum; then
      if [ -z "$asset_digest" ]; then
        echo "Could not find a GitHub SHA256 digest for $asset_name." >&2
        exit 1
      fi
      printf '%s  %s\n' "$asset_digest" "$asset_name" | sha256sum -c -
    else
      echo "sha256sum was not found; skipping difftastic checksum verification." >&2
    fi

    tar -xzf "$asset_name" difft
    run_elevated install -m 0755 difft /usr/local/bin/difft
  ) || status=$?

  rm -rf "$tmp_dir"
  return "$status"
}

uv_release_target() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64-unknown-linux-gnu'
      ;;
    aarch64|arm64)
      printf 'aarch64-unknown-linux-gnu'
      ;;
    i386|i686)
      printf 'i686-unknown-linux-gnu'
      ;;
    *)
      echo "Unsupported uv release architecture: $(uname -m)" >&2
      return 1
      ;;
  esac
}

install_uv_release() {
  local target api_url asset_name asset_url checksum_url tmp_dir status

  target="$(uv_release_target)"
  api_url="https://api.github.com/repos/astral-sh/uv/releases/latest"
  asset_name="uv-${target}.tar.gz"
  tmp_dir="$(mktemp -d)"
  status=0

  (
    set -e
    cd "$tmp_dir"
    download_to_stdout "$api_url" > release.json
    asset_url="$(sed -n "s#.*\"browser_download_url\":[[:space:]]*\"\\([^\"]*/${asset_name}\\)\".*#\\1#p" release.json | head -n 1)"
    if [ -z "$asset_url" ]; then
      echo "Could not find a uv Linux $target release asset." >&2
      exit 1
    fi

    checksum_url="$(sed -n "s#.*\"browser_download_url\":[[:space:]]*\"\\([^\"]*/${asset_name}\\.sha256\\)\".*#\\1#p" release.json | head -n 1)"
    download_to_stdout "$asset_url" > "$asset_name"

    if have sha256sum; then
      if [ -z "$checksum_url" ]; then
        echo "Could not find a uv SHA256 checksum for $asset_name." >&2
        exit 1
      fi
      download_to_stdout "$checksum_url" > "$asset_name.sha256"
      sha256sum -c "$asset_name.sha256"
    else
      echo "sha256sum was not found; skipping uv checksum verification." >&2
    fi

    tar -xzf "$asset_name"
    if [ ! -f "uv-${target}/uv" ]; then
      echo "Could not find uv in $asset_name." >&2
      exit 1
    fi
    run_elevated install -m 0755 "uv-${target}/uv" /usr/local/bin/uv
    if [ -f "uv-${target}/uvx" ]; then
      run_elevated install -m 0755 "uv-${target}/uvx" /usr/local/bin/uvx
    fi
  ) || status=$?

  rm -rf "$tmp_dir"
  return "$status"
}

ast_grep_release_target() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64-unknown-linux-gnu'
      ;;
    aarch64|arm64)
      printf 'aarch64-unknown-linux-gnu'
      ;;
    *)
      echo "Unsupported ast-grep release architecture: $(uname -m)" >&2
      return 1
      ;;
  esac
}

install_ast_grep_release() {
  local target api_url asset_name asset_url asset_digest tmp_dir status

  target="$(ast_grep_release_target)"
  api_url="https://api.github.com/repos/ast-grep/ast-grep/releases/latest"
  asset_name="app-${target}.zip"
  tmp_dir="$(mktemp -d)"
  status=0

  (
    set -e
    cd "$tmp_dir"
    download_to_stdout "$api_url" > release.json
    asset_url="$(sed -n "s#.*\"browser_download_url\":[[:space:]]*\"\\([^\"]*/${asset_name}\\)\".*#\\1#p" release.json | head -n 1)"
    if [ -z "$asset_url" ]; then
      echo "Could not find an ast-grep Linux $target release asset." >&2
      exit 1
    fi

    asset_digest="$(sed -n "/\"name\":[[:space:]]*\"$asset_name\"/,/\"browser_download_url\"/s#.*\"digest\":[[:space:]]*\"sha256:\\([a-f0-9]*\\)\".*#\\1#p" release.json | head -n 1)"
    download_to_stdout "$asset_url" > "$asset_name"

    if have sha256sum; then
      if [ -z "$asset_digest" ]; then
        echo "Could not find a GitHub SHA256 digest for $asset_name." >&2
        exit 1
      fi
      printf '%s  %s\n' "$asset_digest" "$asset_name" | sha256sum -c -
    else
      echo "sha256sum was not found; skipping ast-grep checksum verification." >&2
    fi

    unzip -q "$asset_name"
    if [ ! -f ast-grep ]; then
      echo "Could not find ast-grep in $asset_name." >&2
      exit 1
    fi
    # Do not install the release's `sg` alias: Linux systems commonly already
    # have an unrelated `sg` command, and /usr/local/bin may shadow it.
    run_elevated install -m 0755 ast-grep /usr/local/bin/ast-grep
  ) || status=$?

  rm -rf "$tmp_dir"
  return "$status"
}

install_pre_commit_uv_tool() {
  if ! have uv; then
    echo "uv is required to install pre-commit with the uv tool fallback." >&2
    return 1
  fi
  if ! have python3; then
    echo "python3 is required to install pre-commit with the uv tool fallback." >&2
    return 1
  fi

  run_elevated install -d -m 0755 /usr/local/share/uv/tools /usr/local/bin
  run_elevated env UV_TOOL_DIR=/usr/local/share/uv/tools UV_TOOL_BIN_DIR=/usr/local/bin uv tool install --python python3 --no-managed-python --no-python-downloads pre-commit
}

install_uv_tool() {
  local package="$1"
  case "$package" in
    uv-tool:pre-commit)
      install_pre_commit_uv_tool
      ;;
    *)
      echo "Unsupported uv tool installer: $package" >&2
      return 1
      ;;
  esac
}

install_github_release_tool() {
  local package="$1"
  case "$package" in
    github-release:actionlint)
      install_actionlint_release
      ;;
    github-release:typos)
      install_typos_release
      ;;
    github-release:difftastic)
      install_difftastic_release
      ;;
    github-release:uv)
      install_uv_release
      ;;
    github-release:ast-grep)
      install_ast_grep_release
      ;;
    *)
      echo "Unsupported GitHub release installer: $package" >&2
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
      run_package_command apt-get install --only-upgrade -y "$package"
      ;;
    rpm)
      if have dnf; then
        run_package_command dnf upgrade -y "$package"
      elif have zypper; then
        run_package_command zypper update -y "$package"
      else
        echo "  skip upgrade: rpm package found, but dnf/zypper is unavailable."
      fi
      ;;
    pacman)
      run_package_command pacman -S --needed --noconfirm "$package"
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

print_install_hint() {
  if [ -n "$PACKAGE_MANAGER" ]; then
    cat <<MSG

To install missing tools with $PACKAGE_MANAGER, run:
  ./linux.sh --manager $PACKAGE_MANAGER --install-missing
MSG
  else
    print_manager_guidance
    cat <<'MSG'

Then run:
  ./linux.sh --install-missing
MSG
  fi
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
      if [ "${package#github-release:}" != "$package" ]; then
        printf ' installer: upstream GitHub release\n'
      elif [ "${package#uv-tool:}" != "$package" ]; then
        printf ' installer: uv tool install\n'
      elif [ -n "$package" ]; then
        printf ' package: %s\n' "$package"
      else
        printf ' package: unavailable\n'
      fi

      if [ "$INSTALL_MISSING" -eq 1 ] && [ "${package#github-release:}" != "$package" ]; then
        install_github_release_tool "$package"
      elif [ "$INSTALL_MISSING" -eq 1 ] && [ "${package#uv-tool:}" != "$package" ]; then
        install_uv_tool "$package"
      elif [ "$INSTALL_MISSING" -eq 1 ] && [ -n "$package" ]; then
        install_package "$PACKAGE_MANAGER" "$package"
      fi
    else
      printf ' package: unknown, no supported manager\n'
    fi
    continue
  fi

  source="$(detect_source "$command_path")"
  if version="$(version_for "$command_path")"; then
    if [ -z "$version" ]; then
      version="$(package_version_for_source "$source" "$command_path" || true)"
      if [ -z "$version" ]; then
        version="version output empty"
      fi
    fi
  elif [ "$name" = "yarn" ] && { [ "$source" = "npm-or-node" ] || [ "${source#apt:node}" != "$source" ] || [ "${source#rpm:node}" != "$source" ] || [ "${source#pacman:node}" != "$source" ]; }; then
    version="corepack shim; version is selected per project"
  else
    failed_version_count=$((failed_version_count + 1))
    version="version check failed"
  fi

  version_display="$(version_for_display "$version")"
  path_display="$(path_for_display "$command_path")"
  printf '[found]   %-14s %-48s %-22s %s\n' "$name" "$path_display" "$source" "$version_display"

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
if [ "$missing_count" -gt 0 ] && [ "$INSTALL_MISSING" -eq 0 ]; then
  print_install_hint
fi
