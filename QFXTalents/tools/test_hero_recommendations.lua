local path = assert(arg[1], "HeroRecommendations.lua path is required")
local locale = "zhCN"
function GetLocale() return locale end
function InCombatLockdown() return false end
local methods = {}
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetPoint(...) self.point = {...} end
function methods:SetText(text) self.text = text end
function methods:SetScript(event, handler) self[event] = handler end
function methods:SetMotionScriptsWhileDisabled(value) self.disabledMotion = value end
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function CreateFrame() return setmetatable({}, {__index = methods}) end
GameTooltip = {lines = {}}
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:SetText(text) self.title = text end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
C_ClassTalents = {GetActiveConfigID = function() return 10 end}
C_Traits = {GetSubTreeInfo = function(_, id) return {name = "Localized Hero " .. id} end}

for _, lang in ipairs({"zhCN", "zhTW", "enUS"}) do
    locale = lang
    local ns = {RegisterEUISkin = function() end}
    assert(loadfile(path))("QFXTalents", ns)
    local clicked
    local panel = {}
    panel.ImportButton, panel.ImportButtonTwo = ns.CreateHeroRecommendationButtons({}, function(index) clicked = index end)
    local record = {sampleCount = 50, heroRecommendations = {
        {subtreeID = 1, sampleCount = 35, available = true, name = "One"},
        {subtreeID = 2, sampleCount = 15, available = true, name = "Two"},
    }}
    ns.UpdateHeroRecommendationButtons(panel, record, true)
    local percent, count, total = ns.GetHeroUsagePercent(record, 1)
    assert(percent == 70 and count == 35 and total == 50)
    assert(ns.GetHeroUsagePercent(record, 2) == 30)
    assert(panel.ImportButton.enabled and panel.ImportButtonTwo.enabled)
    assert(panel.ImportButton.text:find("70%%") and panel.ImportButtonTwo.text:find("30%%"))
    panel.ImportButtonTwo.OnClick()
    assert(clicked == 2)
    panel.ImportButtonTwo:OnEnter()
    assert(GameTooltip.title == "Localized Hero 2")
    assert(#GameTooltip.lines == 1)
    record.heroRecommendations[1].sampleCount = 25
    record.heroRecommendations[2].sampleCount = 25
    ns.UpdateHeroRecommendationButtons(panel, record, true)
    assert(panel.ImportButton.text:find("50%%") and panel.ImportButtonTwo.text:find("50%%"))
    assert(ns.GetHeroUsagePercent(record, 1) == 50 and ns.GetHeroUsagePercent(record, 2) == 50)
    panel.ImportButton:OnEnter()
    assert(#GameTooltip.lines == 1)
    record.heroRecommendations[1].sampleCount = 50
    record.heroRecommendations[2].sampleCount = 0
    record.heroRecommendations[2].available = false
    ns.UpdateHeroRecommendationButtons(panel, record, true)
    assert(panel.ImportButton.enabled and not panel.ImportButtonTwo.enabled)
    assert(ns.GetHeroUsagePercent(record, 1) == 100 and ns.GetHeroUsagePercent(record, 2) == 0)
    assert(panel.ImportButtonTwo.disabledMotion and panel.ImportButtonTwo.text:find("0%%"))
    panel.ImportButtonTwo:OnEnter()
    assert(GameTooltip.title == "Localized Hero 2")
    ns.UpdateHeroRecommendationButtons(panel, record, false)
    assert(not panel.ImportButton.enabled and not panel.ImportButtonTwo.enabled)
    ns.UpdateHeroRecommendationButtons(panel, {sampleCount = 10}, true)
    assert(ns.GetHeroUsagePercent({sampleCount = 10}, 1) == nil)
    assert(panel.ImportButton.enabled and not panel.ImportButtonTwo.enabled)
    assert(not panel.ImportButton.text:find("%%"))
    ns.UpdateHeroRecommendationButtons(panel, nil, false)
    assert(not panel.ImportButton.enabled and not panel.ImportButtonTwo.enabled)
    record.sampleCount = 8
    record.heroRecommendations[1].sampleCount = 1
    record.heroRecommendations[2].sampleCount = 7
    record.heroRecommendations[2].available = true
    ns.UpdateHeroRecommendationButtons(panel, record, true)
    assert(panel.ImportButton.text:find("13%%") and panel.ImportButtonTwo.text:find("87%%"))
    assert(ns.GetHeroUsagePercent(record, 1) == 13 and ns.GetHeroUsagePercent(record, 2) == 87)
end
print("Hero recommendation buttons passed: 70/30, 50/50, 100/0, disabled, legacy, three locales")
