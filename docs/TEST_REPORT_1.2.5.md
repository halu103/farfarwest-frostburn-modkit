# v1.2.5 compatibility verification — 2026-11-17

## Target

- [Steam patch 0.3.0.11](https://store.steampowered.com/news/app/3124540/view/1849458702689619), public build `26708584`, installed depot manifest `5935613571091510998`.
- The executable reports `++depot+ReleaseEngine_Dev-CL-3041`; its SHA-256 is `02B2E84C522882D480CD6F30333AC1975D2E08BB60298B15CE294964B250FB95`. Setup still checks both values exactly, rather than accepting any executable labeled `0.3.0.11`.
- UE4SS remains pinned to `v3.0.1-1109-g5b2663e9`. The three existing static checks matched once each: `FName_Constructor` at `0x1474230` (static only), `GNatives` at `0x1099CF0`, and `ProcessLocalScriptFunction` at `0x16630C0`.

## Scope and evidence

No change to the lobby target, Session UI, Allow Mods gate, missile behavior or Joker restore logic. Lua changes are limited to version/build metadata and log wording.

Six focused cooked packages matched the previous CL2979 baselines byte for byte: `BP_TntMissileLauncher`, `AC_PlayerStateJoker`, `BPFL_Multiplayer`, `BP_Manager_Multiplayer`, `S_PlayerItemBackup`, and `GM_GameMode`. `BP_CanyonGameInstance` differs by five bytes in its native save-fix/Joker-limit functions; its Joker backup setters and backup save export are unchanged. The three Session UI widget paths and the referenced player-list fields still exist; this does not prove the UI works at runtime. The comparison used local, read-only extraction to `work/compatibility-CL3041`, which is not part of the release.

Project validation and all 172 Lua checks passed in PowerShell 7 and Windows PowerShell 5.1. Both standalone EXEs passed read-only verification on CL3041; Setup verified all 28 embedded payload files. The installer sandbox passed normal installation, persistent backups, rollback, and rejection of a modified executable with the correct ProductVersion. The uninstaller sandbox passed snapshot restoration, mod-only removal, unrelated-mod preservation, corrupt-backup handling, and rollback. The final executable hashes match their adjacent checksum files.

The website now shows the same public patch and changelist as the installer lock. Both web regression tests, Svelte type checks and the Vercel production build passed locally.

## Release files

The four standalone files are in `dist/release-v1.2.5/`; no player ZIP is required. Both EXEs report file version `1.2.5.0` and are unsigned.

| File | SHA-256 |
| --- | --- |
| `FarFarWest-Frostburn-CL3041-FFWFrostburn8-v1.2.5-Setup.exe` | `4F12CD661910DB9049F7276318F245D9780C5FA9D69AC1EE89DE39B73ED26E2C` |
| `FarFarWest-Frostburn-CL3041-FFWFrostburn8-v1.2.5-Uninstall.exe` | `43D3BF5F147CC87002B1EE989B2C527418E894541EE0E63077D3D2E0EAA20875` |

Owned Lua source tree SHA-256: `7195422CB55686E15A085BDE0BD32DA8A8E8F0EB00876D26895FD52F04337557`.

The real game was not launched or modified. Live multiplayer, including the 5–8 player lobby and unmodified guest compatibility, was not retested. No GitHub release or website deployment was performed.
