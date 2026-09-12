# Updating after a Far Far West patch

This project owns its multiplayer Lua source. Updating it never requires a
download from a third-party mod page.

## Select the PowerShell edition

Windows PowerShell 5.1 and PowerShell 7+ are separate programs. Check the
current terminal with `$PSVersionTable.PSEdition` and
`$PSVersionTable.PSVersion`, then run only the matching command shown in each
step:

- `Desktop 5.1`: use `powershell.exe`;
- `Core 7.x`: use `pwsh.exe` (recommended for maintenance and downloads).

Both editions are tested by the project. PowerShell 4 and earlier and
PowerShell 6 are not supported. See [PowerShell compatibility](POWERSHELL.md)
for troubleshooting.

## 1. Record and scan the new game build

Let Steam finish updating, close the game, and run the matching command.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Compatibility.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Compatibility.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

A changed executable hash is normal after a patch. Every signature must still
have exactly one match. Zero means the implementation changed; more than one
means the pattern is ambiguous. Do not package or install either case.

`config/static-signatures/FName_Constructor.lua` is scan-only. Keep it out of
the runtime signature directory unless a future UE4SS build is proven to accept
that override.

## 2. Refresh official UE4SS and lock the game

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Refresh-Upstream.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Refresh-Upstream.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The script downloads official UE4SS release/config assets, verifies their
published SHA-256 values, scans the staged signatures against the local game,
and updates `config/upstream.lock.json`. Review every resulting diff.

## 3. Review reflected multiplayer paths

The owned source lives at
`src/Mods/FFWFrostburn8/Scripts/main.lua`. After a game update, inspect a fresh
runtime log for these items:

- `CapWrite source=GameSession ... AFTER=8`;
- `CapWrite source=Manager ... AFTER=8`;
- at least one `NativeHook registered` line;
- after creating a room, `SessionParamWrite ... WRITE=true AFTER=8`.

If the game renames a function or capacity field, add its exact reflected path
or exact field name only after confirming its meaning. Keep discovery
fail-closed; never replace an arbitrary small integer just because it currently
equals four.

Update `src/mod.json` and the `MOD_VERSION` constant together when the owned mod
changes.

## 4. Validate and build without installing

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Project.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Project.ps1
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The builder copies the tracked `src/` tree, records its deterministic tree hash,
creates a release under `dist/`, expands it again, and verifies every file. A
release containing PAK, UCAS, or UTOC files is rejected.

Build the distributable one-click installer after the source release passes.
This embeds the exact verified ZIP and runs only a read-only EXE smoke test; it
does not install or launch the game.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-InstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-InstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

Record and publish the resulting EXE's SHA-256. Local builds are unsigned; a
public release should be Authenticode-signed when a trusted certificate is
available.

After the EXE passes the isolated install/rollback test, create the flat player
download bundle. Run only the command matching the installed edition.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-DownloadBundle.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -File .\tools\Build-DownloadBundle.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

Upload the four files under `dist\release-vVERSION` as GitHub Release assets.
Do not tell players to use **Code → Download ZIP**; that archive is source only.
See [publishing a release](PUBLISHING.md).

`Install-Release.ps1` is an internal primitive and requires the expected SHA-256
of its ZIP. The public `Install-Mod.ps1` command supplies that value directly
from the just-built package so a file cannot change between build and install.

## 5. Install and perform a clean startup test

With the game closed, use the generated `Setup.exe` for the normal player path.
PowerShell remains available as the source-tree fallback below; use only the
command matching the installed edition.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

The installer takes a dated backup and refuses to write if the game is running.
Launch the game normally, create a room with **Allow mods** enabled, open
**Current Session**, then run the matching verification command.

For the v1.1.4 host-only experiment, install the mod only on the host. Every
guest must use the same game build with no `dwmapi.dll`/UE4SS mod installation.
First verify the solo `1 member + 7 Invite` tuple with
`-RequireSoloInviteUi`. Then have a fifth real player join and use
`-RequireHostOnlyHooks -RequireHostOnlyJoin -RequireFivePlayerUi`. A passing
five-player report must show the Steam lobby write, selective join-kick block,
at least five observed players, and the exact visible `5 members + 3 Invite`
tuple. Also create a separate room without **Allow mods** and confirm that
Current Session keeps the normal four-row layout.

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

Core startup can be automated, but multiplayer capacity cannot be honestly
proven with one client. Use this live matrix before removing the experimental
label:

1. Host only has v1.1.4; all guests are verified vanilla.
2. Clients 2–4 join normally.
3. Client 5 joins once by session code and once by Steam Invite.
4. Clients 6–8 join and all eight names appear.
5. The group travels to a map, advances one objective, and reconnects one guest.
6. The host manually kicks a guest to prove moderation was not suppressed.

The host log deliberately cannot prove what is installed on guest disks; record
that separately instead of treating `ObservedPlayers=5` as proof by itself.

If startup fails, close the game and restore the dated backup. Attach the fresh
UE4SS log and crash dump to the issue instead of repeatedly launching with a
failed or ambiguous signature.

## 6. Commit source changes

```powershell
git diff
git add src config docs installer tools Install-Mod.ps1 README.md CHANGELOG.md THIRD_PARTY_NOTICES.md
git commit -m "Update FFWFrostburn8 for Far Far West BUILD"
```

Do not force-add ignored content from `vendor/`, `work/`, `dist/`, or
`artifacts/`.
