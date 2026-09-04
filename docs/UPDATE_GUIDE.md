# Updating after a Far Far West patch

This project owns its multiplayer Lua source. Updating it never requires a
download from a third-party mod page.

## Select the PowerShell edition

Windows PowerShell 5.1 and PowerShell 7+ are separate programs. Check the
current terminal with `$PSVersionTable.PSEdition` and
`$PSVersionTable.PSVersion`, then run only the matching command shown in each
step:

- `Desktop 5.1`: use `powershell.exe`;
- `Core 7.x`: use `pwsh.exe` (recommended for maintenance and downloads).

Both editions are tested by the project. PowerShell 4 and earlier and
PowerShell 6 are not supported. See [PowerShell compatibility](POWERSHELL.md)
for troubleshooting.

## 1. Record and scan the new game build

Let Steam finish updating, close the game, and run the matching command.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Compatibility.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Compatibility.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

A changed executable hash is normal after a patch. Every signature must still
have exactly one match. Zero means the implementation changed; more than one
means the pattern is ambiguous. Do not package or install either case.

`config/static-signatures/FName_Constructor.lua` is scan-only. Keep it out of
the runtime signature directory unless a future UE4SS build is proven to accept
that override.

## 2. Refresh official UE4SS and lock the game

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Refresh-Upstream.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Refresh-Upstream.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The script downloads official UE4SS release/config assets, verifies their
published SHA-256 values, scans the staged signatures against the local game,
and updates `config/upstream.lock.json`. Review every resulting diff.

## 3. Review reflected multiplayer paths

The owned source lives at
`src/Mods/FFWFrostburn8/Scripts/main.lua`. After a game update, inspect a fresh
runtime log for these items:

- `CapWrite source=GameSession ... AFTER=8`;
- `CapWrite source=Manager ... AFTER=8`;
- at least one `NativeHook registered` line;
- after creating a room, `SessionParamWrite ... WRITE=true AFTER=8`.

If the game renames a function or capacity field, add its exact reflected path
or exact field name only after confirming its meaning. Keep discovery
fail-closed; never replace an arbitrary small integer just because it currently
equals four.

Update `src/mod.json` and the `MOD_VERSION` constant together when the owned mod
changes.

## 4. Validate and build without installing

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Project.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Project.ps1
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The builder copies the tracked `src/` tree, records its deterministic tree hash,
creates a release under `dist/`, expands it again, and verifies every file. A
release containing PAK, UCAS, or UTOC files is rejected.

`Install-Release.ps1` is an internal primitive and requires the expected SHA-256
of its ZIP. The public `Install-Mod.ps1` command supplies that value directly
from the just-built package so a file cannot change between build and install.

## 5. Install and perform a clean startup test

With the game closed, use only the public one-command path matching the
installed PowerShell edition.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

The installer takes a dated backup and refuses to write if the game is running.
Launch the game normally, create a room with **Allow mods** enabled, open
**Current Session**, then run the matching verification command.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-RuntimeLog.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -RequireCurrentSession `
  -RequireSessionUi
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-RuntimeLog.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -RequireCurrentSession `
  -RequireSessionUi
```

Core startup can be automated, but multiplayer capacity cannot be honestly
proven with one client. Create a hosted room, confirm
`sessionParameterApplied=true`, then have a fifth real player join. Test all
eight clients before labeling a release fully verified for eight players.

If startup fails, close the game and restore the dated backup. Attach the fresh
UE4SS log and crash dump to the issue instead of repeatedly launching with a
failed or ambiguous signature.

## 6. Commit source changes

```powershell
git diff
git add src config docs tools Install-Mod.ps1 README.md CHANGELOG.md THIRD_PARTY_NOTICES.md
git commit -m "Update FFWFrostburn8 for Far Far West BUILD"
```

Do not force-add ignored content from `vendor/`, `work/`, `dist/`, or
`artifacts/`.
