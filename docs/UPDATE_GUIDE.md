# Updating after a Far Far West patch

This workflow deliberately separates discovery, compatibility validation,
packaging, and installation. Never use the game itself as the first test.

## 1. Record the new game build

Allow Steam to finish updating, then close the game. Run:

```powershell
pwsh -NoProfile -File .\tools\Test-Compatibility.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

A changed executable hash is expected after a patch. Signature results are the
important gate:

- Exactly one match: the signature is still structurally valid.
- Zero matches: the function changed and the signature must be regenerated.
- More than one match: the signature is ambiguous and must be extended.

Do not build or install when any signature is not unique.

## 2. Refresh official UE4SS

```powershell
pwsh -NoProfile -File .\tools\Refresh-Upstream.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The script:

1. Reads the current official experimental release.
2. Downloads the basic UE4SS and custom-config assets.
3. Verifies GitHub-provided SHA-256 digests.
4. Stages the Far Far West config.
5. Checks staged AOB signatures against the local executable.
6. Updates tracked config and `upstream.lock.json` only after validation passes.

## 3. Update More Players metadata

Download a new More Players archive from Nexus. Do not commit it.

```powershell
pwsh -NoProfile -File .\tools\Refresh-Upstream.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -MorePlayersArchive "C:\path\to\new-file.7z" `
  -MorePlayersVersion "NEW_VERSION"
```

Review the mod's `main.lua` and confirm the intended
`TARGET_MAX_PLAYERS`. The build script also checks that the archive contains
the Lua folder and the complete PAK/UCAS/UTOC triple.

## 4. Build without installing

```powershell
pwsh -NoProfile -File .\tools\Build-Release.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -MorePlayersArchive "C:\path\to\downloaded-more-players.7z"
```

The result is written under `dist/`. The builder expands the final ZIP again
and compares every file hash with the staging tree.

## 5. Review and commit

```powershell
pwsh -NoProfile -File .\tools\Test-Project.ps1
git diff
git add config docs tools CHANGELOG.md README.md
git commit -m "Update compatibility for Far Far West BUILD"
```

Never use `git add -f` for `vendor/`, `work/`, `dist/`, or
`artifacts/`.

## 6. Install after closing the game

```powershell
pwsh -NoProfile -File .\tools\Install-Release.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -Archive ".\dist\THE-BUILT-PACKAGE.zip"
```

The installer refuses to continue if the game process exists and creates a
dated backup before replacing UE4SS.

## Runtime verification performed by a player

Runtime testing is intentionally outside the automated update process. After a
human launches the game, run:

```powershell
pwsh -NoProfile -File .\tools\Test-RuntimeLog.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The report checks that:

- `ue4ss/UE4SS.log` reaches `Event loop start`.
- The log contains `[FFWMorePlayers v...] Mod loaded`.
- The log contains `Target MaxPlayers=8`.

If the game build exposes its in-game console, `FFW_Settings` prints the active
scaling values. The definitive multiplayer check is to host a lobby and confirm
that a fifth player can join; repeat up to eight if enough testers are available.

If startup fails, restore the most recent backup and attach the UE4SS log and
crash dump to the issue. Do not keep retrying an ambiguous signature.
