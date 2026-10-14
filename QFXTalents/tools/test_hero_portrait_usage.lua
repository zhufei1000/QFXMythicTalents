local corePath = assert(arg[1], "Core.lua path is required")
local heroPath = assert(arg[2], "HeroRecommendations.lua path is required")
local file = assert(io.open(corePath, "rb"))
local source = file:read("*a")
file:close()
function GetLocale() return "enUS" end
local ns = {}
assert(loadfile(heroPath))("QFXTalents", ns)

local function Section(first, following)
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(following, start, true))
    return source:sub(start, finish - 1)
end

local chunk = [[
local ns = ...
local currentStats, currentSpecID, talentFrame, percentagesEnabled, record, selected
local function StateKey(entryID, rank) return entryID .. ":" .. rank end
local function GetCurrentRecommendation() return record end
local function GetHeroSelectionState() return selected, 30 end
local function EnsureHeroSpecRegions() end
local function PositionHeroSpecBadge() end
local function PercentColor() return 1, 1, 1 end
]]
    .. Section("local function GetStatePercent(", "local function GetHeroSelectionState(")
    .. Section("local function DecorateHeroSpecButton(", "local function IsChoiceNode(")
    .. [[
return function(stats, recommendation, subtreeID, entryID, enabled)
    currentStats, currentSpecID, record = stats, 250, recommendation
    selected = {entryID = entryID, rank = 1}
    percentagesEnabled = enabled ~= false
    local button = {shown = false, text = ""}
    local badge = {}
    function badge:Show() button.shown = true end
    function badge:Hide() button.shown = false end
    function badge:SetBackdropBorderColor() end
    button.qfxtHeroPercentFrame = badge
    button.qfxtHeroPercent = {
        SetText = function(_, text) button.text = text end,
        SetTextColor = function() end,
    }
    talentFrame = {HeroTalentsContainer = {
        HeroSpecButton = button,
        activeSubTreeInfo = subtreeID and {ID = subtreeID} or nil,
    }}
    DecorateHeroSpecButton()
    local childPercent = GetStatePercent(stats, 20, {entryID = 200, rank = 1})
    return button.text, button.shown, childPercent
end
]]
local render = assert((loadstring or load)(chunk))(ns)
local record = {sampleCount = 50, heroRecommendations = {
    {subtreeID = 1, sampleCount = 30},
    {subtreeID = 2, sampleCount = 20},
}}
local first = {
    validSamples = 30,
    counts = {[20] = {["200:1"] = 24}},
    entryUsage = {[30] = {[300] = 30}},
}
local second = {
    validSamples = 20,
    counts = {[20] = {["200:1"] = 16}},
    entryUsage = {[30] = {[301] = 20}},
}
local text, shown, child = render(first, record, 1, 300)
assert(text == "60%" and shown and child == 80)
text, shown, child = render(second, record, 2, 301)
assert(text == "40%" and shown and child == 80)
-- The displayed portrait, not the recommendation index, identifies the hero.
assert(render(first, record, 2, 301) == "40%")
record.heroRecommendations[1].sampleCount = 25
record.heroRecommendations[2].sampleCount = 25
assert(render(first, record, 1, 300) == "50%")
record.heroRecommendations[1].sampleCount = 50
record.heroRecommendations[2].sampleCount = 0
assert(render(first, record, 1, 300) == "100%")
assert(render(first, record, 2, 301) == "0%")
text, shown = render(first, record, nil, 300)
assert(text == "" and not shown)
text, shown = render(first, record, 1, 300, false)
assert(text == "" and not shown)
local legacy = {sampleCount = 50}
first.validSamples = 50
assert(render(first, legacy, 1, 300) == "60%")
print("Hero portrait passed: total-population 60/40; child-node 80/80; ties, zero usage, legacy, hidden")
