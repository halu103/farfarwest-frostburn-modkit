# Far Far West Frostburn 8 Players

An independent, source-owned UE4SS mod and maintenance kit for raising Far Far
West's multiplayer capacity to eight players after the Frostburn/Unreal Engine
5.8 update.

The repository contains the complete Lua source for `FFWFrostburn8`. It does
not download, copy, or package another player's-capacity mod, and it does not
contain cooked game assets.

Current baseline:

- Far Far West: `0.2.0.4 - CL 559`
- Unreal Engine override: `5.8`
- UE4SS: `v3.0.1-1109-g5b2663e9`
- Owned mod: `FFWFrostburn8 v1.0.0` (MIT)
- Target capacity: `8`
- Package mode: source-owned Lua only

## Install with one command

Close Far Far West, open PowerShell in this repository, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

The command automatically finds the Steam installation, validates the exact
game build and AOB signatures, obtains the pinned official UE4SS asset when it
is not already cached, builds the owned mod from `src/`, creates a dated backup,
installs the package, and verifies every installed file.

It never starts, closes, or restarts the game. It refuses to write while
`FarFarWest-Win64-Shipping.exe` is running. No Nexus download is used. Internet
access is needed only on the first build when the verified official UE4SS ZIP
is not present under the ignored `vendor/cache/` directory.

If automatic Steam discovery is not available, pass the game path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

## What the mod changes

`src/Mods/FFWFrostburn8/Scripts/main.lua` independently applies the capacity at
the three layers used by the current game:

1. server-side `AGameSession.MaxPlayers`;
2. `BP_Manager_Multiplayer_C.MaxPlayers` before a room is created;
3. native create/update-session capacity parameters discovered from reflected
   Unreal metadata.

The native hook discovery is fail-closed: only exact capacity field names such
as `MaxPlayers`, `NumPublicConnections`, and `PublicConnections` are changed.
If an update renames them, the mod reports that no target was found instead of
guessing an integer argument.

The mod does not change enemy scaling, create fake players, suppress manual
kicks, or install PAK/UCAS/UTOC files. The installer removes the exact legacy
cooked-asset filenames known to crash UE 5.8, but only after including any
existing copies in its backup.

## Verify the installation

After launching the game normally, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-RuntimeLog.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -RequireCurrentSession
```

A passing core report proves that UE4SS and the owned mod loaded without known
fatal scanner errors, and that the server-side cap was written to eight. The
report separately exposes:

- `managerCapApplied`: the game's multiplayer manager was set to eight;
- `nativeSessionHookReady`: a current session create/update hook is attached;
- `sessionParameterApplied`: a create/update-session call actually passed
  through a native hook and its capacity was changed to eight;
- `maximumObservedPlayers`: largest real `PlayerArray` seen in the log;
- `networkCapacityTested`: at least a fifth real player joined;
- `fullEightPlayerSessionTested`: eight real players were observed together.

Setting a value to eight is not the same as proving eight network clients. A
fifth successful join is the end-to-end proof that the original four-player
limit was exceeded; observing all eight is the definitive full-capacity test.

In the UE console, `FFW8_Status` asks the mod to rescan and print its current
status to `ue4ss/UE4SS.log`.

## Restore a backup

Close the game and use the backup path printed by the installer:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Restore-Backup.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -BackupDirectory ".\artifacts\backups\INSTALL-TIMESTAMP"
```

## Repository layout

```text
src/                         Owned mod metadata and complete Lua source
config/upstream.lock.json    Pinned game and official UE4SS versions/hashes
config/ue4ss/                Tracked Far Far West UE4SS compatibility config
config/static-signatures/    Read-only compatibility sentinels
Install-Mod.ps1              One-command build, backup, and installer
tools/                       Build, validation, runtime, and restore tooling
docs/UPDATE_GUIDE.md         Maintainer workflow after a game update
```

Generated or local-only data under `vendor/`, `work/`, `dist/`, and
`artifacts/` is ignored by Git.

### Frostburn FName compatibility note

The official Frostburn config still includes an old custom
`FName_Constructor.lua`. On this build, UE4SS finds its address but rejects the
override during runtime verification. The release therefore uses UE4SS 1109's
integrated FName scanner. The old pattern remains only under
`config/static-signatures/` for a read-only executable compatibility check and
is never packaged.
