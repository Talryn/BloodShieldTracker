local _G = getfenv(0)
local ADDON_NAME, addon = ...

local tostring = _G.tostring
local type = _G.type

local LSM = _G.LibStub:GetLibrary("LibSharedMedia-3.0")

local function IsFrame(frame)
	if frame and type(frame) == "string" then
		local f = _G.GetClickFrame(frame)
		if f and type(f) == "table" and f.SetPoint and f.GetName then
			return true
		end
	end
	return false
end

addon.FrameNames = {
	["Compact Runes"] = "CompactRunes_RunicPowerBar",
}

local Bar = {}
-- Define a generic class for the bars
Bar.__index = Bar
addon.Bar = Bar

function Bar:Create(name, friendlyName, hasTimeRemaining, disableAnchor)
  local object = _G.setmetatable({}, Bar)
	object.name = name
	object.friendlyName = friendlyName or name
	object.anchorTries = 0
	object.hasTimeRemaining = hasTimeRemaining
	object:Initialize()
	-- Add the bar to the addon's table of bars
	addon.bars[name] = object
	if disableAnchor ~= false then
		addon.FrameNames[object.friendlyName] = object.bar:GetName()
	end
	object:UpdatePosition()
	return object
end

function Bar:Initialize()
	self.db = addon.db.profile.bars[self.name]
  self.frameName = ADDON_NAME.."_"..self.name
  local bar = _G.CreateFrame("StatusBar", self.frameName, _G.UIParent)
	self.bar = bar
	bar.object = self
  --bar:SetPoint("CENTER", _G.UIParent, "CENTER", self.db.x, self.db.y)
	bar:SetScale(self.db.scale)
  bar:SetOrientation("HORIZONTAL")
  bar:SetWidth(self.db.width)
  bar:SetHeight(self.db.height)
	local bt = LSM:Fetch("statusbar", self.db.texture)
  bar:SetStatusBarTexture(bt)
  bar:GetStatusBarTexture():SetHorizTile(false)
  bar:GetStatusBarTexture():SetVertTile(false)
  local bc = self.db.color
  bar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetTexture(bt)
  bar.bg:SetAllPoints(true)
  local bgc = self.db.bgcolor
  bar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
  bar.border = bar:CreateTexture(nil, "BACKGROUND")
  bar.border:SetPoint("CENTER")
  bar.border:SetWidth(bar:GetWidth()+9)
  bar.border:SetHeight(bar:GetHeight()+8)
  bar.border:SetTexture("Interface\\Tooltips\\UI-StatusBar-Border")
	if not self.db.border then
		bar.border:Hide()
	end
	local font = LSM:Fetch("font", addon.db.profile.font_face)
    bar.value = bar:CreateFontString(nil, "OVERLAY")
    bar.value:SetPoint("CENTER")
    bar.value:SetFont(font, 
		addon.db.profile.font_size, 
		addon:GetFontFlags())
    bar.value:SetJustifyH("CENTER")
    bar.value:SetShadowOffset(1, -1)
    local tc = self.db.textcolor
    bar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    bar.value:SetText("0")
    bar.lock = false

	if self.hasTimeRemaining then
	    bar.time = bar:CreateFontString(nil, "OVERLAY")
	    bar.time:SetPoint(self.db.time_pos or "RIGHT")
	    bar.time:SetFont(font, 
			addon.db.profile.font_size, 
			addon:GetFontFlags())
	    bar.time:SetJustifyH(self.db.time_pos or "RIGHT")
	    bar.time:SetShadowOffset(1, -1)
	    bar.time:SetTextColor(tc.r, tc.g, tc.b, tc.a)
	    bar.time:SetText("0")
	    if self.db.show_time then
	        bar.time:Show()
	    else
	        bar.time:Hide()
	    end
	end

	if self.name == "EstimateBar" then
	    bar.stacks = bar:CreateFontString(nil, "OVERLAY")
	    bar.stacks:SetPoint(self.db.stacks_pos or "LEFT")
	    bar.stacks:SetFont(font, 
			addon.db.profile.font_size, 
			addon:GetFontFlags())
	    bar.stacks:SetJustifyH(self.db.stacks_pos or "LEFT")
	    bar.stacks:SetShadowOffset(1, -1)
	    bar.stacks:SetTextColor(tc.r, tc.g, tc.b, tc.a)
	    bar.stacks:SetText("0")
		self:UpdateVisibility()
	end

    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart",
        function(self, button)
			if not self.lock then
            	self:StartMoving()
			end
        end)
    bar:SetScript("OnDragStop",
        function(self)
            self:StopMovingOrSizing()
			local scale = self:GetEffectiveScale() / _G.UIParent:GetEffectiveScale()
			local x, y = self:GetCenter()
			x, y = x * scale, y * scale
			x = x - _G.GetScreenWidth()/2
			y = y - _G.GetScreenHeight()/2
			x = x / self:GetScale()
			y = y / self:GetScale()
			self.object.db.x, self.object.db.y = x, y
			self:SetUserPlaced(false);
        end)
    bar:EnableMouse(true)
	bar.duration = 1
    bar:SetMinMaxValues(0, bar.duration)
    bar:SetValue(1)
    bar:Hide()
	self:Lock(self.db.locked)

	if self.name == "HealthBar" or self.name == "EstimateBar" then
		self.altcolor = false
	end

	if self.name == "ShieldBar" then
		self.shield_curr = 0
		self.shield_max = 0
	    self.expires = 0
	    self.active = false
	elseif self.name == "BloodChargeBar" or self.name == "BoneShieldBar" 
		or self.name == "BoneWallBar" then
		self.bar.active = false
		self.bar.timer = 0
		self.bar.count = 0
	elseif self.name == "AMSBar" then
		self.bar.active = false
		self.bar.timer = 0
	--elseif self.name == "EstimateBar" then
	--	self:UpdateEstimateBarText(dsHealMin)
	end
	if self.name == "BoneShieldBar" then
		self.bar.recharge = 0
	end
end

function Bar:UpdateVisibility()
	if self.name == "HealthBar" then
        if not self.db.enabled or 
			(self.db.hide_ooc and (not _G.InCombatLockdown() or addon.idle)) then
            if self.bar:IsVisible() then
                self.bar:Hide()
            end
        else
            self.bar:Show()
        end
	elseif self.name == "EstimateBar" then
		if self.db.enabled and addon:IsTrackerEnabled() and
			(not self.db.hide_ooc or _G.InCombatLockdown()) then
			self.bar:Show()
		else
			self.bar:Hide()
		end

		if self.db.enabled and self.db.show_stacks and addon.IsBloodTank then
		    self.bar.stacks:Show()
		else
		    self.bar.stacks:Hide()
		end
	elseif self.name == "BoneShieldBar" or self.name == "BoneWallBar" then
		if not self.db.enabled or not addon.IsBloodTank then
			self.bar:Hide()
			self.bar:SetScript("OnUpdate", nil)
		end
	else
		if not self.db.enabled then
			self.bar:Hide()
		end
	end
end

function Bar:Hide()
	if addon.configMode then return end
	
	self.bar:Hide()
end

function Bar:Lock(locked)
	if locked == nil then
		locked = self.db.locked
	end

	self.bar.lock = locked
    if locked then
        self.bar:EnableMouse(false)
    else
        self.bar:EnableMouse(true)
    end
end

function Bar:SetValue(value)
	if self.db.enabled then
		self.bar.value:SetText(addon.FormatNumber(value))
	end
end

function Bar:Reset()
	self:Lock()
	self:UpdatePosition()
	self:UpdateTexture()
	self:UpdateBorder()
	self:UpdateUI()
	self:UpdateGraphics()
end

function Bar:UpdatePosition()
	local anchorFrame = addon.FrameNames[self.db.anchorFrame]
	if not anchorFrame and self.db.anchorFrame == "Custom" then
		anchorFrame = self.db.anchorFrameCustom
	end

	self.bar:ClearAllPoints()

	local isFrame = IsFrame(anchorFrame)
	local BST = addon.BloodShieldTracker
	if anchorFrame and isFrame then
		if addon.db.profile.debug then
			BST:Print("Found anchor for bar '"..tostring(self.name).."'.")
		end
		self.bar:SetPoint(
			self.db.anchorPt, anchorFrame, self.db.anchorFramePt, 
			self.db.anchorX, self.db.anchorY)
		self.anchorTries = 0
	else
		self.bar:SetPoint("CENTER", _G.UIParent, "CENTER", self.db.x, self.db.y)
		if anchorFrame and not isFrame and self.anchorTries < 13 then
			if addon.db.profile.debug then
				BST:Print("Waiting for anchor for bar '"..tostring(self.name).."'.")
			end
	    	BST:ScheduleTimer(Bar.UpdatePosition, 5, self)
			self.anchorTries = (self.anchorTries or 0) + 1
		else
			self.anchorTries = 0
		end
	end
end

function Bar:ResetFonts()
	local ff, fh, fontFlags = addon:GetFontSettings()
	self.bar.value:SetFont(ff, fh, fontFlags)						
	self.bar.value:SetText(self.bar.value:GetText())
	if self.hasTimeRemaining then
		self.bar.time:SetFont(ff, fh, fontFlags)
		self.bar.time:SetText(self.bar.time:GetText())
	end
	if self.name == "EstimateBar" then
		self.bar.stacks:SetFont(ff, fh, fontFlags)
		self.bar.stacks:SetText(self.bar.stacks:GetText())
	end
end

function Bar:UpdateUI()
	local show = self.db.shown
	if not show then
		self.bar:SetStatusBarTexture("")
		self.bar.bg:SetTexture("")
		self.bar.border:Hide()
	else
		self:UpdateTexture()
		self:UpdateBorder()
	end
end

function Bar:UpdateBorder()
    local bar = self.bar
	if bar then
	    if addon.CustomUI.showBorders ~= nil then
	        if addon.CustomUI.showBorders == true then
	            bar.border:Show()
            else
                bar.border:Hide()
            end
        else
    		if self.db.border then
    			bar.border:Show()
    		else
    			bar.border:Hide()
    		end
		end
	end
end

function Bar:UpdateTexture()
	if not self.db.shown then
		return
	end

	local bt
    if addon.CustomUI.texture then
        bt = addon.CustomUI.texture
    else
	    bt = LSM:Fetch("statusbar", self.db.texture)
    end
	self.bar:SetStatusBarTexture(bt)
	self.bar.bg:SetTexture(bt)
    self.bar:GetStatusBarTexture():SetHorizTile(false)
    self.bar:GetStatusBarTexture():SetVertTile(false)
	self:UpdateGraphics()
end

function Bar:UpdateGraphics()
    local bc, bgc, tc

	if self.altcolor then
	    bc = self.db.alt_color
	    bgc = self.db.alt_bgcolor
	    tc = self.db.alt_textcolor
	else
	    bc = self.db.color
	    bgc = self.db.bgcolor
	    tc = self.db.textcolor
	end

    self.bar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
    self.bar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
    self.bar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)

	if self.hasTimeRemaining then
	    if self.db.show_time then
	        self.bar.time:Show()
	    else
	        self.bar.time:Hide()
	    end
	    self.bar.time:SetPoint(self.db.time_pos or "RIGHT")
        self.bar.time:SetTextColor(tc.r, tc.g, tc.b, tc.a)
	end
	if self.name == "EstimateBar" then
		self:UpdateVisibility()
	    self.bar.stacks:SetPoint(self.db.stacks_pos or "LEFT")
        self.bar.stacks:SetTextColor(tc.r, tc.g, tc.b, tc.a)
	end
end
