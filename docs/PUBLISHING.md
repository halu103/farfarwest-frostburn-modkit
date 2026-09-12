# Publishing the player build

The GitHub repository serves two different audiences:

- **Code → Download ZIP** is an automatically generated source archive for
  developers. It should not contain the compiled installer.
- **Releases → Assets** contains the ready-to-run player build.

Do not commit the EXE or generated ZIP into the source tree. They contain the
pinned UE4SS runtime, are much larger than source, and become stale whenever
the game or mod changes. `dist/` therefore remains ignored by Git.

## 1. Build and test locally

Build on a Windows machine that has the exact supported Far Far West version.
The commercial game executable must never be uploaded to GitHub, Actions,
secrets, or caches.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-InstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-InstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-DownloadBundle.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

PowerShell 7+:

```powershell
pwsh.exe -NoLogo -NoProfile -File .\tools\Build-InstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
pwsh.exe -NoLogo -NoProfile -File .\tools\Test-InstallerExe.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
pwsh.exe -NoLogo -NoProfile -File .\tools\Build-DownloadBundle.ps1 `
  -GameRoot "D:\SteamLibrary\steamapps\common\FarFarWest"
```

The final upload directory is:

```text
dist\release-v1.1.4\
  FFWFrostburn8-Setup.exe
  FFWFrostburn8-Setup.exe.sha256.txt
  FFWFrostburn8-Windows-x64.zip
  FFWFrostburn8-Windows-x64.zip.sha256.txt
```

Inside `FFWFrostburn8-Windows-x64.zip` there is no nested directory. A player
extracts it and immediately sees:

```text
FFWFrostburn8-Setup.exe
README-VI.txt
SHA256SUMS.txt
LICENSE.txt
THIRD-PARTY-NOTICES.txt
```

The bundle builder uses that exact five-file allowlist, reopens the ZIP,
verifies every file hash, checks the installer is x64/versioned correctly, and
runs its read-only compatibility mode before packaging. It does not install or
launch the game.

## 2. Create the GitHub Release

On `https://github.com/halu103/farfarwest-frostburn-modkit`:

1. Open **Releases** and choose **Draft a new release**.
2. Create a version tag such as `v1.1.4-host-only-experimental-ffw-0.2.0.20-cl915` from the reviewed
   commit.
3. Use a title such as `FFWFrostburn8 v1.1.4 Host-Only Experimental — Far Far West 0.2.0.20 CL 915`.
4. Upload all four files from `dist\release-v1.1.4` as Release assets.
5. Put both SHA-256 values and the supported game version in the release notes.
6. State that the build is unsigned, only the host should install it for this
   experiment, and vanilla-client compatibility is still unverified.
7. Publish it as a **prerelease** until clean clients 5–8, map travel, an
   objective, reconnect, and manual kick have all passed.

Do not upload the raw game executable, `vendor/`, `work/`, or the raw source
release ZIP. The installer already embeds the verified runtime payload.

## 3. Stable player link

Because the downloadable asset keeps a stable filename, the README link does
not change between versions:

```text
https://github.com/halu103/farfarwest-frostburn-modkit/releases/latest/download/FFWFrostburn8-Windows-x64.zip
```

GitHub updates this URL to the most recent non-prerelease release. The version
tag, release notes, installer version, embedded manifest, and strict game-build
check still prevent an old or incompatible build from silently installing.

GitHub-hosted Actions cannot produce the same fully verified build because
they do not have the commercial game. Keep local verified release generation,
or use a carefully secured self-hosted Windows runner later; do not weaken the
game SHA/AOB checks merely to make hosted CI turn green.
