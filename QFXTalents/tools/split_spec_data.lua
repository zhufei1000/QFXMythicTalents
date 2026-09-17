-- Build one load-on-demand data addon per specialization from the generated
-- class providers. Run from the QFXTalents core addon directory.

local sourceRoot = "../QFXTalentData"
local outputPrefix = "../QFXTalentData_Spec_"
local classTokens = {
    "DEATHKNIGHT",
    "DEMONHUNTER",
    "DRUID",
    "EVOKER",
    "HUNTER",
    "MAGE",
    "MONK",
    "PALADIN",
    "PRIEST",
    "ROGUE",
    "SHAMAN",
    "WARLOCK",
    "WARRIOR",
}

local function SortedKeys(value)
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then
            return left < right
        end
        return type(left) == "number"
    end)
    return keys
end

local function IsArray(value)
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false, 0
        end
        count = count + 1
        if key > maximum then
            maximum = key
        end
    end
    return count == maximum, maximum
end

local function Serialize(value, depth)
    local valueType = type(value)
    if valueType == "nil" then
        return "nil"
    elseif valueType == "boolean" or valueType == "number" then
        return tostring(value)
    elseif valueType == "string" then
        return string.format("%q", value)
    elseif valueType ~= "table" then
        error("unsupported value type: " .. valueType)
    end

    depth = depth or 0
    local indent = string.rep("  ", depth)
    local childIndent = string.rep("  ", depth + 1)
    local parts = { "{\n" }
    local array, length = IsArray(value)
    if array then
        for index = 1, length do
            parts[#parts + 1] = childIndent
            parts[#parts + 1] = Serialize(value[index], depth + 1)
            parts[#parts + 1] = ",\n"
        end
    else
        for _, key in ipairs(SortedKeys(value)) do
            parts[#parts + 1] = childIndent
            parts[#parts + 1] = "["
            parts[#parts + 1] = Serialize(key, 0)
            parts[#parts + 1] = "]="
            parts[#parts + 1] = Serialize(value[key], depth + 1)
            parts[#parts + 1] = ",\n"
        end
    end
    parts[#parts + 1] = indent
    parts[#parts + 1] = "}"
    return table.concat(parts)
end

local function CompactSpec(specData)
    for _, recommendation in pairs(specData.dungeons or {}) do
        recommendation.selection = nil
    end
    for _, raidData in pairs(specData.raids or {}) do
        for _, bossData in pairs(raidData.bosses or {}) do
            for _, recommendation in pairs(bossData.difficulties or {}) do
                recommendation.selection = nil
            end
        end
    end
end

local function WriteFile(path, text)
    local file, reason = io.open(path, "wb")
    assert(file, reason)
    file:write(text)
    file:close()
end

local generated = 0
for _, classToken in ipairs(classTokens) do
    _G.QFXTalentData_Loaders = {}
    assert(loadfile(sourceRoot .. "/Classes/" .. classToken .. ".lua"))()
    local classLoader = assert(_G.QFXTalentData_Loaders[classToken], "missing class loader " .. classToken)
    local provider = classLoader()

    for specID, specData in pairs(provider.specs) do
        CompactSpec(specData)
        local specProvider = {
            apiVersion = provider.apiVersion,
            dataVersion = provider.dataVersion,
            classToken = provider.classToken,
            specs = {
                [specID] = specData,
            },
        }

        local addonName = "QFXTalentData_Spec_" .. specID
        local outputRoot = outputPrefix .. specID
        local luaText = table.concat({
            "local LOADERS=_G.QFXTalentData_Loaders\n",
            "if not LOADERS then return end\n",
            "LOADERS[", tostring(specID), "]=function()\n",
            "  return ", Serialize(specProvider, 1), "\n",
            "end\n",
        })
        local tocText = table.concat({
            "## Interface: 120007\n",
            "## Version: ", tostring(provider.dataVersion), "\n",
            "## Title: |cff00ccffQFX Talent Data|r - Spec ", tostring(specID), "\n",
            "## Notes: Load-on-demand talent samples for specialization ", tostring(specID), ".\n",
            "## Author: QFX\n",
            "## X-Category: Data\n",
            "## X-QFX-Data-API: 1\n",
            "## X-QFX-Data-Version: ", tostring(provider.dataVersion), "\n",
            "## X-QFX-Spec-ID: ", tostring(specID), "\n",
            "## LoadOnDemand: 1\n\n",
            "Data.lua\n",
        })

        WriteFile(outputRoot .. "/Data.lua", luaText)
        WriteFile(outputRoot .. "/" .. addonName .. ".toc", tocText)
        generated = generated + 1
    end
end

print(("Generated %d specialization data addons."):format(generated))
