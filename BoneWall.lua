local _G = getfenv(0)
local ADDON_NAME, addonData = ...
local LibStub = _G.LibStub
local addon = LibStub("AceAddon-3.0"):GetAddon(addonData.addon_name)
local L = LibStub("AceLocale-3.0"):GetLocale(addonData.addon_name)

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

defaults.profile.bars["BoneWallBar"] = {
	enabled = false,
    progress = "Time",
    show_time = true,
    time_pos = "RIGHT",
	x = -120,
	y = -120,
	color = {r = 0.057, g = 0.936, b = 0.057, a = 1},
	bgcolor = {r = 0.048, g = 0.78, b = 0.048, a = 0.8},
}

function OnInitialize()
	self.bonewallbar = Bar:Create("BoneWallBar", "Bone Wall Bar", true)
	self:UpdateBoneWallBarMode()
	self.bonewallbar:UpdatePosition()
end

function BloodShieldTracker:UpdateTierBonus()
	boneWall.active = self.tierCount["T16 Tank"] >= 2 and IsBloodTank
end

function BloodShieldTracker:UpdateBoneWallBarMode()
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

function BloodShieldTracker:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, rank, lineId, spellId)
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
function BloodShieldTracker:UpdateBoneWallCharges()
	local bar = self.bonewallbar
	if bar.db.enabled and self.boneWall.active and 
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

local AurasFound = {}
local AuraData = {}
AuraData["Bone Wall"] = AuraData["Bone Wall"] or {}

function BloodShieldTracker:CheckAuras()
    local name, rank, icon, count, dispelType, duration, expires,
        caster, stealable, consolidate, spellId, canApplyAura, isBossDebuff,
		castByPlayer, value, value2, value3

	if self.db.profile.bars["BoneWallBar"].enabled and self.boneWall.active then
		local bar = self.bonewallbar
		if AurasFound["Bone Wall"] then
			local data = AuraData["Bone Wall"]
			if bar.state ~= 1 then
				bar.state = 1
				if bar.db.progress == "Time" then
					bar.bar:SetMinMaxValues(0, data.duration or 120)
				end
			end
			if data then
				bar.bar.active = true
				if boneWall.charges ~= data.count then
					boneWall.charges = data.count
					self.boneWall.subcharges = 0
					bar.bar.count = data.count			
					self:UpdateBoneWallCharges()
				end
				bar.bar.timer = data.expires - GetTime()
				bar.bar:Show()
				bar.bar:SetScript("OnUpdate", onUpdateBoneWall)
			end
		else
			if bar.state ~= 0 then
				bar.state = 0
				bar.bar.active = false
				self.boneWall.charges = 0
				self.boneWall.subcharges = 0
				bar.bar.time:SetText("-")
				bar.bar:SetScript("OnUpdate", nil)
				self:UpdateBoneWallCharges()
			end
		end
	end
end
