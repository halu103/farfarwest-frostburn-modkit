[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$GameRoot,
    [Parameter(Mandatory)] [string]$InstallerPath,
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstallerSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The GUI installer is a .NET Framework executable. Invoke its tested install
# engine under Windows PowerShell 5.1 rather than loading it in PowerShell 7.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw 'Windows PowerShell 5.1 was not found.'
    }
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
        -GameRoot $GameRoot -InstallerPath $InstallerPath `
        -ExpectedInstallerSha256 $ExpectedInstallerSha256
    if ($LASTEXITCODE -ne 0) {
        throw "Installer engine failed under Windows PowerShell 5.1 (exit code $LASTEXITCODE)."
    }
    return
}

$installer = [IO.Path]::GetFullPath($InstallerPath)
$game = [IO.Path]::GetFullPath($GameRoot)
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer not found: $installer"
}
if (-not (Test-Path -LiteralPath $game -PathType Container)) {
    throw "Game folder not found: $game"
}
$actualHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
if (-not $actualHash.Equals($ExpectedInstallerSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Installer SHA-256 mismatch: $actualHash"
}
if (Get-Process -Name 'FarFarWest', 'FarFarWest-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Far Far West is running; installation was refused.'
}

$assembly = [Reflection.Assembly]::LoadFile($installer)
$type = $assembly.GetType('FFWFrostburn8Installer.InstallerEngine', $true)
$flags = [Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic
$method = $type.GetMethods($flags) | Where-Object {
    $_.Name -eq 'Install' -and $_.GetParameters().Count -eq 2
} | Select-Object -First 1
if ($null -eq $method) {
    throw 'The installer engine entry point was not found.'
}

$messages = New-Object 'System.Collections.Generic.List[string]'
$logger = [Action[string]] { param([string]$line) $messages.Add($line) }
try {
    $result = $method.Invoke($null, [object[]]@($game, $logger))
} catch [Reflection.TargetInvocationException] {
    $messages | Select-Object -Last 25 | Write-Output
    if ($_.Exception.InnerException) {
        throw $_.Exception.InnerException
    }
    throw
}
$messages | Select-Object -Last 25 | Write-Output
$resultType = $result.GetType()
$resultFlags = [Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic
$backupProperty = $resultType.GetProperty('BackupDirectory', $resultFlags)
[pscustomobject]@{
    installed = $true
    installerSha256 = $actualHash
    gameRoot = $game
    backupDirectory = $backupProperty.GetValue($result, $null)
    gameWasLaunched = $false
}
