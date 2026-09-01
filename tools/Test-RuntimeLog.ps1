[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameRoot,

    [switch]$RequireCurrentSession
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$gameRootPath = [IO.Path]::GetFullPath($GameRoot).TrimEnd("\")
$logPath = Assert-PathInside `
    -Root $gameRootPath `
    -Path (Join-Path $gameRootPath "FarFarWest\Binaries\Win64\ue4ss\UE4SS.log")

if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw "UE4SS log not found: $logPath"
}

$logItem = Get-Item -LiteralPath $logPath
$logText = Get-Content -LiteralPath $logPath -Raw
$processes = @(Get-Process -Name "FarFarWest-Win64-Shipping" -ErrorAction SilentlyContinue)
$currentSession = $null

if ($processes.Count -gt 0) {
    $oldestStartUtc = ($processes | Sort-Object StartTime | Select-Object -First 1).StartTime.ToUniversalTime()
    $currentSession = $logItem.LastWriteTimeUtc -ge $oldestStartUtc
}

$checks = @(
    [pscustomobject]@{
        name = "UE4SS event loop"
        pattern = "Event loop start"
    },
    [pscustomobject]@{
        name = "More Players loaded"
        pattern = "\[FFWMorePlayers v$([regex]::Escape($lock.morePlayers.internalLuaVersion))\].*Mod loaded"
    },
    [pscustomobject]@{
        name = "Eight-player target"
        pattern = "\[FFWMorePlayers v$([regex]::Escape($lock.morePlayers.internalLuaVersion))\].*Target MaxPlayers=$($lock.morePlayers.defaultMaxPlayers)"
    }
)

$results = @($checks | ForEach-Object {
    [pscustomobject]@{
        name = $_.name
        found = [regex]::IsMatch($logText, $_.pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
})

$markersPass = @($results | Where-Object { -not $_.found }).Count -eq 0
$sessionPass = -not $RequireCurrentSession -or $currentSession -eq $true
$report = [pscustomobject]@{
    schemaVersion = 1
    mode = "log-only"
    logPath = $logPath
    logLastWriteTimeUtc = $logItem.LastWriteTimeUtc.ToString("o")
    gameRunning = $processes.Count -gt 0
    logBelongsToCurrentRunningSession = $currentSession
    expectedModVersion = $lock.morePlayers.internalLuaVersion
    expectedMaxPlayers = [int]$lock.morePlayers.defaultMaxPlayers
    checks = $results
    passed = $markersPass -and $sessionPass
    networkCapacityTested = $false
}

$report

if (-not $markersPass) {
    throw "Runtime log check failed: one or more UE4SS/More Players markers are missing."
}
if (-not $sessionPass) {
    throw "The log was not updated during the currently running game session."
}
