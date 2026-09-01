[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameRoot,

    [Parameter(Mandatory)]
    [string]$Archive,

    [string]$BackupRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

function Remove-ManagedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $safePath = Assert-PathInside -Root $Root -Path $Path
    if (Test-Path -LiteralPath $safePath) {
        Remove-Item -LiteralPath $safePath -Recurse -Force
    }
}

function Copy-ManagedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Get-PathFileInventory {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RelativeTo
    )

    $item = Get-Item -LiteralPath $Path
    $files = if ($item.PSIsContainer) {
        @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File | Sort-Object FullName)
    } else {
        @($item)
    }

    $inventoryRoot = if ($item.PSIsContainer) {
        $RelativeTo
    } elseif ([IO.Path]::GetFullPath($RelativeTo).TrimEnd("\").Equals(
        $item.FullName.TrimEnd("\"),
        [StringComparison]::OrdinalIgnoreCase
    )) {
        Split-Path -Parent $item.FullName
    } else {
        $RelativeTo
    }

    return @($files | ForEach-Object {
        [pscustomobject]@{
            path = Get-RelativePath -Root $inventoryRoot -Path $_.FullName
            sha256 = Get-Sha256 -Path $_.FullName
        }
    })
}

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$gameRootPath = [IO.Path]::GetFullPath($GameRoot).TrimEnd("\")
$archivePath = [IO.Path]::GetFullPath($Archive)

if (-not (Test-Path -LiteralPath $gameRootPath -PathType Container)) {
    throw "Game root not found: $gameRootPath"
}
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Release archive not found: $archivePath"
}

# Refuse before doing any preparatory work. The check is repeated immediately
# before the first write to the game directory.
Assert-GameNotRunning

& (Join-Path $PSScriptRoot "Test-Compatibility.ps1") `
    -GameRoot $gameRootPath `
    -StrictLock `
    -NoWrite | Out-Null

$workRoot = Reset-SafeDirectory -ProjectRoot $projectRoot -Path (Join-Path $projectRoot "work\install")
$expanded = Join-Path $workRoot "release"
New-Item -ItemType Directory -Path $expanded | Out-Null
Expand-ZipSafe -Archive $archivePath -Destination $expanded -SafetyRoot $workRoot

$packageGameRoot = Join-Path $expanded "FarFarWest"
$packageManifestPath = Join-Path $packageGameRoot "Binaries\Win64\ue4ss\FARFARWEST_MODKIT_MANIFEST.json"
if (-not (Test-Path -LiteralPath $packageManifestPath -PathType Leaf)) {
    throw "This is not a modkit release: package manifest is missing."
}

$packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
if ($packageManifest.targetExecutableSha256 -ne $lock.target.executableSha256) {
    throw "The release targets a different Far Far West executable."
}
if ($packageManifest.ue4ss.commit -ne $lock.ue4ss.commit) {
    throw "The release uses a different UE4SS commit than the project lock."
}
if ($packageManifest.morePlayers.archiveSha256 -ne $lock.morePlayers.expectedArchiveSha256) {
    throw "The release uses a different More Players archive than the project lock."
}
if ($packageManifest.morePlayers.packageMode -ne $lock.morePlayers.packageMode -or $packageManifest.morePlayers.cookedAssetsIncluded) {
    throw "The release is not the Frostburn-safe Lua-only package."
}

$managed = @(
    [pscustomobject]@{
        relativePath = "FarFarWest\Binaries\Win64\dwmapi.dll"
        source = Join-Path $packageGameRoot "Binaries\Win64\dwmapi.dll"
        install = $true
    },
    [pscustomobject]@{
        relativePath = "FarFarWest\Binaries\Win64\ue4ss"
        source = Join-Path $packageGameRoot "Binaries\Win64\ue4ss"
        install = $true
    },
    [pscustomobject]@{
        relativePath = "FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.pak"
        source = $null
        install = $false
    },
    [pscustomobject]@{
        relativePath = "FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.ucas"
        source = $null
        install = $false
    },
    [pscustomobject]@{
        relativePath = "FarFarWest\Content\Paks\~mods\ZZZ_FFWMorePlayers_P.utoc"
        source = $null
        install = $false
    }
)

foreach ($entry in $managed) {
    if ($entry.install -and -not (Test-Path -LiteralPath $entry.source)) {
        throw "Required release payload is missing: $($entry.relativePath)"
    }
    if ($entry.install) {
        Assert-PathInside -Root $expanded -Path $entry.source | Out-Null
    }
    Assert-PathInside -Root $gameRootPath -Path (Join-Path $gameRootPath $entry.relativePath) | Out-Null
}

if (-not $BackupRoot) {
    $BackupRoot = Join-Path $projectRoot "artifacts\backups"
}
$backupRootPath = [IO.Path]::GetFullPath($BackupRoot)
New-Item -ItemType Directory -Path $backupRootPath -Force | Out-Null
$backupDirectory = Join-Path $backupRootPath ([DateTime]::UtcNow.ToString("yyyyMMdd-HHmmssZ"))
if (Test-Path -LiteralPath $backupDirectory) {
    throw "Backup directory already exists: $backupDirectory"
}
$backupPayload = Join-Path $backupDirectory "files"
New-Item -ItemType Directory -Path $backupPayload -Force | Out-Null

$backupRecords = @()
foreach ($entry in $managed) {
    $target = Assert-PathInside -Root $gameRootPath -Path (Join-Path $gameRootPath $entry.relativePath)
    $backupTarget = Assert-PathInside -Root $backupDirectory -Path (Join-Path $backupPayload $entry.relativePath)
    $existedBefore = Test-Path -LiteralPath $target

    if ($existedBefore) {
        Copy-ManagedPath -Source $target -Destination $backupTarget
        $backupFiles = @(Get-PathFileInventory -Path $backupTarget -RelativeTo $backupDirectory)
    } else {
        $backupFiles = @()
    }

    $backupRecords += [pscustomobject]@{
        relativePath = $entry.relativePath
        existedBefore = $existedBefore
        backupFiles = $backupFiles
    }
}

$backupManifestPath = Join-Path $backupDirectory "backup-manifest.json"
$backupManifest = [ordered]@{
    schemaVersion = 1
    status = "prepared"
    createdAtUtc = [DateTime]::UtcNow.ToString("o")
    gameRoot = $gameRootPath
    releaseArchive = $archivePath
    releaseArchiveSha256 = Get-Sha256 -Path $archivePath
    records = $backupRecords
}
Write-JsonFile -Value $backupManifest -Path $backupManifestPath

Assert-GameNotRunning

try {
    foreach ($entry in $managed) {
        $target = Assert-PathInside -Root $gameRootPath -Path (Join-Path $gameRootPath $entry.relativePath)
        Remove-ManagedPath -Root $gameRootPath -Path $target
        if ($entry.install) {
            Copy-ManagedPath -Source $entry.source -Destination $target
        }
    }

    foreach ($entry in $managed | Where-Object install) {
        $target = Join-Path $gameRootPath $entry.relativePath
        $sourceInventory = @(Get-PathFileInventory -Path $entry.source -RelativeTo $entry.source)
        $targetInventory = @(Get-PathFileInventory -Path $target -RelativeTo $target)
        if (($sourceInventory | ConvertTo-Json -Depth 5 -Compress) -ne ($targetInventory | ConvertTo-Json -Depth 5 -Compress)) {
            throw "Installed file verification failed: $($entry.relativePath)"
        }
    }

    $backupManifest.status = "installed"
    $backupManifest.completedAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-JsonFile -Value $backupManifest -Path $backupManifestPath
} catch {
    $installError = $_
    foreach ($record in $backupRecords) {
        $target = Assert-PathInside -Root $gameRootPath -Path (Join-Path $gameRootPath $record.relativePath)
        Remove-ManagedPath -Root $gameRootPath -Path $target
        if ($record.existedBefore) {
            $backupTarget = Assert-PathInside -Root $backupDirectory -Path (Join-Path $backupPayload $record.relativePath)
            Copy-ManagedPath -Source $backupTarget -Destination $target
        }
    }
    $backupManifest.status = "rolled-back-after-install-error"
    $backupManifest.error = $installError.Exception.Message
    Write-JsonFile -Value $backupManifest -Path $backupManifestPath
    throw $installError
}

[pscustomobject]@{
    installed = $true
    archive = $archivePath
    archiveSha256 = Get-Sha256 -Path $archivePath
    gameRoot = $gameRootPath
    backupDirectory = $backupDirectory
    runtimeTested = $false
}
