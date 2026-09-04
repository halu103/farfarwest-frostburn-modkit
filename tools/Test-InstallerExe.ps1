[CmdletBinding()]
param(
    [string]$GameRoot,

    [string]$InstallerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSEdition -eq "Core") {
    $forwardArguments = @()
    if ($GameRoot) {
        $forwardArguments += "-GameRoot"
        $forwardArguments += $GameRoot
    }
    if ($InstallerPath) {
        $forwardArguments += "-InstallerPath"
        $forwardArguments += $InstallerPath
    }
    & powershell.exe `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $PSCommandPath `
        @forwardArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The Windows PowerShell 5.1 installer-engine test failed (exit code $LASTEXITCODE)."
    }
    return
}

. (Join-Path $PSScriptRoot "lib\Common.ps1")

function New-InstallerTestGame {
    param(
        [Parameter(Mandatory)]
        [string]$TestRoot,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$SourceExecutable,

        [Parameter(Mandatory)]
        [object]$Lock
    )

    $root = Join-Path $TestRoot "$Name\game"
    $executable = Join-Path $root $Lock.target.executableRelativePath.Replace('/', '\')
    $win64 = Split-Path -Parent $executable
    New-Item -ItemType Directory -Path $win64 -Force | Out-Null
    Copy-Item -LiteralPath $SourceExecutable -Destination $executable

    [IO.File]::WriteAllText(
        (Join-Path $win64 "dwmapi.dll"),
        "installer-test-old-proxy-$Name",
        [Text.UTF8Encoding]::new($false)
    )
    $oldUe4ss = Join-Path $win64 "ue4ss"
    New-Item -ItemType Directory -Path (Join-Path $oldUe4ss "Mods\ExistingUserMod") -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $oldUe4ss "Mods\ExistingUserMod\old.txt"),
        "installer-test-existing-mod-$Name",
        [Text.UTF8Encoding]::new($false)
    )

    $legacyRoot = Join-Path $root "FarFarWest\Content\Paks\~mods"
    New-Item -ItemType Directory -Path $legacyRoot -Force | Out-Null
    foreach ($extension in @("pak", "ucas", "utoc")) {
        [IO.File]::WriteAllText(
            (Join-Path $legacyRoot "ZZZ_FFWMorePlayers_P.$extension"),
            "installer-test-legacy-$extension-$Name",
            [Text.UTF8Encoding]::new($false)
        )
    }

    $unmanagedRoot = Join-Path $root "FarFarWest\Content\InstallerTestUnmanaged"
    New-Item -ItemType Directory -Path $unmanagedRoot -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $unmanagedRoot "sentinel.txt"),
        "installer-test-unmanaged-$Name",
        [Text.UTF8Encoding]::new($false)
    )

    return [IO.Path]::GetFullPath($root)
}

function Assert-TestGameNotRunning {
    $running = @(
        Get-Process -Name "FarFarWest", "FarFarWest-Win64-Shipping" -ErrorAction SilentlyContinue
    )
    if ($running.Count -gt 0) {
        $identities = $running | ForEach-Object { "$($_.ProcessName) PID $($_.Id)" }
        throw "Far Far West is running ($($identities -join ', ')). The sandbox installer test refuses to run while you are playing."
    }
}

function Get-InternalProperty {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $flags = [Reflection.BindingFlags]::Instance -bor `
        [Reflection.BindingFlags]::NonPublic -bor `
        [Reflection.BindingFlags]::Public
    $property = $InputObject.GetType().GetProperty($Name, $flags)
    if (-not $property) {
        throw "Internal result property was not found: $Name"
    }
    return $property.GetValue($InputObject, $null)
}

function Invoke-InstallerEngine {
    param(
        [Parameter(Mandatory)]
        [Reflection.MethodInfo]$Method,

        [Parameter(Mandatory)]
        [string]$TestGameRoot,

        [Parameter(Mandatory)]
        [Action[string]]$Logger,

        [Parameter(Mandatory)]
        [string]$BackupRoot
    )

    try {
        return $Method.Invoke($null, [object[]]@($TestGameRoot, $Logger, $BackupRoot))
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
    $installers = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "dist") -File -Filter "*-Setup.exe" |
        Sort-Object -Property LastWriteTime -Descending)
    if ($installers.Count -eq 0) {
        throw "No Setup.exe was found under dist/. Build it first with tools\Build-InstallerExe.ps1."
    }
    $InstallerPath = $installers[0].FullName
}
$installer = [IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer executable was not found: $installer"
}

$testRootCandidate = Assert-PathInside `
    -Root $projectRoot `
    -Path (Join-Path $projectRoot "work\installer-e2e")
if (Test-Path -LiteralPath $testRootCandidate) {
    $reparsePoints = @(
        Get-Item -LiteralPath $testRootCandidate -Force
        Get-ChildItem -LiteralPath $testRootCandidate -Force -Recurse
    ) | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
    if ($reparsePoints) {
        throw "The existing installer test sandbox contains a reparse point and will not be reset: $($reparsePoints[0].FullName)"
    }
}
$testRoot = Reset-SafeDirectory -ProjectRoot $projectRoot -Path $testRootCandidate
$successGame = New-InstallerTestGame `
    -TestRoot $testRoot `
    -Name "success path with spaces" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
$rollbackGame = New-InstallerTestGame `
    -TestRoot $testRoot `
    -Name "rollback path with spaces" `
    -SourceExecutable $sourceExecutable `
    -Lock $lock
$rollbackInitialTreeSha256 = Get-DirectoryTreeSha256 -Path $rollbackGame

$assembly = [Reflection.Assembly]::LoadFile($installer)
$engineType = $assembly.GetType("FFWFrostburn8Installer.InstallerEngine", $true)
$methodFlags = [Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic
$installMethod = @($engineType.GetMethods($methodFlags) | Where-Object {
    $_.Name -eq "Install" -and $_.GetParameters().Count -eq 3
}) | Select-Object -First 1
if (-not $installMethod) {
    throw "The testable native installer engine entry point was not found."
}

$successLog = [Collections.Generic.List[string]]::new()
$successLogger = [Action[string]]{
    param([string]$line)
    $successLog.Add($line)
}
$successBackupRoot = Join-Path $testRoot "success-backups"
$successResult = Invoke-InstallerEngine `
    -Method $installMethod `
    -TestGameRoot $successGame `
    -Logger $successLogger `
    -BackupRoot $successBackupRoot
$successBackup = [string](Get-InternalProperty -InputObject $successResult -Name "BackupDirectory")
$successManifestPath = Join-Path $successBackup "backup-manifest.json"
$successManifest = Get-Content -LiteralPath $successManifestPath -Raw | ConvertFrom-Json

$successWin64 = Join-Path $successGame "FarFarWest\Binaries\Win64"
$successLegacy = Join-Path $successGame "FarFarWest\Content\Paks\~mods"
$successChecks = @(
    ($successManifest.status -eq "installed"),
    ($successManifest.records.Count -eq 5),
    (@($successManifest.records | Where-Object { -not $_.existedBefore }).Count -eq 0),
    (@($successManifest.records | Where-Object { $_.backupFiles.Count -lt 1 }).Count -eq 0),
    (Test-Path -LiteralPath (Join-Path $successWin64 "ue4ss\UE4SS.dll") -PathType Leaf),
    (Test-Path -LiteralPath (Join-Path $successWin64 "ue4ss\Mods\FFWFrostburn8\Scripts\main.lua") -PathType Leaf),
    (-not (Test-Path -LiteralPath (Join-Path $successWin64 "ue4ss\Mods\ExistingUserMod\old.txt"))),
    (-not (Test-Path -LiteralPath (Join-Path $successLegacy "ZZZ_FFWMorePlayers_P.pak"))),
    (-not (Test-Path -LiteralPath (Join-Path $successLegacy "ZZZ_FFWMorePlayers_P.ucas"))),
    (-not (Test-Path -LiteralPath (Join-Path $successLegacy "ZZZ_FFWMorePlayers_P.utoc"))),
    (Test-Path -LiteralPath (Join-Path $successBackup "files\FarFarWest\Binaries\Win64\ue4ss\Mods\ExistingUserMod\old.txt") -PathType Leaf),
    ((Get-Content -LiteralPath (Join-Path $successGame "FarFarWest\Content\InstallerTestUnmanaged\sentinel.txt") -Raw) -eq
        "installer-test-unmanaged-success path with spaces"),
    ((Get-Sha256 -Path (Join-Path $successGame $lock.target.executableRelativePath.Replace('/', '\'))) -eq
        $lock.target.executableSha256)
)
if ($successChecks -contains $false) {
    throw "The successful-install sandbox did not reach the expected final state."
}

$rollbackState = [pscustomobject]@{
    Stream = $null
    LockOpened = $false
    RollbackObserved = $false
    Lines = [Collections.Generic.List[string]]::new()
}
$rollbackLockedFile = Join-Path $rollbackGame `
    "FarFarWest\Binaries\Win64\ue4ss\Mods\ExistingUserMod\old.txt"
$rollbackLogger = [Action[string]]{
    param([string]$line)
    $rollbackState.Lines.Add($line)
    if (-not $rollbackState.LockOpened -and $line.StartsWith("Game is closed and its executable is locked", [StringComparison]::Ordinal)) {
        $rollbackState.Stream = [IO.File]::Open(
            $rollbackLockedFile,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::None
        )
        $rollbackState.LockOpened = $true
    }
    if ($line.StartsWith("Install failed; restoring every prepared backup entry.", [StringComparison]::Ordinal)) {
        $rollbackState.RollbackObserved = $true
        if ($rollbackState.Stream) {
            $rollbackState.Stream.Dispose()
            $rollbackState.Stream = $null
        }
    }
}
$rollbackBackupRoot = Join-Path $testRoot "rollback-backups"
$rollbackException = $null
try {
    Invoke-InstallerEngine `
        -Method $installMethod `
        -TestGameRoot $rollbackGame `
        -Logger $rollbackLogger `
        -BackupRoot $rollbackBackupRoot | Out-Null
} catch {
    $rollbackException = $_.Exception
} finally {
    if ($rollbackState.Stream) {
        $rollbackState.Stream.Dispose()
        $rollbackState.Stream = $null
    }
}
if (-not $rollbackException -or -not $rollbackState.LockOpened -or -not $rollbackState.RollbackObserved) {
    throw "The rollback fault injection did not trigger the expected install error and rollback path."
}

$rollbackBackup = Get-ChildItem -LiteralPath $rollbackBackupRoot -Directory |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -First 1
if (-not $rollbackBackup) {
    throw "The rollback test did not create a backup manifest."
}
$rollbackManifest = Get-Content -LiteralPath (Join-Path $rollbackBackup.FullName "backup-manifest.json") -Raw |
    ConvertFrom-Json
$rollbackWin64 = Join-Path $rollbackGame "FarFarWest\Binaries\Win64"
$rollbackLegacy = Join-Path $rollbackGame "FarFarWest\Content\Paks\~mods"
$rollbackChecks = @(
    ($rollbackManifest.status -eq "rolled-back-after-install-error"),
    ((Get-Content -LiteralPath (Join-Path $rollbackWin64 "dwmapi.dll") -Raw) -eq "installer-test-old-proxy-rollback path with spaces"),
    ((Get-Content -LiteralPath (Join-Path $rollbackWin64 "ue4ss\Mods\ExistingUserMod\old.txt") -Raw) -eq "installer-test-existing-mod-rollback path with spaces"),
    ((Get-Content -LiteralPath (Join-Path $rollbackLegacy "ZZZ_FFWMorePlayers_P.pak") -Raw) -eq "installer-test-legacy-pak-rollback path with spaces"),
    ((Get-Content -LiteralPath (Join-Path $rollbackLegacy "ZZZ_FFWMorePlayers_P.ucas") -Raw) -eq "installer-test-legacy-ucas-rollback path with spaces"),
    ((Get-Content -LiteralPath (Join-Path $rollbackLegacy "ZZZ_FFWMorePlayers_P.utoc") -Raw) -eq "installer-test-legacy-utoc-rollback path with spaces"),
    ((Get-DirectoryTreeSha256 -Path $rollbackGame) -eq $rollbackInitialTreeSha256),
    ((Get-Sha256 -Path (Join-Path $rollbackGame $lock.target.executableRelativePath.Replace('/', '\'))) -eq
        $lock.target.executableSha256)
)
if ($rollbackChecks -contains $false) {
    throw "The rollback sandbox did not restore the complete original state."
}

Assert-Sha256 -Path $sourceExecutable -Expected $lock.target.executableSha256 | Out-Null

$entryPointLog = Join-Path $testRoot "native-entrypoint-verification.log"
$entryPointArguments = @(
    "--verify-only",
    "--game-root",
    ('"' + $successGame + '"'),
    "--log",
    ('"' + $entryPointLog + '"')
)
$entryPointProcess = Start-Process `
    -FilePath $installer `
    -ArgumentList $entryPointArguments `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($entryPointProcess.ExitCode -ne 0 -or
    -not (Test-Path -LiteralPath $entryPointLog -PathType Leaf) -or
    (Get-Content -LiteralPath $entryPointLog -Raw) -notmatch "Verification completed successfully") {
    throw "The native EXE read-only entry point failed on a sandbox path containing spaces."
}

[pscustomobject]@{
    passed = $true
    installer = $installer
    installerSha256 = Get-Sha256 -Path $installer
    successfulInstallVerified = $true
    persistentBackupVerified = $true
    legacyRemovalVerified = $true
    installedInventoryVerifiedByEngine = $true
    injectedFailureObserved = $true
    completeRollbackVerified = $true
    completeRollbackTreeHashVerified = $true
    nativeEntrypointWithSpacesVerified = $true
    unmanagedFilePreserved = $true
    bothSandboxExecutablesUnchanged = $true
    realGameExecutableUnchanged = $true
    gameLaunched = $false
    realGameFilesInstalled = $false
    sandboxRoot = $testRoot
}
