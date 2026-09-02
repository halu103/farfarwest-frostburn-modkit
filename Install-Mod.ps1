[CmdletBinding()]
param(
    [string]$GameRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
. (Join-Path $projectRoot "tools\lib\Common.ps1")

$lock = Get-LockData -ProjectRoot $projectRoot
$mod = Get-ModData -ProjectRoot $projectRoot
$resolvedGameRoot = Resolve-FarFarWestGameRoot -GameRoot $GameRoot -Lock $lock

# The script never closes or restarts the game. It refuses before any game-file write.
Assert-GameNotRunning

Write-Host "[1/4] Validating the owned mod source..."
$projectTest = & (Join-Path $projectRoot "tools\Test-Project.ps1")

Write-Host "[2/4] Checking the installed Far Far West build..."
$compatibility = & (Join-Path $projectRoot "tools\Test-Compatibility.ps1") `
    -GameRoot $resolvedGameRoot `
    -StrictLock `
    -NoWrite

Write-Host "[3/4] Building $($mod.id) v$($mod.version)..."
$build = & (Join-Path $projectRoot "tools\Build-Release.ps1") `
    -GameRoot $resolvedGameRoot

# Repeat immediately before the installer takes its own backup and writes files.
Assert-GameNotRunning
Write-Host "[4/4] Backing up the current loader and installing the release..."
$install = & (Join-Path $projectRoot "tools\Install-Release.ps1") `
    -GameRoot $resolvedGameRoot `
    -Archive $build.path `
    -ExpectedArchiveSha256 $build.sha256

Write-Host "Installed $($mod.name) successfully."
Write-Host "Backup: $($install.backupDirectory)"

[pscustomobject]@{
    installed = [bool]$install.installed
    modId = $mod.id
    modVersion = $mod.version
    targetMaxPlayers = [int]$mod.maxPlayers
    gameRoot = $resolvedGameRoot
    releaseArchive = $build.path
    releaseSha256 = $build.sha256
    sourceTreeSha256 = $build.sourceTreeSha256
    backupDirectory = $install.backupDirectory
    projectChecks = $projectTest.checks
    compatible = [bool]$compatibility.compatible
    runtimeTested = $false
}
