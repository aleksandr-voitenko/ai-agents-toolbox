## The intent
This is your AI agent on a typical developer machine: eager to help, but missing half the tools it needs. The AI Agents Toolbox project aims to solve this problem for you. 

<img width="640" height="360" alt="Cartoon-style workshop scene showing a confused craftsman in overalls pulling out his empty pockets while looking for missing tools." src="https://github.com/user-attachments/assets/7770f5e2-0454-403e-8634-6c93f45b7ba9" />


## Why This Exists

Every agentic coding session is better when the boring tools are already there:
fast search, JSON and YAML processors, GitHub workflow checks, formatters,
shell linters, PDF utilities, and the little CLI helpers that turn "one quick
change" into actual momentum.

This toolbox gives any AI agent (or a developer) a quick, conservative way to check
a machine and optionally install the missing essentials through a package manager
they already use. Try it when a fresh laptop, container, or borrowed workstation
needs to feel ready for real AI-assisted development instead of another setup
scavenger hunt.

## Tools Managed

The scripts manage these logical tools across supported platforms:

```text
ripgrep (rg) - Fast recursive text searcher with Git-aware defaults.
fd - Fast filesystem search alternative to find.
jq - Command-line JSON processor for querying and transforming structured data.
curl - URL client for HTTP requests, downloads, and install bootstrapping.
sqlite3 - Command-line shell for inspecting and managing SQLite databases.
yq - Command-line YAML, JSON, XML, TOML, and properties processor.
actionlint - Static checker for GitHub Actions workflow files.
typos - Source-code-aware spell checker for code, docs, and config files.
clang-format - Source formatter for C, C++, Objective-C, Java, JavaScript, and related languages.
gh - GitHub CLI for repository, pull request, issue, and workflow operations.
git - Distributed version control CLI.
git-delta (delta) - Syntax-highlighting pager for Git and diff output.
just - Command runner for project-local recipes and repeatable tasks.
difftastic (difft) - Syntax-aware structural diff tool.
node - JavaScript runtime for local tooling and application scripts.
yarn - JavaScript package manager and project script runner.
python - Python runtime for scripts, tests, and developer utilities.
cmake - Cross-platform build system generator.
ninja - Small, fast build executor commonly used with CMake.
bat - Syntax-highlighting file viewer and cat replacement.
eza - Modern directory listing tool and ls replacement.
fzf - Interactive fuzzy finder for shells and scripts.
tree - Recursive directory tree viewer.
file - File type detector based on content signatures.
pandoc - Universal document converter for markup and publishing workflows.
imagemagick (magick/convert) - Image inspection and conversion toolkit.
ffmpeg - Audio and video recording, conversion, and inspection toolkit.
exiftool - Metadata reader and writer for images, media, and documents.
hyperfine - Command-line benchmarking tool.
shellcheck - Static analyzer for shell scripts.
shfmt - Formatter for shell scripts.
ghostscript (gs) - PostScript and PDF interpreter used by document workflows.
pdftotext - PDF text extraction tool from Poppler.
```

Some tools have different package names than command names. For example,
`sqlite3` may be installed by a `sqlite` package, `delta` is often installed by
the `git-delta` package, `difft` by `difftastic`, and `typos` by Homebrew's
`typos-cli` formula. Some Linux distributions also package `pandoc`, `ffmpeg`,
ImageMagick, and ExifTool under distribution-specific names.

## One-Line Installers

macOS, using the default `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/aleksandr-voitenko/ai-agents-toolbox/main/macos.sh | bash -s -- --install-missing
```

Linux, using `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/aleksandr-voitenko/ai-agents-toolbox/main/linux.sh | bash -s -- --install-missing
```

Linux, using `wget`:

```sh
wget -qO- https://raw.githubusercontent.com/aleksandr-voitenko/ai-agents-toolbox/main/linux.sh | bash -s -- --install-missing
```

Windows, using PowerShell:

```powershell
$u="https://raw.githubusercontent.com/aleksandr-voitenko/ai-agents-toolbox/main/windows.ps1"; $f=Join-Path $env:TEMP "ai-agents-toolbox-windows.ps1"; Invoke-WebRequest -UseBasicParsing $u -OutFile $f; powershell -ExecutionPolicy Bypass -File $f -InstallMissing
```

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
