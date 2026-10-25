# Changelog

## 1.2.4 - missile and same-map Joker fix preview (unreleased)

- Retain the previous eight-player capacity and Session UI logic for game
  `0.3.0.7 - CL 2852`.
- Repair the TNT missile's missing initialization cases for 5–8 players. The
  current game already requires four levers; its unhandled player-count switch
  instead produces zero TNT/time defaults. Restore the existing four-player
  baseline of 9 TNT and a 4-second lever window at the exact native timer nodes.
  Keep the game's normal four-lever success, ignition and launch sequence.
- Retain a map-scoped shadow of the game's native Joker backup, keyed by the
  game's stable network player ID. Guests can receive a retained complete list
  on Leave/Back or disconnect/rejoin to the same map when the native list is
  missing/empty. Use the native replicated Joker component to apply cards and
  effects; preserve current death/Uranium metadata.
- Clear the shadow at mission end, lobby/menu, new world or map generation.
  Prefer nonempty native state, never append cached cards, and retain legitimate
  Joker removals. Verify writes and attempt rollback on partial failure.
- Add offline policy and UE4SS-contract tests plus CI execution. These checks
  do not prove live replication, mission rewards, 5–8 players or vanilla guests.
- Build as a separate gameplay test package. No game launch or live install is
  performed by the build. See `docs/GAMEPLAY_FIXES.md` for evidence, limitations
  and a controlled multiplayer verification checklist.

## 1.2.3 - game 0.3.0.7 legacy-runtime test (unreleased)

- Pin the installer to the installed Far Far West `0.3.0.7 - CL 2852`
  executable and its SHA-256; continue to refuse other builds rather than
  forcing installation after a game patch.
- Verify all three existing UE4SS signatures occur exactly once in the new
  executable. This is a static compatibility check, not a multiplayer test.
- Label the installer bundle as an EOS legacy-runtime test. The game moved
  matchmaking to Epic Online Services; old Steam creation/kick hooks do not
  register in the observed 0.3.0.0 run, so 5–8 vanilla clients are unverified.
- Preserve the earlier MaxPlayers/session-cap and Invite-row runtime logic
  rather than conflating an installer version refusal with a runtime failure.
  A single guest joining proves only that a two-player room works; it does not
  validate players 5–8 or host-only vanilla-client compatibility.
- Preserve the diagnostic source added for the earlier local v1.2.3 preview,
  but do not claim it fixes mission or Joker behavior. Its Joker counts were
  unreadable on the previous 0.3.0.0 run and require new-game investigation.

- Add bounded, read-only host-side snapshots for the TNT missile objective,
  including player count, actual lever states, ignition prerequisites, and
  whether the rocket has already blown.
- Trace the game's own lever-enable and ignition calls to identify the normal
  four-player transition before changing mission behavior.
- Record anonymized per-PlayerState Joker collection counts, including the
  nested item-Joker collection, across departure and rejoin.
- Do not restore Joker inventory or force missile ignition. Neither proposed
  gameplay fix is verified; do not publish this preview as a bug-fix release.
- No game installation or multiplayer runtime validation was performed during
  this build.

## 1.2.2 - 2026-09-13

- Add a standalone native x64 `FFWFrostburn8-Uninstall.exe` so players no
  longer need PowerShell or manual folder deletion to remove the mod.
- Make mod-only removal the safe default: remove only the project-owned mod
  directory and ownership marker while preserving UE4SS and unrelated mods.
- Keep complete pre-install snapshot restoration as an explicitly selected
  advanced recovery mode, with full hash validation before any game-file write.
- Support older/manual upgrade histories that have no clean pre-install backup;
  reinstalling over an existing mod is no longer a blocker for normal removal.
- Refuse to change files when the game is running, the active installation is
  not owned by this project, or an advanced snapshot is missing or damaged.
- Create and verify a separate pre-uninstall safety backup; automatically roll
  back to it if any restore operation fails.
- Add sandbox tests covering complete restoration, legacy and missing-backup
  mod-only removal, unrelated-mod preservation, repeat-run refusal,
  corrupted-backup refusal, both rollback paths, and game EXE integrity.
- Include Setup and Uninstall executables together at the release ZIP root with
  SHA-256 entries for both files.

## 1.1.4 - 2026-09-12

- Add an explicitly labelled host-only experimental mode for testing vanilla
  guests while only the host runs UE4SS and `FFWFrostburn8`.
- Extend reflected capacity discovery to SteamCorePro create/update-session and
  lobby-create functions, including the exact `MaxMembers` field.
- Add a fail-closed join guard that suppresses only empty-reason automatic
  kicks from known lobby/player-state validation sources in an **Allow Mods**
  room with 4–7 players. Manual kicks, bans, reason-bearing kicks, non-host
  calls, and ninth-player attempts are preserved.
- Capture **Allow Mods** at room creation and keep that value through the
  Current Session widget-construction race, fixing the erroneous vanilla
  `1 host + 3 Invite` layout in a mod-enabled solo room.
- Give every generated Invite widget a unique slot id, reconcile after widget
  construction, refresh the layout, and emit exact `1+7` and `5+3` UI evidence.
- Add strict runtime-report switches for host-only hooks, a fifth-player join,
  seven solo Invite rows, and the five-player/three-Invite layout.
- Keep vanilla-client compatibility explicitly unverified: the build and
  offline tests do not replace a real clean-client multiplayer test.

## 1.1.3 - 2026-09-11

- Synchronize `UI_Menu_SessionMember` rows with the live `PlayerArray` before
  adding invite rows, so a fifth real player is displayed as the fifth member
  and leaves three invite positions in an eight-player room.
- Gate the eight-row Session interface on the game's live **Allow mods** status;
  an unmodified room now keeps the normal four-row interface even while the
  UE4SS script is installed locally.
- Add runtime evidence for synchronized real-player rows and a strict
  `-RequireSynchronizedPlayerRows` verification option.
- Update the pinned game baseline to `0.2.0.20 - CL 915` after all three tracked
  UE 5.8 signatures matched the executable exactly once in a read-only scan.
- Keep live game launch and five-to-eight-client validation explicitly pending;
  this release was built without starting or restarting Far Far West.

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
