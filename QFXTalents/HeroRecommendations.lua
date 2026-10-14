local _, ns = ...

local labels = {
    zhCN = {"应用推荐一", "应用推荐二", "主流", "样本使用率", "暂无有效样本", "英雄天赋", "英雄天赋统计不可用"},
    zhTW = {"套用推薦一", "套用推薦二", "主流", "樣本使用率", "暫無有效樣本", "英雄天賦", "英雄天賦統計無法使用"},
    enUS = {"Apply Build 1", "Apply Build 2", "Mainstream", "Sample usage", "No valid samples", "Hero talents", "Hero statistics unavailable"},
}
local L = labels[GetLocale()] or labels.enUS
local heroNames = {}

function ns.GetHeroUsagePercent(record, subtreeID)
    local heroes = record and record.heroRecommendations
    local total = record and tonumber(record.sampleCount) or 0
    if not heroes or not subtreeID or total <= 0 then return nil end
    local first = heroes[1]
    local firstPercent = first and math.floor(first.sampleCount * 100 / total + 0.5) or 0
    for index, hero in ipairs(heroes) do
        if hero.subtreeID == subtreeID then
            local percent = math.floor(hero.sampleCount * 100 / total + 0.5)
            if index == 2 and first and first.sampleCount + hero.sampleCount == total then
                percent = 100 - firstPercent
            end
            return percent, hero.sampleCount, total
        end
    end
    return 0, 0, total
end

local function HeroName(hero)
    if hero and heroNames[hero.subtreeID] then return heroNames[hero.subtreeID] end
    if hero and hero.subtreeID and not InCombatLockdown()
        and C_ClassTalents and C_ClassTalents.GetActiveConfigID
        and C_Traits and C_Traits.GetSubTreeInfo
    then
        local configID = C_ClassTalents.GetActiveConfigID()
        if configID and not (issecretvalue and issecretvalue(configID)) then
            local ok, info = pcall(C_Traits.GetSubTreeInfo, configID, hero.subtreeID)
            if ok and info and not (issecretvalue and issecretvalue(info.name)) and info.name then
                heroNames[hero.subtreeID] = info.name
                return info.name
            end
        end
    end
    return hero and hero.name or L[6]
end

function ns.CreateHeroRecommendationButtons(parent, apply)
    local buttons = {}
    for index = 1, 2 do
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(184, 25)
        button:SetPoint("BOTTOM", 0, index == 1 and 60 or 31)
        button:SetText(L[index])
        button:Disable()
        button:SetScript("OnClick", function() apply(index) end)
        if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(HeroName(self.qfxtHero))
            if self.qfxtHero and self.qfxtHero.sampleCount > 0 then
                GameTooltip:AddLine(string.format("%s: %d/%d (%d%%)", L[4],
                    self.qfxtHero.sampleCount, self.qfxtTotal, self.qfxtPercent), 1, 1, 1)
                if self.qfxtHero.sampleCount * 2 > self.qfxtTotal then
                    GameTooltip:AddLine(L[3], 0.2, 0.9, 0.4)
                end
            elseif self.qfxtLegacy then
                GameTooltip:AddLine(L[7], 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine(L[5], 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        ns.RegisterEUISkin(button, "buttonLabel")
        buttons[index] = button
    end
    return buttons[1], buttons[2]
end

function ns.UpdateHeroRecommendationButtons(panel, record, ready)
    local heroes = record and record.heroRecommendations
    local total = record and tonumber(record.sampleCount) or 0
    for index = 1, 2 do
        local button = index == 1 and panel.ImportButton or panel.ImportButtonTwo
        if button then
            local hero = heroes and heroes[index]
            local percent = hero and ns.GetHeroUsagePercent(record, hero.subtreeID) or 0
            button.qfxtHero, button.qfxtTotal, button.qfxtPercent = hero, total, percent
            button.qfxtLegacy = not heroes and record ~= nil and index == 1
            local text = L[index] .. (heroes and string.format(" (%d%%)", percent) or "")
            if button.qfxtLastText ~= text then
                button.qfxtLastText = text
                button:SetText(text)
            end
            local available = hero and hero.available and hero.sampleCount > 0
                or not heroes and index == 1 and record ~= nil
            if ready and available then button:Enable() else button:Disable() end
        end
    end
end
