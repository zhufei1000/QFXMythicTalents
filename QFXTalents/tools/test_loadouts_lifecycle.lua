local sourcePath = assert(arg[1], "Loadouts.lua path is required")
local file = assert(io.open(sourcePath, "rb"))
local source = file:read("*a")
file:close()
local function Section(first, following)
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(following, start, true))
    return source:sub(start, finish - 1)
end
local chunk = [[
local env = ...
local API, Loadouts, section, events = env.API, {}, env.section, env.events
local TLE_ADDON_NAME = "TalentLoadoutsEx"
local operationalEventsEnabled, suppressed, suppressionAnnounced = false, false, false
local selectedIndex, currentExportCache, exportRefreshTimer
local function T() return {tleDetected = "detected"} end
local function RefreshCurrentExport() env.exports = env.exports + 1 end
local function Rebuild() env.rebuilds = env.rebuilds + 1 end
local function UpdateButtons() end
]]
    .. Section("local function SpecList()", "local function SpecIcon()")
    .. Section("local OPERATIONAL_EVENTS =", 'events:RegisterEvent("ADDON_LOADED")')
    .. source:sub((assert(source:find('events:RegisterEvent("ADDON_LOADED")', 1, true))))
    .. [[
return Loadouts, SpecList, UpdateSuppression, function()
    exportRefreshTimer = {Cancel = function() env.cancelled = env.cancelled + 1 end}
end
]]
local inspectingSpec = 251
GetSpecialization = function() return 1 end
GetSpecializationInfo = function() return 250 end
QFXTalentsDB = {loadouts = {['250'] = {{name = "Own"}}, ['251'] = {{name = "Other spec"}}}}
local runningTLE = false
C_AddOns = {IsAddOnLoaded = function() return runningTLE end}
local env = {exports = 0, rebuilds = 0, registered = 0, unregistered = 0, cancelled = 0,
    API = {GetCurrentSpecID = function() return inspectingSpec end},
    section = {Hide = function() end, Show = function() end, IsVisible = function() return true end}}
local timers = {}
C_Timer = {NewTimer = function(_, callback)
    local timer = {callback = callback, Cancel = function(self) self.cancelled = true end}
    timers[#timers + 1] = timer
    return timer
end}
env.events = {RegisterEvent = function() env.registered = env.registered + 1 end,
    UnregisterEvent = function() env.unregistered = env.unregistered + 1 end,
    SetScript = function(_, _, handler) env.handler = handler end}
local loadouts, list, suppress, queue = assert((loadstring or load)(chunk))(env)
assert(list() == QFXTalentsDB.loadouts['250'], "inspection must not change the personal loadout bucket")
loadouts.OnShown(); loadouts.OnShown()
assert(env.exports == 1 and env.rebuilds == 1 and env.registered == 6)
env.handler(nil, "PLAYER_SPECIALIZATION_CHANGED", "party1")
assert(#timers == 0, "another player's spec change must be ignored")
env.handler(nil, "PLAYER_SPECIALIZATION_CHANGED", "player")
env.handler(nil, "TRAIT_NODE_CHANGED")
env.handler(nil, "TRAIT_CONFIG_UPDATED")
for _, timer in ipairs(timers) do
    if not timer.cancelled then timer.callback() end
end
assert(env.exports == 2 and env.rebuilds == 2, "spec and trait bursts must export and rebuild only once")
queue()
runningTLE = true
suppress()
assert(env.unregistered == 5 and env.cancelled == 1,
    "suppression must stop operational events and pending work")
loadouts.OnShown(); loadouts.OnHidden()
assert(env.exports == 2 and env.rebuilds == 2 and env.unregistered == 5)
assert(loadouts.OnSelectionChanged == nil, "the redundant content-selection bridge must be removed")
print("Personal loadout lifecycle passed: own specialization, idempotent show/hide, suppression cancellation")
