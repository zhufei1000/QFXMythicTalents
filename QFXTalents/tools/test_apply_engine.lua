local source = assert(arg[1], "ApplyEngine.lua path is required")

local imported = {}
local messages = {}
local inCombat = false
local eventHandler

_G.QFXTalents = {
    T = {
        applyImportStarted = "official import started",
        applyFailed = "failed",
        applyDeferred = "deferred",
        applyNoConfig = "no config",
        applyInspecting = "inspecting",
    },
    AddMessage = function(message)
        messages[#messages + 1] = message
    end,
    GetCurrentSpecID = function()
        return 71
    end,
}

local talentFrame = {
    GetConfigID = function()
        return 123
    end,
    GetTreeInfo = function()
        return { ID = 456 }
    end,
    ImportLoadout = function(_, text, name)
        imported[#imported + 1] = { text = text, name = name }
        return text ~= "REJECT"
    end,
    GetLoadoutExportString = function()
        return "EXPORTED"
    end,
}

function _G.QFXTalents:GetTalentFrame()
    return talentFrame
end

_G.PlayerSpellsFrame = nil
_G.InCombatLockdown = function()
    return inCombat
end
_G.C_Timer = {
    After = function(_, callback)
        callback()
    end,
}
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function(_, script, callback)
            if script == "OnEvent" then
                eventHandler = callback
            end
        end,
    }
end

assert(loadfile(source))("QFXTalents")

local ok, status = _G.QFXTalents.ApplyLoadoutText("LOADOUT", "QFX Test")
assert(ok and status == "IMPORTING")
assert(#imported == 1)
assert(imported[1].text == "LOADOUT" and imported[1].name == "QFX Test")
assert(messages[#messages] == "official import started")
assert(_G.QFXTalents.ExportCurrentLoadout() == "EXPORTED")

ok, status = _G.QFXTalents.ApplyLoadoutText("REJECT", "Rejected")
assert(not ok and status == "IMPORT_FAILED")
assert(#imported == 2, "a rejected official import must not fall back to node staging")

inCombat = true
ok, status = _G.QFXTalents.ApplyLoadoutText("DEFERRED", "Deferred Name")
assert(ok and status == "DEFERRED")
assert(#imported == 2)
inCombat = false
assert(eventHandler)
eventHandler(nil, "PLAYER_REGEN_ENABLED")
assert(#imported == 3)
assert(imported[3].text == "DEFERRED" and imported[3].name == "Deferred Name")

ok, status = _G.QFXTalents.ApplyLoadoutText("DEFAULT")
assert(ok and status == "IMPORTING")
assert(imported[4].name == "QFX Recommendation")

talentFrame.ImportLoadout = nil
ok, status = _G.QFXTalents.ApplyLoadoutText("NO FALLBACK", "Unavailable")
assert(not ok and status == "OFFICIAL_UNAVAILABLE")
assert(#imported == 4, "the removed node-staging fallback must not run")

-- === auto-generated config pruning ===
local configs = {
    [10] = { name = "QFX_Sporefall_Priest" },
    [20] = { name = "QFX_Nexus_King_Mythic_Priest" },
    [30] = { name = "My Own Build" },
}
local activeConfigID = 30
local nextConfigID = 40
local deletedConfigs = {}

local function SortedConfigIDs()
    local ids = {}
    for id in pairs(configs) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

local function AutoConfigCount()
    local count = 0
    for _, config in pairs(configs) do
        if type(config.name) == "string" and config.name:sub(1, 4) == "QFX_" then
            count = count + 1
        end
    end
    return count
end

_G.C_ClassTalents = {
    GetConfigIDsBySpecID = function()
        return SortedConfigIDs()
    end,
    GetActiveConfigID = function()
        return activeConfigID
    end,
    GetLastSelectedSavedConfigID = function()
        return activeConfigID
    end,
    DeleteConfig = function(configID)
        if not configs[configID] then
            return false
        end
        deletedConfigs[#deletedConfigs + 1] = configID
        configs[configID] = nil
        return true
    end,
}
_G.C_Traits = {
    GetConfigInfo = function(configID)
        return configs[configID]
    end,
}

-- Blizzard-style import: creates a NEW config under the requested name and
-- makes it the active one (TRAIT_CONFIG_CREATED flow).
talentFrame.ImportLoadout = function(_, text, name)
    local configID = nextConfigID
    nextConfigID = nextConfigID + 1
    configs[configID] = { name = name }
    activeConfigID = configID
    imported[#imported + 1] = { text = text, name = name }
    return true
end

-- First apply: the two leftover QFX configs (10, 20) are pruned before the
-- import; the import's own config (40) becomes active and must survive.
ok, status = _G.QFXTalents.ApplyLoadoutText("PRUNED", "QFX_Dungeon_Priest")
assert(ok and status == "IMPORTING")
assert(configs[10] == nil and configs[20] == nil, "leftover QFX configs must be deleted")
assert(configs[40] ~= nil and configs[40].name == "QFX_Dungeon_Priest", "the import's config must survive")
assert(configs[30] ~= nil, "non-QFX configs must never be touched")
assert(#deletedConfigs == 2, "expected the two leftovers to be deleted, got " .. #deletedConfigs)

-- Second apply with the same name: the previous QFX config (40) is stale and
-- replaced by 41. Exactly one auto-generated config must remain.
ok, status = _G.QFXTalents.ApplyLoadoutText("PRUNED AGAIN", "QFX_Dungeon_Priest")
assert(ok and status == "IMPORTING")
assert(configs[40] == nil, "the previous same-named QFX config must be replaced, not accumulated")
assert(configs[41] ~= nil and configs[41].name == "QFX_Dungeon_Priest")
assert(AutoConfigCount() == 1, "exactly one auto-generated config must remain, got " .. AutoConfigCount())

-- Applying a personal (non-QFX) loadout must not prune anything.
ok, status = _G.QFXTalents.ApplyLoadoutText("PERSONAL", "My Personal Build")
assert(ok and status == "IMPORTING")
assert(configs[41] ~= nil, "applying a personal loadout must keep the QFX config")
assert(configs[42] ~= nil and configs[42].name == "My Personal Build")

-- A client that imports in place (no new config appears) must not prune after
-- the import: the follow-up pass only runs once the import's own config shows
-- up in the list. The pre-import pass may still clean leftovers (config 41).
talentFrame.ImportLoadout = function(_, text, name)
    imported[#imported + 1] = { text = text, name = name }
    return true
end
local deletedBefore = #deletedConfigs
ok, status = _G.QFXTalents.ApplyLoadoutText("IN PLACE", "QFX_InPlace_Priest")
assert(ok and status == "IMPORTING")
assert(
    #deletedConfigs == deletedBefore + 1,
    "an in-place import must not trigger the post-import prune, got "
        .. (#deletedConfigs - deletedBefore)
        .. " deletes"
)
assert(configs[42] ~= nil, "the active config must survive an in-place import")

print("ApplyEngine official-only import/export tests passed")
print("ApplyEngine auto-config pruning tests passed")
