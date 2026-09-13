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
    throw "The GUI uninstaller can only be built on Windows."
}

$projectRoot = Get-ModkitRoot
$lock = Get-LockData -ProjectRoot $projectRoot
$mod = Get-ModData -ProjectRoot $projectRoot
$resolvedGameRoot = Resolve-FarFarWestGameRoot -GameRoot $GameRoot -Lock $lock

& (Join-Path $PSScriptRoot "Test-Project.ps1") | Out-Null

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

$workRoot = Reset-SafeDirectory `
    -ProjectRoot $projectRoot `
    -Path (Join-Path $projectRoot "work\uninstaller")
$assemblyVersion = "$($mod.version).0"
$sourceTreeSha256 = Get-DirectoryTreeSha256 -Path (Join-Path $projectRoot "src\Mods\$($mod.id)")
$buildInfoPath = Join-Path $workRoot "BuildInfo.cs"
$buildInfoSource = @"
using System.Reflection;

[assembly: AssemblyTitle("FFWFrostburn8 Uninstaller")]
[assembly: AssemblyDescription("Safe restore-based uninstaller for the Far Far West Frostburn 8-player mod")]
[assembly: AssemblyCompany("FFWFrostburn8")]
[assembly: AssemblyProduct("FFWFrostburn8 Uninstaller")]
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
        internal const string SourceTreeSha256 = $(ConvertTo-CSharpStringLiteral $sourceTreeSha256);
        internal const string ReleaseFileName = "";
        internal const string ReleaseSha256 = "";
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
[IO.File]::WriteAllText($buildInfoPath, $buildInfoSource, [Text.UTF8Encoding]::new($false))

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

$outputRoot = if ($OutputDirectory) {
    [IO.Path]::GetFullPath($OutputDirectory)
} else {
    Join-Path $projectRoot "dist"
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$gameVersion = ([string]$lock.target.productVersion -replace "\s*-\s*", "-" -replace "\s+", "")
$outputName = "FarFarWest-Frostburn-$gameVersion-$($mod.id)-v$($mod.version)-Uninstall.exe"
$outputExe = Join-Path $outputRoot $outputName
if (Test-Path -LiteralPath $outputExe -PathType Container) {
    throw "The uninstaller output path is a directory: $outputExe"
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
    "/main:FFWFrostburn8Installer.UninstallerProgram",
    "/out:$outputExe",
    "/win32manifest:$(Join-Path $projectRoot 'installer\app.manifest')"
)
foreach ($reference in $references) {
    $compilerArguments += "/reference:$(Join-Path $frameworkDirectory $reference)"
}
$compilerArguments += (Join-Path $projectRoot "installer\Installer.cs")
$compilerArguments += (Join-Path $projectRoot "installer\Uninstaller.cs")
$compilerArguments += $buildInfoPath

& $compiler @compilerArguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputExe -PathType Leaf)) {
    throw "The C# compiler failed to create the uninstaller (exit code $LASTEXITCODE)."
}

$verificationLog = Join-Path $workRoot "uninstaller-verification.log"
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
    throw "The built uninstaller failed its read-only verification (exit code $($verificationProcess.ExitCode)).`n$details"
}

$signatureStatus = (Get-AuthenticodeSignature -LiteralPath $outputExe).Status
$uninstallerSha256 = Get-Sha256 -Path $outputExe
$checksumPath = $outputExe + ".sha256.txt"
[IO.File]::WriteAllText(
    $checksumPath,
    $uninstallerSha256 + " *" + [IO.Path]::GetFileName($outputExe) + [Environment]::NewLine,
    [Text.Encoding]::ASCII
)

[pscustomobject]@{
    path = [IO.Path]::GetFullPath($outputExe)
    sha256 = $uninstallerSha256
    checksumPath = [IO.Path]::GetFullPath($checksumPath)
    size = (Get-Item -LiteralPath $outputExe).Length
    modVersion = [string]$mod.version
    targetGameVersion = [string]$lock.target.productVersion
    sourceTreeSha256 = $sourceTreeSha256
    readOnlyVerificationPassed = $true
    authenticodeStatus = [string]$signatureStatus
    gameWasLaunched = $false
    gameFilesWereChanged = $false
}
