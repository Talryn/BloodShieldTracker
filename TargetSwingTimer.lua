local _G = getfenv(0)
local ADDON_NAME, addon = ...
local BST = LibStub("AceAddon-3.0"):GetAddon(addon.addonNameCondensed)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonNameCondensed)

local UnitIsUnit = _G.UnitIsUnit
local UnitGUID = _G.UnitGUID
local GetTime = _G.GetTime
local OffhandHasWeapon = _G.OffhandHasWeapon
local UnitAttackSpeed = _G.UnitAttackSpeed
local select = _G.select
local floor = _G.math.floor
local round = addon.round

local module = {}
module.name = "TargetSwingTimer"
addon:RegisterModule(module.name, module)
module.enabled = false

local MIN_UPDATE_TIME = addon.MIN_UPDATE_TIME
local lastSwingMH, lastSwingOH = nil, nil
local speedMH, speedOH = nil, nil

function module:SetProfile()
	self.profile = addon.db.profile.bars.TargetSwingTimerBar
end

function module.ProfileUpdate()
	module:SetProfile()
end

function module:OnInitialize()
	addon:RegisterCallback("ProfileUpdate", module.name, module.ProfileUpdate)
	self:SetProfile()
end

function module:Enable()
	addon:RegisterCallback("TalentUpdate", module.name, module.TalentUpdate)
	self:Toggle()
end

function module:Disable()
	addon:UnregisterCallback("TalentUpdate", module.name)
	self:OnDisable()
end

function module:Toggle()
	if not addon.isDK then return end
	if self.profile.enabled and self.profile.specs[addon.currentSpec] then
		self:OnEnable()
	else
		self:OnDisable()
	end
end

function module:OnEnable()
	self.eventFrame = self.eventFrame or _G.CreateFrame("frame")
	self.eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self.eventFrame:SetScript("OnEvent", self.EventHandler)
	if not self.targetSwingBar then self:CreateDisplay() end
	self:UpdateDisplay()
	addon:RegisterCallback("PlayerAlive", module.name, module.PlayerAlive)
	addon:RegisterCallback("PlayerDead", module.name, module.PlayerDead)
	addon:RegisterCallback("CombatStart", module.name, module.CombatStart)
	addon:RegisterCallback("CombatEnd", module.name, module.CombatEnd)
	self.enabled = true
end

function module:OnDisable()
	if self.eventFrame then
		self.eventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		self.eventFrame:SetScript("OnEvent", nil)
	end
	self:HideBar()
	addon:UnregisterCallback("PlayerAlive", module.name)
	addon:UnregisterCallback("PlayerDead", module.name)
	addon:UnregisterCallback("CombatStart", module.name)
	addon:UnregisterCallback("CombatEnd", module.name)
	self.enabled = false
end

function module:CreateDisplay()
	self.targetSwingBar = addon.Bar:Create({
		name = "TargetSwingTimerBar",
		friendlyName = "Target Swing Timer Bar",
		initTimer = true,
		hasBorder = true,
		hasOwnTexture = true,
		functions = {
			GetWidth = function(self)
				return self.db.width
			end,
			GetHeight = function(self)
				return self.db.height
			end,
			SetPoint = addon.SetPointWithAnchor,
			PostInitialize = function(self)
				addon.SkinFrame(self.bar)
			end,
		}
	})
	--addon.frames.targetSwingTimerBar = self.targetSwingBar
end

function module:HideBar()
	local bar = module.targetSwingBar
	if not bar then return end
	bar.bar.active = false
	bar.bar.timer = 0
	bar:Hide()
end

function module:UpdateDisplay()
	local bar = self.targetSwingBar
	if not bar then return end
	self:HideBar()
	if self.profile.numericTimer then
		bar.bar.value:Show()
	else
		bar.bar.value:Hide()
	end
end

function module.PlayerAlive()
	module:HideBar()
end

function module.PlayerDead()
	module:HideBar()
end

function module.CombatStart()
	--local bar = module.swingBar
	--if bar then bar:Show() end
end

function module.CombatEnd()
	module:HideBar()
end

function module.TalentUpdate()
	module:Toggle()
end

local timeFmt = "%.1f"
function module.OnUpdate(self, elapsed)
	self.lastUpdate = (self.lastUpdate or 0) + elapsed
	self.timer = self.timer - elapsed
	if self.lastUpdate >= MIN_UPDATE_TIME then
		self.lastUpdate = 0
		if self.active then
			if self.timer < 0 then
				self.timer = 0
				self.active = false
			end
			self:Show()
			self:SetValue(self.timer)
			self.value:SetText(timeFmt:format(self.timer))
		else
			self.value:SetText("0")
			self:Hide()
			self:SetScript("OnUpdate", nil)
		end
	end
end

function module.EventHandler(frame, event, ...)
	local timestamp, eventtype, hideCaster, 
	srcGUID, srcName, srcFlags, srcRaidFlags,
	destGUID, destName, destFlags, destRaidFlags,
	param9, param10, param11, param12, param13, param14, 
	param15, param16, param17, param18, param19, param20 = CombatLogGetCurrentEventInfo()
	local isOffHand = eventtype == "SWING_DAMAGE" and param18 or param10
	
	if srcGUID ~= UnitGUID("target") or destGUID ~= UnitGUID("player") then return end
	if eventtype == "SWING_DAMAGE" or eventtype == "SWING_MISSED" then
		local mainSpeed, ohSpeed = UnitAttackSpeed("target")
		local bar = module.targetSwingBar
		if not isOffHand then
			bar.bar:SetMinMaxValues(0, mainSpeed)
			bar.bar.timer = mainSpeed
			bar.bar.active = true
			bar.bar:SetScript("OnUpdate", module.OnUpdate)
			bar.bar:Show()
		end
	end
end

function module:GetOptions()
	return "targetSwingTimerOpts", self:GetModuleOptions()
end

function module:AddOptions()
	return "TargetSwingTimer", L["Target Swing Timer"], "targetSwingTimerOpts"
end

function module:GetModuleOptions()
	local targetSwingTimerOpts = {
		order = 2,
		type = "group",
		name = L["Target Swing Timer"],
		desc = L["Target Swing Timer"],
		args = {
			description = {
				order = 1,
				type = "description",
				name = L["TargetSwingTimer_Desc"],
			},
			generalOptions = {
				order = 2,
				type = "header",
				name = L["General Options"],
			},
			enable = {
				name = L["Enabled"],
				desc = L["Enabled"],
				type = "toggle",
				order = 10,
				set = function(info, val)
					self.profile.enabled = val
					self:Toggle()
				end,
				get = function(info)
					return self.profile.enabled
				end,
			},
			numericTimer = {
				name = L["Numeric Timer"],
				desc = L["Numeric Timer"],
				type = "toggle",
				order = 20,
				set = function(info, val)
					self.profile.numericTimer = val
					self:UpdateDisplay()
				end,
				get = function(info)
					return self.profile.numericTimer
				end,
			},
			specsHdr = {
				order = 50,
				type = "header",
				name = L["Specializations"],
			},
			bloodSpec = {
				name = _G.select(2, _G.GetSpecializationInfo(1)),
				desc = _G.select(2, _G.GetSpecializationInfo(1)),
				type = "toggle",
				order = 60,
				set = function(info, val)
					self.profile.specs.Blood = val
					self:Toggle()
				end,
				get = function(info)
					return self.profile.specs.Blood
				end,
			},
			frostSpec = {
				name = _G.select(2, _G.GetSpecializationInfo(2)),
				desc = _G.select(2, _G.GetSpecializationInfo(2)),
				type = "toggle",
				order = 70,
				set = function(info, val)
					self.profile.specs.Frost = val
					self:Toggle()
				end,
				get = function(info)
					return self.profile.specs.Frost
				end,
			},
			unholySpec = {
				name = _G.select(2, _G.GetSpecializationInfo(3)),
				desc = _G.select(2, _G.GetSpecializationInfo(3)),
				type = "toggle",
				order = 80,
				set = function(info, val)
					self.profile.specs.Unholy = val
					self:Toggle()
				end,
				get = function(info)
					return self.profile.specs.Unholy
				end,
			},
	    layoutHdr = {
	        order = 100,
	        type = "header",
	        name = L["Layout"],
	    },
			xoffset = {
				order = 110,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()),
				softMax = floor(_G.GetScreenWidth()),
				bigStep = 1,
				set = function(info, val)
					self.profile.x = val
					if self.targetSwingBar then
						self.targetSwingBar:SetDesiredPoint()
					end
				end,
				get = function(info, val)
					return self.profile.x
				end,
			},
			yoffset = {
				order = 120,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()),
				softMax = floor(_G.GetScreenHeight()),
				bigStep = 1,
				set = function(info, val)
					self.profile.y = val
					if self.targetSwingBar then
						self.targetSwingBar:SetDesiredPoint()
					end
				end,
				get = function(info, val)
					return self.profile.y
				end,
			},
			dimensions = {
				order = 200,
				type = "header",
				name = L["Dimensions"],
			},
			width = {
				order = 220,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 10,
				max = 100,
				step = 1,
				set = function(info, val)
					self.profile.width = val
					if self.targetSwingBar then self.targetSwingBar:Reset() end
				end,
				get = function(info, val)
					return self.profile.width or addon.GetBarWidth()
				end,
				disabled = function()
					return not self.profile.overrideWidth
				end,
			},
			height = {
				order = 230,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 5,
				max = 50,
				step = 1,
				set = function(info, val)
					self.profile.height = val
					if self.targetSwingBar then self.targetSwingBar:Reset() end
				end,
				get = function(info, val)
					return self.profile.height or addon.GetBarHeight()
				end,
				disabled = function()
					return not self.profile.overrideHeight
				end,
			},
			colorsHdr = {
				order = 300,
				type = "header",
				name = L["Colors"],
			},
			color = {
		    order = 310,
				name = L["Bar Color"],
				desc = L["Bar Color"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
					local c = self.profile.color
					c.r, c.g, c.b, c.a = r, g, b, a
					if self.targetSwingBar then self.targetSwingBar:UpdateGraphics() end
				end,
				get = function(info)
					local c = self.profile.color
					return c.r, c.g, c.b, c.a
				end,					
			},
			bgcolor = {
		    order = 320,
				name = L["Bar Background Color"],
				desc = L["Bar Background Color"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
					local c = self.profile.bgcolor
					c.r, c.g, c.b, c.a = r, g, b, a
					if self.targetSwingBar then self.targetSwingBar:UpdateGraphics() end
				end,
				get = function(info)
					local c = self.profile.bgcolor
					return c.r, c.g, c.b, c.a
				end,					
			},
			textcolor = {
		    order = 330,
				name = L["Text Color"],
				desc = L["Text Color"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
					local c = self.profile.textcolor
					c.r, c.g, c.b, c.a = r, g, b, a
					if self.targetSwingBar then self.targetSwingBar:UpdateGraphics() end
				end,
				get = function(info)
					local c = self.profile.textcolor
					return c.r, c.g, c.b, c.a
				end,					
			},

		},
	}
	BST:AddAppearanceOptions(targetSwingTimerOpts, "TargetSwingTimerBar")
	BST:AddAdvancedPositioning(targetSwingTimerOpts, "TargetSwingTimerBar")
	return targetSwingTimerOpts
end
