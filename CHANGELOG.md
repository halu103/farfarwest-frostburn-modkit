# Changelog

## 0.1.1 - 2026-09-02

- Excluded the stale upstream FName runtime override after a live Frostburn test showed repeated verification failure.
- Kept the FName pattern as a static-only compatibility sentinel.
- Confirmed UE4SS 1109's integrated scanner reaches `Event loop start` and loads More Players with `Target MaxPlayers=8`.
- Excluded the incompatible pre-Frostburn PAK/UCAS/UTOC set after isolated testing proved it crashes UE 5.8 without the Lua mod loaded.
- Switched releases to a stable Lua-only mode; runtime logs confirm `MaxPlayers` changes from 4 to 8 in the lobby.
- Made the runtime log check reject fatal AOB scan markers.

## 0.1.0 - 2026-09-02

- Added a pinned UE4SS Frostburn baseline at commit `5b2663e9`.
- Added UE 5.8 Far Far West settings and signatures for FName, GNatives, and ProcessLocalScriptFunction.
- Added static executable compatibility scanning with one-match enforcement.
- Added a hash-verified builder using a locally supplied More Players archive.
- Added safe install and backup restoration scripts that refuse to run while the game is active.
- Added a read-only runtime log checker for user-driven game tests.
- Added repository validation and a Windows GitHub Actions workflow.
