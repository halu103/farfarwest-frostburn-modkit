# Third-party notices

## RE-UE4SS

The build tooling downloads release assets from
[UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS).
The tracked Far Far West compatibility files originate from that project and
are used under its MIT license.

Baseline compatibility commit:
`5b2663e955a2dfa15d7d960415dc737608dc676d`.

## More Players Mod

More Players Mod is created by Ettokun and distributed through Nexus Mods.
Its Lua and cooked Unreal assets are not part of this source repository.
The build script accepts a user-supplied local archive and verifies its hash.

Do not publish the generated package or the original Nexus archive unless the
mod author grants permission.

## Far Far West

Far Far West and its executable/assets belong to their respective owners.
No game files are included in this repository. The compatibility scanner reads
a locally installed executable only to calculate a hash and locate byte
signatures; it does not launch or modify the game.
