local _G = getfenv(0)
local ADDON_NAME, addon = ...

local string = _G.string
local table = _G.table
local math = _G.math
local pairs = _G.pairs
local ipairs = _G.ipairs
local select = _G.select

local BloodShieldTracker = _G.LibStub("AceAddon-3.0"):NewAddon(addon.addonName, 
	"AceConsole-3.0", "AceEvent-3.0","AceTimer-3.0")
local BST = BloodShieldTracker
addon.BloodShieldTracker = BloodShieldTracker

local L = _G.LibStub("AceLocale-3.0"):GetLocale(addon.addonName, true)
local LDB = _G.LibStub("LibDataBroker-1.1")
local LibQTip = _G.LibStub("LibQTip-1.0")
local icon = _G.LibStub("LibDBIcon-1.0")
local LSM = _G.LibStub:GetLibrary("LibSharedMedia-3.0")
local AGU = _G.LibStub("AceGUI-3.0")

addon.DEBUG_OUTPUT = false
addon.DEBUG_BUFFER = ""

-- Define Bar for now but the rest is at the bottom of the file.
local Bar = addon.Bar

-- Local versions for performance
local tinsert, tremove, tgetn = table.insert, table.remove, table.getn
local tconcat = table.concat
local floor, ceil, abs = math.floor, math.ceil, math.abs
local max, exp = math.max, math.exp
local unpack = _G.unpack
local tostring = _G.tostring
local tonumber = _G.tonumber
local wipe = _G.wipe
local type = _G.type

-- Local versions of WoW API calls
local UnitAura = _G.UnitAura
local GetTime = _G.GetTime
local UnitHealthMax = _G.UnitHealthMax
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitAttackPower = _G.UnitAttackPower
local GetMasteryEffect = _G.GetMasteryEffect
local GetVersatilityBonus = _G.GetVersatilityBonus
local GetCombatRatingBonus = _G.GetCombatRatingBonus
local GetSpellCooldown = _G.GetSpellCooldown

BloodShieldTracker.loaded = false
BloodShieldTracker.playerName = UnitName("player")
BloodShieldTracker.bars = {}
addon.bars = BloodShieldTracker.bars
BloodShieldTracker.shieldbar = nil
BloodShieldTracker.estimatebar = nil
BloodShieldTracker.pwsbar = nil

-- Player class, talent, and spec info
addon.isDK = nil
addon.currentSpec = ""
addon.IsBloodTank = false
local hasBloodShield = false
addon.tierCount = {
	["T14 Tank"] = 0,
	["T16 Tank"] = 0,
}

-- Settings to allow custom fonts and textures which override the
-- user set options.
addon.CustomUI = {}
local CustomUI = addon.CustomUI
CustomUI.texture = nil
CustomUI.font = nil
CustomUI.fontSize = nil
CustomUI.fontFlags = nil
CustomUI.showBorders = nil

local GearChangeTimer = nil

-- Define a simplistic class for shield statistics
local ShieldStats = {}
ShieldStats.__index = ShieldStats

function ShieldStats:new()
	local stats = {}
	_G.setmetatable(stats, ShieldStats)
	stats:Reset()
	return stats
end

function ShieldStats:NewShield(value, isMinimum, isRefresh)
	self.numShields = self.numShields + 1
	self.totalShields = self.totalShields + value

	if isRefresh then
		self.numRefreshedShields = self.numRefreshedShields + 1
	end

	if self.minShield == 0 or value < self.minShield then
		self.minShield = value
	end
	if value > self.maxShield then
		self.maxShield = value
	end
end

function ShieldStats:RemoveShield()
	self.numRemovedShields = self.numRemovedShields + 1
end

function ShieldStats:ShieldAbsorb(value)
	self.totalAbsorbs = self.totalAbsorbs + value
end

function ShieldStats:StartCombat()
	self.startTime = GetTime()
end

function ShieldStats:EndCombat()
	self.endTime = GetTime()
end

function ShieldStats:Reset()
	self.numShields = 0
	self.numRemovedShields = 0
	self.numRefreshedShields = 0
	self.minShield = 0
	self.maxShield = 0
	self.totalShields = 0
	self.totalAbsorbs = 0
	self.startTime = 0
	self.endTime = 0
end

-- Stats for all fights
BloodShieldTracker.TotalShieldStats = ShieldStats:new()
local TotalShieldStats = BloodShieldTracker.TotalShieldStats

-- Last fight stats
BloodShieldTracker.LastFightStats = ShieldStats:new()
local LastFightStats = BloodShieldTracker.LastFightStats

-- Color codes
local GREEN = "|cff00ff00"
local YELLOW = "|cffffff00"
local BLUE = "|cff0198e1"
local ORANGE = "|cffff9933"

local shieldBarFormatFull = "%s/%s (%d%%)"
local shieldBarFormatNoPer = "%s/%s"
local shieldBarFormatCurrPerc = "%s (%d%%)"

local estimateBarFormat = "%s%s%s"
local estBarPercFmt = "%s%%"

local LookupOrKeyMT = {__index = function (t,k) return k end}

local ItemIds = {
	["Indomitable Pride"] = 77211,
}
local ItemNames = {}
local function LoadItemNames()
	for k,v in pairs(ItemIds) do
		local name = ItemNames[k]
		if not name then
			ItemNames[k] = (_G.GetItemInfo(ItemIds[k]))
		end
	end
end
LoadItemNames()
addon.ItemNames = ItemNames

local SpellIds = {
	["Power Word: Shield"] = 17,
	["Divine Aegis"] = 47753,
	["Indomitable Pride"] = 108008,
	["Scent of Blood"] = 50421,
	["Dark Succor"] = 101568,
	["Vampiric Blood"] = 55233,
	["Blood Presence"] = 48263,
	["Unholy Presence"] = 48265,
	["Frost Presence"] = 48266,
	["Blood Shield"] = 77535,
	["Death Strike"] = 49998,
	["Death Strike Heal"] = 45470,
	["Luck of the Draw"] = 72221,
	["Spirit Link"] = 98017,
	["Spirit Link Totem"] = 98007,
	["Guardian Spirit"] = 47788,
	["Mastery: Blood Shield"] = 77513,
	["Life Cocoon"] = 116849,
	["Spirit Shell"] = 114908,
	["Guard"] = 118604, -- via the Brewmaster's Black Ox Statue
	["Shroud of Purgatory"] = 116888,
	["Blood Charge"] = 114851,
	["Anti-Magic Shell"] = 48707,
	["Bone Shield"] = 49222,
	["Bone Wall"] = 144948,
	["Heart Strike"] = 55050,
	["Death Coil"] = 47541,
	["Rune Strike"] = 56815,
	["Soul Reaper"] = 130735,
	["Soul Reaper (Blood)"] = 114866,
	["Soul Reaper (Frost)"] = 130735,
	["Soul Reaper (Unholy)"] = 130736,
	["Blood Boil"] = 48721,
	["Sacred Shield"] = 65148,
	-- ICC Buffs for Horde
	["Hellscream's Warsong 05"] = 73816,
	["Hellscream's Warsong 10"] = 73818,
	["Hellscream's Warsong 15"] = 73819,
	["Hellscream's Warsong 20"] = 73820,
	["Hellscream's Warsong 25"] = 73821,
	["Hellscream's Warsong 30"] = 73822,
	-- ICC Buffs for Alliance
	["Strength of Wrynn 05"] = 73762,
	["Strength of Wrynn 10"] = 73824,
	["Strength of Wrynn 15"] = 73825,
	["Strength of Wrynn 20"] = 73826,
	["Strength of Wrynn 25"] = 73827,
	["Strength of Wrynn 30"] = 73828,
	["Clarity of Will"] = 152118,
	["Saved by the Light"] = 157047,
}
local SpellNames = {}
_G.setmetatable(SpellNames, LookupOrKeyMT)
local function LoadSpellNames()
	for k, v in pairs(SpellIds) do
		if _G.rawget(SpellNames, k) == nil then
			SpellNames[k] = _G.GetSpellInfo(v)
		end
	end
end
LoadSpellNames()
addon.SpellIds = SpellIds
addon.SpellNames = SpellNames

local AbsorbShieldsOrdered = {
	"Blood Shield",
	"Power Word: Shield",
	"Clarity of Will",
	"Divine Aegis",
	"Life Cocoon",
	"Spirit Shell",
	"Guard",
	"Saved by the Light",
	"Sacred Shield",
	"Anti-Magic Shell",
	"Indomitable Pride",
}
local AbsorbShields = {}
for i, k in ipairs(AbsorbShieldsOrdered) do
	AbsorbShields[SpellIds[k]] = k
end
addon.AbsorbShieldsOrdered = AbsorbShieldsOrdered
addon.AbsorbShields = AbsorbShields

local GlyphIds = {
	["Vampiric Blood"] = 58676,
}

local ICCBuffs = {
	Horde = {
		[SpellIds["Hellscream's Warsong 05"]] = 0.05,
		[SpellIds["Hellscream's Warsong 10"]] = 0.10,
		[SpellIds["Hellscream's Warsong 15"]] = 0.15,
		[SpellIds["Hellscream's Warsong 20"]] = 0.20,
		[SpellIds["Hellscream's Warsong 25"]] = 0.25,
		[SpellIds["Hellscream's Warsong 30"]] = 0.30,
	},
	Alliance = {
		[SpellIds["Strength of Wrynn 05"]] = 0.05,
		[SpellIds["Strength of Wrynn 10"]] = 0.10,
		[SpellIds["Strength of Wrynn 15"]] = 0.15,
		[SpellIds["Strength of Wrynn 20"]] = 0.20,
		[SpellIds["Strength of Wrynn 25"]] = 0.25,
		[SpellIds["Strength of Wrynn 30"]] = 0.30,
	}
}

local scentBloodStackBuff = 0.2
local vbGlyphedHealthInc = 0.0
local vbGlyphedHealingInc = 0.25
local vbUnglyphedHealthInc = 0.15
local vbUnglyphedHealingInc = 0.15
local guardianSpiritHealBuff = 0.60

-- Curent state information
local DarkSuccorBuff = false
local estimatedDS = 0
local estimatedBS = 0
local scentBloodStacks = 0
local luckOfTheDrawBuff = false
local luckOfTheDrawAmt = 0
local iccBuff = false
local iccBuffAmt = 0.0
local vbBuff = false
local vbHealthInc = 0.0
local vbHealingInc = 0.0
local gsHealModifier = 0.0
local healingDebuffMultiplier = 0
local masteryRating = 0
local versatilityBonus = 0
local versatilityPercent = 0
local shieldPercent = 0
addon.effectiveAP = 0
addon.playerLevel = _G.UnitLevel("player")
local dsHealAPMod = 4

local round = addon.round

local Broker = _G.CreateFrame("Frame")
Broker.obj = LDB:NewDataObject(addon.addonTitle, {
    type = "data source",
    icon = "Interface\\Icons\\Spell_DeathKnight_DeathStrike",
    label = addon.addonTitle,
    text = addon.addonTitle,
    barValue = 0,
    barR = 0,
    barG = 0,
    barB = 1,
	OnClick = function(clickedframe, button)
		if button == "RightButton" then
			local optionsFrame = _G.InterfaceOptionsFrame

			if optionsFrame:IsVisible() then
				optionsFrame:Hide()
			else
				BloodShieldTracker:ShowOptions()
			end
		elseif button == "LeftButton" and _G.IsShiftKeyDown() then
		    BloodShieldTracker:ResetStats()
        end
	end
} )

-- Track stats that are used for the LDB data feed.
addon.LDBDataFeed = false
addon.DataFeed = {
	display = "",
	lastDS = 0,
	lastBS = 0,
	estimateBar = 0,
}
local DataFeed = addon.DataFeed

local percentFormat = "%.1f%%"

function addon:UpdateLDBData()
	if DataFeed.display == "LastBS" then
		Broker.obj.text = addon.FormatNumber(DataFeed.lastBS)
	elseif DataFeed.display == "LastDS" then
		Broker.obj.text = addon.FormatNumber(DataFeed.lastDS)
	elseif DataFeed.display == "EstimateBar" then
		Broker.obj.text = addon.FormatNumber(DataFeed.estimateBar)
	else
		Broker.obj.text = addon.addonTitle
	end
end

function addon:SetBrokerLabel()
	if addon.db.profile.ldb_short_label then
		Broker.obj.label = L["BST"]
	else
		Broker.obj.label = addon.addonTitle
	end
end

local addonHdr = GREEN.."%s %s"
local totalDataHdr = ORANGE..L["Total Data"]
local dataLine1 = YELLOW..L["Shields Total/Refreshed/Removed:"]
local shieldDataLine1Fmt = "%d / %d / %d"
local shieldMaxValueLine1 = YELLOW..L["Min - Max / Avg:"]
local rangeWithAvgFmt = "%d - %d / %d"
local valuesWithPercFmt = "%s / %s - %.1f%%"
local shieldUsageLine1 = YELLOW..L["Absorbed/Total Shields/Percent:"]
local secondsFormat = "%.1f " .. L["seconds"]
local durationLine = YELLOW..L["Fight Duration:"]
local shieldFreqLine = YELLOW..L["Shield Frequency:"]
local lastFightValueHdr = ORANGE..L["Last Fight Data"]

local function AddStats(tooltip, stats)
    local avgShieldValue
    if stats.numShields > 0 then
        avgShieldValue = stats.totalShields / stats.numShields
    end

    local shieldUsagePerc = 0
    if stats.totalShields > 0 then
        shieldUsagePerc = stats.totalAbsorbs / stats.totalShields * 100
    end

    tooltip:AddSeparator(1)
    tooltip:AddLine(dataLine1, 
        shieldDataLine1Fmt:format(
            stats.numShields,
            stats.numRefreshedShields, 
            stats.numRemovedShields))
    tooltip:AddLine(shieldMaxValueLine1, 
        rangeWithAvgFmt:format(
            stats.minShield, 
            stats.maxShield, 
            avgShieldValue or 0))
    tooltip:AddLine(shieldUsageLine1, 
        valuesWithPercFmt:format(
            addon.FormatNumber(stats.totalAbsorbs), 
            addon.FormatNumber(stats.totalShields), shieldUsagePerc))
end

function Broker.obj:OnEnter()
	local tooltip = LibQTip:Acquire("BloodShieldTrackerTooltip", 2, "LEFT", "RIGHT")
	self.tooltip = tooltip 

    tooltip:AddHeader(addonHdr:format(addon.addonTitle, addon.addonVersion))
    tooltip:AddLine()

    if addon.isDK then
        tooltip:AddLine(L["Shift + Left-Click to reset."], "", 1, 1, 1)
        tooltip:AddLine()

        tooltip:AddLine(totalDataHdr)
        AddStats(tooltip, TotalShieldStats)

        tooltip:AddLine()
        tooltip:AddLine(lastFightValueHdr)
        AddStats(tooltip, LastFightStats)
        local duration = LastFightStats.endTime - LastFightStats.startTime
        if duration > 0 then
            tooltip:AddLine(durationLine, secondsFormat:format(duration))
            if LastFightStats.numShields > 0 then
                local frequency = duration / LastFightStats.numShields
                tooltip:AddLine(shieldFreqLine, secondsFormat:format(frequency))
            else
                tooltip:AddLine(shieldFreqLine, "")
            end
        else
            tooltip:AddLine(durationLine, "")
            tooltip:AddLine(shieldFreqLine, "")
        end
    end

	tooltip:SmartAnchorTo(self)
	tooltip:Show()
end

function Broker.obj:OnLeave()
	LibQTip:Release(self.tooltip)
	self.tooltip = nil
end

addon.defaults = {
    profile = {
		minimap = {
			hide = true,
		},
        verbose = false,
		debug = false,
        enable_only_for_blood = true,
        precision = "Zero",
		numberFormat = "Abbreviated",
		-- Font Settings
		font_size = 12,
		font_face = "Friz Quadrata TT",
		font_outline = true,
		font_monochrome = false,
		font_thickoutline = false,
        -- Skinning options
		skinning = {
			elvui = {
		        enabled = true,
		        borders = true,
		        texture = true,
		        font = true,
		        font_flags = true,
			},
			tukui = {
		        enabled = true,
		        borders = true,
		        texture = true,
		        font = true,
		        font_flags = true,
			},
		},
        -- LDB Display
        ldb_data_feed = "None",
        ldb_short_label = false,
		-- Bars
		bars = {
			-- Provide defaults for all bars.
			-- These are inherited if no bar or no value is set.
			['**'] = {
				enabled = false,
				shown = true,
				locked = false,
				texture = "Blizzard",
				border = true,
				color = {r = 1.0, g = 0.0, b = 0.0, a = 1},
				bgcolor = {r = 0.65, g = 0.0, b = 0.0, a = 0.8},
				textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
				x = 0, 
				y = 0,
				width = 75,
				height = 15,
				scale = 1,
				anchorFrame = "None",
				anchorFrameCustom = "",
				anchorFramePt = "BOTTOM",
				anchorPt = "TOP",
				anchorX = 0,
				anchorY = -8,
			},
			["ShieldBar"] = {
				enabled = true,
		        progress = "Time",
		        show_time = true,
		        time_pos = "RIGHT",
		        sound_enabled = false,
		        sound_applied = "None",
		        sound_removed = "None",
		        text_format = "OnlyCurrent",
				width = 100,
				y = -90,
			},
			["BloodChargeBar"] = {
				enabled = false,
				progress = "Time",
				show_time = false,
				time_pos = "RIGHT",
				x = -90,
				y = -90,
			},
			["EstimateBar"] = {
				enabled = true,
				hide_ooc = false,
				show_text = true,
				bar_mode = "DS",
				usePercent = false,
				alternateMinimum = 0,
				show_stacks = true,
				stacks_pos = "LEFT",
				color = {r = 1.0, g = 0.0, b = 0.0, a = 1},
				bgcolor = {r = 0.65, g = 0.0, b = 0.0, a = 0.8},
				alt_color = {r = 0.0, g = 1.0, b = 0.0, a = 1},
				alt_bgcolor = {r = 0.0, g = 0.65, b = 0.0, a = 0.8},
				alt_textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
				width = 90,
				x = 0, 
				y = -120,
			},
			["PWSBar"] = {
				color = {r = 1.0, g = 1.0, b = 1.0, a = 1},
				bgcolor = {r = 0.96, g = 0.55, b = 0.73, a = 0.7},
				included = {
					["Power Word: Shield"] = true,
					["Divine Aegis"] = true,
					["Spirit Shell"] = true,
					["Clarity of Will"] = true,
				},
				x = 100, 
				y = -120,
			},
			["TotalAbsorbsBar"] = {
				color = {r = 0.58, g = 0.51, b = 0.79, a = 1},
				bgcolor = {r = 0.58, g = 0.51, b = 0.79, a = 0.7},
				tracked = "Selected",
				included = {
					["Blood Shield"] = false,
					["Power Word: Shield"] = true,
					["Divine Aegis"] = true,
					["Life Cocoon"] = true,
					["Guard"] = true,
					["Indomitable Pride"] = true,
					["Spirit Shell"] = true,
					["Sacred Shield"] = true,
					["Anti-Magic Shell"] = false,
					["Clarity of Will"] = true,
					["Saved by the Light"] = true,
				},
				x = 100, 
				y = -90,
			},
			["PurgatoryBar"] = {
				color = {r = 0.03, g = 0.54, b = 0.03, a = 1},
				bgcolor = {r = 0.05, g = 0.70, b = 0.05, a = 0.7},
				width = 100,
				height = 30,
			},
			["AMSBar"] = {
				color = {r = 0.83, g = 0.94, b = 0.15, a = 1},
				bgcolor = {r = 0.75, g = 0.9, b = 0.13, a = 0.7},
				x = 200,
				y = 0,
			},
			["BoneShieldBar"] = {
				enabled = false,
		    progress = "Charges",
		    show_time = false,
		    time_pos = "RIGHT",
				showCooldown = "true",
				showReady = "true",
				color = {r = 0.03, g = 0.54, b = 0.03, a = 1},
				bgcolor = {r = 0.02, g = 0.4, b = 0.01, a = 0.7},
				x = -90,
				y = -90,
			},
		},
	}
}

local DebugOutputFrame = nil
function BloodShieldTracker:ShowDebugOutput()
	if DebugOutputFrame then return end

	local frame = AGU:Create("Frame")
	frame:SetTitle("Debug Output")
	frame:SetWidth(650)
	frame:SetHeight(400)
	frame:SetLayout("Flow")
	frame:SetCallback("OnClose", function(widget)
		widget:ReleaseChildren()
		widget:Release()
		DebugOutputFrame = nil
	end)

	DebugOutputFrame = frame

	local multiline = AGU:Create("MultiLineEditBox")
	multiline:SetLabel("Output")
	multiline:SetNumLines(20)
	multiline:SetMaxLetters(0)
	multiline:SetFullWidth(true)
	multiline:DisableButton(true)
	frame:AddChild(multiline)
	frame.multiline = multiline

	multiline:SetText(addon.DEBUG_BUFFER)
end

local function splitWords(str)
  local w = {}
  local function helper(word) table.insert(w, word) return nil end
  str:gsub("(%w+)", helper)
  return w
end

function BloodShieldTracker:ChatCommand(input)
	if not input or input:trim() == "" then
  	self:ShowOptions()
  else
		local cmds = splitWords(input)
		if cmds[1] and cmds[1] == "debug" then
			if cmds[2] and cmds[2] == "on" then
				self.db.profile.debug = true
				self:Print("Debugging on.  Use '/bst debug off' to disable.")
			elseif cmds[2] and cmds[2] == "off" then
				self.db.profile.debug = false
				self:Print("Debugging off.")
			else
				self:Print("Debugging is "..(self.db.profile.debug and "on." or "off."))
			end
		elseif cmds[1] and cmds[1] == "log" then
			if cmds[2] and cmds[2] == "on" then
				addon.DEBUG_OUTPUT = true
				self:Print("Logging on.")
			elseif cmds[2] and cmds[2] == "off" then
				addon.DEBUG_OUTPUT = false
				self:Print("Logging off.")
			elseif cmds[2] and cmds[2] == "show" then
				self:ShowDebugOutput()
			else
				self:Print("Logging is "..(addon.DEBUG_OUTPUT and "on." or "off."))
			end
		end
	end
end

function BloodShieldTracker:OnInitialize()
  -- Load the settings
  self.db = _G.LibStub("AceDB-3.0"):New("BloodShieldTrackerDB", 
		addon.defaults, "Default")
	addon.db = self.db

	-- Migrate the settings
	self:MigrateSettings()

	addon.DEBUG_OUTPUT = self.db.profile.debug

	-- Set the number format
	addon:SetNumberFormat(self.db.profile.numberFormat)

    -- Set the precision
	addon:SetNumberPrecision()

	-- Create the bars
	self.shieldbar = Bar:Create("ShieldBar", "Shield Bar", true)
	self:UpdateShieldBarMode()
  	self:UpdateShieldBarText(0, 0, 0)
	self.pwsbar = Bar:Create("PWSBar", "PW:S Bar", false)
	self.absorbsbar = Bar:Create("TotalAbsorbsBar", "Total Absorbs Bar", false)
	self.purgatorybar = Bar:Create("PurgatoryBar", "Purgatory Bar", false)
	self.bloodchargebar = Bar:Create("BloodChargeBar", "Blood Charge Bar", true)
	self.boneshieldbar = Bar:Create("BoneShieldBar", "Bone Shield Bar", true)
	self.amsbar = Bar:Create("AMSBar", "Anti-Magic Shell Bar", true)

	-- Register for profile callbacks
	self.db.RegisterCallback(self, "OnProfileChanged", "Reset")
	self.db.RegisterCallback(self, "OnProfileCopied", "Reset")
	self.db.RegisterCallback(self, "OnProfileReset", "Reset")

    -- Set the LDB options
    DataFeed.display = self.db.profile.ldb_data_feed
    if DataFeed.display ~= "None" then
        addon.LDBDataFeed = true
    end
    addon:SetBrokerLabel()

	icon:Register("BloodShieldTrackerLDB", Broker.obj, self.db.profile.minimap)
	LSM.RegisterCallback(BloodShieldTracker, "LibSharedMedia_Registered")

	for name, obj in pairs(addon.modules) do
		if obj and obj.OnInitialize then
			obj:OnInitialize()
		end
	end

	self:UpdatePositions()
	self:Skin()
end

function BloodShieldTracker:Reset()
	-- Reset positions
	for name,bar in pairs(self.bars) do
		bar.db = self.db.profile.bars[bar.name]
		bar:Reset()
	end

	self:ResetFonts()
	self:ResetStats()
end

function addon:GetFontFlags()
    local flags = {}
    if self.db.profile.font_outline then
        tinsert(flags, "OUTLINE")
    end
    if self.db.profile.font_monochrome then
        tinsert(flags, "MONOCHROME")
    end
    if self.db.profile.font_thickoutline then
        tinsert(flags, "THICKOUTLINE")
    end
    return tconcat(flags, ",")
end

function addon:GetFontSettings()
	local ff, fh, fontFlags

    -- If a custom font is set, then override the settings
    if CustomUI.font then
        ff = CustomUI.font
    else
	    ff = LSM:Fetch("font", self.db.profile.font_face)
    end
    if CustomUI.fontSize then
        fh = CustomUI.fontSize
    else
        fh = self.db.profile.font_size
    end
    if CustomUI.fontFlags then
        fontFlags = CustomUI.fontFlags
    else
        fontFlags = self:GetFontFlags()
    end

	return ff, fh, fontFlags
end

function BloodShieldTracker:Skin()
    local Tukui = _G.Tukui
    local ElvUI = _G.ElvUI

    if Tukui and self.db.profile.skinning.tukui.enabled then
        local T, C, L = unpack(Tukui)
        if C and C["media"] then
            local media = C["media"]
            if media.normTex and self.db.profile.skinning.tukui.texture then
                self:SetCustomTexture(media.normTex)
            end
            if media.font and self.db.profile.skinning.tukui.font then
                self:SetCustomFont(media.font)
            end
            if self.db.profile.skinning.tukui.font_flags then
                self:SetCustomFontFlags("")
            end
            if self.db.profile.skinning.tukui.borders then
                self:SetCustomShowBorders(false)
				for name, bar in pairs(self.bars) do
					bar.bar:CreateBackdrop()
				end
            end
        else
            self:Print("Could not find Tukui config.")
        end
    end
    
    if ElvUI and self.db.profile.skinning.elvui.enabled then
        local E, L, P, G = unpack(ElvUI)
        if E and E["media"] then
            local media = E["media"]
            if media.normTex and self.db.profile.skinning.elvui.texture then
                self:SetCustomTexture(media.normTex)
            end
            if media.normFont and self.db.profile.skinning.elvui.font then
                self:SetCustomFont(media.normFont)
            end
            if self.db.profile.skinning.elvui.font_flags then
                self:SetCustomFontFlags("")
            end
            if self.db.profile.skinning.elvui.borders then
                self:SetCustomShowBorders(false)
				for name, bar in pairs(self.bars) do
					bar.bar:CreateBackdrop()
				end
            end
        else
            self:Print("Could not find the ElvUI config.")
        end
    end
end

function BloodShieldTracker:SetCustomTexture(texture)
    if texture then
        CustomUI.texture = texture
        self:UpdateTextures()
    end
end

function BloodShieldTracker:SetCustomFont(font)
    if font then
        CustomUI.font = font
        self:ResetFonts()
    end
end

function BloodShieldTracker:SetCustomFontSize(size)
    if size then
        CustomUI.fontSize = size
        self:ResetFonts()
    end
end

function BloodShieldTracker:SetCustomFontFlags(flags)
    if flags then
        CustomUI.fontFlags = flags
        self:ResetFonts()
    end
end

function BloodShieldTracker:SetCustomShowBorders(show)
    if show ~= nil then
        CustomUI.showBorders = show
        self:UpdateBorders()
    end
end

function BloodShieldTracker:ResetFonts()
	for name, bar in pairs(self.bars) do
		bar:ResetFonts()
	end
end

function BloodShieldTracker:UpdateTextures()
	for name, bar in pairs(self.bars) do
		bar:UpdateTexture()
	end
end

function BloodShieldTracker:UpdateBorders()
	for name, bar in pairs(self.bars) do
		bar:UpdateBorder()
	end
end

function BloodShieldTracker:UpdatePositions()
	for name, bar in pairs(self.bars) do
		bar:UpdatePosition()
	end
end

function BloodShieldTracker:LibSharedMedia_Registered(event, mediatype, key)
	if _G.strlen(self.db.profile.font_face) > 1 and mediatype == "font" then
		if self.db.profile.font_face == key then
			self:ResetFonts()
		end
	end
	if mediatype == "statusbar" then
	    self:UpdateTextures()
	end
end

function BloodShieldTracker:OnEnable()
	-- Try to load the spell and item names one more time.
	LoadItemNames()
	LoadSpellNames()
	if not self.optionsFrame then
		-- Register Options
		local displayName = addon.addonTitle
		local options = self:GetOptions()
		_G.LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(displayName, options)

		self.optionsFrame = {}
		local ACD = _G.LibStub("AceConfigDialog-3.0")
		self.optionsFrame.Main = ACD:AddToBlizOptions(
			displayName, displayName, nil, "core")
		self.optionsFrame.ShieldBar = ACD:AddToBlizOptions(
			displayName, L["Blood Shield Bar"], displayName, "shieldBarOpts")
		self.optionsFrame.BloodChargeBar = ACD:AddToBlizOptions(
			displayName, L["Blood Charge Bar"], displayName, "bloodChargeOpts")
		self.optionsFrame.BoneShieldBar = ACD:AddToBlizOptions(
			displayName, L["Bone Shield Bar"], displayName, "boneShieldOpts")
		self.optionsFrame.PriestBar = ACD:AddToBlizOptions(
			displayName, L["PW:S Bar"], displayName, "pwsBarOpts")
		self.optionsFrame.AbsorbsBar = ACD:AddToBlizOptions(
			displayName, L["Total Absorbs Bar"], displayName, "absorbsBarOpts")
		self.optionsFrame.AMSBar = ACD:AddToBlizOptions(
			displayName, L["Anti-Magic Shell Bar"], displayName, "amsBarOpts")
		self.optionsFrame.PurgatoryBar = ACD:AddToBlizOptions(
			displayName, L["Purgatory Bar"], displayName, "purgatoryBarOpts")

		-- Add options for modules
		for name, obj in pairs(addon.modules) do
			if obj and obj.AddOptions then
				local name, sectionName, tableName = obj.AddOptions()
				self.optionsFrame[name] = ACD:AddToBlizOptions(
					displayName, sectionName, displayName, tableName)
			end
		end

		self.optionsFrame.Skinning = ACD:AddToBlizOptions(
			displayName, L["Skinning"], displayName, "skinningOpts")
		ACD:AddToBlizOptions(
			displayName, options.args.profile.name, displayName, "profile")

		-- Register the chat command
		self:RegisterChatCommand("bst", "ChatCommand")
		self:RegisterChatCommand("bloodshield", "ChatCommand")
	end

	self:CheckClass()
	self:CheckGear()

	self:CheckTalents()
	self:RegisterEvent("PLAYER_TALENT_UPDATE", "CheckTalents")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","CheckTalents")
	
	-- TODO: Check if anything here needs to be updated or just removed.
	--self:RegisterEvent("GLYPH_ADDED", "CheckGlyphs")
	--self:RegisterEvent("GLYPH_REMOVED", "CheckGlyphs")
	--self:RegisterEvent("GLYPH_UPDATED", "CheckGlyphs")
	
	for name, obj in pairs(addon.modules) do
		if obj and obj.Enable then
			obj:Enable()
		end
	end
end

local UnitEvents = {
	["player"] = {
		["UNIT_AURA"] = true,
	},
}
local function EventFrame_OnEvent(frame, event, ...)
	BloodShieldTracker[event](BloodShieldTracker, event, ...)
end
local EventFrames = {}
function addon.CreateEventFrames()
	for unit, events in pairs(UnitEvents) do
		local frame = _G.CreateFrame("Frame", ADDON_NAME.."_EventFrame_"..unit)
		frame:SetScript("OnEvent", EventFrame_OnEvent)
		EventFrames[unit] = frame
	end
end
addon.CreateEventFrames()
function addon.RegisterUnitEvents(frames, events)
	for unit, events in pairs(events) do
		local frame = frames[unit]
		if frame then
			for event, val in pairs(events) do
				frame:RegisterUnitEvent(event, unit)
			end
		else
			BST:Print("Missing event frame for "..tostring(unit).."!")
		end
	end
end
function addon.UnregisterUnitEvents(frames, events)
	for unit, events in pairs(events) do
		local frame = frames[unit]
		if frame then
			for event, val in pairs(events) do
				frame:UnregisterEvent(event, unit)
			end
		end
	end
end

function BloodShieldTracker:Load()
	if self.loaded then return end

	self.loaded = true

	if self.db.profile.verbose then
		self:Print("Loading.")
	end
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_DEAD")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_ALIVE")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

	addon.RegisterUnitEvents(EventFrames, UnitEvents)

	self.shieldbar:UpdateUI()
end

function BloodShieldTracker:Unload()
	if not self.loaded then return end

	self.loaded = false
	if self.db.profile.verbose then
		self:Print("Unloading.")
	end
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("PLAYER_DEAD")
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("PLAYER_ALIVE")
	self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")

	addon.UnregisterUnitEvents(EventFrames, UnitEvents)

	for k, v in pairs(self.bars) do
		if v then
			v.bar:Hide()
		end
	end
end

function BloodShieldTracker:OnDisable()
end

function BloodShieldTracker:CheckClass()
	local class, className = _G.UnitClass("player")
	if className then
		if (className == 'DEATH KNIGHT' or className == 'DEATHKNIGHT') then
			addon.isDK = true
		else
			addon.isDK = false
		end
	end
end

function BloodShieldTracker:CheckTalents(event)
	addon.IsBloodTank = false
	hasBloodShield = false
	HasVampBlood = false

	self:CheckTalents5()
	self:UpdateTierBonus()
	addon:FireCallback("GearUpdate")

	self.bars["BoneShieldBar"]:UpdateVisibility()

	if self.db.profile.debug then
		local trackerOutputFmt = "Check Talents [DK=%s,BT=%s,MA=%s,VB=%s,Event=%s]"
		self:Print(trackerOutputFmt:format(tostring(addon.isDK),
			tostring(addon.IsBloodTank),tostring(hasBloodShield),tostring(HasVampBlood),
			tostring(event or "")))
	end
end

-- New method to check talents for MoP
function BloodShieldTracker:CheckTalents5()
	if addon.isDK == nil then
		self:CheckClass()
	end

	if addon.isDK then
		-- Check spec: Blood, Frost, or Unholy spec?
		local activeSpecNum = _G.GetSpecialization()
		if activeSpecNum and activeSpecNum > 0 then
			local id, name, desc, texture = _G.GetSpecializationInfo(activeSpecNum)
    	if texture == "Interface\\Icons\\Spell_Deathknight_BloodPresence" then
				addon.currentSpec = "Blood"
			elseif texture == "Interface\\Icons\\Spell_Deathknight_FrostPresence" then
				addon.currentSpec = "Frost"
			elseif texture == "Interface\\Icons\\Spell_Deathknight_UnholyPresence" then
				addon.currentSpec = "Unholy"
			else
				self:Print("Error detecing player spec.")
				addon.currentSpec = "Blood"
			end
			if addon.currentSpec == "Blood" then
				addon.IsBloodTank = true
				-- For 6.0+, the Mastery spell isn't known, just use level for now
				if _G.UnitLevel("player") >= 80 then
					hasBloodShield = true
				end
				-- Check for Mastery so we know if BS is active
				if _G.IsSpellKnown(SpellIds["Mastery: Blood Shield"]) then
					hasBloodShield = true
				end
				-- Check for VB
				if _G.IsSpellKnown(SpellIds["Vampiric Blood"]) then
					HasVampBlood = true
				end
			else
				addon.IsBloodTank = false
			end
		end
		dsHealAPMod = addon.DsHealAPModifiers[addon.currentSpec] or 1 
		
		--self:CheckGlyphs()
	end

	if addon:IsTrackerEnabled() then
		self:Load()
	else
		self:Unload()
	end
end

function addon:IsTrackerEnabled()
	if addon.IsBloodTank or (addon.isDK and 
		not addon.db.profile.enable_only_for_blood) then
		return true
	else
		return false
	end
end

function BloodShieldTracker:CheckGlyphs()
	hasVBGlyphed = false
	--if not HasVampBlood then return end -- Dont bother with glyph check if he doesnt have the talent
	for id = 1, _G.GetNumGlyphSockets() do
		local enabled, glyphType, glyphTooltipIndex, 
		glyphSpell, iconFilename = _G.GetGlyphSocketInfo(id, nil)
		if enabled then
			if glyphSpell == GlyphIds["Vampiric Blood"] then
				hasVBGlyphed = true
			end
		end
	end

	if self.db.profile.debug then
		local trackerOutputFmt = "Check Glyphs [VB=%s]"
		self:Print(trackerOutputFmt:format(tostring(hasVBGlyphed)))
	end
end

local TierSlotIds = {
	["Head"] = _G.GetInventorySlotInfo("HeadSlot"),
	["Shoulder"] = _G.GetInventorySlotInfo("ShoulderSlot"),
	["Chest"] = _G.GetInventorySlotInfo("ChestSlot"),
	["Legs"] = _G.GetInventorySlotInfo("LegsSlot"),
	["Hands"] = _G.GetInventorySlotInfo("HandsSlot"),
}

local TierIds = {
	["T14 Tank"] = {
		["Head"] = {
			[86656] = true,
			[85316] = true,
			[86920] = true,
			},
		["Shoulder"] = {
			[86654] = true,
			[85314] = true,
			[86922] = true,
			},
		["Chest"] = {
			[86658] = true,
			[85318] = true,
			[86918] = true,
			},
		["Legs"] = {
			[86655] = true,
			[85315] = true,
			[86921] = true,
			},
		["Hands"] = {
			[86657] = true,
			[85317] = true,
			[86919] = true,
			},
	},
	["T16 Tank"] = {
		["Head"] = {
			[99049] = true,
			[99190] = true,
			[99323] = true,
			},
		["Shoulder"] = {
			[99040] = true,
			[99179] = true,
			[99325] = true,
			},
		["Chest"] = {
			[99060] = true,
			[99188] = true,
			[99330] = true,
			},
		["Legs"] = {
			[99039] = true,
			[99191] = true,
			[99324] = true,
			},
		["Hands"] = {
			[99048] = true,
			[99189] = true,
			[99331] = true,
			},
	},
}

local TierSlots = {}
for k, v in pairs(TierSlotIds) do
	TierSlots[v] = true
end

function BloodShieldTracker:CheckGear()
	GearChangeTimer = nil
	local count = 0
	local changed = false

	for tier, ids in pairs(TierIds) do
		count = 0
		for slot, slotid in pairs(TierSlotIds) do
			local id = _G.GetInventoryItemID("player", slotid)
			if ids[slot][id] then
				count = count + 1
			end
		end

		if count ~= addon.tierCount[tier] then
			addon.tierCount[tier] = count
			if self.db.profile.debug and not _G.UnitAffectingCombat("player") then
				local fmt = "%s Detected: %d/5"
				self:Print(fmt:format(tier, addon.tierCount[tier]))
			end
			changed = true
		end
	end

	if changed then
		self:UpdateTierBonus()
		addon:FireCallback("GearUpdate")
	end
end

function BloodShieldTracker:UpdateTierBonus()
end

function BloodShieldTracker:PLAYER_EQUIPMENT_CHANGED(event, slot, hasItem)
	if TierSlots[slot] and not GearChangeTimer then
		GearChangeTimer = self:ScheduleTimer("CheckGear", 1.5)
	end
end

function BloodShieldTracker:GetEffectiveHealingBuffModifiers()
    return (1+iccBuffAmt) * (1+vbHealingInc) * (1+gsHealModifier) * (1+luckOfTheDrawAmt)
end

function BloodShieldTracker:GetEffectiveHealingDebuffModifiers()
    return (1-healingDebuffMultiplier)
end

function BloodShieldTracker:PLAYER_REGEN_DISABLED()
	-- Reset the per fight stats
	LastFightStats:Reset()
	LastFightStats:StartCombat()

	if addon.DEBUG_OUTPUT == true then
		addon.DEBUG_BUFFER = ""
	end
end

function BloodShieldTracker:PLAYER_REGEN_ENABLED()
	LastFightStats:EndCombat()
end

function BloodShieldTracker:PLAYER_ENTERING_WORLD()
	self:CheckAuras()
end

function BloodShieldTracker:PLAYER_ALIVE()
	self:CheckAuras()
end

function BloodShieldTracker:PLAYER_DEAD()
	self:CheckAuras()
end

-- function BloodShieldTracker:UpdateEstimateBar()
-- 	local db = self.estimatebar.db
-- 	if not db.enabled then return end
--
-- 	local estimate = db.bar_mode == "BS" and estimatedBS or estimatedDS
-- 	local text = ""
-- 	local sep = ""
-- 	if db.show_text then
-- 		sep = ": "
-- 		if db.bar_mode == "BS" then
-- 			text = L["EstimateBarBSText"]
-- 		else
-- 			text = L["HealBarText"]
-- 		end
-- 	end
--
-- 	local val
-- 	if db.usePercent then
-- 		val = estBarPercFmt:format(
-- 			addon.FormatWithPrecision(estimate / addon.maxHealth * 100))
-- 	else
-- 		val = addon.FormatNumber(estimate)
-- 	end
--
-- 	self.estimatebar.bar.value:SetText(
-- 		estimateBarFormat:format(
-- 		text, sep, val))
--
-- 	DataFeed.estimateBar = estimate
-- 	if addon.LDBDataFeed then
-- 		addon:UpdateLDBData()
-- 	end
-- end

function BloodShieldTracker:UpdateShieldBarMode()
	local values = {
		["Time"] = true,
		["None"] = true,
	}
    if values[self.shieldbar.db.progress] then
        self.shieldbar.bar:SetMinMaxValues(0, 1)
        self.shieldbar.bar:SetValue(1)
    end
end

function BloodShieldTracker:UpdateBloodChargeBarMode()
	local bar = self.bloodchargebar
    if bar.db.progress == "Charges" then
        bar.bar:SetMinMaxValues(0, addon.MAX_BLOOD_CHARGES)
        bar.bar:SetValue(0)
    else
        bar.bar:SetMinMaxValues(0, 1)
        bar.bar:SetValue(1)        
    end
end

function BloodShieldTracker:UpdateBoneShieldBarMode()
	local bar = self.boneshieldbar
    if bar.db.progress == "Charges" then
        bar.bar:SetMinMaxValues(0, 6)
        bar.bar:SetValue(0)
    else
        bar.bar:SetMinMaxValues(0, 1)
        bar.bar:SetValue(1)        
    end
end

function BloodShieldTracker:ShowShieldBar()
    if self.shieldbar.db.enabled then
        if self.shieldbar.db.progress == "Current" then
            self.shieldbar.bar:SetMinMaxValues(0, self.shieldbar.shield_max)
            self.shieldbar.bar:SetValue(self.shieldbar.shield_curr)
        end
        self:UpdateShieldBarText(
            self.shieldbar.shield_curr, self.shieldbar.shield_max, 100)
        self.shieldbar.bar:Show()
    end
end

function BloodShieldTracker:UpdateShieldBar()
    if not addon.IsBloodTank then return end

	if self.shieldbar.shield_curr < 0 and self.db.profile.debug then
        local badShieldValueFmt = "Bad shield value [Cur=%d, Max=%d]"
        self:Print(badShieldValueFmt:format(
            self.shieldbar.shield_curr, self.shieldbar.shield_max))
    end

    if self.shieldbar.db.progress == "Current" then
        self.shieldbar.bar:SetMinMaxValues(0, self.shieldbar.shield_max)
	    self.shieldbar.bar:SetValue(self.shieldbar.shield_curr)
    end

	local diff
	if self.shieldbar.shield_max > 0 and self.shieldbar.shield_curr > 0 then
	    diff = round(self.shieldbar.shield_curr/self.shieldbar.shield_max*100)
    else
        diff = 0
    end
    self:UpdateShieldBarText(self.shieldbar.shield_curr, self.shieldbar.shield_max, diff)
end

function BloodShieldTracker:UpdateShieldBarText(current, maximum, percent)
    local newText = ""
    local percentFormat = "%d%%"
    
    local currentTxt = addon.FormatNumber(current)
    local maximumTxt = addon.FormatNumber(maximum)
    
    if self.shieldbar.db.text_format == "Full" then
        newText = shieldBarFormatFull:format(currentTxt, maximumTxt, percent)
    elseif self.shieldbar.db.text_format == "OnlyCurrent" then
        newText = currentTxt
    elseif self.shieldbar.db.text_format == "OnlyMax" then
        newText = maximumTxt
    elseif self.shieldbar.db.text_format == "OnlyPerc" then
        newText = percentFormat:format(percent)
    elseif self.shieldbar.db.text_format == "CurrMax" then
        newText = shieldBarFormatNoPer:format(currentTxt, maximumTxt)
    else
        newText = shieldBarFormatFull:format(currentTxt, maximumTxt, percent)
    end

	self.shieldbar.bar.value:SetText(newText)
end

function BloodShieldTracker:COMBAT_LOG_EVENT_UNFILTERED(...)
	local event, timestamp, eventtype, hideCaster, 
		srcGUID, srcName, srcFlags, srcRaidFlags, 
		destGUID, destName, destFlags, destRaidFlags, 
		param9, param10, param11, param12, param13, param14, 
		param15, param16, param17, param18, param19, param20

		event, timestamp, eventtype, hideCaster, 
		srcGUID, srcName, srcFlags, srcRaidFlags,
		destGUID, destName, destFlags, destRaidFlags,
		param9, param10, param11, param12, param13, param14, 
		param15, param16, param17, param18, param19, param20 = ...

	if not event or not eventtype or not destName then return end

	local spellName, spellAbsorb = "", ""

	-- This event fires after the DS heal.
	--if eventtype == "SPELL_CAST_SUCCESS" and srcName == self.playerName and 
	--	param9 == SpellIds["Death Strike"] then
	--	if self.db.profile.debug then
	--		local dsHealFormat = "Estimated DS heal: %d"
	--		self:Print(dsHealFormat:format(estimatedDS))
	--	end
	--end
end

function BloodShieldTracker:NewBloodShield(timestamp, shieldValue, expires)
    self.shieldbar.active = true
    self.shieldbar.shield_curr = 0
    self.shieldbar.shield_max = 0
    self.shieldbar.expires = expires

    if not addon.IsBloodTank or not hasBloodShield then return end

    self.shieldbar.shield_max = self.shieldbar.shield_max + shieldValue
    self.shieldbar.shield_curr = self.shieldbar.shield_curr + shieldValue

    -- Update the LDB data feed
    DataFeed.lastBS = shieldValue
    if addon.LDBDataFeed then
        addon:UpdateLDBData()
    end

    if self.db.profile.debug or addon.DEBUG_OUTPUT then
        local shieldFormat = "Blood Shield Amount: %d"
        if self.db.profile.debug then
            self:Print(shieldFormat:format(shieldValue))
        end

        if addon.DEBUG_OUTPUT then
            addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. 
                shieldFormat:format(shieldValue) .."\n"
        end
    end

    self:UpdateStatsNewShield(shieldValue, false)
    self:ShowShieldBar()

    if self.shieldbar.db.sound_enabled and self.shieldbar.db.sound_applied then
        _G.PlaySoundFile(LSM:Fetch("sound", self.shieldbar.db.sound_applied))
    end
end

function BloodShieldTracker:UpdateStatsNewShield(value, isRefresh)
    TotalShieldStats:NewShield(value, isRefresh)
    LastFightStats:NewShield(value, isRefresh)
end

function BloodShieldTracker:UpdateStatsRemoveShield()
    TotalShieldStats:RemoveShield()
    LastFightStats:RemoveShield()
end

function BloodShieldTracker:UpdateStatsShieldAbsorb(value)
    TotalShieldStats:ShieldAbsorb(value)
    LastFightStats:ShieldAbsorb(value)
end

local shieldRefreshedFormat = "Blood Shield Refreshed: %d%s"
function BloodShieldTracker:BloodShieldUpdated(type, timestamp, current, expires)
	if not addon.IsBloodTank then return end

	if type == "refreshed" then
		self.shieldbar.active = true
		elseif type == "removed" then
			self.shieldbar.active = false
		end

		local curr = self.shieldbar.shield_curr or 0

		-- Calculate how much was added or absorbed
		local added = 0
		local absorbed = 0
		-- Check if the shield was increased due to a new DS/BS
		if current > curr then
			-- A new BS shield amount was added.  Update all of the stats.
			added = current - curr

			self:UpdateStatsNewShield(added, true)
			self.shieldbar.expires = expires
			self.shieldbar.shield_max = self.shieldbar.shield_max + added

			-- Update the LDB data feed
			DataFeed.lastBS = added
			if addon.LDBDataFeed then
				addon:UpdateLDBData()
			end

			if addon.DEBUG_OUTPUT then
				local shieldInd = ""
				addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. 
				shieldRefreshedFormat:format(added,shieldInd) .. "\n"
			end

			if self.shieldbar.db.sound_enabled and self.shieldbar.db.sound_applied then
				_G.PlaySoundFile(LSM:Fetch("sound", self.shieldbar.db.sound_applied))
			end
		elseif current == curr and type == "refreshed" then
			-- No damage taken but refresh the time.
			-- This can happen if we hit the max shield value of maximum health.
			self.shieldbar.expires = expires
		else
			absorbed = curr - current
			self:UpdateStatsShieldAbsorb(absorbed)
		end

		self.shieldbar.shield_curr = current
		curr = current

		local max = self.shieldbar.shield_max

		local currPerc = 0
		if max > 0 then
			currPerc = curr / max * 100
		end

		if self.db.profile.debug then
			local bsRemovedFmt = "Blood Shield %s [%d/%d %d%%]%s"
			local addedFmt = "[Added %d]"
			local statusStr = ""
			if added > 0 then
				statusStr = addedFmt:format(added)
			elseif added == 0 and absorbed == 0 then
				statusStr = "[No change]"
			end
			self:Print(bsRemovedFmt:format(type, curr, max, currPerc, statusStr))
		end

		if type == "removed" then
			self.shieldbar.expires = 0
			self.shieldbar.bar:Hide()
			self:UpdateStatsRemoveShield()
			self.shieldbar.shield_max = 0
			self.shieldbar.shield_curr = 0

			if self.shieldbar.db.sound_enabled and self.shieldbar.db.sound_removed then
				_G.PlaySoundFile(LSM:Fetch("sound", self.shieldbar.db.sound_removed))
			end
		end

		self:UpdateShieldBar()
end

function BloodShieldTracker:ResetStats()
    TotalShieldStats:Reset()
    LastFightStats:Reset()
end

local function onUpdateShieldBar(self, elapsed)
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
				local profile = BloodShieldTracker.db.profile.bars["ShieldBar"]
				if profile.show_time then
					self.time:SetText(tostring(round(self.timer)))
				end
				if profile.progress == "Time" then
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

local function onUpdateBloodCharge(self, elapsed)
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
				local profile = BloodShieldTracker.db.profile.bars["BloodChargeBar"]
				if profile.show_time then
					self.time:SetText(tostring(round(self.timer)))
				end
				if profile.progress == "Time" then
					self:SetValue(self.timer)
				elseif profile.progress == "Charges" then
					self:SetValue(self.count)
				end
				self:Show()
			end
		else
			self:Hide()
		end
		self.lastUpdate = 0
	end
end

local function onUpdateBoneShield(self, elapsed)
	self.lastUpdate = (self.lastUpdate or 0) + elapsed
	self.timer = self.timer - elapsed
	self.recharge = self.recharge - elapsed
	if self.lastUpdate >= 0.1 then
		if self.active then
			local profile = BloodShieldTracker.db.profile.bars["BoneShieldBar"]
			if self.timer > 0 then
				if profile.show_time then
					local remaining = ""
					if self.timer > 60 then
						remaining = tostring(ceil(self.timer / 60)) .. "m"
					else
						remaining = tostring(round(self.timer))
					end
					self.time:SetText(remaining)
				end
				self:Show()
				if profile.progress == "Time" then
					self:SetValue(self.timer)
				elseif profile.progress == "Charges" then
					self:SetValue(self.count)
				end
			else
				self.timer = 0
				self.active = false
				self:SetScript("OnUpdate", nil)
				self:Hide()
			end
		elseif self.recharging then
			if self.recharge >= 0 then
				local remaining = 0
				if self.recharge > 60 then
					remaining = tostring(ceil(self.recharge / 60)) .. "m"
				else
					remaining = tostring(round(self.recharge))
				end
				self.value:SetText(remaining)
			else
				self.recharging = false
				self.recharge = 0
				self.value:SetText("-")
				self:SetScript("OnUpdate", nil)			
			end
		else
			self:Hide()
		end
		self.lastUpdate = 0
	end
end

local function onUpdateAMS(self, elapsed)
	self.lastUpdate = (self.lastUpdate or 0) + elapsed
	self.timer = self.timer - elapsed
	if self.lastUpdate >= 0.1 then
		if self.active then
			local profile = addon.db.profile.bars["AMSBar"]
			if self.timer < 0 then
				self.timer = 0
				self.active = false
				self:SetScript("OnUpdate", nil)
				self:Hide()
			else
				if profile.show_time then
					self.time:SetText(tostring(round(self.timer)))
				end
				self:SetValue(self.timer)
				self:Show()
			end
		else
			self:Hide()
		end
		self.lastUpdate = 0
	end
end

function BloodShieldTracker:UNIT_AURA(event, unit, ...)
	if unit == "player" then
		self:CheckAuras()
	end
end

-- Define auras which require extra data.  Boolean indicates if an absorb.
local TrackWithDataNames = {
	["Blood Shield"] = true,
	["Bone Shield"] = false,
	["Anti-Magic Shell"] = true,
	["Blood Charge"] = false,
}
local TrackWithData = {}
for k, v in pairs(TrackWithDataNames) do
	TrackWithData[SpellIds[k]] = k
end
local BSAuraPresent = false
local BSAuraValue = 0
local BSAuraExpires = 0
local AurasFound = {}
local AuraData = {}
for k, v in pairs(TrackWithDataNames) do
	AuraData[k] = {}
end
local OtherShields = {}
local PreviousShieldValues = {}
local PurgatoryAbsorb = 0
local PurgatoryActive = false

local errorReadingFmt = "Error reading the %s value."
function BloodShieldTracker:CheckAuras()
	local name, rank, icon, count, dispelType, duration, expires,
		caster, stealable, consolidate, spellId, canApplyAura, isBossDebuff,
		castByPlayer, value, value2, value3
	
	-- Reset variables
	wipe(AurasFound)
	wipe(OtherShields)

	local Results

	PurgatoryAbsorb = 0

	-- Loop through unit auras to find ones of interest.
	local i = 1
	repeat
		name, rank, icon, count, dispelType, duration, expires, caster, 
		stealable, consolidate, spellId, canApplyAura, isBossDebuff, 
		castByPlayer, new1, new2, value = UnitAura("player", i)
		if name == nil or spellId == nil then break end

		local tracked = AbsorbShields[spellId]
		local trackedWithData = TrackWithData[spellId]

		if spellId == SpellIds["Scent of Blood"] then
			scentBloodStacks = count

		elseif tracked or trackedWithData then
			if trackedWithData then
				AurasFound[trackedWithData] = true
				AuraData[trackedWithData].value = value
				AuraData[trackedWithData].expires = expires
				AuraData[trackedWithData].duration = duration
				AuraData[trackedWithData].count = count
			end
			if tracked then
				AurasFound[tracked] = true
				if value then
					OtherShields[tracked] = (OtherShields[tracked] or 0) + value
				elseif self.db.profile.debug == true then
					self:Print(errorReadingFmt:format(SpellNames[tracked]))
				end
			end
			
		end 
		i = i + 1
	until name == nil

	i = 1
	repeat
		name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
		consolidate, spellId, canApplyAura, isBossDebuff, 
		castByPlayer, new1, new2, value = UnitAura("player", i, "HARMFUL")
		
		if name == nil or spellId == nil then break end

		if spellId == SpellIds["Shroud of Purgatory"] then
			AurasFound["Shroud of Purgatory"] = true
			if not PurgatoryActive then
				if self.db.profile.debug then
					self:Print("Purgatory! ["..tostring(value or 0).."]")
				end
				PurgatoryActive = true
			end
			PurgatoryAbsorb = value or 0
		end

		i = i + 1
	until name == nil

	if self.pwsbar.db.enabled and addon.IsBloodTank then
		local shields = 0
		local included = self.db.profile.bars["PWSBar"].included
		for k,v in pairs(included) do
			if v then
				shields = shields + (OtherShields[k] or 0)
			end
		end

		if shields > 0 then
			if shields ~= PreviousShieldValues["PWSBar"] then
				self.pwsbar:SetValue(shields)
			end
			self.pwsbar.bar:Show()
		else
			self.pwsbar:Hide()
		end
		PreviousShieldValues["PWSBar"] = shields
	end

	if self.absorbsbar.db.enabled and addon.IsBloodTank then
		local shields = 0
		local tracked = self.db.profile.bars["TotalAbsorbsBar"].tracked
		if tracked ~= "All" then
			local included = self.db.profile.bars["TotalAbsorbsBar"].included
			for k,v in pairs(OtherShields) do
				if included[k] == true then
					shields = shields + v
				end
			end
		end

		if tracked == "All" then
			shields = UnitGetTotalAbsorbs("player") or 0
		elseif tracked == "Excluding" then
			shields = (UnitGetTotalAbsorbs("player") or 0) - shields
		end

		if shields > 0 then
			if shields ~= PreviousShieldValues["TotalAbsorbsBar"] then
				self.absorbsbar:SetValue(shields)
			end
			self.absorbsbar.bar:Show()
		else
			self.absorbsbar:Hide()
		end

		PreviousShieldValues["TotalAbsorbsBar"] = shields
	end

	if self.purgatorybar.db.enabled and AurasFound["Shroud of Purgatory"] then
		self.purgatorybar:SetValue(PurgatoryAbsorb or 0)
		self.purgatorybar.bar:Show()
	else
		PurgatoryActive = false
		self.purgatorybar:Hide()
	end

	-- Checking to see if it is necessary to always update the estimates
	--self:UpdateEstimates("CheckAura", "player")

	if self.db.profile.bars["BloodChargeBar"].enabled then
		local bcBar = self.bloodchargebar
		if AurasFound["Blood Charge"] then
			local data = AuraData["Blood Charge"]
			bcBar.bar.timer = data.expires - GetTime()
			if bcBar.db.progress == "Charges" then
				bcBar.bar:SetMinMaxValues(0, addon.MAX_BLOOD_CHARGES)
			elseif bcBar.db.progress == "Time" then
				bcBar.bar:SetMinMaxValues(0, data.duration)
			else
				bcBar.bar:SetMinMaxValues(0, 1)
			end
			bcBar.bar.value:SetText(tostring(data.count))
			bcBar.bar.active = true
			bcBar.bar.count = data.count
			bcBar.bar:Show()
			bcBar.bar:SetScript("OnUpdate", onUpdateBloodCharge)
		else
			bcBar.bar.active = false
			bcBar.bar.timer = 0
			bcBar.bar:SetScript("OnUpdate", nil)
			bcBar:Hide()
		end
	end

	if self.db.profile.bars["BoneShieldBar"].enabled and addon.IsBloodTank then
		local bar = self.boneshieldbar
		local state = nil
		local data = AuraData["Bone Shield"]
		if AurasFound["Bone Shield"] and data then
			state = 0
			bar.bar.timer = data.expires - GetTime()
			bar.bar.active = true
			if data.count ~= bar.bar.count then
				bar.bar.value:SetText(tostring(data.count))
			end
			bar.bar.count = data.count
			bar.bar.recharging = false
			bar.bar.recharge = 0
		else
			bar.bar.active = false
			bar.bar.timer = 0
			bar.bar.count = 0
			--bar.bar:SetScript("OnUpdate", nil)
			--bar:Hide()

			local start, duration, enabled = 
				GetSpellCooldown(SpellIds["Bone Shield"])
			if duration > 0 then
				state = 1
				bar.bar.recharging = true
				bar.bar.recharge = duration - (GetTime() - start)
			else
				state = 2
				bar.bar.recharging = false
				bar.bar.recharging = 0
			end
		end

		-- Update the display if state has changed
		if state ~= bar.bar.state then
			if state == 0 then
				-- Active
				if bar.db.progress == "Charges" then
					bar.bar:SetMinMaxValues(0, addon.MAX_BONESHIELD_CHARGES)
				elseif bar.db.progress == "Time" then
					bar.bar:SetMinMaxValues(0, data.duration)
				else
					bar.bar:SetMinMaxValues(0, 1)
					bar.bar:SetValue(1)
				end
				bar.bar:SetAlpha(1)
				bar.bar:Show()
				bar.bar:SetScript("OnUpdate", onUpdateBoneShield)
			elseif state == 1 then
				-- Recharging
				bar.bar.time:SetText("")
				if bar.db.showCooldown then
					bar.bar:SetAlpha(0.5)
					bar.bar:SetValue(select(2, bar.bar:GetMinMaxValues()))
					bar.bar:SetScript("OnUpdate", onUpdateBoneShield)
					bar.bar:Show()
				else
					bar:Hide()
				end
			else 
				-- Ready
				bar.bar.time:SetText("")
				bar.bar.value:SetText("-")
				if bar.db.showReady then
					bar.bar:SetAlpha(0.5)
					bar.bar:SetValue(select(2, bar.bar:GetMinMaxValues()))
					bar.bar:SetScript("OnUpdate", nil)
					bar.bar:Show()
				else
					bar:Hide()
				end
			end
		end
		bar.bar.state = state
	end

	if self.db.profile.bars["AMSBar"].enabled then
		local bar = self.amsbar
		if AurasFound["Anti-Magic Shell"] then
			local data = AuraData["Anti-Magic Shell"]
			bar:SetValue(data.value or 0)
			bar.bar.timer = data.expires - GetTime()
			if bar.bar.duration ~= data.duration then
				bar.bar.duration = data.duration
				bar.bar:SetMinMaxValues(0, bar.bar.duration or 1)
			end
			bar.bar.active = true
			bar.bar:Show()
			bar.bar:SetScript("OnUpdate", onUpdateAMS)
		else
			bar.bar.active = false
			bar.bar.timer = 0
			bar.bar:SetScript("OnUpdate", nil)
			bar:Hide()
		end
	end

	if AurasFound["Blood Shield"] then
		local data = AuraData["Blood Shield"]
		if data.value then
			if BSAuraPresent == false then
				-- Blood Shield applied
				if self.db.profile.debug == true then
					self:Print("AURA: Blood Shield applied. "..data.value)
				end
				self:NewBloodShield(GetTime(), data.value, data.expires)
			else
				if data.value ~= BSAuraValue or 
					(data.expires ~= BSAuraExpires and data.value > 0) then
					self:BloodShieldUpdated("refreshed", GetTime(), 
						data.value, data.expires)
				end
			end
			BSAuraValue = data.value
			BSAuraExpires = data.expires

			local bar = self.shieldbar.bar
			local db = self.shieldbar.db
			if db.enabled then
				bar.timer = data.expires - GetTime()
				bar.active = true
				if db.progress == "Time" then
					bar:SetMinMaxValues(0, data.duration)
				end
				bar:Show()
				bar:SetScript("OnUpdate", onUpdateShieldBar)
			end
		else
			if self.db.profile.debug == true then
				self:Print("Error reading the Blood Shield value.")
			end
		end
		BSAuraPresent = true
	else
		if BSAuraPresent == true then
			-- Blood Shield removed
			self:BloodShieldUpdated("removed", GetTime(), BSAuraValue, 0)
		end
		BSAuraPresent = false
		BSAuraValue = 0

		local bar = self.shieldbar.bar
		bar.active = false
		bar.timer = 0
		bar:SetScript("OnUpdate", nil)
		bar.object:Hide()
	end

	addon:FireCallback("Auras")
end
