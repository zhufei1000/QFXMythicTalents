local sourcePath = assert(arg[1], "Core.lua path is required")
local file = assert(io.open(sourcePath, "rb"))
local source = file:read("*a")
file:close()
local function Section(first, following)
    local start = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(following, start, true), following)
    return source:sub(start, finish - 1)
end

local chunk = [[
local env = ...
local API, ns, T = env.API, env.ns, {sample = "Samples", auto = "auto", manual = "manual"}
local currentSpecID = 250
local currentStats, currentStatsKey, currentStates, currentStatesContextKey, treeContext
local currentStatesDirty = true
local selectedMode, selectedDungeonID, selectedRaidID, selectedBossID = "dungeon", 1, 10, 100
local selectedRaidDifficultyID, selectedHeroRecommendation = 4, 1
local RAID_DIFFICULTY_HEROIC, RAID_DIFFICULTY_MYTHIC = 4, 5
local pendingStatisticsKey, statisticsDebounceTimer, refreshTimer
local statisticsBuildToken, panelRecoveryToken = 0, 0
local panelRecoveryTimer, panelPositionTimer, visibilitySyncTimer
local forceOverlayRefresh, refreshQueued, pluginSuspended = false, false, false
local ScheduleRefresh
local frameOffsetApplied = false
local talentFrame, sidePanel = env.talentFrame, env.sidePanel
local function CurrentSpecID() return 250 end
local function CurrentClassToken() return "DEATHKNIGHT" end
local function EnsureDataLoaded() env.loaded = env.loaded + 1 end
local function GetCurrentRecommendation() return env.record end
local function CreateStatisticsBuilder() env.builds = env.builds + 1; return {} end
local function ProcessStatisticsSample() return false end
local function FinishStatistics() return env.stats end
local function ResolveCurrentEntryID() return currentStats.choice end
local function DecorateButton() env.decorated = env.decorated + 1 end
local function DecorateHeroSpecButton() end
local function DataStatusText() return "DB" end
local function RaidDifficultyName() return "Heroic" end
local function SetButtonSelected() end
local function SetOperationalEventsEnabled() end
local function GetUnifiedDataAPI() return env.backend end
local function PositionSidePanel() env.positions = env.positions + 1 end
local function GetRaids() return {{id = 10}} end
local function FindBoss() return {} end
local function FindDungeon() return {} end
local function GetCurrentRecommendationText() return "IMPORT" end
local function GetRecommendedLoadoutName() return "QFX_Test" end
local function OpenImport() error("unexpected fallback") end
local function AutoSelectContent() error("unexpected auto selection") end
]]
    .. Section("local function CancelStatisticsBuild()", "CompactDataProvider = function")
    .. Section("local function CurrentSelectionKey()", "local function StateKey(")
    .. Section("local STATISTICS_FRAME_BUDGET", "local function GetCurrentNodeState(")
    .. Section("local function RefreshPanelSelection()", "local function AutoSelectContent()")
    .. [[
RebuildContentButtons = function() env.lists = env.lists + 1; RefreshPanelSelection() end
]]
    .. Section("local function ApplyRecommendation(", "local selectionVisualButtons")
    .. Section("local function AdjustTalentFrameOffset()", "SuspendAddon = function")
    .. Section("local function IsTalentFrameVisible()", "local function InitializeBlizzardUI()")
    .. [[
return {
    refresh = function(force) ScheduleRefresh(0, force) end,
    selectDungeon = SelectDungeon, selectBoss = SelectBoss, selectDifficulty = SelectRaidDifficulty,
    setMode = SetMode, apply = ApplyRecommendation,
    show = ShowPanel, hide = HidePanel, recover = RecoverPanelAfterNativeTransition,
    snapshot = function() return currentStats, currentStates, currentStatsKey end,
    offset = AdjustTalentFrameOffset,
}
]]

local timers = {}
local function RunTimers()
    local queued = timers
    timers = {}
    for _, timer in ipairs(queued) do
        if not timer.cancelled then timer.callback() end
    end
end
C_Timer = {
    NewTimer = function(delay, callback)
        local timer = {delay = delay, callback = callback,
            Cancel = function(self) self.cancelled = true end}
        timers[#timers + 1] = timer
        return timer
    end,
    After = function() error("refresh retries must use cancellable timers") end,
}
GetTime = function() return 0 end
QFXTalentsDB = {}
local env = {builds = 0, decorated = 0, loaded = 0, lists = 0, positions = 0, exports = 0}
InCombatLockdown = function() return false end
env.stats = {treeID = 10, configID = 20, validSamples = 30, choice = 301}
env.record = {sampleCount = 50, sourceRankLimit = 50, heroRecommendations = {{}, {}}}
env.talentFrame = {visible = true, tree = 10, config = 20}
function env.talentFrame:IsVisible() return self.visible end
function env.talentFrame:GetTalentTreeID() return self.tree end
function env.talentFrame:GetConfigID() return self.config end
function env.talentFrame:EnumerateAllTalentButtons() return ipairs({{}}) end
env.sidePanel = {shown = true, Sample = {SetText = function(_, text) env.sampleText = text end}}
function env.sidePanel:IsShown() return self.shown end
function env.sidePanel:Show() self.shown = true end
function env.sidePanel:Hide() self.shown = false end
function env.sidePanel:IsVisible() return self.shown end
function env.sidePanel:GetWidth() return 200 end
local offsets = 0
PlayerSpellsFrame = {IsVisible = function() return env.talentFrame.visible end,
    AdjustPointsOffset = function(_, x, y) assert(x == -100 and y == 0); offsets = offsets + 1 end}
C_Traits = {GetTreeNodes = function() return {1} end,
    GetNodeInfo = function() return {activeRank = 1} end}
env.API = {IsDataReady = function() return true end,
    ApplyLoadoutText = function() end,
    Loadouts = {
        OnShown = function() env.exports = env.exports + 1 end,
        OnHidden = function() end,
        OnSelectionChanged = function() error("content selection must not rebuild personal loadouts") end,
    }}
env.ns = {UpdateHeroRecommendationButtons = function() end}
env.backend = {ReleaseActiveSpec = function() end}
local addon = assert((loadstring or load)(chunk))(env)
addon.refresh(true)
RunTimers(); RunTimers(); RunTimers()
local stats, states, key = addon.snapshot()
assert(stats == env.stats and states[1].entryID == 301 and key)
assert(env.sampleText == "Samples：50/50", "the footer must count both heroes' samples")
local builds = env.builds
addon.selectDungeon(1, false)
addon.setMode("dungeon")
addon.apply(1)
addon.show()
addon.show(); addon.offset()
RunTimers()
assert(env.builds == builds and env.exports == 0 and env.lists == 0,
    "same selection, same hero and repeated Show must reuse existing work")
assert(offsets == 1, "repeated Show must not accumulate frame offsets")

addon.recover(); addon.recover(); addon.recover()
RunTimers(); RunTimers()
assert(env.builds == builds, "native config event bursts must retain unchanged statistics")
env.stats = {treeID = 10, configID = 20, validSamples = 20, choice = 302}
addon.apply(2)
RunTimers(); RunTimers(); RunTimers()
stats, states = addon.snapshot()
assert(env.builds == builds + 1 and states[1].entryID == 302,
    "hero changes must rebuild recommendation-dependent node state")

env.talentFrame.config = 21
env.stats = {treeID = 10, configID = 21, validSamples = 20, choice = 302}
addon.recover()
RunTimers(); RunTimers(); RunTimers(); RunTimers()
assert(env.builds == builds + 2, "a changed config must rebuild statistics")

env.talentFrame.tree = nil
addon.refresh(true)
RunTimers()
assert(#timers == 1 and timers[1].delay == 0.15, "missing config retries must coalesce")
addon.refresh()
assert(#timers == 1)
addon.hide()
RunTimers()
assert(#timers == 0, "hiding the panel must cancel retry timers")
stats, states = addon.snapshot()
assert(stats == nil and states == nil)
addon.refresh()
assert(#timers == 0, "a hidden panel must not queue refreshes")
print("Refresh lifecycle passed: coalescing, cancellation, cache reuse, hero/config invalidation, total samples")
