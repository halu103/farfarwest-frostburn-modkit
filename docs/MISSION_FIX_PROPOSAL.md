# TNT missile objective: implementation boundary

Historical September hypothesis, superseded for game 0.3.0.7 CL2852: full
bytecode decoding found an existing four-lever success threshold and missing
5+ initialization cases yielding a zero-second timer. Official v1.2.3 repairs the
verified initialization/timer nodes and does not force ignition. See
[the current implementation](GAMEPLAY_FIXES.md).

Reported reproduction: in a five-player room, four people held all four TNT-missile levers and ignition did not start. After a guest left, four remaining players operated the same four levers and ignition started. The existing v1.2.2 game log establishes the five-to-four transition and that the TNT-missile level was loaded, but did not record lever state. This is a strong clue, **not a verified decompilation of the blocking condition**.

The game's UE5.8 cooked `BP_TntMissileLauncher` package has reflected names `PlayerArray`, `CallFunc_Array_Length_ReturnValue`, `CallFunc_GreaterEqual_IntInt_ReturnValue`, `amountLeversEnabled`, `levers`, `leversEnabled`, `leverState`, `F_EnableLevers`, and `F_StartIgnition`. `F_StartIgnition` appears as a zero-parameter, `BlueprintCallable`/`BlueprintEvent` UFunction stub. The available asset conversion does not decode this package's event graph reliably: the main graph is raw and `F_EnableLevers` reports an impossible bytecode size. Thus neither the exact condition nor the correct transition action can be asserted from the asset names alone.

If a **separately labelled experimental build** is made, the narrowest Lua-side candidate is a one-shot host-authority action on the live `BP_TntMissileLauncher_C` actor when all of these are true:

- The current game build and UE4SS signatures match the compatibility lock; Allow Mods is confirmed for the active room through a reliable source. Do **not** rely on `hostOnlyRoomGate` alone: the v1.2.2 log shows it repeatedly alternating `armed`/`disarmed` as session UI widgets are scanned, and the room-creation hook was not registered.
- The live GameState `PlayerArray` count is between five and eight, the missile actor has server authority, `levers` has **exactly four** valid lever actors, each reports `isPulled == true`, and `amountLeversEnabled == 4` if runtime inspection confirms that field means active levers. Any unreadable field must fail closed.
- The condition persists across at least two game-thread observations; the actor has not already been acted on; ignition has not already started or completed according to a verified actor state; all checks and action execute on the game thread.
- Prefer the game's own transition function over mutating `PlayerArray` or forging a fifth lever count. The candidate `F_StartIgnition` must first be verified at runtime to be the same function the normal four-player success path invokes. Without that verification, calling it could skip prerequisites or fire twice.

For runtime verification, instrument the same actor in a four-player disposable run and observe `F_EnableLevers`/`F_StartIgnition` hook callbacks, lever properties, and replicated objective state through the transition. Repeat with five players. Confirm all clients see exactly one ignition, objective completion, and rewards, then test six to eight players separately. Do not ask a guest to Leave/Back as the way to complete this mission. Do not ship or advertise a successful fix on syntax/static checks alone.

UE4SS's [official `RegisterHook` documentation](https://docs.ue4ss.com/lua-api/global-functions/registerhook.html) says Blueprint UFunction callbacks are post-execution and the UFunction must already be in memory when registered. Therefore hook registration needs a deferred retry after the class loads, and a post-hook cannot safely be used as a precondition override. [The UObject Lua API](https://docs.ue4ss.com/lua-api/classes/uobject.html) supports reflected property access and UFunction invocation, but that API capability does not prove the game's mission semantics.
