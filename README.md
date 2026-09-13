# Far Far West Frostburn 8 Players — Host-Only Experimental

An independent, source-owned UE4SS mod and maintenance kit for raising Far Far
West's multiplayer capacity to eight players after the Frostburn/Unreal Engine
5.8 update. Version 1.2.2 is an experimental build intended to test whether
only the host can install the mod while guests remain completely vanilla.

The repository contains the complete Lua source for `FFWFrostburn8`. It does
not download, copy, or package another player's-capacity mod, and it does not
contain cooked game assets.

## Download the player build

**Players should use the release build, not GitHub's green `Code` button:**

[Download FFWFrostburn8 for Windows x64](https://github.com/halu103/farfarwest-frostburn-modkit/releases/latest/download/FFWFrostburn8-Windows-x64.zip)

Extract that ZIP and run `FFWFrostburn8-Setup.exe`, which is immediately at the
archive root. The same folder contains `FFWFrostburn8-Uninstall.exe` for safe,
backup-based removal. No source browsing or PowerShell is required. The
download also contains a short Vietnamese/English guide and SHA-256 checksums.

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

- Far Far West: `0.2.0.20 - CL 915`
- Unreal Engine override: `5.8`
- UE4SS: `v3.0.1-1109-g5b2663e9`
- Owned mod: `FFWFrostburn8 v1.2.2` (MIT, host-only experimental)
- Target capacity: `8`
- Session UI: `1 host + 7 invite slots` when hosting alone
- Package mode: source-owned Lua only
- Vanilla-client compatibility: unverified until a real 5–8 player test passes

## Install with the EXE (recommended)

Players do not need to type a PowerShell command. Close Far Far West,
double-click the release file ending in `Setup.exe`, verify the automatically
detected game folder, and click **Install / Cài**. The full package is embedded
in the EXE, so it does not download another multiplayer mod.

For the v1.2.2 host-only experiment, install this build on the **host only**.
Guests must use the same game version but must not install UE4SS or this mod;
otherwise the test cannot prove vanilla-client compatibility. This is a
prerelease claim, not a guarantee that missions remain synchronized at 5–8
players.

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
the four host-side layers used by the current game:

1. server-side `AGameSession.MaxPlayers`;
2. `BP_Manager_Multiplayer_C.MaxPlayers` before a room is created;
3. native create/update-session capacity parameters discovered from reflected
   Unreal metadata;
4. SteamCorePro lobby `MaxMembers`, discovered by its exact reflected field
   name instead of guessing an integer argument.

The experimental join guard suppresses only an empty-reason automatic kick
from the known lobby/player-state validation path while an **Allow Mods** room
has 4–7 players. Manual kicks, bans, reason-bearing kicks, non-authority calls,
rooms without **Allow Mods**, and attempts beyond eight players are left alone.

It also synchronizes the current-session list with the live `PlayerArray`
before filling the remaining positions to eight. A fifth real player therefore
gets a fifth `UI_Menu_SessionMember` row instead of being hidden behind a stale
invite row. When the host is alone, that means one host row plus seven clickable
invite rows. With five players, exactly three Invite rows is correct because
`5 + 3 = 8`. Both member and invite rows use the game's current Frostburn
widgets, so no copied or stale cooked UI asset is required.

When creating a network room, tick **Allow mods** before choosing the room
type. Version 1.2.2 captures that choice when the host creates the room and
keeps it through the widget-construction race; the red "configured to allow
mods" message remains a secondary confirmation. This prevents a temporary
hidden text widget from incorrectly restoring the vanilla `1 + 3` layout. The
checkbox does not load or unload an installed UE4SS script; a newly installed
version is loaded the next time the game starts.

The native hook discovery is fail-closed: only exact capacity field names such
as `MaxPlayers`, `NumPublicConnections`, and `PublicConnections` are changed.
If an update renames them, the mod reports that no target was found instead of
guessing an integer argument.

The mod does not change enemy scaling, create fake players, suppress manual
kicks/bans, or install PAK/UCAS/UTOC files. The installer removes the exact legacy
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
- `hostOnlyRoomHookReady`, `hostOnlyJoinGuardReady`, and
  `hostOnlyLobbyHookReady`: the three experimental host-side hooks attached;
- `hostOnlyLobbyWriteApplied`: Steam lobby `MaxMembers` was written to eight;
- `hostOnlyJoinKickBlocked`: the selective join-time empty-reason kick was
  intercepted;
- `soloInviteUiVerified`: an exact visible `1 member + 7 Invite` layout;
- `fivePlayerUiVerified`: an exact visible `5 members + 3 Invite` layout.

Setting a value to eight is not the same as proving eight network clients. A
fifth successful join is the end-to-end proof that the original four-player
limit was exceeded; observing all eight is the definitive full-capacity test.

In the UE console, `FFW8_Status` asks the mod to rescan and print its current
status to `ue4ss/UE4SS.log`.

To verify the reported fifth-player display fix, first open **Current Session**
while at least five real players are in the same mod-enabled room, then run the
matching command below. This is intentionally a separate live multiplayer
check; a build or static executable scan cannot prove it.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-RuntimeLog.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -RequireCurrentSession `
  -RequireSynchronizedPlayerRows
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -File .\tools\Test-RuntimeLog.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -RequireCurrentSession `
  -RequireSynchronizedPlayerRows
```

A pass reports `maximumSynchronizedPlayerRows` of at least `5` and
`fifthPlayerRowDisplayed: true`. To check the other regression, create a fresh
room without **Allow mods**: the interface must stay at the game's normal four
rows, and the report exposes `allowModsUiGateObserved: true` after that screen
has been observed.

For the host-only experiment, use clean guests and run this on the host after
the fifth player has joined and **Current Session** has been opened:

```powershell
pwsh.exe -NoLogo -NoProfile -File .\tools\Test-RuntimeLog.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -RequireCurrentSession `
  -RequireHostOnlyHooks `
  -RequireHostOnlyJoin `
  -RequireFivePlayerUi
```

The host log cannot inspect guest disks, so it deliberately reports
`vanillaClientInstallationStateProven: false`. Confirm separately that every
guest has no `dwmapi.dll`/UE4SS installation. Test clients 2–4 first, then the
fifth via both session code and Steam Invite, then clients 6–8, map travel,
one mission objective, reconnect, and a manual kick. Do not advertise
host-only support until that matrix succeeds.

## Uninstall with the EXE (recommended)

Close Far Far West, run `FFWFrostburn8-Uninstall.exe` from the extracted player
bundle, verify the detected game folder, and click **Uninstall / Gỡ**. It finds
the newest valid backup whose saved state does not contain FFWFrostburn8,
verifies every recorded hash, creates a separate pre-uninstall safety backup,
and restores that clean state. If restoration fails, it attempts to put the
complete pre-uninstall state back automatically.

The uninstaller deliberately refuses to modify files when the game is running,
the selected folder is not an active installation owned by this project, or no
clean verified backup is available. It may restore UE4SS or legacy mod files
that existed before FFWFrostburn8 was first installed. It never launches,
closes, or restarts the game.

## Restore a backup manually

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
installer/                   Native WinForms Setup and Uninstall source
Install-Mod.ps1              One-command build, backup, and installer
tools/Build-InstallerExe.ps1 Build the offline Setup.exe
tools/Build-UninstallerExe.ps1 Build the restore-based Uninstall.exe
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
