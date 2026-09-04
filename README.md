# Far Far West Frostburn 8 Players

An independent, source-owned UE4SS mod and maintenance kit for raising Far Far
West's multiplayer capacity to eight players after the Frostburn/Unreal Engine
5.8 update.

The repository contains the complete Lua source for `FFWFrostburn8`. It does
not download, copy, or package another player's-capacity mod, and it does not
contain cooked game assets.

## Download the player build

**Players should use the release build, not GitHub's green `Code` button:**

[Download FFWFrostburn8 for Windows x64](https://github.com/halu103/farfarwest-frostburn-modkit/releases/latest/download/FFWFrostburn8-Windows-x64.zip)

Extract that ZIP and run `FFWFrostburn8-Setup.exe`, which is immediately at the
archive root. No source browsing and no PowerShell are required. The download
also contains a short Vietnamese/English guide and SHA-256 checksum.

## Support development

If this mod is useful to you, you can support its continued maintenance:

<a href="https://www.buymeacoffee.com/halu103">
  <img
    src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&amp;emoji=&amp;slug=halu103&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Poppins&amp;outline_colour=000000&amp;coffee_colour=ffffff"
    alt="Buy Me a Coffee"
  />
</a>

GitHub's automatically generated **Source code (zip)** and **Source code
(tar.gz)** files contain developer source only and are not the installer. The
direct link above becomes available after the corresponding asset is uploaded
to the first GitHub Release; see [publishing a release](docs/PUBLISHING.md).

Current baseline:

- Far Far West: `0.2.0.4 - CL 559`
- Unreal Engine override: `5.8`
- UE4SS: `v3.0.1-1109-g5b2663e9`
- Owned mod: `FFWFrostburn8 v1.1.2` (MIT)
- Target capacity: `8`
- Session UI: `1 host + 7 invite slots` when hosting alone
- Package mode: source-owned Lua only

## Install with the EXE (recommended)

Players do not need to type a PowerShell command. Close Far Far West,
double-click the release file ending in `Setup.exe`, verify the automatically
detected game folder, and click **Install / Cài**. The full package is embedded
in the EXE, so it does not download another multiplayer mod.

The installer validates the supported game build and all embedded hashes,
creates a persistent backup, installs and verifies every managed file, and
automatically attempts rollback on failure. It never launches, closes, or
restarts the game and refuses to write while the game is running.

Read [one-click installer details](docs/INSTALLER.md) before distribution. The
current local build is not code-signed, so Windows may show an
unknown-publisher warning; verify its published SHA-256 and do not disable
Defender.

## Install from source with PowerShell

PowerShell is a source/maintainer fallback, not a requirement for players using
`Setup.exe`.

### Choose the correct PowerShell command

This Windows project is tested with both Windows PowerShell 5.1 and PowerShell
7+. They are different programs and use different executable names. In the
PowerShell window that you intend to use, check the edition first:

```powershell
$PSVersionTable.PSEdition
$PSVersionTable.PSVersion
```

- `Desktop` and version `5.1` means **Windows PowerShell**; use
  `powershell.exe`.
- `Core` and version `7.x` means **PowerShell 7+**; use `pwsh.exe`.
- If `pwsh.exe` is not recognized, it is not installed or is not on `PATH`; use
  the Windows PowerShell 5.1 command instead.
- PowerShell 4 and earlier, PowerShell 6, Linux, and macOS are not supported.

Run only the command for the edition you have. The `-ExecutionPolicy Bypass`
option applies only to that new process and does not permanently change the
computer's execution policy.

### Install with one command

Close Far Far West and open the repository folder in the matching PowerShell
edition.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

The command automatically finds the Steam installation, validates the exact
game build and AOB signatures, obtains the pinned official UE4SS asset when it
is not already cached, builds the owned mod from `src/`, creates a dated backup,
installs the package, and verifies every installed file.

It never starts, closes, or restarts the game. It refuses to write while
`FarFarWest-Win64-Shipping.exe` is running. No Nexus download is used. Internet
access is needed only on the first build when the verified official UE4SS ZIP
is not present under the ignored `vendor/cache/` directory.

If automatic Steam discovery is not available, pass the game path. Use only
the command matching your edition.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

See [PowerShell compatibility](docs/POWERSHELL.md) for terminal detection,
common command-not-found and TLS errors, and matching verify/restore commands.

## What the mod changes

`src/Mods/FFWFrostburn8/Scripts/main.lua` independently applies the capacity at
the three layers used by the current game:

1. server-side `AGameSession.MaxPlayers`;
2. `BP_Manager_Multiplayer_C.MaxPlayers` before a room is created;
3. native create/update-session capacity parameters discovered from reflected
   Unreal metadata.

It also expands the current-session player list at runtime from four rows to
eight. When the host is alone, that means one host row plus seven clickable
invite rows. The extra rows are created from the game's current Frostburn
`UI_Menu_Button_Session_Invite` widget, so no copied or stale cooked UI asset is
required.

When creating a network room, tick **Allow mods** before choosing the room
type. This marks the room as mod-enabled for other clients; it does not itself
load UE4SS or change the four-row interface.

The native hook discovery is fail-closed: only exact capacity field names such
as `MaxPlayers`, `NumPublicConnections`, and `PublicConnections` are changed.
If an update renames them, the mod reports that no target was found instead of
guessing an integer argument.

The mod does not change enemy scaling, create fake players, suppress manual
kicks, or install PAK/UCAS/UTOC files. The installer removes the exact legacy
cooked-asset filenames known to crash UE 5.8, but only after including any
existing copies in its backup.

## Verify the installation

After launching the game normally, run the matching command.

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

A passing core report proves that UE4SS and the owned mod loaded without known
fatal scanner errors, and that the server-side cap was written to eight. The
report separately exposes:

- `managerCapApplied`: the game's multiplayer manager was set to eight;
- `nativeSessionHookReady`: a current session create/update hook is attached;
- `sessionParameterApplied`: a create/update-session call actually passed
  through a native hook and its capacity was changed to eight;
- `sessionUiExpanded`: the current Session list was rebuilt to eight rows;
- `maximumInviteSlotsObserved`: largest number of invite rows verified in the
  current log; this is `7` when the host is alone;
- `maximumObservedPlayers`: largest real `PlayerArray` seen in the log;
- `networkCapacityTested`: at least a fifth real player joined;
- `fullEightPlayerSessionTested`: eight real players were observed together.

Setting a value to eight is not the same as proving eight network clients. A
fifth successful join is the end-to-end proof that the original four-player
limit was exceeded; observing all eight is the definitive full-capacity test.

In the UE console, `FFW8_Status` asks the mod to rescan and print its current
status to `ue4ss/UE4SS.log`.

## Restore a backup

Close the game and use the backup path printed by the installer. Use only the
command matching your edition.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Restore-Backup.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -BackupDirectory ".\artifacts\backups\INSTALL-TIMESTAMP"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Restore-Backup.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -BackupDirectory ".\artifacts\backups\INSTALL-TIMESTAMP"
```

## Repository layout

```text
src/                         Owned mod metadata and complete Lua source
config/upstream.lock.json    Pinned game and official UE4SS versions/hashes
config/ue4ss/                Tracked Far Far West UE4SS compatibility config
config/static-signatures/    Read-only compatibility sentinels
installer/                   Native WinForms one-click installer source
Install-Mod.ps1              One-command build, backup, and installer
tools/Build-InstallerExe.ps1 Build the offline Setup.exe
tools/Build-DownloadBundle.ps1 Build the flat player-download ZIP
tools/                       Remaining build, validation, runtime, and restore tooling
docs/INSTALLER.md            One-click installation, safety, and distribution notes
docs/PUBLISHING.md           Upload the player build as GitHub Release assets
docs/POWERSHELL.md           Commands for Windows PowerShell 5.1 and PowerShell 7+
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
