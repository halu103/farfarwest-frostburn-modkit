[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameRoot,

    [Parameter(Mandatory)]
    [string]$BackupDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

$gameRootPath = [IO.Path]::GetFullPath($GameRoot).TrimEnd("\")
$backupPath = [IO.Path]::GetFullPath($BackupDirectory).TrimEnd("\")
$manifestPath = Join-Path $backupPath "backup-manifest.json"
$payloadPath = Join-Path $backupPath "files"

if (-not (Test-Path -LiteralPath $gameRootPath -PathType Container)) {
    throw "Game root not found: $gameRootPath"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Backup manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
    throw "Unsupported backup schema: $($manifest.schemaVersion)"
}
if (-not $gameRootPath.Equals([IO.Path]::GetFullPath($manifest.gameRoot).TrimEnd("\"), [StringComparison]::OrdinalIgnoreCase)) {
    throw "This backup belongs to another game directory: $($manifest.gameRoot)"
}

foreach ($record in $manifest.records) {
    Assert-PathInside -Root $gameRootPath -Path (Join-Path $gameRootPath $record.relativePath) | Out-Null
    if ($record.existedBefore) {
        foreach ($file in $record.backupFiles) {
            $backupFile = Assert-PathInside -Root $backupPath -Path (Join-Path $backupPath $file.path)
            if (-not (Test-Path -LiteralPath $backupFile -PathType Leaf)) {
                throw "Backup payload is missing: $($file.path)"
            }
            Assert-Sha256 -Path $backupFile -Expected $file.sha256 | Out-Null
        }
    }
}

Assert-GameNotRunning

foreach ($record in $manifest.records) {
    $target = Assert-PathInside -Root $gameRootPath -Path (Join-Path $gameRootPath $record.relativePath)
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }

    if ($record.existedBefore) {
        $backupTarget = Assert-PathInside -Root $backupPath -Path (Join-Path $payloadPath $record.relativePath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $backupTarget -Destination $target -Recurse -Force
    }
}

[pscustomobject]@{
    restored = $true
    gameRoot = $gameRootPath
    backupDirectory = $backupPath
    restoredAtUtc = [DateTime]::UtcNow.ToString("o")
}
