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
    preUninstallSafetyBackupVerified = $true
    repeatedUninstallRefused = $true
    corruptedBackupRefusedBeforeWrite = $true
    injectedFailureObserved = $true
    completeSafetyRollbackVerified = $true
    nativeEntrypointWithSpacesVerified = $true
    realGameExecutableUnchanged = $true
    gameLaunched = $false
    realGameFilesInstalled = $false
    sandboxRoot = $testRoot
}
