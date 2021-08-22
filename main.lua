-- Set to false if you don't want to scold people for /rolling with arbitrary values.
local scolding = true

local version = GetAddOnMetadata("KarmaLoot", "Version")
local memberKarma = {}
local currentRaidKarma = {}
local memberRowHeight = 12
local defaultWindowHeight = 70
local playerName = UnitName("player") .. "-" .. GetRealmName()
local currentPlayer = {}
local initialized = false
local frameReady = false
local leaderBoardReady = false
local frameHidden = false
local mmHidden = false
local rollMsg = "KL: Please roll on "
local rollsOpen = false
local highestRoll = 0
local highestRoller = ""
local rollers = {}
local deadlock = false
local item
local success = C_ChatInfo.RegisterAddonMessagePrefix("KarmaLoot") -- Addon name.
local allRaidersTable = {}
local backupData = {}
local restoreConfirm = false
local rollFrame = CreateFrame("Frame",nil,UIParent)

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
local function findPlayerRosterIx(lookup)
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

-- Splits strings lol
local function strSplit(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

-- Prints most chat messages from the addon
local function klSay(msg)
    print("|cFF00FF96kl |cFFFFFFFF " .. msg)
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
local function setKarma(rosterIndex, amount)
    GuildRosterSetOfficerNote(rosterIndex, "k:" .. tostring(amount))
    broadcastRefresh()
end

-- Gets a player's saved karma from the guild roster.
local function getKarma(rosterIndex)
	if(rosterIndex) then
		local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(rosterIndex)
		--print('getKarma() for ' .. rosterIndex .. '-> ' .. name .. ', ' ..officerNote);
		return parseKarma(officerNote)
	end
end

-- Adds the amount specified to the existing pool of Karma for the player.
local function addKarma(rosterIndex, amount)
    local current = getKarma(rosterIndex)
    local newTotal = current + amount
    setKarma(rosterIndex, newTotal)
end

-- Loops through the current guild roster and finds players who need their officer note initialized.
local function initKarmaNotes(rosterIndex, rank, note)
    local initialized = 0
    for k = 1, tablelength(memberKarma), 1 do
        local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(k)
        if officerNote then
            if officerNote == "" then
                setKarma(k, 0)
                initialized = initialized + 1
            end
        end
    end

    if initialized > 0 then
        print("Initialzed " .. initialized .. " officer notes.")
    end
end

-- Loads the guild roster and formulates current Karma standings.
local function loadMemberKarma(showMsg)
    local memberCount = GetNumGuildMembers()
    for k = 1, memberCount, 1 do
        local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(k)
        local member = {name = name, karma = parseKarma(officerNote), rankIx = rankIndex}
        -- if (showMsg and member.karma > 0) then
        --     klSay(member.name..' - '.. tostring(member.karma));
        -- end
        if (name == playerName) then
            currentPlayer = member
        end

        table.insert(memberKarma, member)
    end

    if (currentPlayer.rankIx ~= nil and currentPlayer.rankIx < 2) then
        initKarmaNotes()
    end

    if (showMsg) then
        klSay("Refreshed status for " .. memberCount .. " guild members for " .. currentPlayer.name)
    end
end

-- Updates the karma leaderboard when called
local function updateRaidList(printErrorOnNoRaid)
    local raidSize = GetNumGroupMembers()
    local guildSize = GetNumGuildMembers()
    local raidListText = ""
    local karmaListText = ""
    local guildListText = ""
    currentRaidKarma = {}
    currentGuildKarma = {}

    -- if raidSize < 1 then
    --     if printErrorOnNoRaid then
    --         klSay("Cannot show Karma frame, you are not in a raid or group.")
    --     end
    --     karmaFrame:Hide()
    -- end

    if raidSize < 1 then
        for rIx = 1, GetNumGuildMembers(), 1 do
            local name, _, _, _, class = GetGuildRosterInfo(rIx)

            if name then
                local member = {name = name, karma = getKarma(rIx), class = class, eligible = 0}
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
            if member.name == currentPlayer.name then
                numberColor = '00FF00';
            end
            if member.karma > 0 then
                member.name = strSplit(member.name, "-")
                karmaListText = karmaListText ..'|cFF' .. numberColor ..tostring(member.karma) ..'|r\n'
                --print(member.name, fullName)
                guildListText = guildListText .. '|cFF'.. classColors[member.class:lower()].hex .. member.name[1] ..'\n|r';
            else
                guildSize = guildSize - 1
            end
        end

        raidListFont:SetText(guildListText);
        raidListFont:SetJustifyH("left");
        raidListFont:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        raidListFont:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        karmaListFont:SetText(karmaListText);
        karmaListFont:SetJustifyH("right");
        karmaListFont:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        karmaListFont:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        raidListFont:Show();
        karmaListFont:Show();
        local pixels = raidListFont:GetStringHeight()
        local newHeight = pixels + (pixels / guildSize)
        karmaFrame:SetHeight(newHeight);
    end
    if raidSize > 1 then
        for rIx = 1, 40, 1 do
            local name, rank, subgroup, level, class = GetRaidRosterInfo(rIx)
            if name then
                local playerRosterIx = findPlayerRosterIx(name)
                if playerRosterIx > -1 then
                    local member = {name = name, karma = getKarma(playerRosterIx), class = class, eligble = 0}
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
            if fullName == currentPlayer.name then
                numberColor = '00FF00';
            end
            karmaListText = karmaListText ..'|cFF' .. numberColor ..tostring(member.karma) ..'|r\n'
            raidListText = raidListText .. '|cFF'.. classColors[member.class:lower()].hex ..member.name ..'\n|r';
        end

        raidListFont:SetText(raidListText);
        raidListFont:SetJustifyH("left");
        raidListFont:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        raidListFont:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        karmaListFont:SetText(karmaListText);
        karmaListFont:SetJustifyH("right");
        karmaListFont:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);
        karmaListFont:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 12)

        raidListFont:Show();
        karmaListFont:Show();
        local pixels = raidListFont:GetStringHeight()
        local newHeight = pixels + (pixels / raidSize) * 1.5
        karmaFrame:SetHeight(newHeight);
    end
end

-- Returns whether a player is raid lead, assistant, and master looter
function getRaidRankStuff(name)
    for i = 1, GetNumGroupMembers(), 1 do
        local member, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
        if member == name then
            return rank .. "," .. tostring(isML)
        end

    end
end

-- The /kroll command. Causes the player to perform an infused roll.
local function kRoll()
    loadMemberKarma(false)
    if currentPlayer.karma == 0 then
        klSay("You have no Karma to use.")
    else
        RandomRoll(currentPlayer.karma, 100 + currentPlayer.karma)
    end
end

-- Used by the normal roll button to do a standard 1-100 roll
local function normalRoll()
    RandomRoll(1, 100)
end

-- Used by the pass button to pass on loot
local function passOnLoot()
    C_ChatInfo.SendAddonMessage("KarmaLoot", "pass:" .. currentPlayer.name)
end

-- Used to display a message when a player passes. (Not currently working.)
local function displayPassMsg(playerName)
    playerName = strSplit(playerName,"-")
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

-- Get class color from name and return the hex code to change the color of said name.
local function prependClassColor(playerName)
	local playerClass = UnitClass(playerName)
	local classColor = "|cff" .. classColors[playerClass:lower()].hex .. playerName .. "|r"
	return classColor
end

-- Gets the name and officer note from the guild members index number
local function getNameAndOfficerNote(index)
	local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(index)
	if officerNote ~= "k:0" then
		return name .. "," .. officerNote
	end
end

-- Checks player rank in their guild to prevent usage of certain commands
local function isPlayerOfficer()
    if currentPlayer.rankIx > 1 then
        klSay("You are not an Officer.")
        return false
    else
        return true
    end
end

local function isPlayerLeader()
    if UnitIsGroupLeader("Player", LE_PARTY_CATEGORY_HOME) then
        return true
    else
        return false
    end
end

local function canOpenRolls()
    local result = getRaidRankStuff(UnitName("Player"))
    result = strSplit(result,",")
    if tonumber(result[1]) >= 1 and result[2] == "true" then
        return true
    else
        return false
    end
end

-- Opens rolling on an item
function klItem(msg)
    if canOpenRolls() then
		if not rollsOpen then
            maximizeRollFrame()
			local chatMsg = rollMsg .. msg .. " with Karma."
			item = msg
			SendChatMessage(chatMsg, "RAID_WARNING")
			rollsOpen = true
		end
    else
        klSay("You must be in a |cff00FF96raid|r, a |cff00FF96loot master|r and, at |cff00FF96minimum|r, be a |cff00FF96raid assistant|r to use this command!")
    end
end

-- Attempts to close rolling on an item
local function klClose()
    if canOpenRolls() then
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
            local chatMsg = highestRoller .. " has won " .. item .. " with a roll of " .. highestRoll .. "!"
            SendChatMessage(chatMsg, "RAID_WARNING")
            highestRoll = 0
            highestRoller = ""
            rollers = {}
        else
            klSay("There's nothing to close.")
        end
    else
        klSay("You must be in a |cff00FF96raid|r, a |cff00FF96loot master|r and, at |cff00FF96minimum|r, be a |cff00FF96raid assistant|r to use this command!")
    end
end

-- Builds and displays the loot roll frame when needed
local function createButtonTooltips(frame, text, position, item)
	frame:HookScript("OnEnter", function()
		GameTooltip:SetOwner(frame, position)
		if item then
			GameTooltip:SetHyperlink(text)
		else
			GameTooltip:SetText(text)
		end
		GameTooltip:Show()
	end)

	frame:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
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
            local parts = strSplit(msg, ":")
            local cmd = parts[1]

            if msg == "refresh" then
                GuildRoster()
            end

            if cmd == "pass" then
                displayPassMsg(parts[2])
            end

            -- Gets initial version request, and responds with version number
            if msg == "Version?" then
                C_ChatInfo.SendAddonMessage("KarmaLoot", version, "RAID")
            end

            -- Receives version number from above if statement and checks for differences
            if msg == version then
                for k, v in pairs(allRaidersTable) do
                    if v == sender then
                        table.remove(allRaidersTable, k)
                        break;
                    end
                end
            end

        end
    end

    if initialized and frameReady then
        if event == "GUILD_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
            loadMemberKarma()
            updateRaidList()
        end
        if event == "CHAT_MSG_RAID_WARNING" then
            local msg, author, language, channel = ...
            if string.find(msg, rollMsg) then
                msg = msg:gsub(rollMsg, "")
                msg = msg:gsub(" with Karma.", "")
                local itemId, _, _, _, _, _, _ = GetItemInfoInstant(msg)
                if itemId then
                    frameHidden = false
                    updateRaidList(true)
					rollsOpen = true
					karmaRollFrameDataLoad(itemId)
                end
            end
			-- Can't think of a better way to do this...
			if string.find(msg, "with a roll of") then
				rollFrame:Hide()
				highestRoll = 0
				highestRoller = ""
				rollers = {}
			end
        end

        -- Handle rolls
        if event == "CHAT_MSG_SYSTEM" then
			local msg = ...
			local author, rollResult, rollMin, rollMax = string.match(msg, "(.+) rolls (%d+) %((%d+)-(%d+)%)")
			if author then
				noDuplicates = true
				if rollsOpen == true then
					local winnerIndex = findPlayerRosterIx(author)
					if winnerIndex == -1 then
						klSay("Could not find player by name: " .. author)
						return
					end
					local currentK = getKarma(winnerIndex)

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
							if tonumber(rollResult) > highestRoll then
								deadlock = false
								highestRoll = tonumber(rollResult)
								highestRoller = author
								local recolorName = prependClassColor(author)
								highestRollText:SetText("Highest Roll: \n|cffffffff" .. tostring(highestRoll) .. " - " .. recolorName)
							elseif tonumber(rollResult) == highestRoll then
								deadlock = true
								highestRoller = highestRoller .. ", " .. author
								local recolorName = prependClassColor(highestRoller) .. ", " .. prependClassColor(author)
								highestRollText:SetText("Highest Roll: \n|cffffffff" .. tostring(highestRoll) .. " - " .. recolorName)
							end
						elseif tonumber(rollMin) ~= 1 or tonumber(rollMax) ~= 100 then
							if canOpenRolls() and scolding then
								local chatMsg = "Please don't attempt to use fake values when we are rolling for gear."
								SendChatMessage(chatMsg, "WHISPER", nil, author)
							end
						else
							if tonumber(rollResult) > highestRoll then
								deadlock = false
								highestRoll = tonumber(rollResult)
								highestRoller = author
								local recolorName = prependClassColor(author)
								highestRollText:SetText("Highest Roll: \n|cffffffff" .. tostring(highestRoll) .. " - " .. recolorName)
							elseif tonumber(rollResult) == highestRoll then
								deadlock = true
								highestRoller = highestRoller .. ", " .. author
								local recolorName = prependClassColor(highestRoller) .. ", " .. prependClassColor(author)
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
			KL_Settings.FramePosRelativePoint , _, _, KL_Settings.FramePosX, KL_Settings.FramePosY = karmaFrame:GetPoint(1)
			_, _, _, KL_Settings.MinimapPosX, KL_Settings.MinimapPosY = KarmaLoot_MinimapButton:GetPoint(1)
		end

        --[[if event == "LOOT_OPENED" then
            masterLootTicker = C_Timer.NewTicker(0.1, function()
                if MasterLooterFrame:IsShown() then
                    for i = 1, GetNumLootItems(), 1 do
                        local link = GetLootSlotLink(i)
                        local itemName = GetItemInfo(link)
                        if itemName == LootFrame.selectedItemName then
                            local openRollsButton = CreateFrame("Button", "openRollsButton", MasterLooterFrame, MasterLooterFrame)
                            openRollsButton:Hide()
                            openRollsButton:SetSize(20,20)
                            openRollsButton:SetPoint("TOPRIGHT", 25, -10)
                            openRollsButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/karmadiceup.blp")
                            openRollsButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/karmadicehover.blp", "BLEND")
                            openRollsButton:SetPushedTexture("Interface/Addons/KarmaLoot/textures/karmadicedown.blp")
                            createButtonTooltips(openRollsButton, "Begin rolling on this item", "ANCHOR_TOP", false)
                            openRollsButton:RegisterForClicks("AnyUp");
                            openRollsButton:SetScript("OnClick", function()
                                klItem(link)
                            end)
                            openRollsButton:Show()
                            masterLootTicker:Cancel()
                        end
                    end
                end
        	end)
        end]]
    end
end

-- Used to hide roll frame on a pass
function hideFrame()
    rollFrame:Hide()
    passOnLoot()
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
    loadMemberKarma(true)

    -- Build leaderboard frame
    karmaFrame:SetFrameStrata("BACKGROUND")
    karmaFrame:SetWidth(130)
    karmaFrame:SetHeight(defaultWindowHeight)
    local t = karmaFrame:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background.blp")
    t:SetAllPoints(karmaFrame)
    karmaFrame.texture = t
    --karmaFrame:SetPoint("CENTER", "UIParent", 0, 0)
    karmaFrame:SetMovable(true)
    karmaFrame:EnableMouse(true)
    karmaFrame:RegisterForDrag("LeftButton")
    karmaFrame:SetScript("OnDragStart", karmaFrame.StartMoving)
    karmaFrame:SetScript("OnDragStop", karmaFrame.StopMovingOrSizing)

    -- Build title text
    local title = karmaFrame:CreateFontString("karmaTitle", "ARTWORK", "GameFontNormal")
    title:SetPoint("CENTER", "karmaFrame", "TOP", 0, -10)
    title:SetText("Karma Leaderboard")
    title:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 14)
    title:Show()

    -- Build member/karma list
    raidListFont = karmaFrame:CreateFontString("karmaRaidList", "ARTWORK", "GameFontNormal")
    raidListFont:SetPoint("TOPLEFT", 10, -20)
    karmaListFont = karmaFrame:CreateFontString("karmaRaidList", "ARTWORK", "GameFontNormal")
    karmaListFont:SetPoint("TOPRIGHT", -10, -20)
    updateRaidList()
    leaderBoardReady = true
    karmaFrame:SetPoint(KL_Settings.FramePosRelativePoint, KL_Settings.FramePosX, KL_Settings.FramePosY)
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

    -- Builds Karma Roll button
	local optNeedButton = CreateFrame("Button", "optNeedButton", rollFrame)
    optNeedButton:SetSize(20, 20)
    optNeedButton:SetPoint("BOTTOMRIGHT", -55, 5)
    optNeedButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/karmadiceup.blp")
    optNeedButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/karmadicehover.blp", "BLEND")
    optNeedButton:SetPushedTexture("Interface/Addons/KarmaLoot/textures/karmadicedown.blp")
    optNeedButton:SetScript("OnClick", function()
        kRoll()
        minimizeRollFrame()
    end)

    createButtonTooltips(optNeedButton, "Karma Roll", "ANCHOR_TOP", false)

    -- Builds Normal Roll button
	local optGreedButton = CreateFrame("Button", "optGreedButton", rollFrame)
    optGreedButton:SetSize(20, 20)
    optGreedButton:SetPoint("BOTTOMRIGHT", -30, 5)
    optGreedButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/normaldiceup.blp")
    optGreedButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/normaldicehover.blp", "BLEND")
    optGreedButton:SetPushedTexture("Interface/Addons/KarmaLoot/textures/normaldicedown.blp")
    optGreedButton:SetScript("OnClick", function()
        normalRoll()
        minimizeRollFrame()
    end)

    createButtonTooltips(optGreedButton, "Normal Roll", "ANCHOR_TOP", false)

    -- Builds Pass button
	local optPassButton = CreateFrame("Button", "optPassButton", rollFrame)
    optPassButton:SetSize(20, 20)
    optPassButton:SetPoint("BOTTOMRIGHT", -5, 5)
    optPassButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/passup.blp")
    optPassButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/passhover.blp", "HOVER")
    optPassButton:SetPushedTexture("Interface/Addons/KarmaLoot/textures/passdown.blp")
    optPassButton:SetScript("OnClick", closeRollFrame)

    createButtonTooltips(optPassButton, "Pass", "ANCHOR_TOP", false)

    -- Builds Item Icon
	itemButton = CreateFrame("Button", "itemButton", rollFrame)
    itemButton:SetSize(30, 30)
    itemButton:SetPoint("BOTTOMLEFT", 5, 5)
	itemButton.tex = itemButton:CreateTexture(nil, "ARTWORK")
	itemButton.tex:SetAllPoints(itemButton)
	itemButton.tex:SetTexCoord(.08, .92, .08, .92)

    -- Builds the Item Name
	local itemNameText = rollFrame:CreateFontString("itemNameText", "ARTWORK", "GameFontNormal")
    itemNameText:SetPoint("CENTER", rollFrame, "TOP", 20,-8)
    itemNameText:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 20)
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

    local maximizeButton = CreateFrame("Button", "maximizeButton", rollFrame)
    maximizeButton:SetSize(12,12)
    maximizeButton:SetPoint("TOPRIGHT", -12, 12)
    maximizeButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/maximize.blp")
    maximizeButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/maximizehover.blp", "BLEND")
    maximizeButton:SetScript("OnClick", maximizeRollFrame)

    local closeButton = CreateFrame("Button", "closeButton", rollFrame)
    closeButton:SetSize(12,12)
    closeButton:SetPoint("TOPRIGHT", 0, 12)
    closeButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/close.blp")
    closeButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/closehover.blp", "BLEND")
    closeButton:SetScript("OnClick", closeRollFrame)
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
			createButtonTooltips(itemButton, itemLink, "ANCHOR_TOP", true)
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
            klSay("Karma Loot loaded, but you are not in a guild.")
        end
    end
end

-- Officers only. The /kl earn command. Syntax is /kl earn {amount}. The amount specified will be awarded to everyone in the caller's raid group.
local function klEarn(amount)
    if not isPlayerOfficer then
        return
    end
    loadMemberKarma(false)
    local sanitizedAmt = math.floor(tonumber(amount))

    local successFullGrants = 0
    for rI = 1, 40, 1 do
        local name = GetRaidRosterInfo(rI)
        if name then
            local earnIx = findPlayerRosterIx(name)
            if earnIx > -1 then
                addKarma(earnIx, sanitizedAmt)
                successFullGrants = successFullGrants + 1
            end
        end
    end

    if successFullGrants > 0 then
        SendChatMessage(
        "All Raid members in " .. currentPlayer.name .. "'s raid have earned " .. tostring(sanitizedAmt) .. " Karma",
        "RAID"
        )
    else
        klSay("Something went wrong, no one got granted anything. Are you even in a raid?")
    end
end

-- Officers only. The /kl set command. Syntax: /kl set {playerName} {amount} -- Administrative fixing command that hard sets a player's karma to a specific value.
local function klSet(msg)
    if not isPlayerOfficer then
        return
    end
    loadMemberKarma(false)

    local parts = strSplit(msg) -- special split that allows for special characters in player names
    local amtNum = tonumber(parts[3])
    local amount = math.floor(amtNum)
    local playerIndex = findPlayerRosterIx(parts[2])

    setKarma(playerIndex, amount)
    local chatMsg = "[KarmaLoot]: " .. parts[2] .. "'s Karma has been set to " .. amount .. " by " .. currentPlayer.name
    SendChatMessage(chatMsg, "RAID")
end

-- For officers and raid leaders. The /kl win command. Syntax: /kl win {playerName}. To be called when a player has won an item after performing an infused roll.
local function klWin(msg)
    if not isPlayerLeader and not isPlayerOfficer then
        return
    end
    if (not msg) then
        local targetName = GetUnitName("playertarget")
        if targetName == nil then
            klSay("No name specified or target selected!")
            return
        end
        msg = targetName
    end
    loadMemberKarma(false)
    local winnerIndex = findPlayerRosterIx(msg)
    if winnerIndex == -1 then
        klSay("Could not find player by name: " .. msg)
        return
    end

    local currentK = getKarma(winnerIndex)
    --print(tostring(pIx) .. ' -> ' ..tostring(currentK));

    if currentK == 0 then
        klSay("Could not reduce Karma, " .. msg .. " Karma is already at zero.")
        return
    end

    local newK = math.floor(currentK / 2)
    setKarma(winnerIndex, newK)
    local chatMsg = msg .. " won the item. Karma has been halved. (" .. newK .. ")"
    SendChatMessage(chatMsg, "RAID")
end



-- Gets the version of everyone in the raid and tells you who's slacking
local function klVersion()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers(), 1 do
            member = GetRaidRosterInfo(i)
            table.insert(allRaidersTable, member)
            table.sort(allRaidersTable)
        end
        C_ChatInfo.SendAddonMessage("KarmaLoot", "Version?", "RAID")
        C_Timer.After(1,function()
        if table.concat(allRaidersTable) == '' then
            klSay("Everyone is up to date!")
        else
            for k, v in pairs(allRaidersTable) do
                allRaidersTable[k] = prependClassColor(v)
            end
            klSay("The following players are out of date or do not have the addon installed:\n" .. table.concat(allRaidersTable, ', '))
            allRaidersTable = {}
        end
        end)
    else
        klSay("You need to be in a raid to use this command.")
    end
end

local function klBackups()
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
    klSay("Latest 5 backup dates: " .. table.concat(backups, ", ") .. "\nIf you need to restore a backup, use the |cffffa500'/klrestore DDMMYY'|r command.")
end

-- The /kl command. Primary CLI entry point. Serves several sub commands.
local function slashKl(msg)
    if not msg or msg == "" then
        print("|cFF00FF96KarmaLoot! |cFFAAAAAAUse /KL ? to list options.")
    end
    if msg == "roll" then
        kRoll()
    end
    if msg == "?" then
        print("|cFF00FF96KarmaLoot!|cFFAAAAAA Here's a list of options:")
        print("|cFF00FF96/kl|cFFFFFFFF roll |cFFAAAAAA - perform an infused roll.")
        print("|cFF00FF96/kl|cFFFFFFFF show |cFFAAAAAA - Show the current raid's karma leaderboard.")
        print("|cFF00FF96/kl|cFFFFFFFF hide |cFFAAAAAA - Hide the raid leaderboard.")
        print("|cFF00FF96/kl|cFFFFFFFF check |cFFAAAAAA - Check your own Karma status.")
        print("|cFF00FF96/kl|cFFFFFFFF -v |cFFAAAAAA - Check everyones versions against yours.")
        print("|cFFFFFFFF - Officer commands: ")
        print("|cFF00FF96/kl|cFFFFFFFF earn <Amount>|cFFAAAAAA - Reward the entire raid some Karma.")
        print("|cFF00FF96/kl|cFFFFFFFF set <Player> <Amount>|cFFAAAAAA - Set a player to a specific amount.")
        print("|cFF00FF96/kl|cFFFFFFFF win [<Player> or Current Target]|cFFAAAAAA - Reward a player an item, halving their Karma.")
        print("|cFF00FF96/kl|cFFFFFFFF [ITEM_LINK_HERE]|cFFAAAAAA - Prompts the raid to roll on an item and unhides their KL GUI.")
		print("|cFF00FF96/kl|cFFFFFFFF backups|cFFAAAAAA - Prints a list of backup dates to be used for easy karma restoration.")
    end
    if msg == "check" then
        loadMemberKarma(false)
        klSay("You currently have " .. tostring(currentPlayer.karma) .. " karma to infuse.")
    end
    if msg == "refresh" then
        loadMemberKarma(true)
    end

    if msg == "hide" then
        frameHidden = true
        karmaFrame:Hide()
    end
    if msg == "show" then
        frameHidden = false
        updateRaidList(true)
    end

    local parts = strSplit(msg)
    local cmd = parts[1]

    if cmd == "earn" then
        klEarn(parts[2])
    end

    if cmd == "set" then
        klSet(msg)
    end

    if cmd == "win" then
        klWin(parts[2])
		print(parts[2])
    end

    local itemId = GetItemInfoInstant(msg)
    if itemId then
        klItem(msg)
    end

    if cmd == "close" then
        klClose()
    end

	-- Check versions of other members in your current raid.
    if cmd == "-v" then
        klVersion()
    end

	-- Check dates for latest backups. Useful for backup restoration command.
	if cmd == "backups" then
        klBackups()
	end

end

-- Takes a date argument and finds the respective karma backup, then restores it.
local function klRestore(msg)
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
    	updateRaidList(true)
    	if frameHidden then
    		frameHidden = false
            updateRaidList(true)
    	else
    		frameHidden = true
    		karmaFrame:Hide()
    	end
    end
end

function KarmaLoot_MinimapButton_Details(tt, ldb)
	tt:SetText("KarmaLoot\n|cFF00FF96Left Click: |cffffffffShow/Hide Leaderboard")
end

SLASH_KLENTRY1, SLASH_KLENTRY2 = "/kl", "/karmaloot"
SLASH_KLROLL1, SLASH_KLROLL2 = "/kroll", "/klroll"
SLASH_KLRESTORE1 = "/klrestore"

SlashCmdList["KLENTRY"] = slashKl
SlashCmdList["KLROLL"] = kRoll
SlashCmdList["KLRESTORE"] = klRestore

C_Timer.After(20, init)
