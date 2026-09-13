-- FFWFrostburn8 is an independent, source-owned UE4SS mod for Far Far West.
-- It raises multiplayer capacity and expands the live Session list to eight
-- rows. It does not include cooked game assets, enemy scaling, fake players,
-- or code from another multiplayer mod.

local MOD_ID = "FFWFrostburn8"
local MOD_VERSION = "1.2.2"
local TARGET_MAX_PLAYERS = 8
local VANILLA_MAX_PLAYERS = 4
local TARGET_SESSION_ROWS = TARGET_MAX_PLAYERS
local HOST_ONLY_EXPERIMENTAL = true
local TAG = string.format("[%s v%s]", MOD_ID, MOD_VERSION)

local CURRENT_SESSION_CLASS_PATH = "/Game/Interfaces/MainMenu/UI_Menu_Container_CurrentSession.UI_Menu_Container_CurrentSession_C"
local INVITE_SESSION_ROW_CLASS_PATH = "/Game/Interfaces/MainMenu/UI_Menu_Button_Session_Invite.UI_Menu_Button_Session_Invite_C"
local MEMBER_SESSION_ROW_CLASS_PATH = "/Game/Interfaces/MainMenu/UI_Menu_SessionMember.UI_Menu_SessionMember_C"
local WIDGET_BLUEPRINT_LIBRARY_PATH = "/Script/UMG.Default__WidgetBlueprintLibrary"
local CURRENT_SESSION_CONSTRUCT_PATH = CURRENT_SESSION_CLASS_PATH .. ":Construct"
local CREATE_ROOM_FUNCTION_PATH = "/Game/Gamework/BP_Manager_Multiplayer.BP_Manager_Multiplayer_C:F_CreateSession"
local KICK_PLAYER_FUNCTION_PATH = "/Script/SteamCorePro.SteamUtilities:KickPlayer"

local trackedSessions = {}
local trackedManagers = {}
local trackedGameStates = {}
local trackedSessionWidgets = {}
local hookedFunctions = {}
local describedFunctions = {}
local reportedUiErrors = {}
local reportedUiStates = {}
local ownedSessionRows = {}
local lastObservedPlayers = -1
local sessionCapApplied = false
local managerCapApplied = false
local nativeHookCount = 0
local sessionUiExpanded = false
local maximumInviteSlotsObserved = 0
local maximumMemberRowsObserved = 0
local sessionUiAugmentations = 0
local sessionUiScanTick = 0
local widgetBlueprintLibrary = nil
local inviteSessionRowClass = nil
local memberSessionRowClass = nil
local hostOnlyRoomGate = "unknown"
local hostOnlyRoomGateSource = "none"
local hostOnlyRoomCreationAllowMods = nil
local hostOnlyRoomHookRegistered = false
local hostOnlyJoinGuardRegistered = false
local hostOnlyJoinGuardChecks = 0
local hostOnlyJoinBlocks = 0
local hostOnlyJoinAllows = 0
local hostOnlyLobbyHookCount = 0
local hostOnlyLobbyWrites = 0
local hostOnlyLobbySkips = 0
local sessionUiConstructHookRegistered = false
local hostOnlyHooks = {}

local function log(message)
    print(string.format("%s %s\n", TAG, message))
end

local function logError(scope, value)
    log(string.format("ERROR scope=%s detail=%s", scope, tostring(value)))
end

local function setHostOnlyRoomGate(enabled, source)
    if not HOST_ONLY_EXPERIMENTAL or type(enabled) ~= "boolean" then
        return
    end

    local nextGate = enabled and "armed" or "disarmed"
    local nextSource = tostring(source or "unknown")
    if hostOnlyRoomGate ~= nextGate or hostOnlyRoomGateSource ~= nextSource then
        hostOnlyRoomGate = nextGate
        hostOnlyRoomGateSource = nextSource
        log(string.format("HostOnlyRoomGate state=%s source=%s", hostOnlyRoomGate, hostOnlyRoomGateSource))
    end
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

local function readHookParam(parameter)
    if parameter == nil then
        return nil, false
    end

    local ok, value = pcall(function()
        return parameter:get()
    end)
    if ok then
        return value, true
    end
    return nil, false
end

local function readKickReason(parameter)
    local value, readable = readHookParam(parameter)
    if not readable or value == nil then
        return nil, false
    end
    if type(value) == "string" then
        return value, true
    end

    local ok, text = pcall(function()
        return value:ToString()
    end)
    if ok and type(text) == "string" then
        return text, true
    end
    return nil, false
end

local function getHostOnlyPlayerCount()
    for _, className in ipairs({ "BP_GameState_C", "GameState", "GameStateBase" }) do
        local stateOk, gameState = pcall(function()
            return FindFirstOf(className)
        end)
        if stateOk and isValid(gameState) then
            local arrayOk, players = pcall(function()
                return gameState:GetPropertyValue("PlayerArray")
            end)
            if arrayOk and players ~= nil then
                local countOk, count = pcall(function()
                    return players:GetArrayNum()
                end)
                if not countOk then
                    countOk, count = pcall(function()
                        return #players
                    end)
                end
                if countOk and type(count) == "number" and count >= 1 and count <= TARGET_MAX_PLAYERS then
                    return count
                end
            end
        end
    end
    return nil
end

local function registerHostOnlyRoomHook()
    if not HOST_ONLY_EXPERIMENTAL or hostOnlyRoomHookRegistered then
        return hostOnlyRoomHookRegistered
    end

    local ok, preId, postId = pcall(function()
        return RegisterHook(CREATE_ROOM_FUNCTION_PATH, function(_, _, allowModsParameter)
            local allowMods, readable = readHookParam(allowModsParameter)
            if readable and type(allowMods) == "boolean" then
                hostOnlyRoomCreationAllowMods = allowMods
                setHostOnlyRoomGate(allowMods, "F_CreateSession")
            else
                hostOnlyRoomCreationAllowMods = nil
                hostOnlyRoomGate = "unknown"
                hostOnlyRoomGateSource = "F_CreateSession-unreadable"
                log("HostOnlyRoomGate state=unknown source=F_CreateSession-unreadable")
            end
        end)
    end)
    if not ok then
        if not describedFunctions["HostOnlyRoomHookDeferred"] then
            describedFunctions["HostOnlyRoomHookDeferred"] = true
            log(string.format("HostOnlyHook deferred path=%s detail=%s", CREATE_ROOM_FUNCTION_PATH, tostring(preId)))
        end
        return false
    end

    hostOnlyHooks[CREATE_ROOM_FUNCTION_PATH] = { preId = preId, postId = postId }
    hostOnlyRoomHookRegistered = true
    log(string.format("HostOnlyHook registered role=room-gate path=%s", CREATE_ROOM_FUNCTION_PATH))
    return true
end

local function registerHostOnlyJoinGuard()
    if not HOST_ONLY_EXPERIMENTAL or hostOnlyJoinGuardRegistered then
        return hostOnlyJoinGuardRegistered
    end

    local ok, preId, postId = pcall(function()
        return RegisterHook(
            KICK_PLAYER_FUNCTION_PATH,
            function(_, worldContextParameter, kickedPlayerParameter, kickReasonParameter, returnValueParameter)
                hostOnlyJoinGuardChecks = hostOnlyJoinGuardChecks + 1

                local worldContext, contextReadable = readHookParam(worldContextParameter)
                local kickedPlayer, playerReadable = readHookParam(kickedPlayerParameter)
                local reasonText, reasonReadable = readKickReason(kickReasonParameter)
                local playerCount = getHostOnlyPlayerCount()
                local contextIdentity = contextReadable and isValid(worldContext)
                    and (getClassName(worldContext) .. "|" .. getObjectName(worldContext))
                    or "<unreadable>"
                local joinValidationSource = contextIdentity:find("BP_PlayerState_C", 1, true) ~= nil
                    or contextIdentity:find("GM_Lobby_C", 1, true) ~= nil
                local authorityOk, hasAuthority = pcall(function()
                    return worldContext:HasAuthority()
                end)
                local emptyReason = reasonReadable and reasonText:match("^%s*$") ~= nil
                local eligible = hostOnlyRoomGate == "armed"
                    and contextReadable
                    and playerReadable
                    and isValid(kickedPlayer)
                    and authorityOk
                    and hasAuthority == true
                    and joinValidationSource
                    and emptyReason
                    and type(playerCount) == "number"
                    and playerCount >= VANILLA_MAX_PLAYERS
                    and playerCount < TARGET_MAX_PLAYERS

                if eligible then
                    local targetCleared = pcall(function()
                        kickedPlayerParameter:set(nil)
                    end)
                    local returnSuppressed = pcall(function()
                        returnValueParameter:set(false)
                    end)
                    if targetCleared then
                        hostOnlyJoinBlocks = hostOnlyJoinBlocks + 1
                        log(string.format(
                            "HostOnlyJoinGuard action=BLOCK_EMPTY_JOIN_KICK players=%d gate=%s source=%s target=%s returnSuppressed=%s blocks=%d",
                            playerCount,
                            hostOnlyRoomGate,
                            contextIdentity,
                            getObjectName(kickedPlayer),
                            tostring(returnSuppressed),
                            hostOnlyJoinBlocks
                        ))
                        return
                    end
                    log(string.format(
                        "HostOnlyJoinGuard action=MUTATION_FAILED players=%s gate=%s source=%s",
                        tostring(playerCount),
                        hostOnlyRoomGate,
                        contextIdentity
                    ))
                end

                hostOnlyJoinAllows = hostOnlyJoinAllows + 1
                if hostOnlyJoinAllows <= 30 then
                    log(string.format(
                        "HostOnlyJoinGuard action=ALLOW players=%s gate=%s authority=%s joinSource=%s reason=%s targetReadable=%s allows=%d",
                        tostring(playerCount),
                        hostOnlyRoomGate,
                        tostring(authorityOk and hasAuthority == true),
                        tostring(joinValidationSource),
                        reasonReadable and string.format("%q", reasonText) or "<unreadable>",
                        tostring(playerReadable and isValid(kickedPlayer)),
                        hostOnlyJoinAllows
                    ))
                end
            end
        )
    end)
    if not ok then
        if not describedFunctions["HostOnlyJoinGuardDeferred"] then
            describedFunctions["HostOnlyJoinGuardDeferred"] = true
            log(string.format("HostOnlyHook deferred path=%s detail=%s", KICK_PLAYER_FUNCTION_PATH, tostring(preId)))
        end
        return false
    end

    hostOnlyHooks[KICK_PLAYER_FUNCTION_PATH] = { preId = preId, postId = postId }
    hostOnlyJoinGuardRegistered = true
    log(string.format("HostOnlyHook registered role=selective-join-guard path=%s", KICK_PLAYER_FUNCTION_PATH))
    return true
end

local function registerHostOnlyHooks()
    registerHostOnlyRoomHook()
    registerHostOnlyJoinGuard()
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
        visible = 0,
        template = nil,
        inviteRows = {},
        memberRows = {},
        membersBeforeInvites = true,
        classes = {},
    }
    local sawInvite = false
    for index = 0, total - 1 do
        local childOk, child = pcall(function()
            return panel:GetChildAt(index)
        end)
        if not childOk or not isValid(child) then
            result.unknown = result.unknown + 1
            table.insert(result.classes, "<invalid>")
        else
            table.insert(result.classes, getClassName(child))
            local visibleOk, visible = pcall(function()
                return child:IsVisible()
            end)
            if visibleOk and visible == true then
                result.visible = result.visible + 1
            end
            local rowType = classifySessionRow(child)
            if rowType == "invite" then
                result.invites = result.invites + 1
                result.template = result.template or child
                table.insert(result.inviteRows, child)
                sawInvite = true
            elseif rowType == "member" then
                result.members = result.members + 1
                table.insert(result.memberRows, child)
                if sawInvite then
                    result.membersBeforeInvites = false
                end
            else
                result.unknown = result.unknown + 1
            end
        end
    end
    return result, nil
end

local function resolveMemberSessionRowClass(template)
    if isValid(memberSessionRowClass) then
        return memberSessionRowClass
    end

    if isValid(template) then
        local ok, class = pcall(function()
            return template:GetClass()
        end)
        if ok and isValid(class) then
            memberSessionRowClass = class
            return memberSessionRowClass
        end
    end

    local ok, class = pcall(function()
        return StaticFindObject(MEMBER_SESSION_ROW_CLASS_PATH)
    end)
    if ok and isValid(class) then
        memberSessionRowClass = class
        return memberSessionRowClass
    end
    return nil
end

local function resolveInviteSessionRowClass(template)
    if isValid(inviteSessionRowClass) then
        return inviteSessionRowClass
    end

    local ok, class = pcall(function()
        return StaticFindObject(INVITE_SESSION_ROW_CLASS_PATH)
    end)
    if ok and isValid(class) then
        inviteSessionRowClass = class
        return inviteSessionRowClass
    end

    if isValid(template) and getClassName(template):find("UI_Menu_Button_Session_Invite_C", 1, true) then
        local templateOk, templateClass = pcall(function()
            return template:GetClass()
        end)
        if templateOk and isValid(templateClass) then
            inviteSessionRowClass = templateClass
            return inviteSessionRowClass
        end
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

local function createInviteSessionRow(sessionWidget, template, playerSlotIndex)
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


    local idOk, idError = pcall(function()
        -- The invite widget uses the same zero-based player-slot convention as
        -- the member widget. Unique ids keep every extended button live.
        widget:SetPropertyValue("id", playerSlotIndex - 1)
    end)
    if not idOk then
        return nil, idError
    end
    return widget, nil
end

local function createMemberSessionRow(sessionWidget, template, playerState, playerIndex)
    local class = resolveMemberSessionRowClass(template)
    if not isValid(class) then
        return nil, "UI_Menu_SessionMember_C is not loaded"
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
        return nil, "WidgetBlueprintLibrary.Create returned no member widget"
    end

    local stateOk, stateError = pcall(function()
        widget:SetPropertyValue("playerState", playerState)
        -- The Blueprint uses a zero-based id for profile/mute/kick actions.
        widget:SetPropertyValue("id", playerIndex - 1)
    end)
    if not stateOk then
        return nil, stateError
    end
    return widget, nil
end

local function getSessionModsAllowed(sessionWidget)
    local textOk, textBlock = pcall(function()
        return sessionWidget:GetPropertyValue("TextBlock_Cheats")
    end)
    if not textOk or not isValid(textBlock) then
        return nil, "TextBlock_Cheats is unavailable"
    end

    -- This is the same widget whose visibility the game's
    -- F_IsSessionCheatsEnabled result controls. In Far Far West, "cheats"
    -- is the session setting exposed to players as "Allow mods".
    local visibleOk, visible = pcall(function()
        return textBlock:IsVisible()
    end)
    if visibleOk and type(visible) == "boolean" then
        if visible == false and hostOnlyRoomCreationAllowMods == true then
            -- TextBlock_Cheats can still be collapsed while the Blueprint is
            -- constructing. The value captured from F_CreateSession is the
            -- authoritative choice for this room and must survive that race.
            setHostOnlyRoomGate(true, "F_CreateSession-sticky")
            logUiStateOnce(
                "SessionUiGateRace",
                string.format("widget=%s textVisible=false roomCreationAllowMods=true resolved=true", getObjectName(sessionWidget))
            )
            return true, nil
        end
        setHostOnlyRoomGate(visible, "CurrentSessionUi")
        return visible, nil
    end
    return nil, visible
end

local function readPlayerStates(gameState)
    if not isValid(gameState) then
        return nil, "GameState is unavailable"
    end

    local arrayOk, playerArray = pcall(function()
        return gameState:GetPropertyValue("PlayerArray")
    end)
    if not arrayOk or playerArray == nil then
        return nil, "GameState.PlayerArray is unavailable"
    end

    local countOk, count = pcall(function()
        return playerArray:GetArrayNum()
    end)
    if not countOk or type(count) ~= "number" then
        return nil, "GameState.PlayerArray count is unavailable"
    end
    if count < 1 or count > TARGET_MAX_PLAYERS then
        return nil, string.format("PlayerArray count %s is outside 1..%d", tostring(count), TARGET_MAX_PLAYERS)
    end

    local states = {}
    for index = 1, count do
        local stateOk, playerState = pcall(function()
            return playerArray[index]
        end)
        if not stateOk or not isValid(playerState) then
            return nil, string.format("PlayerArray[%d] is unavailable", index)
        end
        table.insert(states, playerState)
    end
    return states, nil
end

local function getPlayerStatesForWidget(sessionWidget)
    local worldOk, world = pcall(function()
        return sessionWidget:GetWorld()
    end)
    if not worldOk or not isValid(world) then
        return nil, "Current Session world is unavailable"
    end

    local stateOk, gameState = pcall(function()
        return world:GetPropertyValue("GameState")
    end)
    if stateOk and isValid(gameState) then
        return readPlayerStates(gameState)
    end

    -- Some UUserWidget world wrappers do not expose UWorld.GameState. Fall
    -- back only to a tracked GameState from the exact same world; never use a
    -- stale menu/travel world merely because it contains more players.
    local worldName = getObjectName(world)
    for _, candidate in pairs(trackedGameStates) do
        if isValid(candidate) then
            local candidateWorldOk, candidateWorld = pcall(function()
                return candidate:GetWorld()
            end)
            if candidateWorldOk and isValid(candidateWorld) and getObjectName(candidateWorld) == worldName then
                return readPlayerStates(candidate)
            end
        end
    end
    return nil, "No GameState from the Current Session world is tracked"
end

local function getMemberPlayerState(row)
    local ok, playerState = pcall(function()
        return row:GetPropertyValue("playerState")
    end)
    if ok and isValid(playerState) then
        return playerState
    end
    return nil
end

local function removeSessionRow(panel, row)
    if not isValid(row) then
        return false
    end
    local ok, removed = pcall(function()
        return panel:RemoveChild(row)
    end)
    return ok and removed == true
end

local function rememberOwnedSessionRow(row, rowType)
    ownedSessionRows[getObjectName(row)] = {
        object = row,
        rowType = rowType,
    }
end

local function isOwnedSessionRow(row)
    local name = getObjectName(row)
    local entry = ownedSessionRows[name]
    if entry == nil then
        return false
    end
    if not isValid(entry.object) then
        ownedSessionRows[name] = nil
        return false
    end
    return getObjectName(entry.object) == name
end

local function removeOwnedSessionRows(panel, rows)
    local removed = 0
    for _, row in ipairs(rows) do
        local name = getObjectName(row)
        if isOwnedSessionRow(row) and removeSessionRow(panel, row) then
            ownedSessionRows[name] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function refreshSessionLayout(sessionWidget, panel)
    pcall(function()
        panel:InvalidateLayoutAndVolatility()
    end)
    pcall(function()
        sessionWidget:InvalidateLayoutAndVolatility()
    end)
    pcall(function()
        sessionWidget:ForceLayoutPrepass()
    end)
end

local function reportVerifiedSessionUi(sessionWidget, state, playerCount, expectedInvites, reason)
    local ready = state.total == TARGET_SESSION_ROWS
        and state.unknown == 0
        and state.members == playerCount
        and state.invites == expectedInvites
        and state.visible == TARGET_SESSION_ROWS
        and state.membersBeforeInvites
    logUiStateOnce(
        "SessionUiVerified",
        string.format(
            "widget=%s reason=%s players=%d members=%d invites=%d expectedInvites=%d total=%d visibleRows=%d READY=%s",
            getObjectName(sessionWidget),
            reason,
            playerCount,
            state.members,
            state.invites,
            expectedInvites,
            state.total,
            state.visible,
            tostring(ready)
        )
    )
    return ready
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

    local modsAllowed, gateError = getSessionModsAllowed(sessionWidget)
    if modsAllowed == nil then
        logUiStateOnce(
            "SessionUiDeferred",
            string.format("reason=%s widget=%s modsAllowed=unknown detail=%s", reason, getObjectName(sessionWidget), tostring(gateError))
        )
        return false
    end

    local before, inspectError = inspectSessionRows(panel)
    if before == nil then
        logUiErrorOnce("SessionUiInspect", inspectError)
        return false
    end


    if not modsAllowed then
        local ownedRows = {}
        for _, row in ipairs(before.memberRows) do
            table.insert(ownedRows, row)
        end
        for _, row in ipairs(before.inviteRows) do
            table.insert(ownedRows, row)
        end
        local removed = removeOwnedSessionRows(panel, ownedRows)
        local baselineRestored = 0
        if removed > 0 then
            local baseline, baselineError = inspectSessionRows(panel)
            if baseline == nil then
                logUiErrorOnce("SessionUiBaselineInspect", baselineError)
                return false
            end
            local baselineRows = 4
            local baselineInvites = math.max(0, baselineRows - baseline.members)
            for inviteIndex = baseline.invites + 1, baselineInvites do
                local widget, createError = createInviteSessionRow(
                    sessionWidget,
                    before.template,
                    baseline.members + inviteIndex
                )
                if not isValid(widget) then
                    logUiErrorOnce("SessionUiBaselineCreate", createError)
                    break
                end
                local addOk, slotOrError = pcall(function()
                    return panel:AddChild(widget)
                end)
                if not addOk or not isValid(slotOrError) then
                    logUiErrorOnce("SessionUiBaselineAddChild", slotOrError)
                    break
                end
                baselineRestored = baselineRestored + 1
            end
        end
        logUiStateOnce(
            "SessionUiGate",
            string.format(
                "widget=%s modsAllowed=false ownedRowsRemoved=%d baselineInvitesRestored=%d",
                getObjectName(sessionWidget),
                removed,
                baselineRestored
            )
        )
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

    local playerStates, playerStateError = getPlayerStatesForWidget(sessionWidget)
    if playerStates == nil then
        logUiStateOnce(
            "SessionUiDeferred",
            string.format("reason=%s widget=%s modsAllowed=true detail=%s", reason, getObjectName(sessionWidget), tostring(playerStateError))
        )
        return false
    end

    local activePlayers = {}
    for _, playerState in ipairs(playerStates) do
        activePlayers[getObjectName(playerState)] = true
    end

    local representedPlayers = {}
    for _, row in ipairs(before.memberRows) do
        local playerState = getMemberPlayerState(row)
        if not isValid(playerState) then
            logUiStateOnce(
                "SessionUiDeferred",
                string.format("reason=%s widget=%s member=%s playerState=unavailable", reason, getObjectName(sessionWidget), getObjectName(row))
            )
            return false
        end
        local playerName = getObjectName(playerState)
        if representedPlayers[playerName] then
            logUiStateOnce(
                "SessionUiIncompatible",
                string.format("reason=%s widget=%s duplicatePlayerState=%s", reason, getObjectName(sessionWidget), playerName)
            )
            return false
        end
        if not activePlayers[playerName] and not isOwnedSessionRow(row) then
            logUiStateOnce(
                "SessionUiIncompatible",
                string.format("reason=%s widget=%s staleGameMember=%s", reason, getObjectName(sessionWidget), playerName)
            )
            return false
        end
        representedPlayers[playerName] = true
    end

    local desiredInvites = TARGET_SESSION_ROWS - #playerStates
    local allPlayersRepresented = true
    for _, playerState in ipairs(playerStates) do
        if not representedPlayers[getObjectName(playerState)] then
            allPlayersRepresented = false
            break
        end
    end
    local alreadyReady = before.total == TARGET_SESSION_ROWS
        and before.unknown == 0
        and before.members == #playerStates
        and before.invites == desiredInvites
        and before.membersBeforeInvites
        and allPlayersRepresented
    if alreadyReady then
        pcall(function()
            sessionWidget:SetPropertyValue("showedPlayers", #playerStates)
        end)
        maximumInviteSlotsObserved = math.max(maximumInviteSlotsObserved, before.invites)
        maximumMemberRowsObserved = math.max(maximumMemberRowsObserved, before.members)
        refreshSessionLayout(sessionWidget, panel)
        local verified = reportVerifiedSessionUi(sessionWidget, before, #playerStates, desiredInvites, reason)
        sessionUiExpanded = sessionUiExpanded or verified
        return verified
    end

    -- Remove every invite row before adding missing members. Otherwise a
    -- player who joins later would be appended below existing Invite buttons.
    -- The rows are recreated after the member list is synchronized.
    local initial = before
    local rowsRemoved = 0
    if desiredInvites > 0 and not isValid(resolveInviteSessionRowClass(before.template)) then
        logUiErrorOnce("SessionUiResolveInviteClass", "UI_Menu_Button_Session_Invite_C is not loaded")
        return false
    end
    for index = #before.inviteRows, 1, -1 do
        local row = before.inviteRows[index]
        if not removeSessionRow(panel, row) then
            logUiErrorOnce("SessionUiRemoveInvite", getObjectName(row))
            return false
        end
        ownedSessionRows[getObjectName(row)] = nil
        rowsRemoved = rowsRemoved + 1
    end

    before, inspectError = inspectSessionRows(panel)
    if before == nil then
        logUiErrorOnce("SessionUiInspectAfterInviteReset", inspectError)
        return false
    end

    local membersRemoved = 0
    for _, row in ipairs(before.memberRows) do
        local playerState = getMemberPlayerState(row)
        local rowName = getObjectName(row)
        if isOwnedSessionRow(row) and isValid(playerState) and not activePlayers[getObjectName(playerState)] then
            if removeSessionRow(panel, row) then
                ownedSessionRows[rowName] = nil
                membersRemoved = membersRemoved + 1
            end
        end
    end

    if membersRemoved > 0 then
        before, inspectError = inspectSessionRows(panel)
        if before == nil then
            logUiErrorOnce("SessionUiInspectAfterMemberRemoval", inspectError)
            return false
        end
        representedPlayers = {}
        for _, row in ipairs(before.memberRows) do
            local playerState = getMemberPlayerState(row)
            if isValid(playerState) then
                representedPlayers[getObjectName(playerState)] = true
            end
        end
    end

    local membersAdded = 0
    local memberTemplate = before.memberRows[1]
    for playerIndex, playerState in ipairs(playerStates) do
        if not representedPlayers[getObjectName(playerState)] then
            local widget, createError = createMemberSessionRow(sessionWidget, memberTemplate, playerState, playerIndex)
            if not isValid(widget) then
                logUiErrorOnce("SessionUiCreateMember", createError)
                break
            end

            local addOk, slotOrError = pcall(function()
                return panel:AddChild(widget)
            end)
            if not addOk or not isValid(slotOrError) then
                logUiErrorOnce("SessionUiAddMember", slotOrError)
                break
            end
            rememberOwnedSessionRow(widget, "member")
            representedPlayers[getObjectName(playerState)] = true
            membersAdded = membersAdded + 1

            -- Refresh after the widget has a playerState and belongs to the
            -- panel. The Blueprint also keeps its own refresh timer.
            pcall(function()
                widget:F_RefreshInformations()
            end)
        end
    end

    local middle, middleError = inspectSessionRows(panel)
    if middle == nil then
        logUiErrorOnce("SessionUiInspectAfterMembers", middleError)
        return false
    end

    local invitesAdded = 0
    for inviteIndex = 1, desiredInvites do
        local widget, createError = createInviteSessionRow(
            sessionWidget,
            initial.template,
            #playerStates + inviteIndex
        )
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
        rememberOwnedSessionRow(widget, "invite")
        invitesAdded = invitesAdded + 1
    end

    local after, afterError = inspectSessionRows(panel)
    if after == nil then
        logUiErrorOnce("SessionUiVerify", afterError)
        return false
    end

    pcall(function()
        sessionWidget:SetPropertyValue("showedPlayers", #playerStates)
    end)

    refreshSessionLayout(sessionWidget, panel)

    -- Re-read after the layout prepass so a created-but-collapsed row cannot
    -- be counted as a visible Invite slot.
    after, afterError = inspectSessionRows(panel)
    if after == nil then
        logUiErrorOnce("SessionUiVerifyAfterLayout", afterError)
        return false
    end

    maximumInviteSlotsObserved = math.max(maximumInviteSlotsObserved, after.invites)
    maximumMemberRowsObserved = math.max(maximumMemberRowsObserved, after.members)
    local ready = reportVerifiedSessionUi(sessionWidget, after, #playerStates, desiredInvites, reason)
    sessionUiExpanded = sessionUiExpanded or ready
    if membersAdded > 0 or membersRemoved > 0 or invitesAdded > 0 or rowsRemoved > 0 then
        sessionUiAugmentations = sessionUiAugmentations + 1
        log(string.format(
            "SessionUi reason=%s modsAllowed=true playersObserved=%d rowsBefore=%d membersBefore=%d inviteBefore=%d membersAdded=%d membersRemoved=%d invitesAdded=%d rowsRemoved=%d rowsAfter=%d membersAfter=%d inviteAfter=%d READY=%s",
            reason,
            #playerStates,
            initial.total,
            initial.members,
            initial.invites,
            membersAdded,
            membersRemoved,
            invitesAdded,
            rowsRemoved,
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

local function registerSessionUiConstructHook()
    if sessionUiConstructHookRegistered then
        return true
    end

    local ok, preId, postId = pcall(function()
        return RegisterHook(CURRENT_SESSION_CONSTRUCT_PATH, function()
            -- Run after the Blueprint has had time to execute ClearChildren
            -- and rebuild its vanilla four-row list.
            for _, delayMs in ipairs({ 50, 250, 750, 1500 }) do
                local capturedDelay = delayMs
                ExecuteInGameThreadWithDelay(capturedDelay, function()
                    scanClass("UI_Menu_Container_CurrentSession_C", function(object)
                        expandCurrentSessionUi(object, "Construct+" .. tostring(capturedDelay) .. "ms")
                    end)
                end)
            end
        end)
    end)
    if not ok then
        if not describedFunctions["SessionUiConstructHookDeferred"] then
            describedFunctions["SessionUiConstructHookDeferred"] = true
            log(string.format("SessionUiHook deferred path=%s detail=%s", CURRENT_SESSION_CONSTRUCT_PATH, tostring(preId)))
        end
        return false
    end

    hookedFunctions[CURRENT_SESSION_CONSTRUCT_PATH] = { preId = preId, postId = postId }
    sessionUiConstructHookRegistered = true
    log(string.format("SessionUiHook registered role=post-construct-reconcile path=%s", CURRENT_SESSION_CONSTRUCT_PATH))
    return true
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

local function isHostOnlyLobbyFunction(functionPath)
    local lowerPath = tostring(functionPath):lower()
    return lowerPath:find("steam", 1, true) ~= nil
        and lowerPath:find("createlobby", 1, true) ~= nil
end

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
        local applied = writeOk and verifyOk and after == TARGET_MAX_PLAYERS
        if applied and isHostOnlyLobbyFunction(functionPath) then
            hostOnlyLobbyWrites = hostOnlyLobbyWrites + 1
            log(string.format(
                "HostOnlyLobbyWrite function=%s target=%s BEFORE=%s AFTER=%s writes=%d",
                functionPath,
                target.parameter,
                readOk and tostring(before) or "<unreadable>",
                verifyOk and tostring(after) or "<unreadable>",
                hostOnlyLobbyWrites
            ))
        end
        return applied
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
    local applied = writeOk and verifyOk and after == TARGET_MAX_PLAYERS
    if applied and isHostOnlyLobbyFunction(functionPath) then
        hostOnlyLobbyWrites = hostOnlyLobbyWrites + 1
        log(string.format(
            "HostOnlyLobbyWrite function=%s target=%s.%s BEFORE=%s AFTER=%s writes=%d",
            functionPath,
            target.parameter,
            target.field,
            readOk and tostring(before) or "<unreadable>",
            verifyOk and tostring(after) or "<unreadable>",
            hostOnlyLobbyWrites
        ))
    end
    return applied
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
            if isHostOnlyLobbyFunction(functionPath) and hostOnlyRoomGate ~= "armed" then
                hostOnlyLobbySkips = hostOnlyLobbySkips + 1
                log(string.format(
                    "HostOnlyLobbyWrite action=SKIP gate=%s function=%s skips=%d",
                    hostOnlyRoomGate,
                    functionPath,
                    hostOnlyLobbySkips
                ))
                return
            end
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
    if isHostOnlyLobbyFunction(functionPath) then
        hostOnlyLobbyHookCount = hostOnlyLobbyHookCount + 1
    end
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
    "/Script/SteamCorePro.SteamCoreProCreateSession:CreateSteamCoreProSession",
    "/Script/SteamCorePro.SteamCoreProUpdateSession:UpdateSteamCoreProSession",
    "/Script/SteamCorePro.SteamProMatchmaking:CreateLobby",
    "/Script/SteamCorePro.SteamCoreProMatchmakingAsyncActionCreateLobby:CreateLobbyAsync",
}

local knownClassPaths = {
    "/Script/FarFarWest.OnlineBlueprintAsyncCreate",
    "/Script/FarFarWest.MultiplayerStatics",
    "/Script/OnlineSubsystemUtils.CreateSessionCallbackProxy",
    "/Script/SteamCorePro.SteamCoreProCreateSession",
    "/Script/SteamCorePro.SteamCoreProUpdateSession",
    "/Script/SteamCorePro.SteamProMatchmaking",
    "/Script/SteamCorePro.SteamCoreProMatchmakingAsyncActionCreateLobby",
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
        "Status reason=%s target=%d sessionCapApplied=%s managerCapApplied=%s nativeHooks=%d observedPlayers=%d sessionUiExpanded=%s maximumMemberRowsObserved=%d maximumInviteSlotsObserved=%d uiAugmentations=%d hostOnlyMode=%s roomGate=%s roomGateSource=%s roomHookReady=%s joinGuardReady=%s lobbyHooks=%d lobbyWrites=%d lobbySkips=%d joinChecks=%d joinBlocks=%d joinAllows=%d sessionUiConstructHookReady=%s",
        reason,
        TARGET_MAX_PLAYERS,
        tostring(sessionCapApplied),
        tostring(managerCapApplied),
        nativeHookCount,
        lastObservedPlayers,
        tostring(sessionUiExpanded),
        maximumMemberRowsObserved,
        maximumInviteSlotsObserved,
        sessionUiAugmentations,
        tostring(HOST_ONLY_EXPERIMENTAL),
        hostOnlyRoomGate,
        hostOnlyRoomGateSource,
        tostring(hostOnlyRoomHookRegistered),
        tostring(hostOnlyJoinGuardRegistered),
        hostOnlyLobbyHookCount,
        hostOnlyLobbyWrites,
        hostOnlyLobbySkips,
        hostOnlyJoinGuardChecks,
        hostOnlyJoinBlocks,
        hostOnlyJoinAllows,
        tostring(sessionUiConstructHookRegistered)
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
            registerHostOnlyHooks()
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
                registerHostOnlyHooks()
                registerSessionUiConstructHook()
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
            registerHostOnlyHooks()
            registerSessionUiConstructHook()
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
log("HostOnlyMode=EXPERIMENTAL vanillaClients=UNVERIFIED allowModsRequired=true manualKickPreserved=true")
log("Implementation=source-owned-lua runtimeSessionUi=true allowModsUiGate=room-creation-sticky synchronizedMemberRows=true reflectedSteamLobbyCap=true selectiveJoinKickGuard=true cookedAssets=false")

registerObjectNotifications()
registerGameStateHook()
registerConsoleCommand()
registerHostOnlyHooks()
registerSessionUiConstructHook()

ExecuteInGameThreadWithDelay(100, function()
    scanExisting("Startup100ms")
    registerHostOnlyHooks()
    registerSessionUiConstructHook()
    discoverCapacityHooks()
end)
ExecuteInGameThreadWithDelay(1500, function()
    scanExisting("Startup1500ms")
    registerHostOnlyHooks()
    registerSessionUiConstructHook()
    discoverCapacityHooks()
    printStatus("Startup1500ms")
end)
ExecuteInGameThreadWithDelay(5000, function()
    scanExisting("Startup5000ms")
    registerHostOnlyHooks()
    registerSessionUiConstructHook()
    discoverCapacityHooks()
    printStatus("Startup5000ms")
end)

LoopInGameThreadWithDelay(500, function()
    applyTrackedCaps()
    sessionUiScanTick = sessionUiScanTick + 1
    if sessionUiScanTick % 2 == 0 then
        scanClass("UI_Menu_Container_CurrentSession_C", function(object)
            expandCurrentSessionUi(object, "Poll")
        end)
    end
    if sessionUiScanTick % 10 == 0 then
        registerHostOnlyHooks()
        registerSessionUiConstructHook()
        discoverCapacityHooks()
    end
end)
