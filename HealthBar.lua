local _G = getfenv(0)
local ADDON_NAME, addon = ...
local LibStub = _G.LibStub
local BST = LibStub("AceAddon-3.0"):GetAddon(addon.addonNameCondensed)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonNameCondensed)

local ceil = _G.math.ceil
local tostring = _G.tostring
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax

local round = addon.round
local SpellIds = addon.SpellIds
local SpellNames = addon.SpellNames

local maxHealth = 0
local currentHealth = 0
local percentHealth = 0

local formatFull = "%s/%s (%d%%)"
local formatNoPer = "%s/%s"
local formatCurrPerc = "%s (%d%%)"

local module = {}
module.name = "HealthBar"
addon:RegisterModule(module.name, module)
module.enabled = false

addon.defaults.profile.bars["HealthBar"] = {
	hide_ooc = false,
	low_percent = 0.3,
	text_format = "OnlyCurrent",
	color = {r = 0.0, g = 0.5, b = 0.8, a = 1},
	bgcolor = {r = 0.0, g = 0.3, b = 0.6, a = 0.8},
	alt_color = {r = 1.0, g = 0.0, b = 0.0, a = 1},
	alt_bgcolor = {r = 0.65, g = 0.0, b = 0.0, a = 0.8},
	alt_textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
	x = 0, 
	y = -150,
}

function module:SetProfile()
	self.profile = addon.db.profile.bars.HealthBar
end

function module.ProfileUpdate()
	module:SetProfile()
end

function module:OnInitialize()
	addon:RegisterCallback("ProfileUpdate", module.name, module.ProfileUpdate)
	self:SetProfile()
end

function module.TalentUpdate()
	module:Toggle()
end

function module:Enable()
	addon:RegisterCallback("TalentUpdate", module.name, module.TalentUpdate)
	self:Toggle()
end

function module:Disable()
	addon:UnregisterCallback("TalentUpdate", module.name)
	self:OnDisable()
end

function module:PLAYER_REGEN_DISABLED()
	if addon:IsTrackerEnabled() and self.healthbar.db.enabled then
		self.healthbar.bar:Show()
	end
end

function module:PLAYER_REGEN_ENABLED()
    if self.healthbar.db.hide_ooc then
        self.healthbar.bar:Hide()
    end
end

function module:PLAYER_DEAD()
    -- Hide the health bar if configured to do so for OOC
    if self.healthbar.db.hide_ooc then
        if self.healthbar.bar:IsVisible() then
            self.healthbar.bar:Hide()
        end
    end
end

local UnitEvents = {
	["any"] = {
		"PLAYER_REGEN_DISABLED",
		"PLAYER_REGEN_ENABLED",
		"PLAYER_DEAD",
	},
	["player"] = {
		"UNIT_HEALTH",
		"UNIT_MAXHEALTH",
	},
}
local function EventFrame_OnEvent(frame, event, ...)
	if event == "UNIT_HEALTH" then
		module:UNIT_HEALTH(event, ...)
	elseif event == "UNIT_MAXHEALTH" then
		module:UNIT_MAXHEALTH(event, ...)
	elseif event == "PLAYER_REGEN_DISABLED" then
		module:PLAYER_REGEN_DISABLED(event, ...)
	elseif event == "PLAYER_REGEN_ENABLED" then
		module:PLAYER_REGEN_ENABLED(event, ...)
	elseif event == "PLAYER_DEAD" then
		module:PLAYER_DEAD(event, ...)
	end
end
local EventFrames = {}

function module:UNIT_MAXHEALTH(event, unit)
	if unit and unit == "player" then
		local oldHealth = maxHealth or 1
		maxHealth = UnitHealthMax("player") or 1
		if currentHealth <= 0 then
			currentHealth = UnitHealth("player")
		end
		if oldHealth ~= maxHealth then
			if maxHealth > 0 then
				percentHealth = currentHealth / maxHealth
			else
				percentHealth = 0
			end
			self:UpdateHealthBar(true)
		end
	end
end

function module:UNIT_HEALTH(event, unit)
	if unit and unit == "player" then
		local oldHealth = currentHealth or 0
		currentHealth = UnitHealth("player") or 0
		if oldHealth ~= currentHealth then
			if maxHealth > 0 then
				percentHealth = currentHealth / maxHealth
			else
				percentHealth = 0
			end
			self:UpdateHealthBar(false)
		end
	end
end

function module:OnEnable()
	if not self.healthbar then self:CreateDisplay() end
	for unit, events in _G.pairs(UnitEvents) do
		local frame = EventFrames[unit] or _G.CreateFrame("Frame",
				ADDON_NAME.."_HB_EventFrame_"..unit)
		if frame then
			frame:SetScript("OnEvent", EventFrame_OnEvent)
			EventFrames[unit] = frame
			for i, event in _G.ipairs(events) do
				if unit == "any" then
					frame:RegisterEvent(event)
				else
					frame:RegisterUnitEvent(event, unit)
				end
			end
		end
	end
	self:UNIT_MAXHEALTH("Toggle", "player")
	self:UNIT_HEALTH("Toggle", "player")
	self:UpdateHealthBar(true)
	self.healthbar:UpdateVisibility()
	if not self.healthbar.db.hide_ooc or _G.UnitAffectingCombat("player") then
		self.healthbar:Show()
	end
	self.enabled = true
end

function module:CreateDisplay()
	self.healthbar = addon.Bar:Create({
		name = "HealthBar",
		friendlyName = "Health Bar",
		initTimer = false,
		disableAnchor = false,
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
		},
	})
	self.healthbar:Hide()
end

function module:OnDisable()
	for unit, frame in _G.pairs(EventFrames) do
		if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
	end
	if self.healthbar then self.healthbar:Hide() end
	self.enabled = false
end

function module:Toggle()
	if self.profile.enabled and addon:IsTrackerEnabled() then
		self:OnEnable()
	else
		self:OnDisable()
	end
end

local percentIntFmt = "%d%%"
function module:UpdateHealthBar(maxChanged)
	if self.healthbar.db.enabled then
		if maxChanged then
			self.healthbar.bar:SetMinMaxValues(0, maxHealth)
		end

		local low = (percentHealth <= self.healthbar.db.low_percent)
		local changed = (low ~= self.healthbar.altcolor)
		self.healthbar.altcolor = low
		if changed or maxChanged then
			self.healthbar:UpdateGraphics()
		end

		self.healthbar.bar:SetValue(currentHealth)

		local text = ""
		if self.healthbar.db.text_format == "OnlyPerc" then
			text = percentIntFmt:format(percentHealth * 100)
			elseif self.healthbar.db.text_format == "Full" then
				text = formatFull:format(
					addon.FormatNumber(currentHealth), 
					addon.FormatNumber(maxHealth), 
					percentHealth * 100)
			elseif self.healthbar.db.text_format == "CurrMax" then
				text = formatNoPer:format(
					addon.FormatNumber(currentHealth), 
					addon.FormatNumber(maxHealth))
			elseif self.healthbar.db.text_format == "CurrPerc" then
				text = formatCurrPerc:format(
					addon.FormatNumber(currentHealth), 
					percentHealth * 100)
			else
				text = addon.FormatNumber(currentHealth)
			end
			self.healthbar.bar.value:SetText(text)
		end
end

function module:GetOptions()
	return "healthBarOpts", self:GetModuleOptions()
end

function module:AddOptions()
	return "HealthBar", L["Health Bar"], "healthBarOpts"
end

function module:GetModuleOptions()
	local healthBarOpts = {
	    order = 8,
	    type = "group",
	    name = L["Health Bar"],
	    desc = L["Health Bar"],
	    args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["HealthBar_Desc"],
		    },
            generalOptions = {
                order = 2,
                type = "header",
                name = L["General Options"],
            },
    		bar_enabled = {
				name = L["Enabled"],
				desc = L["EnableBarDesc"],
				type = "toggle",
				order = 10,
				set = function(info, val)
				    addon.db.profile.bars["HealthBar"].enabled = val
					if val then self:OnEnable() else self:OnDisable() end
				end,
                get = function(info)
                    return addon.db.profile.bars["HealthBar"].enabled
                end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    addon.db.profile.bars["HealthBar"].locked = val 
					self.healthbar:Lock(val)
				end,
                get = function(info)
                    return addon.db.profile.bars["HealthBar"].locked
                end,
			},
			hide_ooc = {
				name = L["Hide out of combat"],
				desc = L["HideOutOfCombat_OptionDesc"],
				type = "toggle",
				order = 30,
				set = function(info, val)
				    addon.db.profile.bars["HealthBar"].hide_ooc = val
					if not _G.InCombatLockdown() then
					    if val then
					        self.healthbar.bar:Hide()
				        elseif addon:IsTrackerEnabled() and
							addon.db.profile.bars["HealthBar"].enabled then
				            self.healthbar.bar:Show()
			            end
			        end
				end,
                get = function(info)
                    return addon.db.profile.bars["HealthBar"].hide_ooc
                end,
			},
			low_percent = {
				order = 40,
				name = L["Low Health Threshold"],
				desc = L["LowHealthThreshold_OptionDesc"],	
				type = "range",
				isPercent = true,
				min = 0.05,
				max = 0.95,
				bigStep = 0.05,
				set = function(info, val)
				    addon.db.profile.bars["HealthBar"].low_percent = val
				end,
				get = function(info, val)
				    return addon.db.profile.bars["HealthBar"].low_percent
				end,
			},
			text_format = {
				name = L["Text Format"],
				desc = L["TextFormat_OptionDesc"],
				type = "select",
				values = {
				    ["Full"] = L["Full"],
				    ["OnlyPerc"] = L["Only Percent"],
				    ["OnlyCurrent"] = L["Only Current"],
				    ["CurrMax"] = L["Current and Maximum"],
				    ["CurrPerc"] = L["Current and Percent"]
				},
				order = 50,
				set = function(info, val)
				    addon.db.profile.bars["HealthBar"].text_format = val
			        self:UpdateHealthBar(false)
				end,
                get = function(info)
                    return addon.db.profile.bars["HealthBar"].text_format
                end,
			},
            colors = {
                order = 500,
                type = "header",
                name = L["Colors for Normal Health"],
            },
			bar_textcolor = {
				order = 510,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = addon.db.profile.bars["HealthBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["HealthBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_color = {
				order = 520,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = addon.db.profile.bars["HealthBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["HealthBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_bgcolor = {
				order = 530,
				name = L["Bar Background Color"],
				desc = L["BarBackgroundColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = addon.db.profile.bars["HealthBar"].bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["HealthBar"].bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
            colorsLow = {
                order = 550,
                type = "header",
                name = L["Colors for Low Health"],
            },
			bar_low_textcolor = {
				order = 560,
				name = L["Low Health Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = addon.db.profile.bars["HealthBar"].alt_textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["HealthBar"].alt_textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_low_color = {
				order = 570,
				name = L["Low Health Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = addon.db.profile.bars["HealthBar"].alt_color
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["HealthBar"].alt_color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_low_bgcolor = {
				order = 580,
				name = L["Low Health Bar Background Color"],
				desc = L["BarBackgroundColor_LowHealth_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = addon.db.profile.bars["HealthBar"].alt_bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["HealthBar"].alt_bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
		}
	}
	BST:AddDimensionOptions(healthBarOpts, "HealthBar")
	BST:AddPositionOptions(healthBarOpts, "HealthBar")
	BST:AddAppearanceOptions(healthBarOpts, "HealthBar")
	BST:AddAdvancedPositioning(healthBarOpts, "HealthBar")
	return healthBarOpts
end
