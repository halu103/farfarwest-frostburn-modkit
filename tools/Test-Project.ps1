[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$failures = [Collections.Generic.List[string]]::new()
$checks = 0

function Assert-ProjectCheck {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:checks++
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

$requiredFiles = @(
    ".gitignore",
    ".gitattributes",
    "README.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "CHANGELOG.md",
    "config\upstream.lock.json",
    "config\ue4ss\UE4SS-settings.ini",
    "config\static-signatures\FName_Constructor.lua",
    "config\ue4ss\UE4SS_Signatures\GNatives.lua",
    "config\ue4ss\UE4SS_Signatures\ProcessLocalScriptFunction.lua",
    "docs\UPDATE_GUIDE.md",
    "tools\Build-Release.ps1",
    "tools\Install-Release.ps1",
    "tools\Refresh-Upstream.ps1",
    "tools\Restore-Backup.ps1",
    "tools\Test-Compatibility.ps1",
    "tools\Test-Project.ps1",
    "tools\Test-RuntimeLog.ps1",
    "tools\lib\Common.ps1",
    ".github\workflows\validate.yml"
)
foreach ($relative in $requiredFiles) {
    Assert-ProjectCheck -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf) `
        -Message "Required file is missing: $relative"
}

Assert-ProjectCheck -Condition ($lock.schemaVersion -eq 1) -Message "Unsupported lock schema."
Assert-ProjectCheck -Condition ($lock.ue4ss.commit -match "^[0-9a-f]{40}$") -Message "UE4SS commit is not a full Git hash."
foreach ($value in @(
    $lock.target.executableSha256,
    $lock.ue4ss.assetSha256,
    $lock.ue4ss.customConfigsSha256,
    $lock.morePlayers.expectedArchiveSha256
)) {
    Assert-ProjectCheck -Condition ($value -match "^[0-9A-F]{64}$") -Message "A locked SHA-256 value is invalid: $value"
}
Assert-ProjectCheck -Condition (-not [bool]$lock.morePlayers.redistributable) `
    -Message "More Players must remain marked non-redistributable."
Assert-ProjectCheck -Condition ($lock.morePlayers.packageMode -eq "lua-only" -and -not [bool]$lock.morePlayers.cookedAssetsCompatible) `
    -Message "Frostburn releases must stay Lua-only until the cooked assets are rebuilt for UE 5.8."
Assert-ProjectCheck -Condition (@($lock.ue4ss.runtimeExcludedSignatures) -contains "FName_Constructor.lua") `
    -Message "The known-bad UE 5.8 FName runtime override must remain excluded."

$settingsPath = Join-Path $projectRoot "config\ue4ss\UE4SS-settings.ini"
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw
    Assert-ProjectCheck -Condition ($settings -match "(?m)^MajorVersion\s*=\s*$($lock.target.unrealEngineMajor)\s*$") `
        -Message "UE4SS MajorVersion does not match the lock."
    Assert-ProjectCheck -Condition ($settings -match "(?m)^MinorVersion\s*=\s*$($lock.target.unrealEngineMinor)\s*$") `
        -Message "UE4SS MinorVersion does not match the lock."
    Assert-ProjectCheck -Condition ($settings -match "(?m)^HookProcessLocalScriptFunction\s*=\s*1\s*$") `
        -Message "The Frostburn ProcessLocalScriptFunction hook is not enabled."
}

$signatureDirectory = Join-Path $projectRoot "config\ue4ss\UE4SS_Signatures"
if (Test-Path -LiteralPath $signatureDirectory -PathType Container) {
    $actualSignatures = @(Get-ChildItem -LiteralPath $signatureDirectory -File -Filter "*.lua" | Sort-Object Name | Select-Object -ExpandProperty Name)
    $expectedSignatures = @("GNatives.lua", "ProcessLocalScriptFunction.lua") | Sort-Object
    Assert-ProjectCheck -Condition (($actualSignatures -join "|") -eq ($expectedSignatures -join "|")) `
        -Message "The tracked signature set is incomplete or contains unexpected files."
    foreach ($signature in $actualSignatures) {
        try {
            Read-LuaAobPattern -Path (Join-Path $signatureDirectory $signature) | Out-Null
            $checks++
        } catch {
            $failures.Add("Invalid signature file $signature`: $($_.Exception.Message)")
        }
    }
}

$staticSignatureDirectory = Join-Path $projectRoot "config\static-signatures"
if (Test-Path -LiteralPath $staticSignatureDirectory -PathType Container) {
    $staticSignatures = @(Get-ChildItem -LiteralPath $staticSignatureDirectory -File -Filter "*.lua")
    Assert-ProjectCheck -Condition ($staticSignatures.Count -eq 1 -and $staticSignatures[0].Name -eq "FName_Constructor.lua") `
        -Message "The static-only FName compatibility sentinel is missing or ambiguous."
    foreach ($signature in $staticSignatures) {
        try {
            Read-LuaAobPattern -Path $signature.FullName | Out-Null
            $checks++
        } catch {
            $failures.Add("Invalid static signature file $($signature.Name)`: $($_.Exception.Message)")
        }
    }
}

$parseTargets = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "tools") -Recurse -File -Filter "*.ps1")
foreach ($scriptFile in $parseTargets) {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null
    $checks++
    foreach ($parseError in @($parseErrors)) {
        $failures.Add("PowerShell syntax error in $($scriptFile.Name): $($parseError.Message)")
    }
}

$excludedPattern = "[\\/](\.git|artifacts|dist|vendor|work)[\\/]"
$sourceFiles = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch $excludedPattern
})
$forbiddenExtensions = @(".7z", ".zip", ".pak", ".ucas", ".utoc")
foreach ($file in $sourceFiles) {
    Assert-ProjectCheck -Condition ($forbiddenExtensions -notcontains $file.Extension.ToLowerInvariant()) `
        -Message "Third-party/generated archive must not be committed: $(Get-RelativePath -Root $projectRoot -Path $file.FullName)"
}

$result = [pscustomobject]@{
    passed = $failures.Count -eq 0
    checks = $checks
    scriptsParsed = $parseTargets.Count
    sourceFilesReviewed = $sourceFiles.Count
    failures = @($failures)
}
$result

if ($failures.Count -gt 0) {
    throw "Project validation failed with $($failures.Count) error(s)."
}
