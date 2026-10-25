-- Offline native-backup/UE4SS contract simulation; no game or saves are used.
package.path = "src/Mods/FFWFrostburn8/Scripts/?.lua;" .. package.path
local JokerFix = require("JokerFix")
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local LIB = "/Game/Gamework/BPFL_Multiplayer.BPFL_Multiplayer_C:"
local MODE = "/Game/Player/GM_GameMode.GM_GameMode_C:"
local GS = "/Game/Player/BP_GameState.BP_GameState_C:"
local GI = "/Game/Player/BP_CanyonGameInstance.BP_CanyonGameInstance_C:"
local CARDS = "jokers_3_7772715C4ACC8195044D968684F29558"
local DEAD = "dead_5_DD8FE05647F9EF2380333D883E3ECD4A"
local URANIUM = "usedUranium_8_8E09056B480E0517ABCA94B9D9C482BF"
PropertyTypes = { ObjectProperty = "object", StrProperty = "string", NameProperty = "name",
    BoolProperty = "bool", StructProperty = "struct", ArrayProperty = "array", IntProperty = "int" }
FName = function(name) return { ToString = function() return name end } end
local function name(value) return type(value) == "string" and value or value:ToString() end
local function backup(cards, dead, uranium)
    return { [CARDS] = cards or {}, [DEAD] = dead == true, [URANIUM] = uranium or 0 }
end
local function copy(value)
    local cards = {}; for i, card in ipairs(value[CARDS]) do cards[i] = name(card) end
    return backup(cards, value[DEAD], value[URANIUM])
end
local function field(label, kind, structure, inner)
    return { GetFName = function() return FName(label) end,
        IsA = function(_, expected) return expected == kind end,
        GetStruct = function() return structure end, GetInner = function() return inner end }
end
local structure = { ForEachProperty = function(_, cb)
    cb(field(CARDS, "array", nil, field("inner", "name")))
    cb(field(DEAD, "bool")); cb(field(URANIUM, "int"))
end }
local schemas = {
    [LIB .. "F_GetPlayerStateIdAsString"] = { field("PlayerState", "object"), field("__WorldContext", "object"), field("playerId", "string") },
    [LIB .. "F_GetPlayerBackupItems"] = { field("PlayerState", "object"), field("__WorldContext", "object"), field("Found", "bool"), field("BackupItems", "struct", structure) },
    [MODE .. "K2_OnLogout"] = { field("ExitingController", "object") },
    [MODE .. "ReceiveBeginPlay"] = {}, [GS .. "OnRep_hasFinishedMission"] = {},
    [GI .. "F_BackupSetter_AddJoker"] = { field("playerId", "string"), field("Joker", "name") },
    [GI .. "F_BackupSetter_RemoveJoker"] = { field("playerId", "string"), field("joker", "name") },
}
local serial = 0
local function object(full, values, outer)
    serial = serial + 1
    local item = { values = values or {}, address = serial, authority = true }
    function item:IsValid() return self.invalid ~= true end
    function item:GetFullName() return full end
    function item:GetAddress() return self.address end
    function item:HasAuthority() return self.authority end
    function item:GetPropertyValue(key) return self.values[key] end
    function item:GetOuter() return outer end
    return item
end
local function remote(value, setter)
    return { get = function() return value end, set = function(_, new) if setter then setter(new) end; value = new end }
end

local function scenario()
    local env = { hooks = {}, records = {}, writes = 0, logs = {}, enabled = true }
    local level = object("Level /Game/Levels/L_Run.L_Run:PersistentLevel")
    env.state = object("BP_GameState_C /Game/Levels/L_Run.L_Run:PersistentLevel.State", { PlayerArray = {}, hasFinishedMission = false }, level)
    env.world = object("World /Game/Levels/L_Run.L_Run", { GameState = env.state })
    env.mode = object("GM_GameMode_C /Game/Levels/L_Run.L_Run:PersistentLevel.Mode")
    function env.mode:GetWorld() return env.world end
    env.instance = object("BP_CanyonGameInstance_C /Engine/Transient.Instance")
    env.map = {}
    function env.map:Contains(id) return env.records[id] ~= nil end
    function env.map:Find(id)
        if not env.records[id] then error("missing key") end
        return { get = function() return copy(env.records[id]) end }
    end
    function env.map:Add(id, value)
        env.writes = env.writes + 1
        env.records[id] = copy(value)
        if env.corruptWrite then env.records[id][CARDS] = {} end
    end
    function env.map:Remove(id) env.records[id] = nil end
    env.instance.values.playerJokersBackup = env.map
    local library = object("BPFL_Multiplayer_C /Game/Gamework/BPFL_Multiplayer.Default__BPFL_Multiplayer_C")
    function library:F_GetPlayerStateIdAsString(player, _, output) output.playerId = player.id end
    function library:F_GetPlayerBackupItems(player, context, found, value)
        local exists = env.records[player.id] ~= nil
        found.Found = exists
        local source = copy(env.records[player.id] or backup())
        for key, child in pairs(source) do value[key] = child end
        local hook = env.hooks[LIB .. "F_GetPlayerBackupItems"]
        if hook then
            local out = { get = function() return value end, set = function(_, update)
                if env.stuckOutput then
                    if not env.outputWasTouched then
                        for key, child in pairs(update) do value[key] = child end
                        env.outputWasTouched = true
                    end
                    error("injected partial write and failed rollback")
                end
                if env.failOutput then env.failOutput = false; error("injected out failure") end
                for key, child in pairs(update) do value[key] = child end
            end }
            local outFound = { get = function() return found.Found end, set = function(_, new) found.Found = new end }
            hook(remote(library), remote(player), remote(context), outFound, out)
        end
    end
    StaticFindObject = function(path)
        if path == "/Game/Gamework/BPFL_Multiplayer.Default__BPFL_Multiplayer_C" then return library end
        local fields = schemas[path]
        if not fields then return nil end
        return { IsValid = function() return true end,
            ForEachProperty = function(_, cb) for _, item in ipairs(fields) do cb(item) end end }
    end
    RegisterHook = function(path, callback) env.hooks[path] = callback; return 1, 2 end
    env.module = JokerFix.start({ log = function(line) env.logs[#env.logs + 1] = line end,
        isEnabled = function() return env.enabled end })
    function env:player(id, label)
        local player = object("BP_PlayerState_C /Game/Levels/L_Run.L_Run:PersistentLevel." .. label,
            { gameInstance = self.instance }, level)
        player.id = id
        function player:GetClass()
            return object(self.classOverride or "BlueprintGeneratedClass /Game/Player/BP_PlayerState.BP_PlayerState_C")
        end
        return player
    end
    function env:component(player)
        local result = object("AC_PlayerStateJoker_C component", { playerState = player })
        function result:GetClass() return object("BlueprintGeneratedClass /Game/Spells/Jokers/AC_PlayerStateJoker.AC_PlayerStateJoker_C") end
        return result
    end
    function env:lookup(player, context)
        local found, value = {}, {}
        library:F_GetPlayerBackupItems(player, context or self:component(player), found, value)
        return found.Found, copy(value)
    end
    function env:tick(players)
        self.state.values.PlayerArray = players
        self.module.tick(self.state)
    end
    function env:leave(player)
        local controller = object("Controller test", { PlayerState = player })
        self.hooks[MODE .. "K2_OnLogout"](remote(self.mode), remote(controller))
        self:tick({})
    end
    function env:seed(cards, dead)
        local player = self:player("eos:verified-id", "one")
        self.records[player.id] = backup(cards or { "joker-a", "joker-a", "joker-b" }, dead, 5)
        self:tick({ player })
        self:leave(player)
        return player
    end
    return env
end

local env = scenario()
local old = env:seed()
eq(env.module.getStatus().lookupHook, true, "native getter hook registered")
env.records[old.id] = backup({}, true, 17)
local rejoined = env:player(old.id, "two")
env:tick({ rejoined })
local found, value = env:lookup(rejoined)
eq(found, true, "return native backup to Joker component")
eq(#value[CARDS], 3, "full list restored")
eq(value[CARDS][1], "joker-a", "card identity preserved")
eq(value[CARDS][2], "joker-a", "duplicate stack represented exactly")
eq(value[DEAD], true, "current native death metadata preserved")
eq(value[URANIUM], 17, "current native currency metadata preserved")
eq(#env.records[old.id][CARDS], 3, "native backup map rehydrated for future pickups")
eq(env.records[old.id][DEAD], true, "native map death metadata preserved")
eq(env.records[old.id][URANIUM], 17, "native map currency metadata preserved")
local writes = env.writes
env:lookup(rejoined)
eq(env.writes, writes, "repeated getter does not append or reapply shadow")
eq(env.module.getStatus().restores, 1, "once per PlayerState incarnation")
env.records[old.id][CARDS][4] = "joker-c"
env.hooks[GI .. "F_BackupSetter_AddJoker"](remote(env.instance), remote(old.id), remote(FName("joker-c")))
env:leave(rejoined)
env.records[old.id] = backup()
local third = env:player(old.id, "three"); env:tick({ third })
found, value = env:lookup(third)
eq(#value[CARDS], 4, "second reconnect includes newly acquired native card")
eq(value[CARDS][4], "joker-c", "new card never replaces restored old list")

env = scenario(); old = env:seed(); env.records[old.id] = nil
rejoined = env:player(old.id, "two"); env:tick({ rejoined })
found, value = env:lookup(rejoined, rejoined)
eq(found, false, "currency or unrelated native getter caller unchanged")
eq(env.module.getStatus().restores, 0, "unrelated caller cannot consume restore")
found, value = env:lookup(rejoined)
eq(found, true, "missing native entry supplied to Joker component")
eq(#value[CARDS], 3, "missing native map retains cards")
eq(value[URANIUM], 0, "missing native currency defaults preserved")

env = scenario(); old = env:seed(); env.records[old.id] = nil
rejoined = env:player(old.id, "two"); env:tick({ rejoined })
local component = env:component(rejoined)
component.values.gameInstance = env.instance
rejoined.values.gameInstance = nil
found, value = env:lookup(rejoined, component)
eq(#value[CARDS], 3, "component GameInstance supports early PlayerState startup")

env = scenario(); old = env:seed(); env.records[old.id] = backup({ "native-card" }, false, 9)
rejoined = env:player(old.id, "two"); env:tick({ rejoined })
found, value = env:lookup(rejoined)
eq(#value[CARDS], 1, "native restoration wins without merging")
eq(value[CARDS][1], "native-card", "native card kept")
eq(env.module.getStatus().restores, 0, "nonempty native state not rewritten")

env = scenario(); old = env:player("eos:verified-id", "one")
env.records[old.id] = backup({ "spent-card" }); env:tick({ old })
env.records[old.id] = backup()
env.hooks[GI .. "F_BackupSetter_RemoveJoker"](remote(env.instance), remote(old.id), remote(FName("spent-card")))
env:leave(old)
rejoined = env:player(old.id, "two"); env:tick({ rejoined })
found, value = env:lookup(rejoined)
eq(#value[CARDS], 0, "intentionally removed cards never resurrected")
eq(env.module.getStatus().restores, 0, "empty live state respected")

env = scenario(); old = env:seed(); env.records[old.id] = nil
local other = env:player("eos:different-id", "same-display-name"); env:tick({ other })
found, value = env:lookup(other)
eq(found, false, "different stable ID never receives cards")
eq(#value[CARDS], 0, "display names unused")

env = scenario(); old = env:seed(); env.records[old.id] = nil
env.state.values.hasFinishedMission = true
env.hooks[GS .. "OnRep_hasFinishedMission"](remote(env.state))
eq(env.module.getStatus().active, false, "mission end clears active cache immediately")
rejoined = env:player(old.id, "two"); env:tick({ rejoined })
found, value = env:lookup(rejoined)
eq(found, false, "finished mission cannot restore retained cards")

env = scenario(); old = env:seed(); env.records[old.id] = nil
local replacement = object(env.state:GetFullName(), { PlayerArray = {}, hasFinishedMission = false }, env.state:GetOuter())
env.state = replacement; env.world.values.GameState = replacement
rejoined = env:player(old.id, "two"); env:tick({ rejoined })
found = env:lookup(rejoined)
eq(found, false, "replayed same map with new GameState cannot inherit cards")

env = scenario(); old = env:seed(); env.records[old.id] = nil
env.hooks[MODE .. "ReceiveBeginPlay"](remote(env.mode))
rejoined = env:player(old.id, "two"); env:tick({ rejoined })
found = env:lookup(rejoined)
eq(found, false, "native map begin resets even when world name reused")

env = scenario(); old = env:seed(); env.records[old.id] = backup({}, false, 13)
rejoined = env:player(old.id, "two"); env:tick({ rejoined }); env.failOutput = true
found, value = env:lookup(rejoined)
eq(#value[CARDS], 0, "failed OUT write rolls back output")
eq(#env.records[old.id][CARDS], 0, "failed OUT write rolls back native map")
eq(env.records[old.id][URANIUM], 13, "rollback preserves currency")
eq(env.module.getStatus().restores, 0, "failed restoration not acknowledged")
found, value = env:lookup(rejoined)
eq(#value[CARDS], 3, "verified retry remains possible")

env = scenario(); old = env:seed(); env.records[old.id] = backup()
rejoined = env:player(old.id, "two"); env:tick({ rejoined }); env.stuckOutput = true
env:lookup(rejoined)
eq(env.module.getStatus().blocked, true, "unverified output rollback disables restoration for this map")
eq(#env.records[old.id][CARDS], 0, "native map still rolled back when output rollback fails")
eq(env.module.getStatus().restores, 0, "partial output never acknowledged as restored")

env = scenario(); old = env:seed(nil, true); env.records[old.id] = nil
rejoined = env:player(old.id, "two"); env:tick({ rejoined })
found = env:lookup(rejoined)
eq(found, false, "missing death backup fails closed for previously dead player")

env = scenario(); old = env:seed(); env.records[old.id] = nil
rejoined = env:player(old.id, "two"); rejoined.authority = false; env:tick({ rejoined })
found = env:lookup(rejoined)
eq(found, false, "client PlayerState cannot modify authoritative backup")

env = scenario(); old = env:seed(); env.records[old.id] = nil
rejoined = env:player(old.id, "two"); rejoined.classOverride = "BlueprintGeneratedClass SomeOtherActor"
env:tick({ rejoined }); found = env:lookup(rejoined)
eq(found, false, "reused or unrelated actor cannot be treated as a PlayerState")

local saved = schemas[LIB .. "F_GetPlayerBackupItems"][3]
schemas[LIB .. "F_GetPlayerBackupItems"][3] = field("ChangedFound", "bool")
env = scenario()
eq(env.module.getStatus().lookupHook, false, "changed native parameter schema refused")
schemas[LIB .. "F_GetPlayerBackupItems"][3] = saved
print("JokerFix offline checks passed: " .. checks)
