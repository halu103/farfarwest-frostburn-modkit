-- CL2852's TNT missile graph enables four levers and checks >= 4. Its setup
-- selects TNT/time values only for player counts 0..4; 5+ takes zero defaults.
-- The setup repeats before its own Delay(1), so repair those two scalar defaults
-- inside that native call, before the next game tick/lever interaction.
-- No ignition/completion function, player roster, or lever count is changed.
local MissileFix = {}
local CLASS_PATH = "/Game/Objectives/Assets/TntMissile/BP_TntMissileLauncher.BP_TntMissileLauncher_C"
local DELAY_PATH = "/Script/Engine.KismetSystemLibrary:Delay"
local INIT_UUID = -831542045
local LEVER_UUID = 417648707
local LEVER_COUNT = 4
local FOUR_PLAYER_TNT = 9
local FOUR_PLAYER_SECONDS = 4

local function valid(object)
    if object == nil then return false end
    local ok, value = pcall(function() return object:IsValid() end)
    return ok and value == true
end

local function unwrap(parameter)
    local ok, value = pcall(function() return parameter:get() end)
    if ok then return value end
end

local function property(object, name)
    local ok, value = pcall(function() return object:GetPropertyValue(name) end)
    if ok then return value end
end

local function nameOf(object)
    local ok, value = pcall(function() return object:GetFullName() end)
    if ok and type(value) == "string" then return value end
end

local function propertyType(field, expected)
    local ok, result = pcall(function() return field:IsA(PropertyTypes[expected]) end)
    return ok and result == true
end

local function schemaMatches(fn)
    local ok, matches = pcall(function()
        local fields = {}
        fn:ForEachProperty(function(field) fields[#fields + 1] = field end)
        if #fields ~= 3 then return false end
        if fields[1]:GetFName():ToString() ~= "WorldContextObject"
            or not propertyType(fields[1], "ObjectProperty")
            or fields[2]:GetFName():ToString() ~= "Duration"
            or not propertyType(fields[2], "FloatProperty")
            or fields[3]:GetFName():ToString() ~= "LatentInfo"
            or not propertyType(fields[3], "StructProperty") then return false end
        local structure = fields[3]:GetStruct()
        if nameOf(structure) ~= "ScriptStruct /Script/Engine.LatentActionInfo" then return false end
        local found = {}
        structure:ForEachProperty(function(field)
            local name = field:GetFName():ToString()
            if name == "UUID" or name == "Linkage" then found[name] = propertyType(field, "IntProperty") end
        end)
        return found.UUID == true and found.Linkage == true
    end)
    return ok and matches == true
end

function MissileFix.start(options)
    assert(type(options) == "table" and type(options.getPlayerCount) == "function", "MissileFix needs getPlayerCount")
    local state = { registered = false, normalizations = 0, timeoutCorrections = 0 }
    local reported = {}
    local function log(message)
        if type(options.log) == "function" then options.log("MissileFix " .. message) end
    end
    local function once(key, message)
        if not reported[key] then reported[key] = true; log(message) end
    end
    local function supportedActor(actor)
        if not valid(actor) then return nil end
        if type(options.isEnabled) == "function" then
            local ok, enabled = pcall(options.isEnabled, actor)
            if not ok or enabled ~= true then return nil end
        end
        local classOk, class = pcall(function() return actor:GetClass() end)
        if not classOk or nameOf(class) ~= "BlueprintGeneratedClass " .. CLASS_PATH then return nil end
        local authorityOk, authority = pcall(function() return actor:HasAuthority() end)
        if not authorityOk or authority ~= true or property(actor, "hasBlown") ~= false then return nil end
        local countOk, players = pcall(options.getPlayerCount, actor)
        if not countOk or type(players) ~= "number" or players % 1 ~= 0 or players < 5 or players > 8 then return nil end
        local levers = property(actor, "levers")
        local leverOk, count = pcall(function() return levers:GetArrayNum() end)
        if not leverOk or count ~= LEVER_COUNT then return nil end
        local seen = {}
        for index = 1, count do
            local readOk, lever = pcall(function() return levers[index] end)
            local leverName = readOk and valid(lever) and nameOf(lever)
            if not leverName or seen[leverName] then return nil end
            seen[leverName] = true
        end
        return players
    end
    local function setVerified(actor, field, value)
        local ok = pcall(function() actor:SetPropertyValue(field, value) end)
        return ok and property(actor, field) == value
    end
    local function normalize(actor, players)
        local actorName = nameOf(actor) or "<unknown>"
        local seconds = property(actor, "timeRequiredToEnableAllLevers")
        local tnt = property(actor, "requiredTnt")
        -- Only the decoded missing-case zero values are repaired. Positive values
        -- from the game or other mods retain their original behavior.
        if type(seconds) == "number" and seconds <= 0 then
            if setVerified(actor, "timeRequiredToEnableAllLevers", FOUR_PLAYER_SECONDS) then
                state.normalizations = state.normalizations + 1
                once(actorName .. ":time", string.format("players=%d timeSeconds=%s->4 nativeRequiredLevers=4", players, tostring(seconds)))
            else once(actorName .. ":time-error", "ERROR failed to verify timeRequiredToEnableAllLevers write") end
        end
        if tnt == 0 then
            if setVerified(actor, "requiredTnt", FOUR_PLAYER_TNT) then
                state.normalizations = state.normalizations + 1
                -- The graph marks requiredTnt dirty just before its Delay call.
                -- The host will replicate the corrected final value. Refresh
                -- local text through the same helper used by OnRep_requiredTnt.
                pcall(function() actor:F_UpdatePlaceDynamiteText() end)
                pcall(function() actor:ForceNetUpdate() end)
                once(actorName .. ":tnt", string.format("players=%d requiredTnt=0->9 four-player-baseline", players))
            else once(actorName .. ":tnt-error", "ERROR failed to verify requiredTnt write") end
        end
    end
    local function beforeDelay(_, worldParameter, durationParameter, latentParameter)
        local actor = unwrap(worldParameter)
        if not valid(actor) then return end
        local latent = unwrap(latentParameter)
        local readOk, uuid, linkage = pcall(function() return latent.UUID, latent.Linkage end)
        if not readOk then return end
        local initialization = uuid == INIT_UUID and linkage == 15
        local leverTimeout = uuid == LEVER_UUID and linkage == 2503
        if not initialization and not leverTimeout then return end
        local players = supportedActor(actor)
        if not players then return end
        normalize(actor, players)
        if not leverTimeout then return end
        local duration = unwrap(durationParameter)
        local enabled = property(actor, "leversEnabled")
        local progress = property(actor, "amountLeversEnabled")
        if enabled ~= true or type(progress) ~= "number" or progress < 1 or progress >= LEVER_COUNT
            or type(duration) ~= "number" or duration > 0 or duration ~= duration then return end
        -- Duration was evaluated before this native PRE hook. Correct that
        -- captured zero too, rather than scheduling an immediate failed attempt.
        local correctedDuration = property(actor, "timeRequiredToEnableAllLevers")
        if type(correctedDuration) ~= "number" or correctedDuration <= 0 or correctedDuration ~= correctedDuration then return end
        local writeOk = pcall(function() durationParameter:set(correctedDuration) end)
        if writeOk and unwrap(durationParameter) == correctedDuration then
            state.timeoutCorrections = state.timeoutCorrections + 1
            once((nameOf(actor) or "?") .. ":timeout", "first-lever zero timeout=0->" .. tostring(correctedDuration) .. " native success transition retained")
        else once("timeout-error", "ERROR failed to verify native Delay duration write") end
    end
    function state.retryHooks()
        if state.registered then return true end
        local foundOk, fn = pcall(function() return StaticFindObject(DELAY_PATH) end)
        if not foundOk or not valid(fn) then return false end
        if not schemaMatches(fn) then
            once("schema", "disabled reason=native-Delay-schema-mismatch")
            return false
        end
        local ok, preId, postId = pcall(function()
            return RegisterHook(DELAY_PATH, function(...)
                local callbackOk, err = pcall(beforeDelay, ...)
                if not callbackOk then once("callback-error", "ERROR callback=" .. tostring(err)) end
            end)
        end)
        if not ok or type(preId) ~= "number" or type(postId) ~= "number" then
            once("registration", "ERROR native-Delay-hook-registration-failed")
            return false
        end
        state.registered, state.preId, state.postId = true, preId, postId
        log("registered CL2852 four-lever timing fix; no forced ignition")
        return true
    end
    state.retryHooks()
    return state
end

return MissileFix
