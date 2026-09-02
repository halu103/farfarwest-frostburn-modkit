Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ModkitRoot {
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
}

function Get-LockData {
    param(
        [string]$ProjectRoot = (Get-ModkitRoot)
    )

    $path = Join-Path $ProjectRoot "config\upstream.lock.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Lock file not found: $path"
    }

    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-ModData {
    param(
        [string]$ProjectRoot = (Get-ModkitRoot)
    )

    $path = Join-Path $ProjectRoot "src\mod.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Mod metadata not found: $path"
    }

    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-Sha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Expected
    )

    $actual = Get-Sha256 -Path $Path
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw "SHA-256 mismatch for '$Path'. Expected $Expected, got $actual."
    }

    return $actual
}

function Get-DirectoryTreeSha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $root = [IO.Path]::GetFullPath($Path).TrimEnd("\")
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Directory not found: $root"
    }

    $records = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
        $relative = Get-RelativePath -Root $root -Path $_.FullName
        $normalized = $relative.Replace("\", "/")
        [pscustomobject]@{
            Relative = $normalized
            Record = "$normalized`0$(Get-Sha256 -Path $_.FullName)"
        }
    } | Sort-Object -Property Relative | Select-Object -ExpandProperty Record)

    if ($records.Count -eq 0) {
        throw "Cannot hash an empty directory: $root"
    }

    $payload = [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $records))
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($hasher.ComputeHash($payload))).Replace("-", "")
    } finally {
        $hasher.Dispose()
    }
}

function Assert-PathInside {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\")
    $fullPath = [IO.Path]::GetFullPath($Path)
    $prefix = $fullRoot + "\"

    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path outside root '$fullRoot': $fullPath"
    }

    return $fullPath
}

function Reset-SafeDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $safePath = Assert-PathInside -Root $ProjectRoot -Path $Path
    if (Test-Path -LiteralPath $safePath) {
        Remove-Item -LiteralPath $safePath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $safePath -Force | Out-Null
    return $safePath
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText(
        [IO.Path]::GetFullPath($Path),
        $json + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\")
    $fullPath = Assert-PathInside -Root $fullRoot -Path $Path
    return $fullPath.Substring($fullRoot.Length + 1)
}

function Test-ArchiveEntrySafe {
    param(
        [Parameter(Mandatory)]
        [string]$Entry
    )

    $normalized = $Entry.Replace("\", "/")
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $true
    }

    if ($normalized.StartsWith("/") -or $normalized -match "^[A-Za-z]:") {
        return $false
    }

    $parts = $normalized.Split("/", [StringSplitOptions]::RemoveEmptyEntries)
    return -not ($parts -contains "..")
}

function Expand-ZipSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Archive,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$SafetyRoot
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $destinationPath = Assert-PathInside -Root $SafetyRoot -Path $Destination
    if (Test-Path -LiteralPath $destinationPath) {
        $existing = Get-ChildItem -LiteralPath $destinationPath -Force
        if ($existing) {
            throw "ZIP destination must be empty: $destinationPath"
        }
    } else {
        New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    }

    $zip = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
    try {
        foreach ($entry in $zip.Entries) {
            if (-not (Test-ArchiveEntrySafe -Entry $entry.FullName)) {
                throw "Unsafe ZIP entry: $($entry.FullName)"
            }

            $relative = $entry.FullName.Replace("/", "\")
            if ([string]::IsNullOrWhiteSpace($relative)) {
                continue
            }

            $target = Assert-PathInside -Root $destinationPath -Path (Join-Path $destinationPath $relative)
            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                continue
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            $inputStream = $entry.Open()
            $outputStream = [IO.File]::Open($target, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $inputStream.CopyTo($outputStream)
            } finally {
                $outputStream.Dispose()
                $inputStream.Dispose()
            }
        }
    } finally {
        $zip.Dispose()
    }
}

function Find-GitHubReleaseAsset {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string[]]$Tags,

        [Parameter(Mandatory)]
        [string]$AssetName
    )

    $headers = @{
        "User-Agent" = "FarFarWest-Frostburn-Modkit"
        "Accept" = "application/vnd.github+json"
    }

    foreach ($tag in $Tags) {
        try {
            $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases/tags/$tag"
        } catch {
            continue
        }

        $asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
        if ($asset) {
            return [pscustomobject]@{
                Release = $release
                Asset = $asset
            }
        }
    }

    throw "Release asset '$AssetName' was not found in tags: $($Tags -join ', ')"
}

function Download-VerifiedReleaseAsset {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string[]]$Tags,

        [Parameter(Mandatory)]
        [string]$AssetName,

        [Parameter(Mandatory)]
        [string]$ExpectedSha256,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    $found = Find-GitHubReleaseAsset -Repository $Repository -Tags $Tags -AssetName $AssetName
    $headers = @{
        "User-Agent" = "FarFarWest-Frostburn-Modkit"
        "Accept" = "application/vnd.github+json"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Invoke-WebRequest -Headers $headers -Uri $found.Asset.browser_download_url -OutFile $Destination

    $actual = Assert-Sha256 -Path $Destination -Expected $ExpectedSha256
    if ($found.Asset.digest) {
        $apiDigest = ($found.Asset.digest -replace "^sha256:", "").ToUpperInvariant()
        if ($actual -ne $apiDigest) {
            throw "Downloaded hash does not match the GitHub asset digest for $AssetName."
        }
    }

    return [pscustomobject]@{
        Path = [IO.Path]::GetFullPath($Destination)
        Sha256 = $actual
        Asset = $found.Asset
        Release = $found.Release
    }
}

function Get-GameExecutable {
    param(
        [Parameter(Mandatory)]
        [string]$GameRoot,

        [Parameter(Mandatory)]
        [object]$Lock
    )

    $root = [IO.Path]::GetFullPath($GameRoot)
    $relative = $Lock.target.executableRelativePath.Replace("/", "\")
    $exe = Assert-PathInside -Root $root -Path (Join-Path $root $relative)
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw "Far Far West executable not found: $exe"
    }

    return $exe
}

function Resolve-FarFarWestGameRoot {
    param(
        [string]$GameRoot,

        [object]$Lock = (Get-LockData)
    )

    if ($GameRoot) {
        $explicitRoot = [IO.Path]::GetFullPath($GameRoot).TrimEnd("\")
        Get-GameExecutable -GameRoot $explicitRoot -Lock $Lock | Out-Null
        return $explicitRoot
    }

    $steamRoots = [Collections.Generic.List[string]]::new()
    foreach ($registryPath in @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $properties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
            foreach ($propertyName in @("SteamPath", "InstallPath")) {
                $property = $properties.PSObject.Properties[$propertyName]
                $value = if ($property) { $property.Value } else { $null }
                if ($value) {
                    $steamRoots.Add([IO.Path]::GetFullPath([string]$value))
                }
            }
        } catch {
            # Steam may not have this registry view; continue with the other sources.
        }
    }
    foreach ($fallback in @(
        "C:\Program Files (x86)\Steam",
        "C:\Program Files\Steam"
    )) {
        if (Test-Path -LiteralPath $fallback -PathType Container) {
            $steamRoots.Add($fallback)
        }
    }

    $libraries = [Collections.Generic.List[string]]::new()
    foreach ($steamRoot in @($steamRoots | Select-Object -Unique)) {
        $libraries.Add($steamRoot)
        $vdfPath = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (-not (Test-Path -LiteralPath $vdfPath -PathType Leaf)) {
            continue
        }

        $vdf = Get-Content -LiteralPath $vdfPath -Raw
        $matches = [regex]::Matches(
            $vdf,
            '(?m)^\s*(?:"path"|"\d+")\s+"([^"]+)"\s*$'
        )
        foreach ($match in $matches) {
            $library = $match.Groups[1].Value.Replace('\\', '\')
            if (Test-Path -LiteralPath $library -PathType Container) {
                $libraries.Add([IO.Path]::GetFullPath($library))
            }
        }
    }

    $candidates = [Collections.Generic.List[string]]::new()
    foreach ($library in @($libraries | Select-Object -Unique)) {
        $manifestPath = Join-Path $library "steamapps\appmanifest_3124540.acf"
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            continue
        }

        $manifest = Get-Content -LiteralPath $manifestPath -Raw
        $installMatch = [regex]::Match($manifest, '"installdir"\s+"([^"]+)"')
        if (-not $installMatch.Success) {
            continue
        }

        $candidate = Join-Path $library ("steamapps\common\" + $installMatch.Groups[1].Value)
        try {
            Get-GameExecutable -GameRoot $candidate -Lock $Lock | Out-Null
            $candidates.Add([IO.Path]::GetFullPath($candidate).TrimEnd("\"))
        } catch {
            # Ignore stale Steam library entries.
        }
    }

    $resolved = @($candidates | Select-Object -Unique)
    if ($resolved.Count -eq 1) {
        return $resolved[0]
    }
    if ($resolved.Count -gt 1) {
        throw "Multiple Far Far West installations were found. Pass -GameRoot explicitly: $($resolved -join ', ')"
    }

    throw "Far Far West was not found in the registered Steam libraries. Pass -GameRoot explicitly."
}

function Read-LuaAobPattern {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $text = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($text, 'return\s+"([0-9A-Fa-f? ]+)"')
    if (-not $match.Success) {
        throw "No AOB return string found in: $Path"
    }

    return $match.Groups[1].Value
}

function Initialize-StaticAobScanner {
    if ("FarFarWestStaticAobScanner" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;

public static class FarFarWestStaticAobScanner
{
    public static long[] Find(byte[] data, string pattern, int limit)
    {
        string[] parts = pattern.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        byte[] values = new byte[parts.Length];
        bool[] wildcards = new bool[parts.Length];
        int anchor = -1;

        for (int i = 0; i < parts.Length; i++)
        {
            if (parts[i] == "?" || parts[i] == "??")
            {
                wildcards[i] = true;
            }
            else
            {
                values[i] = Convert.ToByte(parts[i], 16);
                if (anchor < 0)
                {
                    anchor = i;
                }
            }
        }

        var hits = new List<long>();
        int last = data.Length - parts.Length;
        for (int i = 0; i <= last; i++)
        {
            if (anchor >= 0 && data[i + anchor] != values[anchor])
            {
                continue;
            }

            bool matched = true;
            for (int j = 0; j < parts.Length; j++)
            {
                if (!wildcards[j] && data[i + j] != values[j])
                {
                    matched = false;
                    break;
                }
            }

            if (matched)
            {
                hits.Add(i);
                if (hits.Count >= limit)
                {
                    break;
                }
            }
        }

        return hits.ToArray();
    }
}
'@
}

function Find-AobMatches {
    param(
        [Parameter(Mandatory)]
        [byte[]]$Data,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [int]$Limit = 20
    )

    Initialize-StaticAobScanner
    return [FarFarWestStaticAobScanner]::Find($Data, $Pattern, $Limit)
}

function Assert-GameNotRunning {
    $process = Get-Process -Name "FarFarWest-Win64-Shipping" -ErrorAction SilentlyContinue
    if ($process) {
        $ids = ($process.Id -join ", ")
        throw "Far Far West is running (PID: $ids). Close the game before installing or restoring files."
    }
}
