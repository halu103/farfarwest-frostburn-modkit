-- FFWFrostburn8 is an independent, source-owned UE4SS mod for Far Far West.
-- It raises only multiplayer capacity. It does not include cooked game assets,
-- enemy scaling, fake players, or code from another multiplayer mod.

local MOD_ID = "FFWFrostburn8"
local MOD_VERSION = "1.0.0"
local TARGET_MAX_PLAYERS = 8
local TAG = string.format("[%s v%s]", MOD_ID, MOD_VERSION)

local trackedSessions = {}
local trackedManagers = {}
local trackedGameStates = {}
local hookedFunctions = {}
local describedFunctions = {}
local lastObservedPlayers = -1
local sessionCapApplied = false
local managerCapApplied = false
local nativeHookCount = 0

local function log(message)
    print(string.format("%s %s\n", TAG, message))
end

local function logError(scope, value)
    log(string.format("ERROR scope=%s detail=%s", scope, tostring(value)))
end

local function isValid(object)
    if object == nil then
        return false
    end

    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    return ok and valid == true
end

local function getObjectName(object)
    local ok, name = pcall(function()
        return object:GetFullName()
    end)
    if ok then
        return tostring(name)
    end
    return "<unknown>"
end

local function remember(collection, object)
    if not isValid(object) then
        return
    end
    collection[getObjectName(object)] = object
end

local function setObjectCap(object, source, collection)
    if not isValid(object) then
        return false
    end

    if collection ~= nil then
        remember(collection, object)
    end

    local readOk, before = pcall(function()
        return object:GetPropertyValue("MaxPlayers")
    end)
    if not readOk or type(before) ~= "number" then
        return false
    end

    local writeOk = true
    if before ~= TARGET_MAX_PLAYERS then
        writeOk = pcall(function()
            object:SetPropertyValue("MaxPlayers", TARGET_MAX_PLAYERS)
        end)
    end

    local verifyOk, after = pcall(function()
        return object:GetPropertyValue("MaxPlayers")
    end)
    local applied = writeOk and verifyOk and after == TARGET_MAX_PLAYERS

    if before ~= TARGET_MAX_PLAYERS then
        log(string.format(
            "CapWrite source=%s object=%s property=MaxPlayers BEFORE=%s WRITE=%s AFTER=%s",
            source,
            getObjectName(object),
            tostring(before),
            tostring(applied),
            tostring(after)
        ))
    end

    if source:find("GameSession", 1, true) then
        sessionCapApplied = sessionCapApplied or applied
    elseif source:find("Manager", 1, true) then
        managerCapApplied = managerCapApplied or applied
    end

    return applied
end

local function observePlayers(gameState)
    if not isValid(gameState) then
        return
    end

    remember(trackedGameStates, gameState)
    local ok, count = pcall(function()
        local players = gameState:GetPropertyValue("PlayerArray")
        return players:GetArrayNum()
    end)
    if ok and type(count) == "number" and count ~= lastObservedPlayers then
        lastObservedPlayers = count
        log(string.format("ObservedPlayers=%d", count))
    end
end

local function applyTrackedCaps()
    for name, object in pairs(trackedSessions) do
        if isValid(object) then
            setObjectCap(object, "GameSession/cached", nil)
        else
            trackedSessions[name] = nil
        end
    end

    for name, object in pairs(trackedManagers) do
        if isValid(object) then
            setObjectCap(object, "Manager/cached", nil)
        else
            trackedManagers[name] = nil
        end
    end

    for name, object in pairs(trackedGameStates) do
        if isValid(object) then
            observePlayers(object)
        else
            trackedGameStates[name] = nil
        end
    end
end

local function scanClass(className, callback)
    local ok, objects = pcall(function()
        return FindAllOf(className)
    end)
    if not ok or objects == nil then
        return 0
    end

    local count = 0
    for _, object in pairs(objects) do
        if isValid(object) then
            count = count + 1
            callback(object)
        end
    end
    return count
end

local function scanExisting(reason)
    local sessions = scanClass("GameSession", function(object)
        setObjectCap(object, "GameSession/" .. reason, trackedSessions)
    end)
    local managers = scanClass("BP_Manager_Multiplayer_C", function(object)
        setObjectCap(object, "Manager/" .. reason, trackedManagers)
    end)
    scanClass("GameStateBase", observePlayers)

    if sessions > 0 or managers > 0 then
        log(string.format("Scan reason=%s sessions=%d managers=%d", reason, sessions, managers))
    end
end

local capacityNames = {
    maxplayers = true,
    maxmembers = true,
    maxpublicconnections = true,
    numpublicconnections = true,
    publicconnections = true,
}

local function propertyName(property)
    local ok, value = pcall(function()
        return property:GetFName():ToString()
    end)
    if ok then
        return tostring(value)
    end
    return "<unknown>"
end

local function isIntProperty(property)
    local ok, result = pcall(function()
        return property:IsA(PropertyTypes.IntProperty)
    end)
    return ok and result == true
end

local function isStructProperty(property)
    local ok, result = pcall(function()
        return property:IsA(PropertyTypes.StructProperty)
    end)
    return ok and result == true
end

local function collectCapacityTargets(fn)
    local targets = {}
    local schema = {}
    local parameterIndex = 0

    fn:ForEachProperty(function(property)
        parameterIndex = parameterIndex + 1
        local name = propertyName(property)
        table.insert(schema, name)

        if isIntProperty(property) and capacityNames[name:lower()] then
            table.insert(targets, {
                index = parameterIndex,
                parameter = name,
                field = nil,
            })
        elseif isStructProperty(property) then
            local structOk, struct = pcall(function()
                return property:GetStruct()
            end)
            if structOk and struct ~= nil then
                pcall(function()
                    struct:ForEachProperty(function(field)
                        local fieldName = propertyName(field)
                        if isIntProperty(field) and capacityNames[fieldName:lower()] then
                            table.insert(targets, {
                                index = parameterIndex,
                                parameter = name,
                                field = fieldName,
                            })
                        end
                    end)
                end)
            end
        end
    end)

    return targets, schema
end

local function normalizeFunctionPath(fn)
    local ok, fullName = pcall(function()
        return fn:GetFullName()
    end)
    if not ok then
        return nil
    end
    return tostring(fullName):gsub("^Function%s+", "")
end

local function setHookTarget(remoteParam, target, functionPath)
    if remoteParam == nil then
        return
    end

    if target.field == nil then
        local readOk, before = pcall(function()
            return remoteParam:get()
        end)
        local writeOk = pcall(function()
            remoteParam:set(TARGET_MAX_PLAYERS)
        end)
        local verifyOk, after = pcall(function()
            return remoteParam:get()
        end)
        log(string.format(
            "SessionParamWrite function=%s parameter=%s BEFORE=%s WRITE=%s AFTER=%s",
            functionPath,
            target.parameter,
            readOk and tostring(before) or "<unreadable>",
            tostring(writeOk and verifyOk and after == TARGET_MAX_PLAYERS),
            verifyOk and tostring(after) or "<unreadable>"
        ))
        return
    end

    local getOk, value = pcall(function()
        return remoteParam:get()
    end)
    if not getOk or value == nil then
        return
    end
    local readOk, before = pcall(function()
        return value[target.field]
    end)
    local writeOk = pcall(function()
        value[target.field] = TARGET_MAX_PLAYERS
    end)
    local verifyOk, after = pcall(function()
        return value[target.field]
    end)
    log(string.format(
        "SessionParamWrite function=%s parameter=%s.%s BEFORE=%s WRITE=%s AFTER=%s",
        functionPath,
        target.parameter,
        target.field,
        readOk and tostring(before) or "<unreadable>",
        tostring(writeOk and verifyOk and after == TARGET_MAX_PLAYERS),
        verifyOk and tostring(after) or "<unreadable>"
    ))
end

local function registerCapacityHook(fn)
    local functionPath = normalizeFunctionPath(fn)
    if functionPath == nil or hookedFunctions[functionPath] then
        return false
    end

    local lowerPath = functionPath:lower()
    local sessionAction = lowerPath:find("session", 1, true) or lowerPath:find("lobby", 1, true)
    local capacityAction = lowerPath:find("create", 1, true) or lowerPath:find("update", 1, true)
    if not sessionAction or not capacityAction or not functionPath:find("^/Script/") then
        return false
    end

    local inspectOk, targets, schema = pcall(function()
        local foundTargets, foundSchema = collectCapacityTargets(fn)
        return foundTargets, foundSchema
    end)
    if not inspectOk then
        if not describedFunctions[functionPath] then
            describedFunctions[functionPath] = true
            logError("InspectFunction " .. functionPath, targets)
        end
        return false
    end

    if #targets == 0 then
        if not describedFunctions[functionPath] then
            describedFunctions[functionPath] = true
            log(string.format("SessionFunction observed path=%s schema=%s capTarget=none", functionPath, table.concat(schema, ",")))
        end
        return false
    end

    local hookOk, preId, postId = pcall(function()
        return RegisterHook(functionPath, function(_, ...)
            local parameters = {...}
            for _, target in ipairs(targets) do
                setHookTarget(parameters[target.index], target, functionPath)
            end
        end)
    end)
    if not hookOk then
        if not describedFunctions[functionPath] then
            describedFunctions[functionPath] = true
            logError("RegisterHook " .. functionPath, preId)
        end
        return false
    end

    hookedFunctions[functionPath] = { preId = preId, postId = postId }
    nativeHookCount = nativeHookCount + 1
    local targetNames = {}
    for _, target in ipairs(targets) do
        table.insert(targetNames, target.field and (target.parameter .. "." .. target.field) or target.parameter)
    end
    log(string.format("NativeHook registered path=%s targets=%s", functionPath, table.concat(targetNames, ",")))
    return true
end

local knownFunctionPaths = {
    "/Script/FarFarWest.OnlineBlueprintAsyncCreate:MP_CreateSessionWithSettings",
    "/Script/FarFarWest.MultiplayerStatics:MP_UpdateSession",
    "/Script/OnlineSubsystemUtils.CreateSessionCallbackProxy:CreateSession",
}

local knownClassPaths = {
    "/Script/FarFarWest.OnlineBlueprintAsyncCreate",
    "/Script/FarFarWest.MultiplayerStatics",
    "/Script/OnlineSubsystemUtils.CreateSessionCallbackProxy",
}

local function discoverCapacityHooks()
    for _, path in ipairs(knownFunctionPaths) do
        local ok, fn = pcall(function()
            return StaticFindObject(path)
        end)
        if ok and isValid(fn) then
            registerCapacityHook(fn)
        end
    end

    for _, path in ipairs(knownClassPaths) do
        local ok, class = pcall(function()
            return StaticFindObject(path)
        end)
        if ok and isValid(class) then
            pcall(function()
                class:ForEachFunction(function(fn)
                    registerCapacityHook(fn)
                end)
            end)
        end
    end
end

local function printStatus(reason)
    log(string.format(
        "Status reason=%s target=%d sessionCapApplied=%s managerCapApplied=%s nativeHooks=%d observedPlayers=%d",
        reason,
        TARGET_MAX_PLAYERS,
        tostring(sessionCapApplied),
        tostring(managerCapApplied),
        nativeHookCount,
        lastObservedPlayers
    ))
end

local function registerObjectNotifications()
    local ok, value = pcall(function()
        NotifyOnNewObject("/Script/Engine.GameSession", function(object)
            setObjectCap(object, "GameSession/new", trackedSessions)
        end)
        NotifyOnNewObject("/Script/Engine.GameStateBase", function(object)
            observePlayers(object)
        end)
        NotifyOnNewObject("/Game/Gamework/BP_Manager_Multiplayer.BP_Manager_Multiplayer_C", function(object)
            setObjectCap(object, "Manager/new", trackedManagers)
            discoverCapacityHooks()
        end)
    end)
    if ok then
        log("Object notifications registered")
    else
        logError("ObjectNotifications", value)
    end
end

local function registerGameStateHook()
    local ok, value = pcall(function()
        RegisterInitGameStatePostHook(function()
            ExecuteInGameThreadWithDelay(50, function()
                scanExisting("InitGameStatePost")
                discoverCapacityHooks()
                printStatus("InitGameStatePost")
            end)
        end)
    end)
    if ok then
        log("InitGameState post hook registered")
    else
        logError("InitGameStatePostHook", value)
    end
end

local function registerConsoleCommand()
    local ok, value = pcall(function()
        RegisterConsoleCommandHandler("FFW8_Status", function()
            scanExisting("Console")
            discoverCapacityHooks()
            printStatus("Console")
            return true
        end)
    end)
    if not ok then
        logError("ConsoleCommand", value)
    end
end

log(string.format("Mod loaded - v%s", MOD_VERSION))
log(string.format("Target MaxPlayers=%d", TARGET_MAX_PLAYERS))
log("Implementation=source-owned-lua cookedAssets=false")

registerObjectNotifications()
registerGameStateHook()
registerConsoleCommand()

ExecuteInGameThreadWithDelay(100, function()
    scanExisting("Startup100ms")
    discoverCapacityHooks()
end)
ExecuteInGameThreadWithDelay(1500, function()
    scanExisting("Startup1500ms")
    discoverCapacityHooks()
    printStatus("Startup1500ms")
end)
ExecuteInGameThreadWithDelay(5000, function()
    scanExisting("Startup5000ms")
    discoverCapacityHooks()
    printStatus("Startup5000ms")
end)

LoopInGameThreadWithDelay(1000, function()
    applyTrackedCaps()
end)
