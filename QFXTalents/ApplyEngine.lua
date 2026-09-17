-- QFXTalents ApplyEngine: delegates complete loadout import/export to
-- Blizzard's talent UI. No direct node refund or purchase fallback is used.

local API = _G.QFXTalents

local pendingCombatRequest
local EMPTY_TRANSLATIONS = {}

local function T()
    return API.T or EMPTY_TRANSLATIONS
end

local Message = API.AddMessage

local function GetTalentFrame()
    return API.GetTalentFrame and API:GetTalentFrame() or nil
end

local function NormalizeLoadoutName(name)
    name = type(name) == "string" and name or ""
    name = name:gsub("[\r\n]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        name = "QFX Recommendation"
    end
    return name:sub(1, 45)
end

-- Auto-generated recommendation loadouts carry this prefix (see
-- GetRecommendedLoadoutName in Core.lua). They are the configs this addon
-- creates through Blizzard's import, and the ones this module prunes so the
-- loadout dropdown never accumulates more than one of them.
local AUTO_LOADOUT_PREFIX = "QFX_"

local function IsAutoLoadoutName(name)
    if type(name) ~= "string" then
        return false
    end
    -- 12.x secret values cannot be inspected; treat them as not ours.
    if issecretvalue and issecretvalue(name) then
        return false
    end
    return name:sub(1, #AUTO_LOADOUT_PREFIX) == AUTO_LOADOUT_PREFIX
end

-- Snapshot of the current specialization's config IDs, used to tell the
-- config the import just created apart from the pre-existing ones.
local function SnapshotConfigIDSet()
    local set = {}
    if not (C_ClassTalents and type(C_ClassTalents.GetConfigIDsBySpecID) == "function") then
        return set
    end
    local specID = API.GetCurrentSpecID and API:GetCurrentSpecID() or nil
    local ok, configIDs = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if ok and type(configIDs) == "table" then
        for _, configID in ipairs(configIDs) do
            set[configID] = true
        end
    end
    return set
end

-- Delete auto-generated (QFX_) configs. Called once before the import with no
-- snapshot (clears leftovers from earlier applies) and once after it with the
-- pre-import snapshot (clears the config that was active before, which the
-- import replaced). The active / last-selected config is never touched, and
-- the post-import pass bails out entirely until the import's own config shows
-- up in the list, so a slow or in-place import can never delete what was just
-- applied. Everything is pcall-guarded: a locked-down or differently shaped
-- client just skips pruning.
local function PruneAutoConfigs(previousIDs)
    if not (C_ClassTalents and C_Traits) then
        return 0
    end
    if type(C_ClassTalents.GetConfigIDsBySpecID) ~= "function"
        or type(C_ClassTalents.DeleteConfig) ~= "function"
        or type(C_Traits.GetConfigInfo) ~= "function" then
        return 0
    end

    local specID = API.GetCurrentSpecID and API:GetCurrentSpecID() or nil
    local okIDs, configIDs = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if not okIDs or type(configIDs) ~= "table" then
        return 0
    end

    local okActive, activeConfigID = pcall(C_ClassTalents.GetActiveConfigID)
    -- Without a known active config there is no way to tell which config the
    -- player is using right now; skip rather than risk deleting it.
    if not okActive or type(activeConfigID) ~= "number" then
        return 0
    end

    local lastSelectedConfigID
    if specID and type(C_ClassTalents.GetLastSelectedSavedConfigID) == "function" then
        local okLast, value = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
        if okLast then
            lastSelectedConfigID = value
        end
    end

    if previousIDs then
        local hasNewAuto = false
        for _, configID in ipairs(configIDs) do
            if not previousIDs[configID] then
                local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, configID)
                local name = okInfo and type(configInfo) == "table" and configInfo.name or nil
                if IsAutoLoadoutName(name) then
                    hasNewAuto = true
                    break
                end
            end
        end
        -- The import has not produced its config yet (or imports in place on
        -- this client); keep everything.
        if not hasNewAuto then
            return 0
        end
    end

    local deleted = 0
    for _, configID in ipairs(configIDs) do
        local isStale = previousIDs == nil or previousIDs[configID]
        if isStale and configID ~= activeConfigID and configID ~= lastSelectedConfigID then
            local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, configID)
            local name = okInfo and type(configInfo) == "table" and configInfo.name or nil
            if IsAutoLoadoutName(name) then
                local okDelete, success = pcall(C_ClassTalents.DeleteConfig, configID)
                if okDelete and success then
                    deleted = deleted + 1
                end
            end
        end
    end
    return deleted
end

-- The import creates its config asynchronously (TRAIT_CONFIG_CREATED), so the
-- follow-up prune runs after a short quiet period.
local function ScheduleAutoConfigCleanup(previousIDs)
    C_Timer.After(0.5, function()
        PruneAutoConfigs(previousIDs)
    end)
end

local function ImportOfficial(text, loadoutName)
    local talentFrame = GetTalentFrame()
    if not talentFrame or not talentFrame:GetConfigID() then
        API.lastLoadoutError = "TALENT_CONFIG_UNAVAILABLE"
        return false, "NO_CONFIG"
    end
    if type(talentFrame.ImportLoadout) ~= "function" then
        API.lastLoadoutError = "OFFICIAL_IMPORT_UNAVAILABLE"
        return false, "OFFICIAL_UNAVAILABLE"
    end

    local ok, success = pcall(
        talentFrame.ImportLoadout,
        talentFrame,
        text,
        NormalizeLoadoutName(loadoutName)
    )
    if not ok then
        API.lastLoadoutError = tostring(success)
        return false, "IMPORT_FAILED"
    end
    if not success then
        API.lastLoadoutError = "IMPORT_REJECTED"
        return false, "IMPORT_FAILED"
    end

    API.lastLoadoutError = nil
    return true, "IMPORTING"
end

local function ExportCurrentLoadout()
    local talentFrame = GetTalentFrame()
    if not talentFrame or not talentFrame:GetConfigID() then
        API.lastLoadoutError = "TALENT_CONFIG_UNAVAILABLE"
        return nil
    end
    if type(talentFrame.GetLoadoutExportString) ~= "function" then
        API.lastLoadoutError = "OFFICIAL_EXPORT_UNAVAILABLE"
        return nil
    end

    local ok, text = pcall(talentFrame.GetLoadoutExportString, talentFrame)
    if ok and type(text) == "string" and text ~= "" then
        API.lastLoadoutError = nil
        return text
    end

    API.lastLoadoutError = ok and "EMPTY_EXPORT_STRING" or tostring(text)
    return nil
end

local function ReportStatus(ok, status)
    local locale = T()
    if ok then
        Message(locale.applyImportStarted, 0.30, 0.90, 0.40)
    elseif status == "NO_CONFIG" then
        Message(locale.applyNoConfig, 1, 0.35, 0.25)
    elseif status == "INSPECTING" then
        Message(locale.applyInspecting, 1, 0.35, 0.25)
    else
        Message(locale.applyFailed, 1, 0.35, 0.25)
    end
end

local function ApplyNow(text, loadoutName)
    if PlayerSpellsFrame
        and PlayerSpellsFrame.IsInspecting
        and PlayerSpellsFrame:IsInspecting()
    then
        ReportStatus(false, "INSPECTING")
        return false, "INSPECTING"
    end

    local normalizedName = NormalizeLoadoutName(loadoutName)
    local pruneAutoConfigs = IsAutoLoadoutName(normalizedName)
    local previousIDs
    if pruneAutoConfigs then
        -- Clean leftovers first, then remember what survived so the post-import
        -- pass knows exactly which configs are the old ones.
        PruneAutoConfigs(nil)
        previousIDs = SnapshotConfigIDSet()
    end

    local ok, status = ImportOfficial(text, normalizedName)
    ReportStatus(ok, status)
    if ok and pruneAutoConfigs then
        ScheduleAutoConfigCleanup(previousIDs)
    end
    return ok, status
end

local function ApplyText(text, loadoutName)
    if type(text) ~= "string" or text == "" then
        return false, "EMPTY"
    end
    if InCombatLockdown() then
        pendingCombatRequest = {
            text = text,
            name = loadoutName,
        }
        Message(T().applyDeferred, 0.45, 0.75, 1)
        return true, "DEFERRED"
    end
    return ApplyNow(text, loadoutName)
end

local engineFrame = CreateFrame("Frame")
engineFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
engineFrame:SetScript("OnEvent", function()
    if not pendingCombatRequest then
        return
    end

    local pending = pendingCombatRequest
    pendingCombatRequest = nil
    C_Timer.After(0.10, function()
        ApplyNow(pending.text, pending.name)
    end)
end)

API.ApplyLoadoutText = ApplyText
API.ExportCurrentLoadout = ExportCurrentLoadout
