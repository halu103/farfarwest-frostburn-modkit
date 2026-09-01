[CmdletBinding()]
param(
    [string]$GameRoot,

    [string]$MorePlayersArchive,

    [string]$MorePlayersVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$workRoot = Reset-SafeDirectory -ProjectRoot $projectRoot -Path (Join-Path $projectRoot "work\refresh")

$headers = @{
    "User-Agent" = "FarFarWest-Frostburn-Modkit"
    "Accept" = "application/vnd.github+json"
}
$release = Invoke-RestMethod `
    -Headers $headers `
    -Uri "https://api.github.com/repos/$($lock.ue4ss.repository)/releases/tags/experimental-latest"

$baseAsset = $release.assets |
    Where-Object { $_.name -match "^UE4SS_v.+-\d+-g[0-9a-fA-F]+\.zip$" } |
    Sort-Object updated_at -Descending |
    Select-Object -First 1
$configAsset = $release.assets |
    Where-Object { $_.name -eq "zCustomGameConfigs.zip" } |
    Select-Object -First 1

if (-not $baseAsset -or -not $configAsset) {
    throw "The current experimental release is missing the required assets."
}

$baseArchive = Join-Path $workRoot $baseAsset.name
$configArchive = Join-Path $workRoot $configAsset.name
Invoke-WebRequest -Headers $headers -Uri $baseAsset.browser_download_url -OutFile $baseArchive
Invoke-WebRequest -Headers $headers -Uri $configAsset.browser_download_url -OutFile $configArchive

$baseHash = Get-Sha256 -Path $baseArchive
$configHash = Get-Sha256 -Path $configArchive
if ($baseAsset.digest) {
    $expected = ($baseAsset.digest -replace "^sha256:", "").ToUpperInvariant()
    if ($baseHash -ne $expected) {
        throw "UE4SS asset hash does not match GitHub's digest."
    }
}
if ($configAsset.digest) {
    $expected = ($configAsset.digest -replace "^sha256:", "").ToUpperInvariant()
    if ($configHash -ne $expected) {
        throw "Custom config asset hash does not match GitHub's digest."
    }
}

$configExtract = Join-Path $workRoot "configs"
New-Item -ItemType Directory -Path $configExtract | Out-Null
Expand-ZipSafe -Archive $configArchive -Destination $configExtract -SafetyRoot $workRoot

$stagedConfig = Join-Path $configExtract "Far Far West"
$stagedSettings = Join-Path $stagedConfig "UE4SS-settings.ini"
$stagedSignatures = Join-Path $stagedConfig "UE4SS_Signatures"
$requiredSignatures = @(
    "FName_Constructor.lua",
    "GNatives.lua",
    "ProcessLocalScriptFunction.lua"
)

if (-not (Test-Path -LiteralPath $stagedSettings -PathType Leaf)) {
    throw "The official release does not contain Far Far West settings."
}
foreach ($name in $requiredSignatures) {
    if (-not (Test-Path -LiteralPath (Join-Path $stagedSignatures $name) -PathType Leaf)) {
        throw "The official release does not contain required signature: $name"
    }
}

if ($GameRoot) {
    & (Join-Path $PSScriptRoot "Test-Compatibility.ps1") `
        -GameRoot $GameRoot `
        -SignatureDirectory $stagedSignatures `
        -NoWrite | Out-Null
}

if ($baseAsset.name -notmatch "-g([0-9a-fA-F]+)\.zip$") {
    throw "Unable to obtain the UE4SS commit from asset name: $($baseAsset.name)"
}
$shortCommit = $Matches[1]
$commit = Invoke-RestMethod `
    -Headers $headers `
    -Uri "https://api.github.com/repos/$($lock.ue4ss.repository)/commits/$shortCommit"

$localConfig = Reset-SafeDirectory `
    -ProjectRoot $projectRoot `
    -Path (Join-Path $projectRoot "config\ue4ss")
Copy-Item -LiteralPath $stagedSettings -Destination (Join-Path $localConfig "UE4SS-settings.ini")
Copy-Item -LiteralPath $stagedSignatures -Destination (Join-Path $localConfig "UE4SS_Signatures") -Recurse

$majorLine = Select-String -LiteralPath $stagedSettings -Pattern "^MajorVersion\s*=\s*(\d+)" | Select-Object -First 1
$minorLine = Select-String -LiteralPath $stagedSettings -Pattern "^MinorVersion\s*=\s*(\d+)" | Select-Object -First 1
if (-not $majorLine -or -not $minorLine) {
    throw "Unable to read the engine override from staged settings."
}

$lock.ue4ss.commit = $commit.sha
$lock.ue4ss.asset = $baseAsset.name
$lock.ue4ss.assetSha256 = $baseHash
$lock.ue4ss.customConfigsAsset = $configAsset.name
$lock.ue4ss.customConfigsSha256 = $configHash
$lock.target.unrealEngineMajor = [int]$majorLine.Matches[0].Groups[1].Value
$lock.target.unrealEngineMinor = [int]$minorLine.Matches[0].Groups[1].Value

if ($GameRoot) {
    $exe = Get-GameExecutable -GameRoot $GameRoot -Lock $lock
    $item = Get-Item -LiteralPath $exe
    $lock.target.productVersion = $item.VersionInfo.ProductVersion
    $lock.target.executableSha256 = Get-Sha256 -Path $exe
}

if ($MorePlayersArchive) {
    if (-not $MorePlayersVersion) {
        throw "-MorePlayersVersion is required when updating the More Players archive."
    }

    $moreArchivePath = [IO.Path]::GetFullPath($MorePlayersArchive)
    if (-not (Test-Path -LiteralPath $moreArchivePath -PathType Leaf)) {
        throw "More Players archive not found: $moreArchivePath"
    }

    $moreExtract = Join-Path $workRoot "more-players"
    New-Item -ItemType Directory -Path $moreExtract | Out-Null
    Expand-ThirdPartyArchiveSafe `
        -Archive $moreArchivePath `
        -Destination $moreExtract `
        -SafetyRoot $workRoot

    $mainLua = Join-Path $moreExtract "FarFarWest\Binaries\Win64\ue4ss\Mods\FFWMorePlayers\Scripts\main.lua"
    $pakDir = Join-Path $moreExtract "FarFarWest\Content\Paks\~mods"
    $requiredMoreFiles = @(
        $mainLua,
        (Join-Path $pakDir "ZZZ_FFWMorePlayers_P.pak"),
        (Join-Path $pakDir "ZZZ_FFWMorePlayers_P.ucas"),
        (Join-Path $pakDir "ZZZ_FFWMorePlayers_P.utoc")
    )
    foreach ($required in $requiredMoreFiles) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Updated More Players archive is incomplete: $required"
        }
    }

    $internalLine = Select-String -LiteralPath $mainLua -Pattern '^local MOD_VERSION\s*=\s*"([^"]+)"' | Select-Object -First 1
    $maxLine = Select-String -LiteralPath $mainLua -Pattern "^local TARGET_MAX_PLAYERS\s*=\s*(\d+)" | Select-Object -First 1
    if (-not $internalLine -or -not $maxLine) {
        throw "Unable to read More Players version/max player fields."
    }

    $lock.morePlayers.displayVersion = $MorePlayersVersion
    $lock.morePlayers.internalLuaVersion = $internalLine.Matches[0].Groups[1].Value
    $lock.morePlayers.defaultMaxPlayers = [int]$maxLine.Matches[0].Groups[1].Value
    $lock.morePlayers.expectedArchiveSha256 = Get-Sha256 -Path $moreArchivePath
}

Write-JsonFile -Value $lock -Path (Join-Path $projectRoot "config\upstream.lock.json")

[pscustomobject]@{
    ue4ssCommit = $lock.ue4ss.commit
    ue4ssAsset = $lock.ue4ss.asset
    ue4ssAssetSha256 = $lock.ue4ss.assetSha256
    engineOverride = "$($lock.target.unrealEngineMajor).$($lock.target.unrealEngineMinor)"
    gameProductVersion = $lock.target.productVersion
    gameExecutableSha256 = $lock.target.executableSha256
    morePlayersVersion = $lock.morePlayers.displayVersion
    morePlayersSha256 = $lock.morePlayers.expectedArchiveSha256
    runtimeTested = $false
}
