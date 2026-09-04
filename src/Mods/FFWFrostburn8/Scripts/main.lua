-- FFWFrostburn8 is an independent, source-owned UE4SS mod for Far Far West.
-- It raises multiplayer capacity and expands the live Session list to eight
-- rows. It does not include cooked game assets, enemy scaling, fake players,
-- or code from another multiplayer mod.

local MOD_ID = "FFWFrostburn8"
local MOD_VERSION = "1.1.2"
local TARGET_MAX_PLAYERS = 8
local TARGET_SESSION_ROWS = TARGET_MAX_PLAYERS
local TAG = string.format("[%s v%s]", MOD_ID, MOD_VERSION)

local CURRENT_SESSION_CLASS_PATH = "/Game/Interfaces/MainMenu/UI_Menu_Container_CurrentSession.UI_Menu_Container_CurrentSession_C"
local INVITE_SESSION_ROW_CLASS_PATH = "/Game/Interfaces/MainMenu/UI_Menu_Button_Session_Invite.UI_Menu_Button_Session_Invite_C"
local WIDGET_BLUEPRINT_LIBRARY_PATH = "/Script/UMG.Default__WidgetBlueprintLibrary"

local trackedSessions = {}
local trackedManagers = {}
local trackedGameStates = {}
local trackedSessionWidgets = {}
local hookedFunctions = {}
local describedFunctions = {}
local reportedUiErrors = {}
local reportedUiStates = {}
local lastObservedPlayers = -1
local sessionCapApplied = false
local managerCapApplied = false
local nativeHookCount = 0
local sessionUiExpanded = false
local maximumInviteSlotsObserved = 0
local sessionUiAugmentations = 0
local sessionUiScanTick = 0
local widgetBlueprintLibrary = nil
local inviteSessionRowClass = nil

local function log(message)
    print(string.format("%s %s\n", TAG, message))
end

local function logError(scope, value)
    log(string.format("ERROR scope=%s detail=%s", scope, tostring(value)))
end

local function logUiErrorOnce(scope, value)
    local key = string.format("%s|%s", tostring(scope), tostring(value))
    if reportedUiErrors[key] then
        return
    end
    reportedUiErrors[key] = true
    logError(scope, value)
end

local function logUiStateOnce(scope, value)
    local key = string.format("%s|%s", tostring(scope), tostring(value))
    if reportedUiStates[key] then
        return
    end
    reportedUiStates[key] = true
    log(string.format("%s detail=%s", scope, tostring(value)))
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

local function getClassName(object)
    local ok, class = pcall(function()
        return object:GetClass()
    end)
    if not ok or not isValid(class) then
        return "<unknown>"
    end
    return getObjectName(class)
end

local function classifySessionRow(object)
    local identity = getClassName(object) .. "|" .. getObjectName(object)
    if identity:find("UI_Menu_Button_Session_Invite", 1, true)
        or identity:find("UI_Menu_SessionEmptySlot", 1, true) then
        return "invite"
    end
    if identity:find("UI_Menu_SessionMember", 1, true) then
        return "member"
    end
    return "unknown"
end

local function inspectSessionRows(panel)
    local ok, total = pcall(function()
        return panel:GetChildrenCount()
    end)
    if not ok or type(total) ~= "number" then
        return nil, "VerticalBox_Players.GetChildrenCount failed"
    end

    local result = {
        total = total,
        invites = 0,
        members = 0,
        unknown = 0,
        template = nil,
        classes = {},
    }
    for index = 0, total - 1 do
        local childOk, child = pcall(function()
            return panel:GetChildAt(index)
        end)
        if not childOk or not isValid(child) then
            result.unknown = result.unknown + 1
            table.insert(result.classes, "<invalid>")
        else
            table.insert(result.classes, getClassName(child))
            local rowType = classifySessionRow(child)
            if rowType == "invite" then
                result.invites = result.invites + 1
                result.template = result.template or child
            elseif rowType == "member" then
                result.members = result.members + 1
            else
                result.unknown = result.unknown + 1
            end
        end
    end
    return result, nil
end

local function resolveInviteSessionRowClass(template)
    if isValid(inviteSessionRowClass) then
        return inviteSessionRowClass
    end

    if isValid(template) then
        local ok, class = pcall(function()
            return template:GetClass()
        end)
        if ok and isValid(class) then
            inviteSessionRowClass = class
            return inviteSessionRowClass
        end
    end

    local ok, class = pcall(function()
        return StaticFindObject(INVITE_SESSION_ROW_CLASS_PATH)
    end)
    if ok and isValid(class) then
        inviteSessionRowClass = class
        return inviteSessionRowClass
    end
    return nil
end

local function resolveWidgetBlueprintLibrary()
    if isValid(widgetBlueprintLibrary) then
        return widgetBlueprintLibrary
    end

    local ok, library = pcall(function()
        return StaticFindObject(WIDGET_BLUEPRINT_LIBRARY_PATH)
    end)
    if ok and isValid(library) then
        widgetBlueprintLibrary = library
        return widgetBlueprintLibrary
    end
    return nil
end

local function createInviteSessionRow(sessionWidget, template)
    local class = resolveInviteSessionRowClass(template)
    if not isValid(class) then
        return nil, "UI_Menu_Button_Session_Invite_C is not loaded"
    end

    local library = resolveWidgetBlueprintLibrary()
    if not isValid(library) then
        return nil, "WidgetBlueprintLibrary is not loaded"
    end

    local owningPlayer = nil
    pcall(function()
        owningPlayer = sessionWidget:GetOwningPlayer()
    end)

    local ok, widget = pcall(function()
        return library:Create(sessionWidget, class, owningPlayer)
    end)
    if not ok then
        return nil, widget
    end
    if not isValid(widget) then
        return nil, "WidgetBlueprintLibrary.Create returned no widget"
    end
    return widget, nil
end

local function expandCurrentSessionUi(sessionWidget, reason)
    if not isValid(sessionWidget) then
        return false
    end
    remember(trackedSessionWidgets, sessionWidget)

    local panelOk, panel = pcall(function()
        return sessionWidget:GetPropertyValue("VerticalBox_Players")
    end)
    if not panelOk or not isValid(panel) then
        panelOk, panel = pcall(function()
            return sessionWidget.VerticalBox_Players
        end)
    end
    if not panelOk or not isValid(panel) then
        logUiStateOnce(
            "SessionUiDeferred",
            string.format("reason=%s widget=%s VerticalBox_Players=unavailable", reason, getObjectName(sessionWidget))
        )
        return false
    end

    local before, inspectError = inspectSessionRows(panel)
    if before == nil then
        logUiErrorOnce("SessionUiInspect", inspectError)
        return false
    end

    -- The game creates only session-member and empty-invite rows in this box.
    -- Refuse to alter a future layout if another kind of child appears.
    if before.total == 0 then
        logUiStateOnce(
            "SessionUiDeferred",
            string.format("reason=%s widget=%s rows=0", reason, getObjectName(sessionWidget))
        )
        return false
    end
    if before.unknown > 0 then
        logUiStateOnce(
            "SessionUiIncompatible",
            string.format(
                "reason=%s widget=%s rows=%d unknown=%d classes=%s",
                reason,
                getObjectName(sessionWidget),
                before.total,
                before.unknown,
                table.concat(before.classes, ";")
            )
        )
        return false
    end

    maximumInviteSlotsObserved = math.max(maximumInviteSlotsObserved, before.invites)
    if before.total >= TARGET_SESSION_ROWS then
        local ready = before.total == TARGET_SESSION_ROWS
            and before.invites == TARGET_SESSION_ROWS - before.members
        sessionUiExpanded = sessionUiExpanded or ready
        return ready
    end

    local requested = TARGET_SESSION_ROWS - before.total
    local added = 0
    for _ = 1, requested do
        local widget, createError = createInviteSessionRow(sessionWidget, before.template)
        if not isValid(widget) then
            logUiErrorOnce("SessionUiCreate", createError)
            break
        end

        local addOk, slotOrError = pcall(function()
            return panel:AddChild(widget)
        end)
        if not addOk or not isValid(slotOrError) then
            logUiErrorOnce("SessionUiAddChild", slotOrError)
            break
        end
        added = added + 1
    end

    local after, afterError = inspectSessionRows(panel)
    if after == nil then
        logUiErrorOnce("SessionUiVerify", afterError)
        return false
    end

    maximumInviteSlotsObserved = math.max(maximumInviteSlotsObserved, after.invites)
    local ready = after.total == TARGET_SESSION_ROWS
        and after.unknown == 0
        and after.invites == TARGET_SESSION_ROWS - after.members
    sessionUiExpanded = sessionUiExpanded or ready
    if added > 0 then
        sessionUiAugmentations = sessionUiAugmentations + 1
        log(string.format(
            "SessionUi reason=%s rowsBefore=%d membersBefore=%d inviteBefore=%d requested=%d added=%d rowsAfter=%d membersAfter=%d inviteAfter=%d READY=%s",
            reason,
            before.total,
            before.members,
            before.invites,
            requested,
            added,
            after.total,
            after.members,
            after.invites,
            tostring(ready)
        ))
    end
    return ready
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

    for name, object in pairs(trackedSessionWidgets) do
        if isValid(object) then
            expandCurrentSessionUi(object, "cached")
        else
            trackedSessionWidgets[name] = nil
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
    local sessionWidgets = scanClass("UI_Menu_Container_CurrentSession_C", function(object)
        expandCurrentSessionUi(object, reason)
    end)

    if sessions > 0 or managers > 0 or sessionWidgets > 0 then
        log(string.format(
            "Scan reason=%s sessions=%d managers=%d sessionWidgets=%d",
            reason,
            sessions,
            managers,
            sessionWidgets
        ))
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
        "Status reason=%s target=%d sessionCapApplied=%s managerCapApplied=%s nativeHooks=%d observedPlayers=%d sessionUiExpanded=%s maximumInviteSlotsObserved=%d uiAugmentations=%d",
        reason,
        TARGET_MAX_PLAYERS,
        tostring(sessionCapApplied),
        tostring(managerCapApplied),
        nativeHookCount,
        lastObservedPlayers,
        tostring(sessionUiExpanded),
        maximumInviteSlotsObserved,
        sessionUiAugmentations
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
        NotifyOnNewObject(CURRENT_SESSION_CLASS_PATH, function(object)
            remember(trackedSessionWidgets, object)
            ExecuteInGameThreadWithDelay(50, function()
                expandCurrentSessionUi(object, "new50ms")
            end)
            ExecuteInGameThreadWithDelay(250, function()
                expandCurrentSessionUi(object, "new250ms")
            end)
            ExecuteInGameThreadWithDelay(750, function()
                expandCurrentSessionUi(object, "new750ms")
            end)
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
log(string.format("Target SessionRows=%d InviteSlotsWhenSolo=%d", TARGET_SESSION_ROWS, TARGET_SESSION_ROWS - 1))
log("Implementation=source-owned-lua runtimeSessionUi=true cookedAssets=false")

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
    sessionUiScanTick = sessionUiScanTick + 1
    if sessionUiScanTick % 2 == 0 then
        scanClass("UI_Menu_Container_CurrentSession_C", function(object)
            expandCurrentSessionUi(object, "Poll")
        end)
    end
end)
