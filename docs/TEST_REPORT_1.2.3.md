# Official v1.2.3 test report — 2026-10-25

Target: Far Far West `0.3.0.7 - CL 2852`, Windows x64. Channel:
`stable`. Live multiplayer validation remains pending. This is distinct from
the earlier v1.2.3 `LEGACY-TEST` package and replaces the local v1.2.4 preview
designation, not its published assets.

## Offline results and release rebuild

The official v1.2.3 EXEs were rebuilt and all checks below were repeated on
2026-10-25. The standalone release files were copied without alteration and
their SHA-256 values checked against the verified build outputs.

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

Primary output folder: `dist/release-v1.2.3/`. It contains only the two
standalone versioned EXEs and their `.sha256.txt` files; no ZIP is required.

- `FarFarWest-Frostburn-0.3.0.7-CL2852-FFWFrostburn8-v1.2.3-Setup.exe`:
  `C6F269A57D0ADB3AC3F06056BEFDB730A2CA0F218572B22BA5BFF7A571AA22CB`
- `FarFarWest-Frostburn-0.3.0.7-CL2852-FFWFrostburn8-v1.2.3-Uninstall.exe`:
  `0EC5E28BA63CB46E97A3D13B5EC0C43B7A0A08E7F0D219049214208E2506930C`
- Owned Lua source tree:
  `6BC899497B82E4A741253CE0B028F2E8A3A05C4CDBAEB8ECC4EE45F994CAB3F5`

The EXEs are unsigned. No antivirus clearance or Nexus review is implied.
The optional ZIP created before the standalone-release clarification is
preserved under `dist/release-v1.2.3-official-CL2852/bundle/` (not required for
upload or install), SHA-256
`192BBE804950C9E59CE5BA363F242F3D823948C5F317B19F751F7DC611B5AC24`.
Commercial game assets are not included.

## Website release discovery

- Ten regression tests passed, including the actual legacy filename format,
  separate Setup/Uninstall roles, Setup-first checksums, unsafe URL rejection,
  and standalone-install guidance in all six locales.
- Svelte/type checks completed with zero errors and zero warnings.
- The parser was checked against the public GitHub API and retained the
  `legacy-v1.2.3` release, including its long Setup and Uninstall asset URLs.
- The current game/preflight text is `0.3.0.7 - CL 2852`. Main download buttons
  prefer Setup and no longer disappear when a release has no ZIP.

These are local-source checks, not a production deployment. No GitHub release
was published and no Vercel deployment was initiated by this build. The official
EXEs must be uploaded as release assets, and the updated web source must be
deployed before the public website can reflect these changes. See
[website deployment instructions](../web/README.md).

## Remaining in-game validation

Use the procedure in [GAMEPLAY_FIXES.md](GAMEPLAY_FIXES.md). Confirm four-player
control and five-plus-player missile completion, Leave/Back and network-loss
Joker reconnects with cards/effects intact, and cache reset after map end.
Also verify that native nonempty Joker backups take precedence and that
current death/Uranium metadata remain unchanged. A missing native backup for
a previously dead player is deliberately skipped; see the implementation notes.
