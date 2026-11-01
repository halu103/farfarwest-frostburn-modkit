# v1.2.4 missile and Joker adapters (game CL 2979)

This build retains the capacity, Session UI and two host-side adapters introduced
by the official v1.2.3 release. The Lua policies and mocked UE4SS contracts are tested
offline. A real multiplayer run has not been performed for this build. The
official version/stable packaging label does not imply verified multiplayer
behavior or vanilla-client compatibility. The historical v1.2.3
`LEGACY-TEST` package does not contain these adapters.

## TNT missile with five to eight players

The current cooked `BP_TntMissileLauncher` graph already checks
`amountLeversEnabled >= 4`. It enables four real levers. The failure is in
initialization: the switch on `GameState.PlayerArray.Length` contains only
cases 0 through 4. A room of five or more selects zero defaults for
`requiredTnt` and `timeRequiredToEnableAllLevers`. Initialization repeats
every second, so a single write at BeginPlay would be overwritten.

`MissileFix.lua` repairs those broken zero defaults at the initialization's
native Delay call to the existing four-player settings: 9 TNT and 4 seconds.
It also corrects a zero duration already captured for the first-lever timer.
The game's own four-lever success check, ignition, countdown and launch remain
in charge. No fake player count or fifth lever is introduced.

The adapter requires host authority, exactly the supported missile class,
five to eight real PlayerStates, four distinct valid lever actors, an unfinished
missile and the native Delay parameter schema. Only the two decoded latent
nodes are eligible: initialization UUID `-831542045` / linkage `15`, and
first-lever timeout UUID `417648707` / linkage `2503`. Other actors and Delay
calls are unaffected. Positive existing mission settings are preserved.

## Joker reconnect in the same map

The October game already has a native reconnect path. The mod shadows its
`BP_CanyonGameInstance.playerJokersBackup` entries in host memory and retains
them when a guest leaves or disconnects. The key comes from the game's
`F_GetPlayerStateIdAsString` helper, which converts the platform network ID;
display names and transient pawn names are never used as player identity.

When the same person returns to the same map with a new PlayerState, the mod
can supply a retained complete Joker list if the native list is empty or
missing. It replaces the list rather than appending and updates the native
backup map too, so later native pickups/removals work from the restored list.
An existing nonempty native list takes precedence. Legitimately removed cards
are sampled through native backup setter hooks, including the empty list.

The fallback is restricted to `AC_PlayerStateJoker` asking for its owner's
backup. The game then assigns its replicated
`playerLocalJokersServerRetrieved` array and applies the normal client UI and
Joker-effect refresh. The mod never directly grants effects, edits save files
or invokes currency restoration. Current native death and spent-Uranium
metadata are preserved. Writes are verified; a failed transaction attempts to
restore the original output and native map entry.

The shadow resets on mission completion, return to lobby/menu, authoritative
GameState/world change, or the native GameMode's map-begin event. Replaying
the same map starts a fresh generation. Nothing is persisted across a host
restart. The adapter skips an entirely missing native backup for a player
whose retained backup says they were dead; it cannot safely decide their new
death state. Unreadable data or changed reflected schemas are also skipped.

## Validation and in-game checks

Run the engine-independent state tests and UE4SS adapter mocks with:

```powershell
pwsh.exe -NoProfile -File .\tools\Test-GameplayFixes.ps1
```

Windows PowerShell 5.1 can run the same script using `powershell.exe`. These
developer tests require Node.js/npm and use pinned Fengari CLI 0.1.0. They do
not run Far Far West, touch a game installation or prove network replication.

When a group chooses to test the built package, close the game before
installation, install on the host and create the room with Allow mods. Use a
disposable run and record Joker names/stacks/effects before leaving and after
rejoining the same map. Repeat with a network interruption. Complete the map,
start a new map and confirm the mod does not return the previous run's cards.
For the missile, test four players as a control, then five to eight players:
load TNT and activate the four levers without removing a guest from the room.
Confirm all clients see the normal countdown, one launch and normal rewards.

Host log: `<game>\FarFarWest\Binaries\Win64\ue4ss\UE4SS.log`.
Look for the startup markers `ReleaseChannel=stable` and `GameplayFixes=`,
then `MissileFix registered`, `MissileFix ...timeSeconds=0->4`,
`JokerFix hook-ready`, `JokerFix cache-reset` and, when the fallback is needed,
`JokerFix native-backup-supplied cards=N`. A successful native restore can keep
the fallback count at zero. `FFW8_Status` prints module status and counters.
Logs intentionally omit platform IDs. Seven Invite buttons alone do not
validate an eight-person room or host-only vanilla-client compatibility.

The original analysis used the CL2852 game and the installed UE5.8 engine's
script serialization definitions. For v1.2.4, relevant assets were extracted
read-only from CL2979. The missile graph still uses the same initialization
and first-lever timeout UUID/linkage pairs and four-lever completion check.
The native multiplayer backup helper, Joker component, backup struct and
GameMode exports match the previously analyzed exports byte-for-byte. The
GameInstance and multiplayer manager have changed, so their whole assets
must not be described as identical. The GameInstance's Joker setter logic
was decoded again; its backup/card/death/Uranium fields remain the same.
These static checks do not prove live UE4SS behavior or network replication.
Commercial assets and bytecode dumps remain under ignored `work/` and are not
included in the source release or installer.
