[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameRoot,

    [string]$SignatureDirectory,

    [switch]$StrictLock,

    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
if (-not $SignatureDirectory) {
    $SignatureDirectory = Join-Path $projectRoot "config\ue4ss\UE4SS_Signatures"
}

$signaturePath = [IO.Path]::GetFullPath($SignatureDirectory)
if (-not (Test-Path -LiteralPath $signaturePath -PathType Container)) {
    throw "Signature directory not found: $signaturePath"
}

$exe = Get-GameExecutable -GameRoot $GameRoot -Lock $lock
$exeItem = Get-Item -LiteralPath $exe
$exeHash = Get-Sha256 -Path $exe
$productVersion = $exeItem.VersionInfo.ProductVersion
$lockHashMatch = $exeHash -eq $lock.target.executableSha256.ToUpperInvariant()
$lockVersionMatch = $productVersion -eq $lock.target.productVersion

# This is a read-only static scan. It never starts the game or reads process memory.
$data = [IO.File]::ReadAllBytes($exe)
$signatureResults = @()
foreach ($file in Get-ChildItem -LiteralPath $signaturePath -File -Filter "*.lua" | Sort-Object Name) {
    $pattern = Read-LuaAobPattern -Path $file.FullName
    $hits = @(Find-AobMatches -Data $data -Pattern $pattern -Limit 20)
    $tokens = $pattern.Split(" ", [StringSplitOptions]::RemoveEmptyEntries)

    $signatureResults += [pscustomobject]@{
        name = $file.Name
        bytes = $tokens.Count
        matches = $hits.Count
        fileOffsets = @($hits | ForEach-Object { "0x{0:X}" -f $_ })
        status = if ($hits.Count -eq 1) { "pass" } else { "fail" }
    }
}

$signaturePass = @($signatureResults | Where-Object { $_.matches -ne 1 }).Count -eq 0
$report = [pscustomobject]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString("o")
    mode = "static-only"
    game = [pscustomobject]@{
        executable = $exe
        productVersion = $productVersion
        sha256 = $exeHash
        lockedProductVersion = $lock.target.productVersion
        lockedSha256 = $lock.target.executableSha256
        lockVersionMatch = $lockVersionMatch
        lockHashMatch = $lockHashMatch
    }
    unrealEngineOverride = [pscustomobject]@{
        major = $lock.target.unrealEngineMajor
        minor = $lock.target.unrealEngineMinor
    }
    signatures = $signatureResults
    compatible = $signaturePass
    runtimeTested = $false
}

if (-not $NoWrite) {
    $reportPath = Join-Path $projectRoot "artifacts\compatibility-report.json"
    Write-JsonFile -Value $report -Path $reportPath
    Write-Host "Compatibility report: $reportPath"
}

$report

if (-not $signaturePass) {
    throw "Compatibility failed: every AOB signature must match exactly once."
}

if ($StrictLock -and (-not $lockHashMatch -or -not $lockVersionMatch)) {
    throw "The executable does not match the pinned game build. Refresh the lock after reviewing the update."
}
