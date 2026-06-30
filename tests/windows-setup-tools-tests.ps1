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

function Invoke-Setup {
  param(
    [pscustomobject]$Context,
    [hashtable]$Parameters = @{},
    [string[]]$ExtraPaths = @()
  )

  $oldPath = $env:Path
  $oldLog = $env:FAKE_COMMAND_LOG

  try {
    $env:Path = (($ExtraPaths + $Context.Paths) -join [System.IO.Path]::PathSeparator)
    $env:FAKE_COMMAND_LOG = $Context.Log
    # windows.ps1 uses Write-Host for status lines, which PowerShell emits on the information stream.
    (& $SetupScript @Parameters *>&1 | Out-String)
  } finally {
    $env:Path = $oldPath
    $env:FAKE_COMMAND_LOG = $oldLog
  }
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
