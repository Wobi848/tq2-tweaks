-- The game's list of data assets (CookedData/JsonMetaDataCache.json: { "pathsByClass": { "<class>": { "paths":
-- [ ... ] } } }), read as text so no JSON parser is needed.
local AssetList = {}

-- Every asset path of every class, as { class, path }.
function AssetList.all(cacheText)
    local assets = {}
    for className, block in cacheText:gmatch('"([^"]+)"%s*:%s*{%s*"paths"%s*:%s*%[(.-)%]') do
        for path in block:gmatch('"([^"]+)"') do
            assets[#assets + 1] = { class = className, path = path }
        end
    end
    return assets
end

-- Asset paths of one class.
function AssetList.pathsOfClass(cacheText, className)
    local paths = {}
    for _, asset in ipairs(AssetList.all(cacheText)) do
        if asset.class == className then
            paths[#paths + 1] = asset.path
        end
    end
    return paths
end

-- "/JsonData/TQ2/Creatures/da_cr_x" -> "/JsonData/TQ2/Creatures/da_cr_x.da_cr_x" (package path plus object name), the
-- form LoadAsset takes.
function AssetList.objectPath(assetPath)
    return assetPath .. "." .. assetPath:match("([^/]+)$")
end

return AssetList
