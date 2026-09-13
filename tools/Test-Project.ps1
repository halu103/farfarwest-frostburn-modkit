[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$mod = Get-ModData -ProjectRoot $projectRoot
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
    "Install-Mod.ps1",
    "README.md",
    "docs\INSTALLER.md",
    "docs\PUBLISHING.md",
    "docs\POWERSHELL.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "CHANGELOG.md",
    "config\upstream.lock.json",
    "config\ue4ss\UE4SS-settings.ini",
    "config\static-signatures\FName_Constructor.lua",
    "config\ue4ss\UE4SS_Signatures\GNatives.lua",
    "config\ue4ss\UE4SS_Signatures\ProcessLocalScriptFunction.lua",
    "src\mod.json",
    "src\Mods\FFWFrostburn8\enabled.txt",
    "src\Mods\FFWFrostburn8\Scripts\main.lua",
    "docs\UPDATE_GUIDE.md",
    "installer\Installer.cs",
    "installer\Uninstaller.cs",
    "installer\app.manifest",
    "tools\Build-InstallerExe.ps1",
    "tools\Build-UninstallerExe.ps1",
    "tools\Build-DownloadBundle.ps1",
    "tools\Build-Release.ps1",
    "tools\Install-Release.ps1",
    "tools\Refresh-Upstream.ps1",
    "tools\Restore-Backup.ps1",
    "tools\Test-Compatibility.ps1",
    "tools\Test-InstallerExe.ps1",
    "tools\Test-UninstallerExe.ps1",
    "tools\Test-Project.ps1",
    "tools\Test-RuntimeLog.ps1",
    "tools\lib\Common.ps1",
    ".github\workflows\validate.yml"
)
foreach ($relative in $requiredFiles) {
    Assert-ProjectCheck -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf) `
        -Message "Required file is missing: $relative"
}

$readmePath = Join-Path $projectRoot "README.md"
$powershellGuidePath = Join-Path $projectRoot "docs\POWERSHELL.md"
$installerGuidePath = Join-Path $projectRoot "docs\INSTALLER.md"
if ((Test-Path -LiteralPath $readmePath -PathType Leaf) -and
    (Test-Path -LiteralPath $powershellGuidePath -PathType Leaf) -and
    (Test-Path -LiteralPath $installerGuidePath -PathType Leaf)) {
    $powerShellDocs = (Get-Content -LiteralPath $readmePath -Raw) + "`n" +
        (Get-Content -LiteralPath $powershellGuidePath -Raw) + "`n" +
        (Get-Content -LiteralPath $installerGuidePath -Raw)
    Assert-ProjectCheck -Condition ($powerShellDocs -match 'powershell\.exe') `
        -Message "Public documentation is missing the Windows PowerShell 5.1 command."
    Assert-ProjectCheck -Condition ($powerShellDocs -match 'pwsh\.exe') `
        -Message "Public documentation is missing the PowerShell 7+ command."
    Assert-ProjectCheck -Condition ($powerShellDocs -match '\$PSVersionTable\.PSEdition') `
        -Message "Public documentation is missing PowerShell edition detection."
    Assert-ProjectCheck -Condition ($powerShellDocs -match '(?i)Setup\.exe') `
        -Message "Public documentation is missing the no-PowerShell installer path."
}

$publishingGuidePath = Join-Path $projectRoot "docs\PUBLISHING.md"
if ((Test-Path -LiteralPath $readmePath -PathType Leaf) -and
    (Test-Path -LiteralPath $publishingGuidePath -PathType Leaf)) {
    $releaseDocs = (Get-Content -LiteralPath $readmePath -Raw) + "`n" +
        (Get-Content -LiteralPath $publishingGuidePath -Raw)
    Assert-ProjectCheck -Condition ($releaseDocs -match 'releases/latest/download/FFWFrostburn8-Windows-x64\.zip') `
        -Message "Public documentation is missing the stable GitHub Release download link."
    Assert-ProjectCheck -Condition ($releaseDocs -match '(?is)Code.*Download ZIP' -and
        $releaseDocs -match '(?i)source') `
        -Message "Documentation must distinguish GitHub's source ZIP from the player build."
}

Assert-ProjectCheck -Condition ($lock.schemaVersion -eq 2) -Message "Unsupported lock schema."
Assert-ProjectCheck -Condition ($mod.schemaVersion -eq 1) -Message "Unsupported mod metadata schema."
Assert-ProjectCheck -Condition ($mod.id -eq "FFWFrostburn8") -Message "Unexpected owned mod id."
Assert-ProjectCheck -Condition ($mod.version -match "^\d+\.\d+\.\d+$") -Message "Mod version must use semantic versioning."
Assert-ProjectCheck -Condition ([int]$mod.maxPlayers -eq 8) -Message "Owned mod must target eight players."
Assert-ProjectCheck -Condition ([int]$mod.sessionRows -eq 8) -Message "Session UI must target eight rows."
Assert-ProjectCheck -Condition ([int]$mod.soloInviteSlots -eq 7) -Message "Solo host UI must target seven invite slots."
Assert-ProjectCheck -Condition ([bool]$mod.requiresAllowMods) -Message "Expanded Session UI must require the game's Allow mods setting."
Assert-ProjectCheck -Condition ([bool]$mod.uiSynchronizesPlayerRows) -Message "Session UI must synchronize real player rows before invite rows."
Assert-ProjectCheck -Condition ($mod.deploymentMode -eq "host-only-experimental") `
    -Message "The current version must be labelled as host-only experimental."
Assert-ProjectCheck -Condition ($mod.vanillaClientCompatibility -eq "unverified") `
    -Message "Vanilla-client compatibility must remain unverified until a live multiplayer test passes."
Assert-ProjectCheck -Condition ($mod.license -eq "MIT") -Message "Owned mod source must remain MIT licensed."
Assert-ProjectCheck -Condition ($mod.packageMode -eq "source-owned-lua" -and -not [bool]$mod.cookedAssetsIncluded) `
    -Message "The Frostburn release must contain only the owned Lua mod."
Assert-ProjectCheck -Condition ($lock.PSObject.Properties.Name -notcontains "morePlayers") `
    -Message "The upstream lock must not contain third-party mod metadata."
Assert-ProjectCheck -Condition ($lock.ue4ss.commit -match "^[0-9a-f]{40}$") -Message "UE4SS commit is not a full Git hash."
foreach ($value in @(
    $lock.target.executableSha256,
    $lock.ue4ss.assetSha256,
    $lock.ue4ss.customConfigsSha256
)) {
    Assert-ProjectCheck -Condition ($value -match "^[0-9A-F]{64}$") -Message "A locked SHA-256 value is invalid: $value"
}
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

$sourceRoot = Join-Path $projectRoot "src"
$sourceMod = $null
try {
    $sourceMod = Assert-PathInside `
        -Root $sourceRoot `
        -Path (Join-Path $sourceRoot $mod.sourceDirectory.Replace("/", "\"))
    $checks++
} catch {
    $failures.Add("Invalid mod source path: $($_.Exception.Message)")
}
if ($sourceMod -and (Test-Path -LiteralPath $sourceMod -PathType Container)) {
    $mainLuaPath = Join-Path $sourceMod "Scripts\main.lua"
    if (Test-Path -LiteralPath $mainLuaPath -PathType Leaf) {
        $mainLua = Get-Content -LiteralPath $mainLuaPath -Raw
        $versionPattern = '(?m)^local MOD_VERSION\s*=\s*"' + [regex]::Escape([string]$mod.version) + '"\s*$'
        $maxPattern = '(?m)^local TARGET_MAX_PLAYERS\s*=\s*' + [regex]::Escape([string]$mod.maxPlayers) + '\s*$'
        Assert-ProjectCheck -Condition ($mainLua -match $versionPattern) `
            -Message "Lua MOD_VERSION does not match src/mod.json."
        Assert-ProjectCheck -Condition ($mainLua -match $maxPattern) `
            -Message "Lua TARGET_MAX_PLAYERS does not match src/mod.json."
        Assert-ProjectCheck -Condition ($mainLua -match 'UI_Menu_Container_CurrentSession' -and $mainLua -match 'VerticalBox_Players') `
            -Message "Owned Lua source is missing the current-session UI expansion."
        Assert-ProjectCheck -Condition ($mainLua -match 'UI_Menu_Button_Session_Invite') `
            -Message "Owned Lua source is missing the Frostburn invite-row widget class."
        Assert-ProjectCheck -Condition ($mainLua -match 'UI_Menu_SessionMember' -and
            $mainLua -match 'playerState' -and
            $mainLua -match 'playersObserved=%d') `
            -Message "Owned Lua source is missing real-player row synchronization."
        Assert-ProjectCheck -Condition ($mainLua -match 'TextBlock_Cheats' -and
            $mainLua -match 'SessionUiGate') `
            -Message "Owned Lua source is missing the Allow mods UI gate."
        Assert-ProjectCheck -Condition ($mainLua -match 'SessionUi .*READY=%s') `
            -Message "Owned Lua source is missing the verified Session UI runtime marker."
        Assert-ProjectCheck -Condition ($mainLua -match '(?m)^local HOST_ONLY_EXPERIMENTAL\s*=\s*true\s*$' -and
            $mainLua -match '(?m)^local VANILLA_MAX_PLAYERS\s*=\s*4\s*$') `
            -Message "Owned Lua source is missing the explicit host-only experimental guardrails."
        Assert-ProjectCheck -Condition ($mainLua -match [regex]::Escape('/Script/SteamCorePro.SteamUtilities:KickPlayer') -and
            $mainLua -match [regex]::Escape('/Script/SteamCorePro.SteamProMatchmaking:CreateLobby') -and
            $mainLua -match [regex]::Escape('/Script/SteamCorePro.SteamCoreProMatchmakingAsyncActionCreateLobby:CreateLobbyAsync')) `
            -Message "Owned Lua source is missing a required host-side lobby or selective join hook path."
        Assert-ProjectCheck -Condition ($mainLua -match 'HostOnlyMode=EXPERIMENTAL' -and
            $mainLua -match 'HostOnlyRoomGate' -and
            $mainLua -match 'HostOnlyLobbyWrite' -and
            $mainLua -match 'HostOnlyJoinGuard action=BLOCK_EMPTY_JOIN_KICK') `
            -Message "Owned Lua source is missing host-only runtime evidence markers."
        Assert-ProjectCheck -Condition ($mainLua -match 'SessionUiGateRace' -and
            $mainLua -match 'F_CreateSession-sticky' -and
            $mainLua -match 'SessionUiVerified') `
            -Message "Owned Lua source is missing the Allow Mods race fix or exact Invite-row evidence."
        Assert-ProjectCheck -Condition ($mainLua -notmatch '(?i)FFWMorePlayers|Nexus') `
            -Message "Owned Lua source contains a forbidden third-party mod reference."
        try {
            Get-DirectoryTreeSha256 -Path $sourceMod | Out-Null
            $checks++
        } catch {
            $failures.Add("Unable to hash the owned mod source: $($_.Exception.Message)")
        }
    }
}

$parseTargets = @(
    Get-Item -LiteralPath (Join-Path $projectRoot "Install-Mod.ps1")
    Get-ChildItem -LiteralPath (Join-Path $projectRoot "tools") -Recurse -File -Filter "*.ps1"
)
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
        -Message "Generated binary/archive must not be committed: $(Get-RelativePath -Root $projectRoot -Path $file.FullName)"
}

$buildScript = Get-Content -LiteralPath (Join-Path $projectRoot "tools\Build-Release.ps1") -Raw
Assert-ProjectCheck -Condition ($buildScript -notmatch '(?i)MorePlayersArchive|Nexus') `
    -Message "Build-Release.ps1 still depends on a downloaded third-party mod archive."

$installerSourcePath = Join-Path $projectRoot "installer\Installer.cs"
$uninstallerSourcePath = Join-Path $projectRoot "installer\Uninstaller.cs"
$installerManifestPath = Join-Path $projectRoot "installer\app.manifest"
$installerBuildPath = Join-Path $projectRoot "tools\Build-InstallerExe.ps1"
$uninstallerBuildPath = Join-Path $projectRoot "tools\Build-UninstallerExe.ps1"
$downloadBundlePath = Join-Path $projectRoot "tools\Build-DownloadBundle.ps1"
if ((Test-Path -LiteralPath $installerSourcePath -PathType Leaf) -and
    (Test-Path -LiteralPath $installerManifestPath -PathType Leaf) -and
    (Test-Path -LiteralPath $installerBuildPath -PathType Leaf)) {
    $installerSource = Get-Content -LiteralPath $installerSourcePath -Raw
    $installerManifest = Get-Content -LiteralPath $installerManifestPath -Raw
    $installerBuild = Get-Content -LiteralPath $installerBuildPath -Raw
    Assert-ProjectCheck -Condition ($installerSource -match 'EnsureGameNotRunning') `
        -Message "The GUI installer does not guard against an active game process."
    Assert-ProjectCheck -Condition ($installerSource -match 'FarFarWest-Win64-Shipping' -and
        $installerSource -match '"FarFarWest"') `
        -Message "The GUI installer does not recognize both Far Far West process names."
    Assert-ProjectCheck -Condition ($installerSource -match 'ReleaseSha256' -and
        $installerSource -match 'SourceTreeSha256') `
        -Message "The GUI installer is missing embedded-release or source-tree verification."
    Assert-ProjectCheck -Condition ($installerSource -match 'rolled-back-after-install-error') `
        -Message "The GUI installer is missing automatic rollback tracking."
    Assert-ProjectCheck -Condition ($installerSource -notmatch '(?i)powershell\.exe|pwsh\.exe') `
        -Message "The GUI installer must be native and must not wrap a PowerShell command."
    Assert-ProjectCheck -Condition ($installerSource -match 'host-only-experimental' -and
        $installerSource -match 'vanillaClientCompatibility' -and
        $installerSource -match 'soloInviteSlots') `
        -Message "The GUI installer is not validating the experimental deployment metadata."
    Assert-ProjectCheck -Condition ($installerManifest -match 'requestedExecutionLevel level="asInvoker"') `
        -Message "The GUI installer manifest must not demand elevation automatically."
    Assert-ProjectCheck -Condition ($installerBuild -match 'FFWFrostburn8\.Payload\.zip' -and
        $installerBuild -match '/target:winexe') `
        -Message "Build-InstallerExe.ps1 is not embedding the offline release in a Windows GUI executable."
}
if ((Test-Path -LiteralPath $uninstallerSourcePath -PathType Leaf) -and
    (Test-Path -LiteralPath $uninstallerBuildPath -PathType Leaf)) {
    $uninstallerSource = Get-Content -LiteralPath $uninstallerSourcePath -Raw
    $uninstallerBuild = Get-Content -LiteralPath $uninstallerBuildPath -Raw
    Assert-ProjectCheck -Condition ($uninstallerSource -match 'AssertOwnedInstallation' -and
        $uninstallerSource -match 'FARFARWEST_MODKIT_MANIFEST\.json') `
        -Message "The native uninstaller is missing ownership validation."
    Assert-ProjectCheck -Condition ($uninstallerSource -match 'FindCleanBackup' -and
        $uninstallerSource -match 'ValidateBackupCandidate' -and
        $uninstallerSource -match 'Hashing\.AssertInventory') `
        -Message "The native uninstaller is missing clean-backup selection or integrity verification."
    Assert-ProjectCheck -Condition ($uninstallerSource -match 'UninstallSafety' -and
        $uninstallerSource -match 'rolled-back-after-uninstall-error') `
        -Message "The native uninstaller is missing its safety backup or automatic rollback."
    Assert-ProjectCheck -Condition ($uninstallerSource -match 'FFWFrostburn8-Installer-v1' -and
        $uninstallerSource -match 'EnsureGameNotRunning' -and
        $uninstallerSource -match 'AcquireGameStartGuard') `
        -Message "The native uninstaller does not share the installer lock or guard against game startup."
    Assert-ProjectCheck -Condition ($uninstallerSource -notmatch '(?i)powershell\.exe|pwsh\.exe') `
        -Message "The GUI uninstaller must be native and must not wrap a PowerShell command."
    Assert-ProjectCheck -Condition ($uninstallerBuild -match '/main:FFWFrostburn8Installer\.UninstallerProgram' -and
        $uninstallerBuild -match '/target:winexe' -and
        $uninstallerBuild -match '/platform:x64') `
        -Message "Build-UninstallerExe.ps1 is not compiling the dedicated native x64 GUI entry point."
}
if (Test-Path -LiteralPath $downloadBundlePath -PathType Leaf) {
    $downloadBundle = Get-Content -LiteralPath $downloadBundlePath -Raw
    Assert-ProjectCheck -Condition ($downloadBundle -match 'FFWFrostburn8-Windows-x64\.zip') `
        -Message "The player bundle does not use the stable GitHub Release asset name."
    Assert-ProjectCheck -Condition ($downloadBundle -match 'flat root layout' -and
        $downloadBundle -match 'round-trip hash mismatch') `
        -Message "The player bundle is missing flat-layout or round-trip verification."
    foreach ($bundleRootName in @(
        "FFWFrostburn8-Setup.exe",
        "FFWFrostburn8-Uninstall.exe",
        "README-VI.txt",
        "SHA256SUMS.txt",
        "LICENSE.txt",
        "THIRD-PARTY-NOTICES.txt"
    )) {
        Assert-ProjectCheck -Condition ($downloadBundle -match [regex]::Escape($bundleRootName)) `
            -Message "The player bundle allowlist is missing: $bundleRootName"
    }
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
