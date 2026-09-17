local ADDON, ns = ...

local API = _G.QFXMythicTalents or {}
_G.QFXMythicTalents = API

API.API_VERSION = 1
API.DATA_API_VERSION = 2
API.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    or "0.7.3"
API.providers = API.providers or {}
API.specProviders = API.specProviders or {}
API.manifest = API.manifest or nil
API.lastDataError = nil

local function ValidateAPIVersion(data)
    return type(data) == "table" and tonumber(data.apiVersion) == API.API_VERSION
end

-- Legacy registration remains available so older dungeon-only database packages
-- do not break immediately. New releases use the unified QFXTalentData backend.
function API:RegisterDataManifest(manifest)
    if not ValidateAPIVersion(manifest) then
        self.lastDataError = "API_VERSION_MISMATCH"
        return false, self.lastDataError
    end
    if type(manifest.dataVersion) ~= "string" or type(manifest.dungeons) ~= "table" then
        self.lastDataError = "INVALID_MANIFEST"
        return false, self.lastDataError
    end
    self.manifest = manifest
    self.lastDataError = nil
    return true
end

function API:RegisterDataProvider(provider)
    if not ValidateAPIVersion(provider) then
        self.lastDataError = "API_VERSION_MISMATCH"
        return false, self.lastDataError
    end
    if type(provider.classToken) ~= "string" or type(provider.specs) ~= "table" then
        self.lastDataError = "INVALID_PROVIDER"
        return false, self.lastDataError
    end
    if self.manifest and provider.dataVersion ~= self.manifest.dataVersion then
        self.lastDataError = "DATA_VERSION_MISMATCH"
        return false, self.lastDataError
    end

    self.providers[provider.classToken] = provider
    for specID in pairs(provider.specs) do
        self.specProviders[specID] = provider
    end
    self.lastDataError = nil
    return true
end

local function VersionAtLeast(currentVersion, minimumVersion)
    local currentMajor, currentMinor, currentPatch =
        tostring(currentVersion or ""):match("^(%d+)%.(%d+)%.(%d+)")
    local minimumMajor, minimumMinor, minimumPatch =
        tostring(minimumVersion or ""):match("^(%d+)%.(%d+)%.(%d+)")
    if not currentMajor or not minimumMajor then
        return false
    end

    local current = {
        tonumber(currentMajor),
        tonumber(currentMinor),
        tonumber(currentPatch),
    }
    local minimum = {
        tonumber(minimumMajor),
        tonumber(minimumMinor),
        tonumber(minimumPatch),
    }
    for index = 1, 3 do
        if current[index] ~= minimum[index] then
            return current[index] > minimum[index]
        end
    end
    return true
end

local unifiedBackend
local unifiedBackendValid = false

local function GetUnifiedDataAPI()
    -- 数据后端一旦加载完成，其 manifest/版本在本次会话内不变。缓存可避免
    -- 每次 API 调用重复做版本字符串解析与表查询（RebuildContentButtons 等
    -- 循环路径会高频调用）。数据插件加载事件会使缓存失效后重新校验。
    if unifiedBackendValid then
        return unifiedBackend
    end
    local backend = _G.QFXTalentData
    if type(backend) ~= "table" then
        return nil
    end
    if tonumber(backend.apiVersion) ~= API.DATA_API_VERSION then
        return nil, "DATA_API_VERSION_MISMATCH"
    end

    local manifest = type(backend.GetManifest) == "function"
        and backend:GetManifest()
        or backend.manifest
    local minimumVersion = manifest and manifest.minDisplayVersion
    if type(minimumVersion) ~= "string"
        or not VersionAtLeast(API.VERSION, minimumVersion)
    then
        return nil, "DISPLAY_VERSION_MISMATCH"
    end
    unifiedBackend = backend
    unifiedBackendValid = true
    return backend
end

local CompactDataProvider

function API:GetDataManifest()
    local backend = GetUnifiedDataAPI()
    if backend and type(backend.GetManifest) == "function" then
        return backend:GetManifest()
    end
    return self.manifest
end

function API:GetDataProvider(classToken)
    local backend = GetUnifiedDataAPI()
    if backend and type(backend.providers) == "table" then
        return classToken and backend.providers[classToken] or nil
    end
    return classToken and self.providers[classToken] or nil
end

function API:GetSpecData(specID)
    local backend = GetUnifiedDataAPI()
    if backend and type(backend.GetSpecData) == "function" then
        return backend:GetSpecData(specID)
    end
    local provider = self.specProviders[specID]
    return provider and provider.specs[specID] or nil
end

function API:GetDungeonData(specID, dungeonID)
    local backend = GetUnifiedDataAPI()
    if backend and type(backend.GetDungeonData) == "function" then
        return backend:GetDungeonData(dungeonID, specID)
    end
    local spec = self:GetSpecData(specID)
    return spec and spec.dungeons and spec.dungeons[dungeonID] or nil
end

function API:GetRaidData(specID, raidID, bossID, difficultyID)
    local backend = GetUnifiedDataAPI()
    if backend and type(backend.GetRaidData) == "function" then
        return backend:GetRaidData(raidID, bossID, difficultyID, specID)
    end

    local spec = self:GetSpecData(specID)
    local raid = spec and spec.raids and spec.raids[raidID]
    local boss = raid and raid.bosses and raid.bosses[bossID]
    if not boss then
        return nil
    end
    if type(boss.difficulties) == "table" then
        return boss.difficulties[difficultyID]
    end
    return boss
end

function API:GetRecommendedDungeonTalent(specID, dungeonID)
    local backend = GetUnifiedDataAPI()
    if backend and type(backend.GetRecommendedDungeonTalent) == "function" then
        return backend:GetRecommendedDungeonTalent(dungeonID, specID)
    end
    local recommendation = self:GetDungeonData(specID, dungeonID)
    return recommendation and recommendation.recommended or nil
end

function API:GetRecommendedRaidTalent(specID, raidID, bossID, difficultyID)
    local backend = GetUnifiedDataAPI()
    if backend and type(backend.GetRecommendedRaidTalent) == "function" then
        return backend:GetRecommendedRaidTalent(raidID, bossID, difficultyID, specID)
    end
    local recommendation = self:GetRaidData(specID, raidID, bossID, difficultyID)
    return recommendation and recommendation.recommended or nil
end

function API:GetDungeons()
    local manifest = self:GetDataManifest()
    return manifest and manifest.dungeons or nil
end

function API:GetRaids()
    local manifest = self:GetDataManifest()
    return manifest and manifest.raids or nil
end

function API:GetRaidDifficulties()
    local manifest = self:GetDataManifest()
    return manifest and manifest.raidDifficulties or nil
end

function API:GetDataVersion()
    local manifest = self:GetDataManifest()
    return manifest and manifest.dataVersion or nil
end

function API:IsDataReady(specID)
    if not specID then
        local index = GetSpecialization and GetSpecialization()
        specID = index and GetSpecializationInfo and GetSpecializationInfo(index)
    end
    return self:GetDataManifest() ~= nil and specID ~= nil and self:GetSpecData(specID) ~= nil
end

local function LoadDataAddOn(addonName)
    if not C_AddOns or not C_AddOns.LoadAddOn then
        return false, "LOAD_API_UNAVAILABLE"
    end
    if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addonName) then
        return true
    end

    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, addonName)
    if not ok then
        return false, tostring(loaded)
    end
    if loaded then
        return true
    end
    return false, reason or "LOAD_FAILED"
end

function API:EnsureDataLoaded(specID, classToken)
    classToken = classToken or select(2, UnitClass("player"))
    if not classToken then
        self.lastDataError = "CLASS_UNAVAILABLE"
        return false, self.lastDataError
    end

    local backend, compatibilityError = GetUnifiedDataAPI()
    if compatibilityError then
        self.lastDataError = compatibilityError
        return false, self.lastDataError
    end
    if not backend then
        -- QFX computes the displayed percentages from the raw loadout samples.
        -- Let the data addon release its much larger duplicate selection maps.
        _G.QFXTalentDataCompactMode = true
        local loaded, reason = LoadDataAddOn("QFXTalentData")
        if not loaded then
            -- Dungeon-only backward compatibility for users upgrading the core
            -- before replacing the old database package.
            loaded, reason = LoadDataAddOn("QFXMythicTalents_Data")
            if not loaded then
                self.lastDataError = "BASE_DATA_" .. tostring(reason)
                return false, self.lastDataError
            end
        end
        backend, compatibilityError = GetUnifiedDataAPI()
        if compatibilityError then
            self.lastDataError = compatibilityError
            return false, self.lastDataError
        end
    end

    if backend then
        local activated, activateReason = true, nil
        if type(backend.ActivateSpec) == "function" then
            activated, activateReason = backend:ActivateSpec(specID, classToken)
        elseif type(backend.ActivateClass) == "function" then
            activated, activateReason = backend:ActivateClass(classToken)
        elseif type(backend.ActivateCurrentClass) == "function" then
            activated, activateReason = backend:ActivateCurrentClass()
        end
        if not activated then
            self.lastDataError = "CLASS_DATA_" .. tostring(activateReason or "ACTIVATION_FAILED")
            return false, self.lastDataError
        end
        local provider = type(backend.providers) == "table" and backend.providers[classToken]
        if CompactDataProvider(provider) and collectgarbage then
            -- 全量 GC 推迟到数据激活完成之后执行，避免与面板创建叠加在同
            -- 一帧造成可见卡顿。一次性开销，之后由游戏的增量 GC 正常回收。
            C_Timer.After(1, function()
                collectgarbage("collect")
            end)
        end
    else
        local database = _G.QFXMythicTalentsData
        if database and type(database.ActivateClass) == "function" then
            local activated, activateReason = database:ActivateClass(classToken)
            if not activated then
                self.lastDataError = "CLASS_DATA_" .. tostring(activateReason or "ACTIVATION_FAILED")
                return false, self.lastDataError
            end
        end
    end

    if not self:IsDataReady(specID) then
        self.lastDataError = _G.QFXTalentDataLoadError
            or _G.QFXMythicTalentsDataLoadError
            or self.lastDataError
            or "PROVIDER_NOT_REGISTERED"
        return false, self.lastDataError
    end

    self.lastDataError = nil
    return true
end

local frameEvents = CreateFrame("Frame")
local talentFrame
local sidePanel
local selectedMode = "dungeon"
local selectedDungeonID
local selectedRaidID
local selectedBossID
local selectedRaidDifficultyID = 5
local currentSpecID
local currentStats
local currentStatsKey
local currentStates
local currentStatesDirty = true
local currentStatesContextKey
local treeContext
local statisticsBuildToken = 0
local pendingStatisticsKey
local statisticsDebounceTimer
local refreshQueued = false
local forceOverlayRefresh = false
local refreshTimer
local panelRecoveryToken = 0
local panelRecoveryTimer
local panelPositionTimer
local visibilitySyncTimer
local operationalEventsEnabled = false
local pluginSuspended = false
local blizzardHooksInstalled = false
local originalEnableCommitCastBar
local percentagesEnabled = true
local contentDataProvider
local hookedButtons = setmetatable({}, { __mode = "k" })
local SetButtonSelected
local ScheduleRefresh
local SuspendAddon

local operationalEvents = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "INSPECT_READY",
    "PLAYER_TALENT_UPDATE",
    "SELECTED_LOADOUT_CHANGED",
    "TRAIT_NODE_CHANGED",
    "TRAIT_NODE_CHANGED_PARTIAL",
    "TRAIT_NODE_ENTRY_UPDATED",
    "TRAIT_SUB_TREE_CHANGED",
    "TRAIT_CONFIG_CREATED",
    "TRAIT_CONFIG_UPDATED",
    "TRAIT_CONFIG_LIST_UPDATED",
    "CONFIG_COMMIT_FAILED",
    "ACTIVE_COMBAT_CONFIG_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "CHALLENGE_MODE_START",
    "ENCOUNTER_START",
}

local function SetOperationalEventsEnabled(enabled)
    enabled = not not enabled
    if operationalEventsEnabled == enabled then
        return
    end
    operationalEventsEnabled = enabled
    for _, event in ipairs(operationalEvents) do
        if enabled then
            frameEvents:RegisterEvent(event)
        else
            frameEvents:UnregisterEvent(event)
        end
    end
end

local function CancelStatisticsBuild()
    statisticsBuildToken = statisticsBuildToken + 1
    pendingStatisticsKey = nil
    if statisticsDebounceTimer then
        statisticsDebounceTimer:Cancel()
        statisticsDebounceTimer = nil
    end
end

CompactDataProvider = function(provider)
    if type(provider) ~= "table" or type(provider.specs) ~= "table" or provider.qfxmtCompacted then
        return false
    end

    local released = false
    local function CompactRecommendation(recommendation)
        if type(recommendation) == "table" and type(recommendation.selection) == "table" then
            recommendation.selection = nil
            released = true
        end
    end

    for _, specData in pairs(provider.specs) do
        for _, recommendation in pairs(specData.dungeons or {}) do
            CompactRecommendation(recommendation)
        end
        for _, raidData in pairs(specData.raids or {}) do
            for _, bossData in pairs(raidData.bosses or {}) do
                for _, recommendation in pairs(bossData.difficulties or {}) do
                    CompactRecommendation(recommendation)
                end
            end
        end
    end

    provider.qfxmtCompacted = true
    return released
end

local L = {
    zhCN = {
        title = "群飞轩天赋推荐",
        sample = "样本",
        noData = "当前专精暂无数据",
        parsing = "正在解析天赋数据…",
        combat = "战斗中无法导入天赋",
        selectedRate = "当前选择率",
        exactState = "当前状态",
        recommendation = "推荐状态",
        matches = "与推荐一致",
        differs = "与推荐不同",
        notSelected = "未选择",
        rank = "等级",
        auto = "已自动匹配当前内容",
        manual = "已手动选择推荐内容",
        command = "输入 /qmt 打开暴雪天赋界面",
        dataMissing = "未安装或未启用天赋数据库",
        dataMismatch = "数据库版本与核心插件不兼容",
        heroic = "英雄",
        mythic = "史诗",
        raidDifficulty = "团本难度",
        apply = "应用推荐",
        applyImportStarted = "已交给暴雪导入完整天赋方案",
        applyFailed = "天赋应用失败",
        applyDeferred = "战斗结束后自动应用天赋",
        applyNoConfig = "当前无法应用天赋",
        applyInspecting = "观察其他玩家时无法应用",
        myLoadouts = "我的方案",
        save = "保存",
        load = "载入",
        edit = "重命名",
        delete = "删除",
        moveUp = "上移",
        moveDown = "下移",
        rowHint = "双击应用该方案",
        loadedTooltip = "当前已加载",
        saveTitle = "保存当前天赋为方案",
        renameTitle = "重命名方案",
        deleteConfirm = "删除方案“%s”？",
        newLoadoutName = "新方案",
        emptyLoadouts = "暂无方案",
        emptyHint = "点击“保存”保存当前天赋",
        combatButtons = "战斗中无法操作方案",
        saveFailed = "无法导出当前天赋",
        tleDetected = "检测到 TalentLoadoutsEx，已隐藏本地方案列表",
    },
    zhTW = {
        title = "群飛軒天賦推薦",
        sample = "樣本",
        noData = "目前專精暫無資料",
        parsing = "正在解析天賦資料…",
        combat = "戰鬥中無法匯入天賦",
        selectedRate = "目前選擇率",
        exactState = "目前狀態",
        recommendation = "推薦狀態",
        matches = "與推薦一致",
        differs = "與推薦不同",
        notSelected = "未選擇",
        rank = "等級",
        auto = "已自動配對目前內容",
        manual = "已手動選擇推薦內容",
        command = "輸入 /qmt 開啟暴雪天賦介面",
        dataMissing = "未安裝或未啟用天賦資料庫",
        dataMismatch = "資料庫版本與核心插件不相容",
        heroic = "英雄",
        mythic = "傳奇",
        raidDifficulty = "團本難度",
        apply = "套用推薦",
        applyImportStarted = "已交給暴雪匯入完整天賦方案",
        applyFailed = "天賦套用失敗",
        applyDeferred = "戰鬥結束後自動套用天賦",
        applyNoConfig = "目前無法套用天賦",
        applyInspecting = "觀察其他玩家時無法套用",
        myLoadouts = "我的方案",
        save = "儲存",
        load = "載入",
        edit = "重新命名",
        delete = "刪除",
        moveUp = "上移",
        moveDown = "下移",
        rowHint = "雙擊套用該方案",
        loadedTooltip = "目前已載入",
        saveTitle = "儲存目前天賦為方案",
        renameTitle = "重新命名方案",
        deleteConfirm = "刪除方案「%s」？",
        newLoadoutName = "新方案",
        emptyLoadouts = "暫無方案",
        emptyHint = "點擊「儲存」儲存目前天賦",
        combatButtons = "戰鬥中無法操作方案",
        saveFailed = "無法匯出目前天賦",
        tleDetected = "偵測到 TalentLoadoutsEx，已隱藏本地方案列表",
    },
    enUS = {
        title = "QFX Talent Recommendations",
        sample = "Samples",
        noData = "No data for the current specialization",
        parsing = "Parsing talent data…",
        combat = "Talents cannot be imported in combat",
        selectedRate = "Current choice rate",
        exactState = "Current state",
        recommendation = "Recommended state",
        matches = "Matches recommendation",
        differs = "Differs from recommendation",
        notSelected = "Not selected",
        rank = "Rank",
        auto = "Current content selected automatically",
        manual = "Recommendation selected manually",
        command = "Type /qmt to open the Blizzard talent frame",
        dataMissing = "Talent database is not installed or enabled",
        dataMismatch = "Database version is incompatible with the core addon",
        heroic = "Heroic",
        mythic = "Mythic",
        raidDifficulty = "Raid difficulty",
        apply = "Apply Recommendation",
        applyImportStarted = "The complete loadout was passed to Blizzard's importer",
        applyFailed = "Failed to apply talents",
        applyDeferred = "Talents will be applied after combat",
        applyNoConfig = "Talents cannot be applied right now",
        applyInspecting = "Cannot apply while inspecting another player",
        myLoadouts = "My Loadouts",
        save = "Save",
        load = "Load",
        edit = "Rename",
        delete = "Delete",
        moveUp = "Up",
        moveDown = "Down",
        rowHint = "Double-click to apply this loadout",
        loadedTooltip = "Currently loaded",
        saveTitle = "Save current talents as a loadout",
        renameTitle = "Rename loadout",
        deleteConfirm = 'Delete loadout "%s"?',
        newLoadoutName = "New Loadout",
        emptyLoadouts = "No loadouts yet",
        emptyHint = "Click Save to store your current talents",
        combatButtons = "Loadouts are locked in combat",
        saveFailed = "Could not export current talents",
        tleDetected = "TalentLoadoutsEx detected; local loadout list hidden",
    },
}

local locale = GetLocale()
local T = L[locale] or L.enUS

-- Shared with the ApplyEngine and Loadouts modules.
API.T = T
API.locale = locale

-- Shared error-frame message helper used by ApplyEngine and Loadouts.
API.AddMessage = function(text, r, g, b)
    if text and text ~= "" and UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, r or 1, g or 0.82, b or 0.10)
    end
end

local function EnsureDataLoaded(specID, classToken)
    return API:EnsureDataLoaded(specID, classToken)
end

local function GetDungeons()
    return API:GetDungeons() or {}
end

local function GetRaids()
    return API:GetRaids() or {}
end

local function GetSpecData(specID)
    return API:GetSpecData(specID)
end

local function DataStatusText()
    local displayVersion = "v" .. tostring(API.VERSION or "0.6.6")
    if API:IsDataReady(currentSpecID) then
        local version = API:GetDataVersion()
        local date = version and version:match("^(%d+%.%d+%.%d+)")
        local databaseVersion = date and ("DB " .. date)
            or version and ("DB " .. version)
            or "DB"
        return displayVersion .. " · " .. databaseVersion
    end
    if API.lastDataError == "API_VERSION_MISMATCH"
        or API.lastDataError == "DATA_VERSION_MISMATCH"
        or API.lastDataError == "DATA_API_VERSION_MISMATCH"
        or API.lastDataError == "DISPLAY_VERSION_MISMATCH"
    then
        return displayVersion .. " · " .. T.dataMismatch
    end
    return displayVersion .. " · " .. T.dataMissing
end

local function CurrentSpecID()
    if PlayerSpellsFrame and PlayerSpellsFrame.IsInspecting
        and PlayerSpellsFrame:IsInspecting()
    then
        local specID = PlayerSpellsFrame.GetSpecID and PlayerSpellsFrame:GetSpecID()
        return type(specID) == "number" and specID > 0 and specID or nil
    end

    local index = GetSpecialization()
    return index and GetSpecializationInfo(index) or nil
end

local function CurrentClassToken()
    if PlayerSpellsFrame and PlayerSpellsFrame.IsInspecting
        and PlayerSpellsFrame:IsInspecting()
    then
        local inspectUnit = PlayerSpellsFrame.GetInspectUnit
            and PlayerSpellsFrame:GetInspectUnit()
        if inspectUnit then
            return select(2, UnitClass(inspectUnit))
        end

        local classID = PlayerSpellsFrame.GetClassID and PlayerSpellsFrame:GetClassID()
        local classInfo = classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo
            and C_CreatureInfo.GetClassInfo(classID)
        return classInfo and classInfo.classFile or nil
    end

    return select(2, UnitClass("player"))
end

local RAID_DIFFICULTY_HEROIC = 4
local RAID_DIFFICULTY_MYTHIC = 5

local function RaidDifficultyName(difficultyID)
    local configured = API:GetRaidDifficulties()
    if configured and configured[difficultyID] then
        local sourceName = configured[difficultyID]
        if difficultyID == RAID_DIFFICULTY_HEROIC then
            return T.heroic
        elseif difficultyID == RAID_DIFFICULTY_MYTHIC then
            return T.mythic
        end
        return sourceName
    end
    return difficultyID == RAID_DIFFICULTY_HEROIC and T.heroic
        or difficultyID == RAID_DIFFICULTY_MYTHIC and T.mythic
        or tostring(difficultyID or "")
end

local function DetectRaidDifficulty()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "raid" then
        return nil
    end
    if difficultyID == 15 then
        return RAID_DIFFICULTY_HEROIC
    elseif difficultyID == 16 then
        return RAID_DIFFICULTY_MYTHIC
    end
end

local function Normalize(text)
    return tostring(text or ""):lower():gsub("[%s%p%c]", "")
end

local function LocalizedRecordName(record, fallback)
    if type(record) ~= "table" then
        return fallback
    end
    local names = record.names
    if type(names) == "table" then
        local localized = names[locale]
        if type(localized) == "string" and localized ~= "" then
            return localized
        end
        local english = names.enUS
        if type(english) == "string" and english ~= "" then
            fallback = english
        end
    end
    return fallback
end

local function DungeonName(dungeon)
    -- Prefer the client's own Challenge Mode name when possible.  This keeps
    -- dungeon labels localized even if a freshly generated database briefly
    -- contains only enUS metadata during a season hand-off.
    if dungeon and dungeon.challengeModeID
        and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo
    then
        local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, dungeon.challengeModeID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return LocalizedRecordName(dungeon, dungeon and dungeon.slug or nil)
end

local function FindDungeon(dungeonID)
    for _, dungeon in ipairs(GetDungeons()) do
        if dungeon.id == dungeonID then
            return dungeon
        end
    end
end

local function FindDungeonByChallengeModeID(challengeModeID)
    if not challengeModeID then
        return nil
    end
    for _, dungeon in ipairs(GetDungeons()) do
        if dungeon.challengeModeID == challengeModeID then
            return dungeon
        end
    end
end

local function RaidName(raid)
    return LocalizedRecordName(raid, raid and raid.slug or nil)
end

local function BossName(boss)
    return LocalizedRecordName(boss, boss and (boss.name or boss.slug) or nil)
end

local function FindRaid(raidID)
    for _, raid in ipairs(GetRaids()) do
        if raid.id == raidID then
            return raid
        end
    end
end

local function FindBoss(raidID, bossID)
    local raid = FindRaid(raidID)
    for _, boss in ipairs(raid and raid.bosses or {}) do
        if boss.id == bossID then
            return boss
        end
    end
end

local function FindRaidByBoss(bossID)
    if not bossID then
        return nil
    end
    for _, raid in ipairs(GetRaids()) do
        for _, boss in ipairs(raid.bosses or {}) do
            if boss.id == bossID then
                return raid
            end
        end
    end
end

local function MatchDungeonName(name)
    local normalized = Normalize(name)
    if normalized == "" then
        return nil
    end

    for _, dungeon in ipairs(GetDungeons()) do
        for _, alias in ipairs(dungeon.aliases or {}) do
            local candidate = Normalize(alias)
            if candidate ~= "" and (normalized == candidate or normalized:find(candidate, 1, true) or candidate:find(normalized, 1, true)) then
                return dungeon.id
            end
        end
    end
end

local function DetectDungeon()
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local challengeMapID = C_ChallengeMode.GetActiveChallengeMapID()
        local dungeon = challengeMapID and FindDungeonByChallengeModeID(challengeMapID)
        if dungeon then
            return dungeon.id
        end
        if challengeMapID and challengeMapID > 0 and C_ChallengeMode.GetMapUIInfo then
            local name = C_ChallengeMode.GetMapUIInfo(challengeMapID)
            local dungeonID = MatchDungeonName(name)
            if dungeonID then
                return dungeonID
            end
        end
    end

    local instanceName = GetInstanceInfo()
    local dungeonID = MatchDungeonName(instanceName)
    if dungeonID then
        return dungeonID
    end

    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        local mapInfo = mapID and C_Map.GetMapInfo(mapID)
        dungeonID = MatchDungeonName(mapInfo and mapInfo.name)
        if dungeonID then
            return dungeonID
        end
    end
end

local function MatchRaidName(name)
    local normalized = Normalize(name)
    if normalized == "" then
        return nil
    end
    for _, raid in ipairs(GetRaids()) do
        local candidates = raid.aliases or {}
        for _, alias in ipairs(candidates) do
            local candidate = Normalize(alias)
            if candidate ~= "" and (normalized == candidate or normalized:find(candidate, 1, true) or candidate:find(normalized, 1, true)) then
                return raid.id
            end
        end
    end
end

local function DetectRaid()
    local instanceName, instanceType = GetInstanceInfo()
    if instanceType == "raid" then
        return MatchRaidName(instanceName)
    end
end

local function GetRecommendation(specID, dungeonID)
    return API:GetDungeonData(specID, dungeonID)
end

local function GetCurrentRecommendation(specID)
    if selectedMode == "raid" then
        return selectedRaidID and selectedBossID and selectedRaidDifficultyID
            and API:GetRaidData(specID, selectedRaidID, selectedBossID, selectedRaidDifficultyID)
            or nil
    end
    return selectedDungeonID and API:GetDungeonData(specID, selectedDungeonID) or nil
end

local function CurrentSelectionKey()
    if selectedMode == "raid" then
        return table.concat({
            "raid",
            selectedRaidID or 0,
            selectedBossID or 0,
            selectedRaidDifficultyID or 0,
        }, ":")
    end
    return "dungeon:" .. tostring(selectedDungeonID or 0)
end

local function StateKey(entryID, rank)
    return tostring(entryID or 0) .. ":" .. tostring(rank or 0)
end

local PACKED_BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PACKED_BASE64_VALUES = {}
for index = 1, #PACKED_BASE64 do
    PACKED_BASE64_VALUES[string.byte(PACKED_BASE64, index)] = index - 1
end

local function DecodePackedBytes(encoded)
    if type(encoded) ~= "string" or encoded == "" then
        return nil
    end

    local bytes = {}
    local buffer, bitCount = 0, 0
    for index = 1, #encoded do
        local value = PACKED_BASE64_VALUES[string.byte(encoded, index)]
        if value == nil then
            return nil
        end
        buffer = buffer * 64 + value
        bitCount = bitCount + 6
        while bitCount >= 8 do
            bitCount = bitCount - 8
            local divisor = 2 ^ bitCount
            bytes[#bytes + 1] = math.floor(buffer / divisor) % 256
            buffer = buffer % divisor
        end
    end
    return bytes
end

local function CreateVarintReader(bytes)
    local byteIndex = 1
    local function ReadVarint()
        local value, multiplier = 0, 1
        for _ = 1, 10 do
            local byte = bytes[byteIndex]
            if byte == nil then
                return nil
            end
            byteIndex = byteIndex + 1
            value = value + (byte % 128) * multiplier
            if byte < 128 then
                return value
            end
            multiplier = multiplier * 128
        end
        return nil
    end
    local function IsFinished()
        return byteIndex > #bytes
    end
    return ReadVarint, IsFinished
end

local function DecodePackedStatistics(encoded)
    local bytes = DecodePackedBytes(encoded)
    if not bytes then
        return nil
    end
    local ReadVarint, IsFinished = CreateVarintReader(bytes)
    local version = ReadVarint()
    local validSamples = ReadVarint()
    local nodeCount = ReadVarint()
    if version ~= 1 or not validSamples or validSamples <= 0 or validSamples > 255
        or not nodeCount or nodeCount < 0
    then
        return nil
    end

    local counts, entryUsage = {}, {}
    local nodeID = 0
    for _ = 1, nodeCount do
        local nodeDelta = ReadVarint()
        local stateCount = ReadVarint()
        if not nodeDelta or nodeDelta <= 0 or not stateCount or stateCount <= 0 then
            return nil
        end
        nodeID = nodeID + nodeDelta
        local nodeCounts, nodeUsage = {}, {}
        counts[nodeID] = nodeCounts
        entryUsage[nodeID] = nodeUsage
        for _ = 1, stateCount do
            local entryID = ReadVarint()
            local rank = ReadVarint()
            local count = ReadVarint()
            if not entryID or entryID <= 0 or not rank or rank <= 0
                or not count or count <= 0 or count > validSamples
            then
                return nil
            end
            nodeCounts[StateKey(entryID, rank)] = count
            nodeUsage[entryID] = (nodeUsage[entryID] or 0) + count
        end
    end
    if not IsFinished() then
        return nil
    end
    return validSamples, counts, entryUsage
end

local packedSchemaCache = {}

local function DecodePackedSchema(encoded)
    if packedSchemaCache[encoded] then
        return packedSchemaCache[encoded]
    end
    local bytes = DecodePackedBytes(encoded)
    if not bytes then
        return nil
    end
    local ReadVarint, IsFinished = CreateVarintReader(bytes)
    local version = ReadVarint()
    local nodeCount = ReadVarint()
    if version ~= 1 or not nodeCount or nodeCount <= 0 then
        return nil
    end

    local schema = { nodes = {}, entries = {} }
    local nodeID = 0
    for nodeIndex = 1, nodeCount do
        local nodeDelta = ReadVarint()
        local entryCount = ReadVarint()
        if not nodeDelta or nodeDelta <= 0 or not entryCount or entryCount <= 0 then
            return nil
        end
        nodeID = nodeID + nodeDelta
        schema.nodes[nodeIndex] = nodeID
        local entries = {}
        schema.entries[nodeID] = entries
        local entryID = 0
        for entryIndex = 1, entryCount do
            local entryDelta = ReadVarint()
            if not entryDelta or entryDelta <= 0 then
                return nil
            end
            entryID = entryID + entryDelta
            entries[entryIndex] = entryID
        end
    end
    if not IsFinished() then
        return nil
    end
    packedSchemaCache[encoded] = schema
    return schema
end

local function DecodePackedStatisticsV2(encoded, encodedSchema)
    local schema = DecodePackedSchema(encodedSchema)
    local bytes = DecodePackedBytes(encoded)
    if not schema or not bytes then
        return nil
    end
    local ReadVarint, IsFinished = CreateVarintReader(bytes)
    local version = ReadVarint()
    local validSamples = ReadVarint()
    local nodeCount = ReadVarint()
    if version ~= 2 or not validSamples or validSamples <= 0 or validSamples > 255
        or not nodeCount or nodeCount < 0
    then
        return nil
    end

    local counts, entryUsage, recommended = {}, {}, {}
    local nodeIndex = 0
    for _ = 1, nodeCount do
        local nodeDelta = ReadVarint()
        if not nodeDelta or nodeDelta <= 0 then
            return nil
        end
        nodeIndex = nodeIndex + nodeDelta
        local nodeID = schema.nodes[nodeIndex]
        local entries = nodeID and schema.entries[nodeID]
        if not entries then
            return nil
        end

        local baselineEntryIndex = ReadVarint()
        local baselineRank = ReadVarint()
        local stateCount = ReadVarint()
        if baselineEntryIndex == nil or baselineRank == nil
            or stateCount == nil or stateCount < 0
        then
            return nil
        end

        local baseline
        if baselineEntryIndex > 0 then
            local entryID = entries[baselineEntryIndex]
            if not entryID or baselineRank <= 0 then
                return nil
            end
            baseline = { entryID = entryID, rank = baselineRank }
            recommended[nodeID] = baseline
        elseif baselineRank ~= 0 then
            return nil
        end

        local nodeCounts, nodeUsage = {}, {}
        for _ = 1, stateCount do
            local entryIndex = ReadVarint()
            local rank = ReadVarint()
            local count = ReadVarint()
            local entryID = entryIndex and entries[entryIndex]
            if not entryID or not rank or rank <= 0
                or not count or count <= 0 or count > validSamples
            then
                return nil
            end
            nodeCounts[StateKey(entryID, rank)] = count
            nodeUsage[entryID] = (nodeUsage[entryID] or 0) + count
        end
        if stateCount == 0 and baseline then
            nodeCounts[StateKey(baseline.entryID, baseline.rank)] = validSamples
            nodeUsage[baseline.entryID] = validSamples
        end
        if next(nodeCounts) then
            counts[nodeID] = nodeCounts
            entryUsage[nodeID] = nodeUsage
        end
    end
    if not IsFinished() then
        return nil
    end
    return validSamples, counts, entryUsage, recommended
end

local function GetEntryName(configID, entryID)
    local entryInfo = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local definitionInfo = entryInfo and entryInfo.definitionID and C_Traits.GetDefinitionInfo(entryInfo.definitionID)
    local spellID = definitionInfo and definitionInfo.spellID
    if spellID then
        if C_Spell and C_Spell.GetSpellName then
            return C_Spell.GetSpellName(spellID)
        end
        return GetSpellInfo(spellID)
    end
    return entryID and ("Entry " .. entryID) or T.notSelected
end

local function IsCapstoneEntry(configID, entryID)
    if not configID or not entryID then
        return false
    end
    local entryInfo = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local entryType = entryInfo and entryInfo.type
    local types = Enum and Enum.TraitNodeEntryType
    return types and (
        entryType == types.SpendCapstoneCircle
        or entryType == types.SpendCapstoneSquare
    ) or false
end

local function IsCapstoneNodeInfo(configID, nodeInfo)
    for _, entryID in ipairs(nodeInfo and nodeInfo.entryIDs or {}) do
        if IsCapstoneEntry(configID, entryID) then
            return true
        end
    end
    return false
end

local function EntriesAreEquivalent(configID, firstEntryID, secondEntryID)
    firstEntryID = tonumber(firstEntryID)
    secondEntryID = tonumber(secondEntryID)
    if not firstEntryID or not secondEntryID then
        return false
    end
    if firstEntryID == secondEntryID then
        return true
    end

    local firstInfo = C_Traits.GetEntryInfo(configID, firstEntryID)
    local secondInfo = C_Traits.GetEntryInfo(configID, secondEntryID)
    if firstInfo and secondInfo
        and firstInfo.definitionID
        and firstInfo.definitionID == secondInfo.definitionID
    then
        return true
    end

    local firstName = GetEntryName(configID, firstEntryID)
    local secondName = GetEntryName(configID, secondEntryID)
    return firstName and secondName
        and firstName == secondName
        and not firstName:match("^Entry %d+$")
end

local function ResolveCurrentEntryID(nodeID, nodeInfo, rank)
    if not nodeInfo or not rank or rank <= 0 then
        return nil
    end

    local candidates = {}
    local seen = {}
    local function AddCandidate(entryID)
        entryID = tonumber(entryID)
        if entryID and entryID > 0 and not seen[entryID] then
            seen[entryID] = true
            candidates[#candidates + 1] = entryID
        end
    end

    local activeEntry = nodeInfo.activeEntry
    AddCandidate(type(activeEntry) == "table" and activeEntry.entryID or nil)
    AddCandidate(nodeInfo.activeEntryID)
    for _, entryID in pairs(nodeInfo.entryIDsWithCommittedRanks or {}) do
        AddCandidate(entryID)
    end

    -- Capstone nodes can expose a runtime active entry that differs from the
    -- selection entry serialized in a loadout. Prefer an actually observed
    -- database state before falling back to Blizzard's active-entry ordering.
    local nodeCounts = currentStats and currentStats.counts[nodeID]
    if nodeCounts then
        for _, entryID in ipairs(candidates) do
            if nodeCounts[StateKey(entryID, rank)] ~= nil then
                return entryID
            end
        end
    end

    local recommended = currentStats and currentStats.recommended[nodeID]
    if recommended
        and tonumber(recommended.rank) == rank
        and IsCapstoneNodeInfo(currentStats.configID, nodeInfo)
    then
        for _, entryID in ipairs(candidates) do
            if EntriesAreEquivalent(currentStats.configID, entryID, recommended.entryID) then
                return tonumber(recommended.entryID)
            end
        end
    end

    return candidates[1]
end

local function DecodeLoadout(text, specID, treeID, configID, entryToNode)
    if not talentFrame or not text or text == "" then
        return nil
    end

    local stream = ExportUtil.MakeImportDataStream(text)
    local headerValid, serializationVersion, loadoutSpecID = talentFrame:ReadLoadoutHeader(stream)
    if not headerValid or serializationVersion ~= C_Traits.GetLoadoutSerializationVersion() or loadoutSpecID ~= specID then
        return nil
    end

    local content = talentFrame:ReadLoadoutContent(stream, treeID)
    if not content then
        return nil
    end

    local loadoutInfos = talentFrame:ConvertToImportLoadoutEntryInfo(configID, treeID, content)
    if not loadoutInfos then
        return nil
    end

    local states = {}
    for _, loadoutInfo in ipairs(loadoutInfos) do
        local entryID = loadoutInfo.selectionEntryID
        local nodeID = entryID and entryToNode[entryID]
        local rank = (loadoutInfo.ranksPurchased or 0) + (loadoutInfo.ranksGranted or 0)
        if nodeID and rank > 0 then
            states[nodeID] = { entryID = entryID, rank = rank }
        end
    end
    return states
end

local function CreateStatisticsBuilder(specID, recommendation)
    if not recommendation or not talentFrame then
        return nil
    end

    local configID = talentFrame:GetConfigID()
    local treeID = talentFrame:GetTalentTreeID()
    if not configID or not treeID then
        return nil
    end

    local isPackedV2 = tonumber(recommendation.formatVersion) == 2
        and type(recommendation.schema) == "string"
        and type(recommendation.selection) == "string"
    local entryToNode = {}
    if not isPackedV2 then
        local contextKey = table.concat({ specID, treeID, configID }, ":")
        if treeContext and treeContext.key == contextKey then
            entryToNode = treeContext.entryToNode
        else
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                for _, entryID in ipairs(nodeInfo and nodeInfo.entryIDs or {}) do
                    entryToNode[entryID] = nodeID
                end
            end
            treeContext = {
                key = contextKey,
                entryToNode = entryToNode,
            }
        end
    end

    local builder = {
        recommendation = recommendation,
        specID = specID,
        configID = configID,
        treeID = treeID,
        entryToNode = entryToNode,
        samples = recommendation.samples or {},
        nextSample = 1,
        validSamples = 0,
        counts = {},
        entryUsage = {},
    }
    if isPackedV2 then
        local validSamples, counts, entryUsage, recommended =
            DecodePackedStatisticsV2(recommendation.selection, recommendation.schema)
        if validSamples then
            builder.samples = {}
            builder.validSamples = validSamples
            builder.counts = counts
            builder.entryUsage = entryUsage
            builder.recommended = recommended
            builder.packedV2 = true
        else
            return nil
        end
    elseif type(recommendation.selection) == "string" then
        local validSamples, counts, entryUsage = DecodePackedStatistics(recommendation.selection)
        if validSamples then
            builder.samples = {}
            builder.validSamples = validSamples
            builder.counts = counts
            builder.entryUsage = entryUsage
            builder.packed = true
        end
    end
    return builder
end

local function ProcessStatisticsSample(builder)
    local sampleText = builder.samples[builder.nextSample]
    builder.nextSample = builder.nextSample + 1
    if not sampleText then
        return false
    end

    local states = DecodeLoadout(
        sampleText,
        builder.specID,
        builder.treeID,
        builder.configID,
        builder.entryToNode
    )
    if states then
        builder.validSamples = builder.validSamples + 1
        for nodeID, state in pairs(states) do
            local nodeCounts = builder.counts[nodeID]
            if not nodeCounts then
                nodeCounts = {}
                builder.counts[nodeID] = nodeCounts
            end
            local key = StateKey(state.entryID, state.rank)
            nodeCounts[key] = (nodeCounts[key] or 0) + 1

            local nodeUsage = builder.entryUsage[nodeID]
            if not nodeUsage then
                nodeUsage = {}
                builder.entryUsage[nodeID] = nodeUsage
            end
            nodeUsage[state.entryID] = (nodeUsage[state.entryID] or 0) + 1
        end
    end
    return builder.nextSample <= #builder.samples
end

local function FinishStatistics(builder)
    local recommended = builder.recommended
    if not recommended then
        recommended = DecodeLoadout(
            builder.recommendation.recommended,
            builder.specID,
            builder.treeID,
            builder.configID,
            builder.entryToNode
        ) or {}
    end
    if builder.packed and not builder.packedV2 then
        for nodeID, state in pairs(recommended) do
            if not builder.counts[nodeID] then
                builder.counts[nodeID] = {
                    [StateKey(state.entryID, state.rank)] = builder.validSamples,
                }
                builder.entryUsage[nodeID] = {
                    [state.entryID] = builder.validSamples,
                }
            end
        end
    end
    return {
        configID = builder.configID,
        treeID = builder.treeID,
        validSamples = builder.validSamples,
        counts = builder.counts,
        entryUsage = builder.entryUsage,
        recommended = recommended,
    }
end

-- 每帧用于统计样本解码的时间预算（秒）。越大解析越快、单帧开销越高；
-- 打包数据不经过逐样本解码，不受此值影响。
local STATISTICS_FRAME_BUDGET = 0.004

local function QueueStatisticsBuild(specID, recommendation, key)
    if pendingStatisticsKey == key then
        return
    end

    statisticsBuildToken = statisticsBuildToken + 1
    local token = statisticsBuildToken
    pendingStatisticsKey = key
    if statisticsDebounceTimer then
        statisticsDebounceTimer:Cancel()
    end

    -- A short debounce means rapidly browsing several dungeons or bosses only
    -- parses the final selection. Packed databases decode node counts directly;
    -- older databases keep the one-sample-per-frame compatibility path.
    statisticsDebounceTimer = C_Timer.NewTimer(0.18, function()
        statisticsDebounceTimer = nil
        if token ~= statisticsBuildToken or pendingStatisticsKey ~= key then
            return
        end
        if not talentFrame or not talentFrame:IsVisible()
            or not sidePanel or not sidePanel:IsShown()
        then
            return
        end

        local builder = CreateStatisticsBuilder(specID, recommendation)
        if not builder then
            pendingStatisticsKey = nil
            return
        end

        local function ProcessNext()
            if token ~= statisticsBuildToken or pendingStatisticsKey ~= key then
                return
            end
            if not talentFrame or not talentFrame:IsVisible()
                or not sidePanel or not sidePanel:IsShown()
            then
                return
            end

            -- 非打包数据源逐样本解码是解析期的主要开销：每帧 1 个会让数百
            -- 样本耗时十几秒。改为按每帧时间预算批量解码（默认 4ms），既避免
            -- 单帧长任务，又把总解析时长缩短数倍。打包数据第一轮即完成，
            -- 行为不变。
            local budget = GetTime() + STATISTICS_FRAME_BUDGET
            local hasMore
            repeat
                hasMore = ProcessStatisticsSample(builder)
            until not hasMore or GetTime() >= budget
            if collectgarbage then
                collectgarbage("step", 8)
            end
            if hasMore then
                C_Timer.After(0, ProcessNext)
                return
            end

            local statistics = FinishStatistics(builder)
            if token ~= statisticsBuildToken or pendingStatisticsKey ~= key then
                return
            end
            currentStats = statistics
            currentStatsKey = key
            pendingStatisticsKey = nil
            ScheduleRefresh(0, true)
        end

        ProcessNext()
    end)
end

local function BuildCurrentStates()
    if not talentFrame or not currentStats or not currentSpecID then
        return nil
    end

    local contextKey = table.concat({
        currentSpecID,
        currentStats.treeID,
        currentStats.configID,
    }, ":")
    if currentStates and not currentStatesDirty
        and currentStatesContextKey == contextKey
    then
        return currentStates, false
    end

    local states = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(currentStats.treeID) or {}) do
        local nodeInfo = C_Traits.GetNodeInfo(currentStats.configID, nodeID)
        if nodeInfo then
            local activeEntry = nodeInfo.activeEntry
            local rank = math.max(
                tonumber(nodeInfo.activeRank) or 0,
                tonumber(nodeInfo.currentRank) or 0,
                (tonumber(nodeInfo.ranksPurchased) or 0)
                    + (tonumber(nodeInfo.ranksGranted) or 0)
            )
            if type(activeEntry) == "table" then
                rank = math.max(
                    rank,
                    tonumber(activeEntry.rank) or 0,
                    (tonumber(activeEntry.ranksPurchased) or 0)
                        + (tonumber(activeEntry.ranksGranted) or 0)
                )
            end
            local entryID = ResolveCurrentEntryID(nodeID, nodeInfo, rank)
            if entryID and rank > 0 then
                states[nodeID] = { entryID = entryID, rank = rank }
            end
        end
    end
    currentStatesDirty = false
    currentStatesContextKey = contextKey
    return states, true
end

local function GetCurrentNodeState(button)
    if not talentFrame then
        return nil
    end

    local nodeID = button.GetNodeID and button:GetNodeID() or nil
    if not nodeID then
        return nil
    end

    local nodeInfo = C_Traits.GetNodeInfo(talentFrame:GetConfigID(), nodeID)
    if not nodeInfo then
        return nil, nodeID, nil
    end

    -- Current selections are cached directly from C_Traits. Browsing another
    -- dungeon or boss reuses this table and performs no import-string work.
    if currentStates then
        return currentStates[nodeID], nodeID, nodeInfo
    end

    -- Conservative fallback only when Blizzard cannot generate an export string.
    local rank = tonumber(nodeInfo.ranksPurchased) or 0
    if rank <= 0 and (tonumber(nodeInfo.activeRank) or 0) > 0 then
        rank = 1
    end
    if rank <= 0 then
        return nil, nodeID, nodeInfo
    end

    local entryID = ResolveCurrentEntryID(nodeID, nodeInfo, rank)
    if not entryID and button.GetEntryID then
        entryID = button:GetEntryID()
    end
    if not entryID and nodeInfo.entryIDs and #nodeInfo.entryIDs > 0 then
        entryID = nodeInfo.entryIDs[1]
    end

    return entryID and { entryID = entryID, rank = rank } or nil, nodeID, nodeInfo
end

local function PercentColor(percent)
    if percent <= 0 then
        return 1.00, 0.18, 0.18
    elseif percent >= 100 then
        return 0.20, 1.00, 0.45
    elseif percent >= 70 then
        return 0.25, 0.95, 0.35
    elseif percent >= 40 then
        return 1.00, 0.82, 0.10
    else
        return 1.00, 0.48, 0.10
    end
end

local function EnsureButtonRegions(button)
    if not button.qfxmtPercentText then
        -- Normal talent nodes use the compact layout from the earlier version:
        -- plain percentage text directly beneath the Blizzard node.
        local font = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        font:SetPoint("TOP", button, "BOTTOM", 0, -2)
        font:SetJustifyH("CENTER")
        font:SetShadowOffset(1, -1)
        font:SetShadowColor(0, 0, 0, 1)
        local fontPath, fontSize = font:GetFont()
        if fontPath then
            font:SetFont(fontPath, math.max(11, fontSize or 11), "OUTLINE")
        end
        button.qfxmtPercentText = font
    end

    if not button.qfxmtPercentFrame then
        -- Capstone / apex nodes have extra rank widgets below the main icon.
        -- Give only those nodes an external badge so their percentage is not covered.
        local badge = CreateFrame("Frame", nil, button, "BackdropTemplate")
        badge:SetSize(36, 17)
        badge:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        badge:SetBackdropColor(0.02, 0.02, 0.02, 0.82)
        badge:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.90)
        badge:EnableMouse(false)
        badge:Hide()

        local font = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        font:SetPoint("CENTER", badge, "CENTER", 0, 0)
        font:SetJustifyH("CENTER")
        font:SetShadowOffset(1, -1)
        font:SetShadowColor(0, 0, 0, 1)
        local fontPath, fontSize = font:GetFont()
        if fontPath then
            font:SetFont(fontPath, math.max(11, fontSize or 11), "OUTLINE")
        end

        button.qfxmtPercentFrame = badge
        button.qfxmtPercentBadgeText = font
    end

    if not button.qfxmtMatchMark then
        local mark = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mark:SetPoint("TOPRIGHT", button, "TOPRIGHT", 5, 5)
        mark:SetJustifyH("RIGHT")
        mark:SetShadowOffset(1, -1)
        mark:SetShadowColor(0, 0, 0, 1)
        button.qfxmtMatchMark = mark
    end
end

local capstoneCacheConfigID
local capstoneCache = {}

local function IsCapstoneNode(button, nodeInfo, nodeID)
    if not nodeInfo then
        return false
    end

    -- Blizzard applies a dedicated mixin to capstone nodes.
    if button and button.CanPurchaseAnyRanksInCapstone then
        return true
    end

    -- 按 config 缓存 capstone 判定结果，避免每次刷新对每个 entry 重复调用
    -- C_Traits.GetEntryInfo。config 变化时（切专精/换配置）整体失效重建。
    local configID = currentStats and currentStats.configID or (talentFrame and talentFrame:GetConfigID())
    if not configID then
        return false
    end
    if capstoneCacheConfigID ~= configID then
        capstoneCacheConfigID = configID
        wipe(capstoneCache)
    end
    if nodeID then
        local cached = capstoneCache[nodeID]
        if cached ~= nil then
            return cached
        end
        local result = IsCapstoneNodeInfo(configID, nodeInfo)
        capstoneCache[nodeID] = result
        return result
    end
    return IsCapstoneNodeInfo(configID, nodeInfo)
end

local function PositionPercentBadge(button)
    local badge = button.qfxmtPercentFrame
    if not badge then
        return
    end

    badge:ClearAllPoints()
    badge:SetFrameLevel(button:GetFrameLevel() + 20)

    local parent = talentFrame and talentFrame.ButtonsParent
    local buttonLeft, buttonRight = button:GetLeft(), button:GetRight()
    local buttonCenter = button:GetCenter()
    local parentLeft = parent and parent:GetLeft()
    local parentRight = parent and parent:GetRight()
    local parentCenter = parent and parent:GetCenter()
    local leftSpace = buttonLeft and parentLeft and (buttonLeft - parentLeft) or 0
    local rightSpace = buttonRight and parentRight and (parentRight - buttonRight) or 0
    local requiredSpace = 42

    -- Only special capstone nodes use this outside badge. Prefer the outer side
    -- of the corresponding tree so the badge stays clear of the three rank icons.
    if buttonCenter and parentCenter and buttonCenter < parentCenter then
        if leftSpace >= requiredSpace then
            badge:SetPoint("RIGHT", button, "LEFT", -7, 0)
        elseif rightSpace >= requiredSpace then
            badge:SetPoint("LEFT", button, "RIGHT", 7, 0)
        else
            badge:SetPoint("BOTTOM", button, "TOP", 0, 7)
        end
    else
        if rightSpace >= requiredSpace then
            badge:SetPoint("LEFT", button, "RIGHT", 7, 0)
        elseif leftSpace >= requiredSpace then
            badge:SetPoint("RIGHT", button, "LEFT", -7, 0)
        else
            badge:SetPoint("BOTTOM", button, "TOP", 0, 7)
        end
    end
end

local function GetStatePercent(stats, nodeID, state)
    if not stats or not state or stats.validSamples <= 0 then
        return 0, 0
    end
    local nodeCounts = stats.counts[nodeID]
    local count = nodeCounts and nodeCounts[StateKey(state.entryID, state.rank)] or 0
    local percent = math.floor(count * 100 / stats.validSamples + 0.5)
    return percent, count
end

local function GetEntryUsagePercent(stats, nodeID, entryID)
    if not stats or not entryID or stats.validSamples <= 0 then
        return 0, 0
    end
    local nodeUsage = stats.entryUsage and stats.entryUsage[nodeID]
    local count = nodeUsage and nodeUsage[entryID] or 0
    local percent = math.floor(count * 100 / stats.validSamples + 0.5)
    return percent, count
end

local function GetHeroSelectionState()
    if not talentFrame or not currentStats then
        return nil
    end

    local container = talentFrame.HeroTalentsContainer
    local nodeInfo = container and container.activeSubTreeSelectionNodeInfo
    local nodeID = nodeInfo and nodeInfo.ID
    if not nodeID then
        return nil
    end

    -- The cached C_Traits state contains the selected SubTreeSelection entry.
    local state = currentStates and currentStates[nodeID] or nil
    if state then
        return state, nodeID, nodeInfo
    end

    -- Fallback for the short window while Blizzard is rebuilding the tree:
    -- map the active hero subtree back to its selection-node entry.
    local activeSubTreeID = container.activeSubTreeInfo and container.activeSubTreeInfo.ID or nil
    if activeSubTreeID then
        for _, entryID in ipairs(nodeInfo.entryIDs or {}) do
            local entryInfo = C_Traits.GetEntryInfo(currentStats.configID, entryID)
            if entryInfo and entryInfo.subTreeID == activeSubTreeID then
                return { entryID = entryID, rank = 1 }, nodeID, nodeInfo
            end
        end
    end

    return nil, nodeID, nodeInfo
end

local function EnsureHeroSpecRegions(button)
    if button.qfxmtHeroPercentFrame then
        return
    end

    local container = talentFrame and talentFrame.HeroTalentsContainer
    if not container then
        return
    end

    -- HeroSpecButton is not one of the regular talent buttons, so it needs
    -- its own badge parented to the hero container.
    local badge = CreateFrame("Frame", nil, talentFrame, "BackdropTemplate")
    badge:SetSize(42, 19)
    badge:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    badge:SetBackdropColor(0.02, 0.02, 0.02, 0.88)
    badge:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.95)
    badge:EnableMouse(false)
    badge:Hide()

    local font = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    font:SetPoint("CENTER", badge, "CENTER", 0, 0)
    font:SetJustifyH("CENTER")
    font:SetShadowOffset(1, -1)
    font:SetShadowColor(0, 0, 0, 1)
    local fontPath, fontSize = font:GetFont()
    if fontPath then
        font:SetFont(fontPath, math.max(12, fontSize or 12), "OUTLINE")
    end

    button.qfxmtHeroPercentFrame = badge
    button.qfxmtHeroPercent = font
end

local function PositionHeroSpecBadge(button)
    local badge = button and button.qfxmtHeroPercentFrame
    if not badge then
        return
    end

    badge:ClearAllPoints()
    badge:SetFrameLevel(math.max(button:GetFrameLevel(), talentFrame.HeroTalentsContainer:GetFrameLevel()) + 30)

    -- Keep the hero-specialization percentage separate from both the large
    -- hero icon and the small selector button beneath it.
    badge:SetPoint("LEFT", button, "RIGHT", 48, 3)
end

local function DecorateHeroSpecButton()
    local container = talentFrame and talentFrame.HeroTalentsContainer
    local button = container and container.HeroSpecButton
    if not button then
        return
    end
    if not percentagesEnabled then
        if button.qfxmtHeroPercent then
            button.qfxmtHeroPercent:SetText("")
        end
        if button.qfxmtHeroPercentFrame then
            button.qfxmtHeroPercentFrame:Hide()
        end
        return
    end

    EnsureHeroSpecRegions(button)
    if not button.qfxmtHeroPercentFrame then
        return
    end

    local current, nodeID = GetHeroSelectionState()
    if not current or not nodeID or not currentStats or currentStats.validSamples <= 0 then
        button.qfxmtHeroPercent:SetText("")
        button.qfxmtHeroPercentFrame:Hide()
        return
    end

    -- Hero specialization is a pure choice. Count the selected subtree entry,
    -- independent of rank, and always display the full 0%–100% range.
    local percent = GetEntryUsagePercent(currentStats, nodeID, current.entryID)
    local r, g, b = PercentColor(percent)
    PositionHeroSpecBadge(button)
    button.qfxmtHeroPercent:SetText(percent .. "%")
    button.qfxmtHeroPercent:SetTextColor(r, g, b, 1)
    button.qfxmtHeroPercentFrame:SetBackdropBorderColor(r, g, b, 0.95)
    button.qfxmtHeroPercentFrame:Show()
end

-- 仅选择型节点算"二选一"。当前客户端的多级（Tiered）节点同样是多 entry
-- （每个等级一个 entry），按 entry 数量判定会把普通多级天赋误判成选择节点。
local function IsChoiceNode(nodeInfo)
    local nodeType = Enum and Enum.TraitNodeType
    if not nodeInfo or not nodeType then
        return false
    end
    return nodeInfo.type == nodeType.Selection
        or nodeInfo.type == nodeType.SubTreeSelection
        or (nodeType.Choice ~= nil and nodeInfo.type == nodeType.Choice)
end

local function GetDisplayedEntryID(button, nodeInfo, recommended)
    -- An unselected choice button can keep showing its default entry even
    -- when that entry has 0% usage. Prefer the recommendation because the
    -- percentage and tooltip must describe the entry QFX actually wants.
    if recommended and recommended.entryID then
        return recommended.entryID
    end

    local entryID = button.GetEntryID and button:GetEntryID() or nil
    if not entryID then
        entryID = nodeInfo and nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or nil
    end
    if not entryID and nodeInfo and nodeInfo.entryIDs and #nodeInfo.entryIDs == 1 then
        entryID = nodeInfo.entryIDs[1]
    end
    return entryID
end

local function GetUnselectedEntryUsage(button, nodeID, nodeInfo, recommended)
    local displayedEntryID = GetDisplayedEntryID(button, nodeInfo, recommended)
    local displayedPercent, displayedCount = GetEntryUsagePercent(
        currentStats,
        nodeID,
        displayedEntryID
    )

    -- Without a recommended state, represent an unselected choice node by its
    -- most-used entry instead of whichever 0%-usage icon Blizzard happens to
    -- display. Ties retain the currently displayed entry for visual stability.
    if not recommended and IsChoiceNode(nodeInfo) then
        for _, entryID in ipairs(nodeInfo.entryIDs or {}) do
            local percent, count = GetEntryUsagePercent(currentStats, nodeID, entryID)
            if count > displayedCount then
                displayedEntryID = entryID
                displayedPercent = percent
                displayedCount = count
            end
        end
    end

    return displayedEntryID, displayedPercent, displayedCount
end

local function AppendTooltip(button)
    if pluginSuspended or not percentagesEnabled
        or not currentStats or not talentFrame or not GameTooltip:IsShown()
    then
        return
    end

    local current, nodeID, nodeInfo = GetCurrentNodeState(button)
    local recommended = nodeID and currentStats.recommended[nodeID] or nil
    local displayedEntryID, displayedPercent, displayedCount
    if not current then
        displayedEntryID, displayedPercent, displayedCount = GetUnselectedEntryUsage(
            button,
            nodeID,
            nodeInfo,
            recommended
        )
    end
    if not current and not recommended and displayedPercent <= 0 then
        return
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("QFX " .. T.selectedRate, 0.20, 0.80, 1.00)

    if current then
        local percent, count = GetStatePercent(currentStats, nodeID, current)
        local r, g, b = PercentColor(percent)
        local currentText = GetEntryName(currentStats.configID, current.entryID)
        if current.rank > 1 then
            currentText = currentText .. " · " .. T.rank .. " " .. current.rank
        end
        GameTooltip:AddDoubleLine(T.exactState .. "：" .. currentText, string.format("%d/%d (%d%%)", count, currentStats.validSamples, percent), 1, 1, 1, r, g, b)
    else
        GameTooltip:AddDoubleLine(T.exactState, T.notSelected, 1, 1, 1, 0.7, 0.7, 0.7)
        if displayedEntryID and displayedPercent > 0 then
            local r, g, b = PercentColor(displayedPercent)
            local displayedText = GetEntryName(currentStats.configID, displayedEntryID)
            GameTooltip:AddDoubleLine(T.selectedRate .. "：" .. displayedText, string.format("%d/%d (%d%%)", displayedCount, currentStats.validSamples, displayedPercent), 0.75, 0.75, 0.75, r, g, b)
        end
    end

    if recommended then
        local percent, count = GetStatePercent(currentStats, nodeID, recommended)
        local recommendedText = GetEntryName(currentStats.configID, recommended.entryID)
        if recommended.rank > 1 then
            recommendedText = recommendedText .. " · " .. T.rank .. " " .. recommended.rank
        end
        GameTooltip:AddDoubleLine(T.recommendation .. "：" .. recommendedText, string.format("%d/%d (%d%%)", count, currentStats.validSamples, percent), 0.35, 1.0, 0.55, 1, 0.82, 0)

        local isSame = current and current.entryID == recommended.entryID and current.rank == recommended.rank
        GameTooltip:AddLine(isSame and T.matches or T.differs, isSame and 0.25 or 1.0, isSame and 1.0 or 0.55, isSame and 0.45 or 0.15)
    end
    GameTooltip:Show()
end

local function DecorateButton(button)
    if not percentagesEnabled then
        if button.qfxmtPercentText then
            button.qfxmtPercentText:SetText("")
        end
        if button.qfxmtPercentBadgeText then
            button.qfxmtPercentBadgeText:SetText("")
        end
        if button.qfxmtPercentFrame then
            button.qfxmtPercentFrame:Hide()
        end
        if button.qfxmtMatchMark then
            button.qfxmtMatchMark:SetText("")
        end
        return
    end
    EnsureButtonRegions(button)

    local current, nodeID, nodeInfo = GetCurrentNodeState(button)
    local recommended = currentStats and nodeID and currentStats.recommended[nodeID] or nil
    local percentToShow

    if currentStats and currentStats.validSamples > 0 and nodeID then
        if current then
            local percent = GetStatePercent(currentStats, nodeID, current)
            -- 普通已选节点若为全员选择，只保留绿色勾；二选一节点始终显示当前选择率。
            if IsChoiceNode(nodeInfo) or percent < 100 then
                percentToShow = percent
            end
        else
            -- 灰色未选节点：推荐项优先；无推荐的二选一节点显示两个
            -- entry 中的最高使用率。整个节点无人选择时才保持空白。
            local _, percent = GetUnselectedEntryUsage(
                button,
                nodeID,
                nodeInfo,
                recommended
            )
            if percent > 0 then
                percentToShow = percent
            end
        end
    end

    local useExternalBadge = IsCapstoneNode(button, nodeInfo, nodeID)
    if percentToShow ~= nil then
        local r, g, b = PercentColor(percentToShow)
        if useExternalBadge then
            button.qfxmtPercentText:SetText("")
            PositionPercentBadge(button)
            button.qfxmtPercentBadgeText:SetText(percentToShow .. "%")
            button.qfxmtPercentBadgeText:SetTextColor(r, g, b, 1)
            button.qfxmtPercentFrame:SetBackdropBorderColor(r, g, b, 0.90)
            button.qfxmtPercentFrame:Show()
        else
            button.qfxmtPercentFrame:Hide()
            button.qfxmtPercentBadgeText:SetText("")
            button.qfxmtPercentText:SetText(percentToShow .. "%")
            button.qfxmtPercentText:SetTextColor(r, g, b, 1)
        end
    else
        button.qfxmtPercentText:SetText("")
        button.qfxmtPercentBadgeText:SetText("")
        button.qfxmtPercentFrame:Hide()
    end

    if recommended then
        local matches = current and current.entryID == recommended.entryID and current.rank == recommended.rank
        button.qfxmtMatchMark:SetText(matches and "|cff33ff66✓|r" or "|cffff8a22!|r")
    else
        button.qfxmtMatchMark:SetText("")
    end

    if not hookedButtons[button] then
        hookedButtons[button] = true
        button:HookScript("OnEnter", function(btn)
            AppendTooltip(btn)
        end)
    end
end

local function ClearTalentDecorations()
    if talentFrame and talentFrame.EnumerateAllTalentButtons then
        for button in talentFrame:EnumerateAllTalentButtons() do
            if button.qfxmtPercentText then
                button.qfxmtPercentText:SetText("")
            end
            if button.qfxmtPercentBadgeText then
                button.qfxmtPercentBadgeText:SetText("")
            end
            if button.qfxmtPercentFrame then
                button.qfxmtPercentFrame:Hide()
            end
            if button.qfxmtMatchMark then
                button.qfxmtMatchMark:SetText("")
            end
        end
    end

    local container = talentFrame and talentFrame.HeroTalentsContainer
    local heroButton = container and container.HeroSpecButton
    if heroButton then
        if heroButton.qfxmtHeroPercent then
            heroButton.qfxmtHeroPercent:SetText("")
        end
        if heroButton.qfxmtHeroPercentFrame then
            heroButton.qfxmtHeroPercentFrame:Hide()
        end
    end
end

local function PercentageToggleText()
    if percentagesEnabled then
        return locale == "zhCN" and "关闭显示"
            or locale == "zhTW" and "關閉顯示"
            or "Hide Display"
    end
    return locale == "zhCN" and "恢复显示"
        or locale == "zhTW" and "恢復顯示"
        or "Show Display"
end

local function SetPercentagesEnabled(enabled, persist)
    percentagesEnabled = not not enabled
    if persist then
        QFXMythicTalentsDB = QFXMythicTalentsDB or {}
        QFXMythicTalentsDB.showPercentages = percentagesEnabled
    end
    if sidePanel and sidePanel.PercentageToggleButton then
        sidePanel.PercentageToggleButton:SetText(PercentageToggleText())
    end
    if percentagesEnabled then
        ScheduleRefresh(0, true)
    else
        ClearTalentDecorations()
    end
end

local function RefreshPanelSelection()
    local frames = sidePanel and sidePanel.ContentScrollBox
        and sidePanel.ContentScrollBox:GetFrames()
        or {}
    for _, button in ipairs(frames) do
        local selected = button.qfxmtMode == selectedMode
            and (
                (selectedMode == "dungeon" and button.qfxmtDungeonID == selectedDungeonID)
                or (
                    selectedMode == "raid"
                    and button.qfxmtRaidID == selectedRaidID
                    and button.qfxmtBossID == selectedBossID
                )
            )
        SetButtonSelected(button, selected)
    end

    if sidePanel and sidePanel.HeroicButton and sidePanel.MythicButton then
        local heroicSelected = selectedMode == "raid" and selectedRaidDifficultyID == RAID_DIFFICULTY_HEROIC
        local mythicSelected = selectedMode == "raid" and selectedRaidDifficultyID == RAID_DIFFICULTY_MYTHIC
        SetButtonSelected(sidePanel.HeroicButton, heroicSelected)
        SetButtonSelected(sidePanel.MythicButton, mythicSelected)
        SetButtonSelected(sidePanel.DungeonTab, selectedMode == "dungeon")
        SetButtonSelected(sidePanel.RaidTab, selectedMode == "raid")
    end

    if API.Loadouts and API.Loadouts.OnSelectionChanged then
        pcall(API.Loadouts.OnSelectionChanged)
    end
end

-- Panel labels change on every refresh (selection, sample counts, status).
-- Skip the layout work for identical text; repeated SetText with the same
-- string still marks the FontString dirty.
local function SetPanelText(fontString, text)
    if not fontString then
        return
    end
    text = text or ""
    if fontString.qfxmtLastText ~= text then
        fontString.qfxmtLastText = text
        fontString:SetText(text)
    end
end

local function UpdatePanelText(statusText)
    if not sidePanel then
        return
    end

    if not API:IsDataReady(currentSpecID) then
        SetPanelText(sidePanel.Sample, DataStatusText())
        sidePanel.ImportButton:Disable()
        SetPanelText(sidePanel.Status, "")
        SetPanelText(sidePanel.DataVersion, "")
        return
    end

    local recommendation = currentSpecID and GetCurrentRecommendation(currentSpecID)
    if recommendation and currentStats then
        local sampleTarget = tonumber(recommendation.sampleCount) or #(recommendation.samples or {})
        SetPanelText(sidePanel.Sample, string.format("%s：%d/%d", T.sample, currentStats.validSamples or 0, sampleTarget))
        sidePanel.ImportButton:Enable()
    elseif recommendation then
        SetPanelText(sidePanel.Sample, T.parsing)
        sidePanel.ImportButton:Disable()
    else
        SetPanelText(sidePanel.Sample, T.noData)
        sidePanel.ImportButton:Disable()
    end

    SetPanelText(sidePanel.DataVersion, DataStatusText())

    local showDifficulty = selectedMode == "raid" and selectedRaidDifficultyID
    if statusText and statusText ~= "" then
        if showDifficulty then
            SetPanelText(sidePanel.Status, statusText .. " · " .. RaidDifficultyName(selectedRaidDifficultyID))
        else
            SetPanelText(sidePanel.Status, statusText)
        end
    elseif showDifficulty then
        SetPanelText(sidePanel.Status, RaidDifficultyName(selectedRaidDifficultyID))
    else
        SetPanelText(sidePanel.Status, "")
    end
end

local function RefreshOverlay()
    refreshTimer = nil
    refreshQueued = false
    local forceDecoration = forceOverlayRefresh
    forceOverlayRefresh = false
    if pluginSuspended
        or not talentFrame or not talentFrame:IsVisible()
        or not sidePanel or not sidePanel:IsShown()
    then
        return
    end

    -- Blizzard owns the import transition. Do not inspect or decorate its tree
    -- while the native commit is in progress; its config events queue one
    -- debounced refresh when the operation settles.
    if talentFrame.IsCommitInProgress and talentFrame:IsCommitInProgress() then
        return
    end

    currentSpecID = CurrentSpecID()
    local recommendation = currentSpecID and GetCurrentRecommendation(currentSpecID)
    if not currentSpecID or not recommendation then
        CancelStatisticsBuild()
        currentStats = nil
        currentStatsKey = nil
        currentStates = nil
        currentStatesDirty = true
        currentStatesContextKey = nil
        for button in talentFrame:EnumerateAllTalentButtons() do
            DecorateButton(button)
        end
        DecorateHeroSpecButton()
        UpdatePanelText()
        return
    end

    local treeID = talentFrame:GetTalentTreeID()
    local configID = talentFrame:GetConfigID()
    if not treeID or not configID then
        C_Timer.After(0.15, function()
            if talentFrame and talentFrame:IsVisible()
                and sidePanel and sidePanel:IsShown()
            then
                RefreshOverlay()
            end
        end)
        return
    end

    local key = table.concat({ currentSpecID, CurrentSelectionKey(), treeID, configID }, ":")
    local statisticsChanged = key ~= currentStatsKey
    if statisticsChanged then
        local newBuild = pendingStatisticsKey ~= key
        currentStats = nil
        currentStatsKey = nil
        QueueStatisticsBuild(currentSpecID, recommendation, key)
        if newBuild then
            -- Clear the previous recommendation immediately. The selected
            -- content's overlays are drawn only after its final sample is ready.
            for button in talentFrame:EnumerateAllTalentButtons() do
                DecorateButton(button)
            end
            DecorateHeroSpecButton()
        end
        UpdatePanelText()
        return
    end

    local states, statesChanged = BuildCurrentStates()
    currentStates = states

    if not forceDecoration and not statisticsChanged and not statesChanged then
        return
    end

    for button in talentFrame:EnumerateAllTalentButtons() do
        DecorateButton(button)
    end
    DecorateHeroSpecButton()
    UpdatePanelText()
end

ScheduleRefresh = function(delay, force)
    if pluginSuspended
        or not talentFrame or not talentFrame:IsVisible()
        or not sidePanel or not sidePanel:IsShown()
    then
        return
    end
    if force then
        forceOverlayRefresh = true
    end
    if refreshQueued then
        return
    end
    refreshQueued = true
    refreshTimer = C_Timer.NewTimer(delay or 0.03, RefreshOverlay)
end

local function CancelRefresh()
    if refreshTimer then
        refreshTimer:Cancel()
        refreshTimer = nil
    end
    refreshQueued = false
    forceOverlayRefresh = false
end

local function ResetRecommendationState()
    CancelStatisticsBuild()
    currentStats = nil
    currentStatsKey = nil
end

local RebuildContentButtons

local function SelectDungeon(dungeonID, automatic)
    if not dungeonID then
        return
    end
    selectedMode = "dungeon"
    selectedDungeonID = dungeonID
    QFXMythicTalentsDB.lastDungeonID = dungeonID
    QFXMythicTalentsDB.lastMode = selectedMode
    ResetRecommendationState()
    RefreshPanelSelection()
    UpdatePanelText(automatic and T.auto or T.manual)
    ScheduleRefresh(0)
end

local function SelectBoss(raidID, bossID, automatic)
    if not raidID or not bossID then
        return
    end
    selectedMode = "raid"
    selectedRaidID = raidID
    selectedBossID = bossID
    -- 难度在加载时已从 SavedVariables 恢复（ADDON_LOADED），此处不再自赋值。
    QFXMythicTalentsDB.lastMode = selectedMode
    QFXMythicTalentsDB.lastRaidID = raidID
    QFXMythicTalentsDB.lastBossID = bossID
    QFXMythicTalentsDB.lastRaidDifficultyID = selectedRaidDifficultyID
    ResetRecommendationState()
    RefreshPanelSelection()
    UpdatePanelText(automatic and T.auto or T.manual)
    ScheduleRefresh(0)
end

local function SelectRaidDifficulty(difficultyID, automatic)
    if difficultyID ~= RAID_DIFFICULTY_HEROIC and difficultyID ~= RAID_DIFFICULTY_MYTHIC then
        return
    end
    selectedMode = "raid"
    selectedRaidDifficultyID = difficultyID
    QFXMythicTalentsDB.lastMode = selectedMode
    QFXMythicTalentsDB.lastRaidDifficultyID = difficultyID
    ResetRecommendationState()
    if RebuildContentButtons then
        RebuildContentButtons()
    else
        RefreshPanelSelection()
    end
    UpdatePanelText(automatic and T.auto or T.manual)
    ScheduleRefresh(0)
end

local function SetMode(mode)
    if mode ~= "dungeon" and mode ~= "raid" then
        return
    end
    if mode == "raid" and #GetRaids() == 0 then
        return
    end
    selectedMode = mode
    QFXMythicTalentsDB.lastMode = mode
    ResetRecommendationState()
    if RebuildContentButtons then
        RebuildContentButtons()
    end
end

local function AutoSelectContent()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" and #GetRaids() > 0 then
        -- Never reuse the last raid inside an unknown raid instance. Doing so
        -- could present a valid-looking recommendation for the wrong boss.
        local raidID = DetectRaid()
        local raid = raidID and FindRaid(raidID)
        local bossID = QFXMythicTalentsDB and QFXMythicTalentsDB.lastBossID
        if not FindBoss(raidID, bossID) then
            bossID = raid and raid.bosses and raid.bosses[1] and raid.bosses[1].id
        end
        if raidID and bossID then
            selectedMode = "raid"
            selectedRaidDifficultyID = DetectRaidDifficulty() or selectedRaidDifficultyID
            if RebuildContentButtons then
                RebuildContentButtons()
            end
            SelectBoss(raidID, bossID, true)
            return
        end
    end

    selectedMode = "dungeon"
    if RebuildContentButtons then
        RebuildContentButtons()
    end
    local detected = DetectDungeon()
    if detected then
        SelectDungeon(detected, true)
        return
    end

    local saved = QFXMythicTalentsDB and QFXMythicTalentsDB.lastDungeonID
    if saved and GetRecommendation(CurrentSpecID(), saved) then
        SelectDungeon(saved, false)
    else
        local dungeons = GetDungeons()
        if dungeons[1] then
            SelectDungeon(dungeons[1].id, false)
        end
    end
end

local function GetRecommendedLoadoutName()
    local spec = GetSpecData(currentSpecID)
    local contentSlug
    if selectedMode == "raid" then
        local boss = FindBoss(selectedRaidID, selectedBossID)
        local difficultySlug = selectedRaidDifficultyID == RAID_DIFFICULTY_HEROIC and "Heroic" or "Mythic"
        contentSlug = (boss and (boss.slug or boss.name) or "Raid") .. "_" .. difficultySlug
    else
        local dungeon = FindDungeon(selectedDungeonID)
        contentSlug = dungeon and dungeon.slug or "MPlus"
    end
    local name = "QFX_" .. contentSlug .. "_" .. (spec and spec.name or tostring(currentSpecID))
    name = name:gsub("[^%w_-]", "")
    return name:sub(1, 45)
end

local function OpenImport()
    local recommendationText
    if selectedMode == "raid" then
        recommendationText = API:GetRecommendedRaidTalent(
            currentSpecID,
            selectedRaidID,
            selectedBossID,
            selectedRaidDifficultyID
        )
    else
        recommendationText = API:GetRecommendedDungeonTalent(
            currentSpecID,
            selectedDungeonID
        )
    end
    if not recommendationText or recommendationText == "" then
        return
    end
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage(T.combat, 1, 0.2, 0.2)
        return
    end
    if not ClassTalentLoadoutImportDialog then
        UIErrorsFrame:AddMessage("Blizzard talent import dialog is unavailable", 1, 0.2, 0.2)
        return
    end

    ClassTalentLoadoutImportDialog:ShowDialog()
    ClassTalentLoadoutImportDialog.ImportControl:SetText(recommendationText)

    ClassTalentLoadoutImportDialog.NameControl:SetText(GetRecommendedLoadoutName())
end

local function GetCurrentRecommendationText()
    if selectedMode == "raid" then
        return selectedRaidID and selectedBossID and selectedRaidDifficultyID
            and API:GetRecommendedRaidTalent(
                currentSpecID,
                selectedRaidID,
                selectedBossID,
                selectedRaidDifficultyID
            )
            or nil
    end
    return selectedDungeonID
        and API:GetRecommendedDungeonTalent(currentSpecID, selectedDungeonID)
        or nil
end

local function ApplyRecommendation()
    local recommendationText = GetCurrentRecommendationText()
    if not recommendationText or recommendationText == "" then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(T.noData, 1, 0.4, 0.2)
        end
        return
    end
    if not API.ApplyLoadoutText then
        OpenImport()
        return
    end
    API.ApplyLoadoutText(recommendationText, GetRecommendedLoadoutName())
end

local selectionVisualButtons = setmetatable({}, { __mode = "k" })

-- Selection colors. EllesmereUI's house selection language is a rail in the
-- user's accent color, so while the skin is active the addon's own highlight
-- follows that accent; without it the original blue is kept. Live accent
-- changes re-apply through the looks callback below.
local function ApplySelectionColors(button)
    local skin = ns.GetEUISkin and ns.GetEUISkin()
    if skin and skin.GetAccentColor then
        local r, g, b = skin.GetAccentColor()
        button.Selected:SetColorTexture(r, g, b, 0.16)
        button.SelectedAccent:SetColorTexture(r, g, b, 0.90)
        button.SelectedTop:SetColorTexture(r, g, b, 0.45)
        button.SelectedBottom:SetColorTexture(r, g, b, 0.28)
    else
        button.Selected:SetColorTexture(0.05, 0.52, 0.72, 0.22)
        button.SelectedAccent:SetColorTexture(0.20, 0.88, 1.00, 0.95)
        button.SelectedTop:SetColorTexture(0.20, 0.78, 1.00, 0.50)
        button.SelectedBottom:SetColorTexture(0.08, 0.38, 0.55, 0.55)
    end
end

local function EnsureSelectionVisual(button)
    if button.Selected then
        return
    end

    -- The selection art lives on an overlay child frame. EllesmereUI's skin
    -- passes (including the re-strip that runs when the talent window is
    -- re-shown) fade every texture region on a skinned button, but they never
    -- touch a child frame's own textures.
    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:SetFrameLevel(button:GetFrameLevel() + 1)
    button.qfxmtSelectionHost = host

    button.Selected = host:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.Selected:SetPoint("TOPLEFT", 2, -2)
    button.Selected:SetPoint("BOTTOMRIGHT", -2, 2)
    button.Selected:SetColorTexture(0.05, 0.52, 0.72, 0.22)
    button.Selected:Hide()

    button.SelectedAccent = host:CreateTexture(nil, "OVERLAY", nil, 2)
    button.SelectedAccent:SetPoint("TOPLEFT", 2, -3)
    button.SelectedAccent:SetPoint("BOTTOMLEFT", 2, 3)
    button.SelectedAccent:SetWidth(3)
    button.SelectedAccent:SetColorTexture(0.20, 0.88, 1.00, 0.95)
    button.SelectedAccent:Hide()

    button.SelectedTop = host:CreateTexture(nil, "OVERLAY", nil, 1)
    button.SelectedTop:SetPoint("TOPLEFT", 3, -2)
    button.SelectedTop:SetPoint("TOPRIGHT", -2, -2)
    button.SelectedTop:SetHeight(1)
    button.SelectedTop:SetColorTexture(0.20, 0.78, 1.00, 0.50)
    button.SelectedTop:Hide()

    button.SelectedBottom = host:CreateTexture(nil, "OVERLAY", nil, 1)
    button.SelectedBottom:SetPoint("BOTTOMLEFT", 3, 2)
    button.SelectedBottom:SetPoint("BOTTOMRIGHT", -2, 2)
    button.SelectedBottom:SetHeight(1)
    button.SelectedBottom:SetColorTexture(0.08, 0.38, 0.55, 0.55)
    button.SelectedBottom:Hide()

    local animation = button.Selected:CreateAnimationGroup()
    local fade = animation:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.14)
    fade:SetSmoothing("OUT")
    button.SelectedAnimation = animation
    selectionVisualButtons[button] = true
    ApplySelectionColors(button)
end

if ns.RegisterEUISkinLooks then
    ns.RegisterEUISkinLooks(function()
        for button in pairs(selectionVisualButtons) do
            ApplySelectionColors(button)
        end
    end)
end

SetButtonSelected = function(button, selected)
    if not button then
        return
    end
    EnsureSelectionVisual(button)

    button.Selected:SetShown(selected)
    button.SelectedAccent:SetShown(selected)
    button.SelectedTop:SetShown(selected)
    button.SelectedBottom:SetShown(selected)

    if selected and not button.qfxmtIsSelected then
        button.SelectedAnimation:Stop()
        button.SelectedAnimation:Play()
    elseif not selected then
        button.SelectedAnimation:Stop()
    end
    button.qfxmtIsSelected = selected

    local fontString = button:GetFontString()
    if fontString and button.qfxmtContentButton then
        if selected then
            fontString:SetTextColor(0.92, 0.98, 1.00)
        elseif button.qfxmtHasData == false then
            fontString:SetTextColor(0.50, 0.52, 0.56)
        else
            fontString:SetTextColor(1.00, 0.82, 0.10)
        end
    end
end

local function InitContentRow(button, elementData)
    if not button.qfxmtRowBuilt then
        button.qfxmtRowBuilt = true
        button.qfxmtContentButton = true
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.qfxmtTooltip or self:GetText() or "")
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        -- One click handler per pooled row; it reads the row's stored
        -- selection data, so rebuilding the list no longer allocates a
        -- closure per entry.
        button:SetScript("OnClick", function(self)
            if self.qfxmtMode == "dungeon" then
                if self.qfxmtDungeonID then
                    SelectDungeon(self.qfxmtDungeonID, false)
                end
            elseif self.qfxmtMode == "raid"
                and self.qfxmtRaidID and self.qfxmtBossID
            then
                SelectBoss(self.qfxmtRaidID, self.qfxmtBossID, false)
            end
        end)
        EnsureSelectionVisual(button)
        ns.RegisterEUISkin(button, "button")
        local fontString = button:GetFontString()
        if fontString then
            fontString:SetWidth(150)
            fontString:SetWordWrap(false)
        end
    end

    button:SetText(elementData.label)
    button.qfxmtTooltip = elementData.tooltip or elementData.label
    button.qfxmtHasData = elementData.hasData
    button.qfxmtMode = elementData.mode
    button.qfxmtDungeonID = elementData.dungeonID
    button.qfxmtRaidID = elementData.raidID
    button.qfxmtBossID = elementData.bossID
    -- Rows are pooled and reinitialized whenever they scroll back into view,
    -- so the selected state is derived here instead of only relying on
    -- RefreshPanelSelection walking the currently acquired frames.
    local selected = elementData.mode == selectedMode
        and (
            (elementData.mode == "dungeon" and elementData.dungeonID == selectedDungeonID)
            or (
                elementData.mode == "raid"
                and elementData.raidID == selectedRaidID
                and elementData.bossID == selectedBossID
            )
        )
    button.qfxmtIsSelected = selected
    SetButtonSelected(button, selected)
end

RebuildContentButtons = function()
    if not sidePanel then
        return
    end

    if sidePanel.DungeonTab then
        sidePanel.DungeonTab:SetEnabled(true)
        sidePanel.RaidTab:SetEnabled(#GetRaids() > 0)
    end
    if sidePanel.HeroicButton then
        local showRaidDifficulty = selectedMode == "raid"
        sidePanel.HeroicButton:SetShown(showRaidDifficulty)
        sidePanel.MythicButton:SetShown(showRaidDifficulty)
        sidePanel.DifficultyLabel:SetShown(showRaidDifficulty)
    end

    -- The list fills the fixed area between the mode tabs (or raid difficulty
    -- buttons) and the recommendation footer; rows beyond the visible extent
    -- are reached with the scrollbar instead of being hidden.
    if sidePanel.ContentScrollBox and sidePanel.Footer then
        local topOffset = selectedMode == "raid" and -104 or -68
        sidePanel.ContentScrollBox:ClearAllPoints()
        sidePanel.ContentScrollBox:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", 8, topOffset)
        sidePanel.ContentScrollBox:SetPoint("BOTTOMRIGHT", sidePanel.Footer, "TOPRIGHT", -20, -2)
    end

    if not contentDataProvider then
        return
    end
    contentDataProvider:Flush()

    if selectedMode == "raid" then
        for _, raid in ipairs(GetRaids()) do
            for _, boss in ipairs(raid.bosses or {}) do
                local hasData = currentSpecID and API:GetRaidData(
                    currentSpecID, raid.id, boss.id, selectedRaidDifficultyID
                ) ~= nil
                local tooltip = RaidName(raid) .. " - " .. BossName(boss)
                    .. " · " .. RaidDifficultyName(selectedRaidDifficultyID)
                if not hasData then
                    tooltip = tooltip .. " · " .. T.noData
                end
                contentDataProvider:Insert({
                    label = BossName(boss),
                    tooltip = tooltip,
                    hasData = hasData,
                    mode = "raid",
                    raidID = raid.id,
                    bossID = boss.id,
                })
            end
        end
    else
        for _, dungeon in ipairs(GetDungeons()) do
            local label = DungeonName(dungeon)
            contentDataProvider:Insert({
                label = label,
                tooltip = label,
                hasData = true,
                mode = "dungeon",
                dungeonID = dungeon.id,
            })
        end
    end
    RefreshPanelSelection()

    -- Keep the current selection reachable: when the panel opens or the mode
    -- switches, bring the selected row into view without jumping if it is
    -- already visible.
    if sidePanel.ContentScrollBox and sidePanel.ContentScrollBox.ScrollToElementDataByPredicate then
        sidePanel.ContentScrollBox:ScrollToElementDataByPredicate(function(elementData)
            return elementData.mode == selectedMode
                and (
                    (selectedMode == "dungeon" and elementData.dungeonID == selectedDungeonID)
                    or (
                        selectedMode == "raid"
                        and elementData.raidID == selectedRaidID
                        and elementData.bossID == selectedBossID
                    )
                )
        end, ScrollBoxConstants.AlignNearest)
    end
end

local function UpdateAdaptiveSectionHeight()
    if not sidePanel or not sidePanel.LoadoutSection then
        return
    end
    local panelHeight = sidePanel:GetHeight() or 0
    if panelHeight <= 0 then
        return
    end

    -- Keep the personal-loadout area useful on both compact and tall talent
    -- frames.  A fixed 340px section made the panel extend far below the
    -- Blizzard frame at smaller UI scales and wasted a large blank area.
    local desired = math.floor(panelHeight * 0.33 + 0.5)
    desired = math.max(190, math.min(300, desired))
    sidePanel.LoadoutSection:SetHeight(desired)
end

local function PositionSidePanel()
    if not sidePanel or not PlayerSpellsFrame then
        return
    end
    sidePanel:ClearAllPoints()
    -- Dock to the right edge of the talent frame at exactly the Blizzard
    -- frame's current height. When TalentLoadoutsEx is visible, only the
    -- horizontal anchor changes; vertical sizing still follows PlayerSpellsFrame.
    local anchorFrame = PlayerSpellsFrame
    if API.Loadouts and API.Loadouts.IsSuppressed and API.Loadouts:IsSuppressed() then
        local tleFrame = _G.TalentLoadoutExMainFrame
        if tleFrame and tleFrame:IsVisible() then
            anchorFrame = tleFrame
        end
    end
    sidePanel:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 0, 0)

    local height = PlayerSpellsFrame:GetHeight()
    if type(height) == "number" and height > 0 then
        local sourceScale = PlayerSpellsFrame.GetEffectiveScale and PlayerSpellsFrame:GetEffectiveScale() or 1
        local panelScale = sidePanel.GetEffectiveScale and sidePanel:GetEffectiveScale() or 1
        if type(sourceScale) == "number" and type(panelScale) == "number" and panelScale > 0 then
            height = height * sourceScale / panelScale
        end
        sidePanel:SetHeight(height)
        UpdateAdaptiveSectionHeight()
    end
end

local function UpdateFooterAnchor()
    if not sidePanel or not sidePanel.Footer then
        return
    end
    local suppressSection = API.Loadouts
        and API.Loadouts.IsSuppressed
        and API.Loadouts:IsSuppressed()
    sidePanel.Footer:ClearAllPoints()
    if sidePanel.LoadoutSection and not suppressSection then
        sidePanel.LoadoutSection:Show()
        sidePanel.Footer:SetPoint("BOTTOMLEFT", sidePanel.LoadoutSection, "TOPLEFT", 0, 0)
        sidePanel.Footer:SetPoint("BOTTOMRIGHT", sidePanel.LoadoutSection, "TOPRIGHT", 0, 0)
    else
        if sidePanel.LoadoutSection then
            sidePanel.LoadoutSection:Hide()
        end
        sidePanel.Footer:SetPoint("BOTTOMLEFT", sidePanel, "BOTTOMLEFT", 5, 5)
        sidePanel.Footer:SetPoint("BOTTOMRIGHT", sidePanel, "BOTTOMRIGHT", -5, 5)
    end
end

API.RefreshFooterAnchor = UpdateFooterAnchor

local function CreateSidePanel()
    if sidePanel then
        return
    end

    sidePanel = CreateFrame("Frame", "QFXMythicTalentsDungeonPanel", UIParent, "BackdropTemplate")
    sidePanel:SetSize(200, 700)
    sidePanel:SetFrameStrata("DIALOG")
    sidePanel:SetClampedToScreen(true)
    sidePanel:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    sidePanel:SetBackdropColor(0.025, 0.025, 0.035, 0.96)
    sidePanel:SetBackdropBorderColor(0.55, 0.45, 0.22, 1)
    sidePanel:Hide()
    ns.RegisterEUISkin(sidePanel, "shell")

    sidePanel.Title = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sidePanel.Title:SetPoint("TOP", 0, -13)
    sidePanel.Title:SetText(T.title)
    ns.RegisterEUISkin(sidePanel.Title, "font")

    sidePanel.CloseButton = CreateFrame("Button", nil, sidePanel, "UIPanelCloseButton")
    sidePanel.CloseButton:SetSize(22, 22)
    sidePanel.CloseButton:SetPoint("TOPRIGHT", -1, -1)
    sidePanel.CloseButton:SetScript("OnClick", function()
        SuspendAddon()
    end)
    sidePanel.CloseButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:SetText(locale == "zhCN" and "关闭插件" or locale == "zhTW" and "關閉插件" or "Disable Addon")
        GameTooltip:AddLine(
            locale == "zhCN" and "停止本次登录期间的全部运行；重载界面或重新登录后自动启动。"
                or locale == "zhTW" and "停止本次登入期間的全部運作；重載介面或重新登入後自動啟動。"
                or "Stops all addon activity for this session. It starts again after reload or login.",
            0.75, 0.85, 1, true
        )
        GameTooltip:AddLine(
            locale == "zhCN" and "输入 /qmt 可立即重新启动"
                or locale == "zhTW" and "輸入 /qmt 可立即重新啟動"
                or "Use /qmt to start it again now.",
            0.45, 0.85, 1
        )
        GameTooltip:Show()
    end)
    sidePanel.CloseButton:SetScript("OnLeave", GameTooltip_Hide)
    ns.RegisterEUISkin(sidePanel.CloseButton, "close")

    sidePanel.DungeonTab = CreateFrame("Button", nil, sidePanel, "UIPanelButtonTemplate")
    sidePanel.DungeonTab:SetSize(92, 24)
    sidePanel.DungeonTab:SetPoint("TOPLEFT", 8, -37)
    EnsureSelectionVisual(sidePanel.DungeonTab)
    ns.RegisterEUISkin(sidePanel.DungeonTab, "buttonLabel")
    sidePanel.DungeonTab:SetText(locale == "zhCN" and "地下城" or locale == "zhTW" and "地城" or "M+")
    sidePanel.DungeonTab:SetScript("OnClick", function()
        SetMode("dungeon")
        local dungeonID = selectedDungeonID
            or (QFXMythicTalentsDB and QFXMythicTalentsDB.lastDungeonID)
            or (GetDungeons()[1] and GetDungeons()[1].id)
        if dungeonID then
            SelectDungeon(dungeonID, false)
        end
    end)

    sidePanel.RaidTab = CreateFrame("Button", nil, sidePanel, "UIPanelButtonTemplate")
    sidePanel.RaidTab:SetSize(92, 24)
    sidePanel.RaidTab:SetPoint("TOPRIGHT", -8, -37)
    EnsureSelectionVisual(sidePanel.RaidTab)
    ns.RegisterEUISkin(sidePanel.RaidTab, "buttonLabel")
    sidePanel.RaidTab:SetText(locale == "zhCN" and "团本" or locale == "zhTW" and "團本" or "Raid")
    sidePanel.RaidTab:SetScript("OnClick", function()
        selectedMode = "raid"
        selectedRaidDifficultyID = DetectRaidDifficulty() or selectedRaidDifficultyID
        local raid = FindRaid(selectedRaidID) or GetRaids()[1]
        local boss = raid and raid.bosses and raid.bosses[1]
        if raid and boss then
            selectedRaidID = raid.id
            selectedBossID = FindBoss(raid.id, selectedBossID) and selectedBossID or boss.id
            SetMode("raid")
            SelectBoss(selectedRaidID, selectedBossID, false)
        end
    end)

    sidePanel.DifficultyLabel = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sidePanel.DifficultyLabel:SetPoint("TOP", 0, -65)
    sidePanel.DifficultyLabel:SetText(T.raidDifficulty)
    sidePanel.DifficultyLabel:Hide()
    ns.RegisterEUISkin(sidePanel.DifficultyLabel, "font")

    local function CreateDifficultyButton(difficultyID, label, point, relativePoint, x, y)
        local button = CreateFrame("Button", nil, sidePanel, "UIPanelButtonTemplate")
        button:SetSize(90, 22)
        button:SetPoint(point, sidePanel, relativePoint, x, y)
        button:SetText(label)
        EnsureSelectionVisual(button)
        ns.RegisterEUISkin(button, "buttonLabel")
        button:SetScript("OnClick", function()
            SelectRaidDifficulty(difficultyID, false)
        end)
        button:SetScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_LEFT")
            GameTooltip:SetText(T.raidDifficulty .. "：" .. RaidDifficultyName(difficultyID))
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        button:Hide()
        return button
    end

    sidePanel.HeroicButton = CreateDifficultyButton(
        RAID_DIFFICULTY_HEROIC, T.heroic, "TOPLEFT", "TOPLEFT", 8, -78
    )
    sidePanel.MythicButton = CreateDifficultyButton(
        RAID_DIFFICULTY_MYTHIC, T.mythic, "TOPRIGHT", "TOPRIGHT", -8, -78
    )

    -- Bottom section: personal loadouts, populated by the Loadouts module.
    -- The recommendation footer sits directly above it.
    sidePanel.LoadoutSection = CreateFrame("Frame", nil, sidePanel)
    sidePanel.LoadoutSection:SetPoint("BOTTOMLEFT", 5, 5)
    sidePanel.LoadoutSection:SetPoint("BOTTOMRIGHT", -5, 5)
    sidePanel.LoadoutSection:SetHeight(231)

    sidePanel.Footer = CreateFrame("Frame", nil, sidePanel)
    sidePanel.Footer:SetPoint("BOTTOMLEFT", sidePanel.LoadoutSection, "TOPLEFT", 0, 0)
    sidePanel.Footer:SetPoint("BOTTOMRIGHT", sidePanel.LoadoutSection, "TOPRIGHT", 0, 0)
    sidePanel.Footer:SetHeight(111)

    sidePanel.Footer.Background = sidePanel.Footer:CreateTexture(nil, "BACKGROUND")
    sidePanel.Footer.Background:SetAllPoints()
    sidePanel.Footer.Background:SetColorTexture(0.015, 0.020, 0.035, 0.94)

    sidePanel.Footer.Divider = sidePanel.Footer:CreateTexture(nil, "BORDER")
    sidePanel.Footer.Divider:SetPoint("TOPLEFT", 1, 0)
    sidePanel.Footer.Divider:SetPoint("TOPRIGHT", -1, 0)
    sidePanel.Footer.Divider:SetHeight(1)
    sidePanel.Footer.Divider:SetColorTexture(0.32, 0.48, 0.58, 0.55)

    sidePanel.Sample = sidePanel.Footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sidePanel.Sample:SetPoint("TOP", 0, -5)
    sidePanel.Sample:SetWidth(180)
    sidePanel.Sample:SetJustifyH("CENTER")
    sidePanel.Sample:SetWordWrap(false)
    ns.RegisterEUISkin(sidePanel.Sample, "font")

    sidePanel.Status = sidePanel.Footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sidePanel.Status:SetPoint("TOP", 0, -19)
    sidePanel.Status:SetWidth(180)
    sidePanel.Status:SetJustifyH("CENTER")
    sidePanel.Status:SetWordWrap(false)
    ns.RegisterEUISkin(sidePanel.Status, "font")

    sidePanel.DataVersion = sidePanel.Footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sidePanel.DataVersion:SetPoint("TOP", 0, -33)
    sidePanel.DataVersion:SetWidth(180)
    sidePanel.DataVersion:SetJustifyH("CENTER")
    sidePanel.DataVersion:SetWordWrap(false)
    sidePanel.DataVersion:SetTextColor(0.45, 0.72, 0.82)
    ns.RegisterEUISkin(sidePanel.DataVersion, "font")

    sidePanel.ImportButton = CreateFrame("Button", nil, sidePanel.Footer, "UIPanelButtonTemplate")
    sidePanel.ImportButton:SetSize(184, 25)
    sidePanel.ImportButton:SetPoint("BOTTOM", 0, 31)
    sidePanel.ImportButton:SetText(T.apply)
    sidePanel.ImportButton:SetScript("OnClick", ApplyRecommendation)
    ns.RegisterEUISkin(sidePanel.ImportButton, "buttonLabel")

    sidePanel.PercentageToggleButton = CreateFrame("Button", nil, sidePanel.Footer, "UIPanelButtonTemplate")
    sidePanel.PercentageToggleButton:SetSize(184, 25)
    sidePanel.PercentageToggleButton:SetPoint("BOTTOM", 0, 2)
    sidePanel.PercentageToggleButton:SetText(PercentageToggleText())
    sidePanel.PercentageToggleButton:SetScript("OnClick", function()
        SetPercentagesEnabled(not percentagesEnabled, true)
    end)
    ns.RegisterEUISkin(sidePanel.PercentageToggleButton, "buttonLabel")

    -- Middle section: the dungeon and boss rows live in a scroll box that
    -- fills the fixed area between the mode tabs and the recommendation
    -- footer. The scrollbar only appears once the rows cannot all fit.
    sidePanel.ContentScrollBox = CreateFrame("Frame", nil, sidePanel, "WowScrollBoxList")
    sidePanel.ContentScrollBar = CreateFrame("EventFrame", nil, sidePanel, "WowTrimScrollBar")
    sidePanel.ContentScrollBar:SetPoint("TOPLEFT", sidePanel.ContentScrollBox, "TOPRIGHT", 1, 0)
    sidePanel.ContentScrollBar:SetPoint("BOTTOMLEFT", sidePanel.ContentScrollBox, "BOTTOMRIGHT", 1, 0)
    ns.RegisterEUISkin(sidePanel.ContentScrollBar, "scrollbar")

    local contentView = CreateScrollBoxListLinearView()
    contentView:SetElementExtent(25)
    contentView:SetPadding(2, 2, 0, 0, 2)
    contentView:SetElementInitializer("UIPanelButtonTemplate", InitContentRow)
    contentDataProvider = CreateDataProvider()
    ScrollUtil.InitScrollBoxListWithScrollBar(
        sidePanel.ContentScrollBox, sidePanel.ContentScrollBar, contentView
    )
    sidePanel.ContentScrollBox:SetDataProvider(
        contentDataProvider, ScrollBoxConstants.RetainScrollPosition
    )
    sidePanel.ContentScrollBar:Hide()

    local function UpdateContentScrollBar()
        sidePanel.ContentScrollBar:SetShown(sidePanel.ContentScrollBox:HasScrollableExtent())
    end
    sidePanel.ContentScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, UpdateContentScrollBar)
    sidePanel.ContentScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, UpdateContentScrollBar)

    RebuildContentButtons()

    if API.Loadouts and API.Loadouts.Populate then
        pcall(API.Loadouts.Populate, sidePanel.LoadoutSection)
    end
    UpdateFooterAnchor()
end

local function ShowPanel()
    if pluginSuspended then
        return
    end
    currentSpecID = CurrentSpecID()
    EnsureDataLoaded(currentSpecID, CurrentClassToken())
    if not sidePanel then
        CreateSidePanel()
    end
    PositionSidePanel()
    sidePanel:Show()
    if talentFrame then
        talentFrame.enableCommitCastBar = false
    end
    SetOperationalEventsEnabled(true)
    if API.Loadouts and API.Loadouts.OnShown then
        pcall(API.Loadouts.OnShown)
    end

    -- Re-showing the panel after Blizzard rebuilds the talent frame must not
    -- overwrite a manual dungeon, boss, or raid difficulty selection, including
    -- combinations that legitimately have no early-season data yet.
    local hasValidSelection = selectedMode == "raid"
        and FindBoss(selectedRaidID, selectedBossID) ~= nil
        or selectedMode == "dungeon" and FindDungeon(selectedDungeonID) ~= nil
    if not hasValidSelection then
        AutoSelectContent()
    else
        RebuildContentButtons()
        RefreshPanelSelection()
        UpdatePanelText()
    end
    ScheduleRefresh(0.08, true)
end

local function HidePanel()
    SetOperationalEventsEnabled(false)
    panelRecoveryToken = panelRecoveryToken + 1
    CancelRefresh()
    if panelRecoveryTimer then
        panelRecoveryTimer:Cancel()
        panelRecoveryTimer = nil
    end
    if panelPositionTimer then
        panelPositionTimer:Cancel()
        panelPositionTimer = nil
    end
    if visibilitySyncTimer then
        visibilitySyncTimer:Cancel()
        visibilitySyncTimer = nil
    end
    if sidePanel then
        sidePanel:Hide()
    end
    if API.Loadouts and API.Loadouts.OnHidden then
        pcall(API.Loadouts.OnHidden)
    end
    currentStats = nil
    currentStatsKey = nil
    currentStates = nil
    currentStatesDirty = true
    currentStatesContextKey = nil
    treeContext = nil
    CancelStatisticsBuild()
    local backend = GetUnifiedDataAPI()
    if backend and type(backend.ReleaseActiveSpec) == "function" then
        -- Drop all strong references immediately. Do not run a full Lua GC here:
        -- it creates a visible CPU spike charged to this addon after the panel
        -- has closed. WoW's normal incremental collector reclaims the tables.
        backend:ReleaseActiveSpec(false)
    end
end

SuspendAddon = function()
    pluginSuspended = true
    GameTooltip_Hide()
    ClearTalentDecorations()
    HidePanel()
    if talentFrame and originalEnableCommitCastBar ~= nil then
        talentFrame.enableCommitCastBar = originalEnableCommitCastBar
    end
end

local function ResumeAddon()
    pluginSuspended = false
end

local function IsTalentFrameVisible()
    return PlayerSpellsFrame and PlayerSpellsFrame:IsVisible()
        and talentFrame and talentFrame:IsVisible()
end

local function SyncPanelVisibility()
    if not pluginSuspended and IsTalentFrameVisible() then
        if not sidePanel or not sidePanel:IsShown() then
            ShowPanel()
        end
    else
        if operationalEventsEnabled or (sidePanel and sidePanel:IsShown()) then
            HidePanel()
        end
    end
end

local function RecoverPanelAfterNativeTransition()
    panelRecoveryToken = panelRecoveryToken + 1
    local token = panelRecoveryToken
    if panelPositionTimer then
        panelPositionTimer:Cancel()
    end
    if panelRecoveryTimer then
        panelRecoveryTimer:Cancel()
    end

    -- Position-only pass for the native frame's immediate hide/show pair. This
    -- deliberately does not invalidate statistics or redraw talent buttons.
    panelPositionTimer = C_Timer.NewTimer(0, function()
        panelPositionTimer = nil
        if token == panelRecoveryToken
            and IsTalentFrameVisible()
            and sidePanel
            and sidePanel:IsShown()
        then
            PositionSidePanel()
        end
    end)

    -- Config creation emits several events in quick succession. Every event
    -- advances panelRecoveryToken, so only the final quiet-period callback does
    -- one complete recovery.
    panelRecoveryTimer = C_Timer.NewTimer(0.35, function()
        panelRecoveryTimer = nil
        if token ~= panelRecoveryToken then
            return
        end

        if not IsTalentFrameVisible() then
            HidePanel()
            return
        end

        if not sidePanel or not sidePanel:IsShown() then
            ShowPanel()
            return
        end

        PositionSidePanel()
        currentSpecID = CurrentSpecID()
        currentStats = nil
        currentStatsKey = nil
        currentStates = nil
        currentStatesDirty = true
        currentStatesContextKey = nil
        treeContext = nil
        CancelStatisticsBuild()
        ScheduleRefresh(0.03)
    end)
end

local function InitializeBlizzardUI()
    if not PlayerSpellsFrame or not PlayerSpellsFrame.TalentsFrame then
        return
    end

    if not talentFrame then
        talentFrame = PlayerSpellsFrame.TalentsFrame
        originalEnableCommitCastBar = talentFrame.enableCommitCastBar
        frameEvents:UnregisterEvent("ADDON_LOADED")
    end
    if pluginSuspended or blizzardHooksInstalled then
        return
    end
    blizzardHooksInstalled = true

    -- WoW 12.0.7's talent-commit cast bar can raise a secret-value taint error
    -- when a loadout string originated in an addon database. Keep Blizzard's
    -- native import/config state machine and spinner intact, but do not start
    -- the affected OverlayPlayerCastingBarFrame path.
    -- A loadout import can transiently hide/rebuild TalentsFrame. Delay the
    -- visibility decision by one frame so that a hide/show pair does not leave
    -- the QFX panel permanently hidden.
    local function ScheduleVisibilitySync()
        if pluginSuspended then
            return
        end
        if visibilitySyncTimer then
            visibilitySyncTimer:Cancel()
        end
        visibilitySyncTimer = C_Timer.NewTimer(0, function()
            visibilitySyncTimer = nil
            SyncPanelVisibility()
        end)
    end
    talentFrame:HookScript("OnShow", ScheduleVisibilitySync)
    talentFrame:HookScript("OnHide", ScheduleVisibilitySync)
    PlayerSpellsFrame:HookScript("OnShow", ScheduleVisibilitySync)
    PlayerSpellsFrame:HookScript("OnHide", ScheduleVisibilitySync)
    hooksecurefunc(PlayerSpellsFrame, "SetInspecting", function()
        currentSpecID = CurrentSpecID()
        EnsureDataLoaded(currentSpecID, CurrentClassToken())
        currentStats = nil
        currentStatsKey = nil
        currentStates = nil
        currentStatesDirty = true
        currentStatesContextKey = nil
        treeContext = nil
        CancelStatisticsBuild()
        if IsTalentFrameVisible() then
            ScheduleRefresh(0.03, true)
        end
    end)
    PlayerSpellsFrame:HookScript("OnSizeChanged", function()
        if sidePanel and sidePanel:IsShown() then
            PositionSidePanel()
        end
    end)

    -- The full-height side strip occupies the space right of the Blizzard
    -- frame; shift the frame by half the strip width so both stay centered.
    -- Dynamic panel layout offsets reset between show cycles, so re-applying
    -- on each Show matches how other side panels behave.
    hooksecurefunc(PlayerSpellsFrame, "Show", function()
        if pluginSuspended or InCombatLockdown() or not sidePanel then
            return
        end
        local halfWidth = sidePanel:GetWidth() / 2
        if halfWidth > 0 then
            pcall(PlayerSpellsFrame.AdjustPointsOffset, PlayerSpellsFrame, -halfWidth, 0)
        end
    end)

    if talentFrame:IsVisible() then
        ShowPanel()
    end
end

local function OpenTalentFrame()
    ResumeAddon()
    if not PlayerSpellsFrame and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_PlayerSpells")
    end
    InitializeBlizzardUI()
    if not PlayerSpellsFrame then
        return
    end

    PlayerSpellsFrame:Show()
    if PlayerSpellsFrame.talentTabID then
        PlayerSpellsFrame:SetTab(PlayerSpellsFrame.talentTabID)
    end
    if IsTalentFrameVisible() then
        ShowPanel()
    end
end

API.OpenTalentFrame = OpenTalentFrame
API.GetTalentFrame = function()
    return talentFrame
end
API.GetCurrentSpecID = function()
    return CurrentSpecID()
end

frameEvents:RegisterEvent("ADDON_LOADED")
frameEvents:RegisterEvent("PLAYER_LOGIN")

frameEvents:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            QFXMythicTalentsDB = QFXMythicTalentsDB or {}
            QFXMythicTalentsDB.loadouts = QFXMythicTalentsDB.loadouts or {}
            pluginSuspended = false
            QFXMythicTalentsDB.enabled = nil
            percentagesEnabled = QFXMythicTalentsDB.showPercentages ~= false
            local savedDifficulty = QFXMythicTalentsDB.lastRaidDifficultyID
            if savedDifficulty == RAID_DIFFICULTY_HEROIC or savedDifficulty == RAID_DIFFICULTY_MYTHIC then
                selectedRaidDifficultyID = savedDifficulty
            end
        elseif arg1 == "QFXTalentData" or arg1 == "QFXMythicTalents_Data" then
            -- 数据后端加载完成，下一次访问时重新校验并填充缓存。
            unifiedBackendValid = false
        elseif arg1 == "Blizzard_PlayerSpells" then
            InitializeBlizzardUI()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        frameEvents:UnregisterEvent("PLAYER_LOGIN")
        SLASH_QFXMYTHICTALENTS1 = "/qmt"
        SLASH_QFXMYTHICTALENTS2 = "/qfxmt"
        SlashCmdList.QFXMYTHICTALENTS = function(message)
            local command = strtrim(string.lower(message or ""))
            if command == "off" or command == "disable" then
                SuspendAddon()
                print("|cff00ccffQFX Talent Recommendations|r disabled for this session; use /qmt to re-enable.")
                return
            end
            OpenTalentFrame()
        end

        SLASH_QFXMYTHICTALENTSDATA1 = "/qmtdb"
        SlashCmdList.QFXMYTHICTALENTSDATA = function()
            local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
            local function Loaded(name)
                return isLoaded and not not isLoaded(name) or false
            end
            print(("|cff00ccffQFX Talent DB V2|r ready=%s, base=%s, M+=%s, heroic=%s, mythic=%s, version=%s, raidDifficulty=%s, error=%s"):format(
                tostring(API:IsDataReady(currentSpecID)),
                tostring(Loaded("QFXTalentData")),
                tostring(Loaded("QFXTalentData_MythicPlus")),
                tostring(Loaded("QFXTalentData_RaidHeroic")),
                tostring(Loaded("QFXTalentData_RaidMythic")),
                tostring(API:GetDataVersion()),
                tostring(RaidDifficultyName(selectedRaidDifficultyID)),
                tostring(API.lastDataError or _G.QFXTalentDataLoadError or _G.QFXMythicTalentsDataLoadError)
            ))
        end

        SLASH_QFXMYTHICTALENTSSTATE1 = "/qmtstate"
        SlashCmdList.QFXMYTHICTALENTSSTATE = function()
            local backend = GetUnifiedDataAPI()
            local active = not pluginSuspended
                and IsTalentFrameVisible()
                and sidePanel and sidePanel:IsShown()
            print(("|cff00ccffQFX sleep state|r suspended=%s, percentages=%s, active=%s, events=%s, refresh=%s, statistics=%s, recovery=%s, dataSpec=%s"):format(
                tostring(pluginSuspended),
                tostring(percentagesEnabled),
                tostring(not not active),
                tostring(operationalEventsEnabled),
                tostring(refreshTimer ~= nil),
                tostring(statisticsDebounceTimer ~= nil or pendingStatisticsKey ~= nil),
                tostring(panelRecoveryTimer ~= nil or panelPositionTimer ~= nil),
                tostring(backend and backend.activeSpecID or nil)
            ))
        end

        InitializeBlizzardUI()
        print("|cff00ccffQFX Talent Recommendations|r：" .. T.command)
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= "player" then
        return
    end

    if event == "INSPECT_READY" then
        if PlayerSpellsFrame and PlayerSpellsFrame.IsInspecting
            and PlayerSpellsFrame:IsInspecting()
        then
            currentSpecID = CurrentSpecID()
            currentStats = nil
            currentStatsKey = nil
            currentStates = nil
            currentStatesDirty = true
            currentStatesContextKey = nil
            treeContext = nil
            CancelStatisticsBuild()
            if IsTalentFrameVisible() then
                EnsureDataLoaded(currentSpecID, CurrentClassToken())
                ScheduleRefresh(0.03, true)
            end
        end
        return
    end

    local nativeTransitionEvent = event == "TRAIT_CONFIG_CREATED"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "TRAIT_CONFIG_LIST_UPDATED"
        or event == "CONFIG_COMMIT_FAILED"
        or event == "ACTIVE_COMBAT_CONFIG_CHANGED"
        or event == "SELECTED_LOADOUT_CHANGED"
    if nativeTransitionEvent then
        currentStatesDirty = true
        if IsTalentFrameVisible() then
            RecoverPanelAfterNativeTransition()
        else
            currentStates = nil
            currentStatesContextKey = nil
            CancelStatisticsBuild()
        end
        return
    end

    local traitStateEvent = event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_NODE_CHANGED"
        or event == "TRAIT_NODE_CHANGED_PARTIAL"
        or event == "TRAIT_NODE_ENTRY_UPDATED"
        or event == "TRAIT_SUB_TREE_CHANGED"
    if traitStateEvent then
        currentStatesDirty = true
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        currentSpecID = CurrentSpecID()
        currentStats = nil
        currentStatsKey = nil
        currentStates = nil
        currentStatesDirty = true
        currentStatesContextKey = nil
        treeContext = nil
        CancelStatisticsBuild()
        if IsTalentFrameVisible() then
            EnsureDataLoaded(currentSpecID, CurrentClassToken())
            AutoSelectContent()
            ScheduleRefresh(0.15)
        end
    elseif event == "PLAYER_TALENT_UPDATE" then
        if IsTalentFrameVisible() then
            ScheduleRefresh(0.05)
        end
    elseif event == "ENCOUNTER_START" then
        local raidID = DetectRaid()
        if not FindBoss(raidID, arg1) then
            local raid = FindRaidByBoss(arg1)
            raidID = raid and raid.id or nil
        end
        if raidID and FindBoss(raidID, arg1) then
            selectedMode = "raid"
            selectedRaidID = raidID
            selectedBossID = arg1
            selectedRaidDifficultyID = DetectRaidDifficulty() or selectedRaidDifficultyID
            if RebuildContentButtons then
                RebuildContentButtons()
            end
            SelectBoss(raidID, arg1, true)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "CHALLENGE_MODE_START" then
        if IsTalentFrameVisible() then
            AutoSelectContent()
        end
    elseif IsTalentFrameVisible() then
        ScheduleRefresh(0.03)
    end
end)
