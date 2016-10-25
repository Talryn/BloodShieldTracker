local _G = getfenv(0)
local ADDON_NAME, addon = ...

local LSM = _G.LibStub:GetLibrary("LibSharedMedia-3.0")

local Bar = {}

-- Table which has pointers to all the bars.
addon.bars = {}

-- Table of possible anchor points.
addon.FrameNames = addon.FrameNames or {}

-- Define a generic class for the bars
Bar.__index = Bar
addon.Bar = Bar

local function IsEnabled(self)
	return self.db.enabled
end

function Bar:UpdateLayoutFunctions(functions)
	if functions then
		for name, func in _G.pairs(functions) do
			if func and _G.type(func) == "function" then
				self[name] = func
			end
		end
		if self.bar then
			self:UpdateVisibility()
		end
	end
end

local function getValueOrDefault(value, default)
	return value == nil and default or value
end

function Bar:Create(settings)
	-- Old params: name, fontAdj, width, height, setPoint, setValuePoint
	local object = _G.setmetatable({}, Bar)
	object.name = settings.name
	object.friendlyName = settings.friendlyName or settings.name
	object.fontAdj = settings.fontAdj or 0
	object.parentFrame = getValueOrDefault(settings.parentFrame, addon.mainFrame or _G.UIParent)
	object.hasBorder = getValueOrDefault(settings.hasBorder, false)
	object.hasOwnTexture = getValueOrDefault(settings.hasOwnTexture, false)
	object.setBarColor = getValueOrDefault(settings.setBarColor, true)
	object.setBkgColor = getValueOrDefault(settings.setBkgColor, true)
	object.setTxtColor = getValueOrDefault(settings.setTxtColor, true)
	object.hideOnDisable = getValueOrDefault(settings.hideOnDisable, true)
	object.updateSetPoint = getValueOrDefault(settings.updateSetPoint, true)
	object.hasSecondaryValue = getValueOrDefault(settings.hasSecondaryValue, false)
	object.movable = getValueOrDefault(settings.movable, true)
	object.secondaryFontAdj = settings.secondaryFontAdj
	object.db = addon.db.profile.bars[settings.name]

	if not object.IsEnabled then
		object.IsEnabled = IsEnabled
	end
	
	if settings.layout and addon.LayoutManager and addon.LayoutManager.RegisterLayout then
		addon.LayoutManager:RegisterLayout(object, settings.layout)
	end

	if settings.width and _G.type(settings.width) ~= "function" then
		object.GetWidth = function() return settings.width end
	end

	if settings.height and _G.type(settings.height) ~= "function" then
		object.GetHeight = function() return settings.height end
	end

	if settings.functions then
		for name, func in _G.pairs(settings.functions) do
			if func and _G.type(func) == "function" then
				object[name] = func
			end
		end
	end

	if not object.SetDesiredPoint then
		object.SetDesiredPoint = function(self) return self:SetPoint() end
	end

	object:Initialize(settings)

	if settings.disableAnchor ~= false then
		addon.FrameNames[object.friendlyName] = object.bar:GetName()
	end

	-- Add the bar to the addon's table of bars
	addon.bars[settings.name] = object
	
	if object.PostInitialize and _G.type(object.PostInitialize) == "function" then
		object:PostInitialize()
	end

	return object
end

function Bar:Initialize(settings)
	local bar = _G.CreateFrame("StatusBar", 
		addon.addonNameCondensed .. "_"  .. self.name, self.parentFrame)
	self.bar = bar
	bar.parent = self
	self.altcolor = false
	bar:SetScale(self.db.scale or 1)
	self.orientation = "HORIZONTAL"
	if self.GetOrientation and _G.type(self.GetOrientation) == "function" then
		self.orientation = self:GetOrientation()
	end
	bar:SetOrientation(self.orientation)
	bar:SetWidth(self:GetWidth())
	bar:SetHeight(self:GetHeight())
	local bt = LSM:Fetch("statusbar", addon.db.profile.texture)
	bar:SetStatusBarTexture(bt)
	bar:GetStatusBarTexture():SetHorizTile(false)
	bar:GetStatusBarTexture():SetVertTile(false)
	if self.setBarColor then
		local bc = self.db.color
		bar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
	end
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetTexture(bt)
	bar.bg:SetAllPoints(true)
	if self.setBkgColor then
		local bgc = self.db.bgcolor
		bar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
	end

	local font, fh, fflags = addon.GetFontSettings()
	bar.value = bar:CreateFontString(nil, "OVERLAY")
	bar.value:SetPoint("CENTER")
	bar.value:SetFont(font, fh + self.fontAdj, fflags)
	bar.value:SetJustifyH("CENTER")
	--bar.value:SetShadowOffset(1, -1)
	local tc = self.db.textcolor
	bar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
	if settings.setValueToZero then
		bar.value:SetText("0")
	end

	if self.hasBorder then
	    bar.border = bar:CreateTexture(nil, "BACKGROUND")
	    bar.border:SetPoint("CENTER")
	    bar.border:SetWidth(bar:GetWidth()+9)
	    bar.border:SetHeight(bar:GetHeight()+8)
	    bar.border:SetTexture("Interface\\Tooltips\\UI-StatusBar-Border")
		self:UpdateBorder()
	end

	if self.hasSecondaryValue then
		bar.secondaryValue = bar:CreateFontString(nil, "OVERLAY")
		bar.secondaryValue:SetPoint("RIGHT")
		bar.secondaryValue:SetFont(font, fh + (self.secondaryFontAdj or self.fontAdj), fflags)
		bar.secondaryValue:SetJustifyH("CENTER")
		local tc = self.db.secondaryTextColor or self.db.textcolor
		bar.secondaryValue:SetTextColor(tc.r, tc.g, tc.b, tc.a)
		bar.secondaryValue:SetText("0")
		bar.secondaryValue:Hide()
		if self.SetSecondaryValuePoint then
			self:SetSecondaryValuePoint()
		end
	end

	if self.SetPoint then self:SetPoint() end
	if self.SetValuePoint then
		self:SetValuePoint()
	else
	    bar.value:SetPoint("CENTER")
	end

	if settings.initTimer then
		bar.active = false
		bar.timer = 0
		bar:Hide()
	end

	if self.db.shown == false then
		self.bar:SetStatusBarTexture("")
		self.bar.bg:SetTexture("")
		self.bar.border:Hide()
	end

	bar.locked = getValueOrDefault(self.db.locked, true)
	bar.updateVisibilityOnLock = settings.updateVisibilityOnLock

	if self.movable then self:SetMovable() end
end

function Bar:Show()
	self.bar:Show()
end

function Bar:Hide()
	if addon.configMode then return end
	self.bar:Hide()
end

function Bar:IsLocked()
	return self.bar.locked
end

function Bar:Lock(locked)
	if locked ~= nil then
		self.bar.locked = locked
	end
	self.bar:EnableMouse(not self.bar.locked)
	if self.updateVisibilityOnLock then
		if not self.bar.locked then
			self.bar:Show()
		elseif not self.bar.active then
			self.bar:Hide()
		end
	end
end

function Bar:SetMovable()
	local bar = self.bar
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart",
        function(self, button)
			if not self.locked then
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
			self.parent.db.x, self.parent.db.y = x, y
			self:SetUserPlaced(false);
        end)
	self:Lock()
end

local numberFmt = "%.0f"
function Bar:SetValue(value)
	self.bar:SetValue(value)
	self.bar.value:SetText(numberFmt:format(value))
end

function Bar:SetValueTextColor(color)
   	local tc = color or self.db.textcolor
   	self.bar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
end

function Bar:Reset()
	self:ResetFonts()
	self:UpdateVisibility()
	--self:UpdateTexture()
	self:UpdateGraphics()
end

function Bar:ResetFonts()
	local font, fh, fontFlags = addon.GetFontSettings()
	self.bar.value:SetFont(font, fh + self.fontAdj, fontFlags)
	self.bar.value:SetText(self.bar.value:GetText())
	if self.hasSecondaryValue and self.bar.secondaryValue then
		self.bar.secondaryValue:SetFont(font, 
			fh + (self.secondaryFontAdj or self.fontAdj), fontFlags)
		self.bar.secondaryValue:SetText(self.bar.secondaryValue:GetText())
	end
end

function Bar:UpdateVisibility()
	if self.GetOrientation and _G.type(self.GetOrientation) == "function" then
		self.orientation = self:GetOrientation()
	end
	self.bar:SetOrientation(self.orientation)
	if self.GetWidth then self.bar:SetWidth(self:GetWidth()) end
	if self.GetHeight then self.bar:SetHeight(self:GetHeight())	end
	if self.SetPoint and self.updateSetPoint then self:SetPoint() end
	if self.SetValuePoint then
		self:SetValuePoint()
	else
		self.bar.value:SetPoint("CENTER")
	end
	if self.hasSecondaryValue then
		if self.SetSecondaryValuePoint then
			self:SetSecondaryValuePoint()
		elseif self.bar.secondaryValue then
			self.bar.secondaryValue:SetPoint("RIGHT")
		end
	end
	if not self.db.enabled and self.hideOnDisable then
		self:Hide()
		self.bar:SetScript("OnUpdate", nil)
	end

	self:UpdateTexture()
end

function Bar:UpdateTexture()
	if self.db.shown == false then return end

	local bt = LSM:Fetch("statusbar", self.hasOwnTexture and 
		self.db.texture or addon.db.profile.texture)
    if addon.CustomUI and addon.CustomUI.texture then
        bt = addon.CustomUI.texture
    end

	self.bar:SetStatusBarTexture(bt)
	self.bar.bg:SetTexture(bt)
	self.bar:GetStatusBarTexture():SetHorizTile(false)
	self.bar:GetStatusBarTexture():SetVertTile(false)
	--self:UpdateGraphics()
end

function Bar:UpdateGraphics()
	local bc, bgc, tc
	if self.altcolor then
		bc = self.db.alt_color or self.db.color
		bgc = self.db.alt_bgcolor or self.db.bgcolor
		tc = self.db.alt_textcolor or self.db.textcolor
	else
		bc = self.db.color
		bgc = self.db.bgcolor
		tc = self.db.textcolor
	end

	if self.setBarColor then
		self.bar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
	end
	if self.setBkgColor then
		self.bar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
	end
	if self.setTxtColor then
		self.bar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
	end
	if self.hasSecondaryValue and self.bar.secondaryValue then
		self.bar.secondaryValue:SetTextColor(tc.r, tc.g, tc.b, tc.a)
	end
end

function Bar:UpdateUI()
	if self.db.shown == false then
		self.bar:SetStatusBarTexture("")
		self.bar.bg:SetTexture("")
		self.bar.border:Hide()
	else
		self:UpdateTexture()
		self:UpdateBorder()
	end
end

function Bar:UpdateBorder()
	if not self.hasBorder then return end
    local bar = self.bar
    if addon.CustomUI and addon.CustomUI.showBorders ~= nil then
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
