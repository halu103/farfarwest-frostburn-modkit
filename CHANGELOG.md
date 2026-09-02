# Changelog

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
