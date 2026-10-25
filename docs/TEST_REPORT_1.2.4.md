# v1.2.4 test report — 2026-10-25

Target: Far Far West `0.3.0.7 - CL 2852`, Windows x64. Channel:
`gameplay-fix-preview`. Live multiplayer validation remains pending.

## Results

| Check | Result |
| --- | --- |
| Map/player cache policies | 86 checks passed |
| Missile adapter and native timer guards | 43 checks passed |
| Joker native-backup adapter and rollback | 43 checks passed |
| Total offline Lua checks | 172 passed |
| Test runner under PowerShell 7 and Windows PowerShell 5.1 | Passed |
| Lua syntax, source/metadata and PowerShell validation | Passed |
| Exact game version and SHA-256 lock | Passed |
| Three static UE4SS patterns | Each matched exactly once |
| Installer payload | 28 files verified |
| ZIP root layout, extraction and checksums | Passed |
| Sandbox install, backup, injected failure and rollback | Passed |
| Sandbox uninstall, mod-only removal and safety rollback | Passed |

The Lua tests use Fengari CLI 0.1.0 and fake UE4SS objects. They verify state
ordering, map reset, ID isolation, native-data precedence, exact timer guards,
duplicate prevention and partial-write rollback. They do not establish real
UE4SS marshaling, client replication, Joker effects, mission rewards or
eight-player/vanilla-client support.

No game was launched. No real-game installation, save or mod file was changed.
The actual game executable stayed at SHA-256
`9EC3CD10D9F986A95372A590FAE515266175488BEE6C2CF5404BECE2AEB5BACC`.

## Final artifacts

Output folder: `dist/gameplay-fixes-v1.2.4-CL2852/bundle/`.

- `FFWFrostburn8-Setup.exe`:
  `98D4C21449303DEA4EC0509E17C8A3060E7B0061ECF133B58097DC3847F527BE`
- `FFWFrostburn8-Uninstall.exe`:
  `F61531C1A3088C1A2C1036311244648B574AFC3BA5DED62B830999EC1AF79A16`
- `FFWFrostburn8-v1.2.4-FFW-0-3-0-7-CL-2852-GAMEPLAY-TEST-Windows-x64.zip`:
  `310432374EABA2814C9814EC9796EE353B3F148E83DEBC4F68466977731BFBC9`
- Owned Lua source tree:
  `7118E15EB939FB6D8F657AC51827BC1C871E4833D45B8DD935B204C34CFB150F`

The EXEs are unsigned. No antivirus clearance or Nexus review is implied.
The ZIP contains both EXEs, checksums, licenses, install instructions and
`GAMEPLAY-FIXES.txt`. Commercial game assets are not included.

## Remaining in-game validation

Use the procedure in [GAMEPLAY_FIXES.md](GAMEPLAY_FIXES.md). Confirm four-player
control and five-plus-player missile completion, Leave/Back and network-loss
Joker reconnects with cards/effects intact, and cache reset after map end.
Also verify that native nonempty Joker backups take precedence and that
current death/Uranium metadata remain unchanged. A missing native backup for
a previously dead player is deliberately skipped; see the implementation notes.
