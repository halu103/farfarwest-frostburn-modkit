# PowerShell compatibility

Players using the release `Setup.exe` do not need PowerShell. Double-click the
EXE and follow the installer window; see [one-click installer](INSTALLER.md).
The commands below are for installing from source, maintenance, verification,
or restoring an older backup.

Far Far West is a Windows game, and this modkit supports these two Windows
PowerShell editions:

| Edition | Version | Executable | Status |
| --- | --- | --- | --- |
| Windows PowerShell (`Desktop`) | 5.1 | `powershell.exe` | Supported and tested |
| PowerShell (`Core`) | 7.x | `pwsh.exe` | Supported and tested; recommended |

PowerShell 7 is recommended for maintainers because its GitHub/TLS behavior is
more consistent. It is a separate installation; Windows does not replace
`powershell.exe` when PowerShell 7 is installed.

## Identify the terminal

Run this inside the PowerShell window:

```powershell
$PSVersionTable.PSEdition
$PSVersionTable.PSVersion
```

Use `powershell.exe` only when the result is `Desktop 5.1`. Use `pwsh.exe` when
the result is `Core 7.x`. Do not run both installers for one update.

## Install from source

First close Far Far West, then change to the repository directory.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1
```

If Steam auto-detection fails, append the explicit game path to the matching
command:

```powershell
-GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The installer refuses to write while `FarFarWest-Win64-Shipping.exe` is
running. It never starts or closes the game.

## Verify the runtime log

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

## Restore a backup

Replace `INSTALL-TIMESTAMP` with the directory printed by the installer.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Restore-Backup.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -BackupDirectory ".\artifacts\backups\INSTALL-TIMESTAMP"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Restore-Backup.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest" `
  -BackupDirectory ".\artifacts\backups\INSTALL-TIMESTAMP"
```

## Common errors

### `pwsh.exe` is not recognized

PowerShell 7 is not installed or is not on `PATH`. Use the Windows PowerShell
5.1 command, or install PowerShell 7 from Microsoft before using `pwsh.exe`.

### Script execution is disabled

Run the complete command shown above, including
`-ExecutionPolicy Bypass -File`. The bypass is process-scoped and does not
change the permanent machine or user policy.

### GitHub download or TLS error in Windows PowerShell 5.1

Retry with PowerShell 7+. Do not disable certificate validation. If the
verified UE4SS archive is already cached under `vendor/cache/`, the installer
does not need to download it again.

### The script opens in an editor instead of running

Do not double-click `Install-Mod.ps1`. Open a PowerShell terminal in the
repository and invoke the matching executable command above.
