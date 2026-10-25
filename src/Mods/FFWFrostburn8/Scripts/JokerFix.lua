-- Host-side, map-scoped shadow of the game's native reconnect backup.
-- The 0.3.0.7 Blueprint contract is documented in docs/GAMEPLAY_FIXES.md.
-- No direct inventory/effect writes: the native getter's out value feeds the
-- existing replicated Joker component and its owning-client restore sequence.
local RunState = require("RunState")
local JokerFix = {}
local Adapter = {}
Adapter.__index = Adapter

local LIBRARY = "/Game/Gamework/BPFL_Multiplayer.BPFL_Multiplayer_C:"
local GAME_MODE = "/Game/Player/GM_GameMode.GM_GameMode_C:"
local INSTANCE = "/Game/Player/BP_CanyonGameInstance.BP_CanyonGameInstance_C:"
local GAME_STATE = "/Game/Player/BP_GameState.BP_GameState_C:"
local CDO = "/Game/Gamework/BPFL_Multiplayer.Default__BPFL_Multiplayer_C"
local CARDS = "jokers_3_7772715C4ACC8195044D968684F29558"
local DEAD = "dead_5_DD8FE05647F9EF2380333D883E3ECD4A"
local URANIUM = "usedUranium_8_8E09056B480E0517ABCA94B9D9C482BF"
local MAX_CARDS = 512

local function valid(object)
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function read(object, name)
    local ok, value = pcall(function() return object:GetPropertyValue(name) end)
    if ok then return value end
    return nil
end

local function remote(parameter)
    local ok, value = pcall(function() return parameter:get() end)
    if ok then return value end
    return nil
end

local function text(value)
    if type(value) == "string" then return value end
    local ok, result = pcall(function() return value:ToString() end)
    if ok and type(result) == "string" then return result end
    return nil
end

local function fullName(object)
    local ok, value = pcall(function() return object:GetFullName() end)
    if ok and type(value) == "string" then return value end
    return nil
end

local function incarnation(object)
    local name = fullName(object)
    if not name then return nil end
    -- The address distinguishes two objects whose engine-generated names were
    -- reused. It never serves as a player identity or crosses a map boundary.
    local ok, address = pcall(function() return object:GetAddress() end)
    return name .. (ok and ("@" .. tostring(address)) or "")
end

local function outerName(object)
    local ok, outer = pcall(function() return object:GetOuter() end)
    return ok and valid(outer) and fullName(outer) or nil
end

local function authority(object)
    local ok, result = pcall(function() return object:HasAuthority() end)
    return ok and result == true
end

local function arrayValues(array, convert)
    if array == nil then return nil end
    local result = {}
    local function append(value)
        if #result >= MAX_CARDS then error("array-limit") end
        local converted = convert(value)
        if converted == nil then error("unreadable-array-value") end
        result[#result + 1] = converted
    end
    local ok = pcall(function()
        if type(array) == "table" and getmetatable(array) == nil then
            for i = 1, #array do append(array[i]) end
        else
            local count = array:GetArrayNum()
            if type(count) ~= "number" or count < 0 or count > MAX_CARDS then error("array-limit") end
            array:ForEach(function(_, value)
                local unwrapped = remote(value)
                append(unwrapped ~= nil and unwrapped or value)
            end)
            if #result ~= count then error("array-incomplete") end
        end
    end)
    return ok and result or nil
end

local function cardName(value)
    local name = text(value)
    if not name or name == "" or name == "None" or #name > 256 then return nil end
    return name
end

local function snapshot(value)
    if value == nil then return nil end
    local ok, cards, dead, uranium = pcall(function()
        return arrayValues(value[CARDS], cardName), value[DEAD], value[URANIUM]
    end)
    if not ok or not cards or type(dead) ~= "boolean" or type(uranium) ~= "number"
        or uranium ~= uranium or uranium < 0 or uranium % 1 ~= 0 then return nil end
    return { cards = cards, dead = dead, usedUranium = uranium }
end

local function sameCards(a, b)
    if not a or not b or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function functionSchema(path, expected)
    local ok, fn = pcall(function() return StaticFindObject(path) end)
    if not ok or not valid(fn) then return false end
    local fields = {}
    ok = pcall(function() fn:ForEachProperty(function(field) fields[#fields + 1] = field end) end)
    if not ok or #fields < #expected then return false end
    -- Blueprint locals follow the parameter prefix. Validate ordered names and
    -- types before relying on callback positions or calling the native helper.
    for index, entry in ipairs(expected) do
        local field = fields[index]
        local checked, matches = pcall(function()
            return field:GetFName():ToString() == entry[1] and field:IsA(PropertyTypes[entry[2]])
        end)
        if not checked or matches ~= true then return false end
        if entry[1] == "BackupItems" then
            local structOk, compatible = pcall(function()
                local structure = field:GetStruct()
                local schema = {}
                structure:ForEachProperty(function(child) schema[child:GetFName():ToString()] = child end)
                local total = 0; for _ in pairs(schema) do total = total + 1 end
                return total == 3 and schema[CARDS] and schema[DEAD] and schema[URANIUM]
                    and schema[CARDS]:IsA(PropertyTypes.ArrayProperty)
                    and schema[CARDS]:GetInner():IsA(PropertyTypes.NameProperty)
                    and schema[DEAD]:IsA(PropertyTypes.BoolProperty)
                    and schema[URANIUM]:IsA(PropertyTypes.IntProperty)
            end)
            if not structOk or compatible ~= true then return false end
        end
    end
    return true
end

function JokerFix.start(options)
    local self = setmetatable({
        options = options or {}, cache = RunState.new(), hooks = {}, errors = {},
        active = false, known = {}, departed = {}, sampling = false,
        stats = { captures = 0, restores = 0, resets = 0 },
    }, Adapter)
    self:retryHooks()
    if type(NotifyOnNewObject) == "function" then
        -- A reconnecting component can query its backup on the next tick.
        -- Register as soon as its class loads rather than waiting 500 ms.
        for _, path in ipairs({ "/Game/Player/BP_PlayerState.BP_PlayerState_C",
            "/Game/Spells/Jokers/AC_PlayerStateJoker.AC_PlayerStateJoker_C" }) do
            pcall(function() NotifyOnNewObject(path, function() self:retryHooks() end) end)
        end
    end
    return {
        tick = function(gameState)
            if gameState ~= nil then self.selectedGameState = gameState end
            self:tick(self.selectedGameState)
        end,
        retryHooks = function() self:retryHooks() end,
        getStatus = function() return self:getStatus() end,
    }
end

function Adapter:log(message)
    if self.options.log then self.options.log("JokerFix " .. message) end
end

function Adapter:errorOnce(reason)
    if self.errors[reason] then return end
    self.errors[reason] = true
    self:log("skipped reason=" .. reason)
end

function Adapter:reset(reason)
    self.cache:endMap()
    self.active, self.gameState, self.scope, self.world = false, nil, nil, nil
    self.known, self.departed, self.blocked = {}, {}, false
    self.stats.resets = self.stats.resets + 1
    self:log("cache-reset reason=" .. tostring(reason))
end

function Adapter:scopePlayer(playerState)
    local classOk, class = pcall(function() return playerState:GetClass() end)
    if not classOk or fullName(class) ~= "BlueprintGeneratedClass /Game/Player/BP_PlayerState.BP_PlayerState_C" then
        return false
    end
    return (not self.options.isEnabled or self.options.isEnabled())
        and not self.blocked and self.active and valid(self.gameState) and authority(self.gameState)
        and read(self.gameState, "hasFinishedMission") == false
        and valid(playerState) and authority(playerState)
        and outerName(playerState) == self.world
end

function Adapter:library()
    if valid(self.nativeLibrary) then return self.nativeLibrary end
    local ok, object = pcall(function() return StaticFindObject(CDO) end)
    if ok and valid(object) then self.nativeLibrary = object; return object end
    return nil
end

function Adapter:identity(playerState)
    if not self.identityReady then return nil end
    local library = self:library()
    if not library then return nil end
    local result = {}
    local ok = pcall(function()
        library:F_GetPlayerStateIdAsString(playerState, playerState, result)
    end)
    local id = ok and text(result.playerId) or nil
    if not id or id == "" or id == "None" or id:upper() == "INVALID" or #id > 512
        or id:match("^%s*$") or id:match("^0+$") then return nil end
    return id
end

function Adapter:sample(playerState)
    if not self:scopePlayer(playerState) then return false end
    local library = self:library()
    if not library then return false end
    local found, backup = {}, {}
    self.sampling = true
    local ok = pcall(function()
        library:F_GetPlayerBackupItems(playerState, playerState, found, backup)
    end)
    self.sampling = false
    if not ok or found.Found ~= true then return false end
    local owned, id, connection = snapshot(backup), self:identity(playerState), incarnation(playerState)
    if not owned or not id or not connection then return false end
    self.known[connection] = { id = id, object = playerState }
    local changed = self.cache:observe(id, connection, owned, #owned.cards == 0)
    if changed then self.stats.captures = self.stats.captures + 1 end
    return changed
end

function Adapter:freeze(playerState)
    if not self:scopePlayer(playerState) then return end
    -- Current K2_OnLogout Blueprint only shows a message/refreshes session
    -- settings; sampling its native backup at the post hook precedes UObject
    -- destruction. Do not sample after marking the incarnation disconnected.
    self:sample(playerState)
    local id, connection = self:identity(playerState), incarnation(playerState)
    if id and connection then
        self.cache:disconnect(id, connection)
        self.departed[connection] = true
    end
end

function Adapter:onLookup(playerParameter, worldParameter, foundParameter, backupParameter)
    if self.sampling then return end
    local playerState = remote(playerParameter)
    if not self:scopePlayer(playerState) then return end
    local id, connection = self:identity(playerState), incarnation(playerState)
    local found, value = remote(foundParameter), remote(backupParameter)
    local current = snapshot(value)
    if not id or not connection or type(found) ~= "boolean" or not current then
        self:errorOnce("native-backup-unreadable")
        return
    end
    self.known[connection] = { id = id, object = playerState }
    if found and #current.cards > 0 then
        self.cache:observe(id, connection, current, false)
        return
    end
    -- The same getter also supplies currency/death restoration. Only the
    -- Joker component's own lookup may consume a Joker restore ticket.
    local caller = remote(worldParameter)
    local classOk, class = pcall(function() return caller:GetClass() end)
    local callerName = classOk and fullName(class) or nil
    local owner = read(caller, "playerState")
    if callerName ~= "BlueprintGeneratedClass /Game/Spells/Jokers/AC_PlayerStateJoker.AC_PlayerStateJoker_C"
        or not valid(owner) or incarnation(owner) ~= connection then
        if found then self.cache:observe(id, connection, current, true) end
        return
    end
    local retained, ticket = self.cache:restoreCandidate(id, connection, current, true)
    if not retained then
        -- A missing lookup is not evidence of an intentional inventory clear.
        -- Existing empty native backups ARE valid snapshots and must be kept.
        if found then self.cache:observe(id, connection, current, true) end
        return
    end
    if not found and retained.dead then
        self.cache:ackRestore(ticket, false)
        self:errorOnce("missing-backup-for-dead-player")
        return
    end
    local names = {}
    local nativeMap, hadNative, previousNative, mapWritten
    local ok = pcall(function()
        for i, name in ipairs(retained.cards) do names[i] = FName(name) end
        -- The native component resolves its own GameInstance before this
        -- lookup, even if the PlayerState's cached reference is not ready yet.
        local instance = read(caller, "gameInstance")
        if not valid(instance) then instance = read(playerState, "gameInstance") end
        if not valid(instance) then error("native-game-instance-unavailable") end
        nativeMap = read(instance, "playerJokersBackup")
        if nativeMap == nil then error("native-backup-map-unavailable") end
        hadNative = nativeMap:Contains(id)
        previousNative = hadNative and snapshot(nativeMap:Find(id):get()) or nil
        if hadNative and not previousNative then error("native-backup-map-unreadable") end
        if hadNative ~= found then error("native-backup-changed-during-lookup") end
        local base = previousNative or current
        if base.dead ~= current.dead or base.usedUranium ~= current.usedUranium then
            error("native-metadata-changed-during-lookup")
        end
        if #base.cards > 0 then error("late-native-restoration") end
        -- Rehydrate the game's own backup as a complete list. Future native
        -- pickup/remove setters must start with the restored cards, not an empty
        -- map entry. Preserve the current native death and currency fields.
        mapWritten = true
        nativeMap:Add(id, { [CARDS] = names, [DEAD] = base.dead, [URANIUM] = base.usedUranium })
        local mapValue = snapshot(nativeMap:Find(id):get())
        if not mapValue or not sameCards(mapValue.cards, retained.cards)
            or mapValue.dead ~= base.dead or mapValue.usedUranium ~= base.usedUranium then
            error("native-map-verification-failed")
        end
        -- UE4SS converts only keys present in this table, leaving all other
        -- native struct fields unchanged (including dead and usedUranium).
        backupParameter:set({ [CARDS] = names })
        local verified = snapshot(remote(backupParameter))
        if not verified or not sameCards(verified.cards, retained.cards)
            or verified.dead ~= current.dead or verified.usedUranium ~= current.usedUranium then
            error("out-value-verification-failed")
        end
        foundParameter:set(true)
        if remote(foundParameter) ~= true then error("found-verification-failed") end
    end)
    self.cache:ackRestore(ticket, ok)
    if ok then
        self.stats.restores = self.stats.restores + 1
        self:log("native-backup-supplied cards=" .. tostring(#retained.cards)
            .. " restores=" .. tostring(self.stats.restores))
    else
        -- Restore the original complete out value if any partial write failed.
        pcall(function()
            local originals = {}
            for i, name in ipairs(current.cards) do originals[i] = FName(name) end
            backupParameter:set({ [CARDS] = originals })
            foundParameter:set(found)
        end)
        local rollbackRead, outputRestored = pcall(function()
            local check = snapshot(remote(backupParameter))
            return check ~= nil and sameCards(check.cards, current.cards)
                and check.dead == current.dead and check.usedUranium == current.usedUranium
                and remote(foundParameter) == found
        end)
        if not rollbackRead or outputRestored ~= true then
            self.blocked = true
            self:errorOnce("output-rollback-unverified-disabled-until-map-end")
        end
        if mapWritten then
            local rolledBack = pcall(function()
                if hadNative then
                    local originalNames = {}
                    for i, name in ipairs(previousNative.cards) do originalNames[i] = FName(name) end
                    nativeMap:Add(id, { [CARDS] = originalNames, [DEAD] = previousNative.dead,
                        [URANIUM] = previousNative.usedUranium })
                else nativeMap:Remove(id) end
                if nativeMap:Contains(id) ~= hadNative then error("rollback-presence-mismatch") end
                if hadNative then
                    local check = snapshot(nativeMap:Find(id):get())
                    if not check or not sameCards(check.cards, previousNative.cards)
                        or check.dead ~= previousNative.dead or check.usedUranium ~= previousNative.usedUranium then
                        error("rollback-value-mismatch")
                    end
                end
            end)
            if not rolledBack then
                self.blocked = true
                self:errorOnce("rollback-unverified-disabled-until-map-end")
            end
        end
        self:errorOnce("native-backup-write-failed")
    end
end

function Adapter:hook(path, expected, callback)
    if self.hooks[path] then return true end
    if not functionSchema(path, expected) then return false end
    -- These game Blueprint UFunctions execute UE4SS callbacks after the body.
    local ok, pre, post = pcall(function()
        return RegisterHook(path, function(...)
            local succeeded = pcall(callback, ...)
            if not succeeded then self:errorOnce("hook-callback-failed:" .. path) end
        end)
    end)
    if ok and type(pre) == "number" and type(post) == "number" then
        self.hooks[path] = { pre, post }
        self:log("hook-ready function=" .. path)
    end
    return self.hooks[path] ~= nil
end

function Adapter:retryHooks()
    self.identityReady = functionSchema(LIBRARY .. "F_GetPlayerStateIdAsString",
        { { "PlayerState", "ObjectProperty" }, { "__WorldContext", "ObjectProperty" }, { "playerId", "StrProperty" } })
    self:hook(LIBRARY .. "F_GetPlayerBackupItems",
        { { "PlayerState", "ObjectProperty" }, { "__WorldContext", "ObjectProperty" },
          { "Found", "BoolProperty" }, { "BackupItems", "StructProperty" } },
        function(_, player, world, found, backup) self:onLookup(player, world, found, backup) end)
    self:hook(GAME_MODE .. "K2_OnLogout", { { "ExitingController", "ObjectProperty" } }, function(_, controller)
        self:freeze(read(remote(controller), "PlayerState"))
    end)
    self:hook(GAME_MODE .. "ReceiveBeginPlay", {}, function(context)
        local mode = remote(context)
        if not valid(mode) or not authority(mode) then return end
        self:reset("native-map-begin")
        local ok, state = pcall(function() return mode:GetWorld():GetPropertyValue("GameState") end)
        if ok then self.selectedGameState = state; self:tick(state) end
    end)
    self:hook(GAME_STATE .. "OnRep_hasFinishedMission", {}, function(context)
        local state = remote(context)
        if valid(state) and authority(state) and incarnation(state) == self.scope
            and read(state, "hasFinishedMission") == true then self:reset("mission-finished") end
    end)
    for _, name in ipairs({ "F_BackupSetter_AddJoker", "F_BackupSetter_RemoveJoker" }) do
        local cardParameter = name == "F_BackupSetter_AddJoker" and "Joker" or "joker"
        self:hook(INSTANCE .. name, { { "playerId", "StrProperty" }, { cardParameter, "NameProperty" } }, function(_, playerId)
            local id = text(remote(playerId))
            if not id then return end
            for connection, entry in pairs(self.known) do
                if entry.id == id and not self.departed[connection] then self:sample(entry.object) end
            end
        end)
    end
end

function Adapter:tick(gameState)
    self:retryHooks()
    if self.options.isEnabled and not self.options.isEnabled() then
        if self.active then self:reset("disabled") end
        return
    end
    if not valid(gameState) or not authority(gameState) then
        if self.active then self:reset("no-authoritative-world") end
        return
    end
    local name, key, world = fullName(gameState), incarnation(gameState), outerName(gameState)
    if not name or not key or not world then return end
    local lower = name:lower()
    if lower:find("l_lobby", 1, true) or lower:find("titlescreen", 1, true)
        or lower:find("splashscreen", 1, true) or read(gameState, "hasFinishedMission") ~= false then
        if self.active then self:reset("map-ended-or-lobby") end
        return
    end
    if not self.active or self.scope ~= key then
        self:reset("world-generation-changed")
        self.scope, self.world, self.gameState, self.active = key, world, gameState, true
        self.cache:beginMap(key, key)
    end
    local players = arrayValues(read(gameState, "PlayerArray"), function(value)
        return valid(value) and value or nil
    end)
    if not players then return end
    local present = {}
    for _, playerState in ipairs(players) do
        local connection = incarnation(playerState)
        if connection and not self.departed[connection] then
            present[connection] = true
            self:sample(playerState)
        end
    end
    for connection, entry in pairs(self.known) do
        if not present[connection] and not self.departed[connection] then
            self.cache:disconnect(entry.id, connection)
            self.departed[connection] = true
        end
    end
end

function Adapter:getStatus()
    return { active = self.active, captures = self.stats.captures, restores = self.stats.restores,
        resets = self.stats.resets, blocked = self.blocked == true,
        lookupHook = self.hooks[LIBRARY .. "F_GetPlayerBackupItems"] ~= nil }
end

return JokerFix
