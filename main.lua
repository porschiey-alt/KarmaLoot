local version = "1.4"

-- Set to false if you don't want to scold people for /rolling with arbitrary values.
local scolding = true

local memberKarma = {}
local currentRaidKarma = {}
local memberRowHeight = 10
local defaultWindowHeight = 64
local playerName = UnitName("player") .. "-" .. GetRealmName()
local currentPlayer = {}
local initialized = false
local frameReady = false
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

-- low level lua utils --
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

local function findPlayerRosterIx(lookup)
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

function karma_OnLoad(self, event, ...)
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("CHAT_MSG_RAID_WARNING")
    self:RegisterEvent("CHAT_MSG_SYSTEM")
end

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
    local name, rank, rankIndex, level, class, zone, note, officerNote = GetGuildRosterInfo(rosterIndex)
    --print('getKarma() for ' .. rosterIndex .. '-> ' .. name .. ', ' ..officerNote);
    return parseKarma(officerNote)
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

local function updateRaidList(printErrorOnNoRaid)
    local raidSize = 0
    local raidListText = ""
    currentRaidKarma = {}
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

    table.sort(
    currentRaidKarma,
    function(a, b)
        return a.karma > b.karma
    end
    )

    if raidSize < 1 then
        if printErrorOnNoRaid then
            klSay("Cannot show Karma frame, you are not in a raid or group.")
        end
        karmaFrame:Hide()
    end

    if raidSize > 1 then
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
            raidListText = raidListText ..'|cFF' .. numberColor ..tostring(member.karma) ..'|r - |cFF'.. classColors[member.class:lower()].hex ..member.name ..'\n|r';
        end

        raidListFont:SetText(raidListText);
        raidListFont:SetJustifyH("left");
        raidListFont:SetTextColor(classColors.priest.r, classColors.priest.g, classColors.priest.b, 1);

        raidListFont:Show();
        local newHeight = (raidSize - 2) * memberRowHeight + defaultWindowHeight;
        karmaFrame:SetHeight(newHeight);
    end
end

-- The /kroll command. Causes the player to perform an infused roll.
local function kRoll()
    loadMemberKarma(false)
    if currentPlayer.karma == 0 then
        print("You have no Karma to use.")
    else
        RandomRoll(currentPlayer.karma, 100 + currentPlayer.karma)
    end
end

local function normalRoll()
    RandomRoll(1, 100)
end

local function passOnLoot()
    C_ChatInfo.SendAddonMessage("KarmaLoot", "pass:" .. currentPlayer.name)
end

local function displayPassMsg(playerName)
    print("|cFFFFFF00" .. playerName .. " passed on loot.|cFFFFFFFF")
end

-- events
function karma_OnEvent(self, event, ...)
    local data = ...

    if ... == "KarmaLoot" then
        if event == "ADDON_LOADED" then
            self:UnregisterEvent("ADDON_LOADED")
            frameReady = true
        end
        if event == "CHAT_MSG_ADDON" then
            local prefix, msg = ...

            if msg == "refresh" then
                GuildRoster()
            end

            local parts = strSplit(msg, ":")
            local cmd = parts[1]
            if cmd == "pass" then
                displayPassMsg(parts[2])
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
                end
            end
        end

        -- Handle rolls
        if event == "CHAT_MSG_SYSTEM" then
            noDuplicates = true
            if rollsOpen == true then
                local msg = ...
                local author, rollResult, rollMin, rollMax = string.match(msg, "(.+) rolls (%d+) %((%d+)-(%d+)%)")
                local winnerIndex = findPlayerRosterIx(author)
                if winnerIndex == -1 then
                    print("Could not find player by name: " .. author)
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
                        elseif tonumber(rollResult) == highestRoll then
                            deadlock = true
                            highestRoller = highestRoller .. ", " .. author
                        end
                    elseif tonumber(rollMin) ~= 1 and tonumber(rollMax) ~= 100 then
                        if UnitIsGroupLeader("Player", LE_PARTY_CATEGORY_HOME) then
                            if scolding then
                                local chatMsg = "Please don't attempt to use fake values when we are rolling for gear."
                                SendChatMessage(chatMsg, "WHISPER", nil, author)
                            end
                        end
                    else
                        if tonumber(rollResult) > highestRoll then
                            deadlock = false
                            highestRoll = tonumber(rollResult)
                            highestRoller = author
                        elseif tonumber(rollResult) == highestRoll then
                            deadlock = true
                            highestRoller = highestRoller .. ", " .. author
                        end
                    end
                end
            end
        end
        if event == "CHAT_MSG_ADDON" then
            realmName = "-" .. GetRealmName()
            local prefix, msg, type, sender = ...

            if msg == "Version?" then
                C_ChatInfo.SendAddonMessage("KarmaLoot", version, "RAID")
            end

            sender = sender:gsub(realmName, '')
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
end

local function hideFrame()
    frameHidden = true
    karmaFrame:Hide()
end

-- Main entry point when WoW client is ready.
local function main()
    loadMemberKarma(true)
    karmaFrame:SetFrameStrata("BACKGROUND")
    karmaFrame:SetWidth(200)
    karmaFrame:SetHeight(defaultWindowHeight)

    local t = karmaFrame:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background.blp")
    t:SetAllPoints(karmaFrame)
    karmaFrame.texture = t

    karmaFrame:SetPoint("CENTER", 200, 0)
    --karmaFrame:Show();

    local toolTip = CreateFrame("Frame", "KarmaTip", karmaFrame)
    toolTip:SetWidth(200)
    toolTip:SetHeight(defaultWindowHeight)
    local t2 = toolTip:CreateTexture(nil, "BACKGROUND")
    t2:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background.blp")
    t2:SetAllPoints(toolTip)
    toolTip.texture = t2
    toolTip:SetPoint("CENTER", 0, 0)

    local toolTipText = toolTip:CreateFontString("toolTipText", "ARTWORK", "GameFontNormal")
    toolTipText:SetPoint("CENTER", "karmaFrame", "CENTER", 0, 0)
    toolTipText:SetText("|cFFFFFFFF--")
    toolTipText:Show()
    toolTip:Hide()

    karmaFrame:SetMovable(true)
    karmaFrame:EnableMouse(true)
    karmaFrame:RegisterForDrag("LeftButton")
    karmaFrame:SetScript("OnDragStart", karmaFrame.StartMoving)
    karmaFrame:SetScript("OnDragStop", karmaFrame.StopMovingOrSizing)

    local title = karmaFrame:CreateFontString("karmaTitle", "ARTWORK", "GameFontNormal")
    title:SetPoint("CENTER", "karmaFrame", "TOP", 0, -6)
    title:SetText("Raid Karma")
    title:Show()

    raidListFont = karmaFrame:CreateFontString("karmaRaidList", "ARTWORK", "GameFontNormal")
    raidListFont:SetPoint("TOPLEFT", 0, -15)
    updateRaidList()

    -- NEED (KROLL)
    local optNeedButton = CreateFrame("Button", "optNeedButton", karmaFrame)
    optNeedButton:SetSize(30, 30)
    optNeedButton:SetPoint("TOPLEFT", 0, 20)
    optNeedButton:SetNormalTexture("Interface/Buttons/UI-GroupLoot-Dice-Up")
    optNeedButton:SetHighlightTexture("Interface/Buttons/UI-GroupLoot-Dice-Highlight")
    optNeedButton:SetPushedTexture("Interface/Buttons/UI-GroupLoot-Dice-Down")
    optNeedButton:SetScript("OnClick", kRoll)
    optNeedButton:SetScript(
    "OnEnter",
    function()
        toolTipText:SetText("|cFFFFFFFFROLL WITH KARMA")
        toolTip:Show()
    end
    )

    optNeedButton:SetScript(
    "OnLeave",
    function()
        toolTip:Hide()
    end
    )

    -- GREED
    local optGreedButton = CreateFrame("Button", "optGreedButton", karmaFrame)
    optGreedButton:SetSize(30, 30)
    optGreedButton:SetPoint("TOP", 0, 20)
    optGreedButton:SetNormalTexture("Interface/Buttons/UI-GroupLoot-Coin-Up")
    optGreedButton:SetHighlightTexture("Interface/Buttons/UI-GroupLoot-Coin-Highlight")
    optGreedButton:SetPushedTexture("Interface/Buttons/UI-GroupLoot-Coin-Down")
    optGreedButton:SetScript("OnClick", normalRoll)
    optGreedButton:SetScript(
    "OnEnter",
    function()
        toolTipText:SetText("|cFFFFFFFFROLL WITHOUT ANY KARMA")
        toolTip:Show()
    end
    )

    optGreedButton:SetScript(
    "OnLeave",
    function()
        toolTip:Hide()
    end
    )

    -- PASS (hide for now)
    local optPassButton = CreateFrame("Button", "optPassButton", karmaFrame)
    optPassButton:SetSize(30, 30)
    optPassButton:SetPoint("TOPRIGHT", 0, 20)
    optPassButton:SetNormalTexture("Interface/Buttons/UI-GroupLoot-Pass-Up")
    optPassButton:SetHighlightTexture("Interface/Buttons/UI-GroupLoot-Pass-Highlight")
    optPassButton:SetPushedTexture("Interface/Buttons/UI-GroupLoot-Pass-Down")
    optPassButton:SetScript("OnClick", hideFrame)
    optPassButton:SetScript(
    "OnEnter",
    function()
        toolTipText:SetText("|cFFFFFFFFHide this window")
        toolTip:Show()
    end
    )

    optPassButton:SetScript(
    "OnLeave",
    function()
        toolTip:Hide()
    end
    )
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
            print("Karma Loot loaded, but you are not in a guild.")
        end
    end
end

-- Officers only. The /kl earn command. Syntax is /kl earn {amount}. The amount specified will be awarded to everyone in the caller's raid group.
local function klEarn(amount)
    if currentPlayer.rankIx > 1 then
        print("You are not an Officer.")
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
    if currentPlayer.rankIx > 1 then
        print("You are not an Officer.")
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
local function klwin(msg)
    if (not msg) then
        local targetName = GetUnitName("playertarget")
        if targetName == nil then
            print("No name specified or target selected!")
            return
        end
        msg = targetName
    end
    loadMemberKarma(false)
    local winnerIndex = findPlayerRosterIx(msg)
    if winnerIndex == -1 then
        print("Could not find player by name: " .. msg)
        return
    end

    local currentK = getKarma(winnerIndex)
    --print(tostring(pIx) .. ' -> ' ..tostring(currentK));

    if currentK == 0 then
        print("Could not reduce Karma, " .. msg .. " Karma is already at zero.")
        return
    end

    local newK = math.floor(currentK / 2)
    setKarma(winnerIndex, newK)
    local chatMsg = msg .. " won the item. Karma has been halved. (" .. newK .. ")"
    SendChatMessage(chatMsg, "RAID")
end

-- Adds a minimap button to hide/show the frame. Need to figure out how to make the icon draggable, but will probably add a command to hide the button in the meantime.
local MinimapButton = CreateFrame("Button", "MainMenuBarToggler", Minimap)

function MinimapButton:Load()
    self:SetFrameStrata("HIGH")
    self:SetWidth(31)
    self:SetHeight(31)
    self:SetFrameLevel(8)
    self:RegisterForClicks("anyUp")
    self:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = self:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local icon = self:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface/Buttons/UI-GroupLoot-Dice-Up")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -5)
    self.icon = icon

    self:SetScript("OnClick", self.OnClick)

    self:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -2, 2)
end

function MinimapButton:OnClick(button)
    if button == "LeftButton" and frameHidden == false then
        karmaFrame:Hide()
        frameHidden = true
    else
        updateRaidList(true)
        karmaFrame:Show()
        frameHidden = false
    end
end

MinimapButton:Load()

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
        print("|cFF00FF96/kl|cFFFFFFFF mmshow |cFFAAAAAA - Shows the minimap button.")
        print("|cFF00FF96/kl|cFFFFFFFF mmhide |cFFAAAAAA - Hides the minimap button.")
        print("|cFF00FF96/kl|cFFFFFFFF -v |cFFAAAAAA - Check everyones versions against yours.")
        print("|cFFFFFFFF - Officer commands: ")
        print("|cFF00FF96/kl|cFFFFFFFF earn <Amount>|cFFAAAAAA - Reward the entire raid some Karma.")
        print("|cFF00FF96/kl|cFFFFFFFF set <Player> <Amount>|cFFAAAAAA - Set a player to a specific amount.")
        print(
        "|cFF00FF96/kl|cFFFFFFFF win [<Player> or Current Target]|cFFAAAAAA - Reward a player an item, halving their Karma."
        )
        print(
        "|cFF00FF96/kl|cFFFFFFFF [ITEM_LINK_HERE]|cFFAAAAAA - Prompts the raid to roll on an item and unhides their KL GUI."
        )
    end
    if msg == "check" then
        loadMemberKarma(false)
        print("You currently have " .. tostring(currentPlayer.karma) .. " karma to infuse.")
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
        klwin(parts[2])
    end

    local itemId, _, _, _, _, _, _ = GetItemInfoInstant(msg)
    if itemId then
        local chatMsg = rollMsg .. msg .. " with Karma."
        item = msg
        SendChatMessage(chatMsg, "RAID_WARNING")
        rollsOpen = true
    end

    if cmd == "close" then
        if deadlock == true then
            local chatMsg = highestRoller .. " had the same roll! Please reroll!"
            SendChatMessage(chatMsg, "RAID_WARNING")
            highestRoll = 0
            highestRoller = ""
            rollers = {}
        elseif highestRoll == 0 then
            local chatMsg = "KL: Nobody used their Karma! Please free roll for " .. item .. "."
            SendChatMessage(chatMsg, "RAID_WARNING")
        else
            rollsOpen = false
            local chatMsg = highestRoller .. " has won " .. item .. " with a roll of " .. highestRoll .. "!"
            SendChatMessage(chatMsg, "RAID_WARNING")
            highestRoll = 0
            highestRoller = ""
            rollers = {}
        end
    end

    if cmd == "mmhide" then
        MinimapButton:Hide()
        mmHidden = true
    end

    if cmd == "mmshow" then
        MinimapButton:Show()
        mmHidden = false
    end

    if cmd == "-v" then
		if IsInRaid() then
			for i = 1, GetNumGroupMembers(), 1 do
				member = GetRaidRosterInfo(i)
				table.insert(allRaidersTable, member)
				table.sort(allRaidersTable)
			end
			C_ChatInfo.SendAddonMessage("KarmaLoot", "Version?", "RAID")
			C_Timer.After(1,function()
			if table.concat(allRaidersTable) == '' then
				print("Everyone is up to date!")
			else
				print("The following players are out of date or do not have the addon installed:\n" .. table.concat(allRaidersTable, '\n'))
				allRaidersTable = {}
			end
			end)
		else
			print("You need to be in a raid to use this command.")
		end
    end
	
	if cmd == "test" then
		local itemFrame = MasterLooterFrame.Item;
		itemFrame.ItemName:SetText(LootFrame.selectedItemName);
		itemFrame.Icon:SetTexture(LootFrame.selectedTexture);
		local colorInfo = ITEM_QUALITY_COLORS[LootFrame.selectedQuality];
		itemFrame.IconBorder:SetVertexColor(colorInfo.r, colorInfo.g, colorInfo.b);
		itemFrame.ItemName:SetVertexColor(colorInfo.r, colorInfo.g, colorInfo.b);
		MasterLooterFrame:Show();
		MasterLooterFrame_UpdatePlayers();
		MasterLooterFrame:SetPoint("TOPLEFT", DropDownList1, 0, 0);
	end
end

SLASH_KLENTRY1, SLASH_KLENTRY2 = "/kl", "/karmaloot"
SLASH_KLROLL1, SLASH_KLROLL2 = "/kroll", "/klroll"

SlashCmdList["KLENTRY"] = slashKl
SlashCmdList["KLROLL"] = kRoll

C_Timer.After(20, init)
