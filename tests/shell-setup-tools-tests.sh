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
  link_utility "$bin_dir" rm

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
        "printf '$manager %s\n' \"\$*\" >> \"\$FAKE_COMMAND_LOG\""
      ;;
    *)
      fail "unsupported fake Linux manager: $manager"
      ;;
  esac
}

add_fake_github_release_installers() {
  local bin_dir="$1"

  write_executable "$bin_dir/curl" \
    'case "$1" in' \
    '  --version)' \
    '    printf "curl 8.0\n"' \
    '    ;;' \
    '  -fsSL)' \
    '    case "$2" in' \
    '      *api.github.com/repos/rhysd/actionlint/releases/latest*)' \
    '        printf "%s\n" "{\"browser_download_url\":\"https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz\"}"' \
    '        printf "%s\n" "{\"browser_download_url\":\"https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_arm64.tar.gz\"}"' \
    '        printf "%s\n" "{\"browser_download_url\":\"https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_386.tar.gz\"}"' \
    '        ;;' \
    '      *api.github.com/repos/crate-ci/typos/releases/latest*)' \
    '        printf "%s\n" "{\"name\":\"typos-v1.47.2-x86_64-unknown-linux-musl.tar.gz\"}"' \
    '        printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '        printf "%s\n" "{\"browser_download_url\":\"https://github.com/crate-ci/typos/releases/download/v1.47.2/typos-v1.47.2-x86_64-unknown-linux-musl.tar.gz\"}"' \
    '        printf "%s\n" "{\"name\":\"typos-v1.47.2-aarch64-unknown-linux-musl.tar.gz\"}"' \
    '        printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '        printf "%s\n" "{\"browser_download_url\":\"https://github.com/crate-ci/typos/releases/download/v1.47.2/typos-v1.47.2-aarch64-unknown-linux-musl.tar.gz\"}"' \
    '        ;;' \
    '      *api.github.com/repos/Wilfred/difftastic/releases/latest*)' \
    '        printf "%s\n" "{\"name\":\"difft-x86_64-unknown-linux-gnu.tar.gz\"}"' \
    '        printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '        printf "%s\n" "{\"browser_download_url\":\"https://github.com/Wilfred/difftastic/releases/download/0.69.0/difft-x86_64-unknown-linux-gnu.tar.gz\"}"' \
    '        printf "%s\n" "{\"name\":\"difft-aarch64-unknown-linux-gnu.tar.gz\"}"' \
    '        printf "%s\n" "{\"digest\":\"sha256:fake\"}"' \
    '        printf "%s\n" "{\"browser_download_url\":\"https://github.com/Wilfred/difftastic/releases/download/0.69.0/difft-aarch64-unknown-linux-gnu.tar.gz\"}"' \
    '        ;;' \
    '      *)' \
    '        printf "fake actionlint archive\n"' \
    '        ;;' \
    '    esac' \
    '    ;;' \
    '  *)' \
    '    exit 2' \
    '    ;;' \
    'esac'

  write_executable "$bin_dir/tar" \
    'printf "tar %s\n" "$*" >> "$FAKE_COMMAND_LOG"' \
    ': > actionlint' \
    ': > typos' \
    ': > difft'

  write_executable "$bin_dir/install" \
    'printf "install %s\n" "$*" >> "$FAKE_COMMAND_LOG"'
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

  for manager in apt dnf pacman zypper; do
    dir="$(new_case_dir "linux-install-$manager")"
    bin="$dir/bin"
    log="$dir/commands.log"
    output="$dir/output.txt"
    add_common_shell_utilities "$bin"
    add_fake_linux_manager "$bin" "$manager"
    add_fake_github_release_installers "$bin"

    FAKE_COMMAND_LOG="$log" run_with_path "$output" "$bin" /bin/bash "$ROOT_DIR/linux.sh" --manager "$manager" --install-missing

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
        expected_exiftool="zypper install -y perl-Image-ExifTool"
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
    assert_log_contains "$log" "$last_expected" "linux install should keep processing tools after $manager invokes a package command"
    if [ "$manager" = "apt" ]; then
      assert_log_contains "$log" "DEBIAN_FRONTEND=noninteractive" "apt installs should run noninteractively"
    fi
  done
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
run_test "linux empty successful version output is not a failure" test_linux_empty_successful_version_output_is_not_a_failure
run_test "linux upgrade-managed uses managed owner only" test_linux_upgrade_managed_uses_owner_only
run_test "linux install-missing without manager prints guidance" test_linux_install_without_manager_prints_guidance
run_test "macOS check-only does not install" test_macos_check_only_does_not_install
run_test "macOS install-missing uses Homebrew" test_macos_install_missing_uses_brew
run_test "macOS install-missing without Homebrew prints guidance" test_macos_install_without_brew_prints_guidance
run_test "macOS empty successful version output is not a failure" test_macos_empty_successful_version_output_is_not_a_failure
run_test "macOS upgrade-managed uses Homebrew owner" test_macos_upgrade_managed_uses_homebrew_owner
