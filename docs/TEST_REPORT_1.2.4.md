# v1.2.4 CL 2979 compatibility update — 2026-11-01

## Failure and correction

The v1.2.3 installer correctly rejected the updated game: it expected
`0.3.0.7 - CL 2852`, while Steam build 26311307 supplies ProductVersion
`++depot+CanyonEngine_Dev-CL-2979`. The installed shipping executable has
SHA-256 `07C476D198ED2D40BABB675E3FAEF68E9B2F3F6E7B8E125F2418A95E5262474A`.

The new lock pins both that exact ProductVersion and executable hash. The
readable `CL2979` label is used only for artifact filenames and display;
validation still compares the complete internal version and all signatures.
The known-bad FName runtime override remains excluded.

## Static contract review

All three existing UE4SS AOB patterns match exactly once in CL2979:

| Pattern | File offset |
| --- | --- |
| FName_Constructor (static sentinel only) | `0x1473A70` |
| GNatives | `0x1099CF0` |
| ProcessLocalScriptFunction | `0x1662900` |

Relevant current cooked assets were extracted read-only into ignored
`work/compatibility-CL2979`, using the existing local retoc utility. No game
assets or extracted bytecode are included in the release.

- The missile graph still has only initialization cases 0–4, checks at least
  four enabled levers, and uses the same eligible Delay nodes:
  UUID `-831542045` / linkage `15`, and UUID `417648707` / linkage `2503`.
  The graph parsed fully: 13,881 memory bytes / 17,661 serialized script bytes.
  Enable/disable lever functions also parsed to their expected lengths.
- The native BPFL_Multiplayer exports, AC_PlayerStateJoker exports,
  S_PlayerItemBackup export and GM_GameMode exports match the prior analyzed
  exports byte-for-byte, with identical name maps.
- BP_CanyonGameInstance and BP_Manager_Multiplayer have changed. Their whole
  assets are not claimed identical. The GameInstance Joker add/remove,
  death and Uranium setter bytecode was decoded again and retains the backup
  map and field names expected by the guarded adapter. Runtime UE4SS schema
  checks and map-scoped behavior are retained.

## Passed offline checks

- Project/source/PowerShell validation passed under PowerShell 7 and Windows
  PowerShell 5.1: 12,257 checks, 16 parsed scripts.
- Lua policies and fake-UE4SS contracts passed under both shell editions:
  86 RunState + 43 MissileFix + 43 JokerFix = 172 checks per run.
- Both standalone EXEs built with version 1.2.4.0 and passed native read-only
  verification against the real CL2979 game. The installer embeds the complete
  package and verified 28 payload files in a ZIP round trip.
- Installer sandbox checks passed: installation, persistent backup, legacy
  mod removal, path-with-spaces entry point, unmanaged-file preservation,
  injected failure and complete original-tree rollback.
- Additional rejection test passed: a one-byte-modified executable retaining
  the exact supported ProductVersion is rejected by SHA-256 before writes.
  Its sandbox tree remains unchanged during verification.
- Uninstaller sandbox checks passed: clean snapshot restoration, update-chain
  handling, legacy/missing-backup mod-only removal, unrelated-mod preservation,
  corrupted-backup refusal, safe fallback to an older valid backup, injected
  failure rollback and native path-with-spaces verification.
- Both adjacent checksum files match their final EXEs. The source game
  executable still matches its pinned SHA-256 after all checks.

Build commands used `Build-InstallerExe.ps1` and `Build-UninstallerExe.ps1`
with explicit `-OutputDirectory dist/release-v1.2.4`. The two sandbox suites
ran sequentially with explicit new EXE paths. Static output is retained in
`artifacts/compatibility-report.json`; fixtures/logs are under
`work/installer-e2e`, `work/uninstaller-e2e` and `work/installer`.

## Final player artifacts

Folder: `dist/release-v1.2.4/`. Four files: standalone Setup, Uninstall and
their adjacent `.sha256.txt` files. No player ZIP is required.

- `FarFarWest-Frostburn-CL2979-FFWFrostburn8-v1.2.4-Setup.exe`
  (9,007,616 bytes):
  `1D4E3A3DB1700F69F13D63B66B05A75E262FFB71876A32D853F2FBC888C0E563`
- `FarFarWest-Frostburn-CL2979-FFWFrostburn8-v1.2.4-Uninstall.exe`
  (75,264 bytes):
  `FD257EDF2386A63C3146BDC46459CEB74693C8CCD859B713DEEA1C5B34755AF4`
- Owned Lua source-tree SHA-256:
  `2E08BD72BC7C3FBA36F465534429F00F7BB38C9C9FC247B9360689985D5C49E9`
- Setup-embedded release ZIP SHA-256:
  `2566CDA8114024355FCEBD25A52BBADDC0CBD3A0F28863BFDA02821198C0F1DC`

## Limits

No live game was launched or real game mod/save files changed. EXEs are
unsigned. No GitHub release or website deployment was performed. Earlier
release artifacts remain in their existing folders.

This update fixes the CL2979 installation refusal and retains the guarded
adapters; it does not verify 5–8 player EOS capacity, vanilla guest support,
replication, missile rewards, Joker effects or reconnect behavior. Those need
the controlled live multiplayer checks in `GAMEPLAY_FIXES.md`.
