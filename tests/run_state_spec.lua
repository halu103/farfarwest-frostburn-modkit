-- Run from the repository root: lua tests/run_state_spec.lua
local RunState = dofile("src/Mods/FFWFrostburn8/Scripts/RunState.lua")
local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function ready(players, levers, pulled, tnt, ignited)
    return RunState.missileReady({ playerCount = players, leverCount = levers,
        pulledCount = pulled, tntReady = tnt, ignited = ignited })
end
equal(ready(4, 4, 4, true, false), false, "four players use vanilla logic")
equal(ready(5, 4, 4, true, false), true, "five players require four actual levers")
equal(ready(8, 4, 4, true, false), true, "eight players require four actual levers")
equal(ready(5, 3, 3, true, false), true, "actual lever count is not hardcoded")
equal(ready(5, 4, 3, true, false), false, "incomplete levers")
equal(ready(5, 4, 5, true, false), false, "duplicate or impossible lever count")
equal(ready(5, 0, 0, true, false), false, "missing lever data")
equal(ready(5, 4, 4, false, false), false, "TNT prerequisites required")
equal(ready(5, 4, 4, nil, false), false, "unknown TNT prerequisites fail closed")
equal(ready(5, 4, 4, true, true), false, "do not reignite")
equal(ready(5, 4, 4, true, nil), false, "unknown ignition state fails closed")
equal(ready(5.5, 4, 4, true, false), false, "fractional players rejected")
equal(ready(5, 4.5, 4.5, true, false), false, "fractional levers rejected")
equal(ready(5, 4, 0 / 0, true, false), false, "NaN rejected")

local empty = { cards = {}, effects = {}, capacity = 4 }
local snapshot = { cards = { { id = "joker-a", stacks = 2, rarity = "rare" },
    { id = "joker-b", stacks = 1, charges = 3 } },
    effects = { damage = 1.25, active = true }, capacity = 4 }
local function seeded()
    local cache = RunState.new()
    equal(cache:beginMap("world-a", 1), true, "begin map")
    equal(cache:observe("steam:123", "pc1", snapshot, false), true, "capture full state")
    equal(cache:disconnect("steam:123", "pc1"), true, "hold on disconnect")
    return cache
end

local cache = seeded()
local candidate, ticket = cache:restoreCandidate("steam:123", "pc2", empty, true)
equal(type(candidate), "table", "return replacement")
equal(candidate.cards[1].id, "joker-a", "card IDs preserved")
equal(candidate.cards[1].stacks, 2, "stack count preserved")
equal(candidate.cards[2].charges, 3, "charges preserved")
equal(candidate.effects.damage, 1.25, "full effects preserved")
equal(candidate.capacity, 4, "nonarray fields preserved")
equal(cache:restoreCandidate("steam:123", "pc2", empty, true), nil, "one outstanding attempt")
equal(cache:ackRestore(ticket, true), true, "acknowledge confirmed restore")
equal(cache:restoreCandidate("steam:123", "pc2", empty, true), nil, "one restore per incarnation")
equal(cache:ackRestore(ticket, true), false, "duplicate acknowledgment rejected")
equal(cache:restoreCandidate("steam:other", "pc9", empty, true), nil, "never cross users")

cache = seeded()
equal(cache:restoreCandidate("steam:123", "pc1", empty, true), nil, "departed incarnation cannot restore")
candidate, ticket = cache:restoreCandidate("steam:123", "pc2", empty, true)
candidate.cards[1].stacks = 99
equal(cache:ackRestore(ticket, false), false, "failed attempt not committed")
candidate, ticket = cache:restoreCandidate("steam:123", "pc2", empty, true)
equal(candidate.cards[1].stacks, 2, "retry returns pristine owned snapshot")
equal(cache:ackRestore(ticket, true), true, "retry succeeds")
equal(cache:disconnect("steam:123", "pc2"), true, "second disconnect")
candidate, ticket = cache:restoreCandidate("steam:123", "pc3", empty, true)
equal(candidate.cards[1].stacks, 2, "later connection may restore once again")

cache = seeded()
local native = { cards = { { id = "native-card", stacks = 3 } }, effects = {}, capacity = 4 }
equal(cache:restoreCandidate("steam:123", "pc2", native, false), nil, "native restoration takes precedence")
equal(cache:restoreCandidate("steam:123", "pc2", empty, true), nil, "never overwrite later empty state on same connection")
equal(cache:disconnect("steam:123", "pc2"), true, "native state can be retained")
candidate = cache:restoreCandidate("steam:123", "pc3", empty, true)
equal(candidate.cards[1].id, "native-card", "next disconnect retains current native state")
equal(#candidate.cards, 1, "old cards never merged into native cards")

cache = seeded()
candidate, ticket = cache:restoreCandidate("steam:123", "pc2", empty, true)
equal(cache:observe("steam:123", "pc2", native, false), true, "late native restore observed")
equal(cache:ackRestore(ticket, true), false, "late native state invalidates pending restore")
equal(next(cache.pending), nil, "cancelled native-state ticket is released")
equal(cache:restoreCandidate("steam:123", "pc2", empty, true), nil, "late native state prevents duplicate restore")

cache = seeded()
equal(cache:observe("steam:123", "pc1", empty, true), true, "departure cleanup sampled after freeze")
candidate = cache:restoreCandidate("steam:123", "pc2", empty, true)
equal(candidate.cards[1].id, "joker-a", "pre-departure freeze preserves the outgoing state")

cache = seeded()
equal(cache:observe("steam:123", "pc2", empty, true), true, "rejoin sample accepted")
candidate = cache:restoreCandidate("steam:123", "pc2", empty, true)
equal(candidate.cards[1].id, "joker-a", "empty rejoin sample does not destroy cache")
equal(cache:observe("steam:123", "pc1", empty, true), false, "stale sample cannot reactivate a retired incarnation")
equal(cache:restoreCandidate("steam:123", "pc1", empty, true), nil, "stale restore request cannot reactivate retired incarnation")

cache = RunState.new()
cache:beginMap("world-a", 1)
local mutable = { cards = { { id = "owned-card" } } }
cache:observe("eos:abc", "one", mutable, false)
mutable.cards[1].id = "mutated"
cache:disconnect("eos:abc", "one")
candidate = cache:restoreCandidate("eos:abc", "two", empty, true)
equal(candidate.cards[1].id, "owned-card", "capture is a deep copy")
equal(cache:disconnect("eos:abc", "one"), false, "stale disconnect cannot affect current connection")

cache = seeded()
candidate, ticket = cache:restoreCandidate("steam:123", "pc2", empty, true)
equal(cache:beginMap("world-a", 1), false, "same active map does not reset")
equal(cache:beginMap("world-a", 2), true, "same map new run resets")
equal(cache:restoreCandidate("steam:123", "pc3", empty, true), nil, "Jokers cannot cross replay generation")
equal(cache:ackRestore(ticket, true), false, "ticket cannot cross map boundary")
cache:observe("steam:123", "pc3", snapshot, false)
cache:disconnect("steam:123", "pc3")
cache:beginMap("world-b", 2)
equal(cache:restoreCandidate("steam:123", "pc4", empty, true), nil, "different world resets even with same generation")
cache:observe("steam:123", "pc4", snapshot, false)
cache:endMap()
equal(cache:observe("steam:123", "pc4", snapshot, false), false, "run ended prevents cache updates")
cache:beginMap("world-b", 2)
equal(cache:restoreCandidate("steam:123", "pc5", empty, true), nil, "session end resets same world and generation")

cache = RunState.new()
cache:beginMap("world-a", 1)
cache:observe("steam:123", "pc1", snapshot, false)
cache:observe("steam:123", "pc1", empty, true)
cache:disconnect("steam:123", "pc1")
equal(cache:restoreCandidate("steam:123", "pc2", empty, true), nil, "spent Jokers are not resurrected")
equal(cache:observe("", "pc1", snapshot, false), false, "empty ID rejected")
equal(cache:observe(nil, "pc1", snapshot, false), false, "missing ID rejected")
equal(cache:observe("steam:123", nil, snapshot, false), false, "missing incarnation rejected")
equal(cache:observe("steam:123", "pc1", snapshot, nil), false, "unknown inventory state rejected")
equal(cache:observe("steam:123", "pc1", setmetatable({}, {}), true), false, "wrapper table rejected")
equal(cache:observe("steam:123", "pc1", { object = function() end }, false), false, "function or UObject-like wrapper rejected")
equal(cache:observe("steam:123", "pc1", { value = math.huge }, false), false, "nonfinite snapshot rejected")
local cycle = {}; cycle.self = cycle
equal(cache:observe("steam:123", "pc1", cycle, false), false, "cycle rejected")
if io and io.stdout then
    equal(cache:observe("steam:123", "pc1", { handle = io.stdout }, false), false, "userdata rejected")
end
print("RunState: " .. checks .. " checks passed")
