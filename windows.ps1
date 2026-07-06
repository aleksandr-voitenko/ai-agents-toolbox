param(
  [switch]$Help,
  [switch]$CheckOnly,
  [switch]$InstallMissing,
  [switch]$UpgradeManaged,
  [ValidateSet("auto", "winget", "scoop", "choco")]
  [string]$Manager = "auto"
)

$ErrorActionPreference = "Stop"
$PathDisplayWidth = 52
$SourceDisplayWidth = 36
$VersionDisplayMax = 48

function Show-Help {
  @"
Usage:
  powershell -ExecutionPolicy Bypass -File .\windows.ps1 [options]

Options:
  -CheckOnly        Check tools and report status. This is the default.
  -InstallMissing  Install missing tools using an existing package manager.
  -UpgradeManaged  Upgrade tools already managed by the same package manager only.
  -Manager NAME    Use auto, winget, scoop, or choco for missing installs.

This script never installs a package manager. If none is available, it prints
guidance. Existing commands from unknown/manual sources are not replaced.
"@
}

if ($PSBoundParameters.ContainsKey("Help")) {
  Show-Help
  exit 0
}

$Tools = @(
  @{ Name = "ripgrep"; Commands = @("rg.exe", "rg"); Winget = "BurntSushi.ripgrep.MSVC"; Scoop = "ripgrep"; Choco = "ripgrep" },
  @{ Name = "fd"; Commands = @("fd.exe", "fd"); Winget = "sharkdp.fd"; Scoop = "fd"; Choco = "fd" },
  @{ Name = "jq"; Commands = @("jq.exe", "jq"); Winget = "jqlang.jq"; Scoop = "jq"; Choco = "jq" },
  @{ Name = "curl"; Commands = @("curl.exe"); Winget = "cURL.cURL"; Scoop = "curl"; Choco = "curl" },
  @{ Name = "sqlite3"; Commands = @("sqlite3.exe", "sqlite3"); Winget = "SQLite.SQLite"; Scoop = "sqlite"; Choco = "sqlite" },
  @{ Name = "yq"; Commands = @("yq.exe", "yq"); Winget = "MikeFarah.yq"; Scoop = "yq"; Choco = "yq" },
  @{ Name = "actionlint"; Commands = @("actionlint.exe", "actionlint"); Winget = "rhysd.actionlint"; Scoop = "actionlint"; Choco = "actionlint" },
  @{ Name = "typos"; Commands = @("typos.exe", "typos"); Winget = $null; Scoop = "typos"; Choco = "typos" },
  @{ Name = "clang-format"; Commands = @("clang-format.exe", "clang-format"); Winget = "LLVM.LLVM"; Scoop = "llvm"; Choco = "llvm" },
  @{ Name = "gh"; Commands = @("gh.exe", "gh"); Winget = "GitHub.cli"; Scoop = "gh"; Choco = "gh" },
  @{ Name = "git"; Commands = @("git.exe", "git"); Winget = "Git.Git"; Scoop = "git"; Choco = "git" },
  @{ Name = "git-delta"; Commands = @("delta.exe", "delta"); Winget = $null; Scoop = "delta"; Choco = "delta" },
  @{ Name = "just"; Commands = @("just.exe", "just"); Winget = "Casey.Just"; Scoop = "just"; Choco = "just" },
  @{ Name = "difftastic"; Commands = @("difft.exe", "difft"); Winget = "Wilfred.difftastic"; Scoop = "difftastic"; Choco = "difftastic" },
  @{ Name = "node"; Commands = @("node.exe", "node"); Winget = "OpenJS.NodeJS.LTS"; Scoop = "nodejs-lts"; Choco = "nodejs-lts" },
  @{ Name = "yarn"; Commands = @("yarn.cmd", "yarn.exe", "yarn"); Winget = "Yarn.Yarn"; Scoop = "yarn"; Choco = "yarn" },
  @{ Name = "python"; Commands = @("python.exe", "python", "py.exe", "py"); Winget = "Python.Python.3"; Scoop = "python"; Choco = "python" },
  @{ Name = "cmake"; Commands = @("cmake.exe", "cmake"); Winget = "Kitware.CMake"; Scoop = "cmake"; Choco = "cmake" },
  @{ Name = "ninja"; Commands = @("ninja.exe", "ninja"); Winget = "Ninja-build.Ninja"; Scoop = "ninja"; Choco = "ninja" },
  @{ Name = "bat"; Commands = @("bat.exe", "bat"); Winget = "sharkdp.bat"; Scoop = "bat"; Choco = "bat" },
  @{ Name = "eza"; Commands = @("eza.exe", "eza"); Winget = "eza-community.eza"; Scoop = "eza"; Choco = "eza" },
  @{ Name = "fzf"; Commands = @("fzf.exe", "fzf"); Winget = "junegunn.fzf"; Scoop = "fzf"; Choco = "fzf" },
  @{ Name = "tree"; Commands = @("tree.exe", "tree", "tree.com"); Winget = $null; Scoop = "tree"; Choco = "tree" },
  @{ Name = "file"; Commands = @("file.exe", "file"); Winget = $null; Scoop = "file"; Choco = "file" },
  @{ Name = "pandoc"; Commands = @("pandoc.exe", "pandoc"); Winget = "JohnMacFarlane.Pandoc"; Scoop = "pandoc"; Choco = "pandoc" },
  @{ Name = "imagemagick"; Commands = @("magick.exe", "magick"); Winget = "ImageMagick.ImageMagick"; Scoop = "imagemagick"; Choco = "imagemagick" },
  @{ Name = "ffmpeg"; Commands = @("ffmpeg.exe", "ffmpeg"); Winget = "Gyan.FFmpeg"; Scoop = "ffmpeg"; Choco = "ffmpeg" },
  @{ Name = "exiftool"; Commands = @("exiftool.exe", "exiftool"); Winget = "OliverBetz.ExifTool"; Scoop = "exiftool"; Choco = "exiftool" },
  @{ Name = "hyperfine"; Commands = @("hyperfine.exe", "hyperfine"); Winget = "sharkdp.hyperfine"; Scoop = "hyperfine"; Choco = "hyperfine" },
  @{ Name = "shellcheck"; Commands = @("shellcheck.exe", "shellcheck"); Winget = "koalaman.shellcheck"; Scoop = "shellcheck"; Choco = "shellcheck" },
  @{ Name = "shfmt"; Commands = @("shfmt.exe", "shfmt"); Winget = "mvdan.shfmt"; Scoop = "shfmt"; Choco = "shfmt" },
  @{ Name = "tar"; Commands = @("tar.exe", "tar"); Winget = $null; Scoop = $null; Choco = $null },
  @{ Name = "zip"; Commands = @("zip.exe", "zip"); Winget = $null; Scoop = "zip"; Choco = "zip" },
  @{ Name = "unzip"; Commands = @("unzip.exe", "unzip"); Winget = $null; Scoop = "unzip"; Choco = "unzip" },
  @{ Name = "rsync"; Commands = @("rsync.exe", "rsync"); Winget = $null; Scoop = $null; Choco = "rsync" },
  @{ Name = "xxd"; Commands = @("xxd.exe", "xxd"); Winget = $null; Scoop = "vim"; Choco = "xxd" },
  @{ Name = "hexdump"; Commands = @("hexdump.exe", "hexdump"); Winget = $null; Scoop = $null; Choco = $null },
  @{ Name = "stat"; Commands = @("stat.exe", "stat"); Winget = "Microsoft.Coreutils"; Scoop = "coreutils"; Choco = "mscoreutils" },
  @{ Name = "realpath"; Commands = @("realpath.exe", "realpath"); Winget = "Microsoft.Coreutils"; Scoop = "coreutils"; Choco = "mscoreutils" },
  @{ Name = "uv"; Commands = @("uv.exe", "uv"); Winget = "astral-sh.uv"; Scoop = "uv"; Choco = "uv" },
  @{ Name = "pre-commit"; Commands = @("pre-commit.exe", "pre-commit"); Winget = $null; Scoop = $null; Choco = $null },
  @{ Name = "ast-grep"; Commands = @("ast-grep.exe", "ast-grep"); Winget = "ast-grep.ast-grep"; Scoop = "ast-grep"; Choco = $null },
  @{ Name = "ghostscript"; Commands = @("gswin64c.exe", "gswin32c.exe", "gs.exe", "gs"); Winget = $null; Scoop = "ghostscript"; Choco = "ghostscript" },
  @{ Name = "pdftotext"; Commands = @("pdftotext.exe", "pdftotext"); Winget = "oschwartz10612.Poppler"; Scoop = "poppler"; Choco = "poppler" }
)

function Test-CommandExists {
  param([string]$Name)
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-WindowsPythonAppExecutionAlias {
  param([System.Management.Automation.CommandInfo]$Command)

  $source = $Command.Source
  if (-not $source) {
    return $false
  }

  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($source)
  $normalized = $source.ToLowerInvariant()
  return (($baseName -eq "python" -or $baseName -eq "python3") -and $normalized -like "*\microsoft\windowsapps\*")
}

function Test-ToolCommandUsable {
  param(
    [hashtable]$Tool,
    [System.Management.Automation.CommandInfo]$Command
  )

  if ($null -ne $Tool -and $Tool.Name -eq "python" -and (Test-WindowsPythonAppExecutionAlias $Command)) {
    # The Windows Store App Execution Alias looks like python.exe on PATH even
    # when it only redirects users to install Python. Keep it only if it can
    # answer the same version probe as a real runtime.
    $version = Get-VersionLine $Command
    return ($version -and $version -ne "version check failed")
  }

  return $true
}

function Get-ToolCommand {
  param(
    [string[]]$Commands,
    [hashtable]$Tool = $null
  )

  foreach ($candidate in $Commands) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd) {
      if (-not (Test-ToolCommandUsable $Tool $cmd)) {
        continue
      }
      return $cmd
    }
  }

  return $null
}

function Test-WingetInstalled {
  param([string]$Id)

  if (-not $Id -or -not (Test-CommandExists "winget")) {
    return $false
  }

  try {
    $output = winget list --id $Id --exact --disable-interactivity 2>$null
    return ($LASTEXITCODE -eq 0 -and ($output -join "`n") -match [regex]::Escape($Id))
  } catch {
    return $false
  }
}

function Test-ScoopInstalled {
  param([string]$Package)

  if (-not $Package -or -not (Test-CommandExists "scoop")) {
    return $false
  }

  try {
    scoop list $Package *> $null
    return $LASTEXITCODE -eq 0
  } catch {
    return $false
  }
}

function Test-ChocoInstalled {
  param([string]$Package)

  if (-not $Package -or -not (Test-CommandExists "choco")) {
    return $false
  }

  try {
    $output = choco list --local-only --exact $Package --limit-output 2>$null
    return ($LASTEXITCODE -eq 0 -and ($output -join "`n") -match "^$([regex]::Escape($Package))\|")
  } catch {
    return $false
  }
}

function Get-ToolSource {
  param(
    [string]$Path,
    [hashtable]$Tool
  )

  $normalized = $Path.ToLowerInvariant()

  if ($normalized -like "*\scoop\*" -or $normalized -like "*\scoop\shims\*") {
    if (Test-ScoopInstalled $Tool.Scoop) {
      return "scoop:$($Tool.Scoop)"
    }
    return "scoop:unknown"
  }

  if ($normalized -like "*\chocolatey\*") {
    if (Test-ChocoInstalled $Tool.Choco) {
      return "choco:$($Tool.Choco)"
    }
    return "choco:unknown"
  }

  if ($normalized -like "*\.cargo\bin\*") {
    return "cargo"
  }

  if ($normalized -like "*\npm\*" -or $normalized -like "*\nodejs\*") {
    return "npm-or-node"
  }

  if (Test-WingetInstalled $Tool.Winget) {
    return "winget:$($Tool.Winget)"
  }

  if ($normalized -like "$($env:windir.ToLowerInvariant())\system32\*") {
    return "system"
  }

  return "unknown"
}

function Get-VersionArguments {
  param([string]$CommandName)

  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($CommandName)

  if ($baseName -like "gswin*c" -or $baseName -eq "gs") {
    return @("--version")
  }
  if ($baseName -eq "pdftotext") {
    return @("-v")
  }
  if ($baseName -eq "zip" -or $baseName -eq "unzip") {
    return @("-v")
  }
  if ($baseName -eq "ffmpeg") {
    return @("-version")
  }
  if ($baseName -eq "exiftool") {
    return @("-ver")
  }

  return @("--version")
}

function Get-VersionFromOutput {
  param([object[]]$Output)

  # Match the shell scripts' compact token extraction, with Windows-specific
  # handling for dotted suffixes and path-like values such as file.exe-5.45.
  $versionPattern = '(^|[^A-Za-z0-9_.])(([A-Za-z_]+-)?v?[0-9]+([.][0-9]+)+(([-+][A-Za-z0-9][A-Za-z0-9._-]*)|([.][A-Za-z][A-Za-z0-9._-]*))?)($|[^A-Za-z0-9_.-])'
  $fallback = $null

  foreach ($entry in $Output) {
    foreach ($line in ("$entry" -split '\r?\n')) {
      $trimmed = $line.Trim()
      if ($trimmed.Length -eq 0) {
        continue
      }

      if ($null -eq $fallback) {
        $fallback = $trimmed
      }

      $match = [regex]::Match($line, $versionPattern)
      if ($match.Success) {
        return $match.Groups[2].Value
      }
    }
  }

  if ($null -ne $fallback) {
    return $fallback
  }
  return ""
}

function Get-VersionLine {
  param([System.Management.Automation.CommandInfo]$Command)

  $commandName = [System.IO.Path]::GetFileName($Command.Source)
  if (-not $commandName) {
    $commandName = $Command.Name
  }

  try {
    if ($commandName -eq "tree.com") {
      return "Windows built-in; no version flag"
    }

    $commandPath = $Command.Source
    if (-not $commandPath) {
      $commandPath = $Command.Name
    }

    $versionArguments = @(Get-VersionArguments $commandName)
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      # Some Windows-native version probes, including Poppler's pdftotext,
      # print their successful version banner on stderr.
      $output = & $commandPath @versionArguments 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
      $baseName = [System.IO.Path]::GetFileNameWithoutExtension($commandName)
      if ($baseName -eq "hexdump" -or $baseName -eq "stat" -or $baseName -eq "realpath") {
        return "system utility; no version flag"
      }
      return "version check failed"
    }

    return Get-VersionFromOutput $output
  } catch {
    return "version check failed"
  }
}

function Format-VersionForDisplay {
  param([string]$Version)

  if ($Version.Length -le $VersionDisplayMax) {
    return $Version
  }

  return "$($Version.Substring(0, $VersionDisplayMax - 3))..."
}

function Format-PathForDisplay {
  param([string]$Path)

  if (-not $Path) {
    return ""
  }

  $display = $Path
  if ($env:USERPROFILE) {
    $userProfileRoot = $env:USERPROFILE -replace '[\\/]+$', ''
    $comparison = [System.StringComparison]::OrdinalIgnoreCase
    if ($display.Equals($userProfileRoot, $comparison)) {
      $display = "~"
    } elseif ($display.StartsWith("$userProfileRoot\", $comparison) -or $display.StartsWith("$userProfileRoot/", $comparison)) {
      $display = "~$($display.Substring($userProfileRoot.Length))"
    }
  }

  if ($display.Length -le $PathDisplayWidth) {
    return $display
  }

  $headLength = 12
  $tailLength = $PathDisplayWidth - $headLength - 3
  $tail = $display.Substring($display.Length - $tailLength)
  $separatorIndex = @($tail.IndexOf("\"), $tail.IndexOf("/")) | Where-Object { $_ -ge 0 } | Sort-Object | Select-Object -First 1
  if ($null -ne $separatorIndex) {
    $boundaryTail = $tail.Substring($separatorIndex)
    # Prefer a path-segment boundary unless it would leave most of the
    # fixed-width path column empty for a long final directory segment.
    if ($boundaryTail.Length -ge [Math]::Ceiling($tailLength / 2)) {
      $tail = $boundaryTail
    }
  }
  return "$($display.Substring(0, $headLength))...$tail"
}

function Get-PackageVersionForSource {
  param([string]$Source)

  $parts = $Source.Split(":", 2)
  if ($parts.Count -ne 2) {
    return $null
  }

  $sourceManager = $parts[0]
  $package = $parts[1]
  if (-not $package -or $package -eq "unknown") {
    return $null
  }

  try {
    if ($sourceManager -eq "winget") {
      $output = winget list --id $package --exact --disable-interactivity 2>$null
      if ($LASTEXITCODE -ne 0) { return $null }
      $line = $output | Where-Object { "$_".Trim() -and "$_" -match [regex]::Escape($package) } | Select-Object -First 1
      if ($line) { return "package version: $("$line".Trim())" }
      return $null
    }

    if ($sourceManager -eq "scoop") {
      $output = scoop list $package 2>$null
      if ($LASTEXITCODE -ne 0) { return $null }
      $line = $output | Where-Object { "$_".Trim() -and "$_" -match [regex]::Escape($package) } | Select-Object -First 1
      if ($line) { return "package version: $("$line".Trim())" }
      return $null
    }

    if ($sourceManager -eq "choco") {
      $output = choco list --local-only --exact $package --limit-output 2>$null
      if ($LASTEXITCODE -ne 0) { return $null }
      $line = $output | Where-Object { "$_".Trim() -and "$_" -match "^$([regex]::Escape($package))\|" } | Select-Object -First 1
      if ($line) { return "package version: $("$line".Trim() -replace '\|', ' ')" }
      return $null
    }
  } catch {
    return $null
  }

  return $null
}

function Get-AvailableManagers {
  $available = @()
  if (Test-CommandExists "winget") { $available += "winget" }
  if (Test-CommandExists "scoop") { $available += "scoop" }
  if (Test-CommandExists "choco") { $available += "choco" }
  return $available
}

function Get-InstallManager {
  param([hashtable]$Tool)

  $available = Get-AvailableManagers
  $candidates = @()

  if ($Manager -eq "auto") {
    $candidates = @("winget", "scoop", "choco")
  } else {
    $candidates = @($Manager)
  }

  foreach ($candidate in $candidates) {
    if ($available -notcontains $candidate) {
      continue
    }
    if ($candidate -eq "winget" -and $Tool.Winget) { return "winget" }
    if ($candidate -eq "scoop" -and $Tool.Scoop) { return "scoop" }
    if ($candidate -eq "choco" -and $Tool.Choco) { return "choco" }
  }

  return $null
}

function Get-ToolMappedManagers {
  param([hashtable]$Tool)

  $mapped = @()
  if ($Tool.Winget) { $mapped += "winget" }
  if ($Tool.Scoop) { $mapped += "scoop" }
  if ($Tool.Choco) { $mapped += "choco" }
  return $mapped
}

function Format-ManagerName {
  param([string]$Manager)

  if ($Manager -eq "scoop") { return "Scoop" }
  if ($Manager -eq "choco") { return "Chocolatey" }
  return $Manager
}

function Format-ManagerList {
  param([string[]]$Managers)

  $names = @($Managers | ForEach-Object { Format-ManagerName $_ })
  if ($names.Count -eq 0) { return "" }
  if ($names.Count -eq 1) { return $names[0] }
  if ($names.Count -eq 2) { return "$($names[0]) or $($names[1])" }

  return "$(($names[0..($names.Count - 2)]) -join ', '), or $($names[-1])"
}

function Add-PathEntries {
  param(
    [System.Collections.Generic.List[string]]$Entries,
    [hashtable]$Seen,
    [string]$PathValue
  )

  if ([string]::IsNullOrEmpty($PathValue)) {
    return
  }

  foreach ($entry in ($PathValue -split [System.IO.Path]::PathSeparator)) {
    $trimmed = "$entry".Trim()
    if (-not $trimmed) {
      continue
    }

    $key = $trimmed.ToLowerInvariant()
    if ($Seen.ContainsKey($key)) {
      continue
    }

    [void]$Entries.Add($trimmed)
    $Seen[$key] = $true
  }
}

function Update-ProcessPathFromEnvironment {
  $entries = [System.Collections.Generic.List[string]]::new()
  $seen = @{}

  Add-PathEntries $entries $seen $env:Path
  # Tests and other controlled callers can provide a refresh source without
  # reading the host's persisted PATH; normal runs use Machine and User PATH.
  if ($null -ne $env:AI_AGENTS_TOOLBOX_WINDOWS_REFRESH_PATH) {
    Add-PathEntries $entries $seen $env:AI_AGENTS_TOOLBOX_WINDOWS_REFRESH_PATH
  } else {
    Add-PathEntries $entries $seen ([Environment]::GetEnvironmentVariable("Path", "Machine"))
    Add-PathEntries $entries $seen ([Environment]::GetEnvironmentVariable("Path", "User"))
  }

  $refreshedPath = $entries -join [System.IO.Path]::PathSeparator
  if ($refreshedPath -ne $env:Path) {
    $env:Path = $refreshedPath
    return $true
  }

  return $false
}

function Test-WingetNoApplicableUpgradeExit {
  param([int]$ExitCode)

  # HRESULT 0x8A15002B is returned when `winget install` finds the
  # package already installed, tries upgrade, and finds no newer version.
  return $ExitCode -eq -1978335189
}

function Install-Tool {
  param(
    [string]$InstallManager,
    [hashtable]$Tool
  )

  if ($InstallManager -eq "winget") {
    Write-Host "Installing $($Tool.Name) with winget..."
    winget install --id $Tool.Winget --exact --disable-interactivity --accept-source-agreements --accept-package-agreements
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      if (Test-WingetNoApplicableUpgradeExit $exitCode) {
        return
      }
      throw "Install failed for $($Tool.Name) with winget package $($Tool.Winget) (exit code $exitCode)."
    }
    return
  }

  if ($InstallManager -eq "scoop") {
    Write-Host "Installing $($Tool.Name) with scoop..."
    scoop install $Tool.Scoop
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      throw "Install failed for $($Tool.Name) with scoop package $($Tool.Scoop) (exit code $exitCode)."
    }
    return
  }

  if ($InstallManager -eq "choco") {
    Write-Host "Installing $($Tool.Name) with Chocolatey..."
    choco install $Tool.Choco -y
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      throw "Install failed for $($Tool.Name) with choco package $($Tool.Choco) (exit code $exitCode)."
    }
    return
  }

  throw "Unsupported install manager: $InstallManager"
}

function Upgrade-ManagedTool {
  param([string]$Source)

  $parts = $Source.Split(":", 2)
  if ($parts.Count -ne 2) {
    return $false
  }

  $sourceManager = $parts[0]
  $package = $parts[1]

  if ($package -eq "unknown") {
    return $false
  }

  if ($sourceManager -eq "winget") {
    Write-Host "Upgrading $package with winget..."
    winget upgrade --id $package --exact --disable-interactivity --accept-source-agreements --accept-package-agreements
    return $true
  }

  if ($sourceManager -eq "scoop") {
    Write-Host "Upgrading $package with scoop..."
    scoop update $package
    return $true
  }

  if ($sourceManager -eq "choco") {
    Write-Host "Upgrading $package with Chocolatey..."
    choco upgrade $package -y
    return $true
  }

  return $false
}

function Show-PackageManagerGuidance {
  @"

No supported Windows package manager was found.

Recommended:
  winget      https://learn.microsoft.com/windows/package-manager/winget/

Optional:
  Scoop       https://scoop.sh/
  Chocolatey  https://chocolatey.org/install

Install one of these package managers, then rerun:
  powershell -ExecutionPolicy Bypass -File .\windows.ps1 -InstallMissing
"@
}

function Show-InstallHint {
  if ((Get-AvailableManagers).Count -gt 0) {
    @"

To install missing tools, run:
  powershell -ExecutionPolicy Bypass -File .\windows.ps1 -InstallMissing
"@
  } else {
    Show-PackageManagerGuidance
  }
}

Write-Host "Checking developer tools for Windows..."
$availableManagers = Get-AvailableManagers
if ($availableManagers.Count -gt 0) {
  Write-Host "Detected package managers: $($availableManagers -join ', ')"
} else {
  Write-Host "Detected package managers: none"
}
Write-Host ""

$missingCount = 0
$unmanagedCount = 0
$failedVersionCount = 0
$installAttemptCount = 0
$postInstallUnavailableCount = 0
$postInstallUnavailableTools = @()
$postInstallPathRefreshCount = 0
$postInstallPathRefreshTools = @()
$differentManagerTools = @()

foreach ($tool in $Tools) {
  $cmd = Get-ToolCommand $tool.Commands $tool

  if ($null -eq $cmd) {
    $missingCount++
    $installManager = Get-InstallManager $tool

    if ($installManager) {
      Write-Host ("[missing] {0,-14} package manager: {1}" -f $tool.Name, $installManager)
      if ($InstallMissing) {
        $installAttemptCount++
        Install-Tool $installManager $tool
        $didRefreshPath = $false
        $postInstallCmd = Get-ToolCommand $tool.Commands $tool
        if ($null -eq $postInstallCmd) {
          $didRefreshPath = Update-ProcessPathFromEnvironment
          if ($didRefreshPath) {
            $postInstallCmd = Get-ToolCommand $tool.Commands $tool
          }
        }
        if ($null -ne $postInstallCmd) {
          if ($didRefreshPath) {
            $postInstallPathRefreshCount++
            $postInstallPathRefreshTools += $tool.Name
          }
        } else {
          $postInstallUnavailableCount++
          $postInstallUnavailableTools += $tool.Name
        }
      }
    } else {
      $mappedManagers = @(Get-ToolMappedManagers $tool)
      $alternateManagers = @($mappedManagers | Where-Object { $availableManagers -notcontains $_ })
      if ($availableManagers.Count -gt 0 -and $alternateManagers.Count -gt 0) {
        Write-Host ("[missing] {0,-14} package not available via detected manager(s)" -f $tool.Name)
        $differentManagerTools += [pscustomobject]@{
          Name = $tool.Name
          Managers = $alternateManagers
        }
      } elseif ($mappedManagers.Count -eq 0) {
        Write-Host ("[missing] {0,-14} package has no supported Windows mapping" -f $tool.Name)
      } else {
        Write-Host ("[missing] {0,-14} package manager: none detected" -f $tool.Name)
      }
    }
    continue
  }

  $source = Get-ToolSource $cmd.Source $tool
  $version = Get-VersionLine $cmd
  if ($tool.Name -eq "yarn" -and $version -eq "version check failed" -and $source -eq "npm-or-node") {
    $version = "corepack shim; version is selected per project"
  } elseif ($null -ne $version -and $version.Length -eq 0) {
    $packageVersion = Get-PackageVersionForSource $source
    if ($packageVersion) {
      $version = $packageVersion
    } else {
      $version = "version output empty"
    }
  } elseif (-not $version -or $version -eq "version check failed") {
    $failedVersionCount++
    $version = "version check failed"
  }

  $versionDisplay = Format-VersionForDisplay $version
  $pathDisplay = Format-PathForDisplay $cmd.Source
  Write-Host ("[found]   {0,-14} {1,-$PathDisplayWidth} {2,-$SourceDisplayWidth} {3}" -f $tool.Name, $pathDisplay, $source, $versionDisplay)

  if ($UpgradeManaged) {
    if ($source -like "winget:*" -or $source -like "scoop:*" -or $source -like "choco:*") {
      $didUpgrade = Upgrade-ManagedTool $source
      if (-not $didUpgrade) {
        $unmanagedCount++
        Write-Host "  skip upgrade: package ownership is not specific enough."
      }
    } else {
      $unmanagedCount++
      Write-Host "  skip upgrade: existing command is not managed by winget, Scoop, or Chocolatey."
    }
  }
}

if ($InstallMissing -and $missingCount -gt 0 -and $availableManagers.Count -eq 0) {
  Show-PackageManagerGuidance
}

Write-Host ""
Write-Host "Summary:"
Write-Host "  Missing before install: $missingCount"
Write-Host "  Version checks failed:  $failedVersionCount"
if ($InstallMissing -and $installAttemptCount -gt 0) {
  Write-Host "  Still unavailable after install attempts: $postInstallUnavailableCount"
  if ($postInstallPathRefreshCount -gt 0) {
    Write-Host "  Available after PATH refresh in this script: $postInstallPathRefreshCount"
  }
}
if ($UpgradeManaged) {
  Write-Host "  Unmanaged upgrades skipped: $unmanagedCount"
}
if ($postInstallPathRefreshCount -gt 0) {
  Write-Host ""
  Write-Host "Note: command(s) became available after refreshing PATH inside this script: $($postInstallPathRefreshTools -join ', '). The parent shell may need a restart or PATH refresh before running them."
}
if ($differentManagerTools.Count -gt 0) {
  Write-Host ""
  Write-Host "Some missing tools need a different package manager:"
  foreach ($item in $differentManagerTools) {
    Write-Host "  $($item.Name): available via $(Format-ManagerList $item.Managers)"
  }
}
if ($postInstallUnavailableCount -gt 0) {
  Write-Warning "$postInstallUnavailableCount command(s) are still unavailable after install attempts: $($postInstallUnavailableTools -join ', '). Package manager reported install/upgrade completed or no upgrade was needed; restart the shell or check package/app alias PATH entries."
}
if ($missingCount -gt 0 -and -not $InstallMissing) {
  Show-InstallHint
}
