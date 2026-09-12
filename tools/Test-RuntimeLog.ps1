[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameRoot,

    [switch]$RequireCurrentSession,

    [switch]$RequireSessionUi,

    [switch]$RequireSynchronizedPlayerRows,

    [switch]$RequireHostOnlyHooks,

    [switch]$RequireHostOnlyJoin,

    [switch]$RequireSoloInviteUi,

    [switch]$RequireFivePlayerUi
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
$loadMarkerPattern = "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*Mod loaded - v$([regex]::Escape($mod.version))"
$loadMarkers = [regex]::Matches(
    $logText,
    $loadMarkerPattern,
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
if ($loadMarkers.Count -gt 0) {
    $logText = $logText.Substring($loadMarkers[$loadMarkers.Count - 1].Index)
}
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
$sessionUiExpanded = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*(?:SessionUi .*rowsAfter=$([int]$mod.sessionRows).*READY=true|Status .*sessionUiExpanded=true)",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$inviteMatches = [regex]::Matches(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*(?:inviteAfter|maximumInviteSlotsObserved)=(\d+)",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$maximumInviteSlotsObserved = 0
foreach ($match in $inviteMatches) {
    $maximumInviteSlotsObserved = [Math]::Max($maximumInviteSlotsObserved, [int]$match.Groups[1].Value)
}
$sevenInviteSlotsDisplayed = $maximumInviteSlotsObserved -ge [int]$mod.soloInviteSlots
$sessionUiPass = -not $RequireSessionUi -or ($sessionUiExpanded -and $sevenInviteSlotsDisplayed)
$synchronizedMatches = [regex]::Matches(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*SessionUi .*modsAllowed=true playersObserved=(\d+).*membersAfter=(\d+).*READY=true",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$maximumSynchronizedPlayerRows = 0
foreach ($match in $synchronizedMatches) {
    $playersObserved = [int]$match.Groups[1].Value
    $membersAfter = [int]$match.Groups[2].Value
    if ($playersObserved -eq $membersAfter) {
        $maximumSynchronizedPlayerRows = [Math]::Max($maximumSynchronizedPlayerRows, $membersAfter)
    }
}
$fifthPlayerRowDisplayed = $maximumSynchronizedPlayerRows -ge 5
$synchronizedPlayerRowsPass = -not $RequireSynchronizedPlayerRows -or $fifthPlayerRowDisplayed
$allowModsUiGateObserved = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*SessionUiGate .*modsAllowed=false",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$hostOnlyRoomHookReady = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*HostOnlyHook registered role=room-gate",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$hostOnlyJoinGuardReady = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*HostOnlyHook registered role=selective-join-guard",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$hostOnlyLobbyHookReady = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*NativeHook registered path=/Script/SteamCorePro\..*CreateLobby.*targets=.*MaxMembers",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$hostOnlyRoomGateArmed = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*HostOnlyRoomGate state=armed",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$hostOnlyLobbyWriteApplied = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*HostOnlyLobbyWrite function=.*CreateLobby.*AFTER=$($mod.maxPlayers)",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$hostOnlyJoinKickBlocked = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*HostOnlyJoinGuard action=BLOCK_EMPTY_JOIN_KICK",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$hostOnlyJoinMutationFailed = [regex]::IsMatch(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*HostOnlyJoinGuard action=MUTATION_FAILED",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$hostOnlyHooksPass = -not $RequireHostOnlyHooks -or (
    $hostOnlyRoomHookReady -and $hostOnlyJoinGuardReady -and $hostOnlyLobbyHookReady
)
$hostOnlyJoinPass = -not $RequireHostOnlyJoin -or (
    $hostOnlyRoomHookReady -and $hostOnlyJoinGuardReady -and $hostOnlyLobbyHookReady -and
    $hostOnlyRoomGateArmed -and $hostOnlyLobbyWriteApplied -and $hostOnlyJoinKickBlocked -and
    -not $hostOnlyJoinMutationFailed -and
    $maximumObservedPlayers -ge 5
)
$verifiedUiMatches = [regex]::Matches(
    $logText,
    "\[$([regex]::Escape($mod.id)) v$([regex]::Escape($mod.version))\].*SessionUiVerified .*players=(\d+) members=(\d+) invites=(\d+) expectedInvites=(\d+) total=(\d+) visibleRows=(\d+) READY=true",
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$soloInviteUiVerified = $false
$fivePlayerUiVerified = $false
foreach ($match in $verifiedUiMatches) {
    $players = [int]$match.Groups[1].Value
    $members = [int]$match.Groups[2].Value
    $invites = [int]$match.Groups[3].Value
    $expectedInvites = [int]$match.Groups[4].Value
    $total = [int]$match.Groups[5].Value
    $visibleRows = [int]$match.Groups[6].Value
    if ($players -eq 1 -and $members -eq 1 -and $invites -eq 7 -and
        $expectedInvites -eq 7 -and $total -eq 8 -and $visibleRows -eq 8) {
        $soloInviteUiVerified = $true
    }
    if ($players -eq 5 -and $members -eq 5 -and $invites -eq 3 -and
        $expectedInvites -eq 3 -and $total -eq 8 -and $visibleRows -eq 8) {
        $fivePlayerUiVerified = $true
    }
}
$soloInviteUiPass = -not $RequireSoloInviteUi -or $soloInviteUiVerified
$fivePlayerUiPass = -not $RequireFivePlayerUi -or $fivePlayerUiVerified
$report = [pscustomobject]@{
    schemaVersion = 4
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
    sessionUiExpanded = $sessionUiExpanded
    maximumInviteSlotsObserved = $maximumInviteSlotsObserved
    sevenInviteSlotsDisplayed = $sevenInviteSlotsDisplayed
    allowModsUiGateObserved = $allowModsUiGateObserved
    hostOnlyRoomHookReady = $hostOnlyRoomHookReady
    hostOnlyJoinGuardReady = $hostOnlyJoinGuardReady
    hostOnlyLobbyHookReady = $hostOnlyLobbyHookReady
    hostOnlyRoomGateArmed = $hostOnlyRoomGateArmed
    hostOnlyLobbyWriteApplied = $hostOnlyLobbyWriteApplied
    hostOnlyJoinKickBlocked = $hostOnlyJoinKickBlocked
    hostOnlyJoinMutationFailed = $hostOnlyJoinMutationFailed
    soloInviteUiVerified = $soloInviteUiVerified
    fivePlayerUiVerified = $fivePlayerUiVerified
    maximumObservedPlayers = $maximumObservedPlayers
    maximumSynchronizedPlayerRows = $maximumSynchronizedPlayerRows
    fifthPlayerRowDisplayed = $fifthPlayerRowDisplayed
    fatalMarkers = $fatalResults
    vanillaClientInstallationStateProven = $false
    passed = $markersPass -and $fatalFree -and $sessionPass -and $sessionUiPass -and
        $synchronizedPlayerRowsPass -and $hostOnlyHooksPass -and $hostOnlyJoinPass -and
        $soloInviteUiPass -and $fivePlayerUiPass
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
if (-not $sessionUiPass) {
    throw "The current log does not prove a solo-host Session screen with seven invite slots."
}
if (-not $synchronizedPlayerRowsPass) {
    throw "The current log does not prove that five real players were rendered as five Session member rows."
}
if (-not $hostOnlyHooksPass) {
    throw "The current log does not prove that the room gate, Steam lobby cap, and selective join guard hooks are ready."
}
if (-not $hostOnlyJoinPass) {
    throw "The current log does not prove a host-only fifth-player join. It needs an armed Allow Mods gate, a Steam lobby MaxMembers write, a blocked empty join-time kick, and at least five observed players."
}
if (-not $soloInviteUiPass) {
    throw "The current log does not prove the exact solo layout: one member plus seven visible Invite rows."
}
if (-not $fivePlayerUiPass) {
    throw "The current log does not prove the exact five-player layout: five members plus three visible Invite rows."
}
