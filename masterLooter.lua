local KarmaLoot, ns = ...
local buttonSize = 32
local masterLootFrameHeight = 100
local selectedPlayer = ""
local selectedPlayerBool = false
ns.disenchanter = ""
ns.scold = true
ns.nice = true


local function addItemToRightClickMenu(unitid)
    if ns.canOpenRolls() then
        for i = 1, #UnitPopupMenus["SELF"] do
            if UnitPopupMenus["SELF"][i] == "ADD_DISENCHANTER" then
                tremove(UnitPopupMenus["SELF"], i)
            end
        end
        if unitid == "player" and UnitExists("target") and UnitIsPlayer("target") then
            for i = 1, #UnitPopupMenus["RAID_PLAYER"] do
                if UnitPopupMenus["RAID_PLAYER"][i] == "ADD_DISENCHANTER" then
                    tremove(UnitPopupMenus["RAID_PLAYER"], i)
                end
            end
            tinsert(UnitPopupMenus["RAID_PLAYER"], #UnitPopupMenus["RAID_PLAYER"] - 14, "ADD_DISENCHANTER")
        end
        tinsert(UnitPopupMenus["SELF"], #UnitPopupMenus["SELF"] - 16, "ADD_DISENCHANTER")
    else
        for i = 1, #UnitPopupMenus["SELF"] do
            if UnitPopupMenus["SELF"][i] == "ADD_DISENCHANTER" then
                tremove(UnitPopupMenus["SELF"], i)
            end
        end
        for i = 1, #UnitPopupMenus["RAID_PLAYER"] do
            if UnitPopupMenus["RAID_PLAYER"][i] == "ADD_DISENCHANTER" then
                tremove(UnitPopupMenus["RAID_PLAYER"], i)
            end
        end
    end
end

local function main()
    ns.masterLootFrame = ns.standardFrameBuilder("ns.masterLootFrame", MasterLooterFrame, buttonSize*3, masterLootFrameHeight, "HIGH", "TOPRIGHT", buttonSize*3+5, 0, false)

    ns.openRollsButton = ns.standardButtonBuilder("ns.openRollsButton", ns.masterLootFrame, buttonSize, buttonSize, "BOTTOMLEFT", buttonSize, buttonSize*-1, "Interface/Addons/KarmaLoot/textures/play.blp", "Interface/Addons/KarmaLoot/textures/playHover.blp")

    ns.createButtonTooltips(ns.openRollsButton, "Begin rolling on this item", "ANCHOR_TOP", false)
    local closeKarmaButton = CreateFrame("Button", "closeKarmaButton", ns.masterLootFrame, ns.masterLootFrame)
    closeKarmaButton:Hide()
    closeKarmaButton:SetSize(buttonSize ,buttonSize)
    closeKarmaButton:SetPoint("BOTTOMLEFT", 0, buttonSize*-1)
    closeKarmaButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/closeKarma.blp")
    closeKarmaButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/closeKarmaHover.blp", "BLEND")
    ns.createButtonTooltips(closeKarmaButton, "Karma Win", "ANCHOR_TOP", false)
    closeKarmaButton:RegisterForClicks("AnyUp");

    local closeNormalButton = CreateFrame("Button", "closeNormalButton", ns.masterLootFrame, ns.masterLootFrame)
    closeNormalButton:Hide()
    closeNormalButton:SetSize(buttonSize ,buttonSize)
    closeNormalButton:SetPoint("BOTTOMLEFT", buttonSize, buttonSize*-1)
    closeNormalButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/closeNormal.blp")
    closeNormalButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/closeNormalHover.blp", "BLEND")
    ns.createButtonTooltips(closeNormalButton, "Normal Win", "ANCHOR_TOP", false)
    closeNormalButton:RegisterForClicks("AnyUp");

    local closeDisenchantButton = CreateFrame("Button", "closeDisenchantButton", ns.masterLootFrame, ns.masterLootFrame)
    closeDisenchantButton:Hide()
    closeDisenchantButton:SetSize(buttonSize ,buttonSize)
    closeDisenchantButton:SetPoint("BOTTOMLEFT", buttonSize*2, buttonSize*-1)
    closeDisenchantButton:SetNormalTexture("Interface/Addons/KarmaLoot/textures/closeDisenchant.blp")
    closeDisenchantButton:SetHighlightTexture("Interface/Addons/KarmaLoot/textures/closeDisenchantHover.blp", "BLEND")
    ns.createButtonTooltips(closeDisenchantButton, "Disenchant Win", "ANCHOR_TOP", false)
    closeDisenchantButton:RegisterForClicks("AnyUp");

    ns.openRollsButton:SetScript("OnClick", function()
        --klItem(itemLink)
        ns.openRollsButton:Hide()
        closeKarmaButton:Show()
        closeNormalButton:Show()
        closeDisenchantButton:Show()
        return
    end)

    local disenchanterName = ns.masterLootFrame:CreateFontString("disenchanterName", "ARTWORK", "GameFontNormal")
    disenchanterName:SetPoint("CENTER", "ns.masterLootFrame", "TOP", 0, -15)
    disenchanterName:SetText("Disenchanter:\n|cffffffffNone")
    --disenchanterName:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 14)
    disenchanterName:Show()

    local scoldButton = ns.standardCheckBoxBuilder("scoldButton", ns.masterLootFrame, "TOPLEFT", 5, -30, "Scold", "Enables/Disables whispers upon detection of fake roll values.")
    local niceButton = ns.standardCheckBoxBuilder("niceButton", ns.masterLootFrame, "TOPLEFT", 5, -50, "Nice", "Enables/Disables wins with rolls of 69.")
    local auctionButton = ns.standardCheckBoxBuilder("auctionButton", ns.masterLootFrame, "TOPLEFT", 5, -70, "Covert", "Enables/Disables holding all rolls until master looter closes rolls.")

    --local poop = ns.standardFrameBuilder("poopy", UIParent, 300, 300, "bgPath", "CENTER")
    --ns.CreateBorder(poop)

    ns.CreateBorder(ns.masterLootFrame)
    ns.CreateBorder(ns.openRollsButton)
    ns.CreateBorder(closeKarmaButton)
    ns.CreateBorder(closeNormalButton)
    ns.CreateBorder(closeDisenchantButton)

    ns.skinCheckBox(scoldButton)
    ns.skinCheckBox(niceButton)
    ns.skinCheckBox(auctionButton)

    scoldButton:SetScript("OnClick", function()
        if scoldButton:GetChecked() then
            ns.scold = true
        else
            ns.scold = false
        end
    end);

    scoldButton:SetChecked(true)

    niceButton:SetScript("OnClick", function()
        if niceButton:GetChecked() then
            ns.nice = true
        else
            ns.nice = false
        end
    end);

    niceButton:SetChecked(true)
    --loadingbar = ns.standardStatusBarBuilder(ns.masterLootFrame, "BOTTOM", 0, -20 + buttonSize*-1, math.floor(ns.masterLootFrame:GetWidth()), 20)
end

local myframe = CreateFrame("Frame")

myframe:RegisterEvent("UNIT_TARGET")
myframe:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")

myframe:SetScript("OnEvent", function(_, event, ...)
    myframe[event](myframe, ...)
end)

function myframe:UNIT_TARGET(unitid)
    addItemToRightClickMenu(unitid)
    if ns.canOpenRolls() then
        ns.masterLootFrame:Show()
    else
        ns.masterLootFrame:Hide()
    end
end

function myframe:PARTY_LOOT_METHOD_CHANGED()
    addItemToRightClickMenu()
    if ns.canOpenRolls() then
        ns.masterLootFrame:Show()
    else
        ns.masterLootFrame:Hide()
    end
end



UnitPopupButtons["ADD_DISENCHANTER"] = {
	text = "Promote to Disenchanter",
	dist = 0,
	func = function()
        ns.disenchanter = selectedPlayer
        selectedPlayer = ns.prependClassColor(selectedPlayer)
        disenchanterName:SetText("Disenchanter:\n" .. selectedPlayer)
	end
}

function Assignfunchook(dropdownMenu, which, unit, name, userData, ...)
	for i=1, UIDROPDOWNMENU_MAXBUTTONS do
		local button = _G["DropDownList"..UIDROPDOWNMENU_MENU_LEVEL.."Button"..i];
        for i = 0, GetNumGroupMembers(), 1 do
            local member = GetRaidRosterInfo(i)
            if member == button.value and member ~= nil then
                selectedPlayer = button.value
            end
        end
        if button.value == "ADD_DISENCHANTER" then
	       button.func = UnitPopupButtons["ADD_DISENCHANTER"].func
		end
	end
end

hooksecurefunc("UnitPopup_ShowMenu", Assignfunchook)
main()
