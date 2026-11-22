-- Small helpers for reading game objects through UE4SS. Fields differ between objects and versions, so reads that
-- may fail go through GameObject.read and the caller decides what a missing value means.
local GameObject = {}

-- Value of read(), or nil if it raises an error (a missing or unreadable field).
function GameObject.read(read)
    local ok, value = pcall(read)
    if ok then
        return value
    end
    return nil
end

-- True for an object that exists and is still valid (not nil, not destroyed).
function GameObject.usable(object)
    return object ~= nil and GameObject.read(function() return object:IsValid() end) == true
end

-- Object name without class and path: "Class /Game/Path/da_x.da_x" -> "da_x".
function GameObject.shortName(object)
    return object:GetFullName():match("([^%.:]+)$")
end

-- TArray as a Lua list, empty for nil. The elements are collected first and handled afterwards: code that may fail
-- must not run inside the engine's ForEach.
function GameObject.listOf(array)
    local list = {}
    if array ~= nil then
        array:ForEach(function(_, element) list[#list + 1] = element:get() end)
    end
    return list
end

-- True if the object with ownerAddress is among the first maxDepth outers of object (the object hangs below it,
-- directly or through sub-objects and components).
function GameObject.isBelow(object, ownerAddress, maxDepth)
    local outer = GameObject.read(function() return object:GetOuter() end)
    for _ = 1, maxDepth do
        if not GameObject.usable(outer) then
            return false
        end
        if outer:GetAddress() == ownerAddress then
            return true
        end
        outer = GameObject.read(function() return outer:GetOuter() end)
    end
    return false
end

-- Names of the tags in a gameplay tag container (FGameplayTagContainer), without empty ones.
function GameObject.tagNames(container)
    local names = {}
    for _, tag in ipairs(GameObject.listOf(container.GameplayTags)) do
        local name = tag.TagName:ToString()
        if name ~= nil and name ~= "" and name ~= "None" then
            names[#names + 1] = name
        end
    end
    return names
end

return GameObject
