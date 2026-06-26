# Developer Tool Setup

These scripts check for the command-line tools used by this workspace and can
install missing tools through an already-installed package manager.

They are intentionally conservative:

- The default mode is check-only.
- Existing commands are detected before any install attempt.
- Missing tools are installed only with `--install-missing` or `-InstallMissing`.
- Existing tools from unknown or manual sources are not replaced.
- Existing tools are upgraded only with `--upgrade-managed` or `-UpgradeManaged`,
  and only when they appear to be owned by the same package manager.
- Package managers are never installed automatically.

## Tools Checked

Core workspace tools:

```text
rg fd jq clang-format gh git node yarn python cmake ninja
```

Convenience and document tools:

```text
bat eza fzf tree hyperfine shellcheck shfmt gs pdftotext
```

Some tools have different package names than command names. For example,
`gs` is installed by the `ghostscript` package, and `pdftotext` is installed by
the `poppler` or `poppler-utils` package.

## macOS

Check only:

```sh
./macos.sh
```

Install missing tools with Homebrew:

```sh
./macos.sh --install-missing
```

Upgrade only tools already managed by Homebrew:

```sh
./macos.sh --upgrade-managed
```

If Homebrew is not installed, install it from:

```text
https://brew.sh/
```

Then rerun the script.

## Linux

Check only:

```sh
./linux.sh
```

Install missing tools with the detected package manager:

```sh
./linux.sh --install-missing
```

When `--manager` is not specified, Linux installs missing tools with the first
available manager in this order: `apt`, `dnf`, `pacman`, then `zypper`.

Upgrade only tools already managed by apt, rpm/dnf/zypper, or pacman:

```sh
./linux.sh --upgrade-managed
```

Force a specific supported package manager:

```sh
./linux.sh --manager apt --install-missing
```

Supported Linux package managers:

```text
apt      Debian and Ubuntu
dnf      Fedora and RHEL-family distributions
pacman   Arch Linux
zypper   openSUSE
```

If none of those exists, install or enable the package manager for your
distribution and rerun the script.

Linux package availability varies by distribution version. If a package is not
available from the native repository, the script reports the failure instead of
switching to a different installation source.

## Windows

Check only:

```powershell
powershell -ExecutionPolicy Bypass -File windows.ps1
```

Install missing tools:

```powershell
powershell -ExecutionPolicy Bypass -File windows.ps1 -InstallMissing
```

When `-Manager` is not specified, Windows installs missing tools with the first
available manager in this order: `winget`, Scoop, then Chocolatey.

Upgrade only tools already managed by winget, Scoop, or Chocolatey:

```powershell
powershell -ExecutionPolicy Bypass -File windows.ps1 -UpgradeManaged
```

Use a specific package manager for missing installs:

```powershell
powershell -ExecutionPolicy Bypass -File windows.ps1 -InstallMissing -Manager scoop
```

Supported Windows package managers:

```text
winget      https://learn.microsoft.com/windows/package-manager/winget/
Scoop       https://scoop.sh/
Chocolatey  https://chocolatey.org/install
```

When `-InstallMissing` is used and missing tools are found, the script suggests
those links if no supported Windows package manager is available. It does not
install any package manager automatically.

## Cross-platform Wrapper

On macOS and Linux, you can use:

```sh
./setup-tools.sh
```

The wrapper dispatches to the OS-specific shell script. On Windows, use the
PowerShell script directly.

## CI

Pull requests and pushes to `main` run hosted smoke checks on Ubuntu, macOS,
and Windows. They also run hermetic fake-manager tests that verify install and
upgrade behavior without touching real package managers.

The install smoke workflow also runs the opt-in install path on disposable
Linux distro containers, macOS with Homebrew, and Windows with Chocolatey. It
is enabled for pull requests, pushes, and its nightly schedule while live
package-manager failures are being debugged.

Run the hermetic tests locally with:

```sh
bash tests/shell-setup-tools-tests.sh
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/windows-setup-tools-tests.ps1
```

## Notes

The source detection is best effort. It is usually reliable for Homebrew,
apt/dpkg, rpm/dnf, pacman, Scoop, Chocolatey, and many winget installs. Manual
installs, custom shims, and PATH entries created by SDKs may be reported as
`unknown`, `system`, `local`, `cargo`, or `npm-or-node`. Those are deliberately
not upgraded or replaced.

Yarn may be reported as a Corepack shim. In that case the command exists, but
the exact Yarn version is selected by each project through `packageManager` in
`package.json`.
