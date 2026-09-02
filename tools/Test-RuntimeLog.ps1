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
$mod = Get-ModData -ProjectRoot $projectRoot
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
        name = "Owned mod loaded"
        pattern = "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*Mod loaded - v$([regex]::Escape($mod.version))"
    },
    [pscustomobject]@{
        name = "Eight-player target"
        pattern = "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*Target MaxPlayers=$($mod.maxPlayers)"
    },
    [pscustomobject]@{
        name = "GameSession cap applied"
        pattern = "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*(?:CapWrite source=GameSession.*WRITE=true AFTER=$($mod.maxPlayers)|Status .*sessionCapApplied=true)"
    }
)

$results = @($checks | ForEach-Object {
    [pscustomobject]@{
        name = $_.name
        found = [regex]::IsMatch($logText, $_.pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
})

$markersPass = @($results | Where-Object { -not $_.found }).Count -eq 0
$fatalMarkers = @(
    "AOB scans could not be completed",
    "Fatal Error",
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\] ERROR"
)
$fatalResults = @($fatalMarkers | ForEach-Object {
    [pscustomobject]@{
        marker = $_
        found = [regex]::IsMatch($logText, $_, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
})
$fatalFree = @($fatalResults | Where-Object { $_.found }).Count -eq 0
$sessionPass = -not $RequireCurrentSession -or $currentSession -eq $true

$observedMatches = [regex]::Matches(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*ObservedPlayers=(\d+)",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$maximumObservedPlayers = 0
foreach ($match in $observedMatches) {
    $maximumObservedPlayers = [Math]::Max($maximumObservedPlayers, [int]$match.Groups[1].Value)
}
$managerCapApplied = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*(?:CapWrite source=Manager.*WRITE=true AFTER=$($mod.maxPlayers)|Status .*managerCapApplied=true)",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$nativeSessionHookReady = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*NativeHook registered",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$sessionParameterApplied = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*SessionParamWrite .*WRITE=true AFTER=$($mod.maxPlayers)",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$report = [pscustomobject]@{
    schemaVersion = 2
    mode = "log-only"
    logPath = $logPath
    logLastWriteTimeUtc = $logItem.LastWriteTimeUtc.ToString("o")
    gameRunning = $processes.Count -gt 0
    logBelongsToCurrentRunningSession = $currentSession
    expectedModId = $mod.id
    expectedModVersion = $mod.version
    expectedMaxPlayers = [int]$mod.maxPlayers
    packageMode = $mod.packageMode
    checks = $results
    managerCapApplied = $managerCapApplied
    nativeSessionHookReady = $nativeSessionHookReady
    sessionParameterApplied = $sessionParameterApplied
    maximumObservedPlayers = $maximumObservedPlayers
    fatalMarkers = $fatalResults
    passed = $markersPass -and $fatalFree -and $sessionPass
    networkCapacityTested = $maximumObservedPlayers -ge 5
    fullEightPlayerSessionTested = $maximumObservedPlayers -ge 8
}

$report

if (-not $markersPass -or -not $fatalFree) {
    throw "Runtime log check failed: required markers are missing or a fatal scan marker is present."
}
if (-not $sessionPass) {
    throw "The log was not updated during the currently running game session."
}
