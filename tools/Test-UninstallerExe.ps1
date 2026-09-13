[CmdletBinding()]
param(
    [string]$GameRoot,

    [string]$InstallerPath,

    [string]$UninstallerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSEdition -eq "Core") {
    $forwardArguments = @()
    foreach ($entry in @(
        @("-GameRoot", $GameRoot),
        @("-InstallerPath", $InstallerPath),
        @("-UninstallerPath", $UninstallerPath)
    )) {
        if ($entry[1]) {
            $forwardArguments += $entry[0]
            $forwardArguments += $entry[1]
        }
    }
    & powershell.exe `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $PSCommandPath `
        @forwardArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The Windows PowerShell 5.1 uninstaller-engine test failed (exit code $LASTEXITCODE)."
    }
    return
}

. (Join-Path $PSScriptRoot "lib\Common.ps1")

function Assert-TestGameNotRunning {
    $running = @(Get-Process -Name "FarFarWest", "FarFarWest-Win64-Shipping" -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $identities = $running | ForEach-Object { "$($_.ProcessName) PID $($_.Id)" }
        throw "Far Far West is running ($($identities -join ', ')). The sandbox uninstaller test refuses to run while you are playing."
    }
}

function New-UninstallerTestGame {
    param(
        [Parameter(Mandatory)] [string]$TestRoot,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$SourceExecutable,
        [Parameter(Mandatory)] [object]$Lock
    )

    $root = Join-Path $TestRoot "$Name\game"
    $executable = Join-Path $root $Lock.target.executableRelativePath.Replace('/', '\')
    $win64 = Split-Path -Parent $executable
    New-Item -ItemType Directory -Path $win64 -Force | Out-Null
    Copy-Item -LiteralPath $SourceExecutable -Destination $executable
    [IO.File]::WriteAllText(
        (Join-Path $win64 "dwmapi.dll"),
        "uninstaller-test-old-proxy-$Name",
        [Text.UTF8Encoding]::new($false)
    )
    $oldUe4ss = Join-Path $win64 "ue4ss"
    New-Item -ItemType Directory -Path (Join-Path $oldUe4ss "Mods\ExistingUserMod") -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $oldUe4ss "Mods\ExistingUserMod\old.txt"),
        "uninstaller-test-existing-mod-$Name",
        [Text.UTF8Encoding]::new($false)
    )
    $legacyRoot = Join-Path $root "FarFarWest\Content\Paks\~mods"
    New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null
    foreach ($extension in @("pak", "ucas", "utoc")) {
        [IO.File]::WriteAllText(
            (Join-Path $legacyRoot "ZZZ_FFWMorePlayers_P.$extension"),
            "uninstaller-test-legacy-$extension-$Name",
            [Text.UTF8Encoding]::new($false)
        )
    }
    $unmanaged = Join-Path $root "FarFarWest\Content\UninstallerTestUnmanaged"
    New-Item -ItemType Directory -Path $unmanaged -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $unmanaged "sentinel.txt"),
        "uninstaller-test-unmanaged-$Name",
        [Text.UTF8Encoding]::new($false)
    )
    return [IO.Path]::GetFullPath($root)
}

function Add-TestOwnedInstallation {
    param(
        [Parameter(Mandatory)] [string]$GameRoot,
        [string]$Version = "legacy"
    )

    $ue4ssRoot = Join-Path $GameRoot "FarFarWest\Binaries\Win64\ue4ss"
    $modRoot = Join-Path $ue4ssRoot "Mods\FFWFrostburn8"
    New-Item -ItemType Directory -Path (Join-Path $modRoot "Scripts") -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $modRoot "Scripts\main.lua"),
        "local MOD_VERSION = `"$Version`"`n",
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $modRoot "enabled.txt"),
        "enabled`n",
        [Text.UTF8Encoding]::new($false)
    )
    $marker = [ordered]@{
        schemaVersion = 2
        mod = [ordered]@{
            id = "FFWFrostburn8"
            version = $Version
            packageMode = "source-owned-lua"
        }
    } | ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText(
        (Join-Path $ue4ssRoot "FARFARWEST_MODKIT_MANIFEST.json"),
        $marker + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function Get-InternalProperty {
    param(
        [Parameter(Mandatory)] [object]$InputObject,
        [Parameter(Mandatory)] [string]$Name
    )
    $flags = [Reflection.BindingFlags]::Instance -bor `
        [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Public
    $property = $InputObject.GetType().GetProperty($Name, $flags)
    if (-not $property) {
        throw "Internal result property was not found: $Name"
    }
    return $property.GetValue($InputObject, $null)
}

function Get-StaticMethod {
    param(
        [Parameter(Mandatory)] [Reflection.Assembly]$Assembly,
        [Parameter(Mandatory)] [string]$TypeName,
        [Parameter(Mandatory)] [string]$MethodName,
        [Parameter(Mandatory)] [int]$ParameterCount
    )
    $type = $Assembly.GetType($TypeName, $true)
    $flags = [Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic
    $method = @($type.GetMethods($flags) | Where-Object {
        $_.Name -eq $MethodName -and $_.GetParameters().Count -eq $ParameterCount
    }) | Select-Object -First 1
    if (-not $method) {
        throw "Native engine method was not found: $TypeName.$MethodName/$ParameterCount"
    }
    return $method
}

function Invoke-ReflectedMethod {
    param(
        [Parameter(Mandatory)] [Reflection.MethodInfo]$Method,
        [Parameter(Mandatory)] [object[]]$Arguments
    )
    $nativeArguments = [object[]]::new($Arguments.Count)
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $value = $Arguments[$index]
        if ($value -is [Management.Automation.PSObject]) {
            $value = $value.PSObject.BaseObject
        }
        $nativeArguments[$index] = $value
    }
    try {
        return $Method.Invoke($null, $nativeArguments)
    } catch [Reflection.TargetInvocationException] {
        if ($_.Exception.InnerException) {
            throw $_.Exception.InnerException
        }
        throw
    }
}

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$resolvedGameRoot = Resolve-FarFarWestGameRoot -GameRoot $GameRoot -Lock $lock
$sourceExecutable = Get-GameExecutable -GameRoot $resolvedGameRoot -Lock $lock
Assert-Sha256 -Path $sourceExecutable -Expected $lock.target.executableSha256 | Out-Null
Assert-TestGameNotRunning

if (-not $InstallerPath) {
    $InstallerPath = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "dist") -File -Filter "*-Setup.exe" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $UninstallerPath) {
    $UninstallerPath = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "dist") -File -Filter "*-Uninstall.exe" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
$installer = [IO.Path]::GetFullPath($InstallerPath)
$uninstaller = [IO.Path]::GetFullPath($UninstallerPath)
foreach ($path in @($installer, $uninstaller)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required executable was not found: $path"
    }
}

$testRootCandidate = Assert-PathInside -Root $projectRoot -Path (Join-Path $projectRoot "work\uninstaller-e2e")
if (Test-Path -LiteralPath $testRootCandidate) {
    $reparsePoints = @(
        Get-Item -LiteralPath $testRootCandidate -Force
        Get-ChildItem -LiteralPath $testRootCandidate -Force -Recurse
    ) | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
    if ($reparsePoints) {
        throw "The existing uninstaller sandbox contains a reparse point: $($reparsePoints[0].FullName)"
    }
}
$testRoot = Reset-SafeDirectory -ProjectRoot $projectRoot -Path $testRootCandidate

$installerAssembly = [Reflection.Assembly]::LoadFile($installer)
$uninstallerAssembly = [Reflection.Assembly]::LoadFile($uninstaller)
$installMethod = Get-StaticMethod `
    -Assembly $installerAssembly `
    -TypeName "FFWFrostburn8Installer.InstallerEngine" `
    -MethodName "Install" `
    -ParameterCount 3
$uninstallMethod = Get-StaticMethod `
    -Assembly $uninstallerAssembly `
    -TypeName "FFWFrostburn8Installer.UninstallerEngine" `
    -MethodName "Uninstall" `
    -ParameterCount 3
$faultMethod = Get-StaticMethod `
    -Assembly $uninstallerAssembly `
    -TypeName "FFWFrostburn8Installer.UninstallerEngine" `
    -MethodName "Uninstall" `
    -ParameterCount 4
$modOnlyMethod = Get-StaticMethod `
    -Assembly $uninstallerAssembly `
    -TypeName "FFWFrostburn8Installer.UninstallerEngine" `
    -MethodName "UninstallModOnly" `
    -ParameterCount 3
$modOnlyFaultMethod = Get-StaticMethod `
    -Assembly $uninstallerAssembly `
    -TypeName "FFWFrostburn8Installer.UninstallerEngine" `
    -MethodName "UninstallModOnly" `
    -ParameterCount 4
$logger = [Action[string]]{ param([string]$line) }

# Successful complete uninstall and repeat-run refusal.
$successGame = New-UninstallerTestGame `
    -TestRoot $testRoot `
    -Name "success path with spaces" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
$successOriginalHash = Get-DirectoryTreeSha256 -Path $successGame
$successBackupRoot = Join-Path $testRoot "success path with spaces\Backups"
Invoke-ReflectedMethod -Method $installMethod -Arguments @($successGame, $logger, $successBackupRoot) | Out-Null
# Simulate an in-place update. The second backup contains an older
# FFWFrostburn8 installation, so a complete uninstall must skip it and select
# the earlier clean pre-install backup.
Invoke-ReflectedMethod -Method $installMethod -Arguments @($successGame, $logger, $successBackupRoot) | Out-Null
$successResult = Invoke-ReflectedMethod `
    -Method $uninstallMethod `
    -Arguments @($successGame, $logger, $successBackupRoot)
$successSafety = [string](Get-InternalProperty -InputObject $successResult -Name "SafetyBackupDirectory")
$successManifest = Get-Content -LiteralPath (Join-Path $successSafety "backup-manifest.json") -Raw | ConvertFrom-Json
if ((Get-DirectoryTreeSha256 -Path $successGame) -ne $successOriginalHash -or
    $successManifest.status -ne "uninstalled") {
    throw "The uninstaller did not restore the complete original sandbox state."
}
$repeatHash = Get-DirectoryTreeSha256 -Path $successGame
$repeatRefused = $false
try {
    Invoke-ReflectedMethod -Method $uninstallMethod -Arguments @($successGame, $logger, $successBackupRoot) | Out-Null
} catch {
    $repeatRefused = $_.Exception.Message -match "No active FFWFrostburn8 installation"
}
if (-not $repeatRefused -or (Get-DirectoryTreeSha256 -Path $successGame) -ne $repeatHash) {
    throw "A repeated uninstall was not refused without changing files."
}

# An upgrade from an older owned build may have backups, but every backup can
# already contain FFWFrostburn8. In that case remove only the project-owned mod
# and marker while preserving the currently installed UE4SS and unrelated mods.
$legacyGame = New-UninstallerTestGame `
    -TestRoot $testRoot `
    -Name "legacy backup fallback" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
Add-TestOwnedInstallation -GameRoot $legacyGame -Version "1.2.1"
$legacyBackupRoot = Join-Path $testRoot "legacy backup fallback\Backups"
Invoke-ReflectedMethod -Method $installMethod -Arguments @($legacyGame, $logger, $legacyBackupRoot) | Out-Null
$legacyWin64 = Join-Path $legacyGame "FarFarWest\Binaries\Win64"
$legacyUnrelated = Join-Path $legacyWin64 "ue4ss\Mods\UnrelatedAfterInstall\keep.txt"
New-Item -ItemType Directory -Path (Split-Path -Parent $legacyUnrelated) -Force | Out-Null
[IO.File]::WriteAllText($legacyUnrelated, "preserve-me", [Text.UTF8Encoding]::new($false))
$legacyProxyHash = Get-Sha256 -Path (Join-Path $legacyWin64 "dwmapi.dll")
$legacyRuntimeHash = Get-Sha256 -Path (Join-Path $legacyWin64 "ue4ss\UE4SS.dll")
$legacyUnrelatedHash = Get-Sha256 -Path $legacyUnrelated
$legacyResult = Invoke-ReflectedMethod `
    -Method $modOnlyMethod `
    -Arguments @($legacyGame, $logger, $legacyBackupRoot)
$legacyMode = [string](Get-InternalProperty -InputObject $legacyResult -Name "RemovalMode")
$legacySafety = [string](Get-InternalProperty -InputObject $legacyResult -Name "SafetyBackupDirectory")
$legacySafetyManifest = Get-Content -LiteralPath (Join-Path $legacySafety "backup-manifest.json") -Raw |
    ConvertFrom-Json
if ($legacyMode -ne "mod-only" -or $legacySafetyManifest.status -ne "uninstalled-mod-only" -or
    (Test-Path -LiteralPath (Join-Path $legacyWin64 "ue4ss\Mods\FFWFrostburn8")) -or
    (Test-Path -LiteralPath (Join-Path $legacyWin64 "ue4ss\FARFARWEST_MODKIT_MANIFEST.json")) -or
    (Get-Sha256 -Path (Join-Path $legacyWin64 "dwmapi.dll")) -ne $legacyProxyHash -or
    (Get-Sha256 -Path (Join-Path $legacyWin64 "ue4ss\UE4SS.dll")) -ne $legacyRuntimeHash -or
    (Get-Sha256 -Path $legacyUnrelated) -ne $legacyUnrelatedHash) {
    throw "The legacy-backup fallback did not remove only FFWFrostburn8 while preserving UE4SS."
}

# A project-owned installation without any backup also uses mod-only removal.
$missingBackupGame = New-UninstallerTestGame `
    -TestRoot $testRoot `
    -Name "missing backup fallback" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
Add-TestOwnedInstallation -GameRoot $missingBackupGame -Version "1.1.2"
$missingBackupRoot = Join-Path $testRoot "missing backup fallback\Backups"
$missingWin64 = Join-Path $missingBackupGame "FarFarWest\Binaries\Win64"
$missingProxyHash = Get-Sha256 -Path (Join-Path $missingWin64 "dwmapi.dll")
$missingUserMod = Join-Path $missingWin64 "ue4ss\Mods\ExistingUserMod\old.txt"
$missingUserModHash = Get-Sha256 -Path $missingUserMod
$missingResult = Invoke-ReflectedMethod `
    -Method $modOnlyMethod `
    -Arguments @($missingBackupGame, $logger, $missingBackupRoot)
$missingMode = [string](Get-InternalProperty -InputObject $missingResult -Name "RemovalMode")
if ($missingMode -ne "mod-only" -or
    (Test-Path -LiteralPath (Join-Path $missingWin64 "ue4ss\Mods\FFWFrostburn8")) -or
    (Test-Path -LiteralPath (Join-Path $missingWin64 "ue4ss\FARFARWEST_MODKIT_MANIFEST.json")) -or
    (Get-Sha256 -Path (Join-Path $missingWin64 "dwmapi.dll")) -ne $missingProxyHash -or
    (Get-Sha256 -Path $missingUserMod) -ne $missingUserModHash) {
    throw "The missing-backup fallback did not preserve UE4SS and unrelated files."
}

# A corrupt original backup must be rejected before the game tree changes.
$corruptGame = New-UninstallerTestGame `
    -TestRoot $testRoot `
    -Name "corrupt backup path" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
$corruptBackupRoot = Join-Path $testRoot "corrupt backup path\Backups"
$corruptInstall = Invoke-ReflectedMethod `
    -Method $installMethod `
    -Arguments @($corruptGame, $logger, $corruptBackupRoot)
$corruptBackup = [string](Get-InternalProperty -InputObject $corruptInstall -Name "BackupDirectory")
$corruptFile = Join-Path $corruptBackup `
    "files\FarFarWest\Binaries\Win64\ue4ss\Mods\ExistingUserMod\old.txt"
[IO.File]::AppendAllText($corruptFile, "tampered", [Text.UTF8Encoding]::new($false))
$corruptInstalledHash = Get-DirectoryTreeSha256 -Path $corruptGame
$corruptRefused = $false
try {
    Invoke-ReflectedMethod -Method $uninstallMethod -Arguments @($corruptGame, $logger, $corruptBackupRoot) | Out-Null
} catch {
    $corruptRefused = $_.Exception.Message -match "hash mismatch|inventory"
}
if (-not $corruptRefused -or (Get-DirectoryTreeSha256 -Path $corruptGame) -ne $corruptInstalledHash) {
    throw "A damaged backup was not rejected before changing the installed game tree."
}

# A newer damaged clean snapshot must not block an older valid clean snapshot.
$candidateGame = New-UninstallerTestGame `
    -TestRoot $testRoot `
    -Name "older valid backup candidate" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
$candidateOriginalHash = Get-DirectoryTreeSha256 -Path $candidateGame
$candidateBackupRoot = Join-Path $testRoot "older valid backup candidate\Backups"
$candidateFirstInstall = Invoke-ReflectedMethod `
    -Method $installMethod `
    -Arguments @($candidateGame, $logger, $candidateBackupRoot)
$candidateOlderBackup = [string](Get-InternalProperty -InputObject $candidateFirstInstall -Name "BackupDirectory")
Invoke-ReflectedMethod -Method $uninstallMethod -Arguments @(
    $candidateGame, $logger, $candidateBackupRoot
) | Out-Null
$candidateSecondInstall = Invoke-ReflectedMethod `
    -Method $installMethod `
    -Arguments @($candidateGame, $logger, $candidateBackupRoot)
$candidateNewerBackup = [string](Get-InternalProperty -InputObject $candidateSecondInstall -Name "BackupDirectory")
$candidateCorruptFile = Join-Path $candidateNewerBackup `
    "files\FarFarWest\Binaries\Win64\ue4ss\Mods\ExistingUserMod\old.txt"
[IO.File]::AppendAllText($candidateCorruptFile, "tampered", [Text.UTF8Encoding]::new($false))
$candidateResult = Invoke-ReflectedMethod `
    -Method $uninstallMethod `
    -Arguments @($candidateGame, $logger, $candidateBackupRoot)
$candidateRestoredBackup = [string](Get-InternalProperty `
    -InputObject $candidateResult `
    -Name "RestoredBackupDirectory")
if (-not [String]::Equals(
        [IO.Path]::GetFullPath($candidateRestoredBackup),
        [IO.Path]::GetFullPath($candidateOlderBackup),
        [StringComparison]::OrdinalIgnoreCase) -or
    (Get-DirectoryTreeSha256 -Path $candidateGame) -ne $candidateOriginalHash) {
    throw "A newer damaged clean snapshot blocked the older valid clean snapshot."
}

# Inject a failure after the first restore step and prove safety rollback.
$rollbackGame = New-UninstallerTestGame `
    -TestRoot $testRoot `
    -Name "rollback path with spaces" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
$rollbackBackupRoot = Join-Path $testRoot "rollback path with spaces\Backups"
Invoke-ReflectedMethod -Method $installMethod -Arguments @($rollbackGame, $logger, $rollbackBackupRoot) | Out-Null
$rollbackInstalledHash = Get-DirectoryTreeSha256 -Path $rollbackGame
$fault = [Action[int]]{
    param([int]$step)
    if ($step -eq 2) {
        throw "Injected uninstaller restore failure."
    }
}
$rollbackObserved = $false
try {
    Invoke-ReflectedMethod `
        -Method $faultMethod `
        -Arguments @($rollbackGame, $logger, $rollbackBackupRoot, $fault) | Out-Null
} catch {
    $rollbackObserved = $_.Exception.Message -match "rolled back from the safety backup"
}
$rollbackSafetyRoot = Join-Path (Split-Path -Parent $rollbackBackupRoot) "UninstallSafety"
$rollbackSafety = Get-ChildItem -LiteralPath $rollbackSafetyRoot -Directory |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$rollbackManifest = Get-Content -LiteralPath (Join-Path $rollbackSafety.FullName "backup-manifest.json") -Raw |
    ConvertFrom-Json
if (-not $rollbackObserved -or $rollbackManifest.status -ne "rolled-back-after-uninstall-error" -or
    (Get-DirectoryTreeSha256 -Path $rollbackGame) -ne $rollbackInstalledHash) {
    throw "Injected uninstaller failure did not restore the complete installed state."
}

# Inject a failure during mod-only fallback and prove its safety backup also
# restores the complete installed tree.
$fallbackRollbackGame = New-UninstallerTestGame `
    -TestRoot $testRoot `
    -Name "mod only rollback" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
Add-TestOwnedInstallation -GameRoot $fallbackRollbackGame -Version "1.2.1"
$fallbackRollbackBackupRoot = Join-Path $testRoot "mod only rollback\Backups"
$fallbackRollbackHash = Get-DirectoryTreeSha256 -Path $fallbackRollbackGame
$fallbackFault = [Action[int]]{
    param([int]$step)
    if ($step -eq 2) {
        throw "Injected mod-only removal failure."
    }
}
$fallbackRollbackObserved = $false
try {
    Invoke-ReflectedMethod `
        -Method $modOnlyFaultMethod `
        -Arguments @($fallbackRollbackGame, $logger, $fallbackRollbackBackupRoot, $fallbackFault) | Out-Null
} catch {
    $fallbackRollbackObserved = $_.Exception.Message -match "rolled back from the safety backup"
}
$fallbackSafetyRoot = Join-Path (Split-Path -Parent $fallbackRollbackBackupRoot) "UninstallSafety"
$fallbackSafety = Get-ChildItem -LiteralPath $fallbackSafetyRoot -Directory |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$fallbackManifest = Get-Content -LiteralPath (Join-Path $fallbackSafety.FullName "backup-manifest.json") -Raw |
    ConvertFrom-Json
if (-not $fallbackRollbackObserved -or
    $fallbackManifest.status -ne "rolled-back-after-uninstall-error" -or
    (Get-DirectoryTreeSha256 -Path $fallbackRollbackGame) -ne $fallbackRollbackHash) {
    throw "Injected mod-only failure did not restore the complete installed state."
}

# Verify the native executable entry point without opening its GUI.
$entryPointLog = Join-Path $testRoot "native uninstaller verification.log"
$entryPointProcess = Start-Process `
    -FilePath $uninstaller `
    -ArgumentList @(
        "--verify-only",
        "--game-root",
        ('"' + $successGame + '"'),
        "--log",
        ('"' + $entryPointLog + '"')
    ) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($entryPointProcess.ExitCode -ne 0 -or
    (Get-Content -LiteralPath $entryPointLog -Raw) -notmatch "Uninstaller verification completed successfully") {
    throw "The native uninstaller read-only entry point failed on a path containing spaces."
}

Assert-Sha256 -Path $sourceExecutable -Expected $lock.target.executableSha256 | Out-Null

[pscustomobject]@{
    passed = $true
    uninstaller = $uninstaller
    uninstallerSha256 = Get-Sha256 -Path $uninstaller
    completePreInstallStateRestored = $true
    cleanBackupSelected = $true
    updateChainUnwoundToCleanState = $true
    legacyBackupModOnlyRemovalVerified = $true
    missingBackupModOnlyRemovalVerified = $true
    ue4ssAndOtherModsPreserved = $true
    preUninstallSafetyBackupVerified = $true
    repeatedUninstallRefused = $true
    corruptedBackupRefusedBeforeWrite = $true
    newerCorruptBackupSkippedForOlderValid = $true
    injectedFailureObserved = $true
    completeSafetyRollbackVerified = $true
    modOnlySafetyRollbackVerified = $true
    nativeEntrypointWithSpacesVerified = $true
    realGameExecutableUnchanged = $true
    gameLaunched = $false
    realGameFilesInstalled = $false
    sandboxRoot = $testRoot
}
