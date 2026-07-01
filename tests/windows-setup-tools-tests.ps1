$ErrorActionPreference = "Stop"

if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
  Write-Host "skipped: Windows setup-tools tests require Windows command resolution"
  exit 0
}

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$SetupScript = Join-Path $RootDir "windows.ps1"
$TestRoots = @()

function Fail {
  param([string]$Message)
  throw $Message
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Needle,
    [string]$Label
  )

  if (-not $Text.Contains($Needle)) {
    Write-Error "Expected to find: $Needle`nIn text:`n$Text"
    Fail $Label
  }
}

function Assert-NotContains {
  param(
    [string]$Text,
    [string]$Needle,
    [string]$Label
  )

  if ($Text.Contains($Needle)) {
    Write-Error "Did not expect to find: $Needle`nIn text:`n$Text"
    Fail $Label
  }
}

function Assert-LogContains {
  param(
    [string]$LogPath,
    [string]$Needle,
    [string]$Label
  )

  if (-not (Test-Path $LogPath)) {
    Fail "command log does not exist: $LogPath"
  }

  $log = Get-Content -Raw -Path $LogPath
  Assert-Contains $log $Needle $Label
}

function Assert-LogNotContains {
  param(
    [string]$LogPath,
    [string]$Needle,
    [string]$Label
  )

  if ((Test-Path $LogPath) -and (Get-Content -Raw -Path $LogPath).Contains($Needle)) {
    Write-Error "Did not expect command log to contain: $Needle`nIn log:`n$(Get-Content -Raw -Path $LogPath)"
    Fail $Label
  }
}

function New-TestContext {
  param([string]$Name)

  $root = Join-Path ([System.IO.Path]::GetTempPath()) "setup-tools-$Name-$([guid]::NewGuid().ToString("N"))"
  $bin = Join-Path $root "bin"
  New-Item -ItemType Directory -Force -Path $bin | Out-Null
  $script:TestRoots += $root

  [pscustomobject]@{
    Root = $root
    Bin = $bin
    Log = Join-Path $root "commands.log"
    Paths = @($bin, (Join-Path $env:SystemRoot "System32"))
  }
}

function Write-CmdFile {
  param(
    [string]$Path,
    [string[]]$Lines
  )

  Set-Content -Path $Path -Encoding ASCII -Value (@("@echo off") + $Lines)
}

function Add-FakeTool {
  param(
    [string]$Directory,
    [string]$CommandName
  )

  Write-CmdFile -Path (Join-Path $Directory "$CommandName.cmd") -Lines @(
    "echo $CommandName 1.0",
    "exit /b 0"
  )
}

function Add-FakeEmptyVersionTool {
  param(
    [string]$Directory,
    [string]$CommandName
  )

  Write-CmdFile -Path (Join-Path $Directory "$CommandName.cmd") -Lines @(
    'if /I "%1"=="--version" exit /b 0',
    'exit /b 2'
  )
}

function Add-FakeMultiLineVersionTool {
  param(
    [string]$Directory,
    [string]$CommandName
  )

  Write-CmdFile -Path (Join-Path $Directory "$CommandName.cmd") -Lines @(
    'if /I not "%1"=="--version" exit /b 2',
    "echo $CommandName 1.0",
    "echo $CommandName build metadata",
    "echo $CommandName extra version detail",
    "exit /b 0"
  )
}

function Add-FakePdftotextStderrVersionTool {
  param([string]$Directory)

  Write-CmdFile -Path (Join-Path $Directory "pdftotext.cmd") -Lines @(
    'if /I not "%1"=="-v" exit /b 2',
    'echo pdftotext version 25.12.0 1>&2',
    'echo Copyright 2005-2025 The Poppler Developers 1>&2',
    'exit /b 0'
  )
}

function Add-FakeManager {
  param(
    [string]$Directory,
    [ValidateSet("winget", "scoop", "choco")]
    [string]$Manager
  )

  switch ($Manager) {
    "winget" {
      Write-CmdFile -Path (Join-Path $Directory "winget.cmd") -Lines @(
        'echo winget %*>>"%FAKE_COMMAND_LOG%"',
        'if /I "%1"=="list" echo ripgrep BurntSushi.ripgrep.MSVC 15.0.0 winget',
        'exit /b 0'
      )
    }
    "scoop" {
      Write-CmdFile -Path (Join-Path $Directory "scoop.cmd") -Lines @(
        'echo scoop %*>>"%FAKE_COMMAND_LOG%"',
        'if /I "%1"=="list" echo ripgrep 15.0.0',
        'exit /b 0'
      )
    }
    "choco" {
      Write-CmdFile -Path (Join-Path $Directory "choco.cmd") -Lines @(
        'echo choco %*>>"%FAKE_COMMAND_LOG%"',
        'if /I "%1"=="list" echo ripgrep^|15.0.0',
        'exit /b 0'
      )
    }
  }
}

function Add-FakeFailingInstallManager {
  param(
    [string]$Directory,
    [ValidateSet("winget", "scoop", "choco")]
    [string]$Manager,
    [int]$ExitCode
  )

  switch ($Manager) {
    "winget" {
      Write-CmdFile -Path (Join-Path $Directory "winget.cmd") -Lines @(
        'echo winget %*>>"%FAKE_COMMAND_LOG%"',
        "if /I ""%1""==""install"" exit /b $ExitCode",
        'if /I "%1"=="list" echo ripgrep BurntSushi.ripgrep.MSVC 15.0.0 winget',
        'exit /b 0'
      )
    }
    "scoop" {
      Write-CmdFile -Path (Join-Path $Directory "scoop.cmd") -Lines @(
        'echo scoop %*>>"%FAKE_COMMAND_LOG%"',
        "if /I ""%1""==""install"" exit /b $ExitCode",
        'if /I "%1"=="list" echo ripgrep 15.0.0',
        'exit /b 0'
      )
    }
    "choco" {
      Write-CmdFile -Path (Join-Path $Directory "choco.cmd") -Lines @(
        'echo choco %*>>"%FAKE_COMMAND_LOG%"',
        "if /I ""%1""==""install"" exit /b $ExitCode",
        'if /I "%1"=="list" echo ripgrep^|15.0.0',
        'exit /b 0'
      )
    }
  }
}

function Add-FakeWingetAlreadyInstalledNoUpgradeManager {
  param([string]$Directory)

  Write-CmdFile -Path (Join-Path $Directory "winget.cmd") -Lines @(
    'echo winget %*>>"%FAKE_COMMAND_LOG%"',
    'if /I "%1"=="install" echo Found an existing package already installed. Trying to upgrade the installed package...',
    'if /I "%1"=="install" echo No available upgrade found.',
    'if /I "%1"=="install" echo No newer package versions are available from the configured sources.',
    'if /I "%1"=="install" exit /b -1978335189',
    'if /I "%1"=="list" echo ripgrep BurntSushi.ripgrep.MSVC 15.0.0 winget',
    'exit /b 0'
  )
}

function Invoke-Setup {
  param(
    [pscustomobject]$Context,
    [hashtable]$Parameters = @{},
    [string[]]$ExtraPaths = @(),
    [string[]]$RefreshPaths = @()
  )

  $oldPath = $env:Path
  $oldLog = $env:FAKE_COMMAND_LOG
  $oldRefreshPath = $env:AI_AGENTS_TOOLBOX_WINDOWS_REFRESH_PATH

  try {
    $env:Path = (($ExtraPaths + $Context.Paths) -join [System.IO.Path]::PathSeparator)
    $env:FAKE_COMMAND_LOG = $Context.Log
    if ($RefreshPaths.Count -gt 0) {
      $env:AI_AGENTS_TOOLBOX_WINDOWS_REFRESH_PATH = ($RefreshPaths -join [System.IO.Path]::PathSeparator)
    } else {
      $env:AI_AGENTS_TOOLBOX_WINDOWS_REFRESH_PATH = (($ExtraPaths + $Context.Paths) -join [System.IO.Path]::PathSeparator)
    }
    # windows.ps1 uses Write-Host for status lines, which PowerShell emits on the information stream.
    (& $SetupScript @Parameters *>&1 | Out-String)
  } finally {
    $env:Path = $oldPath
    $env:FAKE_COMMAND_LOG = $oldLog
    $env:AI_AGENTS_TOOLBOX_WINDOWS_REFRESH_PATH = $oldRefreshPath
  }
}

function Invoke-SetupWithRefreshPathEntry {
  param(
    [pscustomobject]$Context,
    [hashtable]$Parameters,
    [string]$RefreshPathEntry
  )

  Invoke-Setup $Context $Parameters @() @($RefreshPathEntry)
}

function Run-Test {
  param(
    [string]$Name,
    [scriptblock]$Body
  )

  Write-Host "test: $Name"
  & $Body
  Write-Host "ok: $Name"
}

try {
  Run-Test "Windows check-only does not install" {
    $ctx = New-TestContext "check-only"
    Add-FakeManager $ctx.Bin "winget"

    $output = Invoke-Setup $ctx @{ CheckOnly = $true }

    Assert-Contains $output "Detected package managers: winget" "Windows should detect fake winget"
    Assert-Contains $output "[missing] ripgrep" "Windows should report missing tools"
    Assert-Contains $output "To install missing tools, run:" "Windows check-only should print install guidance"
    Assert-Contains $output "powershell -ExecutionPolicy Bypass -File .\windows.ps1 -InstallMissing" "Windows check-only should print a copy-paste install command"
    Assert-NotContains $output "Installing " "Windows check-only should not print installs"
    Assert-LogNotContains $ctx.Log " install " "Windows check-only should not invoke installs"
  }

  foreach ($manager in @("winget", "scoop", "choco")) {
    Run-Test "Windows install-missing uses $manager" {
      $ctx = New-TestContext "install-$manager"
      Add-FakeManager $ctx.Bin $manager

      $output = Invoke-Setup $ctx @{ InstallMissing = $true; Manager = $manager }
      Assert-Contains $output "[missing] ripgrep" "Windows should report ripgrep missing for $manager"

      if ($manager -eq "winget") {
        Assert-LogContains $ctx.Log "winget install --id BurntSushi.ripgrep.MSVC" "Windows should install ripgrep with winget"
        Assert-LogContains $ctx.Log "winget install --id SQLite.SQLite" "Windows should install sqlite3 with winget"
        Assert-LogContains $ctx.Log "winget install --id MikeFarah.yq" "Windows should install yq with winget"
        Assert-LogContains $ctx.Log "winget install --id rhysd.actionlint" "Windows should install actionlint with winget"
        Assert-LogContains $ctx.Log "winget install --id GnuWin32.File" "Windows should install file with winget"
        Assert-LogContains $ctx.Log "winget install --id Casey.Just" "Windows should install just with winget"
        Assert-LogContains $ctx.Log "winget install --id Wilfred.difftastic" "Windows should install difftastic with winget"
        Assert-LogContains $ctx.Log "winget install --id JohnMacFarlane.Pandoc" "Windows should install pandoc with winget"
        Assert-LogContains $ctx.Log "winget install --id ImageMagick.ImageMagick" "Windows should install ImageMagick with winget"
        Assert-LogContains $ctx.Log "winget install --id Gyan.FFmpeg" "Windows should install ffmpeg with winget"
        Assert-LogContains $ctx.Log "winget install --id OliverBetz.ExifTool" "Windows should install exiftool with winget"
        Assert-LogNotContains $ctx.Log "winget install --id dandavison" "Windows should not use an unverified delta winget id"
        Assert-LogNotContains $ctx.Log "winget install --id typos" "Windows should not use an unverified typos winget id"
        Assert-Contains $output "Package manager reported install/upgrade completed" "Windows should explain when winget succeeds but the command remains unavailable"
        Assert-Contains $output "PATH entries." "Windows should hint at PATH and app alias fixes after winget succeeds without exposing the command"
      } elseif ($manager -eq "scoop") {
        Assert-LogContains $ctx.Log "scoop install ripgrep" "Windows should install ripgrep with Scoop"
        Assert-LogContains $ctx.Log "scoop install sqlite" "Windows should install sqlite3 with Scoop"
        Assert-LogContains $ctx.Log "scoop install yq" "Windows should install yq with Scoop"
        Assert-LogContains $ctx.Log "scoop install actionlint" "Windows should install actionlint with Scoop"
        Assert-LogContains $ctx.Log "scoop install typos" "Windows should install typos with Scoop"
        Assert-LogContains $ctx.Log "scoop install delta" "Windows should install git-delta with Scoop"
        Assert-LogContains $ctx.Log "scoop install file" "Windows should install file with Scoop"
        Assert-LogContains $ctx.Log "scoop install just" "Windows should install just with Scoop"
        Assert-LogContains $ctx.Log "scoop install difftastic" "Windows should install difftastic with Scoop"
        Assert-LogContains $ctx.Log "scoop install pandoc" "Windows should install pandoc with Scoop"
        Assert-LogContains $ctx.Log "scoop install imagemagick" "Windows should install ImageMagick with Scoop"
        Assert-LogContains $ctx.Log "scoop install ffmpeg" "Windows should install ffmpeg with Scoop"
        Assert-LogContains $ctx.Log "scoop install exiftool" "Windows should install exiftool with Scoop"
      } else {
        Assert-LogContains $ctx.Log "choco install ripgrep -y" "Windows should install ripgrep with Chocolatey"
        Assert-LogContains $ctx.Log "choco install sqlite -y" "Windows should install sqlite3 with Chocolatey"
        Assert-LogContains $ctx.Log "choco install yq -y" "Windows should install yq with Chocolatey"
        Assert-LogContains $ctx.Log "choco install actionlint -y" "Windows should install actionlint with Chocolatey"
        Assert-LogContains $ctx.Log "choco install typos -y" "Windows should install typos with Chocolatey"
        Assert-LogContains $ctx.Log "choco install delta -y" "Windows should install git-delta with Chocolatey"
        Assert-LogContains $ctx.Log "choco install file -y" "Windows should install file with Chocolatey"
        Assert-LogContains $ctx.Log "choco install just -y" "Windows should install just with Chocolatey"
        Assert-LogContains $ctx.Log "choco install difftastic -y" "Windows should install difftastic with Chocolatey"
        Assert-LogContains $ctx.Log "choco install pandoc -y" "Windows should install pandoc with Chocolatey"
        Assert-LogContains $ctx.Log "choco install imagemagick -y" "Windows should install ImageMagick with Chocolatey"
        Assert-LogContains $ctx.Log "choco install ffmpeg -y" "Windows should install ffmpeg with Chocolatey"
        Assert-LogContains $ctx.Log "choco install exiftool -y" "Windows should install exiftool with Chocolatey"
      }
    }
  }

  Run-Test "Windows upgrade-managed uses winget owner" {
    $ctx = New-TestContext "upgrade-winget"
    Add-FakeManager $ctx.Bin "winget"
    Add-FakeTool $ctx.Bin "rg"

    $output = Invoke-Setup $ctx @{ UpgradeManaged = $true }

    Assert-Contains $output "winget:BurntSushi.ripgrep.MSVC" "Windows should report winget ownership"
    Assert-LogContains $ctx.Log "winget upgrade --id BurntSushi.ripgrep.MSVC" "Windows should upgrade managed winget owner"
    Assert-LogNotContains $ctx.Log "winget install" "Windows upgrade should not install missing tools"
  }

  Run-Test "Windows empty successful version output is not a failure" {
    $ctx = New-TestContext "empty-version"
    Add-FakeManager $ctx.Bin "winget"
    Add-FakeEmptyVersionTool $ctx.Bin "rg"

    $output = Invoke-Setup $ctx @{ CheckOnly = $true }

    Assert-Contains $output "[found]   ripgrep" "Windows should find fake ripgrep"
    Assert-Contains $output "package version: ripgrep BurntSushi.ripgrep.MSVC 15.0.0 winget" "Windows should use package metadata for empty successful version output"
    Assert-Contains $output "Version checks failed:  0" "Windows should not fail successful empty version checks"
    Assert-NotContains $output "version output empty" "Windows should prefer package metadata when it is available"
    Assert-NotContains $output "version check failed" "Windows should not report successful empty version output as failed"
  }

  Run-Test "Windows multiline version output uses first line without failing" {
    $ctx = New-TestContext "multiline-version"
    Add-FakeManager $ctx.Bin "winget"
    Add-FakeMultiLineVersionTool $ctx.Bin "rg"

    $output = Invoke-Setup $ctx @{ CheckOnly = $true }

    Assert-Contains $output "[found]   ripgrep" "Windows should find fake multiline ripgrep"
    Assert-Contains $output "rg 1.0" "Windows should report the first useful version output line"
    Assert-Contains $output "Version checks failed:  0" "Windows should not fail a successful multiline version command"
    Assert-NotContains $output "rg build metadata" "Windows should not report later version output lines"
    Assert-NotContains $output "version check failed" "Windows should not report successful multiline version output as failed"
  }

  Run-Test "Windows successful stderr version output is not a failure" {
    $ctx = New-TestContext "stderr-version"
    Add-FakePdftotextStderrVersionTool $ctx.Bin

    $output = Invoke-Setup $ctx @{ CheckOnly = $true }

    Assert-Contains $output "[found]   pdftotext" "Windows should find fake pdftotext"
    Assert-Contains $output "pdftotext version 25.12.0" "Windows should report successful stderr version output"
    Assert-Contains $output "Version checks failed:  0" "Windows should not fail a successful stderr version command"
    Assert-NotContains $output "version check failed" "Windows should not report successful stderr version output as failed"
  }

  Run-Test "Windows version checks invoke the discovered executable path" {
    $ctx = New-TestContext "version-source-path"
    Add-FakeManager $ctx.Bin "winget"
    Add-FakeTool $ctx.Bin "rg"

    try {
      Set-Alias -Name "rg.cmd" -Value Get-Date -Scope Script
      $output = Invoke-Setup $ctx @{ CheckOnly = $true }
    } finally {
      if (Test-Path "Alias:rg.cmd") {
        Remove-Item "Alias:rg.cmd" -Force
      }
    }

    Assert-Contains $output "[found]   ripgrep" "Windows should find fake ripgrep despite an alias sharing the application name"
    Assert-Contains $output "rg 1.0" "Windows should invoke the discovered executable path instead of the alias-shadowed command name"
    Assert-Contains $output "Version checks failed:  0" "Windows should not fail when command-name re-resolution is shadowed"
    Assert-NotContains $output "version check failed" "Windows should not report the alias-shadowed path check as failed"
  }

  foreach ($manager in @("winget", "scoop", "choco")) {
    Run-Test "Windows install-missing surfaces $manager exit code" {
      $ctx = New-TestContext "install-fails-$manager"
      Add-FakeFailingInstallManager $ctx.Bin $manager 23

      try {
        Invoke-Setup $ctx @{ InstallMissing = $true; Manager = $manager } | Out-Null
        Fail "Windows should fail when $manager install exits nonzero"
      } catch {
        $message = "$_"
      }

      Assert-Contains $message "Install failed for ripgrep" "Windows should name the tool whose install failed"
      Assert-Contains $message $manager "Windows should name the package manager whose install failed"
      Assert-Contains $message "exit code 23" "Windows should report the native installer exit code"
    }
  }

  Run-Test "Windows install-missing treats winget already-installed no-upgrade as nonfatal" {
    $ctx = New-TestContext "winget-no-upgrade"
    Add-FakeWingetAlreadyInstalledNoUpgradeManager $ctx.Bin

    $output = Invoke-Setup $ctx @{ InstallMissing = $true; Manager = "winget" }

    Assert-Contains $output "[missing] ripgrep" "Windows should report the command missing before the winget attempt"
    Assert-Contains $output "No available upgrade found." "Windows should surface winget no-upgrade output"
    Assert-Contains $output "Package manager reported install/upgrade completed" "Windows should still explain that the command remains unavailable"
    Assert-Contains $output "Still unavailable after install attempts:" "Windows should include post-install availability summary"
    Assert-NotContains $output "Install failed for ripgrep with winget package BurntSushi.ripgrep.MSVC" "Windows should not abort on winget already-installed no-upgrade"
  }

  Run-Test "Windows install-missing refreshes PATH before reporting unavailable commands" {
    $ctx = New-TestContext "path-refresh"
    $refreshedBin = Join-Path $ctx.Root "refreshed-bin"
    New-Item -ItemType Directory -Force -Path $refreshedBin | Out-Null
    Add-FakeWingetAlreadyInstalledNoUpgradeManager $ctx.Bin
    Add-FakeTool $refreshedBin "rg"

    $output = Invoke-SetupWithRefreshPathEntry $ctx @{ InstallMissing = $true; Manager = "winget" } $refreshedBin

    Assert-Contains $output "[missing] ripgrep" "Windows should report ripgrep missing before install"
    Assert-Contains $output "Available after PATH refresh in this script:" "Windows should report commands found after refreshing PATH"
    Assert-Contains $output "ripgrep" "Windows should name the command found after PATH refresh"
    Assert-Contains $output "The parent shell may need" "Windows should explain parent shell PATH staleness at the end"
    Assert-Contains $output "PATH refresh before running them." "Windows should explain how to refresh parent shell PATH"
    Assert-NotContains $output "WARNING: ripgrep:" "Windows should not print a per-tool warning for commands found after PATH refresh"
    Assert-NotContains $output "unavailable after install attempts: ripgrep" "Windows should not include refreshed commands in the unavailable summary"
  }

  Run-Test "Windows upgrade-managed uses Scoop owner" {
    $ctx = New-TestContext "upgrade-scoop"
    $scoopShims = Join-Path $ctx.Root "scoop\shims"
    New-Item -ItemType Directory -Force -Path $scoopShims | Out-Null
    Add-FakeManager $ctx.Bin "scoop"
    Add-FakeTool $scoopShims "rg"

    $output = Invoke-Setup $ctx @{ UpgradeManaged = $true } @($scoopShims)

    Assert-Contains $output "scoop:ripgrep" "Windows should report Scoop ownership"
    Assert-LogContains $ctx.Log "scoop update ripgrep" "Windows should upgrade managed Scoop owner"
    Assert-LogNotContains $ctx.Log "scoop install" "Windows upgrade should not install missing tools"
  }

  Run-Test "Windows upgrade-managed uses Chocolatey owner" {
    $ctx = New-TestContext "upgrade-choco"
    $chocoBin = Join-Path $ctx.Root "chocolatey\bin"
    New-Item -ItemType Directory -Force -Path $chocoBin | Out-Null
    Add-FakeManager $ctx.Bin "choco"
    Add-FakeTool $chocoBin "rg"

    $output = Invoke-Setup $ctx @{ UpgradeManaged = $true } @($chocoBin)

    Assert-Contains $output "choco:ripgrep" "Windows should report Chocolatey ownership"
    Assert-LogContains $ctx.Log "choco upgrade ripgrep -y" "Windows should upgrade managed Chocolatey owner"
    Assert-LogNotContains $ctx.Log "choco install" "Windows upgrade should not install missing tools"
  }

  Run-Test "Windows install-missing without manager prints guidance" {
    $ctx = New-TestContext "no-manager"

    $output = Invoke-Setup $ctx @{ InstallMissing = $true }

    Assert-Contains $output "Detected package managers: none" "Windows should report no package managers"
    Assert-Contains $output "No supported Windows package manager was found." "Windows should print package-manager guidance"
    Assert-LogNotContains $ctx.Log " install " "Windows without a manager should not invoke installs"
  }
} finally {
  foreach ($root in $TestRoots) {
    if (Test-Path $root) {
      Remove-Item -Recurse -Force -Path $root
    }
  }
}
