local _G = getfenv(0)
local ADDON_NAME, addon = ...
local LibStub = _G.LibStub
local BST = LibStub("AceAddon-3.0"):GetAddon(addon.addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonName)

local ceil = _G.math.ceil
local tostring = _G.tostring
local UnitAura = _G.UnitAura
local GetTime = _G.GetTime

local round = addon.round
local SpellIds = addon.SpellIds
local SpellNames = addon.SpellNames

local BWTracker = {}
addon:RegisterModule("BWTracker", BWTracker)
BWTracker.enabled = false

local boneWall = {
	active = false,
	charges = 0,
	subcharges = 0,
}

local BoneWallAbilities = {
	[SpellIds["Heart Strike"]] = true,
	[SpellIds["Rune Strike"]] = true,
	[SpellIds["Soul Reaper"]] = true,
	[SpellIds["Soul Reaper (Blood)"]] = true,
	[SpellIds["Blood Boil"]] = true,
	[SpellIds["Death Coil"]] = true,
}

addon.defaults.profile.bars["BoneWallBar"] = {
	enabled = false,
    progress = "Time",
    show_time = true,
    time_pos = "RIGHT",
	x = -120,
	y = -120,
	color = {r = 0.057, g = 0.936, b = 0.057, a = 1},
	bgcolor = {r = 0.048, g = 0.78, b = 0.048, a = 0.8},
}

local UnitEvents = {
	["player"] = {
		"UNIT_SPELLCAST_SUCCEEDED",
	},
}
local function EventFrame_OnEvent(frame, event, ...)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		BWTracker:UNIT_SPELLCAST_SUCCEEDED(event, ...)
	end
end
local EventFrames = {}

function BWTracker:OnInitialize()
	self.bonewallbar = addon.Bar:Create("BoneWallBar", "Bone Wall Bar", true)
end

function BWTracker:Enable()
	if BST.db.profile.bars["BoneWallBar"].enabled then
		self:OnEnable()
	else
		self:OnDisable()
	end
end

function BWTracker:OnEnable()
	if self.enabled then return end
	self.enabled = true
	boneWall.subcharges = 0
	self:UpdateBoneWallBarMode()
	self.bonewallbar:UpdatePosition()
	self.bonewallbar:UpdateVisibility()

	for unit, events in _G.pairs(UnitEvents) do
		local frame = EventFrames[unit] or _G.CreateFrame("Frame",
				ADDON_NAME.."_BW_EventFrame_"..unit)
		if frame then
			frame:SetScript("OnEvent", EventFrame_OnEvent)
			EventFrames[unit] = frame
			for i, event in _G.ipairs(events) do
				frame:RegisterUnitEvent(event, unit)
			end
		end
	end

	addon:RegisterCallback("Auras", "BWTracker", BWTracker.CheckAuras)
	addon:RegisterCallback("GearUpdate", "BWTracker", BWTracker.GearUpdate)
	self:GearUpdate()
end

function BWTracker:OnDisable()
	if not self.enabled then return end
	self.enabled = false
	for unit, events in _G.pairs(UnitEvents) do
		local frame = EventFrames[unit]
		if frame then
			frame:SetScript("OnEvent", nil)
			for i, event in _G.ipairs(events) do
				frame:UnregisterEvent(event, unit)
			end
		end
	end

	addon:UnregisterCallback("Auras", "BWTracker")
	addon:UnregisterCallback("GearUpdate", "BWTracker")
	local bar = self.bonewallbar
	if bar then
		bar.bar:SetScript("OnUpdate", nil)
		bar.bar:Hide()
	end
end

function BWTracker:GetOptions()
	return "boneWallOpts", self:GetBoneWallBarOptions()
end

function BWTracker:AddOptions()
	return "BoneWallBar", L["Bone Wall Bar"], "boneWallOpts"
end

function BWTracker:GearUpdate()
	boneWall.active = addon.tierCount["T16 Tank"] >= 2 and addon.IsBloodTank
end

function BWTracker:UpdateBoneWallBarMode()
	local bar = self.bonewallbar
    if bar.db.progress == "Time" then
        bar.bar:SetMinMaxValues(0, 120)
        bar.bar:SetValue(120)
    elseif bar.db.progress == "Charges" then
        bar.bar:SetMinMaxValues(0, 10)
        bar.bar:SetValue(0)
    elseif bar.db.progress == "None" then
        bar.bar:SetMinMaxValues(0, 1)
        bar.bar:SetValue(1)        
    end
end

function BWTracker:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, rank, lineId, spellId)
    if unit == "player" then
		if boneWall.active then
			if BoneWallAbilities[spellId] then
				if spellId ~= SpellIds["Blood Boil"] or 
					_G.UnitAffectingCombat("player") then
					boneWall.subcharges = boneWall.subcharges + 1
					self:UpdateBoneWallCharges()
				end
			end
		end
	end
end

local function onUpdateBoneWall(self, elapsed)
	self.lastUpdate = (self.lastUpdate or 0) + elapsed
	self.timer = self.timer - elapsed
	if self.lastUpdate >= 0.1 then
		if self.active then
			if self.timer < 0 then
				self.timer = 0
				self.active = false
				self:SetScript("OnUpdate", nil)
				self:Hide()
			else
				if self.object.db.show_time then
					local remaining = 0
					if self.timer > 60 then
						remaining = tostring(ceil(self.timer / 60)) .. "m"
					else
						remaining = tostring(round(self.timer))
					end
					self.time:SetText(remaining)
				end
				if self.object.db.progress == "Time" then
					self:SetValue(self.timer)
				end
				self:Show()
			end
		else
			self:Hide()
		end
		self.lastUpdate = 0
	end
end

local boneWallFmt = "%d.%d"
function BWTracker:UpdateBoneWallCharges()
	local bar = self.bonewallbar
	if bar.db.enabled and boneWall.active and 
		(boneWall.charges > 0 or boneWall.subcharges > 0) then
		bar.bar:Show()
		bar.bar.value:SetText(
			boneWallFmt:format(boneWall.charges, boneWall.subcharges))
		if bar.db.progress == "Charges" then
			bar.bar:SetValue(boneWall.subcharges)
		end
	else
		bar.bar:Hide()
	end 
end

function BWTracker:CheckAuras()
    local name, rank, icon, count, dispelType, duration, expires,
        caster, stealable, consolidate, spellId, canApplyAura, isBossDebuff,
		castByPlayer, value, value2, value3
		= UnitAura("player", SpellNames["Bone Wall"])

	local found = true and spellId and spellId == SpellIds["Bone Wall"] or false

	local bar = BWTracker.bonewallbar
	if bar and bar.db.enabled and boneWall.active then
		if found then
			if bar.state ~= 1 then
				bar.state = 1
				if bar.db.progress == "Time" then
					bar.bar:SetMinMaxValues(0, duration or 120)
				end
			end
			bar.bar.active = true
			if boneWall.charges ~= count then
				boneWall.charges = count
				boneWall.subcharges = 0
				bar.bar.count = count			
				BWTracker:UpdateBoneWallCharges()
			end
			bar.bar.timer = expires - GetTime()
			bar.bar:Show()
			bar.bar:SetScript("OnUpdate", onUpdateBoneWall)
		else
			if bar.state ~= 0 then
				bar.state = 0
				bar.bar.active = false
				boneWall.charges = 0
				boneWall.subcharges = 0
				bar.bar.time:SetText("-")
				bar.bar:SetScript("OnUpdate", nil)
				BWTracker:UpdateBoneWallCharges()
			end
		end
	end
end

function BWTracker:GetBoneWallBarOptions()
	local boneWallOpts = {
		order = 2,
		type = "group",
		name = L["Bone Wall Bar"],
		desc = L["Bone Wall Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["BoneWallBar_Desc"],
		    },
            generalOptions = {
                order = 2,
                type = "header",
                name = L["General Options"],
            },
    		status_bar_enabled = {
				name = L["Enabled"],
				desc = L["EnableBarDesc"],
				type = "toggle",
				order = 10,
				set = function(info, val)
				    BST.db.profile.bars["BoneWallBar"].enabled = val
					BWTracker:Enable()
				end,
                get = function(info)
					return BST.db.profile.bars["BoneWallBar"].enabled
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    BST.db.profile.bars["BoneWallBar"].locked = val 
					BST.bars["BoneWallBar"]:Lock()
				end,
                get = function(info)
					return BST.db.profile.bars["BoneWallBar"].locked
				end,
			},
			progress = {
				name = L["Progress Bar"],
				desc = L["ProgressBar_OptionDesc"],
				type = "select",
				values = {
				    ["None"] = L["None"],
				    ["Time"] = L["Time Remaining"],
				    ["Charges"] = L["Charges"]
				},
				order = 30,
				set = function(info, val)
				    BST.db.profile.bars["BoneWallBar"].progress = val
			        self:UpdateBoneWallBarMode()
				end,
                get = function(info)
                    return BST.db.profile.bars["BoneWallBar"].progress
                end,
			},
            timeRemaining = {
                order = 100,
                type = "header",
                name = L["Time Remaining"],
            },
			show_time = {
				name = L["Show Time"],
				desc = L["ShowTime_OptionDesc"],
				type = "toggle",
				order = 110,
				set = function(info, val)
				    BST.db.profile.bars["BoneWallBar"].show_time = val
				    if val then
				        BST.bars["BoneWallBar"].bar.time:Show()
			        else
			            BST.bars["BoneWallBar"].bar.time:Hide()
		            end
				end,
                get = function(info)
                    return BST.db.profile.bars["BoneWallBar"].show_time
                end,
			},
			time_pos = {
				name = L["Position"],
				desc = L["TimePosition_OptionDesc"],
				type = "select",
				values = {
				    ["RIGHT"] = L["Right"],
				    ["LEFT"] = L["Left"],
				},
				order = 120,
				set = function(info, val)
				    BST.db.profile.bars["BoneWallBar"].time_pos = val
			        BST.bars["BoneWallBar"].bar.time:SetPoint(val or "RIGHT")
			        BST.bars["BoneWallBar"].bar.time:SetJustifyH(val or "RIGHT")
				end,
                get = function(info)
                    return BST.db.profile.bars["BoneWallBar"].time_pos
                end,
                disabled = function()
                    return not BST.db.profile.bars["BoneWallBar"].show_time
                end,
			},
		},
	}
	BST:AddDimensionOptions(boneWallOpts, "BoneWallBar")
	BST:AddPositionOptions(boneWallOpts, "BoneWallBar")
	BST:AddColorsOptions(boneWallOpts, "BoneWallBar")
	BST:AddAppearanceOptions(boneWallOpts, "BoneWallBar")
	BST:AddAdvancedPositioning(boneWallOpts, "BoneWallBar")
	return boneWallOpts
end
