local file = assert(io.open(assert(arg[1], "Core.lua path is required"), "rb"))
local source = file:read("*a")
file:close()
local stop = assert(source:find("local frameEvents = CreateFrame", 1, true))
source = source:sub(1, stop - 1)
C_AddOns = {GetAddOnMetadata = function() return "0.9.0" end}
local record = {heroRecommendations = {{available = true}, {available = true}}}
local selected
QFXTalentData = {
    apiVersion = 2,
    manifest = {minDisplayVersion = "0.9.0"},
    GetDungeonData = function(_, dungeonID, specID, heroIndex)
        assert(dungeonID == 1 and specID == 250)
        selected = heroIndex
        return record
    end,
    GetRaidData = function(_, raidID, bossID, difficultyID, specID, heroIndex)
        assert(raidID == 10 and bossID == 100 and difficultyID == 4 and specID == 250)
        selected = heroIndex
        return record
    end,
    GetRecommendedDungeonTalent = function(_, dungeonID, specID, heroIndex)
        assert(dungeonID == 1 and specID == 250)
        return "MPLUS" .. heroIndex
    end,
    GetRecommendedRaidTalent = function(_, raidID, bossID, difficultyID, specID, heroIndex)
        assert(raidID == 10 and bossID == 100 and difficultyID == 4 and specID == 250)
        return "RAID" .. heroIndex
    end,
}
assert((loadstring or load)(source))("QFXTalents", {})
assert(QFXTalents:GetDungeonData(250,1,2) == record and selected == 2)
assert(QFXTalents:GetRaidData(250,10,100,4,2) == record and selected == 2)
assert(QFXTalents:GetRecommendedDungeonTalent(250,1,2) == "MPLUS2")
assert(QFXTalents:GetRecommendedRaidTalent(250,10,100,4,2) == "RAID2")
record = {sampleCount = 10}
assert(QFXTalents:GetDungeonData(250,1,2) == nil)
assert(QFXTalents:GetRaidData(250,10,100,4,2) == nil)
assert(QFXTalents:GetRecommendedDungeonTalent(250,1,2) == nil)
assert(QFXTalents:GetRecommendedRaidTalent(250,10,100,4,2) == nil)
assert(QFXTalents:GetRecommendedDungeonTalent(250,1,1) == "MPLUS1")
assert(QFXTalents:GetRecommendedRaidTalent(250,10,100,4,1) == "RAID1")
print("Hero API forwarding and old-database no-fallback tests passed")
