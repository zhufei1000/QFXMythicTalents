-- QFXTalents Loadouts: personal loadout management embedded in the
-- recommendation panel. Personal loadouts are stored per specialization in
-- QFXTalentsDB.loadouts and applied through ApplyEngine.

local ADDON, ns = ...

local API = _G.QFXTalents

local Loadouts = {}
API.Loadouts = Loadouts

local TLE_ADDON_NAME = "TalentLoadoutsEx"
local ROW_HEIGHT = 32

local section
local suppressed = false
local suppressionAnnounced = false
local selectedIndex
local currentExportCache
local exportRefreshTimer
local rebuildTimer

local events = CreateFrame("Frame")

local EMPTY_TRANSLATIONS = {}

local function T()
    return API.T or EMPTY_TRANSLATIONS
end

local function SpecList()
    local root = _G.QFXTalentsDB
    if not root then
        return nil
    end
    root.loadouts = root.loadouts or {}
    local specID = API.GetCurrentSpecID and API:GetCurrentSpecID()
    local key = tostring(specID or 0)
    root.loadouts[key] = root.loadouts[key] or {}
    return root.loadouts[key]
end

local function SpecIcon()
    local index = GetSpecialization()
    if index then
        local _, _, _, icon = GetSpecializationInfo(index)
        if icon then
            return icon
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function UniqueName(list, base)
    base = strtrim(tostring(base or ""))
    if base == "" then
        base = T().newLoadoutName or "New Loadout"
    end
    local existing = {}
    for _, entry in ipairs(list) do
        existing[entry.name] = true
    end
    if not existing[base] then
        return base
    end
    local suffix = 2
    while existing[base .. " " .. suffix] do
        suffix = suffix + 1
    end
    return base .. " " .. suffix
end

local Message = API.AddMessage

------------------------------------------------------------------
-- Actions

local Rebuild
local UpdateButtons
local RefreshCurrentExport

local function SaveLoadout(name)
    if PlayerSpellsFrame
        and PlayerSpellsFrame.IsInspecting
        and PlayerSpellsFrame:IsInspecting()
    then
        Message(T().applyInspecting, 1, 0.4, 0.2)
        return
    end
    local list = SpecList()
    if not list then
        return
    end
    local ok, text = pcall(function()
        return API.ExportCurrentLoadout and API.ExportCurrentLoadout()
    end)
    if not ok or not text or text == "" then
        Message(T().saveFailed, 1, 0.4, 0.2)
        local reason = not ok and text or API.lastLoadoutError
        if reason then
            print("|cff00ccffQFXTalents|r: save failed - " .. tostring(reason))
        end
        return
    end
    list[#list + 1] = {
        name = UniqueName(list, name),
        icon = SpecIcon(),
        text = text,
    }
    selectedIndex = #list
    currentExportCache = text
    Rebuild()
end

local function RenameSelected(name)
    local list = SpecList()
    local entry = list and selectedIndex and list[selectedIndex]
    if not entry then
        return
    end
    name = strtrim(tostring(name or ""))
    if name == "" or name == entry.name then
        return
    end
    local existing = false
    for index, other in ipairs(list) do
        if index ~= selectedIndex and other.name == name then
            existing = true
            break
        end
    end
    entry.name = not existing and name or UniqueName(list, name)
    Rebuild()
end

local function DeleteSelected()
    local list = SpecList()
    if not (list and selectedIndex and list[selectedIndex]) then
        return
    end
    table.remove(list, selectedIndex)
    if selectedIndex > #list then
        selectedIndex = #list > 0 and #list or nil
    end
    Rebuild()
end

local function MoveSelected(delta)
    local list = SpecList()
    if not (list and selectedIndex and list[selectedIndex]) then
        return
    end
    local target = selectedIndex + delta
    if target < 1 or target > #list then
        return
    end
    list[selectedIndex], list[target] = list[target], list[selectedIndex]
    selectedIndex = target
    Rebuild()
end

local function ApplyText(text, name)
    if text and text ~= "" and API.ApplyLoadoutText then
        API.ApplyLoadoutText(text, name)
    end
end

local function LoadSelected()
    local list = SpecList()
    local entry = list and selectedIndex and list[selectedIndex]
    if entry then
        ApplyText(entry.text, entry.name)
    end
end

local function RequestRebuild()
    if rebuildTimer then
        rebuildTimer:Cancel()
    end
    rebuildTimer = C_Timer.NewTimer(0.20, function()
        rebuildTimer = nil
        Rebuild()
    end)
end

RefreshCurrentExport = function()
    currentExportCache = API.ExportCurrentLoadout and API.ExportCurrentLoadout() or nil
end

------------------------------------------------------------------
-- Static popups

local function GetPopupEditBox(dialog)
    return dialog and (dialog.EditBox or dialog.editBox) or nil
end

StaticPopupDialogs["QFXTALENTS_SAVE_LOADOUT"] = {
    text = T().saveTitle or "Save current talent loadout",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 48,
    OnShow = function(self)
        local editBox = GetPopupEditBox(self)
        if editBox then
            editBox:SetText(T().newLoadoutName or "New Loadout")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    OnAccept = function(self)
        local editBox = GetPopupEditBox(self)
        SaveLoadout(editBox and editBox:GetText() or nil)
    end,
    EditBoxOnEnterPressed = function(self)
        SaveLoadout(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["QFXTALENTS_RENAME_LOADOUT"] = {
    text = T().renameTitle or "Rename loadout",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 48,
    OnShow = function(self)
        local list = SpecList()
        local entry = list and selectedIndex and list[selectedIndex]
        local editBox = GetPopupEditBox(self)
        if editBox then
            editBox:SetText(entry and entry.name or "")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    OnAccept = function(self)
        local editBox = GetPopupEditBox(self)
        RenameSelected(editBox and editBox:GetText() or nil)
    end,
    EditBoxOnEnterPressed = function(self)
        RenameSelected(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["QFXTALENTS_DELETE_LOADOUT"] = {
    text = T().deleteConfirm or "Delete %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        DeleteSelected()
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

------------------------------------------------------------------
-- List UI

local scrollBox
local scrollBar
local dataProvider
local emptyHint
local actionButtons = {}

local selectionVisualRows = setmetatable({}, { __mode = "k" })

-- Selection colors. While EllesmereUI's skin is active the row highlight
-- follows the user's accent color (the house selection language is an accent
-- rail); otherwise the original gold wash is kept and the rail stays hidden.
local function ApplyRowSelectionColors(button)
    local skin = ns.GetEUISkin and ns.GetEUISkin()
    if skin and skin.GetAccentColor then
        local r, g, b = skin.GetAccentColor()
        button.SelectedBar:SetColorTexture(r, g, b, 0.13)
        button.SelectedRail:SetColorTexture(r, g, b, 0.90)
    else
        button.SelectedBar:SetColorTexture(1.00, 0.82, 0.10, 0.14)
        button.SelectedRail:SetColorTexture(1.00, 0.82, 0.10, 0)
    end
end

local function CreateRowVisuals(button)
    -- The row content lives on an overlay child frame. EllesmereUI's skin
    -- passes (and the re-strip that runs when the talent window re-shows) fade
    -- every texture region on a skinned button, but never a child frame's own
    -- textures, so the icon / check mark / selection wash survive the skin.
    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:SetFrameLevel(button:GetFrameLevel() + 1)

    button.Icon = host:CreateTexture(nil, "ARTWORK")
    button.Icon:SetPoint("LEFT", 7, 0)
    button.Icon:SetSize(24, 24)
    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.Name = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.Name:SetPoint("LEFT", button.Icon, "RIGHT", 8, 0)
    button.Name:SetPoint("RIGHT", button, "RIGHT", -26, 0)
    button.Name:SetJustifyH("LEFT")
    button.Name:SetWordWrap(false)

    button.Check = host:CreateTexture(nil, "OVERLAY")
    button.Check:SetPoint("RIGHT", -6, 0)
    button.Check:SetSize(16, 16)
    button.Check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    button.Check:Hide()

    button.SelectedBar = host:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.SelectedBar:SetAllPoints()
    button.SelectedBar:SetColorTexture(1.00, 0.82, 0.10, 0.14)
    button.SelectedBar:Hide()

    -- Left rail, the same selection language as the recommendation rows.
    button.SelectedRail = host:CreateTexture(nil, "OVERLAY", nil, 2)
    button.SelectedRail:SetPoint("TOPLEFT", 2, -3)
    button.SelectedRail:SetPoint("BOTTOMLEFT", 2, 3)
    button.SelectedRail:SetWidth(3)
    button.SelectedRail:SetColorTexture(1.00, 0.82, 0.10, 0)
    button.SelectedRail:Hide()

    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    selectionVisualRows[button] = true
    ApplyRowSelectionColors(button)
end

if ns.RegisterEUISkinLooks then
    ns.RegisterEUISkinLooks(function()
        for button in pairs(selectionVisualRows) do
            ApplyRowSelectionColors(button)
        end
    end)
end

local function InitRow(button, elementData)
    if not button.qfxtRowBuilt then
        button.qfxtRowBuilt = true
        CreateRowVisuals(button)
        ns.RegisterEUISkin(button, "button")
        -- One set of handlers per pooled row; they read the row's stored data
        -- instead of capturing per-refresh closures.
        button:SetScript("OnClick", function(self)
            local rowData = self.qfxtRowData
            if not rowData or selectedIndex == rowData.index then
                return
            end
            local previous = selectedIndex
            selectedIndex = rowData.index
            -- 选中切换只重绘受影响的两个可见行（旧选中 + 新选中），避免
            -- 每次点击都全量 Flush + 重插列表；拿不到行数据时回退到 Rebuild。
            local frames = scrollBox:GetFrames()
            local updated = false
            for _, row in ipairs(frames) do
                local otherData = row.qfxtRowData
                if otherData
                    and (otherData.index == previous or otherData.index == selectedIndex)
                then
                    InitRow(row, otherData)
                    updated = true
                end
            end
            if not updated then
                Rebuild()
            end
            UpdateButtons()
        end)
        button:SetScript("OnDoubleClick", function(self)
            local rowData = self.qfxtRowData
            if rowData then
                selectedIndex = rowData.index
                LoadSelected()
            end
        end)
        button:SetScript("OnEnter", function(self)
            local rowData = self.qfxtRowData
            if not rowData then
                return
            end
            local isLoaded = currentExportCache ~= nil and rowData.text == currentExportCache
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(rowData.name or "")
            GameTooltip:AddLine(T().rowHint, 0.75, 0.85, 1, true)
            if isLoaded then
                GameTooltip:AddLine(T().loadedTooltip, 0.35, 0.95, 0.55)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
    end

    local isLoaded = currentExportCache ~= nil and elementData.text == currentExportCache
    local isSelected = elementData.index == selectedIndex

    if elementData.icon then
        button.Icon:SetTexture(elementData.icon)
        button.Icon:Show()
    else
        button.Icon:Hide()
    end
    button.Name:SetText(elementData.name or "")
    if isLoaded then
        button.Name:SetTextColor(0.55, 0.95, 0.75)
    else
        button.Name:SetTextColor(1, 1, 1)
    end
    button.Check:SetShown(isLoaded)
    button.SelectedBar:SetShown(isSelected)
    button.SelectedRail:SetShown(isSelected)

    button.qfxtRowData = elementData
end

Rebuild = function()
    if not (section and scrollBox and dataProvider) then
        return
    end
    if not section:IsVisible() then
        return
    end

    dataProvider:Flush()

    local list = SpecList() or {}
    if selectedIndex and (selectedIndex > #list or selectedIndex < 1) then
        selectedIndex = #list > 0 and #list or nil
    end

    for index, entry in ipairs(list) do
        dataProvider:Insert({
            index = index,
            name = entry.name,
            icon = entry.icon,
            text = entry.text,
        })
    end

    if emptyHint then
        emptyHint:SetShown(#list == 0)
    end
    UpdateButtons()
end

UpdateButtons = function()
    local visible = section ~= nil and section:IsVisible()
    -- The buttons only matter while the section is on screen; Rebuild/OnShown
    -- repaints them before the next time they can be clicked.
    if not visible then
        return
    end

    local list = SpecList() or {}
    local hasSelection = selectedIndex ~= nil and list[selectedIndex] ~= nil
    local combat = InCombatLockdown()
    for name, button in pairs(actionButtons) do
        if combat then
            button:Disable()
        elseif name == "save" then
            button:Enable()
        else
            button:SetEnabled(hasSelection)
        end
    end
end

------------------------------------------------------------------
-- Section construction

local function CreateActionButton(parent, name, label, onClick, anchor)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(60, 22)
    button:SetPoint(unpack(anchor))
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    ns.RegisterEUISkin(button, "buttonLabel")
    actionButtons[name] = button
    return button
end

function Loadouts.Populate(parent)
    section = parent

    section.Header = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    section.Header:SetPoint("TOP", 0, -6)
    section.Header:SetText(T().myLoadouts)
    ns.RegisterEUISkin(section.Header, "font")

    section.HeaderDivider = section:CreateTexture(nil, "BORDER")
    section.HeaderDivider:SetPoint("TOPLEFT", 2, -22)
    section.HeaderDivider:SetPoint("TOPRIGHT", -2, -22)
    section.HeaderDivider:SetHeight(1)
    section.HeaderDivider:SetColorTexture(0.32, 0.48, 0.58, 0.55)

    scrollBox = CreateFrame("Frame", nil, section, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", section, "TOPLEFT", 4, -27)
    scrollBox:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -16, -58)

    scrollBar = CreateFrame("EventFrame", nil, section, "WowTrimScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 1, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 1, 0)
    ns.RegisterEUISkin(scrollBar, "scrollbar")

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetPadding(1, 1, 2, 1, 0)
    view:SetElementInitializer("Button", InitRow)
    dataProvider = CreateDataProvider()
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)

    -- Do not show a dead scrollbar when there are no saved loadouts (or all
    -- rows fit). It becomes visible automatically only when scrolling exists.
    scrollBar:Hide()
    local function UpdateScrollBar()
        scrollBar:SetShown(scrollBox:HasScrollableExtent())
    end
    scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, UpdateScrollBar)
    scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, UpdateScrollBar)

    emptyHint = section:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyHint:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
    emptyHint:SetWidth(156)
    emptyHint:SetText(T().emptyLoadouts .. "\n" .. T().emptyHint)
    emptyHint:Hide()
    ns.RegisterEUISkin(emptyHint, "font")

    CreateActionButton(section, "save", T().save, function()
        if InCombatLockdown() then
            Message(T().combatButtons, 1, 0.55, 0.10)
            return
        end
        StaticPopup_Show("QFXTALENTS_SAVE_LOADOUT")
    end, { "BOTTOMLEFT", section, "BOTTOMLEFT", 3, 30 })

    CreateActionButton(section, "load", T().load, function()
        LoadSelected()
    end, { "BOTTOM", section, "BOTTOM", 0, 30 })

    CreateActionButton(section, "edit", T().edit, function()
        if InCombatLockdown() then
            Message(T().combatButtons, 1, 0.55, 0.10)
            return
        end
        StaticPopup_Show("QFXTALENTS_RENAME_LOADOUT")
    end, { "BOTTOMRIGHT", section, "BOTTOMRIGHT", -3, 30 })

    CreateActionButton(section, "moveUp", T().moveUp, function()
        MoveSelected(-1)
    end, { "BOTTOMLEFT", section, "BOTTOMLEFT", 3, 4 })

    CreateActionButton(section, "delete", T().delete, function()
        if InCombatLockdown() then
            Message(T().combatButtons, 1, 0.55, 0.10)
            return
        end
        local list = SpecList()
        local entry = list and selectedIndex and list[selectedIndex]
        StaticPopup_Show("QFXTALENTS_DELETE_LOADOUT", entry and entry.name or "")
    end, { "BOTTOM", section, "BOTTOM", 0, 4 })

    CreateActionButton(section, "moveDown", T().moveDown, function()
        MoveSelected(1)
    end, { "BOTTOMRIGHT", section, "BOTTOMRIGHT", -3, 4 })

    UpdateButtons()
end

------------------------------------------------------------------
-- Own lightweight events. Only ADDON_LOADED is permanent (it waits for the
-- original TalentLoadoutsEx); the rest are registered while the panel is
-- visible, so a closed panel costs nothing.

local OPERATIONAL_EVENTS = {
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "TRAIT_NODE_CHANGED",
}

local function SetOperationalEventsEnabled(enabled)
    enabled = not not enabled
    for _, event in ipairs(OPERATIONAL_EVENTS) do
        if enabled then
            events:RegisterEvent(event)
        else
            events:UnregisterEvent(event)
        end
    end
end

------------------------------------------------------------------
-- Suppression by the original TalentLoadoutsEx

local function IsTLERunning()
    return C_AddOns
        and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded(TLE_ADDON_NAME)
end

local function UpdateSuppression()
    local now = IsTLERunning() and true or false
    if now == suppressed then
        return
    end
    suppressed = now
    if suppressed then
        if section then
            section:Hide()
        end
        if not suppressionAnnounced then
            suppressionAnnounced = true
            print("|cff00ccffQFXTalents|r：" .. T().tleDetected)
        end
    else
        if section then
            section:Show()
            RefreshCurrentExport()
            Rebuild()
        end
    end
    if API.RefreshFooterAnchor then
        API:RefreshFooterAnchor()
    end
end

function Loadouts.IsSuppressed()
    return suppressed
end

------------------------------------------------------------------
-- Lifecycle bridge used by Core.lua

function Loadouts.OnShown()
    UpdateSuppression()
    if suppressed then
        return
    end
    SetOperationalEventsEnabled(true)
    selectedIndex = nil
    RefreshCurrentExport()
    Rebuild()
end

function Loadouts.OnHidden()
    SetOperationalEventsEnabled(false)
    if rebuildTimer then
        rebuildTimer:Cancel()
        rebuildTimer = nil
    end
    if exportRefreshTimer then
        exportRefreshTimer:Cancel()
        exportRefreshTimer = nil
    end
end

function Loadouts.OnSelectionChanged()
    if section and section:IsVisible() then
        RequestRebuild()
    end
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == TLE_ADDON_NAME then
            UpdateSuppression()
        end
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- 该事件也会为队友触发（unit event），只响应玩家自己的专精变化，
        -- 与 Core.lua 的过滤保持一致，避免队友切专精时重置本地方案选中。
        if arg1 ~= "player" then
            return
        end
        selectedIndex = nil
        currentExportCache = nil
        if section and section:IsVisible() then
            RequestRebuild()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        UpdateButtons()
        return
    end

    if event == "TRAIT_CONFIG_UPDATED" or event == "TRAIT_NODE_CHANGED" then
        -- Trait-state changes refresh the loaded check marks with a short
        -- quiet-period debounce. Restarting the timer for every event keeps an
        -- import event burst to one export and one list rebuild.
        if section and section:IsVisible() then
            if exportRefreshTimer then
                exportRefreshTimer:Cancel()
            end
            exportRefreshTimer = C_Timer.NewTimer(0.35, function()
                exportRefreshTimer = nil
                if section and section:IsVisible() then
                    RefreshCurrentExport()
                    Rebuild()
                end
            end)
        end
    end
end)
