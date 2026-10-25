-- Offline contract tests: no game process, game files, or player saves are used.
local MissileFix = dofile("src/Mods/FFWFrostburn8/Scripts/MissileFix.lua")
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
PropertyTypes = { ObjectProperty = "object", FloatProperty = "float", StructProperty = "struct", IntProperty = "int" }
local function field(name, kind, structure)
    return {
        GetFName = function() return { ToString = function() return name end } end,
        IsA = function(_, value) return value == kind end,
        GetStruct = function() return structure end,
    }
end
local latentStruct = {
    GetFullName = function() return "ScriptStruct /Script/Engine.LatentActionInfo" end,
    ForEachProperty = function(_, cb) cb(field("UUID", "int")); cb(field("Linkage", "int")) end,
}
local functionFields = { field("WorldContextObject", "object"), field("Duration", "float"), field("LatentInfo", "struct", latentStruct) }
local fn = {
    IsValid = function() return true end,
    ForEachProperty = function(_, cb) for _, f in ipairs(functionFields) do cb(f) end end,
}
local hook
local available = true
StaticFindObject = function(path)
    eq(path, "/Script/Engine.KismetSystemLibrary:Delay", "only verified native hook")
    return available and fn or nil
end
RegisterHook = function(path, cb) hook = cb; return 7, 8 end
local players = 5
local enabled = true
local function lever(index)
    return { IsValid = function() return true end, GetFullName = function() return "BP_Lever_C lever" .. index end }
end
local function actor()
    local levers = { lever(1), lever(2), lever(3), lever(4) }
    levers.GetArrayNum = function(self) return #self end
    local a = {
        values = { hasBlown = false, requiredTnt = 0, timeRequiredToEnableAllLevers = 0, leversEnabled = true, amountLeversEnabled = 1, levers = levers },
        authority = true, updates = 0, names = "BlueprintGeneratedClass /Game/Objectives/Assets/TntMissile/BP_TntMissileLauncher.BP_TntMissileLauncher_C",
    }
    function a:IsValid() return true end
    function a:GetFullName() return "BP_TntMissileLauncher_C test" end
    function a:GetClass() return { GetFullName = function() return self.names end } end
    function a:HasAuthority() return self.authority end
    function a:GetPropertyValue(key) return self.values[key] end
    function a:SetPropertyValue(key, value) if not self.failWrites then self.values[key] = value end end
    function a:F_UpdatePlaceDynamiteText() self.updates = self.updates + 1 end
    function a:ForceNetUpdate() self.netUpdates = (self.netUpdates or 0) + 1 end
    function a:F_StartIgnition() error("must not force ignition") end
    function a:F_TakeOff_Server() error("must not force launch") end
    return a
end
local function remote(value)
    return { get = function(self) return self.value end, set = function(self, new) self.value = new end, value = value }
end
local function invoke(a, duration, uuid, linkage)
    local d = remote(duration)
    hook(remote(nil), remote(a), d, remote({ UUID = uuid or -831542045, Linkage = linkage or 15 }))
    return d.value
end
local state = MissileFix.start({ getPlayerCount = function() return players end, isEnabled = function() return enabled end })
eq(state.registered, true, "registered")
local a = actor()
eq(invoke(a, 1), 1, "setup Delay(1) preserved")
eq(a.values.requiredTnt, 9, "five players use four-player TNT baseline")
eq(a.values.timeRequiredToEnableAllLevers, 4, "five players use four-player time window")
eq(a.updates, 1, "refresh local TNT text")
eq(a.netUpdates, 1, "request replication of corrected TNT")
-- Native initialization is a one-second loop, not a one-off BeginPlay event.
a.values.requiredTnt, a.values.timeRequiredToEnableAllLevers = 0, 0
invoke(a, 1)
eq(a.values.requiredTnt, 9, "repeated native setup remains repaired")
eq(a.values.timeRequiredToEnableAllLevers, 4, "repeated native time setup remains repaired")
eq(invoke(a, 0, 417648707, 2503), 4, "captured first-lever zero delay corrected before scheduling")
eq(state.timeoutCorrections, 1, "verified timeout correction counted")
for count = 1, 8 do
    players = count
    local candidate = actor()
    invoke(candidate, 1)
    eq(candidate.values.timeRequiredToEnableAllLevers, count >= 5 and 4 or 0, "player boundary " .. count)
end
players = 9
local candidate = actor(); invoke(candidate, 1)
eq(candidate.values.requiredTnt, 0, "unknown room layout above eight untouched")
players = 5
local function unchanged(label, mutate)
    local candidate = actor(); mutate(candidate)
    invoke(candidate, 1)
    eq(candidate.values.requiredTnt, 0, label)
end
unchanged("client untouched", function(a) a.authority = false end)
unchanged("completed actor untouched", function(a) a.values.hasBlown = true end)
unchanged("unknown completion state untouched", function(a) a.values.hasBlown = nil end)
unchanged("different class untouched", function(a) a.names = "BlueprintGeneratedClass Other" end)
unchanged("missing lever untouched", function(a) a.values.levers[4] = nil end)
unchanged("duplicate lever untouched", function(a) a.values.levers[4] = a.values.levers[3] end)
enabled = false; unchanged("feature gate off", function() end); enabled = true
candidate = actor(); candidate.values.requiredTnt, candidate.values.timeRequiredToEnableAllLevers = 12, 7
invoke(candidate, 1)
eq(candidate.values.requiredTnt, 12, "positive game TNT variation preserved")
eq(candidate.values.timeRequiredToEnableAllLevers, 7, "positive game timing variation preserved")
eq(invoke(candidate, 0, 417648707, 2503), 7, "captured timeout follows positive game timing variation")
candidate = actor(); candidate.failWrites = true; invoke(candidate, 1)
eq(candidate.values.requiredTnt, 0, "unverified write not treated as successful")
eq(invoke(actor(), 0, 417648708, 2503), 0, "different delay UUID untouched")
eq(invoke(actor(), 0, 417648707, 2504), 0, "different graph linkage untouched")
eq(invoke(actor(), 2, 417648707, 2503), 2, "positive timeout preserved")
candidate = actor(); candidate.values.amountLeversEnabled = 4
eq(invoke(candidate, 0, 417648707, 2503), 0, "all-four success uses native graph")
candidate = actor(); candidate.values.leversEnabled = false
eq(invoke(candidate, 0, 417648707, 2503), 0, "inactive lever phase untouched")
candidate = actor(); candidate.values.amountLeversEnabled = 0
eq(invoke(candidate, 0, 417648707, 2503), 0, "no lever attempt untouched")
-- Absent native UFunction is retried after loading, and schema mismatch fails closed.
available = false
local waiting = MissileFix.start({ getPlayerCount = function() return 5 end })
eq(waiting.registered, false, "unloaded function waits")
available = true
eq(waiting.retryHooks(), true, "retry hook after function loads")
local saved = functionFields[2]
functionFields[2] = field("ChangedDuration", "float")
local incompatible = MissileFix.start({ getPlayerCount = function() return 5 end })
eq(incompatible.registered, false, "changed native schema fails closed")
functionFields[2] = saved
print("MissileFix offline checks passed: " .. checks)
