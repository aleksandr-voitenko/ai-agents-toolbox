#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" "$haystack"; then
    echo "Expected to find: $needle" >&2
    echo "In output:" >&2
    cat "$haystack" >&2
    fail "$label"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$haystack"; then
    echo "Did not expect to find: $needle" >&2
    echo "In output:" >&2
    cat "$haystack" >&2
    fail "$label"
  fi
}

assert_log_contains() {
  local log_file="$1"
  local needle="$2"
  local label="$3"
  if [ ! -f "$log_file" ] || ! grep -Fq "$needle" "$log_file"; then
    echo "Expected command log to contain: $needle" >&2
    if [ -f "$log_file" ]; then
      cat "$log_file" >&2
    fi
    fail "$label"
  fi
}

assert_log_line_count() {
  local log_file="$1"
  local needle="$2"
  local expected="$3"
  local label="$4"
  local actual=0

  if [ -f "$log_file" ]; then
    actual="$(grep -F -c "$needle" "$log_file" || true)"
  fi

  if [ "$actual" -ne "$expected" ]; then
    echo "Expected command log to contain $expected instances of: $needle" >&2
    echo "Found: $actual" >&2
    if [ -f "$log_file" ]; then
      cat "$log_file" >&2
    fi
    fail "$label"
  fi
}

assert_log_not_contains() {
  local log_file="$1"
  local needle="$2"
  local label="$3"
  if [ -f "$log_file" ] && grep -Fq "$needle" "$log_file"; then
    echo "Did not expect command log to contain: $needle" >&2
    cat "$log_file" >&2
    fail "$label"
  fi
}

run_with_path() {
  local output_file="$1"
  local path_value="$2"
  shift 2

  local status
  set +e
  PATH="$path_value" "$@" >"$output_file" 2>&1
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    cat "$output_file" >&2
    fail "command failed with status $status: $*"
  fi
}

new_case_dir() {
  local name="$1"
  local dir="$TEST_ROOT/$name"
  mkdir -p "$dir/bin"
  printf '%s\n' "$dir"
}

link_utility() {
  local bin_dir="$1"
  local utility="$2"
  local utility_path
  utility_path="$(command -v "$utility" || true)"
  [ -n "$utility_path" ] || fail "required test utility not found: $utility"
  ln -s "$utility_path" "$bin_dir/$utility"
}

write_executable() {
  local path="$1"
  shift
  {
    printf '#!/bin/sh\n'
    printf '%s\n' "$@"
  } >"$path"
  chmod +x "$path"
}

add_common_shell_utilities() {
  local bin_dir="$1"
  link_utility "$bin_dir" cat
  link_utility "$bin_dir" head
  link_utility "$bin_dir" basename
  link_utility "$bin_dir" cut
  link_utility "$bin_dir" sed
  link_utility "$bin_dir" grep
  link_utility "$bin_dir" dirname
  link_utility "$bin_dir" pwd
  link_utility "$bin_dir" uname
  link_utility "$bin_dir" env
  link_utility "$bin_dir" mktemp
  link_utility "$bin_dir" mkdir
  link_utility "$bin_dir" rm
  link_utility "$bin_dir" chmod

  write_executable "$bin_dir/id" \
    'if [ "$1" = "-u" ]; then' \
    '  printf "0\n"' \
    'else' \
    '  printf "uid=0(root) gid=0(root) groups=0(root)\n"' \
    'fi'
}

add_fake_tool() {
  local bin_dir="$1"
  local command_name="$2"
  write_executable "$bin_dir/$command_name" \
    "printf '%s version 1.0\n' '$command_name'"
}

add_fake_empty_version_tool() {
  local bin_dir="$1"
  local command_name="$2"
  write_executable "$bin_dir/$command_name" \
    'case "$1" in' \
    '  --version|-version)' \
    '  exit 0' \
    '  ;;' \
    '  *)' \
    '  exit 2' \
    '  ;;' \
    'esac'
}

add_fake_long_version_tool() {
  local bin_dir="$1"
  local command_name="$2"
  write_executable "$bin_dir/$command_name" \
    'case "$1" in' \
    '  --version|-version)' \
    '  printf "12345678901234567890123456789012345678901234567890123456789012345678901234567890hidden-tail\n"' \
    '  ;;' \
    '  *)' \
    '  exit 2' \
    '  ;;' \
    'esac'
}

add_fake_multiline_shellcheck_tool() {
  local bin_dir="$1"
  write_executable "$bin_dir/shellcheck" \
    'case "$1" in' \
    '  --version)' \
    '  printf "ShellCheck - shell script analysis tool\n"' \
    '  printf "version: 0.11.0\n"' \
    '  printf "license: GNU General Public License, version 3\n"' \
    '  ;;' \
    '  *)' \
    '  exit 2' \
    '  ;;' \
    'esac'
}

add_fake_cluttered_imagemagick_tool() {
  local bin_dir="$1"
  write_executable "$bin_dir/magick" \
    'case "$1" in' \
    '  --version)' \
    '  printf "Version: ImageMagick 7.1.2-23 Q16-HDRI aarch64 hidden-tail\n"' \
    '  ;;' \
    '  *)' \
    '  exit 2' \
    '  ;;' \
    'esac'
}

add_fake_verbose_ffmpeg_tool() {
  local bin_dir="$1"
  write_executable "$bin_dir/ffmpeg" \
    'case "$1" in' \
    '  -version)' \
    '    printf "ffmpeg version 1.0\n"' \
    '    i=0' \
    '    while [ "$i" -lt 20000 ]; do' \
    '      printf "configuration line %s with enough content to trip pipefail under head\n" "$i"' \
    '      i=$((i + 1))' \
    '    done' \
    '    ;;' \
    '  *)' \
    '    exit 2' \
    '    ;;' \
    'esac'
}

add_fake_linux_manager() {
  local bin_dir="$1"
  local manager="$2"
  case "$manager" in
    apt)
      write_executable "$bin_dir/apt-get" \
        'printf "apt-get %s DEBIAN_FRONTEND=%s\n" "$*" "$DEBIAN_FRONTEND" >> "$FAKE_COMMAND_LOG"' \
        'read -r _ || true'
      ;;
    dnf|pacman|zypper)
      write_executable "$bin_dir/$manager" \
        "bin_dir='$bin_dir'" \
        "printf '$manager %s\n' \"\$*\" >> \"\$FAKE_COMMAND_LOG\"" \
        'case "$*" in' \
        '  "install -y python3")' \
        '    {' \
        '      printf "#!/bin/sh\n"' \
        '      printf "printf '\''python3 3.13.0\\n'\''\n"' \
        '    } > "$bin_dir/python3"' \
        '    chmod +x "$bin_dir/python3"' \
        '    ;;' \
        'esac'
      ;;
    *)
      fail "unsupported fake Linux manager: $manager"
      ;;
  esac
}

add_fake_flaky_zypper_manager() {
  local bin_dir="$1"
  write_executable "$bin_dir/zypper" \
    "bin_dir='$bin_dir'" \
    'printf "zypper %s\n" "$*" >> "$FAKE_COMMAND_LOG"' \
    'case "$*" in' \
    '  "install -y ripgrep")' \
    '    if [ ! -f "$FAKE_ZYPPER_FAILED_ONCE" ]; then' \
    '      printf "The requested URL returned error: 404\n" >&2' \
    '      : > "$FAKE_ZYPPER_FAILED_ONCE"' \
    '      exit 4' \
    '    fi' \
    '    ;;' \
    '  "install -y python3")' \
    '    {' \
    '      printf "#!/bin/sh\n"' \
    '      printf "printf '\''python3 3.13.0\\n'\''\n"' \
    '    } > "$bin_dir/python3"' \
    '    chmod +x "$bin_dir/python3"' \
    '    ;;' \
    'esac'
}

add_fake_github_release_installers() {
  local bin_dir="$1"

  write_executable "$bin_dir/curl" \
    'if [ "$1" = "--version" ]; then' \
    '  printf "curl 8.0\n"' \
    '  exit 0' \
    'fi' \
    'url=""' \
    'while [ "$#" -gt 0 ]; do' \
    '  case "$1" in' \
    '    -H)' \
    '      printf "curl header %s\n" "$2" >> "$FAKE_COMMAND_LOG"' \
    '      shift 2' \
    '      ;;' \
    '    -fsSL)' \
    '      shift' \
    '      ;;' \
    '    *)' \
    '      url="$1"' \
    '      shift' \
    '      ;;' \
    '  esac' \
    'done' \
    'case "$url" in' \
    '  *api.github.com/repos/rhysd/actionlint/releases/latest*)' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_arm64.tar.gz\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_386.tar.gz\"}"' \
    '    ;;' \
    '  *api.github.com/repos/crate-ci/typos/releases/latest*)' \
    '    printf "%s\n" "{\"name\":\"typos-v1.47.2-x86_64-unknown-linux-musl.tar.gz\"}"' \
    '    printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/crate-ci/typos/releases/download/v1.47.2/typos-v1.47.2-x86_64-unknown-linux-musl.tar.gz\"}"' \
    '    printf "%s\n" "{\"name\":\"typos-v1.47.2-aarch64-unknown-linux-musl.tar.gz\"}"' \
    '    printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/crate-ci/typos/releases/download/v1.47.2/typos-v1.47.2-aarch64-unknown-linux-musl.tar.gz\"}"' \
    '    ;;' \
    '  *api.github.com/repos/Wilfred/difftastic/releases/latest*)' \
    '    printf "%s\n" "{\"name\":\"difft-x86_64-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/Wilfred/difftastic/releases/download/0.69.0/difft-x86_64-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"name\":\"difft-aarch64-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/Wilfred/difftastic/releases/download/0.69.0/difft-aarch64-unknown-linux-gnu.tar.gz\"}"' \
    '    ;;' \
    '  *api.github.com/repos/astral-sh/uv/releases/latest*)' \
    '    printf "%s\n" "{\"name\":\"uv-x86_64-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/astral-sh/uv/releases/download/0.11.26/uv-x86_64-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"name\":\"uv-x86_64-unknown-linux-gnu.tar.gz.sha256\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/astral-sh/uv/releases/download/0.11.26/uv-x86_64-unknown-linux-gnu.tar.gz.sha256\"}"' \
    '    printf "%s\n" "{\"name\":\"uv-aarch64-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/astral-sh/uv/releases/download/0.11.26/uv-aarch64-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"name\":\"uv-aarch64-unknown-linux-gnu.tar.gz.sha256\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/astral-sh/uv/releases/download/0.11.26/uv-aarch64-unknown-linux-gnu.tar.gz.sha256\"}"' \
    '    printf "%s\n" "{\"name\":\"uv-i686-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/astral-sh/uv/releases/download/0.11.26/uv-i686-unknown-linux-gnu.tar.gz\"}"' \
    '    printf "%s\n" "{\"name\":\"uv-i686-unknown-linux-gnu.tar.gz.sha256\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/astral-sh/uv/releases/download/0.11.26/uv-i686-unknown-linux-gnu.tar.gz.sha256\"}"' \
    '    ;;' \
    '  *api.github.com/repos/ast-grep/ast-grep/releases/latest*)' \
    '    printf "%s\n" "{\"name\":\"app-x86_64-unknown-linux-gnu.zip\"}"' \
    '    printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/ast-grep/ast-grep/releases/download/0.44.1/app-x86_64-unknown-linux-gnu.zip\"}"' \
    '    printf "%s\n" "{\"name\":\"app-aarch64-unknown-linux-gnu.zip\"}"' \
    '    printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '    printf "%s\n" "{\"browser_download_url\":\"https://github.com/ast-grep/ast-grep/releases/download/0.44.1/app-aarch64-unknown-linux-gnu.zip\"}"' \
    '    ;;' \
    '  *uv-*-unknown-linux-gnu.tar.gz.sha256*)' \
    '    asset="${url##*/}"' \
    '    printf "fake  %s\n" "${asset%.sha256}"' \
    '    ;;' \
    '  *)' \
    '    printf "fake actionlint archive\n"' \
    '    ;;' \
    'esac'

  write_executable "$bin_dir/tar" \
    'if [ "$1" = "--version" ]; then' \
    '  printf "tar 1.0\n"' \
    '  exit 0' \
    'fi' \
    'printf "tar %s\n" "$*" >> "$FAKE_COMMAND_LOG"' \
    'mkdir -p uv-x86_64-unknown-linux-gnu' \
    'mkdir -p uv-aarch64-unknown-linux-gnu' \
    'mkdir -p uv-i686-unknown-linux-gnu' \
    ': > actionlint' \
    ': > typos' \
    ': > difft' \
    ': > uv-x86_64-unknown-linux-gnu/uv' \
    ': > uv-x86_64-unknown-linux-gnu/uvx' \
    ': > uv-aarch64-unknown-linux-gnu/uv' \
    ': > uv-aarch64-unknown-linux-gnu/uvx' \
    ': > uv-i686-unknown-linux-gnu/uv' \
    ': > uv-i686-unknown-linux-gnu/uvx'

  write_executable "$bin_dir/unzip" \
    'if [ "$1" = "-v" ]; then' \
    '  printf "UnZip 6.00\n"' \
    '  exit 0' \
    'fi' \
    'printf "unzip %s\n" "$*" >> "$FAKE_COMMAND_LOG"' \
    ': > ast-grep' \
    ': > sg'

  write_executable "$bin_dir/install" \
    "bin_dir='$bin_dir'" \
    'printf "install %s\n" "$*" >> "$FAKE_COMMAND_LOG"' \
    'case "$*" in' \
    '  *" /usr/local/bin/uv")' \
    '    {' \
    '      printf "#!/bin/sh\n"' \
    '      printf "printf '\''uv %%s UV_TOOL_DIR=%%s UV_TOOL_BIN_DIR=%%s\\n'\'' \"\$*\" \"\$UV_TOOL_DIR\" \"\$UV_TOOL_BIN_DIR\" >> \"\$FAKE_COMMAND_LOG\"\n"' \
    '    } > "$bin_dir/uv"' \
    '    chmod +x "$bin_dir/uv"' \
    '    ;;' \
    'esac'
}

add_fake_rpm_owner() {
  local bin_dir="$1"
  local owner="$2"
  write_executable "$bin_dir/rpm" \
    'if [ "$1" = "-qf" ]; then' \
    "  printf '$owner\n'" \
    '  exit 0' \
    'fi' \
    'exit 1'
}

add_fake_dpkg_owner() {
  local bin_dir="$1"
  local owner="$2"
  write_executable "$bin_dir/dpkg" \
    'if [ "$1" = "-S" ]; then' \
    "  printf '$owner: %s\n' \"\$2\"" \
    '  exit 0' \
    'fi' \
    'exit 1'
}

add_fake_brew() {
  local bin_dir="$1"
  write_executable "$bin_dir/brew" \
    'printf "brew %s\n" "$*" >> "$FAKE_COMMAND_LOG"' \
    'case "$1" in' \
    '  --prefix)' \
    '    printf "%s\n" "$FAKE_BREW_PREFIX"' \
    '    ;;' \
    '  list)' \
    '    if [ "$2" = "--versions" ]; then' \
    '      printf "%s 15.0.0\n" "$3"' \
    '    fi' \
    '    ;;' \
    '  outdated)' \
    '    printf "%s\n" "$3"' \
    '    ;;' \
    'esac'
}

test_linux_check_only_does_not_install() {
  local dir bin log output
  dir="$(new_case_dir linux-check-only)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_linux_manager "$bin" apt

  FAKE_COMMAND_LOG="$log" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh"

  assert_contains "$output" "Detected package manager: apt" "linux should detect fake apt"
  assert_contains "$output" "[missing] ripgrep" "linux should report missing tools"
  assert_contains "$output" "To install missing tools with apt, run:" "linux check-only should print install guidance"
  assert_contains "$output" "./linux.sh --manager apt --install-missing" "linux check-only should print a copy-paste install command"
  assert_not_contains "$output" "Installing " "linux check-only should not print installs"
  assert_log_not_contains "$log" "apt-get install" "linux check-only should not invoke apt-get install"
}

test_linux_install_missing_uses_selected_managers() {
  local manager dir bin log output expected expected_sqlite expected_delta expected_file expected_actionlint expected_typos
  local expected_just expected_difftastic expected_pandoc expected_imagemagick expected_ffmpeg expected_exiftool last_expected
  local expected_uv expected_pre_commit expected_ast_grep expected_zip expected_rsync expected_xxd expected_hexdump expected_stat uv_release_dir

  for manager in apt dnf pacman zypper; do
    dir="$(new_case_dir "linux-install-$manager")"
    bin="$dir/bin"
    log="$dir/commands.log"
    output="$dir/output.txt"
    add_common_shell_utilities "$bin"
    add_fake_linux_manager "$bin" "$manager"
    add_fake_github_release_installers "$bin"

    FAKE_COMMAND_LOG="$log" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh" --manager "$manager" --install-missing

    case "$(uname -m)" in
      x86_64|amd64)
        uv_release_dir="uv-x86_64-unknown-linux-gnu"
        ;;
      aarch64|arm64)
        uv_release_dir="uv-aarch64-unknown-linux-gnu"
        ;;
      i386|i686)
        uv_release_dir="uv-i686-unknown-linux-gnu"
        ;;
      *)
        fail "unsupported test architecture for uv release fixture: $(uname -m)"
        ;;
    esac

    case "$manager" in
      apt)
        expected="apt-get install -y ripgrep"
        expected_sqlite="apt-get install -y sqlite3"
        expected_delta="apt-get install -y git-delta"
        expected_file="apt-get install -y file"
        expected_actionlint="install -m 0755 actionlint /usr/local/bin/actionlint"
        expected_typos="install -m 0755 typos /usr/local/bin/typos"
        expected_just="apt-get install -y just"
        expected_difftastic="install -m 0755 difft /usr/local/bin/difft"
        expected_pandoc="apt-get install -y pandoc"
        expected_imagemagick="apt-get install -y imagemagick"
        expected_ffmpeg="apt-get install -y ffmpeg"
        expected_exiftool="apt-get install -y libimage-exiftool-perl"
        expected_uv="install -m 0755 $uv_release_dir/uv /usr/local/bin/uv"
        expected_pre_commit="apt-get install -y pre-commit"
        expected_ast_grep="install -m 0755 ast-grep /usr/local/bin/ast-grep"
        expected_zip="apt-get install -y zip"
        expected_rsync="apt-get install -y rsync"
        expected_xxd="apt-get install -y xxd"
        expected_hexdump="apt-get install -y bsdextrautils"
        expected_stat="apt-get install -y coreutils"
        last_expected="apt-get install -y poppler-utils"
        ;;
      dnf)
        expected="dnf install -y ripgrep"
        expected_sqlite="dnf install -y sqlite"
        expected_delta="dnf install -y git-delta"
        expected_file="dnf install -y file"
        expected_actionlint="install -m 0755 actionlint /usr/local/bin/actionlint"
        expected_typos="install -m 0755 typos /usr/local/bin/typos"
        expected_just="dnf install -y just"
        expected_difftastic="dnf install -y difftastic"
        expected_pandoc="dnf install -y pandoc-cli"
        expected_imagemagick="dnf install -y ImageMagick"
        expected_ffmpeg="dnf install -y ffmpeg-free"
        expected_exiftool="dnf install -y perl-Image-ExifTool"
        expected_uv="dnf install -y uv"
        expected_pre_commit="dnf install -y pre-commit"
        expected_ast_grep="install -m 0755 ast-grep /usr/local/bin/ast-grep"
        expected_zip="dnf install -y zip"
        expected_rsync="dnf install -y rsync"
        expected_xxd="dnf install -y xxd"
        expected_hexdump="dnf install -y util-linux"
        expected_stat="dnf install -y coreutils"
        last_expected="dnf install -y poppler-utils"
        ;;
      pacman)
        expected="pacman -S --needed --noconfirm ripgrep"
        expected_sqlite="pacman -S --needed --noconfirm sqlite"
        expected_delta="pacman -S --needed --noconfirm git-delta"
        expected_file="pacman -S --needed --noconfirm file"
        expected_actionlint="pacman -S --needed --noconfirm actionlint"
        expected_typos="pacman -S --needed --noconfirm typos"
        expected_just="pacman -S --needed --noconfirm just"
        expected_difftastic="pacman -S --needed --noconfirm difftastic"
        expected_pandoc="pacman -S --needed --noconfirm pandoc-cli"
        expected_imagemagick="pacman -S --needed --noconfirm imagemagick"
        expected_ffmpeg="pacman -S --needed --noconfirm ffmpeg"
        expected_exiftool="pacman -S --needed --noconfirm perl-image-exiftool"
        expected_uv="pacman -S --needed --noconfirm uv"
        expected_pre_commit="pacman -S --needed --noconfirm pre-commit"
        expected_ast_grep="pacman -S --needed --noconfirm ast-grep"
        expected_zip="pacman -S --needed --noconfirm zip"
        expected_rsync="pacman -S --needed --noconfirm rsync"
        expected_xxd="pacman -S --needed --noconfirm vim"
        expected_hexdump="pacman -S --needed --noconfirm util-linux"
        expected_stat="pacman -S --needed --noconfirm coreutils"
        last_expected="pacman -S --needed --noconfirm poppler"
        ;;
      zypper)
        expected="zypper install -y ripgrep"
        expected_sqlite="zypper install -y sqlite3"
        expected_delta="zypper install -y git-delta"
        expected_file="zypper install -y file"
        expected_actionlint="install -m 0755 actionlint /usr/local/bin/actionlint"
        expected_typos="install -m 0755 typos /usr/local/bin/typos"
        expected_just="zypper install -y just"
        expected_difftastic="zypper install -y difftastic"
        expected_pandoc="zypper install -y pandoc-cli"
        expected_imagemagick="zypper install -y ImageMagick"
        expected_ffmpeg="zypper install -y ffmpeg-8"
        expected_exiftool="zypper install -y exiftool"
        expected_uv="install -m 0755 $uv_release_dir/uv /usr/local/bin/uv"
        expected_pre_commit="uv tool install --python python3 --no-managed-python --no-python-downloads pre-commit UV_TOOL_DIR=/usr/local/share/uv/tools UV_TOOL_BIN_DIR=/usr/local/bin"
        expected_ast_grep="install -m 0755 ast-grep /usr/local/bin/ast-grep"
        expected_zip="zypper install -y zip"
        expected_rsync="zypper install -y rsync"
        expected_xxd="zypper install -y vim"
        expected_hexdump="zypper install -y util-linux"
        expected_stat="zypper install -y coreutils"
        last_expected="zypper install -y poppler-tools"
        ;;
    esac
    assert_log_contains "$log" "$expected" "linux install should use selected $manager manager"
    assert_log_contains "$log" "$expected_sqlite" "linux install should map sqlite3 for $manager"
    assert_log_contains "$log" "$expected_delta" "linux install should map git-delta for $manager"
    assert_log_contains "$log" "$expected_file" "linux install should map file for $manager"
    assert_log_contains "$log" "$expected_actionlint" "linux install should install actionlint for $manager"
    assert_log_contains "$log" "$expected_typos" "linux install should install typos for $manager"
    assert_log_contains "$log" "$expected_just" "linux install should map just for $manager"
    assert_log_contains "$log" "$expected_difftastic" "linux install should map difftastic for $manager"
    assert_log_contains "$log" "$expected_pandoc" "linux install should map pandoc for $manager"
    assert_log_contains "$log" "$expected_imagemagick" "linux install should map ImageMagick for $manager"
    assert_log_contains "$log" "$expected_ffmpeg" "linux install should map ffmpeg for $manager"
    assert_log_contains "$log" "$expected_exiftool" "linux install should map exiftool for $manager"
    assert_log_contains "$log" "$expected_uv" "linux install should map uv for $manager"
    assert_log_contains "$log" "$expected_pre_commit" "linux install should map pre-commit for $manager"
    assert_log_contains "$log" "$expected_ast_grep" "linux install should map ast-grep for $manager"
    assert_log_contains "$log" "$expected_zip" "linux install should map zip for $manager"
    assert_log_contains "$log" "$expected_rsync" "linux install should map rsync for $manager"
    assert_log_contains "$log" "$expected_xxd" "linux install should map xxd for $manager"
    assert_log_contains "$log" "$expected_hexdump" "linux install should map hexdump for $manager"
    assert_log_contains "$log" "$expected_stat" "linux install should map stat/realpath for $manager"
    assert_log_contains "$log" "$last_expected" "linux install should keep processing tools after $manager invokes a package command"
    if [ "$manager" = "apt" ]; then
      assert_log_contains "$log" "DEBIAN_FRONTEND=noninteractive" "apt installs should run noninteractively"
    fi
  done
}

test_linux_zypper_rebuilds_metadata_after_install_failure() {
  local dir bin log output
  dir="$(new_case_dir linux-zypper-stale-metadata)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_flaky_zypper_manager "$bin"
  add_fake_github_release_installers "$bin"

  FAKE_COMMAND_LOG="$log" FAKE_ZYPPER_FAILED_ONCE="$dir/zypper-failed-once" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh" --manager zypper --install-missing

  assert_contains "$output" "zypper install failed for ripgrep; rebuilding metadata and retrying." "linux should explain zypper metadata recovery"
  assert_log_line_count "$log" "zypper install -y ripgrep" 2 "linux should retry the failed zypper install once"
  assert_log_contains "$log" "zypper clean --metadata" "linux should rebuild stale zypper metadata before retrying"
  assert_log_contains "$log" "zypper install -y fd" "linux should keep installing after zypper recovery"
}

test_linux_github_release_downloads_use_token_when_available() {
  local dir bin log output
  dir="$(new_case_dir linux-github-token)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_linux_manager "$bin" apt
  add_fake_github_release_installers "$bin"

  GITHUB_TOKEN="fake-token" FAKE_COMMAND_LOG="$log" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh" --manager apt --install-missing

  assert_log_contains "$log" "curl header Authorization: Bearer fake-token" "linux release downloads should authenticate GitHub API requests when a token is available"
  assert_log_contains "$log" "curl header X-GitHub-Api-Version: 2022-11-28" "linux release downloads should send the GitHub API version header with token-authenticated requests"
}

test_linux_empty_successful_version_output_is_not_a_failure() {
  local dir bin output
  dir="$(new_case_dir linux-empty-version)"
  bin="$dir/bin"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_rpm_owner "$bin" "ripgrep-15.0.0-1.fc44.x86_64"
  add_fake_empty_version_tool "$bin" rg

  run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh"

  assert_contains "$output" "[found]   ripgrep" "linux should find fake ripgrep"
  assert_contains "$output" "package version: ripgrep-15.0.0-1.fc44.x86_64" "linux should use package metadata for empty successful version output"
  assert_contains "$output" "Version checks failed:  0" "linux should not fail successful empty version checks"
  assert_not_contains "$output" "version output empty" "linux should prefer package metadata when it is available"
  assert_not_contains "$output" "version check failed" "linux should not report successful empty version output as failed"
}

test_linux_caps_long_version_output() {
  local dir bin output
  dir="$(new_case_dir linux-long-version)"
  bin="$dir/bin"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_long_version_tool "$bin" rg

  run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh"

  assert_contains "$output" "[found]   ripgrep" "linux should find fake ripgrep"
  assert_contains "$output" "12345678901234567890123456789012345678901234567890123456789012345678901234567..." "linux should shorten long version output with ellipsis"
  assert_not_contains "$output" "hidden-tail" "linux should omit text beyond the version display cap"
}

test_linux_extracts_precise_version_strings() {
  local dir bin output
  dir="$(new_case_dir linux-precise-versions)"
  bin="$dir/bin"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_multiline_shellcheck_tool "$bin"
  add_fake_cluttered_imagemagick_tool "$bin"

  run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh"

  assert_contains "$output" "[found]   shellcheck" "linux should find fake ShellCheck"
  assert_contains "$output" "0.11.0" "linux should scan later version output lines"
  assert_not_contains "$output" "ShellCheck - shell script analysis tool" "linux should not report ShellCheck's descriptive banner"
  assert_not_contains "$output" "license: GNU" "linux should not report later ShellCheck metadata"
  assert_contains "$output" "[found]   imagemagick" "linux should find fake ImageMagick"
  assert_contains "$output" "7.1.2-23" "linux should extract ImageMagick's compact version token"
  assert_not_contains "$output" "Version: ImageMagick" "linux should not report ImageMagick's verbose banner"
  assert_not_contains "$output" "Q16-HDRI" "linux should not report ImageMagick build metadata"
}

test_linux_formats_display_paths() {
  local dir bin output home node_dir long_dir path_value home_marker
  dir="$(new_case_dir linux-display-paths)"
  bin="$dir/bin"
  output="$dir/output.txt"
  home="$dir/home"
  node_dir="$home/.nvm/versions/node/v22.22.2/bin"
  long_dir="$dir/path-segment-that-should-disappear/versions/node/v22.22.2/bin"
  mkdir -p "$node_dir" "$long_dir"
  add_common_shell_utilities "$bin"
  add_fake_tool "$node_dir" node
  add_fake_tool "$long_dir" rg
  path_value="$long_dir:$node_dir:$bin"
  home_marker="~"

  HOME="$home" run_with_path "$output" "$path_value" /bin/bash "$ROOT_DIR/linux.sh"

  assert_contains "$output" "$home_marker/.nvm/versions/node/v22.22.2/bin/node" "linux should display home paths with tilde"
  assert_contains "$output" ".../versions/node/v22.22.2/bin/rg" "linux should preserve the useful tail when shortening long paths"
  assert_not_contains "$output" "$home/.nvm" "linux should not print the full home directory in display paths"
  assert_not_contains "$output" "path-segment-that-should-disappear" "linux should omit the middle of overlong display paths"
}

test_linux_finds_vendor_perl_exiftool() {
  local dir bin output
  dir="$(new_case_dir linux-vendor-perl-exiftool)"
  bin="$dir/bin"
  output="$dir/output.txt"
  mkdir -p "$bin/vendor_perl"
  add_common_shell_utilities "$bin"
  write_executable "$bin/vendor_perl/exiftool" \
    'if [ "$1" = "-ver" ]; then' \
    '  printf "13.59\n"' \
    'else' \
    '  exit 2' \
    'fi'

  run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh"

  assert_contains "$output" "[found]   exiftool" "linux should find ExifTool in a vendor_perl PATH subdirectory"
  assert_contains "$output" "/bin/vendor_perl/exiftool" "linux should report the vendor_perl ExifTool path suffix"
  assert_contains "$output" "13.59" "linux should run version checks for vendor_perl ExifTool"
  assert_contains "$output" "Version checks failed:  0" "linux should not fail vendor_perl ExifTool version checks"
}

test_linux_verbose_ffmpeg_version_output_is_not_a_pipefail_failure() {
  local dir bin output
  dir="$(new_case_dir linux-verbose-ffmpeg-version)"
  bin="$dir/bin"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_rpm_owner "$bin" "ffmpeg-free-8.1.2-1.fc44.x86_64"
  add_fake_verbose_ffmpeg_tool "$bin"

  run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh"

  assert_contains "$output" "[found]   ffmpeg" "linux should find fake FFmpeg"
  assert_contains "$output" "1.0" "linux should report FFmpeg's compact version token"
  assert_contains "$output" "Version checks failed:  0" "linux should not fail verbose FFmpeg version checks"
  assert_not_contains "$output" "version check failed" "linux should not let head/pipefail break verbose FFmpeg checks"
}

test_linux_upgrade_managed_uses_owner_only() {
  local dir bin log output
  dir="$(new_case_dir linux-upgrade-managed)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_linux_manager "$bin" apt
  add_fake_dpkg_owner "$bin" ripgrep
  add_fake_tool "$bin" rg

  FAKE_COMMAND_LOG="$log" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh" --upgrade-managed

  assert_contains "$output" "apt:ripgrep" "linux should report managed apt ownership"
  assert_log_contains "$log" "apt-get install --only-upgrade -y ripgrep" "linux should upgrade the managed owner"
  assert_log_not_contains "$log" "apt-get install -y fd-find" "linux upgrade should not install missing tools"
}

test_linux_install_without_manager_prints_guidance() {
  local dir bin log output
  dir="$(new_case_dir linux-no-manager)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"

  FAKE_COMMAND_LOG="$log" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh" --install-missing

  assert_contains "$output" "Detected package manager: none" "linux should report no manager"
  assert_contains "$output" "No supported Linux package manager was found." "linux should print manager guidance"
  assert_log_not_contains "$log" "install" "linux without a manager should not invoke installs"
}

test_macos_check_only_does_not_install() {
  local dir bin log output prefix
  dir="$(new_case_dir macos-check-only)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  prefix="$dir/homebrew"
  mkdir -p "$prefix"
  add_common_shell_utilities "$bin"
  add_fake_brew "$bin"

  FAKE_COMMAND_LOG="$log" FAKE_BREW_PREFIX="$prefix" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/macos.sh"

  assert_contains "$output" "[missing] ripgrep" "macOS should report missing tools"
  assert_contains "$output" "To install missing tools with Homebrew, run:" "macOS check-only should print install guidance"
  assert_contains "$output" "./macos.sh --install-missing" "macOS check-only should print a copy-paste install command"
  assert_not_contains "$output" "Installing " "macOS check-only should not print installs"
  assert_log_not_contains "$log" "brew install" "macOS check-only should not invoke brew install"
}

test_macos_install_missing_uses_brew() {
  local dir bin log output prefix
  dir="$(new_case_dir macos-install)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  prefix="$dir/homebrew"
  mkdir -p "$prefix"
  add_common_shell_utilities "$bin"
  add_fake_brew "$bin"

  FAKE_COMMAND_LOG="$log" FAKE_BREW_PREFIX="$prefix" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/macos.sh" --install-missing

  assert_log_contains "$log" "brew install ripgrep" "macOS install should use Homebrew when requested"
  assert_log_contains "$log" "brew install actionlint" "macOS install should map actionlint to Homebrew"
  assert_log_contains "$log" "brew install typos-cli" "macOS install should map typos to Homebrew typos-cli"
  assert_log_contains "$log" "brew install just" "macOS install should map just to Homebrew"
  assert_log_contains "$log" "brew install difftastic" "macOS install should map difftastic to Homebrew"
  assert_log_contains "$log" "brew install pandoc" "macOS install should map pandoc to Homebrew"
  assert_log_contains "$log" "brew install imagemagick" "macOS install should map ImageMagick to Homebrew"
  assert_log_contains "$log" "brew install ffmpeg" "macOS install should map ffmpeg to Homebrew"
  assert_log_contains "$log" "brew install exiftool" "macOS install should map exiftool to Homebrew"
  assert_log_contains "$log" "brew install gnu-tar" "macOS install should map tar to GNU tar"
  assert_log_contains "$log" "brew install zip" "macOS install should map zip to Homebrew"
  assert_log_contains "$log" "brew install unzip" "macOS install should map unzip to Homebrew"
  assert_log_contains "$log" "brew install rsync" "macOS install should map rsync to Homebrew"
  assert_log_contains "$log" "brew install vim" "macOS install should map xxd to Vim"
  assert_log_contains "$log" "brew install util-linux" "macOS install should map hexdump to util-linux"
  assert_log_contains "$log" "brew install coreutils" "macOS install should map stat and realpath to coreutils"
  assert_log_contains "$log" "brew install uv" "macOS install should map uv to Homebrew"
  assert_log_contains "$log" "brew install pre-commit" "macOS install should map pre-commit to Homebrew"
  assert_log_contains "$log" "brew install ast-grep" "macOS install should map ast-grep to Homebrew"
}

test_macos_install_without_brew_prints_guidance() {
  local dir bin log output
  dir="$(new_case_dir macos-no-brew)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"

  FAKE_COMMAND_LOG="$log" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/macos.sh" --install-missing

  assert_contains "$output" "Homebrew was not found" "macOS should print Homebrew guidance"
  assert_log_not_contains "$log" "brew install" "macOS without Homebrew should not invoke installs"
}

test_macos_empty_successful_version_output_is_not_a_failure() {
  local dir bin log output prefix rg_dir path_value
  dir="$(new_case_dir macos-empty-version)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  prefix="$dir/homebrew"
  rg_dir="$prefix/Cellar/ripgrep/15.0.0/bin"
  mkdir -p "$rg_dir"
  add_common_shell_utilities "$bin"
  add_fake_brew "$bin"
  add_fake_empty_version_tool "$rg_dir" rg
  path_value="$rg_dir:$bin"

  FAKE_COMMAND_LOG="$log" FAKE_BREW_PREFIX="$prefix" run_with_path "$output" "$path_value" /bin/bash "$ROOT_DIR/macos.sh"

  assert_contains "$output" "[found]   ripgrep" "macOS should find fake ripgrep"
  assert_contains "$output" "package version: ripgrep 15.0.0" "macOS should use Homebrew metadata for empty successful version output"
  assert_contains "$output" "Version checks failed:  0" "macOS should not fail successful empty version checks"
  assert_not_contains "$output" "version output empty" "macOS should prefer package metadata when it is available"
  assert_not_contains "$output" "version check failed" "macOS should not report successful empty version output as failed"
}

test_macos_caps_long_version_output() {
  local dir bin output
  dir="$(new_case_dir macos-long-version)"
  bin="$dir/bin"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_long_version_tool "$bin" rg

  run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/macos.sh"

  assert_contains "$output" "[found]   ripgrep" "macOS should find fake ripgrep"
  assert_contains "$output" "12345678901234567890123456789012345678901234567890123456789012345678901234567..." "macOS should shorten long version output with ellipsis"
  assert_not_contains "$output" "hidden-tail" "macOS should omit text beyond the version display cap"
}

test_macos_extracts_precise_version_strings() {
  local dir bin output
  dir="$(new_case_dir macos-precise-versions)"
  bin="$dir/bin"
  output="$dir/output.txt"
  add_common_shell_utilities "$bin"
  add_fake_multiline_shellcheck_tool "$bin"
  add_fake_cluttered_imagemagick_tool "$bin"

  run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/macos.sh"

  assert_contains "$output" "[found]   shellcheck" "macOS should find fake ShellCheck"
  assert_contains "$output" "0.11.0" "macOS should scan later version output lines"
  assert_not_contains "$output" "ShellCheck - shell script analysis tool" "macOS should not report ShellCheck's descriptive banner"
  assert_not_contains "$output" "license: GNU" "macOS should not report later ShellCheck metadata"
  assert_contains "$output" "[found]   imagemagick" "macOS should find fake ImageMagick"
  assert_contains "$output" "7.1.2-23" "macOS should extract ImageMagick's compact version token"
  assert_not_contains "$output" "Version: ImageMagick" "macOS should not report ImageMagick's verbose banner"
  assert_not_contains "$output" "Q16-HDRI" "macOS should not report ImageMagick build metadata"
}

test_macos_formats_display_paths() {
  local dir bin output home node_dir long_dir path_value home_marker
  dir="$(new_case_dir macos-display-paths)"
  bin="$dir/bin"
  output="$dir/output.txt"
  home="$dir/home"
  node_dir="$home/.nvm/versions/node/v22.22.2/bin"
  long_dir="$dir/path-segment-that-should-disappear/versions/node/v22.22.2/bin"
  mkdir -p "$node_dir" "$long_dir"
  add_common_shell_utilities "$bin"
  add_fake_tool "$node_dir" node
  add_fake_tool "$long_dir" rg
  path_value="$long_dir:$node_dir:$bin"
  home_marker="~"

  HOME="$home" run_with_path "$output" "$path_value" /bin/bash "$ROOT_DIR/macos.sh"

  assert_contains "$output" "$home_marker/.nvm/versions/node/v22.22.2/bin/node" "macOS should display home paths with tilde"
  assert_contains "$output" ".../versions/node/v22.22.2/bin/rg" "macOS should preserve the useful tail when shortening long paths"
  assert_not_contains "$output" "$home/.nvm" "macOS should not print the full home directory in display paths"
  assert_not_contains "$output" "path-segment-that-should-disappear" "macOS should omit the middle of overlong display paths"
}

test_macos_upgrade_managed_uses_homebrew_owner() {
  local dir bin log output prefix rg_dir path_value
  dir="$(new_case_dir macos-upgrade-managed)"
  bin="$dir/bin"
  log="$dir/commands.log"
  output="$dir/output.txt"
  prefix="$dir/homebrew"
  rg_dir="$prefix/Cellar/ripgrep/1.0/bin"
  mkdir -p "$rg_dir"
  add_common_shell_utilities "$bin"
  add_fake_brew "$bin"
  add_fake_tool "$rg_dir" rg
  path_value="$rg_dir:$bin"

  FAKE_COMMAND_LOG="$log" FAKE_BREW_PREFIX="$prefix" run_with_path "$output" "$path_value" /bin/bash "$ROOT_DIR/macos.sh" --upgrade-managed

  assert_contains "$output" "homebrew:ripgrep" "macOS should report Homebrew ownership"
  assert_log_contains "$log" "brew outdated --quiet ripgrep" "macOS should check Homebrew outdated state"
  assert_log_contains "$log" "brew upgrade ripgrep" "macOS should upgrade managed Homebrew tool"
  assert_log_not_contains "$log" "brew install fd" "macOS upgrade should not install missing tools"
}

run_test() {
  local name="$1"
  shift
  echo "test: $name"
  "$@"
  echo "ok: $name"
}

run_test "linux check-only does not install" test_linux_check_only_does_not_install
run_test "linux install-missing uses selected managers" test_linux_install_missing_uses_selected_managers
run_test "linux zypper rebuilds metadata after install failure" test_linux_zypper_rebuilds_metadata_after_install_failure
run_test "linux GitHub release downloads use token" test_linux_github_release_downloads_use_token_when_available
run_test "linux empty successful version output is not a failure" test_linux_empty_successful_version_output_is_not_a_failure
run_test "linux caps long version output" test_linux_caps_long_version_output
run_test "linux extracts precise version strings" test_linux_extracts_precise_version_strings
run_test "linux formats display paths" test_linux_formats_display_paths
run_test "linux finds vendor_perl ExifTool" test_linux_finds_vendor_perl_exiftool
run_test "linux verbose FFmpeg version output is not a pipefail failure" test_linux_verbose_ffmpeg_version_output_is_not_a_pipefail_failure
run_test "linux upgrade-managed uses managed owner only" test_linux_upgrade_managed_uses_owner_only
run_test "linux install-missing without manager prints guidance" test_linux_install_without_manager_prints_guidance
run_test "macOS check-only does not install" test_macos_check_only_does_not_install
run_test "macOS install-missing uses Homebrew" test_macos_install_missing_uses_brew
run_test "macOS install-missing without Homebrew prints guidance" test_macos_install_without_brew_prints_guidance
run_test "macOS empty successful version output is not a failure" test_macos_empty_successful_version_output_is_not_a_failure
run_test "macOS caps long version output" test_macos_caps_long_version_output
run_test "macOS extracts precise version strings" test_macos_extracts_precise_version_strings
run_test "macOS formats display paths" test_macos_formats_display_paths
run_test "macOS upgrade-managed uses Homebrew owner" test_macos_upgrade_managed_uses_homebrew_owner
