local KarmaLoot, ns = ...
local decayConfirm = false

-- Checks player rank in their guild to prevent usage of certain commands
local function isPlayerOfficer()
    if ns.currentPlayer.rankIx > 1 then
        ns.klSay("You are not an Officer.")
        return false
    else
        return true
    end
end

function ns.isPlayerLeader()
    if UnitIsGroupLeader("Player", LE_PARTY_CATEGORY_HOME) then
        return true
    else
        return false
    end
end

-- The /kroll command. Causes the player to perform an infused roll.
function ns.kRoll()
    ns.loadMemberKarma(false)
    if ns.currentPlayer.karma == 0 then
        ns.klSay("You have no Karma to use.")
    else
        RandomRoll(ns.currentPlayer.karma, 100 + ns.currentPlayer.karma)
    end
end

-- Used by the normal roll button to do a standard 1-100 roll
function ns.normalRoll()
    RandomRoll(1, 100)
end

-- Used by the pass button to pass on loot
function ns.passOnLoot()
    C_ChatInfo.SendAddonMessage("KarmaLoot", "pass:" .. ns.currentPlayer.name)
end

-- Used to display a message when a player passes. (Not currently working.)
function ns.displayPassMsg(playerName)
    playerName = ns.strSplit(playerName,"-")
    playerName = playerName[1]
    local number = math.random(1)
    if number == 1 then
        print("|cFFFFFF00" .. playerName .. " passes.|cFFFFFFFF")
    elseif number == 2 then
        print("|cFFFFFF00" .. playerName .. " says \"hard pass\".|cFFFFFFFF")
    elseif number == 3 then
        print("|cFFFFFF00" .. playerName .. " probably hit the wrong button.|cFFFFFFFF")
    elseif number == 4 then
        print("|cFFFFFF00" .. playerName .. " is clearly already in full BiS.|cFFFFFFFF")
    elseif number == 5 then
        print("|cFFFFFF00" .. playerName .. " would rather someone else gets it.|cFFFFFFFF")
    end
end

-- Prints most chat messages from the addon
function ns.klSay(msg)
    print("|cFF00FF96kl |cFFFFFFFF " .. msg)
end

-- Officers only. The /kl earn command. Syntax is /kl earn {amount}. The amount specified will be awarded to everyone in the caller's raid group.
function ns.klEarn(amount)
    if not isPlayerOfficer then
        return
    end
    ns.loadMemberKarma(false)
    local sanitizedAmt = math.floor(tonumber(amount))

    local successFullGrants = 0
    for rI = 1, 40, 1 do
        local name = GetRaidRosterInfo(rI)
        if name then
            local earnIx = ns.findPlayerRosterIx(name)
            if earnIx > -1 then
                ns.addKarma(earnIx, sanitizedAmt)
                successFullGrants = successFullGrants + 1
            end
        end
    end

    if successFullGrants > 0 then
        SendChatMessage(
        "All Raid members in " .. ns.currentPlayer.name .. "'s raid have earned " .. tostring(sanitizedAmt) .. " Karma",
        "RAID"
        )
    else
        ns.klSay("Something went wrong, no one got granted anything. Are you even in a raid?")
    end
end

-- Officers only. The /kl set command. Syntax: /kl set {playerName} {amount} -- Administrative fixing command that hard sets a player's karma to a specific value.
function ns.klSet(msg)
    if not isPlayerOfficer then
        return
    end
    ns.loadMemberKarma(false)

    local parts = ns.strSplit(msg) -- special split that allows for special characters in player names
    local amtNum = tonumber(parts[3])
    local amount = math.floor(amtNum)
    local playerIndex = ns.findPlayerRosterIx(parts[2])

    ns.setKarma(playerIndex, amount)
    local chatMsg = "[KarmaLoot]: " .. parts[2] .. "'s Karma has been set to " .. amount .. " by " .. ns.currentPlayer.name
    SendChatMessage(chatMsg, "RAID")
end

-- Officers only. The /kl adjust command. Syntax: /kl adjust {playerName} {amount} -- Adjusts a players Karma by a specific delta, positive or negative.
function ns.klAdjust(msg)
    if not isPlayerOfficer() then
        return
    end
    ns.loadMemberKarma(false)

    local parts = ns.strSplit(msg)
    local player = parts[2] .. "-" .. GetRealmName()
    player = player:lower()
    local amount = math.floor(tonumber(parts[3]))
    local nameFound = false
    for i = 1, GetNumGuildMembers() do
        member = GetGuildRosterInfo(i)
        member = member:lower()
        if player == member then
            nameFound = true
            local oldKarma = ns.getKarma(i)
            local adjustedKarma = ns.getKarma(i) + amount
            ns.setKarma(i, adjustedKarma)
            ns.klSay("Adjusted Karma for " .. GetGuildRosterInfo(i) .. ". |cFF00FF96Old value:|r " .. oldKarma .. " | |cFF00FF96New value:|r " .. adjustedKarma .. ".")
            return
        end
    end
    if nameFound == false then
        ns.klSay("It seems like that name wasn't found in the guild roster! This error may be due to a non-guildie or incorrect spelling. You can shift-click a name in the guild roster to add it to your command if you need to.")
    end
end


-- For officers and raid leaders. The /kl win command. Syntax: /kl win {playerName}. To be called when a player has won an item after performing an infused roll.
function ns.klWin(msg)
    if not isPlayerLeader and not isPlayerOfficer then
        return
    end
    if (not msg) then
        local targetName = GetUnitName("playertarget")
        if targetName == nil then
            ns.klSay("No name specified or target selected!")
            return
        end
        msg = targetName
    end
    ns.loadMemberKarma(false)
    local winnerIndex = ns.findPlayerRosterIx(msg)
    if winnerIndex == -1 then
        ns.klSay("Could not find player by name: " .. msg)
        return
    end

    local currentK = ns.getKarma(winnerIndex)
    --print(tostring(pIx) .. ' -> ' ..tostring(currentK));

    if currentK == 0 then
        ns.klSay("Could not reduce Karma, " .. msg .. " Karma is already at zero.")
        return
    end

    local newK = math.floor(currentK / 2)
    ns.setKarma(winnerIndex, newK)
    local chatMsg = msg .. " won the item. Karma has been halved. (" .. newK .. ")"
    SendChatMessage(chatMsg, "RAID")
end

-- Gets the version of everyone in the raid and tells you who's slacking
function ns.klVersion()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers(), 1 do
            member = GetRaidRosterInfo(i)
            table.insert(ns.allRaidersTable, member)
            table.sort(ns.allRaidersTable)
        end
        C_ChatInfo.SendAddonMessage("KarmaLoot", "Version?", "RAID")
        C_Timer.After(1,function()
        if table.concat(ns.allRaidersTable) == '' then
            ns.klSay("Everyone is up to date!")
        else
            for k, v in pairs(ns.allRaidersTable) do
                ns.allRaidersTable[k] = ns.prependClassColor(v)
            end
            ns.klSay("The following players are out of date or do not have the addon installed:\n" .. table.concat(ns.allRaidersTable, ', '))
            ns.allRaidersTable = {}
        end
        end)
    else
        ns.klSay("You need to be in a raid to use this command.")
    end
end

function ns.klBackups()
    local backups = {}
    local length = 0
    for k1, v1 in pairs(KL_Karma_Backup) do
        for k, _ in pairs(v1) do
            table.insert(backups, k)
        end
    end

    for _, _ in pairs(backups) do
        length = length + 1
    end
    for i = length, 5 + 1, -1 do
        backups[i] = nil
    end
    ns.klSay("Latest 5 backup dates: " .. table.concat(backups, ", ") .. "\nIf you need to restore a backup, use the |cffffa500'/klrestore DDMMYY'|r command.")
end

-- The /kl command. Primary CLI entry point. Serves several sub commands.
function ns.slashKl(msg)
    if not msg or msg == "" then
        print("|cFF00FF96KarmaLoot! |cFFAAAAAAUse /KL ? to list options.")
    end
    if msg == "roll" then
        ns.kRoll()
    end
    if msg == "?" then
        print("|cFF00FF96KarmaLoot!|cFFAAAAAA Here's a list of options:")
        print("|cFF00FF96/kl|cFFFFFFFF roll |cFFAAAAAA - perform an infused roll.")
        print("|cFF00FF96/kl|cFFFFFFFF toggle |cFFAAAAAA - Show/Hide the Karma leaderboard.")
        print("|cFF00FF96/kl|cFFFFFFFF check |cFFAAAAAA - Check your own Karma status.")
        print("|cFF00FF96/kl|cFFFFFFFF -v |cFFAAAAAA - Check everyones versions against yours.")
        print("|cFFFFFFFF - Officer commands: ")
        print("|cFF00FF96/kl|cFFFFFFFF earn <Amount>|cFFAAAAAA - Reward the entire raid some Karma.")
        print("|cFF00FF96/kl|cFFFFFFFF adjust <Player> <Amount>|cFFAAAAAA - Adjust a players Karma by a specific amount.")
        print("|cFF00FF96/kl|cFFFFFFFF set <Player> <Amount>|cFFAAAAAA - Set a player to a specific amount.")
        print("|cFF00FF96/kl|cFFFFFFFF win [<Player> or Current Target]|cFFAAAAAA - Reward a player an item, halving their Karma.")
        print("|cFF00FF96/kl|cFFFFFFFF [ITEM_LINK_HERE]|cFFAAAAAA - Prompts the raid to roll on an item and unhides their KL GUI.")
        print("|cFF00FF96/kl|cFFFFFFFF decay|cFFAAAAAA - Reduce the entire guilds Karma by 80%.")
		print("|cFF00FF96/kl|cFFFFFFFF backups|cFFAAAAAA - Prints a list of backup dates to be used for easy karma restoration.")
    end
    if msg == "check" then
        ns.loadMemberKarma(false)
        ns.klSay("You currently have " .. tostring(ns.currentPlayer.karma) .. " karma to infuse.")
    end
    if msg == "refresh" then
        ns.loadMemberKarma(true)
    end

    if msg == "hide" or msg == "show" then
        ns.klSay("The show/hide commands are now defunct. Please utilize |cFF00FF96/kl toggle|r instead. You can also left-click the minimap button to perform the same function.")
    end

    if msg == "toggle" then
        ns.KarmaLoot:updateFrame(true)
    end

    local parts = ns.strSplit(msg)
    local cmd = parts[1]

    if cmd == "earn" then
        ns.klEarn(parts[2])
    end

    if cmd == "set" then
        ns.klSet(msg)
    end

    if cmd == "adjust" then
        ns.klAdjust(msg)
    end

    if cmd == "win" then
        ns.klWin(parts[2])
    end

    local itemId = GetItemInfoInstant(msg)
    if itemId then
        ns.klItem(msg)
    end

    if cmd == "close" then
        ns.klClose()
    end

	-- Check versions of other members in your current raid.
    if cmd == "-v" then
        ns.klVersion()
    end

	-- Check dates for latest backups. Useful for backup restoration command.
	if cmd == "backups" then
        ns.klBackups()
	end

    if cmd == "decay" then
        ns.klDecay(false)
    end
end

-- Takes a date argument and finds the respective karma backup, then restores it.
function ns.klRestore(msg)
    if not isPlayerOfficer then
        return
    end
	local index1 = 0
	local index2 = 0
    if msg then
		for k, v in pairs(KL_Karma_Backup) do
			for k2, v2 in pairs(v) do
				if k2 == msg then
					index1, index2 = k, k2
					break
				end
			end
		end
		for k, v in pairs(KL_Karma_Backup[index1][index2]) do
			local name, officerNote = v:match("([^,]+),([^,]+)")
			local memberIndex = 0
			for i = 1, GetNumGuildMembers(), 1 do
				if name == GetGuildRosterInfo(i) then
					memberIndex = i
				end
			end
			GuildRosterSetOfficerNote(memberIndex, officerNote)
		end
	end
end

function ns.klDecay(command)
    local guildmaster = IsGuildLeader()
    print(guildmaster)
    if not guildmaster then
        return
    end
    if command then
        if not guildmaster then
            return
        end
        if not decayConfirm then
            ns.klSay("Are you sure you want to reduce everyone's Karma by 80%? Type the command in again once more to confirm.")
        end

        if decayConfirm then
            for i = 1, GetNumGuildMembers(), 1 do
                local member = GetGuildRosterInfo(i)
                if ns.getKarma(i) > 0 then
                    decayedKarma = math.floor(ns.getKarma(i) * 0.2)
                    GuildRosterSetOfficerNote(i, "k:" .. decayedKarma)
                end
            end
            ns.klSay("Decay complete! If something went horribly wrong, please revert to a backup.")
            decayConfirm = false
        end
        decayConfirm = true
    elseif not command then
        if not guildmaster then
            return
        end
        for i = 1, GetNumGuildMembers(), 1 do
            local member = GetGuildRosterInfo(i)
            if ns.getKarma(i) > 0 then
                decayedKarma = math.floor(ns.getKarma(i) * 0.2)
                GuildRosterSetOfficerNote(i, "k:" .. decayedKarma)
            end
        end
        ns.klSay("Decay complete! If something went horribly wrong, please revert to a backup.")
    end
end


SLASH_KLENTRY1, SLASH_KLENTRY2 = "/kl", "/karmaloot"
SLASH_KLROLL1, SLASH_KLROLL2 = "/kroll", "/klroll"
SLASH_KLRESTORE1 = "/klrestore"

SlashCmdList["KLENTRY"] = ns.slashKl
SlashCmdList["KLROLL"] = ns.kRoll
SlashCmdList["KLRESTORE"] = ns.klRestore
