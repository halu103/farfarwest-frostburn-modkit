-- Pure policies: no engine objects, engine calls, timers, or file persistence.
-- Caller must run all methods on one game thread and supply trusted values.
--
-- Map boundary: beginMap(worldKey, generation) clears all retained Jokers when
-- either token changes. generation MUST change for each run, including replay
-- of the same map. Call endMap() when that run/session ends, even without travel.
--
-- Identity: stableId is a verified platform/network ID, NEVER a display name.
-- incarnation identifies a connection/PlayerState, NEVER a respawning pawn.
-- Snapshots are complete Joker state as owned plain Lua tables. isEmpty must
-- describe all Joker state in that snapshot, not merely one inventory array.
--
-- observe() samples connected players. disconnect() retains their last sample.
-- restoreCandidate() returns a COMPLETE REPLACEMENT and an opaque ticket only
-- on a different connection incarnation whose current Joker state is empty.
-- Caller must recheck empty state immediately before replacing, never append,
-- and ackRestore(ticket, true) only after confirming the complete replacement.
-- Failed attempts may retry; nonempty native state always takes precedence.
local RunState = {}
local Cache = {}
Cache.__index = Cache

local function finiteNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function count(value)
    return finiteNumber(value) and value >= 0 and value % 1 == 0
end

local function token(value)
    return (type(value) == "string" and #value > 0)
        or (finiteNumber(value) and value % 1 == 0)
end

local function identity(value)
    return type(value) == "string" and #value > 0 and #value <= 512
        and value:match("%S") ~= nil
end

-- Reject wrappers/metatables, userdata, functions, cycles, and unbounded data.
-- No cache operation ever retains the caller's table or returns its own table.
local function ownedSnapshot(snapshot)
    if type(snapshot) ~= "table" then return nil, "snapshot-not-table" end
    local ancestors, nodes = {}, 0
    local function copy(value, depth)
        nodes = nodes + 1
        if nodes > 8192 or depth > 32 then error("snapshot-too-large", 0) end
        local kind = type(value)
        if kind == "boolean" or kind == "string" then return value end
        if kind == "number" and finiteNumber(value) then return value end
        if kind ~= "table" then error("snapshot-unsupported-value", 0) end
        if getmetatable(value) ~= nil then error("snapshot-metatable", 0) end
        if ancestors[value] then error("snapshot-cycle", 0) end
        ancestors[value] = true
        local result = {}
        for key, child in pairs(value) do
            if type(key) ~= "string" and not count(key) then
                error("snapshot-unsupported-key", 0)
            end
            result[key] = copy(child, depth + 1)
        end
        ancestors[value] = nil
        return result
    end
    local ok, result = pcall(copy, snapshot, 0)
    if not ok then return nil, result end
    return result
end

function RunState.missileReady(state)
    if type(state) ~= "table" then return false, "invalid-state" end
    if not count(state.playerCount) or state.playerCount < 5 then
        return false, "vanilla-player-count"
    end
    if not count(state.leverCount) or state.leverCount == 0 then
        return false, "invalid-lever-count"
    end
    if not count(state.pulledCount) or state.pulledCount > state.leverCount then
        return false, "invalid-pulled-count"
    end
    if state.ignited ~= false then return false, "already-ignited-or-unknown" end
    if state.tntReady ~= true then return false, "tnt-not-ready" end
    if state.pulledCount ~= state.leverCount then return false, "levers-incomplete" end
    return true, "all-levers-ready"
end

function RunState.new()
    return setmetatable({ entries = {}, pending = {}, epoch = 0, active = false }, Cache)
end

function Cache:beginMap(worldKey, generation)
    if not token(worldKey) or not token(generation) then return false, "invalid-map-token" end
    if self.active and self.worldKey == worldKey and self.generation == generation then
        return false, "same-map-generation"
    end
    self.epoch = self.epoch + 1
    self.entries = {}
    self.pending = {}
    self.worldKey, self.generation, self.active = worldKey, generation, true
    return true, "map-begun"
end

function Cache:endMap()
    self.epoch = self.epoch + 1
    self.entries = {}
    self.pending = {}
    self.worldKey, self.generation, self.active = nil, nil, false
    return true, "map-ended"
end

local function arguments(cache, stableId, incarnation, snapshot, isEmpty)
    if not cache.active then return nil, "no-active-map" end
    if not identity(stableId) then return nil, "invalid-stable-id" end
    if not token(incarnation) then return nil, "invalid-incarnation" end
    if type(isEmpty) ~= "boolean" then return nil, "unknown-empty-state" end
    return ownedSnapshot(snapshot)
end

local function cancelTicket(cache, entry)
    if entry.ticket then cache.pending[entry.ticket] = nil end
    entry.ticket = nil
end

local function reconnect(cache, entry, incarnation)
    if entry.retired[incarnation] then return nil end
    if entry.incarnation == incarnation then return false end
    entry.retired[entry.incarnation] = true
    entry.incarnation = incarnation
    entry.disconnected = false
    entry.awaitingRestore = true
    entry.restoredFor = nil
    cancelTicket(cache, entry)
    return true
end

local function adopt(cache, entry, snapshot, isEmpty)
    entry.snapshot, entry.isEmpty = snapshot, isEmpty
    entry.awaitingRestore = false
    cancelTicket(cache, entry)
end

function Cache:observe(stableId, incarnation, snapshot, isEmpty)
    local owned, reason = arguments(self, stableId, incarnation, snapshot, isEmpty)
    if not owned then return false, reason end
    local entry = self.entries[stableId]
    if not entry then
        self.entries[stableId] = {
            incarnation = incarnation, snapshot = owned, isEmpty = isEmpty,
            disconnected = false, awaitingRestore = false, retired = {},
        }
        return true, "captured"
    end
    if reconnect(self, entry, incarnation) == nil then return false, "stale-incarnation" end
    if entry.disconnected then return true, "disconnected-snapshot-held" end
    if entry.awaitingRestore and isEmpty then return true, "rejoin-snapshot-held" end
    adopt(self, entry, owned, isEmpty)
    return true, isEmpty and "captured-empty" or "captured-native-state"
end

function Cache:disconnect(stableId, incarnation)
    if not self.active then return false, "no-active-map" end
    local entry = self.entries[stableId]
    if not entry then return false, "no-snapshot" end
    if entry.incarnation ~= incarnation then return false, "stale-incarnation" end
    entry.disconnected = true
    cancelTicket(self, entry)
    return true, "snapshot-held"
end

function Cache:restoreCandidate(stableId, incarnation, currentSnapshot, isEmpty)
    local owned, reason = arguments(self, stableId, incarnation, currentSnapshot, isEmpty)
    if not owned then return nil, reason end
    local entry = self.entries[stableId]
    if not entry then return nil, "no-snapshot" end
    if reconnect(self, entry, incarnation) == nil then return nil, "stale-incarnation" end
    if entry.disconnected then return nil, "not-rejoined" end
    if not isEmpty then
        adopt(self, entry, owned, false)
        return nil, "native-state-present"
    end
    if entry.restoredFor == incarnation then return nil, "already-restored" end
    if not entry.awaitingRestore then return nil, "not-rejoined" end
    if entry.isEmpty then return nil, "no-jokers" end
    if entry.ticket then return nil, "restore-pending" end
    local replacement, copyReason = ownedSnapshot(entry.snapshot)
    if not replacement then return nil, copyReason end
    local ticket = {}
    entry.ticket = ticket
    self.pending[ticket] = {
        epoch = self.epoch, stableId = stableId, incarnation = incarnation,
    }
    return replacement, ticket
end

function Cache:ackRestore(ticket, success)
    if type(success) ~= "boolean" then return false, "invalid-result" end
    local pending = self.pending and self.pending[ticket]
    if not pending then return false, "unknown-ticket" end
    self.pending[ticket] = nil
    local entry = self.entries[pending.stableId]
    if not self.active or pending.epoch ~= self.epoch or not entry
        or entry.incarnation ~= pending.incarnation or entry.disconnected
        or entry.ticket ~= ticket then
        return false, "stale-ticket"
    end
    entry.ticket = nil
    if not success then return false, "retry-allowed" end
    entry.restoredFor = pending.incarnation
    entry.awaitingRestore = false
    return true, "restore-recorded"
end

return RunState
