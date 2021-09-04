-- BINDINGs labels
BINDING_HEADER_ACE3 = "Ace3"
BINDING_NAME_RELOADUI = "ReloadUI"
--
local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
ldb.callbacks = ldb.callbacks or LibStub("CallbackHandler-1.0"):New(ldb)
local AceGUI = LibStub("AceGUI-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local reg = LibStub("AceConfigRegistry-3.0")
local dialog = LibStub("AceConfigDialog-3.0")
local icon = LibStub("LibDBIcon-1.0")
local ScrollingTable = LibStub("ScrollingTable");
KarmaLoot = LibStub("AceAddon-3.0"):NewAddon("KarmaLoot", "AceConsole-3.0")
local KarmaLoot = KarmaLoot

local selectedgroup
local frame
local select
local status = {}
local configs = {}

local _, ns = ...
local version = GetAddOnMetadata("KarmaLoot", "Version")
local authors = GetAddOnMetadata("KarmaLoot", "Author")
local memberKarma = {}
local currentRaidKarma = {}
local memberRowHeight = 12
local defaultWindowHeight = 70
local karmaFrameWidth = 105
local playerName = UnitName("player") .. "-" .. GetRealmName()
local initialized = false
local frameReady = false
local leaderBoardReady = false
local frameShown = false
local mmHidden = false
local tgtConfirmation = false
local rollMsg = "KL: Please roll on "
local rollsOpen = false
local highestRoll = 0
local highestRoller = ""
local rollers = {}
local deadlock = false
local masterLootItemSelected = false
local lootSettingsFrameOpen = false
local itemCache = {}
local success = C_ChatInfo.RegisterAddonMessagePrefix("KarmaLoot") -- Addon name.
local backupData = {}
local restoreConfirm = false
local rollFrame = CreateFrame("Frame",nil,UIParent)
local leaderBoardOnLogin = true
local wasFrameToggled = false

local wasKarmaUsed = false
local lastKarmaUser = ""
local numOfBackups = 5
local raidSize = 0
ns.currentPlayer = {}
ns.allRaidersTable = {}

local scrollContainerFrame = AceGUI:Create("SimpleGroup")
local masterLooterContainer = AceGUI:Create("SimpleGroup")


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

-- Populates native interface/addons gui
local karmaLootSettings = {
    name = "KarmaLoot Settings",
    handler = KarmaLoot,
    type = 'group',
    order = 1,
    childGroups = "tab",
    args = {
        LeaderBoardSettings={
            name = "Leaderboard Settings",
            type = "group",
            order = 29,
            args={
                range1 = {
                    name = "Set Leaderboard Width",
                    desc = nil,
                    min = 100,
                    max = 500,
                    type = "range",
                    set = function(info,val)
                        KarmaLoot.db.char.LeaderBoardWidth = val
                        karmaFrame:SetWidth(KarmaLoot.db.char.LeaderBoardWidth)
                    end,
                    get = function(info) return KarmaLoot.db.char.LeaderBoardWidth or karmaFrame:GetWidth() end,
                    order = 2
                },
                range2 = {
                    name = "Set Leaderboard Height",
                    desc = nil,
                    min = 100,
                    max = 600,
                    type = "range",
                    set = function(info,val)
                        KarmaLoot.db.char.LeaderBoardHeight = val
                        karmaFrame:SetHeight(KarmaLoot.db.char.LeaderBoardHeight)
                    end,
                    get = function(info) return KarmaLoot.db.char.LeaderBoardHeight or karmaFrame:GetHeight() end,
                    order = 5
                },
                -- range3 = {
                    --     name = "Set KarmaLoot Scale",
                    --     desc = "This will apply to all KarmaLoot frames.",
                    --     min = 0.5,
                    --     max = 2.0,
                    --     softMin = 0.8,
                    --     type = "range",
                    --     set = function(info,val) KarmaLoot:SetUIScale(info, val) end,
                    --     get = function(info) return KarmaLoot:GetUIScale(info) end,
                    --     order = 4
                -- },
                range4 = {
                    name = "Set Leaderboard Font Size",
                    desc = nil,
                    min = 4,
                    max = 30,
                    bigStep = 1,
                    type = "range",
                    set = function(info,val)
                        KarmaLoot.db.char.FontSize = val
                        title:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", KarmaLoot.db.char.FontSize + (KarmaLoot.db.char.FontSize*.1) or 14)
                        KarmaLoot:updateFrame(false)
                    end,
                    get = function(info) return KarmaLoot.db.char.FontSize or 10 end,
                    order = 10,
                },
                enable = {
                    name = "Show Leaderboard on Login",
                    desc = nil,
                    type = "toggle",
                    set = function(info,val) KarmaLoot.db.char.leaderBoardOnLogin = input end,
                    get = function(info) return KarmaLoot.db.char.leaderBoardOnLogin end,
                    order = 1,
                    width = "full"
                },
                enable2 = {
                    name = "Hide Minimap button",
                    desc = nil,
                    type = "toggle",
                    set = function(info,val) KarmaLoot:minimapButtonHide() end,
                    get = function(info) return KarmaLoot.db.profile.minimap.hide end,
                    order = 2,
                    width = "full"
                },
                enable3 = {
                    name = "Hide Leaderboard in Combat",
                    desc = nil,
                    type = "toggle",
                    set = function(info,val) KarmaLoot.db.profile.leaderboardHideInCombat = val end,
                    get = function(info) return KarmaLoot.db.profile.leaderboardHideInCombat or false end,
                    order = 2,
                    width = "full"
                },
                execute = {
                    name = "Refresh Leaderboard",
                    type = "execute",
                    desc = "Click here if the Leaderboard looks wonky.",
                    func = function() KarmaLoot:updateFrame(false) end,
                    order = 25,
                    width = 3
                },


            }
        },
        raidLeaderSettings={
            name = "Raid Leader Settings",
            type = "group",
            order = 29,
            args={
                range2 = {
                    name = "Award Karma",
                    desc = "How many bosses were killed?",
                    min = 0,
                    max = 10,
                    step = 1,
                    type = "range",
                    set = function(info,val)
                        if val >= 0 then
                            val = (val*3) + 10
                            ns.klEarn(val)
                        end
                    end,
                    order = 5,
                    confirm =
                        function(info, val)
                            if val == 0 then
                                return "You killed zero bosses? Tough break."
                            elseif val == 1 then
                                return "Are you sure you killed " .. val .. " boss?"
                            else
                                return "Are you sure you killed " .. val .. " bosses?"
                            end
                        end,
                    width = 3
                },
                execute = {
                    name = "Check KarmaLoot Versions",
                    type = "execute",
                    func = function() ns.klVersion() end,
                    order = 25,
                    width = 3
                },
            }
        },
        officerSettings = {
            name = "Officer Settings",
            type = "group",
            order = 39,
            hidden = false,
            args={
                execute = {
                    name = "Check Backups",
                    type = "execute",
                    func = function() ns.klBackups() end,
                    order = 25,
                    width = 2
                },
                input = {
                    name = "Restore Backup",
                    type = "input",
                    set =
                    function(info, input)

                        StaticPopupDialogs["KL_RESTORE"] = {
                          text = "Are you sure you'd like to restore the " .. input .. " backup?",
                          button1 = "Yes",
                          button2 = "No",
                          OnAccept = function()
                              ns.klRestore(input)
                              ns.klSay("Backup " .. input .. " has been restored!")
                          end,
                          timeout = 0,
                          whileDead = true,
                          hideOnEscape = true,
                          preferredIndex = 3,
                        }
                        if type(tonumber(input)) == "number" then
                            StaticPopup_Show ("KL_RESTORE")
                        end
                    end,
                    order = 25,
                    width = 1
                },
                execute2 = {
                    name = "Decay Karma",
                    type = "execute",
                    func =
                    function()
                        StaticPopupDialogs["KL_DECAY"] = {
                          text = "Are you sure you'd like to decay everyones Karma by 80 percent?",
                          button1 = "Yes",
                          button2 = "No",
                          OnAccept = function()
                              ns.klDecay(false)
                          end,
                          timeout = 0,
                          whileDead = true,
                          hideOnEscape = true,
                          preferredIndex = 3,
                        }
                        StaticPopup_Show ("KL_DECAY")
                    end,
                    order = 26,
                    width = 3
                },
            }
        },
        createdBy = {
            name = "About",
            type = "group",
            order = 99,
            args={
                description = {
                    name = "Created by: |cff" .. classColors["paladin"].hex .. " Fyfor-Whitemane|r and |cff" .. classColors["priest"].hex .. "|cffffffffRefúge-Whitemane\nVersion: " .. version .. "\nhttps://www.curseforge.com/wow/addons/karmaloot" ,
                    type = "description",
                    order = 100,
                    width = 3
                },
            },

        },

    },
}

AceConfig:RegisterOptionsTable("KarmaLoot", karmaLootSettings, {"/kl"})

-- Update the frame container
-- bool toggle will toggle display of the frame
function KarmaLoot:updateFrame(toggle)
    if scrollContainerFrame:IsVisible() then
        scrollContainerFrame:ReleaseChildren()
    end
    if frameShown and toggle then
        karmaFrame:Hide()
        frameShown = false
    elseif toggle and not frameShown then
        frameShown = true
        karmaFrame:Show()
    end
    if frameShown then
        local scrollcontainer = AceGUI:Create("InlineGroup")
        scrollcontainer:SetLayout("Fill") -- important!

        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("Flow")
        scroll:SetFullWidth(true)
        scrollcontainer:AddChild(scroll)
        local data = ns.updateLeaderboard()
        for k, v in pairs(data) do
            local label = AceGUI:Create("Label")
            label:SetText(v[1])
            label:SetRelativeWidth(0.75)
            label:SetJustifyH("left")
            label:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", self.db.char.FontSize or 10)
            scroll:AddChild(label)

            local label = AceGUI:Create("Label")
            label:SetText(v[2])
            label:SetRelativeWidth(0.25)
            label:SetJustifyH("right")
            label:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", self.db.char.FontSize or 10)
            scroll:AddChild(label)
        end
        scrollContainerFrame:AddChild(scrollcontainer)
        scrollcontainer:SetPoint("TOPLEFT", karmaFrame, "TOPLEFT", -3,19)
        scrollcontainer:SetPoint("BOTTOMRIGHT", karmaFrame, "BOTTOMRIGHT",5,-6)
        scroll:DoLayout()
    end
end

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
            if name then
    			if lookup:lower() == name:lower() then
    				return mi
    			end
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
function ns.updateLeaderboard(printErrorOnNoRaid)
    -- local thing = reg:GetOptionsTable("KarmaLoot", "toggle", "LibDataBroker-1.1")
    -- print(thing)
    local guildSize = GetNumGuildMembers()
    local data = {}
    currentKarma = {}

    if not IsInGroup() and guildSize > 0 then
        for rIx = 1, GetNumGuildMembers(), 1 do
            local name, _, _, _, class = GetGuildRosterInfo(rIx)
            if name then
                local member = {name = name, karma = ns.getKarma(rIx), class = class, eligible = 0}
                table.insert(currentKarma, member)
            end
        end
    elseif IsInGroup() then
        for rIx = 1, GetNumGroupMembers(), 1 do
            local name, rank, subgroup, level, class = GetRaidRosterInfo(rIx)
            if name then
                local playerRosterIx = ns.findPlayerRosterIx(name)
                if playerRosterIx > -1 then
                    local member = {name = name, karma = ns.getKarma(playerRosterIx), class = class, eligble = 0}
                    table.insert(currentKarma, member)
                end
            end
        end
    end
    table.sort(currentKarma, function(a, b)
        return a.karma > b.karma
    end)

    for rTableIx = 1, tablelength(currentKarma), 1 do
        local member = currentKarma[rTableIx];
        local numberColor = 'FFFFFF';
        if IsInGroup() then
            local fullName = member.name .. '-' .. GetRealmName();
            if fullName == ns.currentPlayer.name then
                numberColor = '00FF00';
            end
        elseif not IsInGroup() and member.name == ns.currentPlayer.name then
             numberColor = '00FF00';
        end

        member.name = ns.strSplit(member.name, "-")
        if member.karma ~= 0  then
            table.insert(data, {'|cFF'.. classColors[member.class:lower()].hex ..member.name[1], '|cFF' .. numberColor ..tostring(member.karma)}  )
        end
    end
    return data
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
			itemId, _, _, _, _, _, _ = GetItemInfoInstant(msg)
			SendChatMessage(chatMsg, "RAID_WARNING")
			rollsOpen = true
            C_ChatInfo.SendAddonMessage("KarmaLoot", "openRolls:" .. itemId, "RAID");
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
            local chatMsg = "KL: Nobody used their Karma! Please free roll for " .. itemCache.itemLink .. "."
            SendChatMessage(chatMsg, "RAID_WARNING")
        elseif rollsOpen == true then
            rollsOpen = false
            wasKarmaUsed = false
            if highestRoll > 0 then
                local chatMsg = highestRoller .. " has won " .. itemCache.itemLink .. " with a roll of " .. highestRoll .. "!"
                SendChatMessage(chatMsg, "RAID_WARNING")
                C_ChatInfo.SendAddonMessage("KarmaLoot", "closeRolls", "RAID");
            end
            highestRoll = 0
            rollers = {}
            itemCache = {}
            return true
        else
            ns.klSay("There's nothing to close.")
        end
    else
        ns.klSay("You must be in a |cff00FF96raid|r, a |cff00FF96loot master|r and, at |cff00FF96minimum|r, be a |cff00FF96raid assistant|r to use this command!")
    end
end

-- Closes rolls if disenchanting the item
function KarmaLoot:disenchantClose()
    if ns.canOpenRolls() then
        C_ChatInfo.SendAddonMessage("KarmaLoot", "closeRolls", "RAID");
        local chatMsg = "KL: " .. itemCache.itemLink .. " is getting disenchanted by " .. self.db.char.disenchanter .. "."
        SendChatMessage(chatMsg, "RAID_WARNING")
        rollsOpen = false
        highestRoll = 0
        rollers = {}
        itemCache = {}
    end
end

-- Checks item index and gives item at that index to whomever is supposed to get it
function KarmaLoot:giveLoot(lootCache)
    local itemFound = false
    masterLootItemSelected = false
    -- Update item index if it changes for whatever reason
    for i = 1, GetNumLootItems() do
        if GetLootSlotLink(i) == lootCache.itemLink then
            lootCache.itemIndex = i
            itemFound = true
            break
        end
    end
    if itemFound then
        for i = 1, GetNumGroupMembers() do
            local candidate = GetMasterLootCandidate(lootCache.itemIndex, i)
            local member = GetRaidRosterInfo(i)
            if candidate == highestRoller and highestRoll > 0 then
                GiveMasterLoot(lootCache.itemIndex, i)
            elseif highestRoll == 0 and candidate == self.db.char.disenchanter then
                GiveMasterLoot(lootCache.itemIndex, i)
            end

        end
    else
        ns.klSay(itemCache.itemLink .. " was not found! Are you looting the correct mob?")
    end
end

-- Main master looter frame function. Creates the frame that the master looter
-- will see when selecting items or opening rolls on said items.
function KarmaLoot:MasterLooter()
    local disenchanter = self.db.char.disenchanter
    for i = 1, GetNumLootItems() do
        local itemName
        local itemID
        local itemIcon
        -- Get each item name and link
        local itemLink = GetLootSlotLink(i)
        if itemLink then -- In case there's gold/silver/copper in the loot table
            itemName = GetItemInfo(itemLink)
            itemID = GetItemInfoInstant(itemLink)
            itemIcon = GetItemIcon(itemID)
        end

        -- Match the item name to whatever the master looter has selected
        -- If it matches, allow starting rolls on it
        if itemName == LootFrame.selectedItemName then
            itemCache = { itemName = itemName, itemLink = itemLink, itemIndex = i}
            if f == nil and not masterLootItemSelected then
                masterLootItemSelected = true
                local f = AceGUI:Create("SimpleGroup")
                masterLooterContainer:AddChild(f)
                f:SetPoint("TOP", UIParent, "TOP", 0, -10)
                f:SetWidth(MasterLooterFrame:GetWidth())
                local b = AceGUI:Create("Button")
                function b:beginRolls(toggle)
                    local function addCloseButtons()
                        f:ReleaseChildren()
                        local label = AceGUI:Create("Label")
                        label:SetText(itemCache.itemLink)
                        label:SetJustifyH("MIDDLE")
                        label:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 14)
                        label:SetImage(itemIcon)
                        label:SetImageSize(50,50)
                        label:SetRelativeWidth(1)
                        local karmaB = AceGUI:Create("Button")
                        karmaB:SetText("Karma")
                        karmaB:SetCallback("OnClick", function()
                            if wasKarmaUsed then
                                if MasterLooterFrame:IsShown() then
                                    masterLooterContainer:ReleaseChildren()
                                    KarmaLoot:giveLoot(itemCache)
                                    ns.klClose()
                                    ns.klWin(highestRoller)
                                    rollFrame:Hide()
                                else
                                    ns.klSay("You need to have the Master Loot frame visible to continue. Loot the mob, select the item you'd like to distribute, and try again.")
                                end
                            else
                                ns.klSay("Karma wasn't used for " .. itemCache.itemLink)
                            end
                        end)
                        karmaB:SetRelativeWidth(1)
                        local regB = AceGUI:Create("Button")
                        regB:SetText("Standard")
                        regB:SetCallback("OnClick", function()
                            if MasterLooterFrame:IsShown() then
                                if highestRoll > 0 then
                                    masterLooterContainer:ReleaseChildren()
                                    KarmaLoot:giveLoot(itemCache)
                                end
                                ns.klClose()
                            else
                                ns.klSay("You need to have the Master Loot frame visible to continue. Loot the mob, select the item you'd like to distribute, and try again.")
                            end
                        end)
                        regB:SetRelativeWidth(1)

                        local disB = AceGUI:Create("Button")
                        disB:SetText("Disenchanter: " .. ns.prependClassColor(disenchanter) or "None Selected")
                        disB:SetCallback("OnClick", function()
                            masterLooterContainer:ReleaseChildren()
                            KarmaLoot:giveLoot(itemCache)
                            KarmaLoot:disenchantClose()
                        end)
                        disB:SetRelativeWidth(1)
                        f:AddChild(label)
                        f:AddChild(karmaB)
                        f:AddChild(regB)
                        f:AddChild(disB)
                    end
                    if toggle then
                        b:SetCallback("OnClick", function()
                            addCloseButtons()
                            ns.klItem(itemCache.itemLink)
                        end)
                    else
                        addCloseButtons()
                    end
                end
                b:SetText("Begin rolls on " .. itemCache.itemLink)
                b:SetRelativeWidth(1)
                f:AddChild(b)
                local cancelBtn = AceGUI:Create("Button")
                cancelBtn:SetText("|cffFF0000Cancel")
                cancelBtn:SetCallback("OnClick", function()
                    masterLooterContainer:ReleaseChildren()
                    masterLootItemSelected = false
                end)
                cancelBtn:SetRelativeWidth(1)
                f:AddChild(cancelBtn)

                if not rollsOpen then
                    b:beginRolls(true)
                else
                    b:beginRolls(false)
                end
            end
        elseif LootFrame.selectedItemName ~= itemCache.itemName and rollsOpen then
            ns.klSay("You have already begun rolling on " .. itemCache.itemLink .. ". Please award that item to a member of the raid before continuing.")
        end
    end
end


-- Creates a frame to determine loot settings for a raid. All settings are sent
-- to other members of the raid to update their end. More settings to come.
function KarmaLoot:OpenLootSettings()
    local raidRosterTable = {}
    local disenchanterExists = false
    if not lootSettingsFrameOpen then
        local f = AceGUI:Create("Frame")
        f:SetTitle("Loot Settings")
        f:SetCallback("OnClose", function(widget)
            AceGUI:Release(widget)
            lootSettingsFrameOpen = false
        end)
        f:SetLayout("List")
        f:SetWidth(400)
        f:SetHeight(200)
        f:EnableResize(false)
        lootSettingsFrameOpen = true

        -- Scold checkbox
        local scoldCheckbox = AceGUI:Create("CheckBox")
        scoldCheckbox:SetLabel("Scold")
        scoldCheckbox:SetDescription("Send a warning to anyone who uses fake roll values while we're rolling for loot")
        scoldCheckbox:SetValue(self.db.char.scold or true)
        scoldCheckbox:SetCallback("OnValueChanged", function(_, _, value)
            self.db.char.scold = value
            C_ChatInfo.SendAddonMessage("KarmaLoot", 'Scold:' .. tostring(self.db.char.scold), "RAID");
        end)
        scoldCheckbox:SetRelativeWidth(1)
        f:AddChild(scoldCheckbox)

        -- Nice checkbox
        local niceCheckbox = AceGUI:Create("CheckBox")
        niceCheckbox:SetLabel("Nice")
        niceCheckbox:SetValue(self.db.char.nice or true)
        niceCheckbox:SetDescription("Allow 69 to win if Karma isn't used")
        niceCheckbox:SetCallback("OnValueChanged", function(_, _, value)
            self.db.char.nice = value
            C_ChatInfo.SendAddonMessage("KarmaLoot", 'Nice:' .. tostring(self.db.char.nice), "RAID");
        end)
        niceCheckbox:SetRelativeWidth(1)
        f:AddChild(niceCheckbox)


        -- Loot threshold dropdown
        local lootThresholdDropdown = AceGUI:Create("Dropdown")
        lootThresholdDropdown:SetLabel("Loot Threshold")
        if GetLootThreshold() == 2 then
            lootThresholdDropdown:SetText("|cff" .. qualityColors.uncommon.hex .. "Uncommon")
        elseif GetLootThreshold() == 3 then
            lootThresholdDropdown:SetText("|cff" .. qualityColors.rare.hex .. "Rare")
        elseif GetLootThreshold() == 4 then
            lootThresholdDropdown:SetText("|cff" .. qualityColors.epic.hex .. "Epic")
        end
        lootThresholdDropdown:AddItem(2, "|cff" .. qualityColors.uncommon.hex .. "Uncommon")
        lootThresholdDropdown:AddItem(3, "|cff" .. qualityColors.rare.hex .. "Rare")
        lootThresholdDropdown:AddItem(4, "|cff" .. qualityColors.epic.hex .. "Epic")

        lootThresholdDropdown:SetCallback("OnValueChanged", function(key, callback, index)
            SetLootThreshold(index)
        end)

        f:AddChild(lootThresholdDropdown)


        -- Disenchanter dropdown
        local disenchanterDropdown = AceGUI:Create("Dropdown")
        disenchanterDropdown:SetLabel("Disenchanter")
        for i = 1, GetNumGroupMembers() do
            name = GetRaidRosterInfo(i)
            if name == self.db.char.disenchanter then
                disenchanterExists = true
            end
            table.insert(raidRosterTable, name)
            disenchanterDropdown:AddItem(i, ns.prependClassColor(name))
        end
        disenchanterDropdown:SetCallback("OnValueChanged", function(key, callback, index)
            self.db.char.disenchanter = raidRosterTable[index]
            C_ChatInfo.SendAddonMessage("KarmaLoot", 'Disenchanter:' .. self.db.char.disenchanter, "RAID");
        end)
        if not disenchanterExists then
            self.db.char.disenchanter = nil
        end
        disenchanterDropdown:SetText(ns.prependClassColor(self.db.char.disenchanter) or "None")
        f:AddChild(disenchanterDropdown)


    end
end

-- Event listeners
local frame, events = CreateFrame("Frame"), {};
function events:ADDON_LOADED(...)
    self:UnregisterEvent("ADDON_LOADED")
    frameReady = true
end
function events:CHAT_MSG_ADDON(...)
    local prefix, msg, type, sender = ...
    local realmName = "-" .. GetRealmName()
    sender = sender:gsub(realmName, '')
    local parts = ns.strSplit(msg, ":")
    local cmd = parts[1]

    if msg == "refresh" then
        GuildRoster()
    elseif cmd == "pass" then
        ns.displayPassMsg(parts[2])
    elseif msg == "Version?" then -- Gets initial version request, and responds with version number
        C_ChatInfo.SendAddonMessage("KarmaLoot", version, "RAID")
    elseif msg == version then -- Receives version number from above if statement and checks for differences
        for k, v in pairs(ns.allRaidersTable) do
            if v == sender then
                table.remove(ns.allRaidersTable, k)
                break;
            end
        end
    elseif cmd == "Disenchanter" then
        KarmaLoot.db.char.disenchanter = parts[2]
    elseif cmd == "Scold" then
        if parts[2] == "false" then
            KarmaLoot.db.char.scold = false
        elseif parts[2] == "true"  then
            KarmaLoot.db.char.scold = true
        end
    elseif cmd == "openRolls" then
        rollsOpen = true
        maximizeRollFrame()
        ns.updateLeaderboard(true)
        karmaRollFrameDataLoad(parts[2])
    elseif cmd == "closeRolls" then
        rollsOpen = false
        highestRoll = 0
        rollers = {}
        itemCache = {}
        rollFrame:Hide()
        highestRoll = 0
        highestRoller = ""
        rollers = {}
        maximizeRollFrame()
    end
end
function events:GUILD_ROSTER_UPDATE(...)
    if initialized and frameReady then
        ns.loadMemberKarma()
        KarmaLoot:updateFrame(false)
    end
end
function events:RAID_ROSTER_UPDATE(...)
    if initialized and frameReady then
        KarmaLoot:updateFrame(false)
    end
end
function events:CHAT_MSG_SYSTEM(...)
    if initialized and frameReady then
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
                        if UnitIsGroupLeader("Player") and KarmaLoot.db.char.scold then
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
                        elseif tonumber(rollResult) == 69 and not ns.wasKarmaUsed and KarmaLoot.db.char.nice then
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
end
function events:PLAYER_LOGOUT(...)
    if initialized and frameReady then
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
end
function events:LOOT_OPENED(...)

    if initialized and frameReady then
        masterLootTicker = C_Timer.NewTicker(1, function()
            if MasterLooterFrame:IsShown() then
                if GetNumLootItems() > 0 then
                    masterLootTicker:Cancel()
                    KarmaLoot:MasterLooter()
                end
            end
        end)
    end
end
function events:PLAYER_REGEN_DISABLED(...)
    if KarmaLoot.db.profile.leaderboardHideInCombat and frameShown then
        KarmaLoot:updateFrame(true)
        wasFrameToggled = true
    end
end
function events:PLAYER_REGEN_ENABLED(...)
    if KarmaLoot.db.profile.leaderboardHideInCombat and wasFrameToggled then
        KarmaLoot:updateFrame(true)
        wasFrameToggled = true
    end
end
function events:PARTY_LOOT_METHOD_CHANGED(...)
    if ns.canOpenRolls() and not lootSettingsFrameOpen then
        KarmaLoot:OpenLootSettings()
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    events[event](self, ...);
end);

for k, v in pairs(events) do
    frame:RegisterEvent(k); -- Register all events for which handlers have been defined
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
function KarmaLoot:main()
    ns.loadMemberKarma(true)
    leaderBoardReady = true
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
        C_Timer.After(1, function()
            waitForGuildApiReady(attempts)
        end)
    end
    if memberCount > 0 then
        KarmaLoot:main()
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

--LibDBIcon stuff for minimap button
local karmaLDB = LibStub("LibDataBroker-1.1"):NewDataObject("karmaLDB", {
    type = "data source",
    text = "Minimap Button",
    icon = "Interface\\Addons\\KarmaLoot\\textures\\karmadicemmbtn.blp",
    OnTooltipShow = function(tooltip)
		tooltip:AddLine("|cFF00FF96KarmaLoot v" .. version)
        tooltip:AddLine("Left Click: |cffffffffShow/Hide Leaderboard")
        tooltip:AddLine("Right Click: |cffffffffOpen Settings")
        if ns.canOpenRolls() or ns.isPlayerLeader() or UnitIsGroupAssistant("Player") then
            tooltip:AddLine("Middle Click: |cffffffffOpen Loot Settings")
        end
	end,
    OnClick = function(button, down)
        if leaderBoardReady and down == "LeftButton" then
        	KarmaLoot:updateFrame(true)
        elseif down == "RightButton" then
            -- Gotta fire it twice cause blizzard
            InterfaceOptionsFrame_OpenToCategory("KarmaLoot")
            InterfaceOptionsFrame_OpenToCategory("KarmaLoot")
        elseif down == "MiddleButton" then
            if ns.canOpenRolls() or ns.isPlayerLeader() or UnitIsGroupAssistant("Player") then
                KarmaLoot:OpenLootSettings()
            end
        end
    end,})
local icon = LibStub("LibDBIcon-1.0")

function KarmaLoot:minimapButtonHide()
    self.db.profile.minimap.hide = not self.db.profile.minimap.hide
    if self.db.profile.minimap.hide then
        icon:Hide("karmaMinimapButton")
    else
        icon:Show("karmaMinimapButton")
    end
end

function KarmaLoot:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("KarmaLootDB",{ profile = { minimap = { hide = false, }, }, })
    icon:Register("karmaMinimapButton", karmaLDB, self.db.profile.minimap)

    karmaFrame = ns.standardFrameBuilder("karmaFrame", UIParent, self.db.char.LeaderBoardWidth or 150, self.db.char.LeaderBoardHeight or 200, "BACKGROUND", KL_Settings.FramePosRelativePoint, KL_Settings.FramePosX, KL_Settings.FramePosY, true)
    karmaFrame:SetBackdropColor(0.1,0.1,0.1,.7);
    title = ns.standardFontStringBuilder("karmaTitle", "BOTTOM", karmaFrame, "karmaFrame", "TOP", 0, 2, "|cff00FF96Karma Leaderboard", 14)
    versionText = ns.standardFontStringBuilder("versionText", "TOPRIGHT", karmaFrame, "karmaFrame", "BOTTOMRIGHT", 0, -5, "|cff00FF96v" .. version, 8)
    karmaFrame:Hide()
    dialog:AddToBlizOptions("KarmaLoot")

    karmaFrame:SetScale(self.db.char.UIScale or karmaFrame:GetScale())
    if self.db.char.leaderBoardOnLogin then
        KarmaLoot:updateFrame(true)
        karmaFrame:Show()
    end
end



init()
