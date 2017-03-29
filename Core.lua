local _G = getfenv(0)
local ADDON_NAME, addon = ...

local string = _G.string
local pairs = _G.pairs
local floor, abs = _G.math.floor, _G.math.abs
local tonumber = _G.tonumber
local tostring = _G.tostring

addon.addonName = "Blood Shield Tracker"
addon.addonNameCondensed = "BloodShieldTracker"

-- Add an external frame for anchoring.
addon.FrameNames = {
	["Compact Runes"] = "CompactRunes_RunicPowerBar",
}

-- Try to remove the Git hash at the end, otherwise return the passed in value.
local function cleanupVersion(version)
	local iter = string.gmatch(version, "(.*)-[a-z0-9]+$")
	if iter then
		local ver = iter()
		if ver and #ver >= 3 then
			return ver
		end
	end
	return version
end

addon.addonTitle = _G.GetAddOnMetadata(ADDON_NAME,"Title")
addon.addonVersion = cleanupVersion("@project-version@")

addon.CURRENT_BUILD, addon.CURRENT_INTERNAL, 
    addon.CURRENT_BUILD_DATE, addon.CURRENT_UI_VERSION = _G.GetBuildInfo()
addon.WoD = addon.CURRENT_UI_VERSION >= 60000
addon.Legion = addon.CURRENT_UI_VERSION >= 70000

local function round(number)
    if not number then return 0 end
    return floor(number+0.5)
end
addon.round = round

function addon.GetAddOnInfoByName(name)
	local addonName, title, notes, enabled, loadable, reason, security
	for i = 1, _G.GetNumAddOns() do
		addonName, title, notes, enabled, loadable, reason, security = 
			_G.GetAddOnInfo(i)
		if addonName == name then
			return addonName, title, notes, enabled, loadable, reason, security
		end
	end
end

addon.callbacks = {
	["Auras"] = {},
	["GearUpdate"] = {},
	["WeaponUpdate"] = {},
	["TalentUpdate"] = {},
	["CombatStart"] = {},
	["CombatEnd"] = {},
	["ProfileUpdate"] = {},
	["PlayerAlive"] = {},
	["PlayerDead"] = {},
}
function addon:RegisterCallback(event, name, func)
	local callbacks = addon.callbacks[event]
	if not callbacks then return end
	if name and func and _G.type(func) == "function" then
		callbacks[name] = func
	end
end
function addon:UnregisterCallback(event, name)
	local callbacks = addon.callbacks[event]
	if not callbacks then return end
	if name then
		callbacks[name] = nil
	end
end
function addon:FireCallback(event)
	local callbacks = addon.callbacks[event]
	if not callbacks then return end
	for name, func in pairs(callbacks) do
		if func then func() end
	end
end

addon.modules = {}
function addon:RegisterModule(name, obj)
	addon.modules[name] = obj
end
function addon:UnregisterModule(name)
	addon.modules[name] = nil
end

local millFmtOne = "%.1fm"
local thousandFmtOne = "%.1fk"
local millFmtZero = "%.0fm"
local thousandFmtZero = "%.0fk"
local millFmt = millFmtZero
local thousandFmt = thousandFmtZero
local baseFmtOne = "%.1f"
local baseFmtZero = "%.0f"
local baseFmt = baseFmtZero

local ThousandsDelim = ('%.1f'):format(1/5):match('([^0-9])') == '.' and ',' or '.'
local BillionDelimFmt = '%s%d' .. ThousandsDelim .. '%03d' .. ThousandsDelim .. '%03d' .. ThousandsDelim .. '%03d'
local MillionDelimFmt = '%s%d' .. ThousandsDelim .. '%03d' .. ThousandsDelim .. '%03d'
local ThousandDelimFmt = '%s%d' .. ThousandsDelim..'%03d'

addon.FormatNumberDelimited = function(number)
    if tonumber(number) == nil then
        return number
    end

	local sign = ""
	if number < 0 then
		sign = "-"
		number = abs(number)
	end

    if number >= 1000000000 then
      return BillionDelimFmt:format(sign, number / 1000000000, (number / 1000000) % 1000, (number / 1000) % 1000, number % 1000)
    elseif number >= 1000000 then
      return MillionDelimFmt:format(sign, number / 1000000, (number / 1000) % 1000, number % 1000)
    elseif number >= 1000 then
      return ThousandDelimFmt:format(sign, number / 1000, number % 1000)
    else
      return tostring(number)
    end
end

addon.FormatNumberAbbreviated = function(number)
    if tonumber(number) == nil then
        return number
    end

    if number > 1000000 then
        return millFmt:format(number / 1000000)
    elseif number > 1000 then
        return thousandFmt:format(number / 1000)
    end

    return number
end

addon.FormatNumberRaw = function(number)
	return tostring(number)
end

addon.FormatNumber = FormatNumberAbbreviated

function addon:SetNumberFormat(format)
	if format == "Delimited" then
		addon.FormatNumber = addon.FormatNumberDelimited
	elseif format == "Raw" then
		addon.FormatNumber = addon.FormatNumberRaw
	else
		addon.FormatNumber = addon.FormatNumberAbbreviated
	end
	return addon.FormatNumber
end

function addon:SetNumberPrecision()
    if self.db.profile.precision == "One" then
        millFmt = millFmtOne
        thousandFmt = thousandFmtOne
		baseFmt = baseFmtOne
    else
        millFmt = millFmtZero
        thousandFmt = thousandFmtZero
		baseFmt = baseFmtZero
    end
end

function addon.FormatWithPrecision(value)
	return baseFmt:format(value)
end

function addon.GetSpellSchool(school)
    local schools = {
        [1] = "Physical",
        [2] = "Holy",
        [3] = "Fire",
        [4] = "Nature",
        [5] = "Frost",
        [6] = "Shadow",
        [7] = "Arcane"
    }
    return schools[school] or "Special"
end

addon.UpdateDisplayEvents = {
	["PlayerAura"] = {},
	["SpellCooldown"] = {},
	["CombatStart"] = {},
	["CombatEnd"] = {},
}

function addon:BarDisplayUpdateForEvent(event)
	for bar, enabled in pairs(addon.UpdateDisplayEvents[event] or {}) do
		if bar and enabled and bar.UpdateDisplay then
			bar:UpdateDisplay(event)
		end
	end
end

function addon:BarDisplayAdd(event, bar)
	local events = addon.UpdateDisplayEvents[event]
	events[bar] = true
end

function addon:BarDisplayRemove(event, bar)
	local events = addon.UpdateDisplayEvents[event]
	events[bar] = nil
end
