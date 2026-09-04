# Changelog

## 1.1.2 - 2026-09-04

- Added a native x64 WinForms `Setup.exe` builder with the verified release ZIP
  embedded for one-click, offline installation without end-user PowerShell.
- Added exact game/package/source hash checks, persistent backups, installed
  file verification, legacy cooked-file cleanup, and automatic rollback to the
  GUI installer. It refuses to write while Far Far West is running and never
  launches, closes, or restarts the game.
- Documented unsigned-build/SmartScreen limitations and separated the normal
  EXE path from PowerShell maintainer/fallback commands.
- Added a flat, five-file Windows x64 player bundle with the installer at ZIP
  root, round-trip hash verification, stable GitHub Release download naming,
  and guidance that distinguishes build assets from source ZIPs.
- Recognize Frostburn's live `UI_Menu_Button_Session_Invite_C` rows and clone
  that exact runtime widget when expanding Current Session to eight rows.
- Keep compatibility recognition for the older `UI_Menu_SessionEmptySlot`
  naming while preferring the class observed in build `0.2.0.4 - CL 559`.
- Document that **Allow mods** marks the room as mod-enabled but does not load
  UE4SS or expand the interface by itself.
- Split every public install, verification, and restore example between
  Windows PowerShell 5.1 (`powershell.exe`) and PowerShell 7+ (`pwsh.exe`).

## 1.1.1 - 2026-09-04

- Added periodic discovery for the Current Session widget because Frostburn can
  construct it before the UE4SS object notification becomes observable.
- Added fail-closed diagnostics for every child class in
  `VerticalBox_Players`, allowing UI changes in future game updates to be
  identified without guessing or mutating an unknown layout.

## 1.1.0 - 2026-09-03

- Expanded `UI_Menu_Container_CurrentSession.VerticalBox_Players` from four to
  eight live rows using the game's current Frostburn empty-slot widget.
- Added seven visible invite rows when hosting alone, without shipping a copied
  PAK, UCAS, UTOC, or another multiplayer mod.
- Added fail-closed child-type checks so a future incompatible lobby layout is
  logged instead of being modified blindly.
- Added runtime evidence for the eight-row Session UI and a strict
  `-RequireSessionUi` verification mode.

## 1.0.0 - 2026-09-02

- Replaced the downloaded multiplayer-mod input with the independently written,
  MIT-licensed `FFWFrostburn8` Lua source.
- Added capacity enforcement for `AGameSession`,
  `BP_Manager_Multiplayer_C`, and reflected native session create/update
  parameters.
- Added fail-closed hook discovery and real `PlayerArray` observation markers.
- Added `Install-Mod.ps1` for one-command Steam discovery, validation, build,
  backup, installation, and installed-file verification.
- Added deterministic source-tree hashing to release and install manifests.
- Removed all external player-capacity archive metadata and download steps.
- Kept recoverable cleanup for incompatible legacy cooked assets that crash
  Frostburn/UE 5.8.
- Confirmed on `0.2.0.4 - CL 559` that the game reaches the title/lobby screens
  without a new crash dump, GameSession and the multiplayer manager hold eight,
  two current native session hooks register, and live session-update settings
  are rewritten from 20 to 8. Real 5–8 client testing remains explicitly
  separate.

## 0.1.1 - 2026-09-02

- Excluded the stale upstream FName runtime override after live Frostburn
  verification failed.
- Kept the FName pattern as a static-only compatibility sentinel.
- Excluded the incompatible pre-Frostburn cooked-asset set after isolation
  testing showed it crashes UE 5.8.
- Made the runtime log check reject fatal AOB scanner markers.

## 0.1.0 - 2026-09-02

- Added a pinned UE4SS Frostburn baseline at commit `5b2663e9`.
- Added UE 5.8 settings and compatibility signatures.
- Added static executable scanning, safe install/restore tooling, runtime log
  validation, and Windows CI validation.
