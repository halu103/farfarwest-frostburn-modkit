# Far Far West Frostburn Modkit

Source-first tooling for maintaining a Far Far West More Players package across game updates.

The project does four things without starting the game:

1. Pins an official UE4SS experimental build by commit and SHA-256.
2. Tracks the Far Far West UE 5.8 compatibility configuration in Git.
3. Scans the current game executable and requires every critical AOB signature to match exactly once.
4. Combines UE4SS with a locally downloaded More Players archive into a hash-verified release ZIP.

The current baseline targets:

- Far Far West: `0.2.0.4 - CL 559`
- Unreal Engine override: `5.8`
- UE4SS: `v3.0.1-1109-g5b2663e9`
- More Players Nexus release: `3.6`
- Maximum players: `8`

## Important distribution rule

The More Players author does not permit re-uploading their files to other sites. This repository therefore does **not** contain their Lua, PAK, UCAS, UTOC, or Nexus archive.

Download the archive from Nexus Mods yourself and pass its local path to the build script. Generated packages are placed in `dist/`, which is excluded from Git.

## Repository layout

```text
config/
  upstream.lock.json       Pinned game, UE4SS, and More Players versions/hashes
  ue4ss/                   Version-controlled Far Far West compatibility config
docs/
  UPDATE_GUIDE.md          Procedure for handling a new game update
tools/
  Build-Release.ps1        Reproducible package builder
  Test-Compatibility.ps1  Static AOB and version checker; never starts the game
  Refresh-Upstream.ps1     Pulls a new official UE4SS build/config into the repo
  Install-Release.ps1      Safe installer; refuses while the game is running
  Restore-Backup.ps1       Restores a backup made by the installer
  Test-RuntimeLog.ps1      Checks an existing UE4SS log without starting the game
  Test-Project.ps1         CI/repository validation
```

## First use

Run a static compatibility check:

```powershell
pwsh -NoProfile -File .\tools\Test-Compatibility.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

Build a release using your locally downloaded Nexus archive:

```powershell
pwsh -NoProfile -File .\tools\Build-Release.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -MorePlayersArchive "C:\path\to\FFW-More-Players-3.6.7z"
```

Install only after closing the game:

```powershell
pwsh -NoProfile -File .\tools\Install-Release.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -Archive ".\dist\FarFarWest-Frostburn-0.2.0.4-CL559-MorePlayers8-UE4SS-1109.zip"
```

The installer creates a dated backup and never launches the game.

If you need to undo an installation, close the game and restore the backup path
printed by the installer:

```powershell
pwsh -NoProfile -File .\tools\Restore-Backup.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -BackupDirectory ".\artifacts\backups\INSTALL-TIMESTAMP"
```

Neither script can close, restart, or launch Far Far West. Both refuse to write
while `FarFarWest-Win64-Shipping.exe` is running.

After you launch the game yourself, verify that UE4SS and the mod really loaded:

```powershell
pwsh -NoProfile -File .\tools\Test-RuntimeLog.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The check passes only when the current log contains UE4SS's event-loop marker,
the More Players load marker, and `Target MaxPlayers=8`. A real fifth player
successfully joining a hosted lobby is the final end-to-end multiplayer test.

## After a game update

Follow [docs/UPDATE_GUIDE.md](docs/UPDATE_GUIDE.md). The important rule is simple: do not install anything if a signature has zero or multiple matches.

Only the source and maintenance tooling are intended for GitHub. Do not force-add files ignored under `vendor/`, `work/`, `dist/`, or `artifacts/`.
