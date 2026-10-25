[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $npx) { $npx = Get-Command npx -ErrorAction SilentlyContinue }
if (-not $npx) { throw "Install Node.js with npm to run the offline Lua policy and adapter tests." }

# Fengari runs Lua 5.3 semantics against fake UE4SS objects. These are offline
# tests of ordering/guards; they do not launch the game or prove replication.
$specs = @("tests/run_state_spec.lua", "tests/MissileFix.spec.lua", "tests/joker_fix_spec.lua")
Push-Location -LiteralPath $projectRoot
try {
    foreach ($spec in $specs) {
        if (-not (Test-Path -LiteralPath $spec -PathType Leaf)) { throw "Missing test: $spec" }
        & $npx.Source --yes --package=fengari-node-cli@0.1.0 fengari $spec
        if ($LASTEXITCODE -ne 0) { throw "Offline gameplay test failed: $spec" }
    }
} finally {
    Pop-Location
}

[pscustomobject]@{ passed = $true; specs = $specs; gameLaunched = $false; multiplayerRuntimeVerified = $false }
