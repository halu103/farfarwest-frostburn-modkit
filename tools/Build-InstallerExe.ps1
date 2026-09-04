[CmdletBinding()]
param(
    [string]$GameRoot,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\Common.ps1")

function ConvertTo-CSharpStringLiteral {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return "null"
    }

    $escaped = $Value.Replace('\', '\\')
    $escaped = $escaped.Replace('"', '\"')
    $escaped = $escaped.Replace("`r", '\r')
    $escaped = $escaped.Replace("`n", '\n')
    $escaped = $escaped.Replace("`t", '\t')
    return '"' + $escaped + '"'
}

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

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "The GUI installer can only be built on Windows."
}

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$mod = Get-ModData -ProjectRoot $projectRoot
$resolvedGameRoot = Resolve-FarFarWestGameRoot -GameRoot $GameRoot -Lock $lock

& (Join-Path $PSScriptRoot "Test-Project.ps1") | Out-Null

$workRoot = Reset-SafeDirectory `
    -ProjectRoot $projectRoot `
    -Path (Join-Path $projectRoot "work\installer")
$releaseRoot = Join-Path $workRoot "release"
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

$release = & (Join-Path $PSScriptRoot "Build-Release.ps1") `
    -GameRoot $resolvedGameRoot `
    -OutputDirectory $releaseRoot
if (-not $release -or -not $release.path) {
    throw "Build-Release.ps1 did not return a release archive."
}

$signatureFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $projectRoot "config\ue4ss\UE4SS_Signatures") -File -Filter "*.lua"
    Get-ChildItem -LiteralPath (Join-Path $projectRoot "config\static-signatures") -File -Filter "*.lua"
) | Sort-Object -Property Name

$aobNames = [Collections.Generic.List[string]]::new()
$aobPatterns = [Collections.Generic.List[string]]::new()
foreach ($signatureFile in $signatureFiles) {
    $aobNames.Add($signatureFile.BaseName)
    $aobPatterns.Add((Read-LuaAobPattern -Path $signatureFile.FullName))
}
if ($aobNames.Count -eq 0 -or $aobNames.Count -ne $aobPatterns.Count) {
    throw "No compatibility signatures were available for the installer."
}

$assemblyVersion = "$($mod.version).0"
$buildInfoPath = Join-Path $workRoot "BuildInfo.cs"
$buildInfoSource = @"
using System.Reflection;

[assembly: AssemblyTitle("FFWFrostburn8 Installer")]
[assembly: AssemblyDescription("Offline installer for the Far Far West Frostburn 8-player mod")]
[assembly: AssemblyCompany("FFWFrostburn8")]
[assembly: AssemblyProduct("FFWFrostburn8 Installer")]
[assembly: AssemblyCopyright("Copyright (c) FFWFrostburn8 contributors")]
[assembly: AssemblyVersion("$assemblyVersion")]
[assembly: AssemblyFileVersion("$assemblyVersion")]

namespace FFWFrostburn8Installer
{
    internal static class BuildInfo
    {
        internal const string ModVersion = $(ConvertTo-CSharpStringLiteral ([string]$mod.version));
        internal const string GameVersion = $(ConvertTo-CSharpStringLiteral ([string]$lock.target.productVersion));
        internal const string GameExecutableSha256 = $(ConvertTo-CSharpStringLiteral ([string]$lock.target.executableSha256));
        internal const string Ue4ssCommit = $(ConvertTo-CSharpStringLiteral ([string]$lock.ue4ss.commit));
        internal const string Ue4ssAssetSha256 = $(ConvertTo-CSharpStringLiteral ([string]$lock.ue4ss.assetSha256));
        internal const string SourceTreeSha256 = $(ConvertTo-CSharpStringLiteral ([string]$release.sourceTreeSha256));
        internal const string ReleaseFileName = $(ConvertTo-CSharpStringLiteral ([IO.Path]::GetFileName([string]$release.path)));
        internal const string ReleaseSha256 = $(ConvertTo-CSharpStringLiteral ([string]$release.sha256));
        internal const string PayloadResourceName = "FFWFrostburn8.Payload.zip";
        internal const string GameExecutableRelativePath = $(ConvertTo-CSharpStringLiteral ([string]$lock.target.executableRelativePath.Replace('/', '\')));

        internal static readonly string[] AobNames = new string[]
        {
            $(($aobNames | ForEach-Object { ConvertTo-CSharpStringLiteral $_ }) -join ",`r`n            ")
        };

        internal static readonly string[] AobPatterns = new string[]
        {
            $(($aobPatterns | ForEach-Object { ConvertTo-CSharpStringLiteral $_ }) -join ",`r`n            ")
        };
    }
}
"@
[IO.File]::WriteAllText(
    $buildInfoPath,
    $buildInfoSource,
    [Text.UTF8Encoding]::new($false)
)

$compilerCandidates = @(
    (Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) "csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $compiler) {
    throw "The .NET Framework C# compiler was not found. Install or enable .NET Framework 4.8."
}

if (-not $OutputDirectory) {
    $outputRoot = Join-Path $projectRoot "dist"
} else {
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$gameVersion = ([string]$lock.target.productVersion -replace "\s*-\s*", "-" -replace "\s+", "")
$outputName = "FarFarWest-Frostburn-$gameVersion-$($mod.id)-v$($mod.version)-Setup.exe"
$outputExe = Join-Path $outputRoot $outputName
if (Test-Path -LiteralPath $outputExe -PathType Container) {
    throw "The installer output path is a directory: $outputExe"
}
if (Test-Path -LiteralPath $outputExe -PathType Leaf) {
    [IO.File]::Delete([IO.Path]::GetFullPath($outputExe))
}

$frameworkDirectory = Split-Path -Parent $compiler
$references = @(
    "System.dll",
    "System.Core.dll",
    "System.Drawing.dll",
    "System.Windows.Forms.dll",
    "System.IO.Compression.dll",
    "System.IO.Compression.FileSystem.dll",
    "System.Web.Extensions.dll"
)
foreach ($reference in $references) {
    $referencePath = Join-Path $frameworkDirectory $reference
    if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) {
        throw "Required .NET Framework assembly not found: $referencePath"
    }
}

$compilerArguments = @(
    "/nologo",
    "/target:winexe",
    "/platform:x64",
    "/optimize+",
    "/langversion:5",
    "/out:$outputExe",
    "/win32manifest:$(Join-Path $projectRoot 'installer\app.manifest')",
    "/resource:$($release.path),FFWFrostburn8.Payload.zip,private",
    "/resource:$(Join-Path $projectRoot 'LICENSE'),FFWFrostburn8.LICENSE.txt,private",
    "/resource:$(Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md'),FFWFrostburn8.THIRD_PARTY_NOTICES.txt,private"
)
foreach ($reference in $references) {
    $compilerArguments += "/reference:$(Join-Path $frameworkDirectory $reference)"
}
$compilerArguments += (Join-Path $projectRoot "installer\Installer.cs")
$compilerArguments += $buildInfoPath

& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputExe -PathType Leaf)) {
    throw "The C# compiler failed to create the installer (exit code $LASTEXITCODE)."
}

$verificationLog = Join-Path $workRoot "installer-verification.log"
$nativeArguments = @(
    "--verify-only",
    "--game-root",
    (Protect-NativeArgument -Value $resolvedGameRoot),
    "--log",
    (Protect-NativeArgument -Value $verificationLog)
)
$verificationProcess = Start-Process `
    -FilePath $outputExe `
    -ArgumentList $nativeArguments `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($verificationProcess.ExitCode -ne 0) {
    $details = if (Test-Path -LiteralPath $verificationLog -PathType Leaf) {
        Get-Content -LiteralPath $verificationLog -Raw
    } else {
        "No verification log was created."
    }
    throw "The built installer failed its read-only verification (exit code $($verificationProcess.ExitCode)).`n$details"
}

$signatureStatus = (Get-AuthenticodeSignature -LiteralPath $outputExe).Status
$installerSha256 = Get-Sha256 -Path $outputExe
$checksumPath = $outputExe + ".sha256.txt"
[IO.File]::WriteAllText(
    $checksumPath,
    $installerSha256 + " *" + [IO.Path]::GetFileName($outputExe) + [Environment]::NewLine,
    [Text.Encoding]::ASCII
)
[pscustomobject]@{
    path = [IO.Path]::GetFullPath($outputExe)
    sha256 = $installerSha256
    checksumPath = [IO.Path]::GetFullPath($checksumPath)
    size = (Get-Item -LiteralPath $outputExe).Length
    modVersion = [string]$mod.version
    targetGameVersion = [string]$lock.target.productVersion
    embeddedReleaseSha256 = [string]$release.sha256
    sourceTreeSha256 = [string]$release.sourceTreeSha256
    filesVerifiedInRelease = [int]$release.filesVerified
    readOnlyVerificationPassed = $true
    authenticodeStatus = [string]$signatureStatus
    gameWasLaunched = $false
    gameFilesWereChanged = $false
}
