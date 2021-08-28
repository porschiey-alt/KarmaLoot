local KarmaLoot, ns = ...
local version = GetAddOnMetadata("KarmaLoot", "Version")
local memberKarma = {}
local currentRaidKarma = {}
local memberRowHeight = 12
local defaultWindowHeight = 70
local karmaFrameWidth = 100
local playerName = UnitName("player") .. "-" .. GetRealmName()
local initialized = false
local frameReady = false
local leaderBoardReady = false
local frameHidden = false
local mmHidden = false
local tgtConfirmation = false
local rollMsg = "KL: Please roll on "
local rollsOpen = false
local highestRoll = 0
local highestRoller = ""
local rollers = {}
local deadlock = false
local item
local success = C_ChatInfo.RegisterAddonMessagePrefix("KarmaLoot") -- Addon name.
local backupData = {}
local restoreConfirm = false
local rollFrame = CreateFrame("Frame",nil,UIParent)
local wasKarmaUsed = false
local lastKarmaUser = ""
local numOfBackups = 5
ns.currentPlayer = {}
ns.allRaidersTable = {}

--Fix for current bug where right click doesn't work anymore after using the MasterLooterFrame
hooksecurefunc(MasterLooterFrame, 'Hide', function(self) self:ClearAllPoints() end)

-- RGB and HEX colors for each class through WotLK, because that's all that matters
classColors = {
    deathknight = {r = .77, g = .12, b = .23, hex = "C41F3B"},
    druid = {r = 1, g = .49, b = .04, hex = "FF7D0A"},
    hunter = {r = .67, g = .83, b = .45, hex = "ABD473"},
    mage = {r = .41, g = .80, b = .94, hex = "69CCF0"},
    paladin = {r = .96, g = .55, b = .73, hex = "F58CBA"},
    priest = {r = 1, g = 1, b = 1, hex = "FFFFFF"},
    rogue = {r = 1, g = .96, b = .41, hex = "FFF569"},
    shaman = {r = 0, g = .44, b = .87, hex = "0070DE"},
    warlock = {r = .58, g = .51, b = .79, hex = "9482C9"},
    warrior = {r = .78, g = .61, b = .43, hex = "C79C6E"}
}

qualityColors = {
    poor = {r = .62, g = .62, b = .62, hex = "9D9D9D"},
    common = {r = 1, g = 1, b = 1, hex = "FFFFFF"},
    uncommon = {r = .12, g = 1, b = 0, hex = "1EFF00"},
    rare = {r = 0, g = .44, b = .87, hex = "0070DD"},
    epic = {r = .64, g = .21, b = .93, hex = "A335EE"},
    legendary = {r = 1, g = .5, b = 0, hex = "FF8000"},
    artifact = {r = .9, g = .8, b = .5, hex = "E6CC80"},
    heirloom = {r = 0, g = .8, b = 1, hex = "00CCFF"},
}

KL_Karma_Backup = {}
KL_Settings = {
    MinimapPos = 45,
    FramePosRelativePoint = "CENTER",
    FramePosRelativeParent = "UIParent",
    FramePosX = 0,
    FramePosY = 0,
    displayPassMsg = true,
}

-- low level lua utils --
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

-- Find index of each guild member
function ns.findPlayerRosterIx(lookup)
	if lookup then
		lookup = lookup .. "-" .. GetRealmName()
		local memberCount = GetNumGuildMembers()
		for mi = 1, memberCount, 1 do
			local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(mi)
			if lookup:lower() == name:lower() then
				return mi
			end
		end
		return -1
	end
end

local function broadcastRefresh()
    C_ChatInfo.SendAddonMessage("KarmaLoot", "refresh")
end

-- Parses Officer note string into a number (Karma)
local function parseKarma(note)
    -- phase 1, phase 2,
    if note then
        if note == "" then
            return 0
        else
            local amount = string.match(note, "^k:(%d+)$")
            if amount then
                return tonumber(amount)
            end
        end
    end
end

-- Sets and saves a player's karma to specific amount.
function ns.setKarma(rosterIndex, amount)
    GuildRosterSetOfficerNote(rosterIndex, "k:" .. tostring(amount))
    broadcastRefresh()
end

-- Gets a player's saved karma from the guild roster.
function ns.getKarma(rosterIndex)
	if(rosterIndex) then
		local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(rosterIndex)
		return parseKarma(officerNote)
	end
end

-- Adds the amount specified to the existing pool of Karma for the player.
function ns.addKarma(rosterIndex, amount)
    local current = ns.getKarma(rosterIndex)
    local newTotal = current + amount
    ns.setKarma(rosterIndex, newTotal)
end

-- Loops through the current guild roster and finds players who need their officer note initialized.
local function initKarmaNotes(rosterIndex, rank, note)
    local initialized = 0
    for k = 1, tablelength(memberKarma), 1 do
        local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(k)
        if officerNote then
            if officerNote == "" then
                ns.setKarma(k, 0)
                initialized = initialized + 1
            end
        end
    end

    if initialized > 0 then
        print("Initialzed " .. initialized .. " officer notes.")
    end
end

-- Loads the guild roster and formulates current Karma standings.
function ns.loadMemberKarma(showMsg)
    local memberCount = GetNumGuildMembers()
    for k = 1, memberCount, 1 do
        local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(k)
        local member = {name = name, karma = parseKarma(officerNote), rankIx = rankIndex}
        if (name == playerName) then
            ns.currentPlayer = member
        end

        table.insert(memberKarma, member)
    end

    if (ns.currentPlayer.rankIx ~= nil and ns.currentPlayer.rankIx < 2) then
        initKarmaNotes()
    end

    if (showMsg) then
        ns.klSay("Refreshed status for " .. memberCount .. " guild members for " .. ns.currentPlayer.name)
    end
end

-- Updates the karma leaderboard when called
function ns.updateRaidList(printErrorOnNoRaid)
    local raidSize = GetNumGroupMembers()
    local guildSize = GetNumGuildMembers()
    local raidListText = ""
    local karmaListText = ""
    local guildListText = ""
    local karmaListTextLeft = ""
    local guildListTextLeft = ""
    local karmaListTextRight = ""
    local guildListTextRight = ""
    currentRaidKarma = {}
    currentGuildKarma = {}

    if raidSize < 1 then
        karmaFrame:SetWidth(karmaFrameWidth*2)
        for rIx = 1, GetNumGuildMembers(), 1 do
            local name, _, _, _, class = GetGuildRosterInfo(rIx)

            if name then
                local member = {name = name, karma = ns.getKarma(rIx), class = class, eligible = 0}
                table.insert(currentGuildKarma, member)
            end
        end

        table.sort(currentGuildKarma, function(a, b)
            return a.karma > b.karma
        end)

        if frameHidden == false then
            karmaFrame:Show();
        end

        for i = 1, GetNumGuildMembers(), 1 do

            local member = currentGuildKarma[i];
            local numberColor = 'FFFFFF';
            if member.name == ns.currentPlayer.name then
                numberColor = '00FF00';
            end
            if member.karma > 0 then
                member.name = ns.strSplit(member.name, "-")
                karmaListText = karmaListText ..'|cFF' .. numberColor ..tostring(member.karma) ..'-|r'
                --print(member.name, fullName)
                guildListText = guildListText .. '|cFF'.. classColors[member.class:lower()].hex .. member.name[1] ..'-|r';
            end
        end
        karmaListText = ns.strSplit(karmaListText, "-")
        guildListText = ns.strSplit(guildListText, "-")
        guildSize = math.floor(#karmaListText / 2)

        for i = 1, #karmaListText, 1 do
            if i > math.floor(#karmaListText / 2) then
                karmaListTextRight = karmaListTextRight .. karmaListText[i] .. "\n"
                guildListTextRight = guildListTextRight .. guildListText[i] .. "\n"
            else
                karmaListTextLeft = karmaListTextLeft .. karmaListText[i] .. "\n"
                guildListTextLeft = guildListTextLeft .. guildListText[i] .. "\n"
            end
        end



        raidListFontLeft:SetText(guildListTextLeft);
        raidListFontLeft:SetJustifyH("left");
        raidListFontLeft:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        raidListFontLeft:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        karmaListFontLeft:SetText(karmaListTextLeft);
        karmaListFontLeft:SetJustifyH("right");
        karmaListFontLeft:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        karmaListFontLeft:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        raidListFontRight:SetText(guildListTextRight);
        raidListFontRight:SetJustifyH("left");
        raidListFontRight:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        raidListFontRight:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        karmaListFontRight:SetText(karmaListTextRight);
        karmaListFontRight:SetJustifyH("right");
        karmaListFontRight:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        karmaListFontRight:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        raidListFontLeft:Show();
        karmaListFontLeft:Show();
        raidListFontRight:Show();
        karmaListFontRight:Show();
        local pixels = raidListFontLeft:GetStringHeight()
        local newHeight = pixels + 12 + (pixels / guildSize)
        local widthLeft = raidListFontLeft:GetStringWidth()
        local widthRight = raidListFontRight:GetStringWidth()
        local karmaWidth = karmaListFontLeft:GetStringWidth()
        if widthLeft > widthRight then
            karmaFrame:SetWidth(widthLeft*2 + karmaWidth + 30)
        else
            karmaFrame:SetWidth(widthRight*2 + karmaWidth + 30)
        end
        karmaFrame:SetHeight(newHeight);
        karmaListFontLeft:SetPoint("TOPRIGHT",karmaFrame:GetWidth()/-2 - 2.5, -20)
        raidListFontRight:SetPoint("TOPLEFT",karmaFrame:GetWidth()/2 + 2.5, -20)
    end
    if raidSize > 1 then
        karmaFrame:SetWidth(karmaFrameWidth)
        for rIx = 1, 40, 1 do
            local name, rank, subgroup, level, class = GetRaidRosterInfo(rIx)
            if name then
                local playerRosterIx = ns.findPlayerRosterIx(name)
                if playerRosterIx > -1 then
                    local member = {name = name, karma = ns.getKarma(playerRosterIx), class = class, eligble = 0}
                    table.insert(currentRaidKarma, member)
                    raidSize = raidSize + 1
                end
            end
        end

        table.sort(currentRaidKarma, function(a, b)
            return a.karma > b.karma
        end)

        if frameHidden == false then
            karmaFrame:Show();
        end

        for rTableIx = 1, tablelength(currentRaidKarma), 1
        do

            local member = currentRaidKarma[rTableIx];
            local numberColor = 'FFFFFF';
            local fullName = member.name .. '-' .. GetRealmName();
            if fullName == ns.currentPlayer.name then
                numberColor = '00FF00';
            end
            karmaListText = karmaListText ..'|cFF' .. numberColor ..tostring(member.karma) ..'|r\n'
            raidListText = raidListText .. '|cFF'.. classColors[member.class:lower()].hex ..member.name ..'\n|r';
        end

        raidListFontLeft:SetText(raidListText);
        raidListFontLeft:SetJustifyH("left");
        raidListFontLeft:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        raidListFontLeft:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        karmaListFontLeft:SetText(karmaListText);
        karmaListFontLeft:SetJustifyH("right");
        karmaListFontLeft:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        karmaListFontLeft:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        raidListFontLeft:Show();
        karmaListFontLeft:Show();
        raidListFontRight:Hide();
        karmaListFontRight:Hide();
        local pixels = raidListFontLeft:GetStringHeight()
        local newHeight = pixels + (pixels / raidSize) * 1.5
        karmaFrame:SetHeight(newHeight);
        karmaListFontLeft:SetPoint("TOPRIGHT", -5, -20)
        if karmaFrame:GetWidth() < title:GetStringWidth() then
            karmaFrame:SetWidth(title:GetStringWidth() + 10)
        end
    end
end

-- Gets the name and officer note from the guild members index number
local function getNameAndOfficerNote(index)
	local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(index)
	if officerNote ~= "k:0" then
		return name .. "," .. officerNote
	end
end

-- Opens rolling on an item
function ns.klItem(msg)
    if ns.canOpenRolls() then
		if not rollsOpen then
            maximizeRollFrame()
			local chatMsg = rollMsg .. msg .. " with Karma."
			item = msg
			SendChatMessage(chatMsg, "RAID_WARNING")
			rollsOpen = true
		end
    else
        ns.klSay("You must be in a |cff00FF96raid|r, a |cff00FF96loot master|r and, at |cff00FF96minimum|r, be a |cff00FF96raid assistant|r to use this command!")
    end
end

-- Attempts to close rolling on an item
function ns.klClose()
    if ns.canOpenRolls() then
        if deadlock == true and rollsOpen == true then
            local chatMsg = highestRoller .. " had the same roll! Please reroll!"
            SendChatMessage(chatMsg, "RAID_WARNING")
            highestRoll = 0
            highestRoller = ""
            rollers = {}
        elseif highestRoll == 0 and rollsOpen == true then
            local chatMsg = "KL: Nobody used their Karma! Please free roll for " .. item .. "."
            SendChatMessage(chatMsg, "RAID_WARNING")
        elseif rollsOpen == true then
            rollsOpen = false
            wasKarmaUsed = false
            if highestRoll > 0 then
                local chatMsg = highestRoller .. " has won " .. item .. " with a roll of " .. highestRoll .. "!"
                SendChatMessage(chatMsg, "RAID_WARNING")
            end
            highestRoll = 0
            rollers = {}
            item = nil
            return true
        else
            ns.klSay("There's nothing to close.")
        end
    else
        ns.klSay("You must be in a |cff00FF96raid|r, a |cff00FF96loot master|r and, at |cff00FF96minimum|r, be a |cff00FF96raid assistant|r to use this command!")
    end
end

local function disenchantClose()
    if ns.canOpenRolls() then
        local chatMsg = "KL: " .. item .. " is getting disenchanted by " .. ns.disenchanter .. "."
        SendChatMessage(chatMsg, "RAID_WARNING")
        rollsOpen = false
        highestRoll = 0
        rollers = {}
        item = nil
    end
end

local function giveLoot(lootIndex)
    for i = 1, GetNumGroupMembers(), 1 do
        local candidate = GetMasterLootCandidate(lootIndex, i)
        local member = GetRaidRosterInfo(i)
        if candidate == highestRoller and highestRoll > 0 then
            print('1')
            GiveMasterLoot(lootIndex, i)
        elseif highestRoll == 0 and candidate == ns.disenchanter then
            GiveMasterLoot(lootIndex, i)
        end
    end
end

-- Registers events to be utilized later
function karma_OnLoad(self, event, ...)
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("CHAT_MSG_RAID_WARNING")
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("PLAYER_LOGOUT")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_SLOT_CLEARED")
end

-- Event listeners
function karma_OnEvent(self, event, ...)
    local data = ...

    if ... == "KarmaLoot" then
        if event == "ADDON_LOADED" then
            self:UnregisterEvent("ADDON_LOADED")
  			KarmaLoot_MinimapButton_Reposition()
            frameReady = true
        end
        if event == "CHAT_MSG_ADDON" then
            local prefix, msg, type, sender = ...
            local realmName = "-" .. GetRealmName()
            sender = sender:gsub(realmName, '')
            local parts = ns.strSplit(msg, ":")
            local cmd = parts[1]

            if msg == "refresh" then
                GuildRoster()
            end

            if cmd == "pass" then
                ns.displayPassMsg(parts[2])
            end

            -- Gets initial version request, and responds with version number
            if msg == "Version?" then
                C_ChatInfo.SendAddonMessage("KarmaLoot", version, "RAID")
            end

            -- Receives version number from above if statement and checks for differences
            if msg == version then
                for k, v in pairs(ns.allRaidersTable) do
                    if v == sender then
                        table.remove(ns.allRaidersTable, k)
                        break;
                    end
                end
            end

        end
    end

    if initialized and frameReady then
        if event == "GUILD_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
            ns.loadMemberKarma()
            ns.updateRaidList()
        end
        if event == "CHAT_MSG_RAID_WARNING" then
            local msg, author, language, channel = ...
            if string.find(msg, rollMsg) then
                maximizeRollFrame()
                msg = msg:gsub(rollMsg, "")
                msg = msg:gsub(" with Karma.", "")
                local itemId, _, _, _, _, _, _ = GetItemInfoInstant(msg)
                if itemId then
                    frameHidden = false
                    ns.updateRaidList(true)
					rollsOpen = true
					karmaRollFrameDataLoad(itemId)
                end
            end
			-- Can't think of a better way to do this...
			if string.find(msg, "with a roll of") or string.find(msg, "is getting disenchanted by") then
				rollFrame:Hide()
				highestRoll = 0
				highestRoller = ""
				rollers = {}
                maximizeRollFrame()
			end
        end

        -- Handle rolls
        if event == "CHAT_MSG_SYSTEM" then
			local msg = ...
			local author, rollResult, rollMin, rollMax = string.match(msg, "(.+) rolls (%d+) %((%d+)-(%d+)%)")
			if author then
				noDuplicates = true
				if rollsOpen == true then
					local winnerIndex = ns.findPlayerRosterIx(author)
					if winnerIndex == -1 then
						ns.klSay("Could not find player by name: " .. author)
						return
					end
					local currentK = ns.getKarma(winnerIndex)

					-- Make sure rolls are legit
					if rollers ~= {} then
						for k, v in pairs(rollers) do
							if v == author then
								noDuplicates = false
								break
							end
						end
					end
					table.insert(rollers, author)
					if noDuplicates then
						if tonumber(rollMin) == tonumber(currentK) and tonumber(rollMax) == tonumber(currentK) + 100 then
                            wasKarmaUsed = true
							if tonumber(rollResult) > highestRoll then
                                lastKarmaUser = author
								deadlock = false
								highestRoll = tonumber(rollResult)
								highestRoller = author
								local recolorName = ns.prependClassColor(author)
								highestRollText:SetText("Highest Roll: \n|cffffffff" .. tostring(highestRoll) .. " - " .. recolorName)
							elseif tonumber(rollResult) == highestRoll then
								deadlock = true
								highestRoller = highestRoller .. ", " .. author
								local recolorName = ns.prependClassColor(highestRoller) .. ", " .. ns.prependClassColor(author)
								highestRollText:SetText("Highest Roll: \n|cffffffff" .. tostring(highestRoll) .. " - " .. recolorName)
							end
						elseif tonumber(rollMin) ~= 1 or tonumber(rollMax) ~= 100 then
							if ns.canOpenRolls() and ns.scold then
								local chatMsg = "Please don't attempt to use fake values when we are rolling for gear."
								SendChatMessage(chatMsg, "WHISPER", nil, author)
							end
						else
							if tonumber(rollResult) > highestRoll then
								deadlock = false
								highestRoll = tonumber(rollResult)
								highestRoller = author
								local recolorName = ns.prependClassColor(author)
								highestRollText:SetText("Highest Roll: \n|cffffffff" .. tostring(highestRoll) .. " - " .. recolorName)
							elseif tonumber(rollResult) == highestRoll then
								deadlock = true
								highestRoller = highestRoller .. ", " .. author
								local recolorName = ns.prependClassColor(highestRoller) .. ", " .. ns.prependClassColor(author)
								highestRollText:SetText("Highest Roll: \n|cffffffff" .. tostring(highestRoll) .. " - " .. recolorName)
                            elseif tonumber(rollResult) == 69 and not ns.wasKarmaUsed and ns.nice then
                                deadlock = false
                                highestRoll = tonumber(rollResult)
                                highestRoller = author
                                local recolorName = ns.prependClassColor(author)
								highestRollText:SetText("Highest Roll: \n|cffffffff" .. tostring(highestRoll) .. " - " .. recolorName)
                            end
						end
					end
				end
			end
        end

		-- Automatically saves a backup of all karma that isn't 0,
        -- as well as all the other things we need to save for persistence
		if event == "PLAYER_LOGOUT" then
			local backupDate = date("%m" .. "%d" .. "%y")
			backupData[backupDate] = {}
			for i = 1, GetNumGuildMembers(), 1 do
				local result = getNameAndOfficerNote(i)
				if result ~= nil then
					local name, officerNote = result:match("([^,]+),([^,]+)")
					table.insert(backupData[backupDate], result)
				end
			end
			local duplicates = false
			for k1, v1 in pairs(KL_Karma_Backup) do
				for k2, v2 in pairs(v1) do
					if backupDate == k2 then
						duplicates = true
					end
				end
			end
			if duplicates == false then
				table.insert(KL_Karma_Backup, backupData)
			end
            if #KL_Karma_Backup > numOfBackups then
                table.remove(KL_Karma_Backup, 1)
            end
			KL_Settings.FramePosRelativePoint , _, _, KL_Settings.FramePosX, KL_Settings.FramePosY = karmaFrame:GetPoint(1)
			_, _, _, KL_Settings.MinimapPosX, KL_Settings.MinimapPosY = KarmaLoot_MinimapButton:GetPoint(1)
		end

        if event == "LOOT_OPENED" then
            masterLootTicker = C_Timer.NewTicker(1, function()
                if MasterLooterFrame:IsShown() then
                    if GetNumLootItems() > 0 and not rollsOpen then
                        for i = 1, GetNumLootItems(), 1 do
                            link = GetLootSlotLink(i)
                            itemName, itemLink = GetItemInfo(link)
                            if itemName == LootFrame.selectedItemName then
                                local lootIndex = i
                                ns.openRollsButton:SetScript("OnClick", function()
                                    ns.klItem(itemLink)
                                    ns.openRollsButton:Hide()
                                    closeKarmaButton:Show()
                                    closeNormalButton:Show()
                                    closeDisenchantButton:Show()
                                    return
                                end)
                                ns.openRollsButton:Show()

                                closeKarmaButton:SetScript("OnClick", function()
                                    if highestRoller ~= "" and wasKarmaUsed and highestRoller == lastKarmaUser then
                                        giveLoot(lootIndex)
                                        ns.klClose()
                                        ns.klWin(highestRoller)
                                        closeKarmaButton:Hide()
                                        closeNormalButton:Hide()
                                        closeDisenchantButton:Hide()
                                        ns.openRollsButton:Hide()
                                        highestRoller = ""
                                        MasterLooterFrame:Hide()
                                        rollsOpen = false
                                    end
                                end)

                                closeNormalButton:SetScript("OnClick", function()
                                    if highestRoller ~= "" then
                                        giveLoot(lootIndex)
                                        ns.klClose()
                                        closeKarmaButton:Hide()
                                        closeNormalButton:Hide()
                                        closeDisenchantButton:Hide()
                                        ns.openRollsButton:Hide()
                                        MasterLooterFrame:Hide()
                                        rollsOpen = false
                                    end
                                end)

                                closeDisenchantButton:SetScript("OnClick", function()
                                    if ns.disenchanter == "" then
                                        ns.klSay("Please promote a member of your raid to Disenchanter.")
                                    else
                                        disenchantClose()
                                        giveLoot(lootIndex)
                                        closeKarmaButton:Hide()
                                        closeNormalButton:Hide()
                                        closeDisenchantButton:Hide()
                                        ns.openRollsButton:Hide()
                                        MasterLooterFrame:Hide()
                                        rollFrame:Hide()
                                        rollsOpen = false
                                    end
                                end)
                                return
                            end
                        end
                    else
                        masterLootTicker:Cancel()
                    end
                end
        	end)
            local itemName = ""
            local itemLink = ""
        end
    end
end

-- Used to hide roll frame on a pass
function hideFrame()
    rollFrame:Hide()
    ns.passOnLoot()
end

function closeRollFrame()
    rollFrame:Hide()
end

function maximizeRollFrame()
    rollFrame:SetWidth(250)
    rollFrame:SetHeight(40)
    itemButton:Show()
    itemNameText:Show()
    optNeedButton:Show()
    optGreedButton:Show()
    optPassButton:Show()
    highestRollText:SetPoint("CENTER", rollFrame, "BOTTOM", -15, 15)
end

function minimizeRollFrame()
    rollFrame:SetWidth(100)
    rollFrame:SetHeight(24)
    itemButton:Hide()
    itemNameText:Hide()
    optNeedButton:Hide()
    optGreedButton:Hide()
    optPassButton:Hide()
    highestRollText:SetPoint("CENTER", rollFrame, "BOTTOM", 0, 12)
end

-- Main entry point when WoW client is ready.
local function main()
    ns.loadMemberKarma(true)

    -- Build leaderboard frame
    karmaFrame = ns.standardFrameBuilder("karmaFrame", UIParent, karmaFrameWidth, defaultWindowHeight, "HIGH", KL_Settings.FramePosRelativePoint, KL_Settings.FramePosX, KL_Settings.FramePosY, true)
    title = ns.standardFontStringBuilder("karmaTitle", "CENTER", karmaFrame, "karmaFrame", "TOP", 0, -10, "Karma Leaderboard")

    raidListFontLeft = karmaFrame:CreateFontString("raidListFontLeft", "ARTWORK", "GameFontNormal")
    raidListFontLeft:SetPoint("TOPLEFT", 5, -20)
    karmaListFontLeft = karmaFrame:CreateFontString("karmaListFontLeft", "ARTWORK", "GameFontNormal")
    raidListFontRight = karmaFrame:CreateFontString("raidListFontRight", "ARTWORK", "GameFontNormal")
    raidListFontRight:SetPoint("TOPLEFT", karmaFrameWidth + 5, -20)
    karmaListFontRight = karmaFrame:CreateFontString("karmaListFontRight", "ARTWORK", "GameFontNormal")
    karmaListFontRight:SetPoint("TOPRIGHT", -5, -20)
    ns.updateRaidList()
    leaderBoardReady = true
    karmaFrame:SetPoint(KL_Settings.FramePosRelativePoint, UIParent, KL_Settings.FramePosX, KL_Settings.FramePosY)
    ns.CreateBorder(karmaFrame)
end

-- Builds the templates for the roll frame
local function karmaRollFrame()
    -- Builds roll frame
    rollFrame:Hide()
	rollFrame:SetFrameStrata("HIGH")
	rollFrame:SetWidth(250)
	rollFrame:SetHeight(40)
	local t = rollFrame:CreateTexture(nil,"BACKGROUND")
	t:SetAllPoints(rollFrame)
	t:SetColorTexture(0,0,0,0.5)
	rollFrame:SetPoint("CENTER",0,-200)
    ns.CreateBorder(rollFrame)
    -- Builds Karma Roll button
	local optNeedButton = CreateFrame("Button", "optNeedButton", rollFrame)
    optNeedButton:SetSize(20, 20)
    optNeedButton:SetPoint("BOTTOMRIGHT", -55, 5)
    optNeedButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/karmadiceup.blp")
    optNeedButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/karmadicehover.blp", "BLEND")
    optNeedButton:SetPushedTexture("Interface/Addons/KarmaLoot/textures/karmadicedown.blp")
    optNeedButton:SetScript("OnClick", function()
        ns.kRoll()
        minimizeRollFrame()
    end)

    ns.createButtonTooltips(optNeedButton, "Karma Roll", "ANCHOR_TOP", false)

    -- Builds Normal Roll button
	local optGreedButton = CreateFrame("Button", "optGreedButton", rollFrame)
    optGreedButton:SetSize(20, 20)
    optGreedButton:SetPoint("BOTTOMRIGHT", -30, 5)
    optGreedButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/normaldiceup.blp")
    optGreedButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/normaldicehover.blp", "BLEND")
    optGreedButton:SetPushedTexture("Interface/Addons/KarmaLoot/textures/normaldicedown.blp")
    optGreedButton:SetScript("OnClick", function()
        ns.normalRoll()
        minimizeRollFrame()
    end)

    ns.createButtonTooltips(optGreedButton, "Normal Roll", "ANCHOR_TOP", false)

    -- Builds Pass button
	local optPassButton = CreateFrame("Button", "optPassButton", rollFrame)
    optPassButton:SetSize(20, 20)
    optPassButton:SetPoint("BOTTOMRIGHT", -5, 5)
    optPassButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/passup.blp")
    optPassButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/passhover.blp", "HOVER")
    optPassButton:SetPushedTexture("Interface/Addons/KarmaLoot/textures/passdown.blp")
    optPassButton:SetScript("OnClick", closeRollFrame)

    ns.createButtonTooltips(optPassButton, "Pass", "ANCHOR_TOP", false)

    -- Builds Item Icon
	itemButton = CreateFrame("Button", "itemButton", rollFrame)
    itemButton:SetSize(30, 30)
    itemButton:SetPoint("BOTTOMLEFT", 5, 5)
	itemButton.tex = itemButton:CreateTexture(nil, "ARTWORK")
	itemButton.tex:SetAllPoints(itemButton)
	itemButton.tex:SetTexCoord(.08, .92, .08, .92)

    ns.CreateBorder(itemButton)

    -- Builds the Item Name
	local itemNameText = rollFrame:CreateFontString("itemNameText", "ARTWORK", "GameFontNormal")
    itemNameText:SetPoint("CENTER", rollFrame, "TOP", 20,-8)
    itemNameText:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 14)
    itemNameText:SetJustifyH("center");
    itemNameText:Show()

    -- Builds highest roller text
	local highestRollText = rollFrame:CreateFontString("highestRollText", "ARTWORK", "GameFontNormal")

    highestRollText:SetPoint("CENTER", rollFrame, "BOTTOM", -15, 15)
    --highestRollText:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 10)
    highestRollText:Show()

    local minimizeButton = CreateFrame("Button", "minimizeButton", rollFrame)
    minimizeButton:SetSize(12,12)
    minimizeButton:SetPoint("TOPRIGHT", -24, 12)
    minimizeButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/minimize.blp")
    minimizeButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/minimizehover.blp", "BLEND")
    minimizeButton:SetScript("OnClick", minimizeRollFrame)
    ns.CreateBorder(minimizeButton)
    local maximizeButton = CreateFrame("Button", "maximizeButton", rollFrame)
    maximizeButton:SetSize(12,12)
    maximizeButton:SetPoint("TOPRIGHT", -12, 12)
    maximizeButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/maximize.blp")
    maximizeButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/maximizehover.blp", "BLEND")
    maximizeButton:SetScript("OnClick", maximizeRollFrame)
    ns.CreateBorder(maximizeButton)
    local closeButton = CreateFrame("Button", "closeButton", rollFrame)
    closeButton:SetSize(12,12)
    closeButton:SetPoint("TOPRIGHT", 0, 12)
    closeButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/close.blp")
    closeButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/closehover.blp", "BLEND")
    closeButton:SetScript("OnClick", closeRollFrame)
    ns.CreateBorder(closeButton)
end
karmaRollFrame()

-- Builds information into the roll frame and displays it for use
function karmaRollFrameDataLoad(itemId)
    -- Need to use a ticker here as there aren't really any events I could use.
    -- This one will loop until it gets the item data back from blizzards servers.
    -- This could possibly cause Blizz to force disconnect a user. We'll see!
    waitTicker = C_Timer.NewTicker(0.1, function()
		local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType, expacID, setID, isCraftingReagent = GetItemInfo(itemId)
		if (itemName) then
            if itemQuality == 0 then
                itemName = "|cff" .. qualityColors["poor"].hex .. itemName .. "|r"
            elseif itemQuality == 1 then
                itemName = "|cff" .. qualityColors["common"].hex .. itemName .. "|r"
            elseif itemQuality == 2 then
                itemName = "|cff" .. qualityColors["uncommon"].hex .. itemName .. "|r"
            elseif itemQuality == 3 then
                itemName = "|cff" .. qualityColors["rare"].hex .. itemName .. "|r"
            elseif itemQuality == 4 then
                itemName = "|cff" .. qualityColors["epic"].hex .. itemName .. "|r"
            elseif itemQuality == 5 then
                itemName = "|cff" .. qualityColors["legendary"].hex .. itemName .. "|r"
            end

			itemButton.tex:SetTexture(GetItemIcon(itemId))
			itemNameText:SetText(itemName)
            if itemNameText:GetStringWidth(itemName) > 220 then
                itemName = string.sub(itemName, 0, 45) .. "..."
                itemNameText:SetText(itemName)
            end
			highestRollText:SetText("Highest Roll: \n|cffffffffNone")
			ns.createButtonTooltips(itemButton, itemLink, "ANCHOR_TOP", true)
			rollFrame:Show()
			waitTicker:Cancel()
		end
	end)
end

-- WoW API apparently returns that no one is in the guild right after you login. This method attempts 40 times to check/wait for the Guild in-game APIs to be ready.
local function waitForGuildApiReady(attempts)
    if attempts > 40 then
        return
    end

    local memberCount = GetNumGuildMembers()
    attempts = attempts + 1
    if memberCount == 0 then
        C_Timer.After(
        1,
        function()
            waitForGuildApiReady(attempts)
        end
        )
    end
    if memberCount > 0 then
        main()
    end
end

-- Start up method that gets the add-on loaded and tracking.
local function init()
    if not initialized then
        initialized = true
        local isInGuild = IsInGuild()
        if not frameReady or isInGuild then
            waitForGuildApiReady(0)
        else
            ns.klSay("Karma Loot loaded, but you are not in a guild.")
        end
    end
end

-- Minimap stuff
function KarmaLoot_MinimapButton_DraggingFrame_OnUpdate()

	local xpos,ypos = GetCursorPosition()
	local xmin,ymin = Minimap:GetLeft(), Minimap:GetBottom()

	xpos = xmin-xpos/UIParent:GetScale()+70 -- get coordinates as differences from the center of the minimap
	ypos = ypos/UIParent:GetScale()-ymin-70

	KL_Settings.MinimapPos = math.deg(math.atan2(ypos,xpos)) -- save the degrees we are relative to the minimap center

	KarmaLoot_MinimapButton_Reposition() -- move the button
end

function KarmaLoot_MinimapButton_Reposition()
	KarmaLoot_MinimapButton:SetPoint("TOPLEFT","Minimap","TOPLEFT",52-(80*cos(KL_Settings.MinimapPos)),(80*sin(KL_Settings.MinimapPos))-52)
end

function KarmaLoot_MinimapButton_OnEnter(self)
	if (self.dragging) then
		return
	end
	GameTooltip:SetOwner(self or UIParent, "ANCHOR_LEFT")
	KarmaLoot_MinimapButton_Details(GameTooltip)
end

function KarmaLoot_MinimapButton_OnClick()
    if leaderBoardReady then
    	ns.updateRaidList(true)
    	if frameHidden then
    		frameHidden = false
            ns.updateRaidList(true)
    	else
    		frameHidden = true
    		karmaFrame:Hide()
    	end
    end
end

function KarmaLoot_MinimapButton_Details(tt, ldb)
	tt:SetText("KarmaLoot\n|cFF00FF96Left Click: |cffffffffShow/Hide Leaderboard")
end

C_Timer.After(20, init)
