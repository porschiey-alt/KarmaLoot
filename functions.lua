local KarmaLoot, ns = ...

-- Splits strings lol
function ns.strSplit(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function ns.canOpenRolls()
    local result = ns.getRaidRankStuff(UnitName("Player"))
    if result then
        result = ns.strSplit(result,",")
        if result[2] == "true" then
            return true
        else
            return false
        end
    end
end

-- Returns whether a player is raid lead, assistant, and master looter
function ns.getRaidRankStuff(name)
    for i = 1, GetNumGroupMembers(), 1 do
        local member, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
        if member == name then
            return rank .. "," .. tostring(isML)
        end
    end
end

-- Get class color from name and return the hex code to change the color of said name.
function ns.prependClassColor(playerName)
	local playerClass = UnitClass(playerName)
	local classColor = "|cff" .. classColors[playerClass:lower()].hex .. playerName .. "|r"
	return classColor
end
