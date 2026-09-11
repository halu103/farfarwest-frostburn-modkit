# One-click Windows installer

The generated `Setup.exe` is the recommended installation path for players.
It is a native Windows GUI application: it does not invoke PowerShell and does
not download another multiplayer mod. The complete verified release ZIP is
embedded in the executable.

For players, publish `FFWFrostburn8-Windows-x64.zip` as a GitHub Release asset.
That download has a flat layout, so `FFWFrostburn8-Setup.exe` is visible
immediately after extraction. Do not direct players to GitHub's automatically
generated source archive. See [publishing](PUBLISHING.md).

## Install without PowerShell

1. Close Far Far West.
2. Double-click the release file ending in `Setup.exe`.
3. Check the detected game folder. Select the root `FarFarWest` folder only if
   Steam detection chose the wrong location.
4. Click **Install / Cài** and confirm.
5. Start the game normally, create a room, and tick **Allow mods**.

Version 1.1.3 expands the Session list only when the room's **Allow mods**
status is active. With one host it should show seven Invite buttons; with five
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
a supported local game build. It does not prove that five through eight real
network clients can join. In game, **Current Session** should show eight rows
(one host plus seven invite rows while alone). A fifth real player joining is
the proof that the original four-player limit was exceeded; all eight real
players must join to claim a complete eight-player test.

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

Use `$PSVersionTable.PSEdition` and `$PSVersionTable.PSVersion` to choose the
correct maintainer command. See [PowerShell compatibility](POWERSHELL.md) for
details.
