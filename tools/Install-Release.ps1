[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameRoot,

    [Parameter(Mandatory)]
    [string]$Archive,

    [Parameter(Mandatory)]
    [ValidatePattern("^[0-9A-Fa-f]{64}$")]
    [string]$ExpectedArchiveSha256,

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

function Test-PathWithinOrEqual {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\")
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd("\")
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + "\", [StringComparison]::OrdinalIgnoreCase)
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
$mod = Get-ModData -ProjectRoot $projectRoot
$gameRootPath = [IO.Path]::GetFullPath($GameRoot).TrimEnd("\")
$archivePath = [IO.Path]::GetFullPath($Archive)

if (-not (Test-Path -LiteralPath $gameRootPath -PathType Container)) {
    throw "Game root not found: $gameRootPath"
}
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Release archive not found: $archivePath"
}
Assert-Sha256 -Path $archivePath -Expected $ExpectedArchiveSha256 | Out-Null

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
if ($packageManifest.schemaVersion -ne 2) {
    throw "Unsupported release manifest schema: $($packageManifest.schemaVersion)"
}
if ($packageManifest.targetExecutableSha256 -ne $lock.target.executableSha256) {
    throw "The release targets a different Far Far West executable."
}
if ($packageManifest.ue4ss.commit -ne $lock.ue4ss.commit) {
    throw "The release uses a different UE4SS commit than the project lock."
}
if ($packageManifest.ue4ss.assetSha256 -ne $lock.ue4ss.assetSha256) {
    throw "The release uses a different UE4SS archive than the project lock."
}
if (
    $packageManifest.mod.id -ne $mod.id -or
    $packageManifest.mod.version -ne $mod.version -or
    [int]$packageManifest.mod.maxPlayers -ne [int]$mod.maxPlayers -or
    $packageManifest.mod.license -ne $mod.license -or
    $packageManifest.mod.packageMode -ne $mod.packageMode -or
    [bool]$packageManifest.mod.cookedAssetsIncluded
) {
    throw "The release metadata does not match the source-owned mod."
}

$packageModRoot = Join-Path $packageGameRoot "Binaries\Win64\ue4ss\Mods\$($mod.id)"
if (-not (Test-Path -LiteralPath $packageModRoot -PathType Container)) {
    throw "The release is missing the source-owned mod: $($mod.id)"
}
$packageModHash = Get-DirectoryTreeSha256 -Path $packageModRoot
if ($packageModHash -ne $packageManifest.mod.sourceTreeSha256) {
    throw "The packaged mod source-tree hash is invalid."
}
$localSourceRoot = Join-Path $projectRoot "src"
$localSourceMod = Assert-PathInside `
    -Root $localSourceRoot `
    -Path (Join-Path $localSourceRoot $mod.sourceDirectory.Replace("/", "\"))
if ($packageModHash -ne (Get-DirectoryTreeSha256 -Path $localSourceMod)) {
    throw "The release was not built from the current owned mod source."
}

$cookedPayload = @(Get-ChildItem -LiteralPath $packageGameRoot -Recurse -File | Where-Object {
    $_.Extension.ToLowerInvariant() -in @(".pak", ".ucas", ".utoc")
})
if ($cookedPayload.Count -gt 0) {
    throw "The source-owned Lua release must not contain cooked PAK/UCAS/UTOC files."
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
if (Test-PathWithinOrEqual -Root $gameRootPath -Path $backupRootPath) {
    throw "BackupRoot must not be inside the game directory."
}
if (Test-PathWithinOrEqual -Root $workRoot -Path $backupRootPath) {
    throw "BackupRoot must not be inside the install staging directory."
}
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
    modId = $mod.id
    modVersion = $mod.version
    targetMaxPlayers = [int]$mod.maxPlayers
    sourceTreeSha256 = $packageModHash
    archive = $archivePath
    archiveSha256 = Get-Sha256 -Path $archivePath
    gameRoot = $gameRootPath
    backupDirectory = $backupDirectory
    runtimeTested = $false
}
