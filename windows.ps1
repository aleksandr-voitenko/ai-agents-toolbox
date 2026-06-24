param(
  [switch]$Help,
  [switch]$CheckOnly,
  [switch]$InstallMissing,
  [switch]$UpgradeManaged,
  [ValidateSet("auto", "winget", "scoop", "choco")]
  [string]$Manager = "auto"
)

$ErrorActionPreference = "Stop"

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
  @{ Name = "clang-format"; Commands = @("clang-format.exe", "clang-format"); Winget = "LLVM.LLVM"; Scoop = "llvm"; Choco = "llvm" },
  @{ Name = "gh"; Commands = @("gh.exe", "gh"); Winget = "GitHub.cli"; Scoop = "gh"; Choco = "gh" },
  @{ Name = "git"; Commands = @("git.exe", "git"); Winget = "Git.Git"; Scoop = "git"; Choco = "git" },
  @{ Name = "node"; Commands = @("node.exe", "node"); Winget = "OpenJS.NodeJS.LTS"; Scoop = "nodejs-lts"; Choco = "nodejs-lts" },
  @{ Name = "yarn"; Commands = @("yarn.cmd", "yarn.exe", "yarn"); Winget = "Yarn.Yarn"; Scoop = "yarn"; Choco = "yarn" },
  @{ Name = "python"; Commands = @("python.exe", "python", "py.exe", "py"); Winget = "Python.Python.3"; Scoop = "python"; Choco = "python" },
  @{ Name = "cmake"; Commands = @("cmake.exe", "cmake"); Winget = "Kitware.CMake"; Scoop = "cmake"; Choco = "cmake" },
  @{ Name = "ninja"; Commands = @("ninja.exe", "ninja"); Winget = "Ninja-build.Ninja"; Scoop = "ninja"; Choco = "ninja" },
  @{ Name = "bat"; Commands = @("bat.exe", "bat"); Winget = "sharkdp.bat"; Scoop = "bat"; Choco = "bat" },
  @{ Name = "eza"; Commands = @("eza.exe", "eza"); Winget = "eza-community.eza"; Scoop = "eza"; Choco = "eza" },
  @{ Name = "fzf"; Commands = @("fzf.exe", "fzf"); Winget = "junegunn.fzf"; Scoop = "fzf"; Choco = "fzf" },
  @{ Name = "tree"; Commands = @("tree.com", "tree.exe", "tree"); Winget = $null; Scoop = "tree"; Choco = "tree" },
  @{ Name = "hyperfine"; Commands = @("hyperfine.exe", "hyperfine"); Winget = "sharkdp.hyperfine"; Scoop = "hyperfine"; Choco = "hyperfine" },
  @{ Name = "shellcheck"; Commands = @("shellcheck.exe", "shellcheck"); Winget = "koalaman.shellcheck"; Scoop = "shellcheck"; Choco = "shellcheck" },
  @{ Name = "shfmt"; Commands = @("shfmt.exe", "shfmt"); Winget = "mvdan.shfmt"; Scoop = "shfmt"; Choco = "shfmt" },
  @{ Name = "ghostscript"; Commands = @("gswin64c.exe", "gswin32c.exe", "gs.exe", "gs"); Winget = "ArtifexSoftware.Ghostscript"; Scoop = "ghostscript"; Choco = "ghostscript" },
  @{ Name = "pdftotext"; Commands = @("pdftotext.exe", "pdftotext"); Winget = "oschwartz10612.Poppler"; Scoop = "poppler"; Choco = "poppler" }
)

function Test-CommandExists {
  param([string]$Name)
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ToolCommand {
  param([string[]]$Commands)

  foreach ($candidate in $Commands) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd) {
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

function Get-VersionLine {
  param([string]$CommandName)

  try {
    if ($CommandName -eq "tree.com" -or $CommandName -eq "tree.exe" -or $CommandName -eq "tree") {
      return "Windows tree command"
    }
    if ($CommandName -like "gswin*c.exe" -or $CommandName -eq "gs.exe" -or $CommandName -eq "gs") {
      $output = & $CommandName --version 2>&1 | Select-Object -First 1
      if ($LASTEXITCODE -ne 0) { return "version check failed" }
      return $output
    }
    if ($CommandName -eq "pdftotext.exe" -or $CommandName -eq "pdftotext") {
      $output = & $CommandName -v 2>&1 | Select-Object -First 1
      if ($LASTEXITCODE -ne 0) { return "version check failed" }
      return $output
    }
    $output = & $CommandName --version 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -ne 0) { return "version check failed" }
    return $output
  } catch {
    return "version check failed"
  }
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

function Install-Tool {
  param(
    [string]$InstallManager,
    [hashtable]$Tool
  )

  if ($InstallManager -eq "winget") {
    Write-Host "Installing $($Tool.Name) with winget..."
    winget install --id $Tool.Winget --exact --disable-interactivity --accept-source-agreements --accept-package-agreements
    return
  }

  if ($InstallManager -eq "scoop") {
    Write-Host "Installing $($Tool.Name) with scoop..."
    scoop install $Tool.Scoop
    return
  }

  if ($InstallManager -eq "choco") {
    Write-Host "Installing $($Tool.Name) with Chocolatey..."
    choco install $Tool.Choco -y
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

foreach ($tool in $Tools) {
  $cmd = Get-ToolCommand $tool.Commands

  if ($null -eq $cmd) {
    $missingCount++
    $installManager = Get-InstallManager $tool

    if ($installManager) {
      Write-Host ("[missing] {0,-14} package manager: {1}" -f $tool.Name, $installManager)
      if ($InstallMissing) {
        Install-Tool $installManager $tool
      }
    } else {
      Write-Host ("[missing] {0,-14} package manager: unavailable or no package mapping" -f $tool.Name)
    }
    continue
  }

  $source = Get-ToolSource $cmd.Source $tool
  $version = Get-VersionLine $cmd.Name
  if ($tool.Name -eq "yarn" -and $version -eq "version check failed" -and $source -eq "npm-or-node") {
    $version = "corepack shim; version is selected per project"
  } elseif (-not $version -or $version -eq "version check failed") {
    $failedVersionCount++
    $version = "version check failed"
  }

  Write-Host ("[found]   {0,-14} {1,-46} {2,-24} {3}" -f $tool.Name, $cmd.Source, $source, $version)

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
if ($UpgradeManaged) {
  Write-Host "  Unmanaged upgrades skipped: $unmanagedCount"
}
