-- Combine the generated compact specialization loaders into one data-addon
-- source file. Only the selected specialization's loader is executed at runtime.

local outputPath = "../QFXTalentData/SpecLoaders.lua"
local specIDs = {
    62, 63, 64, 65, 66, 70, 71, 72, 73,
    102, 103, 104, 105,
    250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261,
    262, 263, 264, 265, 266, 267, 268, 269, 270,
    577, 581, 1467, 1468, 1473, 1480,
}

local output, reason = io.open(outputPath, "wb")
assert(output, reason)
output:write("-- Generated compact specialization loaders. Do not edit manually.\n")

for _, specID in ipairs(specIDs) do
    local path = ("../QFXTalentData_Spec_%d/Data.lua"):format(specID)
    local input, inputReason = io.open(path, "rb")
    assert(input, inputReason)
    local content = input:read("*a")
    input:close()
    output:write("\n-- Specialization ", tostring(specID), "\n")
    output:write(content)
    if content:sub(-1) ~= "\n" then
        output:write("\n")
    end
end

output:close()
print(("Combined %d specialization loaders into %s."):format(#specIDs, outputPath))
