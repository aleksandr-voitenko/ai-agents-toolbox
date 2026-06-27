# ai-agents-toolbox Memory

## Project Purpose

This folder contains a small cross-platform AI developer-tool bootstrapper. Its job is to help a user check for, install, and optionally upgrade common command-line tools used by this workspace without surprising them or taking ownership of their machine.

The product should feel like a safe prerequisite checker with optional install behavior, not a workstation provisioning framework.

- Detect required tools before attempting installation.
- Report the command path, best-effort installation source, and version.
- Install only missing tools, and only when the user explicitly asks.
- Upgrade only tools that appear to be managed by the same detected package
  manager, and only when the user explicitly asks.
- Never replace, shadow, remove, or upgrade tools from unknown/manual sources.
- Never install package managers automatically. If none is available, print clear guidance and links.

This conservative stance is the main project invariant.

## Repository Shape

- `setup-tools.sh` dispatches to the OS-specific shell script on macOS or Linux and points Windows users to PowerShell.
- `macos.sh` uses Homebrew if it already exists.
- `linux.sh` detects `apt`, `dnf`, `pacman`, or `zypper`, with optional `--manager`.
- `windows.ps1` detects `winget`, Scoop, or Chocolatey, with optional `-Manager`.
- `.github/workflows/ci.yml` runs PR/push smoke checks and hermetic fake-manager tests.
- `.github/workflows/nightly-install-smoke.yml` runs real install smoke checks on disposable runners and containers for PRs, pushes, and the preserved nightly schedule while live package-manager failures are being debugged.
- `tests/shell-setup-tools-tests.sh` and `tests/windows-setup-tools-tests.ps1` exercise conservative install and upgrade behavior with fake tools and package managers.
- `README.md`, when present, is the human-facing usage guide. Keep this file focused on durable project context for maintainers and agents.

## Behavioral Constraints

- Default behavior must remain check-only.
- Any installation behavior must require `--install-missing` on shell scripts or `-InstallMissing` on PowerShell.
- Any upgrade behavior must require `--upgrade-managed` on shell scripts or `-UpgradeManaged` on PowerShell.
- Do not add a global "upgrade everything" mode.
- Do not install Homebrew, winget, Scoop, Chocolatey, or Linux package managers.
- Do not silently switch package managers for an already-installed command.
- Treat source detection as best effort and label uncertain cases honestly.
- Preserve support for commands whose package name differs from their executable name, such as `sqlite` -> `sqlite3`, `git-delta` -> `delta`, `libmagic` -> `file`, `ghostscript` -> `gs`, and `poppler`/`poppler-utils` -> `pdftotext`.
- Be careful with Windows: PATH shims and multi-manager ownership can be messy. Prefer reporting uncertainty over making destructive assumptions.

## Implementation Guidance

- Keep scripts dependency-light. They should still be able to run before tools like `jq`, `python`, or `node` are installed.
- Keep OS-specific behavior in the OS-specific script. Avoid forcing a shared runtime or manifest parser unless it is already available on a fresh machine.
- Prefer clear output over clever output. Users should be able to tell what was found, where it came from, and why an action was skipped.
- When adding a tool, update all relevant OS scripts and any user-facing documentation that exists.
- If adding a package manager, add it conservatively and include source detection and package-manager guidance. Do not make it the default unless it is widely available and low surprise.
- If adding version checks, handle commands that return nonzero for `--version`. Do not treat error output as a valid version.

## Verification

For shell changes, run:

```sh
bash -n setup-tools.sh
bash -n macos.sh
bash -n linux.sh
shellcheck setup-tools.sh macos.sh linux.sh
bash tests/shell-setup-tools-tests.sh
```

For PowerShell or Windows behavior changes, run when `pwsh` is available:

```sh
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/windows-setup-tools-tests.ps1
```

On macOS, also run:

```sh
./macos.sh
```

The GitHub Actions PR workflow runs hosted check-only smoke tests on Ubuntu, macOS, and Windows. The install smoke workflow also runs real install checks with Linux `apt`, `dnf`, `pacman`, and `zypper` containers, macOS Homebrew, and Windows Chocolatey on PRs, pushes, and the preserved nightly schedule while live package-manager failures are being debugged.

`shellcheck` and PowerShell validation may require extra local tools. If `pwsh` or Windows is not available, say so in the final response and describe what was statically checked.
