local KarmaLoot, ns = ...
local skinCheckBox = true

function ns.standardFrameBuilder(name, parent, width, height, strata, setPoint, x, y, draggable)
    local f = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetWidth(width)
    f:SetHeight(height)
    f:SetFrameStrata(strata)
    local texture = f:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background.blp")
    texture:SetAllPoints(f)
    f.texture = texture
    if setPoint then
        f:SetPoint(setPoint, x, y)
    end
    if draggable then
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
    end
    f:Show()
    return f
end

function ns.standardButtonBuilder(name, parent, width, height, setPoint, x, y, texture, highlightTexture)
    local f = CreateFrame("Button", "f", parent)
    f:Hide()
    f:SetSize(width,height)
    f:SetPoint(setPoint, x, y)
    f:SetNormalTexture(texture)
    f:SetHighlightTexture(highlightTexture, "BLEND")
    --createButtonTooltips(f, "Begin rolling on this item", "ANCHOR_TOP", false)
    f:RegisterForClicks("AnyUp");
    return f
end

-- Builds and displays the loot roll frame when needed
function ns.createButtonTooltips(f, text, position, item)
	f:HookScript("OnEnter", function()
		GameTooltip:SetOwner(f, position)
		if item then
			GameTooltip:SetHyperlink(text)
		else
			GameTooltip:SetText(text)
		end
		GameTooltip:Show()
	end)

	f:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

function ns.standardCheckBoxBuilder(name, parent, setPoint, x, y, text, tooltip)
    local f = CreateFrame("CheckButton", name , parent, "ChatConfigCheckButtonTemplate");
    f:SetPoint(setPoint, x, y);
    f.tooltip = tooltip;
    f.text = text
    _G[f:GetName() .. 'Text']:SetText(text)
    _G[f:GetName() .. 'Text']:SetPoint("TOP", 0, -7)
    f:SetHitRectInsets(0, 0, 0, 0);
    --getglobal(f:GetName() .. 'Text'):SetText(text);
    --getglobal(f:GetName() .. 'Text'):SetPoint(parent, 0, -2)
    return f
end

function ns.standardFontStringBuilder(name, setPoint1, parent, parentString, setPoint2, x, y, text)
    local f = parent:CreateFontString(name, "ARTWORK", "GameFontNormal")
    f:SetPoint(setPoint1, parentString, setPoint2, x, y)
    f:SetText(text)
    f:SetFont("Interface/Addons/KarmaLoot/fonts/PTSansNarrow.ttf", 14)
    f:Show()
    return f
end

function ns.standardStatusBarBuilder(parent, setPoint1, x, y, width, height)
    local statusbar = CreateFrame("StatusBar", nil, parent)
    statusbar:SetPoint(setPoint1, parent, x, y)
    statusbar:SetWidth(width)
    statusbar:SetHeight(height)
    statusbar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    statusbar:GetStatusBarTexture():SetHorizTile(false)
    statusbar:GetStatusBarTexture():SetVertTile(false)
    statusbar:SetStatusBarColor(0, 0.65, 0)

    statusbar.bg = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    statusbar.bg:SetAllPoints(true)
    statusbar.bg:SetVertexColor(0, 0.35, 0)

    statusbar.value = statusbar:CreateFontString(nil, "OVERLAY")
    statusbar.value:SetPoint("LEFT", statusbar, "LEFT", 4, 0)
    statusbar.value:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    statusbar.value:SetJustifyH("LEFT")
    statusbar.value:SetShadowOffset(1, -1)
    statusbar.value:SetTextColor(0, 1, 0)
    statusbar.value:SetText("100%")
    return statusbar
end

function ns.skinCheckBox(frame, noBackdrop, noReplaceTextures, frameLevel)
    if IsAddOnLoaded("ElvUI") then
        assert(frame, 'does not exist.')

        if frame.isSkinned then return end

        frame:StripTextures()



        if noBackdrop then
            frame:Size(16)
        else
            frame:CreateBackdrop(nil, nil, nil, nil, nil, nil, nil, frameLevel)
            frame.backdrop:SetInside(nil, 4, 4)
        end

        if not noReplaceTextures then
            if frame.SetCheckedTexture then
                if skinCheckBox then
                    frame:SetCheckedTexture("Interface\\Addons\\KarmaLoot\\textures\\Melli.tga")

                    local checkedTexture = frame:GetCheckedTexture()
                    checkedTexture:SetVertexColor(1, .82, 0, 0.8)
                    checkedTexture:SetInside(frame.backdrop)
                else
                    frame:SetCheckedTexture(check)

                    if noBackdrop then
                        frame:GetCheckedTexture():SetInside(nil, -4, -4)
                    end
                end
            end

            if frame.SetDisabledTexture then
                if skinCheckBox then
                    frame:SetDisabledTexture("Interface\\Addons\\KarmaLoot\\textures\\Melli.tga")

                    local disabledTexture = frame:GetDisabledTexture()
                    disabledTexture:SetVertexColor(.6, .6, .6, .8)
                    disabledTexture:SetInside(frame.backdrop)
                else
                    frame:SetDisabledTexture(disabled)

                    if noBackdrop then
                        frame:GetDisabledTexture():SetInside(nil, -4, -4)
                    end
                end
            end

            frame:HookScript('OnDisable', function(checkbox)
                if not checkbox.SetDisabledTexture then return; end
                if checkbox:GetChecked() then
                    if skinCheckBox then
                        checkbox:SetDisabledTexture("Interface\\Addons\\KarmaLoot\\textures\\Melli.tga")
                    else
                        checkbox:SetDisabledTexture(disabled)
                    end
                else
                    checkbox:SetDisabledTexture('')
                end
            end)

            hooksecurefunc(frame, 'SetNormalTexture', function(checkbox, texPath)
                if texPath ~= '' then checkbox:SetNormalTexture('') end
            end)
            hooksecurefunc(frame, 'SetPushedTexture', function(checkbox, texPath)
                if texPath ~= '' then checkbox:SetPushedTexture('') end
            end)
            hooksecurefunc(frame, 'SetHighlightTexture', function(checkbox, texPath)
                if texPath ~= '' then checkbox:SetHighlightTexture('') end
            end)
            hooksecurefunc(frame, 'SetCheckedTexture', function(checkbox, texPath)
                if texPath == "Interface\\Addons\\KarmaLoot\\textures\\Melli.tga" or texPath == check then return end
                if skinCheckBox then
                    checkbox:SetCheckedTexture("Interface\\Addons\\KarmaLoot\\textures\\Melli.tga")
                else
                    checkbox:SetCheckedTexture(check)
                end
            end)
        end

        frame.isSkinned = true
    end
end

function ns.CreateBorder(self)
    if not self.borders then
        self.borders = {}
        for i=1, 4 do
            self.borders[i] = self:CreateLine(nil, "BACKGROUND", nil, 0)
            local l = self.borders[i]
            l:SetThickness(1)
            l:SetColorTexture(0,0,0, 1)
            if i==1 then
                l:SetStartPoint("TOPLEFT")
                l:SetEndPoint("TOPRIGHT")
            elseif i==2 then
                l:SetStartPoint("TOPRIGHT")
                l:SetEndPoint("BOTTOMRIGHT")
            elseif i==3 then
                l:SetStartPoint("BOTTOMRIGHT")
                l:SetEndPoint("BOTTOMLEFT")
            else
                l:SetStartPoint("BOTTOMLEFT")
                l:SetEndPoint("TOPLEFT")
            end
        end
    end
end
