local root = arg[1] or "."
dofile(root .. "/QFXTalentData/Core.lua")
dofile(root .. "/QFXTalentData/Common.lua")
dofile(root .. "/QFXTalentData/Schemas.lua")
local api = QFXTalentData
local folders = {
    mythicplus = "QFXTalentData_MythicPlus",
    raidHeroic = "QFXTalentData_RaidHeroic",
    raidMythic = "QFXTalentData_RaidMythic",
}
for kind, folder in pairs(folders) do
    dofile(root .. "/" .. folder .. "/Data.lua")
    local module = assert(api.contentModules[kind])
    local combinations, dual, single, full = 0, 0, 0, 0
    for specID, values in pairs(module.records) do
        for index = 1, #values, module.stride do
            local key1, key2 = values[index], values[index + 1]
            local function data(heroIndex)
                if kind == "mythicplus" then return api:GetDungeonData(key1, specID, heroIndex) end
                return api:GetRaidData(key1, key2, kind == "raidHeroic" and 4 or 5, specID, heroIndex)
            end
            local function text(heroIndex)
                if kind == "mythicplus" then return api:GetRecommendedDungeonTalent(key1, specID, heroIndex) end
                return api:GetRecommendedRaidTalent(key1, key2, kind == "raidHeroic" and 4 or 5, specID, heroIndex)
            end
            local record = assert(data(1))
            assert(record.sourceRankLimit == 50 and record.sampleCount > 0 and record.sampleCount <= 50)
            local heroes = assert(record.heroRecommendations)
            local total, available, previous = 0, 0, 51
            for heroIndex, hero in ipairs(heroes) do
                assert(hero.sampleCount <= previous)
                previous = hero.sampleCount
                total = total + hero.sampleCount
                if hero.sampleCount > 0 then
                    available = available + 1
                    assert(hero.available and text(heroIndex) and data(heroIndex))
                    assert(data(heroIndex).sampleCount == record.sampleCount)
                else
                    assert(not hero.available and text(heroIndex) == nil and data(heroIndex) == nil)
                end
            end
            assert(total == record.sampleCount and available >= 1 and available <= 2)
            if available == 2 then dual = dual + 1 else single = single + 1 end
            if record.sampleCount == 50 then full = full + 1 end
            combinations = combinations + 1
        end
    end
    print(string.format("%s: combinations=%d dual=%d single=%d full50=%d", kind, combinations, dual, single, full))
end
print("All hero recommendation records passed runtime API validation")
