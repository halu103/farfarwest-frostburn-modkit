# One-click Windows installer and uninstaller

The generated `Setup.exe` is the recommended installation path for players.
It is a native Windows GUI application: it does not invoke PowerShell and does
not download another multiplayer mod. The complete verified release ZIP is
embedded in the executable.

For players, publish `FFWFrostburn8-Windows-x64.zip` as a GitHub Release asset.
That download has a flat layout, so `FFWFrostburn8-Setup.exe` and
`FFWFrostburn8-Uninstall.exe` are visible immediately after extraction. Do not
direct players to GitHub's automatically generated source archive. See
[publishing](PUBLISHING.md).

## Install without PowerShell

1. Close Far Far West.
2. Double-click the release file ending in `Setup.exe`.
3. Check the detected game folder. Select the root `FarFarWest` folder only if
   Steam detection chose the wrong location.
4. Click **Install / Cài** and confirm.
5. Start the game normally, create a room, and tick **Allow mods**.

Version 1.2.2 is a **host-only experimental** build. Install it on the host
only; test guests must use the same game version with no UE4SS/mod installation.
It captures the room's **Allow mods** choice during room creation so a temporary
widget-visibility race cannot collapse the interface to the vanilla three
Invite buttons. With one host it should show seven Invite buttons; with five
real players it should show five member names and three Invite buttons. A room
created without **Allow mods** should retain the game's normal four-row UI.

The installer never launches, closes, or restarts the game. It refuses to
write if either Far Far West process is running. It validates the exact game
version, executable SHA-256, compatibility signatures, embedded release hash,
package manifest, and owned Lua source hash before changing game files. After
copying, it compares every installed file with the embedded release.

The install replaces `dwmapi.dll` and the complete `ue4ss` folder. Existing
UE4SS mods are backed up but are not automatically merged or kept active. The
three exact legacy `ZZZ_FFWMorePlayers_P` cooked files are also backed up and
removed because they are incompatible with the Frostburn/UE 5.8 build.

Backups and logs are stored outside the game:

```text
%LOCALAPPDATA%\FFWFrostburn8\Backups
%LOCALAPPDATA%\FFWFrostburn8\Logs
```

If a write or verification fails, the installer attempts an automatic
rollback before reporting the error. Keep the backup directory shown in the
success dialog if you may want to return to the previous UE4SS setup later.

## Uninstall without PowerShell

1. Close Far Far West.
2. Run `FFWFrostburn8-Uninstall.exe` from the extracted release bundle.
3. Verify the detected game folder.
4. Leave **Advanced** clear, click **Uninstall / Gỡ**, and confirm.

The recommended mode verifies that the active installation belongs to this
project, creates and verifies an additional safety backup, then removes only
`ue4ss\Mods\FFWFrostburn8` and `ue4ss\FARFARWEST_MODKIT_MANIFEST.json`. It does
not remove `dwmapi.dll`, the complete `ue4ss` directory, its configuration, or
unrelated mods. A failure triggers an automatic restore from the safety backup.
This mode works even if Setup was first run over an older/manual copy and every
historical backup already contains FFWFrostburn8.

The unchecked-by-default **Advanced** option instead selects the newest clean
pre-install snapshot, validates every recorded hash, and restores the complete
managed state. It stops before writing if that snapshot is missing or damaged.
Because a full snapshot replacement can revert UE4SS changes or unrelated mods
added later, use it only when deliberately returning to that older state.

Neither mode requires the game executable to remain on the old supported
version, so the mod can still be removed after a game update.

## Windows security notice

Local development builds are not Authenticode-signed and Windows SmartScreen
may show an unknown-publisher warning. Compare the file's SHA-256 with the hash
published for that release or its generated `.sha256.txt` sidecar. Do not
disable Defender or certificate checks. A future public release should be
code-signed before broad distribution.

The installer runs with the current user's permissions. Most Steam libraries
are writable without elevation. If Windows reports access denied for a Steam
library under a protected directory, close the installer and run that exact
verified installer as administrator; do not weaken folder-wide security.

## What a successful install proves

A successful installer result proves that the correct files were installed on
a supported local host build. It does not prove that unmodified clients can
join or remain synchronized. In game, **Current Session** should show eight rows
(one host plus seven invite rows while alone). A fifth real player joining is
the proof that the original four-player limit was exceeded; all eight real
players must join to claim a complete eight-player test.

For a valid host-only test, verify that every guest has neither `dwmapi.dll`
nor a `ue4ss` folder in the game's `Binaries\Win64` directory. Join clients
2–4, then the fifth through both session code and Steam Invite, then clients
6–8. Also test map travel, an objective, reconnect, and a manual host kick.
Keep the release labelled experimental until all of those checks pass.

## Build the installer from source

Maintainers need PowerShell only to build the distributable EXE. End users do
not need it. Close the game before a compatibility build.

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

The builder supports the .NET Framework 4.8 compiler already present on many
Windows systems; a separate .NET SDK is not required. It first builds and
round-trip verifies the release ZIP, embeds that exact ZIP, compiles an x64
WinForms executable, then runs the EXE's read-only `--verify-only` mode. The
smoke test never launches the game or installs game files.

For a complete isolated install-and-rollback test, keep the real game closed
and run the matching command. The script copies only the locked game
executable into `work/installer-e2e`; all installation and backup writes stay
inside that disposable sandbox.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-InstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -File .\tools\Test-InstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The PowerShell 7 command automatically delegates only the .NET Framework
reflection harness to built-in Windows PowerShell 5.1. The generated installer
itself remains native and does not invoke PowerShell.

Build and test the standalone uninstaller with the matching edition:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-UninstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-UninstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+ uses `pwsh.exe` with the same script paths. The tests install and
uninstall only inside `work/uninstaller-e2e`; they exercise clean-snapshot,
legacy-upgrade, and missing-backup histories, preserve unrelated mods, corrupt
a backup, and inject failures into both removal modes to prove complete rollback.

Use `$PSVersionTable.PSEdition` and `$PSVersionTable.PSVersion` to choose the
correct maintainer command. See [PowerShell compatibility](POWERSHELL.md) for
details.
