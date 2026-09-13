[CmdletBinding()]
param(
    [string]$GameRoot,

    [string]$InstallerPath,

    [string]$UninstallerPath,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

function Protect-NativeArgument {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($Value.Contains('"')) {
        throw "A native command argument cannot contain a quotation mark: $Value"
    }
    return '"' + $Value + '"'
}

function Assert-X64PortableExecutable {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $stream = [IO.File]::OpenRead([IO.Path]::GetFullPath($Path))
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 256 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw "Executable is not a valid Windows PE file: $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0x40 -or $peOffset -gt $stream.Length - 6) {
            throw "Executable has an invalid PE header offset: $Path"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Executable PE signature is invalid: $Path"
        }
        $machine = $reader.ReadUInt16()
        if ($machine -ne 0x8664) {
            throw ("Executable must be x64 (PE machine 0x8664); found 0x{0:X4}." -f $machine)
        }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$mod = Get-ModData -ProjectRoot $projectRoot
$resolvedGameRoot = Resolve-FarFarWestGameRoot -GameRoot $GameRoot -Lock $lock

& (Join-Path $PSScriptRoot "Test-Project.ps1") | Out-Null

if (-not $InstallerPath) {
    $expectedPattern = "*-FFWFrostburn8-v$($mod.version)-Setup.exe"
    $installers = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "dist") -File -Filter $expectedPattern |
        Where-Object { $_.Directory.Name -ne "release-v$($mod.version)" } |
        Sort-Object -Property LastWriteTime -Descending)
    if ($installers.Count -eq 0) {
        throw "No matching Setup.exe was found under dist/. Build it first with tools\Build-InstallerExe.ps1."
    }
    $InstallerPath = $installers[0].FullName
}
$sourceInstaller = [IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $sourceInstaller -PathType Leaf)) {
    throw "Installer executable was not found: $sourceInstaller"
}

if (-not $UninstallerPath) {
    $expectedUninstallerPattern = "*-FFWFrostburn8-v$($mod.version)-Uninstall.exe"
    $uninstallers = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "dist") -File -Filter $expectedUninstallerPattern |
        Where-Object { $_.Directory.Name -ne "release-v$($mod.version)" } |
        Sort-Object -Property LastWriteTime -Descending)
    if ($uninstallers.Count -eq 0) {
        throw "No matching Uninstall.exe was found under dist/. Build it first with tools\Build-UninstallerExe.ps1."
    }
    $UninstallerPath = $uninstallers[0].FullName
}
$sourceUninstaller = [IO.Path]::GetFullPath($UninstallerPath)
if (-not (Test-Path -LiteralPath $sourceUninstaller -PathType Leaf)) {
    throw "Uninstaller executable was not found: $sourceUninstaller"
}

Assert-X64PortableExecutable -Path $sourceInstaller
Assert-X64PortableExecutable -Path $sourceUninstaller
$installerVersionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($sourceInstaller)
$uninstallerVersionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($sourceUninstaller)
$expectedFileVersion = "$($mod.version).0"
if ($installerVersionInfo.FileVersion -ne $expectedFileVersion -or
    $installerVersionInfo.ProductVersion -ne $expectedFileVersion) {
    throw "Installer version mismatch. Expected $expectedFileVersion, found FileVersion=$($installerVersionInfo.FileVersion), ProductVersion=$($installerVersionInfo.ProductVersion)."
}
if ($uninstallerVersionInfo.FileVersion -ne $expectedFileVersion -or
    $uninstallerVersionInfo.ProductVersion -ne $expectedFileVersion) {
    throw "Uninstaller version mismatch. Expected $expectedFileVersion, found FileVersion=$($uninstallerVersionInfo.FileVersion), ProductVersion=$($uninstallerVersionInfo.ProductVersion)."
}

$workRoot = Reset-SafeDirectory `
    -ProjectRoot $projectRoot `
    -Path (Join-Path $projectRoot "work\download-bundle")
$verificationLog = Join-Path $workRoot "installer-verification.log"
$verifyArguments = @(
    "--verify-only",
    "--game-root",
    (Protect-NativeArgument -Value $resolvedGameRoot),
    "--log",
    (Protect-NativeArgument -Value $verificationLog)
)
$verifyProcess = Start-Process `
    -FilePath $sourceInstaller `
    -ArgumentList $verifyArguments `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($verifyProcess.ExitCode -ne 0 -or
    -not (Test-Path -LiteralPath $verificationLog -PathType Leaf) -or
    (Get-Content -LiteralPath $verificationLog -Raw) -notmatch "Verification completed successfully") {
    throw "The installer failed read-only verification and will not be packaged."
}
$uninstallerVerificationLog = Join-Path $workRoot "uninstaller-verification.log"
$uninstallerVerifyArguments = @(
    "--verify-only",
    "--game-root",
    (Protect-NativeArgument -Value $resolvedGameRoot),
    "--log",
    (Protect-NativeArgument -Value $uninstallerVerificationLog)
)
$uninstallerVerifyProcess = Start-Process `
    -FilePath $sourceUninstaller `
    -ArgumentList $uninstallerVerifyArguments `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($uninstallerVerifyProcess.ExitCode -ne 0 -or
    -not (Test-Path -LiteralPath $uninstallerVerificationLog -PathType Leaf) -or
    (Get-Content -LiteralPath $uninstallerVerificationLog -Raw) -notmatch "Uninstaller verification completed successfully") {
    throw "The uninstaller failed read-only verification and will not be packaged."
}

if (-not $OutputDirectory) {
    $outputRoot = Reset-SafeDirectory `
        -ProjectRoot $projectRoot `
        -Path (Join-Path $projectRoot "dist\release-v$($mod.version)")
} else {
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}

$friendlyInstallerName = "FFWFrostburn8-Setup.exe"
$friendlyUninstallerName = "FFWFrostburn8-Uninstall.exe"
$directInstaller = Join-Path $outputRoot $friendlyInstallerName
$directUninstaller = Join-Path $outputRoot $friendlyUninstallerName
Copy-Item -LiteralPath $sourceInstaller -Destination $directInstaller -Force
Copy-Item -LiteralPath $sourceUninstaller -Destination $directUninstaller -Force
$installerSha256 = Get-Sha256 -Path $directInstaller
$uninstallerSha256 = Get-Sha256 -Path $directUninstaller
if ($installerSha256 -ne (Get-Sha256 -Path $sourceInstaller)) {
    throw "The friendly release copy does not match the verified installer."
}
if ($uninstallerSha256 -ne (Get-Sha256 -Path $sourceUninstaller)) {
    throw "The friendly release copy does not match the verified uninstaller."
}
$directChecksum = $directInstaller + ".sha256.txt"
$directUninstallerChecksum = $directUninstaller + ".sha256.txt"
[IO.File]::WriteAllText(
    $directChecksum,
    $installerSha256 + " *" + $friendlyInstallerName + [Environment]::NewLine,
    [Text.Encoding]::ASCII
)
[IO.File]::WriteAllText(
    $directUninstallerChecksum,
    $uninstallerSha256 + " *" + $friendlyUninstallerName + [Environment]::NewLine,
    [Text.Encoding]::ASCII
)

$stageRoot = Join-Path $workRoot "bundle-root"
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
Copy-Item -LiteralPath $directInstaller -Destination (Join-Path $stageRoot $friendlyInstallerName)
Copy-Item -LiteralPath $directUninstaller -Destination (Join-Path $stageRoot $friendlyUninstallerName)
Copy-Item -LiteralPath (Join-Path $projectRoot "LICENSE") -Destination (Join-Path $stageRoot "LICENSE.txt")
Copy-Item `
    -LiteralPath (Join-Path $projectRoot "THIRD_PARTY_NOTICES.md") `
    -Destination (Join-Path $stageRoot "THIRD-PARTY-NOTICES.txt")

$readmeText = @"
FFWFrostburn8 v$($mod.version) - Far Far West 8 Players
=======================================================

Danh cho / For: Far Far West $($lock.target.productVersion), Windows x64
Che do / Mode: HOST-ONLY EXPERIMENTAL - VANILLA CLIENTS UNVERIFIED

CAI DAT / INSTALL
1. Dong Far Far West hoan toan. / Close Far Far West completely.
2. Chay $friendlyInstallerName ngay trong thu muc nay.
   Run $friendlyInstallerName from this folder.
3. Kiem tra duong dan game, bam "Install / Cai" va cho thong bao thanh cong.
   Check the game path, click "Install / Cai", and wait for success.
4. Mo game binh thuong, tao phong va tich "Allow mods".
   Start the game normally, create a room, and tick "Allow mods".
5. Chi host cai ban nay; may khach de game nguyen ban, khong cai UE4SS/mod.
   Install this build on the host only; guests must remain vanilla.
6. Khi mot minh: kiem tra 7 nut Invite. Khi co 5 nguoi: kiem tra du 5 ten va
   con 3 nut Invite. Neu khong tick "Allow mods", giao dien phai giu 4 dong.
   Alone: verify 7 Invite buttons. With 5 players: verify all 5 names and 3
   Invite buttons. Without "Allow mods", the UI must keep its normal 4 rows.

GO CAI DAT / UNINSTALL
1. Dong Far Far West hoan toan. / Close Far Far West completely.
2. Chay $friendlyUninstallerName va kiem tra dung thu muc game.
   Run $friendlyUninstallerName and verify the selected game folder.
3. De trong o Advanced, bam "Uninstall / Go" de chi go FFWFrostburn8; UE4SS va
   cac mod khac duoc giu nguyen.
   Leave Advanced unchecked and click "Uninstall / Go" to remove only
   FFWFrostburn8; UE4SS and other mods are preserved.
4. Advanced chi dung khi co y khoi phuc toan bo snapshot sach truoc khi cai.
   Use Advanced only when intentionally restoring the complete clean snapshot.
   Thay doi UE4SS/mod sau snapshot co the bi hoan tac; backup thieu/hong se bi tu choi.
   Later UE4SS/mod changes may be reverted; a missing/damaged snapshot is refused.

Khong can PowerShell. Bo cai khong tai them mod cua nguoi khac va khong tu mo,
dong hay khoi dong lai game. Neu game dang chay, bo cai se tu choi ghi file.
No PowerShell is required. The installer downloads no other multiplayer mod and
never starts, closes, or restarts the game. It refuses to write while the game
is running.

LUU Y / IMPORTANT
- Bo cai thay the dwmapi.dll va toan bo thu muc ue4ss hien tai.
- Existing UE4SS files are backed up but are not kept active automatically.
- Backup: %LOCALAPPDATA%\FFWFrostburn8\Backups
- Uninstall safety: %LOCALAPPDATA%\FFWFrostburn8\UninstallSafety
- Log:    %LOCALAPPDATA%\FFWFrostburn8\Logs
- Build nay chua co chu ky so; hay doi chieu SHA256SUMS.txt neu Windows hien
  canh bao unknown publisher. Khong tat Windows Defender.
- A successful install does not by itself prove eight real network clients.
  Test a fifth vanilla player via session code and Steam Invite, then all eight,
  map travel, an objective, reconnect, and manual kick before claiming support.
- Day la ban thu nghiem. Khong coi 7 nut Invite la bang chung client vanilla vao duoc.
  This is experimental. Seven Invite buttons do not prove vanilla clients can join.

SHA-256 cua ca Setup va Uninstall nam trong SHA256SUMS.txt.
SHA-256 values for both Setup and Uninstall are recorded in SHA256SUMS.txt.
"@
[IO.File]::WriteAllText(
    (Join-Path $stageRoot "README-VI.txt"),
    $readmeText + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
    (Join-Path $stageRoot "SHA256SUMS.txt"),
    $installerSha256 + " *" + $friendlyInstallerName + [Environment]::NewLine +
    $uninstallerSha256 + " *" + $friendlyUninstallerName + [Environment]::NewLine,
    [Text.Encoding]::ASCII
)

$bundleName = "FFWFrostburn8-Windows-x64.zip"
$bundlePath = Join-Path $outputRoot $bundleName
if (Test-Path -LiteralPath $bundlePath -PathType Container) {
    throw "Bundle output path is a directory: $bundlePath"
}
if (Test-Path -LiteralPath $bundlePath -PathType Leaf) {
    [IO.File]::Delete([IO.Path]::GetFullPath($bundlePath))
}
$stageFiles = @(Get-ChildItem -LiteralPath $stageRoot -File | Sort-Object -Property Name)
Compress-Archive `
    -LiteralPath $stageFiles.FullName `
    -DestinationPath $bundlePath `
    -CompressionLevel Optimal

$roundTripRoot = Join-Path $workRoot "round-trip"
New-Item -ItemType Directory -Path $roundTripRoot -Force | Out-Null
Expand-ZipSafe -Archive $bundlePath -Destination $roundTripRoot -SafetyRoot $workRoot

$expectedNames = @($stageFiles.Name | Sort-Object)
$actualFiles = @(Get-ChildItem -LiteralPath $roundTripRoot -Recurse -File | Sort-Object -Property Name)
$actualNames = @($actualFiles | ForEach-Object {
    Get-RelativePath -Root $roundTripRoot -Path $_.FullName
})
if (($actualNames -join "|") -ne ($expectedNames -join "|")) {
    throw "The download ZIP does not contain the expected flat root layout. Expected: $($expectedNames -join ', '); actual: $($actualNames -join ', ')."
}
foreach ($stageFile in $stageFiles) {
    $expandedFile = Join-Path $roundTripRoot $stageFile.Name
    if ((Get-Sha256 -Path $stageFile.FullName) -ne (Get-Sha256 -Path $expandedFile)) {
        throw "Download ZIP round-trip hash mismatch: $($stageFile.Name)"
    }
}
if (Get-ChildItem -LiteralPath $roundTripRoot -Directory) {
    throw "The download ZIP must not contain a nested top-level directory."
}

$bundleSha256 = Get-Sha256 -Path $bundlePath
$bundleChecksum = $bundlePath + ".sha256.txt"
[IO.File]::WriteAllText(
    $bundleChecksum,
    $bundleSha256 + " *" + $bundleName + [Environment]::NewLine,
    [Text.Encoding]::ASCII
)

[pscustomobject]@{
    releaseDirectory = [IO.Path]::GetFullPath($outputRoot)
    directInstaller = [IO.Path]::GetFullPath($directInstaller)
    directInstallerSha256 = $installerSha256
    directInstallerChecksum = [IO.Path]::GetFullPath($directChecksum)
    directUninstaller = [IO.Path]::GetFullPath($directUninstaller)
    directUninstallerSha256 = $uninstallerSha256
    directUninstallerChecksum = [IO.Path]::GetFullPath($directUninstallerChecksum)
    downloadBundle = [IO.Path]::GetFullPath($bundlePath)
    downloadBundleSha256 = $bundleSha256
    downloadBundleChecksum = [IO.Path]::GetFullPath($bundleChecksum)
    rootFiles = @($expectedNames)
    flatRootLayoutVerified = $true
    roundTripHashesVerified = $true
    installerReadOnlyVerificationPassed = $true
    uninstallerReadOnlyVerificationPassed = $true
    gameWasLaunched = $false
    gameFilesWereChanged = $false
    installerAuthenticodeStatus = [string](Get-AuthenticodeSignature -LiteralPath $directInstaller).Status
    uninstallerAuthenticodeStatus = [string](Get-AuthenticodeSignature -LiteralPath $directUninstaller).Status
    authenticodeStatus = [string](Get-AuthenticodeSignature -LiteralPath $directInstaller).Status
}
