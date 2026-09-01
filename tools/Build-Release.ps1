[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MorePlayersArchive,

    [string]$GameRoot,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$archivePath = [IO.Path]::GetFullPath($MorePlayersArchive)

if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "More Players archive not found: $archivePath"
}

Assert-Sha256 -Path $archivePath -Expected $lock.morePlayers.expectedArchiveSha256 | Out-Null

if ($GameRoot) {
    & (Join-Path $PSScriptRoot "Test-Compatibility.ps1") `
        -GameRoot $GameRoot `
        -SignatureDirectory (Join-Path $projectRoot "config\ue4ss\UE4SS_Signatures") `
        -StrictLock `
        -NoWrite | Out-Null
}

$workRoot = Reset-SafeDirectory -ProjectRoot $projectRoot -Path (Join-Path $projectRoot "work\build")
$cacheRoot = Join-Path $projectRoot "vendor\cache"
New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null

$ue4ssArchive = Join-Path $cacheRoot $lock.ue4ss.asset
if (Test-Path -LiteralPath $ue4ssArchive) {
    try {
        Assert-Sha256 -Path $ue4ssArchive -Expected $lock.ue4ss.assetSha256 | Out-Null
    } catch {
        Remove-Item -LiteralPath $ue4ssArchive -Force
    }
}

if (-not (Test-Path -LiteralPath $ue4ssArchive)) {
    Download-VerifiedReleaseAsset `
        -Repository $lock.ue4ss.repository `
        -Tags @($lock.ue4ss.releaseTags) `
        -AssetName $lock.ue4ss.asset `
        -ExpectedSha256 $lock.ue4ss.assetSha256 `
        -Destination $ue4ssArchive | Out-Null
}

$baseExtract = Join-Path $workRoot "ue4ss-base"
New-Item -ItemType Directory -Path $baseExtract | Out-Null
Expand-ZipSafe -Archive $ue4ssArchive -Destination $baseExtract -SafetyRoot $workRoot

$moreExtract = Join-Path $workRoot "more-players"
New-Item -ItemType Directory -Path $moreExtract | Out-Null
Expand-ThirdPartyArchiveSafe -Archive $archivePath -Destination $moreExtract -SafetyRoot $workRoot

$sourceProxy = Join-Path $baseExtract "dwmapi.dll"
$sourceUe4ss = Join-Path $baseExtract "ue4ss"
$sourceMod = Join-Path $moreExtract "FarFarWest\Binaries\Win64\ue4ss\Mods\FFWMorePlayers"
$sourcePaks = Join-Path $moreExtract "FarFarWest\Content\Paks\~mods"

$requiredSources = @(
    $sourceProxy,
    (Join-Path $sourceUe4ss "UE4SS.dll"),
    (Join-Path $sourceMod "enabled.txt"),
    (Join-Path $sourceMod "Scripts\main.lua"),
    (Join-Path $sourcePaks "ZZZ_FFWMorePlayers_P.pak"),
    (Join-Path $sourcePaks "ZZZ_FFWMorePlayers_P.ucas"),
    (Join-Path $sourcePaks "ZZZ_FFWMorePlayers_P.utoc")
)
foreach ($required in $requiredSources) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required source file is missing: $required"
    }
}

$mainLua = Join-Path $sourceMod "Scripts\main.lua"
$maxPlayersLine = Select-String -LiteralPath $mainLua -Pattern "^local TARGET_MAX_PLAYERS\s*=\s*(\d+)" | Select-Object -First 1
if (-not $maxPlayersLine) {
    throw "TARGET_MAX_PLAYERS was not found in More Players main.lua."
}
$actualMaxPlayers = [int]$maxPlayersLine.Matches[0].Groups[1].Value
if ($actualMaxPlayers -ne [int]$lock.morePlayers.defaultMaxPlayers) {
    throw "More Players target is $actualMaxPlayers, but the lock expects $($lock.morePlayers.defaultMaxPlayers)."
}

$packageRoot = Join-Path $workRoot "package"
$targetWin64 = Join-Path $packageRoot "FarFarWest\Binaries\Win64"
$targetPaks = Join-Path $packageRoot "FarFarWest\Content\Paks\~mods"
New-Item -ItemType Directory -Path $targetWin64 -Force | Out-Null
New-Item -ItemType Directory -Path $targetPaks -Force | Out-Null

Copy-Item -LiteralPath $sourceProxy -Destination (Join-Path $targetWin64 "dwmapi.dll")
Copy-Item -LiteralPath $sourceUe4ss -Destination (Join-Path $targetWin64 "ue4ss") -Recurse

$targetUe4ss = Join-Path $targetWin64 "ue4ss"
Copy-Item `
    -LiteralPath (Join-Path $projectRoot "config\ue4ss\UE4SS-settings.ini") `
    -Destination (Join-Path $targetUe4ss "UE4SS-settings.ini") `
    -Force

$targetSignatures = Join-Path $targetUe4ss "UE4SS_Signatures"
if (Test-Path -LiteralPath $targetSignatures) {
    $safeSignaturePath = Assert-PathInside -Root $workRoot -Path $targetSignatures
    Remove-Item -LiteralPath $safeSignaturePath -Recurse -Force
}
New-Item -ItemType Directory -Path $targetSignatures -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $projectRoot "config\ue4ss\UE4SS_Signatures") -File -Filter "*.lua" |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $targetSignatures $_.Name)
    }

Copy-Item -LiteralPath $sourceMod -Destination (Join-Path $targetUe4ss "Mods\FFWMorePlayers") -Recurse
foreach ($name in @(
    "ZZZ_FFWMorePlayers_P.pak",
    "ZZZ_FFWMorePlayers_P.ucas",
    "ZZZ_FFWMorePlayers_P.utoc"
)) {
    Copy-Item -LiteralPath (Join-Path $sourcePaks $name) -Destination (Join-Path $targetPaks $name)
}

$manifest = [pscustomobject]@{
    schemaVersion = 1
    builtAtUtc = [DateTime]::UtcNow.ToString("o")
    projectVersion = $lock.projectVersion
    targetProductVersion = $lock.target.productVersion
    targetExecutableSha256 = $lock.target.executableSha256
    unrealEngineOverride = "$($lock.target.unrealEngineMajor).$($lock.target.unrealEngineMinor)"
    ue4ss = [pscustomobject]@{
        repository = $lock.ue4ss.repository
        commit = $lock.ue4ss.commit
        asset = $lock.ue4ss.asset
        assetSha256 = Get-Sha256 -Path $ue4ssArchive
    }
    morePlayers = [pscustomobject]@{
        nexusModId = $lock.morePlayers.modId
        nexusFileId = $lock.morePlayers.fileId
        displayVersion = $lock.morePlayers.displayVersion
        archiveSha256 = Get-Sha256 -Path $archivePath
        defaultMaxPlayers = $actualMaxPlayers
        redistributionPermission = $false
    }
    runtimeTested = $false
}
Write-JsonFile -Value $manifest -Path (Join-Path $targetUe4ss "FARFARWEST_MODKIT_MANIFEST.json")

if (-not $OutputDirectory) {
    $outputRoot = Reset-SafeDirectory -ProjectRoot $projectRoot -Path (Join-Path $projectRoot "dist")
} else {
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}

$buildNumber = if ($lock.ue4ss.asset -match "-(\d+)-g[0-9a-fA-F]+\.zip$") {
    $Matches[1]
} else {
    "custom"
}
$gameVersion = ($lock.target.productVersion -replace "\s*-\s*", "-" -replace "\s+", "")
$zipName = "FarFarWest-Frostburn-$gameVersion-MorePlayers$actualMaxPlayers-UE4SS-$buildNumber.zip"
$outputZip = Join-Path $outputRoot $zipName
if (Test-Path -LiteralPath $outputZip) {
    throw "Output already exists: $outputZip"
}

Compress-Archive `
    -LiteralPath (Join-Path $packageRoot "FarFarWest") `
    -DestinationPath $outputZip `
    -CompressionLevel Optimal

$roundTrip = Join-Path $workRoot "round-trip"
New-Item -ItemType Directory -Path $roundTrip | Out-Null
Expand-ZipSafe -Archive $outputZip -Destination $roundTrip -SafetyRoot $workRoot

$sourceFiles = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File)
$verifiedFiles = 0
foreach ($sourceFile in $sourceFiles) {
    $relative = Get-RelativePath -Root $packageRoot -Path $sourceFile.FullName
    $roundTripFile = Join-Path $roundTrip $relative
    if (-not (Test-Path -LiteralPath $roundTripFile -PathType Leaf)) {
        throw "Round-trip verification failed; missing file: $relative"
    }

    if ((Get-Sha256 -Path $sourceFile.FullName) -ne (Get-Sha256 -Path $roundTripFile)) {
        throw "Round-trip verification failed; hash mismatch: $relative"
    }
    $verifiedFiles++
}

[pscustomobject]@{
    path = [IO.Path]::GetFullPath($outputZip)
    sha256 = Get-Sha256 -Path $outputZip
    size = (Get-Item -LiteralPath $outputZip).Length
    filesVerified = $verifiedFiles
    targetMaxPlayers = $actualMaxPlayers
    runtimeTested = $false
}
