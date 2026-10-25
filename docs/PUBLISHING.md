# Publishing the official v1.2.3 player build

Official v1.2.3 uses the `stable` packaging channel and targets Far Far West
`0.3.0.7 - CL 2852`. It retains capacity/Invite behavior and includes the
missile/Joker adapters. The release label does not change the evidence:
multiplayer gameplay, eight-player EOS sessions and host-only vanilla guests
remain unverified. State those limits in the release notes.

The earlier v1.2.3 `legacy-runtime-preview` package is historical and does not
contain the adapters. Preserve its existing tag, assets and checksums. Do not
overwrite an old published asset just because its numeric mod version matches.

The repository serves two different audiences:

- **Code → Download ZIP** contains source for developers, not the installer.
- **Releases → Assets** contains the ready-to-run player build.

Keep generated EXEs/ZIPs under ignored `dist/`, not committed to the source
tree. They embed the pinned UE4SS runtime and must be rebuilt when source or
the compatibility lock changes.

## 1. Build and test locally

Use a Windows machine with the exact supported game. Never upload the
commercial game executable, extracted assets or bytecode dumps to GitHub,
Actions, secrets or caches.

Check the current terminal first:

```powershell
$PSVersionTable.PSEdition
$PSVersionTable.PSVersion
```

Windows PowerShell reports `Desktop` / `5.1`; PowerShell 7 reports `Core` /
`7.x`. The script calls below run in either supported terminal, without
requiring the other edition's executable. If process execution-policy handling
is needed, reopen the chosen terminal with `powershell.exe -NoProfile -ExecutionPolicy Bypass`
for 5.1, or `pwsh.exe -NoProfile -ExecutionPolicy Bypass` for 7+. This does not
change the machine-wide policy. See [PowerShell compatibility](POWERSHELL.md).

From the project root, use a **new explicit output directory** so legacy and
official builds are not mixed. The name below is for the official CL2852 build;
choose a fresh suffix if preserving an earlier build at the same path.

```powershell
$releaseRoot = Join-Path (Get-Location).Path 'dist\release-v1.2.3'
$gameRoot = 'D:\SteamLibrary\steamapps\common\FarFarWest'
$setupPath = Join-Path $releaseRoot 'FarFarWest-Frostburn-0.3.0.7-CL2852-FFWFrostburn8-v1.2.3-Setup.exe'
$uninstallPath = Join-Path $releaseRoot 'FarFarWest-Frostburn-0.3.0.7-CL2852-FFWFrostburn8-v1.2.3-Uninstall.exe'

& .\tools\Test-Project.ps1
& .\tools\Test-GameplayFixes.ps1
& .\tools\Build-InstallerExe.ps1 -GameRoot $gameRoot -OutputDirectory $releaseRoot
& .\tools\Build-UninstallerExe.ps1 -GameRoot $gameRoot -OutputDirectory $releaseRoot
& .\tools\Test-InstallerExe.ps1 -GameRoot $gameRoot -InstallerPath $setupPath
& .\tools\Test-UninstallerExe.ps1 -GameRoot $gameRoot -InstallerPath $setupPath -UninstallerPath $uninstallPath
```

The gameplay policy/adapter tests require Node.js/npm and pinned Fengari CLI
0.1.0. Run the installer and uninstaller sandbox tests sequentially because
they share an installer mutex. These tests operate on isolated fixtures; they
do not install into or launch the real game.

The four upload files are in `dist\release-v1.2.3\`, just like the earlier
standalone EXE releases:

```text
FarFarWest-Frostburn-0.3.0.7-CL2852-FFWFrostburn8-v1.2.3-Setup.exe
FarFarWest-Frostburn-0.3.0.7-CL2852-FFWFrostburn8-v1.2.3-Setup.exe.sha256.txt
FarFarWest-Frostburn-0.3.0.7-CL2852-FFWFrostburn8-v1.2.3-Uninstall.exe
FarFarWest-Frostburn-0.3.0.7-CL2852-FFWFrostburn8-v1.2.3-Uninstall.exe.sha256.txt
```

The Setup EXE already embeds the complete mod payload. Do not run
`Build-DownloadBundle.ps1` for this normal workflow: a separate ZIP is optional,
not a prerequisite or another mod dependency. Both EXE builders run read-only
verification; the sandbox tests check install/uninstall and rollback. They do
not install into or launch the real game. Update
[the v1.2.3 test report](TEST_REPORT_1.2.3.md) with the exact new artifact hashes;
do not reuse hashes from a preview or legacy build.

## 2. Create the GitHub Release

On [the project repository](https://github.com/halu103/farfarwest-frostburn-modkit):

1. Review and commit the source used for the build, then draft a new release.
2. Use a new tag such as `v1.2.3` if that tag does not already exist. Otherwise
   use `v1.2.3-official` only if that tag is unused too. Never move or replace
   a previously published legacy tag without an explicit migration.
3. Use a title such as `FFWFrostburn8 v1.2.3 — Far Far West 0.3.0.7 CL 2852`.
4. Upload the four files from `dist/release-v1.2.3`, not the old `LEGACY-TEST`
   ZIP, raw source package, or build-intermediate directories.
5. Include the supported game build, new SHA-256 values, changes and known
   runtime limits. Say the EXEs are unsigned; no antivirus or Nexus approval
   is implied by a successful local build.
6. For the requested official release, publish it as a normal, non-prerelease
   release and explicitly select **Set as the latest release** if appropriate.
   Keep host-only and gameplay-validation caveats in the notes. Publishing as
   stable is a distribution choice, not evidence that untested scenarios work.

The website can only show public, published releases and their uploaded assets.
A local build, draft, private asset, or pushed source commit alone does not add
a public download. Verify the public Release page and asset URLs after upload.

## 3. Stable and legacy download links

If a ZIP bundle is optionally published, its stable filename link is:

```text
https://github.com/halu103/farfarwest-frostburn-modkit/releases/latest/download/FFWFrostburn8-Windows-x64.zip
```

That URL resolves through GitHub's latest normal release; it does not enumerate
prereleases or legacy packages and fails if that release lacks the exact
filename. Standalone-only releases do not need to make this optional ZIP URL
work. Keep downloads linked to each release's actual EXE assets rather than
substituting or guessing a ZIP URL.

The website must enumerate the releases API (including legacy/prerelease
entries) and use each asset's actual `browser_download_url`. Do not guess
legacy asset names from the stable filename. A missing GitHub response should
show a retry/fallback link, not imply that no releases exist.

GitHub-hosted Actions cannot reproduce the fully game-verified package without
the commercial executable. Keep verified release generation local or use a
secured self-hosted Windows runner; do not weaken the game SHA/AOB checks to
make hosted CI appear green.
