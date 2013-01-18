local _G = getfenv(0)

local string = _G.string
local table = _G.table
local math = _G.math
local pairs = _G.pairs
local ipairs = _G.ipairs
local select = _G.select

local L = _G.LibStub("AceLocale-3.0"):GetLocale("BloodShieldTracker", true)
local LDB = _G.LibStub("LibDataBroker-1.1")
local LibQTip = _G.LibStub("LibQTip-1.0")
local icon = _G.LibStub("LibDBIcon-1.0")
local LSM = _G.LibStub:GetLibrary("LibSharedMedia-3.0")
local AGU = _G.LibStub("AceGUI-3.0")

local BloodShieldTracker = _G.LibStub("AceAddon-3.0"):NewAddon("BloodShieldTracker", "AceConsole-3.0", "AceEvent-3.0","AceTimer-3.0")
local BST = BloodShieldTracker

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

BloodShieldTracker.ADDON_NAME = ...
BloodShieldTracker.ADDON_VERSION = cleanupVersion("@project-version@")

local DEBUG_OUTPUT = false
local DEBUG_BUFFER = ""

-- Define Bar for now but the rest is at the bottom of the file.
local Bar = {}

-- Local versions for performance
local tinsert, tremove, tgetn = table.insert, table.remove, table.getn
local tconcat = table.concat
local floor, ceil, abs = math.floor, math.ceil, math.abs
local unpack = _G.unpack
local tostring = _G.tostring
local tonumber = _G.tonumber
local wipe = _G.wipe
local type = _G.type

-- Local versions of WoW API calls
local UnitAura = _G.UnitAura
local GetTime = _G.GetTime
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax

BloodShieldTracker.loaded = false
BloodShieldTracker.playerName = UnitName("player")
BloodShieldTracker.bars = {}
BloodShieldTracker.shieldbar = nil
BloodShieldTracker.estimatebar = nil
BloodShieldTracker.pwsbar = nil
BloodShieldTracker.illumbar = nil
BloodShieldTracker.healthbar = nil

-- Player class, talent, and spec info
local isDK = nil
local IsBloodTank = false
local hasBloodShield = false
local HasVampBlood = false
local hasVBGlyphed = false
local HasSuccorGlyphed = false
local Tier14Count = 0
local Tier14Bonus = 1

-- Settings to allow custom fonts and textures which override the
-- user set options.
local CustomUI = {}
CustomUI.texture = nil
CustomUI.font = nil
CustomUI.fontSize = nil
CustomUI.fontFlags = nil
CustomUI.showBorders = nil

-- Keep track of time.  Start with current client time
-- but will use the combat log timestamps after that.
local currentTime = time()
local idle = true
local updateTimer = nil
local lastSeconds = 5
local damageTaken = {}
local removeList = {}
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

    if isMinimum then
        self.numMinShields = self.numMinShields + 1
    end

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
    self.numMinShields = 0
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

local millFmtOne = "%.1fm"
local thousandFmtOne = "%.1fk"
local millFmtZero = "%.0fm"
local thousandFmtZero = "%.0fk"
local millFmt = millFmtZero
local thousandFmt = thousandFmtZero
local baseFmtOne = "%.1f"
local baseFmtZero = "%.0f"
local baseFmt = baseFmtZero

local CURRENT_BUILD, CURRENT_INTERNAL, 
    CURRENT_BUILD_DATE, CURRENT_UI_VERSION = GetBuildInfo()

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

local SpellIds = {
	["Power Word: Shield"] = 17,
	["Divine Aegis"] = 47753,
	["Illuminated Healing"] = 86273,
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
	["Vengeance"] = 132365,
	["Anti-Magic Shell"] = 48707,
	["Bone Shield"] = 49222,
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

local PriestAbsorbsOrdered = {
	"Power Word: Shield",
	"Divine Aegis",
	"Spirit Shell",
}

local AbsorbShieldsOrdered = {
	"Blood Shield",
	"Power Word: Shield",
	"Illuminated Healing",
	"Divine Aegis",
	"Life Cocoon",
	"Spirit Shell",
	"Guard",
	"Indomitable Pride",
	"Anti-Magic Shell",
}
local AbsorbShields = {}
for i, k in ipairs(AbsorbShieldsOrdered) do
	AbsorbShields[SpellIds[k]] = k
end

local GlyphIds = {
	["Vampiric Blood"] = 58676,
	["Dark Succor"] = 96279,
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

-- Constants
local BS_DURATION = 10  -- The duration of Blood Shield
local MAX_BLOOD_CHARGES = 12
local dsHealModifier = 0.20  -- Percent of the DS Heal from the tooltip.
local dsMinHealPercent = 0.07
local dsMinHealPercentSuccor = 0.20
local shieldPerMasteryPoint = 6.25
local scentBloodStackBuff = 0.2
local LUCK_OF_THE_DRAW_MOD = 0.05
local vbGlyphedHealthInc = 0.0
local vbGlyphedHealingInc = 0.4
local vbUnglyphedHealthInc = 0.15
local vbUnglyphedHealingInc = 0.25
local guardianSpiritHealBuff = 0.40
local T14BonusAmt = 0.1

-- Curent state information
local DarkSuccorBuff = false
local DS_SentTime = nil
local DS_Latency = nil
-- The actual minimum DS heal percent, based on spec, glyphs, and presence.
local actualDsMinHeal = dsMinHealPercent
local maxHealth = 0
local currentHealth = 0
local percentHealth = 0
local dsHealMin = 0
local bsMinimum = 0
local scentBloodStacks = 0
local dsScentBloodStacks = 0 -- Have to track SoB stacks as of last DS
local CurrentPresence = nil
local luckOfTheDrawBuff = false
local luckOfTheDrawAmt = 0
local iccBuff = false
local iccBuffAmt = 0.0
local vbBuff = false
local vbHealthInc = 0.0
local vbHealingInc = 0.0
local gsHealModifier = 0.0
local healingDebuffMultiplier = 1
local lastDSSuccess = nil
local masteryRating = 0
local shieldPercent = 0

local HealingDebuffs = {
    -- PvP healing debuffs
	[56112] = 0.20, -- Furious Attacks (Warrior)
	[54680] = 0.25, -- Monstrous Bite (Hunter: Devilsaur)
	[12294] = 0.25, -- Mortal Strike (Warrior)
	[82654] = 0.25, -- Widow Venom (Hunter)
	[13218] = 0.25, -- Wound Poison (Rogue)
	[48301] = 0.25, -- Mind Trauma (Priest)
	[11175] = 0.08, -- Permafrost (Mage)
	[12569] = 0.16, -- Permafrost (Mage)
	[12571] = 0.25, -- Permafrost (Mage)
	[30213] = 0.25, -- Legion Strike (Warlock)
    -- NPCs healing debuffs
	[69674] = 0.50, -- Rotface Mutated Infection
	[73023] = 0.75, -- Rotface Mutated Infection
	[73022] = 0.75, -- Rotface Mutated Infection
	[71224] = 0.50, -- Rotface Mutated Infection
	[71127] = 0.10, -- Stinky/Precious Mortal Wound
	[59455] = 0.75, -- Mortal Strike (NPC)
	[54716] = 0.50, -- Mortal Strike (NPC)
	[19643] = 0.50, -- Mortal Strike (NPC)
    [32736] = 0.50, -- Mortal Strike (NPC)
    [67542] = 0.50, -- Mortal Strike (NPC)
    [13737] = 0.50, -- Mortal Strike (NPC)
    [68784] = 0.50, -- Mortal Strike (NPC)
    [71552] = 0.50, -- Mortal Strike (NPC)
    [68782] = 0.50, -- Mortal Strike (NPC),
    [39171] = 0.06, -- Malevolent Strikes
    [83908] = 0.06, -- Malevolent Strikes
}

local function round(number)
    if not number then return 0 end
    return floor(number+0.5)
end

local ThousandsDelim = ('%.1f'):format(1/5):match('([^0-9])') == '.' and ',' or '.'
local BillionDelimFmt = '%s%d' .. ThousandsDelim .. '%03d' .. ThousandsDelim .. '%03d' .. ThousandsDelim .. '%03d'
local MillionDelimFmt = '%s%d' .. ThousandsDelim .. '%03d' .. ThousandsDelim .. '%03d'
local ThousandDelimFmt = '%s%d' .. ThousandsDelim..'%03d'

local function FormatNumberDelimited(number)
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

local function FormatNumberAbbreviated(number)
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

local function FormatNumberRaw(number)
	return tostring(number)
end

local FormatNumber = FormatNumberAbbreviated

function BloodShieldTracker:SetNumberFormat(format)
	if format == "Delimited" then
		FormatNumber = FormatNumberDelimited
	elseif format == "Raw" then
		FormatNumber = FormatNumberRaw
	else
		FormatNumber = FormatNumberAbbreviated
	end
end

function BloodShieldTracker:SetNumberPrecision()
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

local Broker = _G.CreateFrame("Frame")
Broker.obj = LDB:NewDataObject(_G.GetAddOnMetadata(BST.ADDON_NAME, "Title"), {
    type = "data source",
    icon = "Interface\\Icons\\Spell_DeathKnight_DeathStrike",
    label = _G.GetAddOnMetadata(BST.ADDON_NAME, "Title"),
    text = _G.GetAddOnMetadata(BST.ADDON_NAME, "Title"),
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
local LDBDataFeed = false
local DataFeed = {
    display = "",
    lastDS = 0,
    lastBS = 0,
    estimateBar = 0,
	vengeance = 0,
}

local function UpdateLDBData()
    if DataFeed.display == "LastBS" then
        Broker.obj.text = FormatNumber(DataFeed.lastBS)
    elseif DataFeed.display == "LastDS" then
        Broker.obj.text = FormatNumber(DataFeed.lastDS)
    elseif DataFeed.display == "EstimateBar" then
        Broker.obj.text = FormatNumber(DataFeed.estimateBar)
	elseif DataFeed.display == "Vengeance" then
        Broker.obj.text = FormatNumber(DataFeed.vengeance)
    else
        Broker.obj.text = _G.GetAddOnMetadata(BST.ADDON_NAME, "Title")
    end
end

local function SetBrokerLabel()
    if BloodShieldTracker.db.profile.ldb_short_label then
        Broker.obj.label = L["BST"]
    else
        Broker.obj.label = _G.GetAddOnMetadata(BST.ADDON_NAME, "Title")
    end
end

local addonHdr = GREEN.."%s %s"
local totalDataHdr = ORANGE..L["Total Data"]
local dataLine1 = YELLOW..L["Shields Total/Refreshed/Removed:"]
local dataLine2 = YELLOW..L["Number of Minimum Shields:"]
local shieldDataMinShld = "%d (%d%%)"
local shieldDataLine1Fmt = "%d / %d / %d"
local shieldMaxValueLine1 = YELLOW..L["Min - Max / Avg:"]
local rangeWithAvgFmt = "%d - %d / %d"
local valuesWithPercFmt = "%s / %s - %.1f%%"
local shieldUsageLine1 = YELLOW..L["Absorbed/Total Shields/Percent:"]
local percentFormat = "%.1f%%"
local secondsFormat = "%.1f " .. L["seconds"]
local durationLine = YELLOW..L["Fight Duration:"]
local shieldFreqLine = YELLOW..L["Shield Frequency:"]
local lastFightValueHdr = ORANGE..L["Last Fight Data"]

local function AddStats(tooltip, stats)
    local percentMinimum = 0
    local avgShieldMaxValue
    if stats.numShields > 0 then
        percentMinimum = stats.numMinShields / stats.numShields * 100
        avgShieldMaxValue = stats.totalShields / stats.numShields
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
    tooltip:AddLine(dataLine2, 
        shieldDataMinShld:format(
            stats.numMinShields, 
            percentMinimum))
    tooltip:AddLine(shieldMaxValueLine1, 
        rangeWithAvgFmt:format(
            stats.minShield, 
            stats.maxShield, 
            avgShieldMaxValue or 0))
    tooltip:AddLine(shieldUsageLine1, 
        valuesWithPercFmt:format(
            FormatNumber(stats.totalAbsorbs), 
            FormatNumber(stats.totalShields), shieldUsagePerc))
end

function Broker.obj:OnEnter()
	local tooltip = LibQTip:Acquire("BloodShieldTrackerTooltip", 2, "LEFT", "RIGHT")
	self.tooltip = tooltip 

    tooltip:AddHeader(addonHdr:format(_G.GetAddOnMetadata(BST.ADDON_NAME,"Title"), BST.ADDON_VERSION))
    tooltip:AddLine()

    if isDK then
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

local function IsFrame(frame)
	if frame and type(frame) == "string" then
		local f = _G.GetClickFrame(frame)
		if f and type(f) == "table" and f.SetPoint and f.GetName then
			return true
		end
	end
	return false
end

local configMode = false

local defaults = {
    profile = {
		minimap = {
			hide = true,
		},
        verbose = false,
		debug = false,
        enable_only_for_blood = true,
        precision = "Zero",
		numberFormat = "Abbreviated",
		useAuraForShield = true,
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
				latencyMethod = "None",
				latencyFixed = 0,
				color = {r = 1.0, g = 0.0, b = 0.0, a = 1},
				bgcolor = {r = 0.65, g = 0.0, b = 0.0, a = 0.8},
				alt_color = {r = 0.0, g = 1.0, b = 0.0, a = 1},
				alt_bgcolor = {r = 0.0, g = 0.65, b = 0.0, a = 0.8},
				alt_textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
				width = 90,
				x = 0, 
				y = -120,
			},
			["HealthBar"] = {
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
			},
			["PWSBar"] = {
				color = {r = 1.0, g = 1.0, b = 1.0, a = 1},
				bgcolor = {r = 0.96, g = 0.55, b = 0.73, a = 0.7},
				included = {
					["Power Word: Shield"] = true,
					["Divine Aegis"] = true,
					["Spirit Shell"] = true,
				},
				x = 100, 
				y = -120,
			},
			["IllumBar"] = {
				color = {r = 0.96, g = 0.55, b = 0.73, a = 1},
				bgcolor = {r = 0.96, g = 0.55, b = 0.73, a = 0.7},
				x = 190, 
				y = -120,
			},
			["TotalAbsorbsBar"] = {
				color = {r = 0.58, g = 0.51, b = 0.79, a = 1},
				bgcolor = {r = 0.58, g = 0.51, b = 0.79, a = 0.7},
				included = {
					["Blood Shield"] = false,
					["Power Word: Shield"] = true,
					["Divine Aegis"] = true,
					["Illuminated Healing"] = true,
					["Life Cocoon"] = true,
					["Guard"] = true,
					["Indomitable Pride"] = true,
					["Spirit Shell"] = true,
					["Anti-Magic Shell"] = false,
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
		}
    }
}

local options

function BloodShieldTracker:AddAdvancedPositioning(options, barName)
    options.args.advPos = {
        order = 1000,
        type = "header",
        name = L["Anchor"],
    }

    options.args.description = {
        order = 1001,
        type = "description",
        name = L["Anchor_Desc"],
    }

	options.args.anchorFrame = {
		name = L["Anchor"],
		desc = L["Anchor_OptDesc"],
		type = "select",
		values = {
		    ["None"] = L["None"],
		    ["Custom"] = L["Custom"],
		    --["Compact Runes"] = L["Compact Runes"],
			["Shield Bar"] = L["Shield Bar"],
			["Estimate Bar"] = L["Estimate Bar"],
			["Health Bar"] = L["Health Bar"],
			["PW:S Bar"] = L["PW:S Bar"],
			["Illuminated Healing Bar"] = L["Illuminated Healing Bar"],
			["Total Absorbs Bar"] = L["Total Absorbs Bar"],
			["Anti-Magic Shell Bar"] = L["Anti-Magic Shell Bar"],
		},
		order = 1010,
		set = function(info, val)
		    self.db.profile.bars[barName].anchorFrame = val
			self.bars[barName]:UpdatePosition()
		end,
        get = function(info)
            return self.db.profile.bars[barName].anchorFrame
        end,
	}
	if select(6, _G.GetAddOnInfo("CompactRunes")) ~= "MISSING" or 
		self.db.profile.bars[barName].anchorFrame == "Compact Runes" then
		options.args.anchorFrame.values["Compact Runes"] = 
			L["Compact Runes"]
	end

	options.args.anchorFrameCustom = {
		name = L["Frame"],
		desc = L["Frame_OptDesc"],
		type = "input",
		width = "double",
		order = 1020,
		set = function(info, val)
		    self.db.profile.bars[barName].anchorFrameCustom = val
			self.bars[barName]:UpdatePosition()
		end,
        get = function(info)
            return self.db.profile.bars[barName].anchorFrameCustom
        end,
		disabled = function()
			return self.db.profile.bars[barName].anchorFrame ~= "Custom"
		end,
	}
	options.args.anchorFramePt = {
		name = L["Anchor Point"],
		desc = L["AnchorPoint_OptDesc"],
		type = "select",
		values = {
		    ["TOP"] = L["Top"],
		    ["BOTTOM"] = L["Bottom"],
		    ["LEFT"] = L["Left"],
		    ["RIGHT"] = L["Right"],
		},
		order = 1030,
		set = function(info, val)
		    self.db.profile.bars[barName].anchorFramePt = val
			self.bars[barName]:UpdatePosition()
		end,
        get = function(info)
            return self.db.profile.bars[barName].anchorFramePt
        end,
		disabled = function()
			return self.db.profile.bars[barName].anchorFrame == "None"
		end,
	}
	options.args.anchorPt = {
		name = L["Bar Point"],
		desc = L["BarPoint_OptDesc"],
		type = "select",
		values = {
		    ["TOP"] = L["Top"],
		    ["BOTTOM"] = L["Bottom"],
		    ["LEFT"] = L["Left"],
		    ["RIGHT"] = L["Right"],
		},
		order = 1040,
		set = function(info, val)
		    self.db.profile.bars[barName].anchorPt = val
			self.bars[barName]:UpdatePosition()
		end,
        get = function(info)
            return self.db.profile.bars[barName].anchorPt
        end,
		disabled = function()
			return self.db.profile.bars[barName].anchorFrame == "None"
		end,
	}
	options.args.anchorX = {
		order = 1050,
		name = L["X Offset"],
		desc = L["XOffsetAnchor_Desc"],	
		type = "range",
		softMin = -floor(_G.GetScreenWidth()),
		softMax = floor(_G.GetScreenWidth()),
		bigStep = 1,
		set = function(info, val)
		    self.db.profile.bars[barName].anchorX = val
			self.bars[barName]:UpdatePosition()
		end,
		get = function(info, val)
		    return self.db.profile.bars[barName].anchorX
		end,
		disabled = function()
			return self.db.profile.bars[barName].anchorFrame == "None"
		end,
	}
	options.args.anchorY = {
		order = 1060,
		name = L["Y Offset"],
		desc = L["YOffsetAnchor_Desc"],	
		type = "range",
		softMin = -floor(_G.GetScreenHeight()),
		softMax = floor(_G.GetScreenHeight()),
		bigStep = 1,
		set = function(info, val)
		    self.db.profile.bars[barName].anchorY = val
			self.bars[barName]:UpdatePosition()
		end,
		get = function(info, val)
		    return self.db.profile.bars[barName].anchorY
		end,
		disabled = function()
			return self.db.profile.bars[barName].anchorFrame == "None"
		end,
	}
end

function BloodShieldTracker:ShowOptions()
	_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.ShieldBar)
	_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.Main)
end

function BloodShieldTracker:GetOptions()
    if not options then
        options = {
            type = "group",
            name = _G.GetAddOnMetadata(BST.ADDON_NAME, "Title"),
            args = {
				core = self:GetGeneralOptions(),
				shieldBarOpts = self:GetShieldBarOptions(),
				estimateBarOpts = self:GetEstimateBarOptions(),
				bloodChargeOpts = self:GetBloodChargeBarOptions(),
				boneShieldOpts = self:GetBoneShieldBarOptions(),
				pwsBarOpts = self:GetPWSBarOptions(),
				illumBarOpts = self:GetIllumBarOptions(),
				absorbsBarOpts = self:GetAbsorbsBarOptions(),
				purgatoryBarOpts = self:GetPurgatoryBarOptions(),
				amsBarOpts = self:GetAMSBarOptions(),
				healthBarOpts = self:GetHealthBarOptions(),
				skinningOpts = self:GetSkinningOptions(),
            }
        }
		options.args.profile = _G.LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    end
    return options
end

function BloodShieldTracker:GetGeneralOptions()
	local testNumber = 12000
	local core = {
	    order = 1,
		name = L["General Options"],
		type = "group",
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["BloodShieldTracker_Desc"],
		    },
		    generalOptions = {
		        order = 2,
		        type = "header",
		        name = L["General Options"],
		    },
            enable_only_for_blood = {
                name = L["Only for Blood DK"],
				order = 10,
                desc = L["OnlyForBlood_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.enable_only_for_blood = val
                    self:CheckTalents()
                end,
                get = function(info)
                    return self.db.profile.enable_only_for_blood
                end,
            },
    	    minimap = {
    			order = 20,
                name = L["Minimap Button"],
                desc = L["Toggle the minimap button"],
                type = "toggle",
                set = function(info,val)
                    	-- Reverse the value since the stored value is to hide it
                        self.db.profile.minimap.hide = not val
                    	if self.db.profile.minimap.hide then
                    		icon:Hide("BloodShieldTrackerLDB")
                    	else
                    		icon:Show("BloodShieldTrackerLDB")
                    	end
                      end,
                get = function(info)
            	        -- Reverse the value since the stored value is to hide it
                        return not self.db.profile.minimap.hide
                      end,
            },
            verbose = {
                name = L["Verbose"],
				order = 30,
                desc = L["Toggles the display of informational messages"],
                type = "toggle",
                set = function(info, val) self.db.profile.verbose = val end,
                get = function(info) return self.db.profile.verbose end,
            },
			numberFormat = {
				name = L["Number Format"],
				desc = L["NumberFormat_OptionDesc"],
				type = "select",
				values = {
				    ["Raw"] = L["Raw"] .. 
						" (" .. FormatNumberRaw(testNumber) .. ")",
				    ["Delimited"] = L["Delimited"] .. 
						" (" .. FormatNumberDelimited(testNumber) .. ")",
				    ["Abbreviated"] = L["Abbreviated"] .. 
						" (" .. FormatNumberAbbreviated(testNumber) .. ")"
				},
				order = 34,
				set = function(info, val)
				    self.db.profile.numberFormat = val
					self:SetNumberFormat(val)
				end,
                get = function(info)
                    return self.db.profile.numberFormat
                end,
			},
			precision = {
				name = L["Precision"],
				desc = L["Precision_OptionDesc"],
				type = "select",
				values = {
				    ["Zero"] = L["Zero"],
				    ["One"] = L["One"]
				},
				order = 35,
				set = function(info, val)
				    self.db.profile.precision = val
					self:SetNumberPrecision()
				end,
                get = function(info)
                    return self.db.profile.precision
                end,
			},
			config_mode = {
				name = L["Config Mode"],
				desc = L["Toggle config mode"],
				type = "execute",
				order = 50,
				func = function()
				    configMode = not configMode
					if configMode then
						for name, bar in pairs(self.bars) do
							bar.bar:Show()
						end
					else
						self.shieldbar.bar:Hide()
						if self.estimatebar.db.hide_ooc and 
							not _G.InCombatLockdown() then
						    self.estimatebar.bar:Hide()
                        end
						self.bloodchargebar.bar:Hide()
						self.boneshieldbar.bar:Hide()
						self.pwsbar.bar:Hide()
						self.illumbar.bar:Hide()
						self.absorbsbar.bar:Hide()
						self.purgatorybar.bar:Hide()
						self.amsbar.bar:Hide()
						if not self.healthbar.db.enabled or 
							(self.healthbar.db.hide_ooc and 
							not _G.InCombatLockdown()) then
						    self.healthbar.bar:Hide()
                        end
					end
				end,
			},
		    fonts = {
		        order = 60,
		        type = "header",
		        name = L["Font"],
		    },
			bar_font_size = {
				order = 70,
				name = L["Font size"],
				desc = L["Font size for the bars."],
				type = "range",
				min = 8,
				max = 30,
				step = 1,
				set = function(info, val) 
					self.db.profile.font_size = val 
					BloodShieldTracker:ResetFonts()
				end,
				get = function(info,val) return self.db.profile.font_size end,
			},
			bar_font = {
				order = 80,
				type = "select",
				name = L["Font"],
				desc = L["Font to use."],
				values = LSM:HashTable("font"),
				dialogControl = 'LSM30_Font',
				get = function() return self.db.profile.font_face end,
				set = function(info, val) 
				    self.db.profile.font_face = val
				    self:ResetFonts()
				end
			},
			bar_font_outline = {
				name = L["Outline"],
				desc = L["FontOutline_OptionDesc"],
				type = "toggle",
				order = 90,
				set = function(info, val)
				    self.db.profile.font_outline = val
				    self:ResetFonts()
				end,
                get = function(info)
                    return self.db.profile.font_outline
                end,
			},
			bar_font_monochrome = {
				name = L["Monochrome"],
				desc = L["FontMonochrome_OptionDesc"],
				type = "toggle",
				order = 100,
				set = function(info, val)
				    self.db.profile.font_monochrome = val
				    self:ResetFonts()
				end,
                get = function(info)
                    return self.db.profile.font_monochrome
                end,
			},
			bar_font_thickoutline = {
				name = L["Thick Outline"],
				desc = L["FontThickOutline_OptionDesc"],
				type = "toggle",
				order = 110,
				set = function(info, val)
				    self.db.profile.font_thickoutline = val
				    self:ResetFonts()
				end,
                get = function(info)
                    return self.db.profile.font_thickoutline
                end,
			},
		    ldb = {
		        order = 300,
		        type = "header",
		        name = L["LDB"],
		    },
			ldb_short_label = {
				name = L["Short Label"],
				desc = L["ShortLabel_OptionDesc"],
				type = "toggle",
				order = 310,
				set = function(info, val)
				    self.db.profile.ldb_short_label = val
				    SetBrokerLabel()
				end,
                get = function(info)
                    return self.db.profile.ldb_short_label
                end,
			},
			ldb_data_feed = {
				name = L["Data Feed"],
				desc = L["DataFeed_OptionDesc"],
				type = "select",
				values = {
				    ["None"] = L["None"],
				    ["LastDS"] = L["Last Death Strike Heal"],
				    ["LastBS"] = L["Last Blood Shield Value"],
				    ["EstimateBar"] = L["Estimate Bar Value"],
					["Vengeance"] = SpellNames["Vengeance"],
				},
				order = 320,
				set = function(info, val)
				    self.db.profile.ldb_data_feed = val
				    DataFeed.display = val
				    if val == "None" then
				        LDBDataFeed = false
			        else
			            LDBDataFeed = true
		            end
				    UpdateLDBData()
				end,
                get = function(info)
                    return self.db.profile.ldb_data_feed
                end,
			},
		},
	}
	return core
end

function BloodShieldTracker:GetShieldBarOptions()
	local shieldBarOpts = {
		order = 2,
		type = "group",
		name = L["Blood Shield Bar"],
		desc = L["Blood Shield Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["BloodShieldBar_Desc"],
		    },
            generalOptions = {
                order = 2,
                type = "header",
                name = L["General Options"],
            },
    		status_bar_enabled = {
				name = L["Enabled"],
				desc = L["Enable the Blood Shield Bar."],
				type = "toggle",
				order = 10,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].enabled = val
					self.bars["ShieldBar"]:UpdateVisibility()
				end,
                get = function(info)
					return self.db.profile.bars["ShieldBar"].enabled
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].locked = val 
					self.shieldbar:Lock()
				end,
                get = function(info)
					return self.db.profile.bars["ShieldBar"].locked
				end,
			},
			text_format = {
				name = L["Text Format"],
				desc = L["ShieldTextFormat_OptionDesc"],
				type = "select",
				values = {
				    ["Full"] = L["Full"],
				    ["OnlyPerc"] = L["Only Percent"],
				    ["OnlyCurrent"] = L["Only Current"],
				    ["OnlyMax"] = L["Only Maximum"],
				    ["CurrMax"] = L["Current and Maximum"]
				},
				order = 30,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].text_format = val
				end,
                get = function(info)
                    return self.db.profile.bars["ShieldBar"].text_format
                end,
			},
			progress = {
				name = L["Progress Bar"],
				desc = L["ShieldProgress_OptionDesc"],
				type = "select",
				values = {
				    ["None"] = L["None"],
				    ["Time"] = L["Time Remaining"],
				    ["Current"] = L["Current Value"]
				},
				order = 40,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].progress = val
				    if val == "Time" or val == "None" then
				        self:UpdateShieldBarMode()
			        end
				end,
                get = function(info)
                    return self.db.profile.bars["ShieldBar"].progress
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
				    self.db.profile.bars["ShieldBar"].show_time = val
				    if val then
				        self.shieldbar.bar.time:Show()
			        else
			            self.shieldbar.bar.time:Hide()
		            end
				end,
                get = function(info)
                    return self.db.profile.bars["ShieldBar"].show_time
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
				    self.db.profile.bars["ShieldBar"].time_pos = val
			        self.shieldbar.bar.time:SetPoint(val or "RIGHT")
			        self.shieldbar.bar.time:SetJustifyH(val or "RIGHT")
				end,
                get = function(info)
                    return self.db.profile.bars["ShieldBar"].time_pos
                end,
                disabled = function()
                    return not self.db.profile.bars["ShieldBar"].show_time
                end,
			},
            sound = {
                order = 200,
                type = "header",
                name = L["Sound"],
            },
			sound_enabled = {
				name = L["Enabled"],
				desc = L["ShieldSoundEnabledDesc"],
				type = "toggle",
				order = 210,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].sound_enabled = val
				end,
                get = function(info)
                    return self.db.profile.bars["ShieldBar"].sound_enabled
                end,
			},
			applied_sound = {
				order = 220,
				name = L["Applied Sound"],
				desc = L["AppliedSoundDesc"],
				type = "select",
				values = LSM:HashTable("sound"),
				dialogControl = 'LSM30_Sound',
				get = function()
				    return self.db.profile.bars["ShieldBar"].sound_applied
				end,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].sound_applied = val
				end,
				disabled = function()
				    return not self.db.profile.bars["ShieldBar"].sound_enabled
				end,
			},
			removed_sound = {
				order = 230,
				name = L["Removed Sound"],
				desc = L["RemovedSoundDesc"],
				type = "select",
				values = LSM:HashTable("sound"),
				dialogControl = 'LSM30_Sound',
				get = function()
				    return self.db.profile.bars["ShieldBar"].sound_removed
				end,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].sound_removed = val
				end,
				disabled = function()
				    return not self.db.profile.bars["ShieldBar"].sound_enabled
				end,
			},
            dimensions = {
                order = 300,
                type = "header",
                name = L["Dimensions"],
            },
			width = {
				order = 310,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 50,
				max = 300,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].width = val 
					self.shieldbar.bar:SetWidth(val)
					self.shieldbar.bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["ShieldBar"].width
				end,
			},
			height = {
				order = 320,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 10,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].height = val 
					self.shieldbar.bar:SetHeight(val)
					self.shieldbar.bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["ShieldBar"].height
				end,					
			},
			scale = {
				order = 330,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
					return self.db.profile.bars["ShieldBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].scale = val
				    self.shieldbar.bar:SetScale(val)
				end
			},
            position = {
                order = 400,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 410,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].x = val
					self.shieldbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["ShieldBar"].x, 
						self.db.profile.bars["ShieldBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["ShieldBar"].x
				end,
			},
			y = {
				order = 420,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].y = val
					self.shieldbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["ShieldBar"].x, 
						self.db.profile.bars["ShieldBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["ShieldBar"].y
				end,
			},
            colors = {
                order = 500,
                type = "header",
                name = L["Colors"],
            },
			textcolor = {
				order = 510,
				name = L["Text Color"],
				desc = L["BloodShieldBarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["ShieldBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.shieldbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["ShieldBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			color = {
				order = 520,
				name = L["Bar Color"],
				desc = L["BloodShieldBarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["ShieldBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.shieldbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["ShieldBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bgcolor = {
				order = 530,
				name = L["Bar Depleted Color"],
				desc = L["BloodShieldDepletedBarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["ShieldBar"].bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.shieldbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["ShieldBar"].bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 600,
                type = "header",
                name = L["Appearance"],
            },
			texture_opt = {
				order = 610,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["ShieldBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].texture = val
				    self.shieldbar:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["ShieldBar"].shown
				end,
			},
			border_visible_opt = {
				order = 620,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["ShieldBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["ShieldBar"].border = val
				    self.shieldbar:UpdateBorder()
				end,
			},
			visible_opt = {
				order = 630,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
					return self.db.profile.bars["ShieldBar"].shown
				end,
				set = function(info,val) 
			        self.db.profile.bars["ShieldBar"].shown = val
			        self.shieldbar:UpdateUI()
			    end,
			},
		},
	}

	self:AddAdvancedPositioning(shieldBarOpts, "ShieldBar")
	return shieldBarOpts
end

function BloodShieldTracker:GetBloodChargeBarOptions()
	local bloodChargeOpts = {
		order = 2,
		type = "group",
		name = L["Blood Charge Bar"],
		desc = L["Blood Charge Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["BloodChargeBar_Desc"],
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
				    self.db.profile.bars["BloodChargeBar"].enabled = val
					self.bars["BloodChargeBar"]:UpdateVisibility()
				end,
                get = function(info)
					return self.db.profile.bars["BloodChargeBar"].enabled
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].locked = val 
					self.bars["BloodChargeBar"]:Lock()
				end,
                get = function(info)
					return self.db.profile.bars["BloodChargeBar"].locked
				end,
			},
			progress = {
				name = L["Progress Bar"],
				desc = L["BloodChargeProgress_OptionDesc"],
				type = "select",
				values = {
				    ["None"] = L["None"],
				    ["Time"] = L["Time Remaining"],
				    ["Charges"] = L["Charges"]
				},
				order = 40,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].progress = val
			        self:UpdateBloodChargeBarMode()
				end,
                get = function(info)
                    return self.db.profile.bars["BloodChargeBar"].progress
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
				    self.db.profile.bars["BloodChargeBar"].show_time = val
				    if val then
				        self.bars["BloodChargeBar"].bar.time:Show()
			        else
			            self.bars["BloodChargeBar"].bar.time:Hide()
		            end
				end,
                get = function(info)
                    return self.db.profile.bars["BloodChargeBar"].show_time
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
				    self.db.profile.bars["BloodChargeBar"].time_pos = val
			        self.bars["BloodChargeBar"].bar.time:SetPoint(val or "RIGHT")
			        self.bars["BloodChargeBar"].bar.time:SetJustifyH(val or "RIGHT")
				end,
                get = function(info)
                    return self.db.profile.bars["BloodChargeBar"].time_pos
                end,
                disabled = function()
                    return not self.db.profile.bars["BloodChargeBar"].show_time
                end,
			},
            dimensions = {
                order = 300,
                type = "header",
                name = L["Dimensions"],
            },
			width = {
				order = 310,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 50,
				max = 300,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].width = val 
					self.bars["BloodChargeBar"].bar:SetWidth(val)
					self.bars["BloodChargeBar"].bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["BloodChargeBar"].width
				end,
			},
			height = {
				order = 320,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 10,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].height = val 
					self.bars["BloodChargeBar"].bar:SetHeight(val)
					self.bars["BloodChargeBar"].bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["BloodChargeBar"].height
				end,					
			},
			scale = {
				order = 330,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
					return self.db.profile.bars["BloodChargeBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].scale = val
				    self.bars["BloodChargeBar"].bar:SetScale(val)
				end
			},
            position = {
                order = 400,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 410,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].x = val
					self.bars["BloodChargeBar"].bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["BloodChargeBar"].x, 
						self.db.profile.bars["BloodChargeBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["BloodChargeBar"].x
				end,
			},
			y = {
				order = 420,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].y = val
					self.bars["BloodChargeBar"].bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["BloodChargeBar"].x, 
						self.db.profile.bars["BloodChargeBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["BloodChargeBar"].y
				end,
			},
            colors = {
                order = 500,
                type = "header",
                name = L["Colors"],
            },
			textcolor = {
				order = 510,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["BloodChargeBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["BloodChargeBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["BloodChargeBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			color = {
				order = 520,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["BloodChargeBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["BloodChargeBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["BloodChargeBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bgcolor = {
				order = 530,
				name = L["Bar Background Color"],
				desc = L["BarBackgroundColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["BloodChargeBar"].bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["BloodChargeBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["BloodChargeBar"].bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 600,
                type = "header",
                name = L["Appearance"],
            },
			texture_opt = {
				order = 610,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["BloodChargeBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].texture = val
				    self.bars["BloodChargeBar"]:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["BloodChargeBar"].shown
				end,
			},
			border_visible_opt = {
				order = 620,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["BloodChargeBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["BloodChargeBar"].border = val
				    self.bars["BloodChargeBar"]:UpdateBorder()
				end,
			},
			visible_opt = {
				order = 630,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
					return self.db.profile.bars["BloodChargeBar"].shown
				end,
				set = function(info,val) 
			        self.db.profile.bars["BloodChargeBar"].shown = val
			        self.bars["BloodChargeBar"]:UpdateUI()
			    end,
			},
		},
	}

	self:AddAdvancedPositioning(bloodChargeOpts, "BloodChargeBar")
	return bloodChargeOpts
end

function BloodShieldTracker:GetBoneShieldBarOptions()
	local boneShieldOpts = {
		order = 2,
		type = "group",
		name = L["Bone Shield Bar"],
		desc = L["Bone Shield Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["BoneShieldBar_Desc"],
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
				    self.db.profile.bars["BoneShieldBar"].enabled = val
					self.bars["BoneShieldBar"]:UpdateVisibility()
				end,
                get = function(info)
					return self.db.profile.bars["BoneShieldBar"].enabled
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].locked = val 
					self.bars["BoneShieldBar"]:Lock()
				end,
                get = function(info)
					return self.db.profile.bars["BoneShieldBar"].locked
				end,
			},
			progress = {
				name = L["Progress Bar"],
				desc = L["BoneShieldProgress_OptionDesc"],
				type = "select",
				values = {
				    ["None"] = L["None"],
				    ["Time"] = L["Time Remaining"],
				    ["Charges"] = L["Charges"]
				},
				order = 30,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].progress = val
			        self:UpdateBoneShieldBarMode()
				end,
                get = function(info)
                    return self.db.profile.bars["BoneShieldBar"].progress
                end,
			},
			showCooldown = {
				name = L["Show on Cooldown"],
				desc = L["ShowCooldownDesc"],
				type = "toggle",
				order = 40,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].showCooldown = val
				end,
                get = function(info)
					return self.db.profile.bars["BoneShieldBar"].showCooldown
				end,
			},
			showReady = {
				name = L["Show when Ready"],
				desc = L["ShowReadyDesc"],
				type = "toggle",
				order = 50,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].showReady = val
				end,
                get = function(info)
					return self.db.profile.bars["BoneShieldBar"].showReady
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
				    self.db.profile.bars["BoneShieldBar"].show_time = val
				    if val then
				        self.bars["BoneShieldBar"].bar.time:Show()
			        else
			            self.bars["BoneShieldBar"].bar.time:Hide()
		            end
				end,
                get = function(info)
                    return self.db.profile.bars["BoneShieldBar"].show_time
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
				    self.db.profile.bars["BoneShieldBar"].time_pos = val
			        self.bars["BoneShieldBar"].bar.time:SetPoint(val or "RIGHT")
			        self.bars["BoneShieldBar"].bar.time:SetJustifyH(val or "RIGHT")
				end,
                get = function(info)
                    return self.db.profile.bars["BoneShieldBar"].time_pos
                end,
                disabled = function()
                    return not self.db.profile.bars["BoneShieldBar"].show_time
                end,
			},
            dimensions = {
                order = 300,
                type = "header",
                name = L["Dimensions"],
            },
			width = {
				order = 310,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 50,
				max = 300,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].width = val 
					self.bars["BoneShieldBar"].bar:SetWidth(val)
					self.bars["BoneShieldBar"].bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["BoneShieldBar"].width
				end,
			},
			height = {
				order = 320,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 10,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].height = val 
					self.bars["BoneShieldBar"].bar:SetHeight(val)
					self.bars["BoneShieldBar"].bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["BoneShieldBar"].height
				end,					
			},
			scale = {
				order = 330,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
					return self.db.profile.bars["BoneShieldBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].scale = val
				    self.bars["BoneShieldBar"].bar:SetScale(val)
				end
			},
            position = {
                order = 400,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 410,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].x = val
					self.bars["BoneShieldBar"].bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["BoneShieldBar"].x, 
						self.db.profile.bars["BoneShieldBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["BoneShieldBar"].x
				end,
			},
			y = {
				order = 420,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].y = val
					self.bars["BoneShieldBar"].bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["BoneShieldBar"].x, 
						self.db.profile.bars["BoneShieldBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["BoneShieldBar"].y
				end,
			},
            colors = {
                order = 500,
                type = "header",
                name = L["Colors"],
            },
			textcolor = {
				order = 510,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["BoneShieldBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["BoneShieldBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["BoneShieldBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			color = {
				order = 520,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["BoneShieldBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["BoneShieldBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["BoneShieldBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bgcolor = {
				order = 530,
				name = L["Bar Background Color"],
				desc = L["BarBackgroundColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["BoneShieldBar"].bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["BoneShieldBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["BoneShieldBar"].bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 600,
                type = "header",
                name = L["Appearance"],
            },
			texture_opt = {
				order = 610,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["BoneShieldBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].texture = val
				    self.bars["BoneShieldBar"]:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["BoneShieldBar"].shown
				end,
			},
			border_visible_opt = {
				order = 620,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["BoneShieldBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["BoneShieldBar"].border = val
				    self.bars["BoneShieldBar"]:UpdateBorder()
				end,
			},
			visible_opt = {
				order = 630,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
					return self.db.profile.bars["BoneShieldBar"].shown
				end,
				set = function(info,val) 
			        self.db.profile.bars["BoneShieldBar"].shown = val
			        self.bars["BoneShieldBar"]:UpdateUI()
			    end,
			},
		},
	}

	self:AddAdvancedPositioning(boneShieldOpts, "BoneShieldBar")
	return boneShieldOpts
end

function BloodShieldTracker:GetEstimateBarOptions()
	local estimateBarOpts = {
	    order = 3,
	    type = "group",
	    name = L["Estimated Healing Bar"],
	    desc = L["Estimated Healing Bar"],
	    args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["EstimatedHealingBar_Desc"],
		    },
            generalOptions = {
                order = 10,
                type = "header",
                name = L["General Options"],
            },
    		enabled = {
				name = L["Enabled"],
				desc = L["Enable the Estimated Healing Bar."],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].enabled = val
					self.bars["EstimateBar"]:UpdateVisibility()
				end,
                get = function(info)
					return self.db.profile.bars["EstimateBar"].enabled 
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 30,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].locked = val 
					self.estimatebar:Lock()
				end,
                get = function(info)
					return self.db.profile.bars["EstimateBar"].locked
				end,
			},
			hide_ooc = {
				name = L["Hide out of combat"],
				desc = L["HideOOC_OptionDesc"],
				type = "toggle",
				order = 40,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].hide_ooc = val
					if not _G.InCombatLockdown() then
					    if val then
					        self.estimatebar.bar:Hide()
				        elseif self:IsTrackerEnabled() then
				            self.estimatebar.bar:Show()
			            end
			        end
				end,
                get = function(info)
                    return self.db.profile.bars["EstimateBar"].hide_ooc
                end,
			},
			show_text = {
				name = L["Show Text"],
				desc = L["EstHealBarShowText_OptDesc"],
				type = "toggle",
				order = 50,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].show_text = val
				    self:UpdateMinHeal("UpdateShowText", "player")
				end,
                get = function(info)
					return self.db.profile.bars["EstimateBar"].show_text
				end,
			},
			bar_mode = {
				name = L["Mode"],
				desc = L["Mode"],
				type = "select",
				values = {
				    ["DS"] = L["Death Strike Heal"],
				    ["BS"] = L["Blood Shield"],
				},
				order = 60,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].bar_mode = val
				end,
                get = function(info)
                    return self.db.profile.bars["EstimateBar"].bar_mode
                end,
			},
    		usePercent = {
				name = L["Percent"],
				desc = L["Percent_OptDesc"],
				type = "toggle",
				order = 70,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].usePercent = val
				end,
                get = function(info)
					return self.db.profile.bars["EstimateBar"].usePercent 
				end,
			},
    		alternateMinimum = {
				order = 80,
				name = L["Alternate Minimum"],
				desc = L["AlternateMinimum_OptDesc"],
				type = "range",
				min = 0,
				max = 1000000,
				step = 1,
				bigStep = 1000,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].alternateMinimum = val
				end,
                get = function(info)
					return self.db.profile.bars["EstimateBar"].alternateMinimum 
				end,
			},
            sobStacks = {
                order = 100,
                type = "header",
                name = SpellNames["Scent of Blood"],
            },
			show_stacks = {
				name = L["Enable"],
				desc = L["SoBStacks_OptionDesc"],
				type = "toggle",
				order = 110,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].show_stacks = val
					self.bars["EstimateBar"]:UpdateVisibility()
				end,
                get = function(info)
                    return self.db.profile.bars["EstimateBar"].show_stacks
                end,
			},
			stacks_pos = {
				name = L["Position"],
				desc = L["Position_OptionDesc"],
				type = "select",
				values = {
				    ["RIGHT"] = L["Right"],
				    ["LEFT"] = L["Left"],
				},
				order = 120,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].stacks_pos = val
			        self.estimatebar.bar.stacks:SetPoint(val or "LEFT")
			        self.estimatebar.bar.stacks:SetJustifyH(val or "LEFT")
				end,
                get = function(info)
                    return self.db.profile.bars["EstimateBar"].stacks_pos
                end,
                disabled = function()
                    return not self.db.profile.bars["EstimateBar"].show_stacks
                end,
			},
            dimensions = {
                order = 200,
                type = "header",
                name = L["Dimensions"],
            },
			bar_width = {
				order = 210,
				name = L["Width"],
				desc = L["Change the width of the estimated healing bar."],	
				type = "range",
				min = 10,
				max = 200,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].width = val 
					self.estimatebar.bar:SetWidth(val)
					self.estimatebar.bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["EstimateBar"].width
				end,
			},
			bar_height = {
				order = 220,
				name = L["Height"],
				desc = L["Change the height of the estimated healing bar."],	
				type = "range",
				min = 8,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].height = val 
					self.estimatebar.bar:SetHeight(val)
					self.estimatebar.bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["EstimateBar"].height
				end,
			},
			bar_scaling = {
				order = 230,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
				    return self.db.profile.bars["EstimateBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].scale = val
				    self.estimatebar.bar:SetScale(val)
				end
			},
            position = {
                order = 300,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 310,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].x = val
					self.estimatebar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["EstimateBar"].x, 
						self.db.profile.bars["EstimateBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["EstimateBar"].x
				end,
			},
			y = {
				order = 320,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].y = val
					self.estimatebar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["EstimateBar"].x, 
						self.db.profile.bars["EstimateBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["EstimateBar"].y
				end,
			},
            colorsMinimum = {
                order = 400,
                type = "header",
                name = L["Colors for Minimum Heal"],
            },
			min_textcolor = {
				order = 410,
				name = L["Minimum Text Color"],
				desc = L["EstHealBarMinTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["EstimateBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
					self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["EstimateBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			min_color = {
				order = 420,
				name = L["Minimum Bar Color"],
				desc = L["EstHealBarMinColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["EstimateBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["EstimateBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			min_bgcolor = {
				order = 430,
				name = L["Minimum Bar Background Color"],
				desc = L["EstHealBarMinBackgroundColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["EstimateBar"].bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["EstimateBar"].bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
            colorsOptimal = {
                order = 500,
                type = "header",
                name = L["Colors for Optimal Heal"],
            },
			opt_textcolor = {
				order = 510,
				name = L["Optimal Text Color"],
				desc = L["EstHealBarOptTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["EstimateBar"].alt_textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["EstimateBar"].alt_textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			opt_color = {
				order = 520,
				name = L["Optimal Bar Color"],
				desc = L["EstHealBarOptColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["EstimateBar"].alt_color
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["EstimateBar"].alt_color
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 600,
                type = "header",
                name = L["Appearance"],
            },
			texture_opt = {
				order = 610,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["EstimateBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].texture = val
				    self.estimatebar:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["EstimateBar"].shown
				end,
			},
			border_visible_opt = {
				order = 620,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["EstimateBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].border = val
				    self.estimatebar:UpdateBorder()
				end,
			},
			visible_opt = {
				order = 630,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["EstimateBar"].shown
				end,
				set = function(info,val)
				    self.db.profile.bars["EstimateBar"].shown = val
				    self.estimatebar:UpdateUI()
				end,
			},
            latencyOptions = {
                order = 700,
                type = "header",
                name = L["Latency"],
            },
			latencyMode = {
				name = L["Mode"],
				desc = L["Mode"],
				type = "select",
				values = {
				    ["None"] = L["None"],
				    ["DS"] = L["Death Strike"],
				    ["Fixed"] = L["Fixed"],
				},
				order = 710,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].latencyMethod = val
				end,
                get = function(info)
                    return self.db.profile.bars["EstimateBar"].latencyMethod
                end,
			},
			latencyFixed = {
				order = 720,
				name = L["Fixed"],
				desc = L["Fixed"],
				type = "range",
				min = 0,
				max = 2000,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["EstimateBar"].latencyFixed = val 
				end,
				get = function(info, val)
				    return self.db.profile.bars["EstimateBar"].latencyFixed
				end,					
			},
		}
	}
	self:AddAdvancedPositioning(estimateBarOpts, "EstimateBar")
	return estimateBarOpts
end

function BloodShieldTracker:GetPWSBarOptions()
	local pwsBarOpts = {
		order = 4,
		type = "group",
		name = L["PW:S Bar"],
		desc = L["PW:S Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["PWSBar_Desc"],
		    },
            generalOptions = {
                order = 2,
                type = "header",
                name = L["General Options"],
            },
    		enabled = {
				name = L["Enabled"],
				desc = L["EnableBarDesc"],
				type = "toggle",
				order = 10,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].enabled = val
					self.bars["PWSBar"]:UpdateVisibility()
				end,
                get = function(info)
					return self.db.profile.bars["PWSBar"].enabled
				end,
			},
			locked = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].locked = val 
					self.bars["PWSBar"]:Lock(val)
				end,
                get = function(info)
					return self.db.profile.bars["PWSBar"].locked
				end,
			},
            includedOptions = {
                order = 100,
                type = "header",
                name = L["Included Absorbs"],
            },

            dimensions = {
                order = 300,
                type = "header",
                name = L["Dimensions"],
            },
			width = {
				order = 310,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 50,
				max = 300,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].width = val 
					self.bars["PWSBar"].bar:SetWidth(val)
					self.bars["PWSBar"].bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["PWSBar"].width
				end,
			},
			height = {
				order = 320,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 10,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].height = val 
					self.bars["PWSBar"].bar:SetHeight(val)
					self.bars["PWSBar"].bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["PWSBar"].height
				end,					
			},
			scaling = {
				order = 330,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
					return self.db.profile.bars["PWSBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].scale = val
				    self.bars["PWSBar"].bar:SetScale(val)
				end
			},
            position = {
                order = 390,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 391,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].x = val
					self.pwsbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["PWSBar"].x, 
						self.db.profile.bars["PWSBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["PWSBar"].x
				end,
			},
			y = {
				order = 392,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].y = val
					self.pwsbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["PWSBar"].x, 
						self.db.profile.bars["PWSBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["PWSBar"].y
				end,
			},
            colors = {
                order = 400,
                type = "header",
                name = L["Colors"],
            },
			textcolor = {
				order = 410,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["PWSBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["PWSBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["PWSBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			color = {
				order = 420,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["PWSBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["PWSBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["PWSBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 500,
                type = "header",
                name = L["Appearance"],
            },
			texture_opt = {
				order = 510,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["PWSBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].texture = val
				    self.bars["PWSBar"]:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["PWSBar"].shown
				end,
			},
			border_visible_opt = {
				order = 520,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["PWSBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["PWSBar"].border = val
				    self.bars["PWSBar"]:UpdateBorder()
				end,
			},
			visible_opt = {
				order = 530,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
					return self.db.profile.bars["PWSBar"].shown
				end,
				set = function(info,val) 
			        self.db.profile.bars["PWSBar"].shown = val
			        self.bars["PWSBar"]:UpdateUI()
			    end,
			},
		},
	}

	-- Add included absorbs
	local orderid = 100
	for i, tracked in ipairs(PriestAbsorbsOrdered) do
		orderid = orderid + 1
		pwsBarOpts.args[tracked] = {
			name = SpellNames[tracked],
			desc = L["IncludeGeneric_Desc"],
			type = "toggle",
			order = orderid,
			set = function(info, val)
			    self.db.profile.bars["PWSBar"].included[tracked] = val
			end,
	        get = function(info)
				return self.db.profile.bars["PWSBar"].included[tracked]
			end,
		}
	end

	self:AddAdvancedPositioning(pwsBarOpts, "PWSBar")
	return pwsBarOpts
end

function BloodShieldTracker:GetIllumBarOptions()
	local illumBarOpts = {
		order = 5,
		type = "group",
		name = L["Illuminated Healing Bar"],
		desc = L["Illuminated Healing Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["IllumBar_Desc"],
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
				    self.db.profile.bars["IllumBar"].enabled = val
					self.bars["IllumBar"]:UpdateVisibility()
				end,
                get = function(info)
					return self.db.profile.bars["IllumBar"].enabled
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["IllumBar"].locked = val 
					self.bars["IllumBar"]:Lock(val)
				end,
                get = function(info)
					return self.db.profile.bars["IllumBar"].locked
				end,
			},
            dimensions = {
                order = 300,
                type = "header",
                name = L["Dimensions"],
            },
			bar_width = {
				order = 310,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 50,
				max = 300,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["IllumBar"].width = val 
					self.bars["IllumBar"].bar:SetWidth(val)
					self.bars["IllumBar"].bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["IllumBar"].width
				end,
			},
			bar_height = {
				order = 320,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 10,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["IllumBar"].height = val 
					self.bars["IllumBar"].bar:SetHeight(val)
					self.bars["IllumBar"].bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["IllumBar"].height
				end,					
			},
			bar_scaling = {
				order = 330,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
					return self.db.profile.bars["IllumBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["IllumBar"].scale = val
				    self.bars["IllumBar"].bar:SetScale(val)
				end
			},
            position = {
                order = 390,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 391,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["IllumBar"].x = val
					self.illumbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["IllumBar"].x, 
						self.db.profile.bars["IllumBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["IllumBar"].x
				end,
			},
			y = {
				order = 392,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["IllumBar"].y = val
					self.illumbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["IllumBar"].x, 
						self.db.profile.bars["IllumBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["IllumBar"].y
				end,
			},
            colors = {
                order = 400,
                type = "header",
                name = L["Colors"],
            },
			bar_textcolor = {
				order = 410,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["IllumBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["IllumBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["IllumBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_color = {
				order = 420,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["IllumBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["IllumBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["IllumBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 500,
                type = "header",
                name = L["Appearance"],
            },
			bar_texture_opt = {
				order = 510,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["IllumBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["IllumBar"].texture = val
				    self.bars["IllumBar"]:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["IllumBar"].shown
				end,
			},
			bar_border_visible_opt = {
				order = 520,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["IllumBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["IllumBar"].border = val
				    self.bars["IllumBar"]:UpdateBorder()
				end,
			},
			bar_visible_opt = {
				order = 530,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
					return self.db.profile.bars["IllumBar"].shown
				end,
				set = function(info,val) 
			        self.db.profile.bars["IllumBar"].shown = val
			        self.bars["IllumBar"]:UpdateUI()
			    end,
			},
		},
	}
	self:AddAdvancedPositioning(illumBarOpts, "IllumBar")
	return illumBarOpts
end

function BloodShieldTracker:GetAbsorbsBarOptions()
	local absorbsBarOpts = {
		order = 6,
		type = "group",
		name = L["Total Absorbs Bar"],
		desc = L["Total Absorbs Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["TotalAbsorbsBar_Desc"],
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
				    self.db.profile.bars["TotalAbsorbsBar"].enabled = val
					self.bars["TotalAbsorbsBar"]:UpdateVisibility()
				end,
                get = function(info) 
					return self.db.profile.bars["TotalAbsorbsBar"].enabled
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].locked = val 
					self.bars["TotalAbsorbsBar"]:Lock(val)
				end,
                get = function(info)
					return self.db.profile.bars["TotalAbsorbsBar"].locked
				end,
			},
            includedOptions = {
                order = 100,
                type = "header",
                name = L["Included Absorbs"],
            },
            dimensions = {
                order = 300,
                type = "header",
                name = L["Dimensions"],
            },
			bar_width = {
				order = 310,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 50,
				max = 300,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].width = val 
					self.bars["TotalAbsorbsBar"].bar:SetWidth(val)
					self.bars["TotalAbsorbsBar"].bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["TotalAbsorbsBar"].width
				end,
			},
			bar_height = {
				order = 320,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 10,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].height = val 
					self.bars["TotalAbsorbsBar"].bar:SetHeight(val)
					self.bars["TotalAbsorbsBar"].bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["TotalAbsorbsBar"].height
				end,					
			},
			bar_scaling = {
				order = 330,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
					return self.db.profile.bars["TotalAbsorbsBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].scale = val
				    self.bars["TotalAbsorbsBar"].bar:SetScale(val)
				end
			},
            position = {
                order = 390,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 391,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].x = val
					self.absorbsbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["TotalAbsorbsBar"].x, 
						self.db.profile.bars["TotalAbsorbsBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["TotalAbsorbsBar"].x
				end,
			},
			y = {
				order = 392,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].y = val
					self.absorbsbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["TotalAbsorbsBar"].x, 
						self.db.profile.bars["TotalAbsorbsBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["TotalAbsorbsBar"].y
				end,
			},
            colors = {
                order = 400,
                type = "header",
                name = L["Colors"],
            },
			bar_textcolor = {
				order = 410,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["TotalAbsorbsBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["TotalAbsorbsBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["TotalAbsorbsBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_color = {
				order = 420,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["TotalAbsorbsBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["TotalAbsorbsBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["TotalAbsorbsBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 500,
                type = "header",
                name = L["Appearance"],
            },
			bar_texture_opt = {
				order = 510,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["TotalAbsorbsBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].texture = val
				    self.bars["TotalAbsorbsBar"]:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["TotalAbsorbsBar"].shown
				end,
			},
			bar_border_visible_opt = {
				order = 520,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["TotalAbsorbsBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].border = val
				    self.bars["TotalAbsorbsBar"]:UpdateBorder()
				end,
			},
			bar_visible_opt = {
				order = 530,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
					return self.db.profile.bars["TotalAbsorbsBar"].shown
				end,
				set = function(info,val) 
			        self.db.profile.bars["TotalAbsorbsBar"].shown = val
			        self.bars["TotalAbsorbsBar"]:UpdateUI()
			    end,
			},
		},
	}

	-- Add included absorbs
	local orderid = 100
	for i, tracked in ipairs(AbsorbShieldsOrdered) do
		orderid = orderid + 1
		absorbsBarOpts.args[tracked] = {
			name = ItemNames[tracked] or SpellNames[tracked],
			desc = L["IncludeGeneric_Desc"],
			type = "toggle",
			order = orderid,
			set = function(info, val)
			    self.db.profile.bars["TotalAbsorbsBar"].included[tracked] = val
			end,
	        get = function(info)
				return self.db.profile.bars["TotalAbsorbsBar"].included[tracked]
			end,
		}
	end

	self:AddAdvancedPositioning(absorbsBarOpts, "TotalAbsorbsBar")
	return absorbsBarOpts
end

function BloodShieldTracker:GetPurgatoryBarOptions()
	local purgatoryBarOpts = {
		order = 6,
		type = "group",
		name = L["Purgatory Bar"],
		desc = L["Purgatory Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["PurgatoryBar_Desc"],
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
				    self.db.profile.bars["PurgatoryBar"].enabled = val
					self.bars["PurgatoryBar"]:UpdateVisibility()
				end,
                get = function(info)
					return self.db.profile.bars["PurgatoryBar"].enabled
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["PurgatoryBar"].locked = val 
					self.bars["PurgatoryBar"]:Lock(val)
				end,
                get = function(info)
					return self.db.profile.bars["PurgatoryBar"].locked
				end,
			},
            dimensions = {
                order = 300,
                type = "header",
                name = L["Dimensions"],
            },
			bar_width = {
				order = 310,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 50,
				max = 300,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["PurgatoryBar"].width = val 
					self.bars["PurgatoryBar"].bar:SetWidth(val)
					self.bars["PurgatoryBar"].bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["PurgatoryBar"].width
				end,
			},
			bar_height = {
				order = 320,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 10,
				max = 90,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["PurgatoryBar"].height = val 
					self.bars["PurgatoryBar"].bar:SetHeight(val)
					self.bars["PurgatoryBar"].bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["PurgatoryBar"].height
				end,					
			},
			bar_scaling = {
				order = 330,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
					return self.db.profile.bars["PurgatoryBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["PurgatoryBar"].scale = val
				    self.bars["PurgatoryBar"].bar:SetScale(val)
				end
			},
            position = {
                order = 390,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 391,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["PurgatoryBar"].x = val
					self.bars["PurgatoryBar"].bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["PurgatoryBar"].x, 
						self.db.profile.bars["PurgatoryBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["PurgatoryBar"].x
				end,
			},
			y = {
				order = 392,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["PurgatoryBar"].y = val
					self.bars["PurgatoryBar"].bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["PurgatoryBar"].x, 
						self.db.profile.bars["PurgatoryBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["PurgatoryBar"].y
				end,
			},
            colors = {
                order = 400,
                type = "header",
                name = L["Colors"],
            },
			bar_textcolor = {
				order = 410,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["PurgatoryBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["PurgatoryBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["PurgatoryBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_color = {
				order = 420,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["PurgatoryBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["PurgatoryBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["PurgatoryBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 500,
                type = "header",
                name = L["Appearance"],
            },
			bar_texture_opt = {
				order = 510,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["PurgatoryBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["PurgatoryBar"].texture = val
				    self.bars["PurgatoryBar"]:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["PurgatoryBar"].shown
				end,
			},
			bar_border_visible_opt = {
				order = 520,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["PurgatoryBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["PurgatoryBar"].border = val
				    self.bars["PurgatoryBar"]:UpdateBorder()
				end,
			},
			bar_visible_opt = {
				order = 530,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
					return self.db.profile.bars["PurgatoryBar"].shown
				end,
				set = function(info,val) 
			        self.db.profile.bars["PurgatoryBar"].shown = val
			        self.bars["PurgatoryBar"]:UpdateUI()
			    end,
			},
		},
	}
	self:AddAdvancedPositioning(purgatoryBarOpts, "PurgatoryBar")
	return purgatoryBarOpts
end

function BloodShieldTracker:GetAMSBarOptions()
	local amsBarOpts = {
		order = 2,
		type = "group",
		name = L["Anti-Magic Shell Bar"],
		desc = L["Anti-Magic Shell Bar"],
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["AMSBar_Desc"],
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
				    self.db.profile.bars["AMSBar"].enabled = val
					self.bars["AMSBar"]:UpdateVisibility()
				end,
                get = function(info)
					return self.db.profile.bars["AMSBar"].enabled
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["AMSBar"].locked = val 
					self.bars["AMSBar"]:Lock()
				end,
                get = function(info)
					return self.db.profile.bars["AMSBar"].locked
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
				    self.db.profile.bars["AMSBar"].show_time = val
				    if val then
				        self.bars["AMSBar"].bar.time:Show()
			        else
			            self.bars["AMSBar"].bar.time:Hide()
		            end
				end,
                get = function(info)
                    return self.db.profile.bars["AMSBar"].show_time
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
				    self.db.profile.bars["AMSBar"].time_pos = val
			        self.bars["AMSBar"].bar.time:SetPoint(val or "RIGHT")
			        self.bars["AMSBar"].bar.time:SetJustifyH(val or "RIGHT")
				end,
                get = function(info)
                    return self.db.profile.bars["AMSBar"].time_pos
                end,
                disabled = function()
                    return not self.db.profile.bars["AMSBar"].show_time
                end,
			},
            dimensions = {
                order = 300,
                type = "header",
                name = L["Dimensions"],
            },
			width = {
				order = 310,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 50,
				max = 300,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["AMSBar"].width = val 
					self.bars["AMSBar"].bar:SetWidth(val)
					self.bars["AMSBar"].bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["AMSBar"].width
				end,
			},
			height = {
				order = 320,
				name = L["Height"],
				desc = L["BarHeight_Desc"],
				type = "range",
				min = 10,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["AMSBar"].height = val 
					self.bars["AMSBar"].bar:SetHeight(val)
					self.bars["AMSBar"].bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["AMSBar"].height
				end,					
			},
			scale = {
				order = 330,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
					return self.db.profile.bars["AMSBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["AMSBar"].scale = val
				    self.bars["AMSBar"].bar:SetScale(val)
				end
			},
            position = {
                order = 400,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 410,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["AMSBar"].x = val
					self.bars["AMSBar"].bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["AMSBar"].x, 
						self.db.profile.bars["AMSBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["AMSBar"].x
				end,
			},
			y = {
				order = 420,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["AMSBar"].y = val
					self.bars["AMSBar"].bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["AMSBar"].x, 
						self.db.profile.bars["AMSBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["AMSBar"].y
				end,
			},
            colors = {
                order = 500,
                type = "header",
                name = L["Colors"],
            },
			textcolor = {
				order = 510,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["AMSBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["AMSBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["AMSBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			color = {
				order = 520,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["AMSBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["AMSBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["AMSBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bgcolor = {
				order = 530,
				name = L["Bar Background Color"],
				desc = L["BarBackgroundColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["AMSBar"].bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
				    self.bars["AMSBar"]:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["AMSBar"].bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
            appearance = {
                order = 600,
                type = "header",
                name = L["Appearance"],
            },
			texture_opt = {
				order = 610,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["AMSBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["AMSBar"].texture = val
				    self.bars["AMSBar"]:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["AMSBar"].shown
				end,
			},
			border_visible_opt = {
				order = 620,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["AMSBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["AMSBar"].border = val
				    self.bars["AMSBar"]:UpdateBorder()
				end,
			},
			visible_opt = {
				order = 630,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
					return self.db.profile.bars["AMSBar"].shown
				end,
				set = function(info,val) 
			        self.db.profile.bars["AMSBar"].shown = val
			        self.bars["AMSBar"]:UpdateUI()
			    end,
			},
		},
	}

	self:AddAdvancedPositioning(amsBarOpts, "AMSBar")
	return amsBarOpts
end

function BloodShieldTracker:GetHealthBarOptions()
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
				    self.db.profile.bars["HealthBar"].enabled = val
			        self:ToggleHealthBar()
				end,
                get = function(info)
                    return self.db.profile.bars["HealthBar"].enabled
                end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 20,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].locked = val 
					self.bars["HealthBar"]:Lock(val)
				end,
                get = function(info)
                    return self.db.profile.bars["HealthBar"].locked
                end,
			},
			hide_bar_ooc = {
				name = L["Hide out of combat"],
				desc = L["HideOutOfCombat_OptionDesc"],
				type = "toggle",
				order = 30,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].hide_ooc = val
					if not _G.InCombatLockdown() then
					    if val then
					        self.healthbar.bar:Hide()
				        elseif self:IsTrackerEnabled() then
				            self.healthbar.bar:Show()
			            end
			        end
				end,
                get = function(info)
                    return self.db.profile.bars["HealthBar"].hide_ooc
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
				    self.db.profile.bars["HealthBar"].low_percent = val
				end,
				get = function(info, val)
				    return self.db.profile.bars["HealthBar"].low_percent
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
				    self.db.profile.bars["HealthBar"].text_format = val
			        self:UpdateHealthBar(false)
				end,
                get = function(info)
                    return self.db.profile.bars["HealthBar"].text_format
                end,
			},
            dimensions = {
                order = 100,
                type = "header",
                name = L["Dimensions"],
            },
			bar_width = {
				order = 110,
				name = L["Width"],
				desc = L["BarWidth_Desc"],	
				type = "range",
				min = 10,
				max = 200,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].width = val 
					self.healthbar.bar:SetWidth(val)
					self.healthbar.bar.border:SetWidth(val+9)
				end,
				get = function(info, val)
				    return self.db.profile.bars["HealthBar"].width
				end,
			},
			bar_height = {
				order = 120,
				name = L["Height"],
				desc = L["BarHeight_Desc"],	
				type = "range",
				min = 8,
				max = 30,
				step = 1,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].height = val 
					self.healthbar.bar:SetHeight(val)
					self.healthbar.bar.border:SetHeight(val + 8)
				end,
				get = function(info, val)
				    return self.db.profile.bars["HealthBar"].height
				end,
			},
			bar_scaling = {
				order = 130,
				name = L["Scale"],
				desc = L["ScaleDesc"],
				type = "range",
				min = 0.1,
				max = 3,
				step = 0.1,
				get = function()
				    return self.db.profile.bars["HealthBar"].scale
				end,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].scale = val
				    self.healthbar.bar:SetScale(val)
				end
			},
            position = {
                order = 190,
                type = "header",
                name = L["Position"],
            },
			x = {
				order = 191,
				name = L["X Offset"],
				desc = L["XOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenWidth()/2),
				softMax = floor(_G.GetScreenWidth()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].x = val
					self.healthbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["HealthBar"].x, 
						self.db.profile.bars["HealthBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["HealthBar"].x
				end,
			},
			y = {
				order = 192,
				name = L["Y Offset"],
				desc = L["YOffset_Desc"],	
				type = "range",
				softMin = -floor(_G.GetScreenHeight()/2),
				softMax = floor(_G.GetScreenHeight()/2),
				bigStep = 1,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].y = val
					self.healthbar.bar:SetPoint(
						"CENTER", _G.UIParent, "CENTER", 
						self.db.profile.bars["HealthBar"].x, 
						self.db.profile.bars["HealthBar"].y)
				end,
				get = function(info, val)
				    return self.db.profile.bars["HealthBar"].y
				end,
			},
            colors = {
                order = 200,
                type = "header",
                name = L["Colors for Normal Health"],
            },
			bar_textcolor = {
				order = 210,
				name = L["Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["HealthBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["HealthBar"].textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_color = {
				order = 220,
				name = L["Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["HealthBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["HealthBar"].color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_bgcolor = {
				order = 230,
				name = L["Bar Background Color"],
				desc = L["BarBackgroundColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["HealthBar"].bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["HealthBar"].bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},

            colorsLow = {
                order = 300,
                type = "header",
                name = L["Colors for Low Health"],
            },
			bar_low_textcolor = {
				order = 310,
				name = L["Low Health Text Color"],
				desc = L["BarTextColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["HealthBar"].alt_textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["HealthBar"].alt_textcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_low_color = {
				order = 320,
				name = L["Low Health Bar Color"],
				desc = L["BarColor_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["HealthBar"].alt_color
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["HealthBar"].alt_color
				    return c.r, c.g, c.b, c.a
				end,					
			},
			bar_low_bgcolor = {
				order = 330,
				name = L["Low Health Bar Background Color"],
				desc = L["BarBackgroundColor_LowHealth_OptionDesc"],
				type = "color",
				hasAlpha = true,
				set = function(info, r, g, b, a)
				    local c = self.db.profile.bars["HealthBar"].alt_bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.healthbar:UpdateGraphics()
				end,
				get = function(info)
			        local c = self.db.profile.bars["HealthBar"].alt_bgcolor
				    return c.r, c.g, c.b, c.a
				end,					
			},

            appearance = {
                order = 400,
                type = "header",
                name = L["Appearance"],
            },
			bar_texture_opt = {
				order = 410,
				name = L["Texture"],
				desc = L["BarTexture_OptionDesc"],
				type = "select",
				values = LSM:HashTable("statusbar"),
				dialogControl = 'LSM30_Statusbar',
				get = function()
				    return self.db.profile.bars["HealthBar"].texture
				end,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].texture = val
				    self.healthbar:UpdateTexture()
				end,
				disabled = function()
				    return not self.db.profile.bars["HealthBar"].shown
				end,
			},
			bar_border_visible_opt = {
				order = 420,
				name = L["ShowBorder"],
				desc = L["ShowBorderDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["HealthBar"].border
				end,
				set = function(info, val)
				    self.db.profile.bars["HealthBar"].border = val
				    self.healthbar:UpdateBorder()
				end,
			},
			bar_visible_opt = {
				order = 430,
				name = L["ShowBar"],
				desc = L["ShowBarDesc"],
				type = "toggle",
				get = function()
				    return self.db.profile.bars["HealthBar"].shown
				end,
				set = function(info,val)
				    self.db.profile.bars["HealthBar"].shown = val
				    self.healthbar:UpdateUI()
				end,
			},

		}
	}
	self:AddAdvancedPositioning(healthBarOpts, "HealthBar")
	return healthBarOpts
end

function BloodShieldTracker:GetSkinningOptions()
	local skinningOpts = {
	    order = 10,
		name = L["Skinning"],
		type = "group",
		args = {
		    description = {
		        order = 1,
		        type = "description",
		        name = L["Skinning_Desc"],
		    },
		    elvuiOptions = {
		        order = 10,
		        type = "header",
		        name = L["ElvUI"],
		    },
            elvui_enabled = {
                name = L["Enabled"],
				order = 20,
                desc = L["ElvUIEnabled_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.elvui.enabled = val
                end,
                get = function(info)
                    return self.db.profile.skinning.elvui.enabled
                end,
            },
            elvui_borders = {
                name = L["Borders"],
				order = 30,
                desc = L["ElvUIBorders_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.elvui.borders = val
                end,
                get = function(info)
                    return self.db.profile.skinning.elvui.borders
                end,
            },
            elvui_texture = {
                name = L["Texture"],
				order = 40,
                desc = L["ElvUITexture_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.elvui.texture = val
                end,
                get = function(info)
                    return self.db.profile.skinning.elvui.texture
                end,
            },
            elvui_font = {
                name = L["Font"],
				order = 50,
                desc = L["ElvUIFont_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.elvui.font = val
                end,
                get = function(info)
                    return self.db.profile.skinning.elvui.font
                end,
            },
            elvui_font_flags = {
                name = L["Font Flags"],
				order = 60,
                desc = L["ElvUIFontFlags_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.elvui.font_flags = val
                end,
                get = function(info)
                    return self.db.profile.skinning.elvui.font_flags
                end,
            },

		    tukuiOptions = {
		        order = 100,
		        type = "header",
		        name = L["Tukui"],
		    },
            tukui_enabled = {
                name = L["Enabled"],
				order = 110,
                desc = L["TukuiEnabled_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.tukui.enabled = val
                end,
                get = function(info)
                    return self.db.profile.skinning.tukui.enabled
                end,
            },
            tukui_borders = {
                name = L["Borders"],
				order = 120,
                desc = L["TukuiBorders_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.tukui.borders = val
                end,
                get = function(info)
                    return self.db.profile.skinning.tukui.borders
                end,
            },
            tukui_texture = {
                name = L["Texture"],
				order = 130,
                desc = L["TukuiTexture_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.tukui.texture = val
                end,
                get = function(info)
                    return self.db.profile.skinning.tukui.texture
                end,
            },
            tukui_font = {
                name = L["Font"],
				order = 140,
                desc = L["TukuiFont_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.tukui.font = val
                end,
                get = function(info)
                    return self.db.profile.skinning.tukui.font
                end,
            },
            tukui_font_flags = {
                name = L["Font Flags"],
				order = 150,
                desc = L["TukuiFontFlags_OptionDesc"],
                type = "toggle",
                set = function(info, val)
                    self.db.profile.skinning.tukui.font_flags = val
                end,
                get = function(info)
                    return self.db.profile.skinning.tukui.font_flags
                end,
            },
        }
    }
	return skinningOpts
end

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

    multiline:SetText(DEBUG_BUFFER)
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
	            DEBUG_OUTPUT = true
	            self:Print("Logging on.")
	        elseif cmds[2] and cmds[2] == "off" then
	            DEBUG_OUTPUT = false
	            self:Print("Logging off.")
	        elseif cmds[2] and cmds[2] == "show" then
	            self:ShowDebugOutput()
			else
				self:Print("Logging is "..(DEBUG_OUTPUT and "on." or "off."))
			end
        elseif cmds[1] and cmds[1] == "useAura" then
			if cmds[2] and cmds[2] == "false" then
				self.db.profile.useAuraForShield = false
				self:Print("Not using the aura.")
			elseif cmds[2] and cmds[2] == "true" then
				self.db.profile.useAuraForShield = true
				self:Print("Using the aura.")
			else
				self:Print("useAura = " .. tostring(self.db.profile.useAuraForShield))
			end
        end
        --_G.LibStub("AceConfigCmd-3.0").HandleCommand(BloodShieldTracker, "bst", "BloodShieldTracker", input)
    end
end

function BloodShieldTracker:OnInitialize()
    -- Load the settings
    self.db = _G.LibStub("AceDB-3.0"):New("BloodShieldTrackerDB", defaults, "Default")

	-- Migrate the settings
	self:MigrateSettings()

	DEBUG_OUTPUT = self.db.profile.debug

	-- Set the number format
	self:SetNumberFormat(self.db.profile.numberFormat)

    -- Set the precision
	self:SetNumberPrecision()

	-- Create the bars
	self.shieldbar = Bar:Create("ShieldBar", "Shield Bar", true)
	self:UpdateShieldBarMode()
    self:UpdateShieldBarText(0, 0, 0)
    self.estimatebar = Bar:Create("EstimateBar", "Estimate Bar", false)
	self.pwsbar = Bar:Create("PWSBar", "PW:S Bar", false)
	self.illumbar = Bar:Create("IllumBar", "Illuminated Healing Bar", false)
	self.healthbar = Bar:Create("HealthBar", "Health Bar", false)
	self.absorbsbar = Bar:Create("TotalAbsorbsBar", "Total Absorbs Bar", false)
	self.purgatorybar = Bar:Create("PurgatoryBar", "Purgatory Bar", false)
	self.bloodchargebar = Bar:Create("BloodChargeBar", "Blood Charge Bar", true)
	self.boneshieldbar = Bar:Create("BoneShieldBar", "Bone Shield Bar", true)
	self.amsbar = Bar:Create("AMSBar", "Anti-Magic Shell Bar", true)
	self:UpdatePositions()

	-- Register for profile callbacks
	self.db.RegisterCallback(self, "OnProfileChanged", "Reset")
	self.db.RegisterCallback(self, "OnProfileCopied", "Reset")
	self.db.RegisterCallback(self, "OnProfileReset", "Reset")

    -- Set the LDB options
    DataFeed.display = self.db.profile.ldb_data_feed
    if DataFeed.display ~= "None" then
        LDBDataFeed = true
    end
    SetBrokerLabel()

	icon:Register("BloodShieldTrackerLDB", Broker.obj, self.db.profile.minimap)
	LSM.RegisterCallback(BloodShieldTracker, "LibSharedMedia_Registered")

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

function BloodShieldTracker:GetFontFlags()
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

function BloodShieldTracker:GetFontSettings()
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
	    local displayName = _G.GetAddOnMetadata(BST.ADDON_NAME, "Title")
		local options = self:GetOptions()
	    _G.LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(displayName, options)

	    self.optionsFrame = {}
	    local ACD = _G.LibStub("AceConfigDialog-3.0")
		self.optionsFrame.Main = ACD:AddToBlizOptions(
		    displayName, displayName, nil, "core")
		self.optionsFrame.ShieldBar = ACD:AddToBlizOptions(
		    displayName, L["Blood Shield Bar"], displayName, "shieldBarOpts")
		self.optionsFrame.EstHealBar = ACD:AddToBlizOptions(
		    displayName, L["Estimated Healing Bar"], displayName, "estimateBarOpts")
		self.optionsFrame.BloodChargeBar = ACD:AddToBlizOptions(
		    displayName, L["Blood Charge Bar"], displayName, "bloodChargeOpts")
		self.optionsFrame.BoneShieldBar = ACD:AddToBlizOptions(
		    displayName, L["Bone Shield Bar"], displayName, "boneShieldOpts")
		self.optionsFrame.PriestBar = ACD:AddToBlizOptions(
		    displayName, L["PW:S Bar"], displayName, "pwsBarOpts")
		self.optionsFrame.IllumBar = ACD:AddToBlizOptions(
		    displayName, L["Illuminated Healing Bar"], displayName, "illumBarOpts")
		self.optionsFrame.AbsorbsBar = ACD:AddToBlizOptions(
		    displayName, L["Total Absorbs Bar"], displayName, "absorbsBarOpts")
		self.optionsFrame.AMSBar = ACD:AddToBlizOptions(
		    displayName, L["Anti-Magic Shell Bar"], displayName, "amsBarOpts")
		self.optionsFrame.PurgatoryBar = ACD:AddToBlizOptions(
		    displayName, L["Purgatory Bar"], displayName, "purgatoryBarOpts")
		self.optionsFrame.HealthBar = ACD:AddToBlizOptions(
		    displayName, L["Health Bar"], displayName, "healthBarOpts")
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
	self:UpdateMastery()
	self:UpdateMinHeal("UNIT_MAXHEALTH", "player")
	self:CheckTalents()
	self:RegisterEvent("PLAYER_TALENT_UPDATE", "CheckTalents")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","CheckTalents")
	self:RegisterEvent("GLYPH_ADDED", "CheckGlyphs")
	self:RegisterEvent("GLYPH_REMOVED", "CheckGlyphs")
	self:RegisterEvent("GLYPH_UPDATED", "CheckGlyphs")
end

function BloodShieldTracker:Load()
	if self.loaded then return end

	self.loaded = true

	if self.db.profile.verbose then
		self:Print("Loading.")
	end
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("COMBAT_RATING_UPDATE","UpdateMastery")
	self:RegisterEvent("MASTERY_UPDATE","UpdateMastery")
	self:RegisterEvent("UNIT_MAXHEALTH","UpdateMinHeal")
	self:RegisterEvent("PLAYER_DEAD")
	self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckAuras")
    self:RegisterEvent("PLAYER_ALIVE", "CheckAuras")
    self:RegisterEvent("UNIT_SPELLCAST_SENT")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:ToggleHealthBar()
    self.shieldbar:UpdateUI()
	self.estimatebar:UpdateUI()
	self.estimatebar:UpdateVisibility()
end

function BloodShieldTracker:Unload()
	if not self.loaded then return end

	self.loaded = false
	if self.db.profile.verbose then
		self:Print("Unloading.")
	end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:UnregisterEvent("COMBAT_RATING_UPDATE")
	self:UnregisterEvent("MASTERY_UPDATE")
	self:UnregisterEvent("UNIT_MAXHEALTH")
	self:UnregisterEvent("PLAYER_DEAD")
	self:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("PLAYER_ALIVE")
    self:UnregisterEvent("UNIT_SPELLCAST_SENT")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("UNIT_HEALTH")
    self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	
	for k, v in pairs(self.bars) do
		if v then
			v.bar:Hide()
		end
	end
end

function BloodShieldTracker:OnDisable()
end

function BloodShieldTracker:UpdateMastery()
    masteryRating = _G.GetMastery()
	shieldPercent = masteryRating*shieldPerMasteryPoint/100
end

function BloodShieldTracker:CheckClass()
    local class, className = _G.UnitClass("player")
    if className then
        if (className == 'DEATH KNIGHT' or className == 'DEATHKNIGHT') then
            isDK = true
        else
            isDK = false
        end
    end
end

function BloodShieldTracker:CheckTalents(event)
	IsBloodTank = false
	hasBloodShield = false
	HasVampBlood = false

	self:CheckTalents5()
	self:UpdateTierBonus()

	self.bars["EstimateBar"]:UpdateVisibility()
	self.bars["BoneShieldBar"]:UpdateVisibility()

	if self.db.profile.debug then
		local trackerOutputFmt = "Check Talents [DK=%s,BT=%s,MA=%s,VB=%s,Event=%s]"
		self:Print(trackerOutputFmt:format(tostring(isDK),
			tostring(IsBloodTank),tostring(hasBloodShield),tostring(HasVampBlood),
			tostring(event or "")))
	end
end

-- New method to check talents for MoP
function BloodShieldTracker:CheckTalents5()
	if isDK == nil then
		self:CheckClass()
	end

	if isDK then
		-- Check spec: Blood, Frost, or Unholy spec?
		local activeSpecNum = _G.GetSpecialization()
		if activeSpecNum and activeSpecNum > 0 then
			local id, name, desc, texture = _G.GetSpecializationInfo(activeSpecNum)
	    	if texture == "Interface\\Icons\\Spell_Deathknight_BloodPresence" then
	    		IsBloodTank = true
				-- Check for Mastery so we know if BS is active
		        if _G.IsSpellKnown(SpellIds["Mastery: Blood Shield"]) then
		            hasBloodShield = true
		        end
				-- Check for VB
				if _G.IsSpellKnown(SpellIds["Vampiric Blood"]) then
					HasVampBlood = true
				end
			else
				IsBloodTank = false
			end
		end
       	self:CheckGlyphs()
	end

	if self:IsTrackerEnabled() then
	    self:Load()
    else
        self:Unload()
    end
end

function BloodShieldTracker:IsTrackerEnabled()
    if IsBloodTank or (isDK and not self.db.profile.enable_only_for_blood) then
        return true
    else
        return false
    end
end

function BloodShieldTracker:CheckGlyphs()
    hasVBGlyphed = false
    HasSuccorGlyphed = false
	--if not HasVampBlood then return end -- Dont bother with glyph check if he doesnt have the talent
    for id = 1, _G.GetNumGlyphSockets() do
        local enabled, glyphType, glyphTooltipIndex, 
            glyphSpell, iconFilename = _G.GetGlyphSocketInfo(id, nil)
        if enabled then
            if glyphSpell == GlyphIds["Vampiric Blood"] then
                hasVBGlyphed = true
            elseif glyphSpell == GlyphIds["Dark Succor"] then
                HasSuccorGlyphed = true
            end
        end
    end

	if self.db.profile.debug then
		local trackerOutputFmt = "Check Glyphs [VB=%s,DSuccor=%s]"
		self:Print(trackerOutputFmt:format(
			tostring(hasVBGlyphed), tostring(HasSuccorGlyphed)))
	end
end

local TierSlotIds = {
	["Head"] = _G.GetInventorySlotInfo("HeadSlot"),
	["Shoulder"] = _G.GetInventorySlotInfo("ShoulderSlot"),
	["Chest"] = _G.GetInventorySlotInfo("ChestSlot"),
	["Legs"] = _G.GetInventorySlotInfo("LegsSlot"),
	["Hands"] = _G.GetInventorySlotInfo("HandsSlot"),
}

local Tier14Ids = {
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
}

local TierSlots = {}
for k, v in pairs(TierSlotIds) do
	TierSlots[v] = true
end

function BloodShieldTracker:CheckGear()
	GearChangeTimer = nil
	local count = 0

	for slot, slotid in pairs(TierSlotIds) do
		local id = _G.GetInventoryItemID("player", slotid)
		if Tier14Ids[slot][id] then
			count = count + 1
		end
	end

	if count ~= Tier14Count then
		Tier14Count = count
		if self.db.profile.verbose and idle then
			local fmt = "T14 Detected: %d/5"
			self:Print(fmt:format(Tier14Count))
		end
		self:UpdateTierBonus()
	end
end

function BloodShieldTracker:UpdateTierBonus()
	local currentBonus = Tier14Bonus
	Tier14Bonus = 1 + (Tier14Count >= 4 and T14BonusAmt or 0)
	if currentBonus ~= Tier14Bonus then
		self:UpdateMinHeal("CheckGear", "player")
		if self.db.profile.verbose and idle then
			local fmt = "T14 Bonus: %d%%"
			self:Print(fmt:format(Tier14Bonus*100-100))
		end
	end
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

function BloodShieldTracker:UNIT_HEALTH(event, unit)
    if unit and unit == "player" then
        local oldHealth = currentHealth
        currentHealth = UnitHealth("player")
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

function BloodShieldTracker:UpdateMinHeal(event, unit)
	if unit == "player" then
	    local oldHealth = maxHealth
	    maxHealth = UnitHealthMax("player")
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
	    actualDsMinHeal = dsMinHealPercent

        -- Check for Dark Succor
        if DarkSuccorBuff == true and 
			(CurrentPresence == "Unholy" or CurrentPresence == "Frost") then
   	        actualDsMinHeal = dsMinHealPercentSuccor
        end

		local baseValue = maxHealth * actualDsMinHeal * Tier14Bonus *
			(1 + scentBloodStacks * scentBloodStackBuff)
		dsHealMin = round(baseValue *
		    self:GetEffectiveHealingBuffModifiers() * 
		    self:GetEffectiveHealingDebuffModifiers())
		bsMinimum = round(baseValue * shieldPercent)
		if idle then
		    self:UpdateEstimateBarTextWithMin()
		end
	end
end

local function UpdateTime(self, elapsed)
    currentTime = currentTime + elapsed
end

function BloodShieldTracker:PLAYER_REGEN_DISABLED()
	-- Once combat starts, update the damage bar.
	idle = false
	if self:IsTrackerEnabled() then
    	updateTimer = self:ScheduleRepeatingTimer("UpdateBars", 0.5)
        if self.estimatebar.db.enabled then
	        self.estimatebar.bar:Show()
	        self.estimatebar.bar:SetScript("OnUpdate", UpdateTime)
        end
        if self.healthbar.db.enabled then
            self.healthbar.bar:Show()
        end
    end
    -- Reset the per fight stats
    LastFightStats:Reset()
    LastFightStats:StartCombat()
    
    if DEBUG_OUTPUT == true then
        DEBUG_BUFFER = ""
    end
end

function BloodShieldTracker:PLAYER_REGEN_ENABLED()
	idle = true
	self:UpdateEstimateBarTextWithMin()
    self.estimatebar.altcolor = false
    self.estimatebar:UpdateGraphics()
    self.estimatebar.bar:SetMinMaxValues(0, 1)
    self.estimatebar.bar:SetValue(1)
    
    if self.estimatebar.db.hide_ooc then
        self.estimatebar.bar:Hide()
    end

    if self.healthbar.db.hide_ooc then
        self.healthbar.bar:Hide()
    end

    self.estimatebar.bar:SetScript("OnUpdate", nil)

    LastFightStats:EndCombat()
end

function BloodShieldTracker:PLAYER_DEAD()
    -- Just in case, hide the BS bar if the player dies
    self.shieldbar.expires = 0
    self:CheckAuras()
    self.shieldbar.bar:Hide()
    -- Hide the estimate bar if configured to do so for OOC
    if self.estimatebar.db.hide_ooc then
        if self.estimatebar.bar:IsVisible() then
            self.estimatebar.bar:Hide()
        end
    end
    -- Hide the health bar if configured to do so for OOC
    if self.healthbar.db.hide_ooc then
        if self.healthbar.bar:IsVisible() then
            self.healthbar.bar:Hide()
        end
    end
	if DataFeed.vengeance > 0 then
		DataFeed.vengeance = 0
		UpdateLDBData()
	end
end

function BloodShieldTracker:UpdateBars(timestamp)
    -- If we're out of combat and no Blood Shields are present, stop the timer
    if idle and self.shieldbar.expires <= 0 then
    	if updateTimer then
            self:CancelTimer(updateTimer)
            updateTimer = nil
        end
    end

    if self.shieldbar.db.enabled then
        local expires = self.shieldbar.expires
        local timeleft = 0
        local timeLeftFmt = "%d"
        local current = GetTime()
        if expires > 0 then
            timeleft = expires - current
            if timeleft < 0 or timeleft > BS_DURATION then
                timeleft = 0
            end
        
            timeleft = floor(timeleft)
        end

        if self.shieldbar.db.progress == "Time" then
            self.shieldbar.bar:SetValue(timeleft)
        end

        self.shieldbar.bar.time:SetText(timeLeftFmt:format(timeleft))
    end

    self:UpdateEstimateBar(timestamp)
end

function BloodShieldTracker:UpdateEstimateBar(timestamp)
    if self.estimatebar.db.enabled and not idle then
        local recentDamage = self:GetRecentDamageTaken(timestamp)

        local predictedValue, minimumValue = 0, 0
        local baseValue = recentDamage * dsHealModifier * Tier14Bonus * 
			(1 + scentBloodStacks * scentBloodStackBuff)

        if self.estimatebar.db.bar_mode == "BS" then
            predictedValue = round(baseValue * shieldPercent)
            minimumValue = bsMinimum
        else
            predictedValue = round(baseValue *
                self:GetEffectiveHealingBuffModifiers() * 
                self:GetEffectiveHealingDebuffModifiers())
            minimumValue = dsHealMin
        end

        local estimate = minimumValue
    	if predictedValue > minimumValue then
    	    estimate = predictedValue
    	end

        self:UpdateEstimateBarText(estimate)
        self.estimatebar.bar:SetMinMaxValues(0, minimumValue)

		local altMin = self.estimatebar.db.alternateMinimum or 0
		if altMin > 0 and predictedValue >= altMin then
            self.estimatebar.altcolor = true
            self.estimatebar.bar:SetValue(predictedValue)
		elseif altMin == 0 and predictedValue > minimumValue then
            self.estimatebar.altcolor = true
            self.estimatebar.bar:SetValue(minimumValue)
        else
            self.estimatebar.altcolor = false
            self.estimatebar.bar:SetValue(predictedValue)
		end
        self.estimatebar:UpdateGraphics()

        DataFeed.estimateBar = estimate
        if LDBDataFeed then
            UpdateLDBData()
        end
    end
end

function BloodShieldTracker:UpdateEstimateBarText(estimate)
	local text = ""
	local sep = ""
    if self.estimatebar.db.show_text then
		sep = ": "
        if self.estimatebar.db.bar_mode == "BS" then
            text = L["EstimateBarBSText"]
        else
            text = L["HealBarText"]
        end
    end

	local val
	if self.estimatebar.db.usePercent then
		val = estBarPercFmt:format(
			baseFmt:format(estimate / (maxHealth or 1) * 100))
	else
		val = FormatNumber(estimate)
	end

    self.estimatebar.bar.value:SetText(
        estimateBarFormat:format(
            text, sep, val))
end

function BloodShieldTracker:UpdateEstimateBarTextWithMin()
	local value = 0
    if self.estimatebar.db.bar_mode == "BS" then
        value = bsMinimum
    else
        value = dsHealMin
    end
	self:UpdateEstimateBarText(value)
end

function BloodShieldTracker:UpdateShieldBarMode()
    if self.shieldbar.db.progress == "Time" then
        self.shieldbar.bar:SetMinMaxValues(0, BS_DURATION)
        self.shieldbar.bar:SetValue(BS_DURATION)
    elseif self.shieldbar.db.progress == "None" then
        self.shieldbar.bar:SetMinMaxValues(0, 1)
        self.shieldbar.bar:SetValue(1)        
    end
end

function BloodShieldTracker:UpdateBloodChargeBarMode()
	local bar = self.bloodchargebar
    if bar.db.progress == "Time" then
        bar.bar:SetMinMaxValues(0, BS_DURATION)
        bar.bar:SetValue(BS_DURATION)
    elseif bar.db.progress == "Charges" then
        bar.bar:SetMinMaxValues(0, MAX_BLOOD_CHARGES)
        bar.bar:SetValue(0)
    elseif bar.db.progress == "None" then
        bar.bar:SetMinMaxValues(0, 1)
        bar.bar:SetValue(1)        
    end
end

function BloodShieldTracker:UpdateBoneShieldBarMode()
	local bar = self.boneshieldbar
    if bar.db.progress == "Time" then
        bar.bar:SetMinMaxValues(0, 1)
        bar.bar:SetValue(1)
    elseif bar.db.progress == "Charges" then
        bar.bar:SetMinMaxValues(0, 6)
        bar.bar:SetValue(0)
    elseif bar.db.progress == "None" then
        bar.bar:SetMinMaxValues(0, 1)
        bar.bar:SetValue(1)        
    end
end

function BloodShieldTracker:ShowShieldBar()
    if self.shieldbar.db.enabled then
        if self.shieldbar.db.progress == "Time" then
            self.shieldbar:SetValue(BS_DURATION)
        elseif self.shieldbar.db.progress == "Current" then
            self.shieldbar.bar:SetMinMaxValues(0, self.shieldbar.shield_max)
            self.shieldbar.bar:SetValue(self.shieldbar.shield_curr)
        end

        self:UpdateShieldBarText(
            self.shieldbar.shield_curr, self.shieldbar.shield_max, 100)
        self.shieldbar.bar:Show()
    end
end

function BloodShieldTracker:UpdateShieldBar()
    if not IsBloodTank then return end

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

function BloodShieldTracker:ToggleHealthBar()
    if self.db.profile.bars["HealthBar"].enabled then
        self:RegisterEvent("UNIT_HEALTH")
		self:UNIT_HEALTH("ToggleHealthBar", "player")
		self:UpdateHealthBar(true)
    else
        self:UnregisterEvent("UNIT_HEALTH")
    end
	self.bars["HealthBar"]:UpdateVisibility()
end

local percentIntFmt = "%d%%"
function BloodShieldTracker:UpdateHealthBar(maxChanged)
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
            text = shieldBarFormatFull:format(
                FormatNumber(currentHealth), 
                FormatNumber(maxHealth), 
                percentHealth * 100)
        elseif self.healthbar.db.text_format == "CurrMax" then
            text = shieldBarFormatNoPer:format(
                FormatNumber(currentHealth), 
                FormatNumber(maxHealth))
        elseif self.healthbar.db.text_format == "CurrPerc" then
            text = shieldBarFormatCurrPerc:format(
                FormatNumber(currentHealth), 
                percentHealth * 100)
        else
            text = FormatNumber(currentHealth)
        end

        self.healthbar.bar.value:SetText(text)
    end
end

function BloodShieldTracker:UpdateShieldBarText(current, maximum, percent)
    local newText = ""
    local percentFormat = "%d%%"
    
    local currentTxt = FormatNumber(current)
    local maximumTxt = FormatNumber(maximum)
    
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

function BloodShieldTracker:GetRecentDamageTaken(timestamp)
    local latency = 0
    local damage = 0
    local current = timestamp
    
    if not current or current <= 0 then
        current = currentTime
    end

    if self.estimatebar.db.latencyMethod == "DS" then
        if DS_Latency and DS_Latency > 0 and DS_Latency <= 2 then
            latency = DS_Latency
        end
    elseif self.estimatebar.db.latencyMethod == "Fixed" then
        latency = self.estimatebar.db.latencyFixed / 1000
    end

    if latency > 0 then
        current = current - latency
    end

    local diff
    
    for i, v in ipairs(damageTaken) do
        if v and v[1] and v[2] then
            diff = current - v[1]
            -- If the damage occured in the window, 
            -- adjusted for latency above, then add it.
            if diff <= lastSeconds and diff >= 0 then
                damage = damage + v[2]
            end
        end
    end
    
    return damage
end

function BloodShieldTracker:AddDamageTaken(timestamp, damage)
    -- Add the new damage taken data
    tinsert(damageTaken, {timestamp,damage})

    wipe(removeList)

    -- Remove any data older than lastSeconds
    for i, v in ipairs(damageTaken) do
        if v and v[1] then
            if timestamp - v[1] > lastSeconds + 3 then
                tinsert(removeList, i)
            end
        end
    end
    
    for i, v in ipairs(removeList) do
        if v then
            tremove(damageTaken, v)
        end
    end
    
    self:UpdateBars(timestamp)
end

function BloodShieldTracker:GetSpellSchool(school)
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

function BloodShieldTracker:UNIT_SPELLCAST_SENT(event, unit, spellName)
    if unit == "player" and spellName == SpellNames["Death Strike"] then
        DS_SentTime = GetTime()
    end
end

function BloodShieldTracker:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName)
    if unit == "player" and spellName == SpellNames["Death Strike"] then
        local succeededTime = GetTime()
        if DS_SentTime then
            local diff = succeededTime - DS_SentTime
            if diff > 0 then
                DS_Latency = diff
                if self.db.profile.debug then
                    self:Print("DS Latency: "..DS_Latency)
                end
                -- If the latency appears overly large then cap it at 2 seconds.
                if DS_Latency > 2 then 
                    DS_Latency = 2
                end
                DS_SentTime = nil
            end
        end
    end
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

    currentTime = timestamp

    if eventtype:find("_DAMAGE") and destName == self.playerName then
        if eventtype:find("SWING_") and param9 then
            local damage, absorb = param9, param14 or 0

            if self.db.profile.debug then
                local swingDmgFmt = "Swing Damage for %d [%d absorbed]"
                self:Print(swingDmgFmt:format(damage, absorb))
            end

            self:AddDamageTaken(timestamp, damage)
        elseif eventtype:find("SPELL_") or eventtype:find("RANGE_") then
            local type
            if eventtype:find("SPELL_") then type = "Spell" end
            if eventtype:find("RANGE_") then type = "Range" end        
            local damage, absorb, school = param12 or 0, param17 or 0, param14 or 0
            local spellName = param10 or "n/a"
            local schoolName = self:GetSpellSchool(school) or "N/A"

            local countDamage = true
            -- Do not count damage from no source or maybe this is just
            -- particular items like Shannox's Jagged Tear?
            if srcName == nil then
                countDamage = false
                if self.db.profile.debug then
                    self:Print("Ignoring no source damage [" .. spellName .. 
                        "] of "..(damage or 0))
                end
            end

            -- Do not count Spirit Link damage since it doesn't affect DS.
            if spellName == SpellIds["Spirit Link"] and 
				srcName == SpellNames["Spirit Link Totem"] then
                countDamage = false
                if self.db.profile.debug then
                    self:Print("Ignoring Spirit Link damage of "..(damage or 0))
                end
            end

            if countDamage == true then
                self:AddDamageTaken(timestamp, damage)
            end

            if self.db.profile.debug then
                local spellDmgFmt = "%s Damage (%s-%s,%d) for %d [%d absorbed]"
                self:Print(spellDmgFmt:format(
                    type, spellName, schoolName, school, damage, absorb))
            end
        end
    end    

    if eventtype:find("_MISSED") and destName == self.playerName then
        if eventtype == "SWING_MISSED" then
            if param9 and param9 == "ABSORB" then
    			local damage = 0
   			    damage = param11 or 0

                if self.db.profile.debug then
                    local absorbFmt = "Absorbed swing for %d"
                    self:Print(absorbFmt:format(damage))
                end
            end
        elseif eventtype:find("SPELL_") then
            if param12 and param12 == 'ABSORB' then
                local damage = 0
                damage = param14 or 0

                local spellName, school = param10 or "n/a", param11 or 0
                local schoolName = self:GetSpellSchool(school) or "N/A"

                if self.db.profile.debug then
                    local absorbFmt = "Absorbed spell (%s-%s,%d) for %d"
                    self:Print(absorbFmt:format(spellName, schoolName, school, damage))
                end
            end
        end
    end

	if eventtype == "SPELL_CAST_SUCCESS" and srcName == self.playerName and 
	    param9 == SpellIds["Death Strike"] then

        if self.db.profile.debug then
            local dsHealFormat = "Estimated damage of %d will be a heal for %d"
            local recentDmg = self:GetRecentDamageTaken(timestamp)
            local predictedHeal = 0
            if healingDebuffMultiplier ~= 1 then 
                predictedHeal = round(
                    recentDmg * dsHealModifier * Tier14Bonus *
					(1 + scentBloodStacks * scentBloodStackBuff) *
                    self:GetEffectiveHealingBuffModifiers() * 
                    self:GetEffectiveHealingDebuffModifiers())
            end
    		self:Print(dsHealFormat:format(recentDmg, predictedHeal))
        end
	end
    if eventtype == "SPELL_HEAL" and destName == self.playerName 
        and param9 == SpellIds["Death Strike Heal"] then
        
        local totalHeal = param12 or 0
        local overheal = param13 or 0
        local actualHeal = param12-param13

		-- The SoB stacks are lost once the aura processing occurs
		-- so save the value here to use later.
		dsScentBloodStacks = scentBloodStacks

        -- Update the LDB data feed
        DataFeed.lastDS = totalHeal
        if LDBDataFeed then
            UpdateLDBData()
        end

        -- Apparently the BS value server-side is calculated from the last
        -- five seconds of data since the DS heal is affected by modifiers
        -- and debuffs.  Because we cannot reliably calculate the server-
        -- side last five seconds of damage, we will take the heal and work
        -- backwards.  The forumula below attempts to factor in various
        -- healing buffs.
        local shieldValue, predictedHeal

        local isMinimum = false
        local recentDmg = self:GetRecentDamageTaken(timestamp)
        local minimumHeal = dsHealMin
        
        if healingDebuffMultiplier == 1 then
            shieldValue = bsMinimum
            predictedHeal = 0
            isMinimum = true
        else
            shieldValue = round(totalHeal * shieldPercent / 
                self:GetEffectiveHealingBuffModifiers() / 
                self:GetEffectiveHealingDebuffModifiers())
            if shieldValue <= bsMinimum then
                isMinimum = true
                shieldValue = bsMinimum
            end
            predictedHeal = round(
                recentDmg * dsHealModifier * Tier14Bonus * 
					(1 + scentBloodStacks * scentBloodStackBuff) *
                    self:GetEffectiveHealingBuffModifiers() * 
                    self:GetEffectiveHealingDebuffModifiers())
        end

        if self.db.profile.debug then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Last5:%d, Pred:%d, Mast: %0.2f%%, SoB: %0.2f%%, MinBS: %d]"
			local sobValue = scentBloodStacks * scentBloodStackBuff
            self:Print(dsHealFormat:format(
                totalHeal,actualHeal,overheal,recentDmg,predictedHeal,shieldPercent*100,sobValue,bsMinimum))
        end
        
        if DEBUG_OUTPUT == true then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Last5:%d, Pred:%d, Mast: %0.2f%%, SoB: %0.2f%%, MinBS: %d]"
			local sobValue = scentBloodStacks * scentBloodStackBuff
            DEBUG_BUFFER = DEBUG_BUFFER .. timestamp .. "   " .. 
                dsHealFormat:format(totalHeal,actualHeal,overheal,
                recentDmg,predictedHeal,shieldPercent*100,sobValue,bsMinimum) .. "\n"
        end
    end

    if eventtype == "SPELL_AURA_APPLIED" and destName == self.playerName and param10 then
        if param10 then spellName = param10 end
        if param13 then spellAbsorb = param13 end

        if param9 == SpellIds["Blood Shield"] then
            if self.db.profile.debug then
                if spellAbsorb and spellAbsorb ~= "" then
                    self:Print("Blood Shield applied.  Value = "..spellAbsorb)
                else
                    self:Print("Blood Shield applied.  No value present.")
                end
            end

            if self.db.profile.useAuraForShield == false then
                self:NewBloodShield(timestamp, spellAbsorb, GetTime() + BS_DURATION)
            end
        elseif param9 == SpellIds["Shroud of Purgatory"] then
            if self.db.profile.debug then
                self:Print("Purgatory applied.  Value = "..tostring(spellAbsorb or 0)..", "..tostring(param14 or 0))
			end
        elseif param9 == SpellIds["Vampiric Blood"] then
            if self.db.profile.debug then
                self:Print("Vampiric Blood applied.")
            end
        elseif param9 == SpellIds["Guardian Spirit"] then
            if self.db.profile.debug then
                self:Print("Guardian Spirit applied.")
            end
        end
    end

    if eventtype == "SPELL_AURA_REFRESH" and destName == self.playerName then
        if param10 then spellName = param10 end
        if param13 then spellAbsorb = param13 end

        if param9 then
            if param9 == SpellIds["Blood Shield"] then
                if self.db.profile.debug and spellAbsorb and spellAbsorb ~= "" then
                    self:Print("Blood Shield refresh.  New value = "..spellAbsorb)
                end

                if self.db.profile.useAuraForShield == false then
                    self:BloodShieldUpdated("refreshed", timestamp, spellAbsorb or 0, GetTime() + BS_DURATION)
                end
	        elseif param9 == SpellIds["Shroud of Purgatory"] then
	            if self.db.profile.debug then
	                self:Print("Purgatory refreshed.  Value = "..tostring(spellAbsorb or 0)..", "..tostring(param14 or 0))
				end

            end
        end
    end

    if eventtype == "SPELL_AURA_REMOVED" and destName == self.playerName and param10 then
        if param10 then spellName = param10 end
        if param13 then spellAbsorb = param13 end

        if param9 == SpellIds["Blood Shield"] then
            if self.db.profile.useAuraForShield == false then
                self:BloodShieldUpdated("removed", timestamp, spellAbsorb or 0, 0)
            end

            if self.db.profile.debug and spellAbsorb and spellAbsorb ~= "" then
                self:Print("Blood Shield removed.  Remaining = "..spellAbsorb)
            end
        elseif param9 == SpellIds["Shroud of Purgatory"] then
            if self.db.profile.debug then
                self:Print("Purgatory removed.  Value = "..tostring(spellAbsorb or 0)..", "..tostring(param14 or 0))
			end
        elseif param9 == SpellIds["Vampiric Blood"] then
            if self.db.profile.debug then
                self:Print("Vampiric Blood removed.")
            end
        elseif param9 == SpellIds["Guardian Spirit"] then
            if self.db.profile.debug then
                self:Print("Guardian Spirit removed.")
            end
        end
    end
end

function BloodShieldTracker:NewBloodShield(timestamp, shieldValue, expires)
    self.shieldbar.active = true
    self.shieldbar.shield_curr = 0
    self.shieldbar.shield_max = 0
    self.shieldbar.expires = expires

    if not IsBloodTank or not hasBloodShield then return end

	local isMinimum = false
	-- Calculate the minimum shield value.  Use the previous SoB stack value.
	local minimumBS = round(maxHealth * actualDsMinHeal * Tier14Bonus *
		(1 + dsScentBloodStacks * scentBloodStackBuff) * shieldPercent)
	if shieldValue <= minimumBS then
		isMinimum = true
	end

    self.shieldbar.shield_max = self.shieldbar.shield_max + shieldValue
    self.shieldbar.shield_curr = self.shieldbar.shield_curr + shieldValue

    -- Update the LDB data feed
    DataFeed.lastBS = shieldValue
    if LDBDataFeed then
        UpdateLDBData()
    end

    if self.db.profile.debug or DEBUG_OUTPUT then
        local shieldInd = ""
        if isMinimum then
            shieldInd = " (min)"
        end

        local shieldFormat = "Blood Shield Amount: %d%s"
        if self.db.profile.debug then
            self:Print(shieldFormat:format(shieldValue,shieldInd))
        end

        if DEBUG_OUTPUT then
            DEBUG_BUFFER = DEBUG_BUFFER .. 
                shieldFormat:format(shieldValue,shieldInd) .."\n"
        end
    end

    self:UpdateStatsNewShield(shieldValue, isMinimum, false)
    self:ShowShieldBar()

    if self.shieldbar.db.sound_enabled and self.shieldbar.db.sound_applied then
        _G.PlaySoundFile(LSM:Fetch("sound", self.shieldbar.db.sound_applied))
    end
end

function BloodShieldTracker:UpdateStatsNewShield(value, isMinimum, isRefresh)
    TotalShieldStats:NewShield(value, isMinimum, isRefresh)
    LastFightStats:NewShield(value, isMinimum, isRefresh)
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
    if not IsBloodTank then return end

    if type == "refreshed" then
        self.shieldbar.active = true
    elseif type == "removed" then
        self.shieldbar.active = false
    end

    local curr = self.shieldbar.shield_curr or 0
    local isMinimum = false

    -- Calculate how much was added or absorbed
    local added = 0
    local absorbed = 0
    -- Check if the shield was increased due to a new DS/BS
    if current > curr then
        -- A new BS shield amount was added.  Update all of the stats.
        added = current - curr

        -- Check if it is a minimum heal.  Use the previous SoB stack value.
		local minimumBS = round(maxHealth * actualDsMinHeal * Tier14Bonus *
			(1 + dsScentBloodStacks * scentBloodStackBuff) * shieldPercent)
        if added <= minimumBS then
            isMinimum = true
        end
        self:UpdateStatsNewShield(added, isMinimum, true)
        self.shieldbar.expires = expires
        self.shieldbar.shield_max = self.shieldbar.shield_max + added

        -- Update the LDB data feed
        DataFeed.lastBS = added
        if LDBDataFeed then
            UpdateLDBData()
        end

        if DEBUG_OUTPUT then
            local shieldInd = ""
            if isMinimum then
                shieldInd = " (min)"
            end

            DEBUG_BUFFER = DEBUG_BUFFER .. 
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
        local addedFmt = "[Added %d%s]"
        local minStr = ""
        if isMinimum then
            minStr = " (min)"
        end
        local statusStr = ""
        if added > 0 then
            statusStr = addedFmt:format(added, minStr)
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

local function onUpdateBloodCharge(self, elapsed)
	self.lastUpdate = (self.lastUpdate or 0) + elapsed
	self.timer = self.timer - elapsed
	if self.lastUpdate >= 0.1 then
		if self.active then
			local profile = BloodShieldTracker.db.profile.bars["BloodChargeBar"]
			if self.timer < 0 then
				self.timer = 0
				self.active = false
				self:SetScript("OnUpdate", nil)
				self:Hide()
			else
				if profile.show_time then
					self.time:SetText(tostring(round(self.timer)))
				end
				self:Show()
				if profile.progress == "Time" then
					self:SetValue(self.timer)
				elseif profile.progress == "Charges" then
					self:SetValue(self.count)
				end
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
			local profile = BloodShieldTracker.db.profile.bars["AMSBar"]
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

function BloodShieldTracker:UNIT_AURA(...)
    local event, unit = ...
    if unit == "player" then
        self:CheckAuras()
    end
end

local BSAuraPresent = false
local BSAuraValue = 0
local BSAuraExpires = 0
local AurasFound = {}
local AuraData = {}
AuraData["Bone Shield"] = AuraData["Bone Shield"] or {}
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

    local iccBuffFound = false
    local vampBloodFound = false
    local healingDebuff = 0
	local BSValue = 0
	local BSExpires = 0
	local BSDuration = 0
	local BCExpires = 0
	local BCDuration = 0
	local BCCount = 0
	local AMSValue = 0
	local AMSExpires = 0
	local AMSDuration = 0
	local Results

    CurrentPresence = nil
	scentBloodStacks = 0
    DarkSuccorBuff = false
    luckOfTheDrawBuff = false
    luckOfTheDrawAmt = 0
	healingDebuffMultiplier = 0
    gsHealModifier = 0.0
	PurgatoryAbsorb = 0

    -- Loop through unit auras to find ones of interest.
    local i = 1
    repeat
        name, rank, icon, count, dispelType, duration, expires, caster, 
			stealable, consolidate, spellId, canApplyAura, isBossDebuff, 
			castByPlayer, value, value2, value3 = UnitAura("player", i)
        if name == nil or spellId == nil then break end

		local tracked = AbsorbShields[spellId]

		if spellId == SpellIds["Scent of Blood"] then
			scentBloodStacks = count

		elseif spellId == SpellIds["Bone Shield"] then
			AurasFound["Bone Shield"] = true
			AuraData["Bone Shield"].expires = expires
			AuraData["Bone Shield"].duration = duration
			AuraData["Bone Shield"].count = count

        elseif tracked then
            AurasFound[tracked] = true
            if value then
                OtherShields[tracked] = 
					(OtherShields[tracked] or 0) + value
			elseif self.db.profile.debug == true then
                self:Print(errorReadingFmt:format(SpellNames[tracked]))
            end
			
			if spellId == SpellIds["Blood Shield"] then
				BSValue = value
				BSExpires = expires
				BSDuration = duration
			end

			if spellId == SpellIds["Anti-Magic Shell"] then
				AMSValue = value
				AMSExpires = expires
				AMSDuration = duration
			end

		elseif spellId == SpellIds["Vengeance"] then
			AurasFound["Vengeance"] = true
			DataFeed.vengeance = value or 0
			UpdateLDBData()

		elseif spellId == SpellIds["Blood Charge"] then
			AurasFound["Blood Charge"] = true
			BCExpires = expires
			BCDuration = duration
			BCCount = count

        elseif spellId == SpellIds["Frost Presence"] then
            CurrentPresence = "Frost"

        elseif spellId == SpellIds["Unholy Presence"] then
            CurrentPresence = "Unholy"

        elseif spellId == SpellIds["Blood Presence"] then
            CurrentPresence = "Blood"

        elseif spellId == SpellIds["Dark Succor"] then
            DarkSuccorBuff = true

        elseif spellId == SpellIds["Luck of the Draw"] then
            luckOfTheDrawBuff = true
    	    if not count or count == 0 then
    	        count = 1
            end
            luckOfTheDrawAmt = LUCK_OF_THE_DRAW_MOD * count

        elseif name == SpellNames["Hellscream's Warsong 30"] then
            iccBuffFound = true
            iccBuff = true
            iccBuffAmt = ICCBuffs.Horde[spellId] or 
				ICCBuffs.Horde[SpellIds["Hellscream's Warsong 30"]]

        elseif name == SpellNames["Strength of Wrynn 30"] then
            iccBuffFound = true
            iccBuff = true
            iccBuffAmt = ICCBuffs.Alliance[spellId] or 
				ICCBuffs.Alliance[SpellIds["Strength of Wrynn 30"]]

        elseif spellId == SpellIds["Vampiric Blood"] then
			vampBloodFound = true
            vbBuff = true
    		-- No Need to check how much bonus health we get from VB since we listen
    		-- for Unit Max Health updates
            if hasVBGlyphed then
                vbHealthInc = vbGlyphedHealthInc
                vbHealingInc = vbGlyphedHealingInc
            else
                vbHealthInc = vbUnglyphedHealthInc
                vbHealingInc = vbUnglyphedHealingInc
            end

        elseif spellId == SpellIds["Guardian Spirit"] then
            AurasFound["Guardian Spirit"] = true
            gsHealModifier = guardianSpiritHealBuff
			
        else
            -- Check for various healing debuffs
        	for k,v in pairs(HealingDebuffs) do
        		if spellId == k then
        		    if not count or count == 0 then
        		        count = 1
        	        end
        			healingDebuff = v * count
        			if healingDebuff > healingDebuffMultiplier then
        			    healingDebuffMultiplier = healingDebuff
        			end
        		end
            end
        end 

        i = i + 1
    until name == nil

    i = 1
    repeat
        name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
            consolidate, spellId, canApplyAura, isBossDebuff, 
			castByPlayer, value, value2, value3 = UnitAura("player", i, "HARMFUL")
        if name == nil or spellId == nil then break end

        if spellId == SpellIds["Shroud of Purgatory"] then
            AurasFound["Shroud of Purgatory"] = true

			if not PurgatoryActive then
				if self.db.profile.debug then
					self:Print("Pugatory! ["..tostring(value or 0).."]")
				end
				PurgatoryActive = true
			end

			PurgatoryAbsorb = value or 0
		end

        i = i + 1
    until name == nil

	if not AurasFound["Vengeance"] then
		if DataFeed.vengeance > 0 then
			DataFeed.vengeance = 0
			UpdateLDBData()
		end
	end

    if self.pwsbar.db.enabled and IsBloodTank then
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
			self.pwsbar.bar:Hide()
		end

		PreviousShieldValues["PWSBar"] = shields
    end

    if self.illumbar.db.enabled and IsBloodTank then
        local illumValue = OtherShields["Illuminated Healing"]
        if AurasFound["Illuminated Healing"] then
            if illumValue and illumValue ~= PreviousShieldValues["PaladinBar"] then
                self.illumbar:SetValue(illumValue)
            end
            self.illumbar.bar:Show()
        else
            self.illumbar.bar:Hide()
        end
		
		PreviousShieldValues["PaladinBar"] = illumValue
    end

	if self.absorbsbar.db.enabled and IsBloodTank then
		local shields = 0
		local included = self.db.profile.bars["TotalAbsorbsBar"].included
		for k,v in pairs(OtherShields) do
			if included[k] == true then
				shields = shields + v
			end
		end

		if shields > 0 then
			if shields ~= PreviousShieldValues["TotalAbsorbsBar"] then
				self.absorbsbar:SetValue(shields)
			end
			self.absorbsbar.bar:Show()
		else
			self.absorbsbar.bar:Hide()
		end

		PreviousShieldValues["TotalAbsorbsBar"] = shields
	end

    if self.estimatebar.db.enabled and 
		self.estimatebar.db.show_stacks and IsBloodTank then
		self.estimatebar.bar.stacks:SetText(scentBloodStacks)
	end

	if self.purgatorybar.db.enabled and AurasFound["Shroud of Purgatory"] then
		self.purgatorybar:SetValue(PurgatoryAbsorb or 0)
		self.purgatorybar.bar:Show()
	else
		PurgatoryActive = false
		self.purgatorybar.bar:Hide()
	end

    -- If the ICC buff isn't present, reset the values
    if not iccBuffFound then
        iccBuff = false
        iccBuffAmt = 0.0
    end

    if not vampBloodFound then
        vbBuff = false
        vbHealthInc = 0.0
        vbHealingInc = 0.0
    end

	-- Just in case make sure the healing modifier is a sane value
	if healingDebuffMultiplier > 1 then
	    healingDebuffMultiplier = 1
    end

    self:UpdateMinHeal("CheckAura", "player")

	if self.db.profile.bars["BloodChargeBar"].enabled then
		local bcBar = self.bloodchargebar
		if AurasFound["Blood Charge"] then
			bcBar.bar.timer = BCExpires - GetTime()
			if bcBar.db.progress == "Charges" then
				bcBar.bar:SetMinMaxValues(0, MAX_BLOOD_CHARGES)
			elseif bcBar.db.progress == "Time" then
				bcBar.bar:SetMinMaxValues(0, BCDuration)
			else
				bcBar.bar:SetMinMaxValues(0, 1)
			end
			bcBar.bar.value:SetText(tostring(BCCount))
			bcBar.bar.active = true
			bcBar.bar.count = BCCount
			bcBar.bar:Show()
			bcBar.bar:SetScript("OnUpdate", onUpdateBloodCharge)
		else
			bcBar.bar.active = false
			bcBar.bar.timer = 0
			bcBar.bar:SetScript("OnUpdate", nil)
			bcBar.bar:Hide()
		end
	end

	if self.db.profile.bars["BoneShieldBar"].enabled and IsBloodTank then
		local bar = self.boneshieldbar
		local state = nil
		local data = AuraData["Bone Shield"]
		if AurasFound["Bone Shield"] then
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
			--bar.bar:Hide()

			local start, duration, enabled = 
				_G.GetSpellCooldown(SpellIds["Bone Shield"])
			if duration > 0 then
				state = 1
				bar.bar.recharging = true
				bar.bar.recharge = duration - (_G.GetTime() - start)
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
					bar.bar:SetMinMaxValues(0, 6)
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
					bar.bar:SetValue(_G.select(2, bar.bar:GetMinMaxValues()))
					bar.bar:SetScript("OnUpdate", onUpdateBoneShield)
					bar.bar:Show()
				else
					bar.bar:Hide()
				end
			else 
				-- Ready
				bar.bar.time:SetText("")
				bar.bar.value:SetText("-")
				if bar.db.showReady then
					bar.bar:SetAlpha(0.5)
					bar.bar:SetValue(_G.select(2, bar.bar:GetMinMaxValues()))
					bar.bar:SetScript("OnUpdate", nil)
					bar.bar:Show()
				else
					bar.bar:Hide()
				end
			end
		end
		bar.bar.state = state
	end

	if self.db.profile.bars["AMSBar"].enabled then
		local amsBar = self.amsbar
		if AurasFound["Anti-Magic Shell"] then
			amsBar:SetValue(AMSValue or 0)
			amsBar.bar.timer = AMSExpires - GetTime()
			if amsBar.bar.duration ~= AMSDuration then
				amsBar.bar.duration = AMSDuration
				amsBar.bar:SetMinMaxValues(0, amsBar.bar.duration or 1)
			end
			amsBar.bar.active = true
			amsBar.bar:Show()
			amsBar.bar:SetScript("OnUpdate", onUpdateAMS)
		else
			amsBar.bar.active = false
			amsBar.bar.timer = 0
			amsBar.bar:SetScript("OnUpdate", nil)
			amsBar.bar:Hide()
		end
	end

    if AurasFound["Blood Shield"] then
		if BSValue then
	        if BSAuraPresent == false then
	            -- Blood Shield applied
	            if self.db.profile.debug == true then
	                self:Print("AURA: Blood Shield applied. "..BSValue)
	            end
	            self:NewBloodShield(GetTime(), BSValue, BSExpires)
	        else
	            if BSValue ~= BSAuraValue or 
	                (BSExpires ~= BSAuraExpires and BSValue > 0) then
	                -- Blood Shield refreshed
	                if self.db.profile.debug == true then
	                    self:Print("AURA: Blood Shield refreshed. "..BSValue
	                        .." ["..(BSValue - BSAuraValue).."]")
	                end
	                self:BloodShieldUpdated("refreshed", GetTime(), 
						BSValue, BSExpires)
	            end
	        end

	        BSAuraValue = BSValue
	        BSAuraExpires = BSExpires
		else
			if self.db.profile.debug == true then
				self:Print("Error reading the Blood Shield value.")
			end
		end
        BSAuraPresent = true
	else
        if BSAuraPresent == true then
            -- Blood Shield removed
            if self.db.profile.debug == true then
                self:Print("AURA: Blood Shield removed. "..BSAuraValue)
            end

            self:BloodShieldUpdated("removed", GetTime(), BSAuraValue, 0)
        end
            
        BSAuraPresent = false
        BSAuraValue = 0
    end
end

local FrameNames = {
	["Compact Runes"] = "CompactRunes_RunicPowerBar",
}

function BloodShieldTracker:UpdateBarPosition()
end

-- Define a generic class for the bars
Bar.__index = Bar

function Bar:Create(name, friendlyName, hasTimeRemaining, disableAnchor)
    local object = _G.setmetatable({}, Bar)
	object.name = name
	object.friendlyName = friendlyName or name
	object.anchorTries = 0
	object.hasTimeRemaining = hasTimeRemaining
	object:Initialize()
	-- Add the bar to the addon's table of bars
	BloodShieldTracker.bars[name] = object
	if not disableAnchor then
		FrameNames[object.friendlyName] = object.bar:GetName()
	end
	object:UpdatePosition()
	return object
end

function Bar:Initialize()
	self.db = BloodShieldTracker.db.profile.bars[self.name]

    local bar = _G.CreateFrame("StatusBar", "BloodShieldTracker_"..self.name, _G.UIParent)
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
	local font = LSM:Fetch("font", BloodShieldTracker.db.profile.font_face)
    bar.value = bar:CreateFontString(nil, "OVERLAY")
    bar.value:SetPoint("CENTER")
    bar.value:SetFont(font, 
		BloodShieldTracker.db.profile.font_size, 
		BloodShieldTracker:GetFontFlags())
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
			BloodShieldTracker.db.profile.font_size, 
			BloodShieldTracker:GetFontFlags())
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
			BloodShieldTracker.db.profile.font_size, 
			BloodShieldTracker:GetFontFlags())
	    bar.stacks:SetJustifyH(self.db.stacks_pos or "LEFT")
	    bar.stacks:SetShadowOffset(1, -1)
	    bar.stacks:SetTextColor(tc.r, tc.g, tc.b, tc.a)
	    bar.stacks:SetText("0")
		self:UpdateVisibility()
	end

    bar:SetMovable()
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
	elseif self.name == "BloodChargeBar" or self.name == "BoneShieldBar" then
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
			(self.db.hide_ooc and (not _G.InCombatLockdown() or idle)) then
            if self.bar:IsVisible() then
                self.bar:Hide()
            end
        else
            self.bar:Show()
        end
	elseif self.name == "EstimateBar" then
		if self.db.enabled and BloodShieldTracker:IsTrackerEnabled() and
			(not self.db.hide_ooc or _G.InCombatLockdown()) then
			self.bar:Show()
		else
			self.bar:Hide()
		end

		if self.db.enabled and self.db.show_stacks and IsBloodTank then
		    self.bar.stacks:Show()
		else
		    self.bar.stacks:Hide()
		end
	elseif self.name == "BoneShieldBar" then
		if not self.db.enabled or not IsBloodTank then
			self.bar:Hide()
			self.bar:SetScript("OnUpdate", nil)
		end
	else
		if not self.db.enabled then
			self.bar:Hide()
		end
	end
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
		self.bar.value:SetText(FormatNumber(value))
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
	local anchorFrame = FrameNames[self.db.anchorFrame]
	if not anchorFrame and self.db.anchorFrame == "Custom" then
		anchorFrame = self.db.anchorFrameCustom
	end

	self.bar:ClearAllPoints()

	local isFrame = IsFrame(anchorFrame)
	local BST = BloodShieldTracker
	if anchorFrame and isFrame then
		if BST.db.profile.debug then
			BST:Print("Found anchor for bar '"..tostring(self.name).."'.")
		end
		self.bar:SetPoint(
			self.db.anchorPt, anchorFrame, self.db.anchorFramePt, 
			self.db.anchorX, self.db.anchorY)
		self.anchorTries = 0
	else
		self.bar:SetPoint("CENTER", _G.UIParent, "CENTER", self.db.x, self.db.y)
		if anchorFrame and not isFrame and self.anchorTries < 13 then
			if BST.db.profile.debug then
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
	local ff, fh, fontFlags = BloodShieldTracker:GetFontSettings()
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
	    if CustomUI.showBorders ~= nil then
	        if CustomUI.showBorders == true then
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
    if CustomUI.texture then
        bt = CustomUI.texture
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

function BloodShieldTracker:MigrateSettings()
	local profile_version = self.db.profile.profile_version

	if profile_version == nil or profile_version < 3 then
		self:MigrateSkinningSettings3()
	end

	if profile_version == nil or profile_version < 2 then
		self:MigrateShieldBarSettings2()
		self:MigrateEstimateBarSettings2()
		self:MigratePWSBarSettings2()
		self:MigrateIllumBarSettings2()
		self:MigrateHealthBarSettings2()
	end

	if profile_version == nil or profile_version < 4 then
		self:MigrateSettings4()
	end

	self.db.profile.profile_version = 4
end

function BloodShieldTracker:MigrateSettings4()
	local pwsbar = self.db.profile.bars["PWSBar"]
	local absbar = self.db.profile.bars["TotalAbsorbsBar"]

	-- Rename
	if pwsbar.included["DivineAegis"] ~= nil then
		pwsbar.included["Divine Aegis"] = pwsbar.included["DivineAegis"]
		pwsbar.included["DivineAegis"] = nil
	end
	if absbar.included["DivineAegis"] ~= nil then
		absbar.included["Divine Aegis"] = absbar.included["DivineAegis"]
		absbar.included["DivineAegis"] = nil
	end
	if absbar.included["IlluminatedHealing"] ~= nil then
		absbar.included["Illuminated Healing"] = absbar.included["IlluminatedHealing"]
		absbar.included["IlluminatedHealing"] = nil
	end
	if absbar.included["IndomitablePride"] ~= nil then
		absbar.included["Indomitable Pride"] = absbar.included["IndomitablePride"]
		absbar.included["IndomitablePride"] = nil
	end

	if pwsbar.includeda ~= nil then
		pwsbar.included["Divine Aegis"] = pwsbar.includeda
		pwsbar.includeda = nil
	end

	if absbar.includebs ~= nil then
		absbar.included["Blood Shield"] = absbar.includebs
		absbar.includebs = nil
	end
end

function BloodShieldTracker:MigrateIllumBarSettings2()
	local settings = self.db.profile.bars["IllumBar"]
	if self.db.profile.illumbar_enabled ~= nil then
		settings.enabled = self.db.profile.illumbar_enabled
	end
	if self.db.profile.illumbar_shown ~= nil then
		settings.shown = self.db.profile.illumbar_shown
	end
	if self.db.profile.lock_illumbar ~= nil then
		settings.locked = self.db.profile.lock_illumbar
	end
	if self.db.profile.lock_illum ~= nil then
		settings.locked = self.db.profile.lock_illum
	end
	if self.db.profile.illumbar_texture ~= nil then
		settings.texture = self.db.profile.illumbar_texture
	end
	if self.db.profile.illumbar_border ~= nil then
		settings.border = self.db.profile.illumbar_border
	end
	if self.db.profile.illumbar_color ~= nil then
		settings.color = self.db.profile.illumbar_color
	end
	if self.db.profile.illumbar_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.illumbar_bgcolor
	end
	if self.db.profile.illumbar_textcolor ~= nil then
		settings.textcolor = self.db.profile.illumbar_textcolor
	end
	if self.db.profile.illumbar_x ~= nil then
		settings.x = self.db.profile.illumbar_x
	end
	if self.db.profile.illumbar_y ~= nil then
		settings.y = self.db.profile.illumbar_y
	end
	if self.db.profile.illumbar_width ~= nil then
		settings.width = self.db.profile.illumbar_width
	end
	if self.db.profile.illumbar_height ~= nil then
		settings.height = self.db.profile.illumbar_height
	end
	if self.db.profile.illumbar_scale ~= nil then
		settings.scale = self.db.profile.illumbar_scale
	end

	self.db.profile.illumbar_enabled = nil
	self.db.profile.illumbar_shown = nil
	self.db.profile.lock_illum = nil
	self.db.profile.lock_illumbar = nil
	self.db.profile.illumbar_texture = nil
	self.db.profile.illumbar_border = nil
	self.db.profile.illumbar_color = nil
	self.db.profile.illumbar_bgcolor = nil
	self.db.profile.illumbar_textcolor = nil
	self.db.profile.illumbar_x = nil
	self.db.profile.illumbar_y = nil
	self.db.profile.illumbar_width = nil
	self.db.profile.illumbar_height = nil
	self.db.profile.illumbar_scale = nil
end

function BloodShieldTracker:MigratePWSBarSettings2()
	local settings = self.db.profile.bars["PWSBar"]
	if self.db.profile.pwsbar_enabled ~= nil then
		settings.enabled = self.db.profile.pwsbar_enabled
	end
	if self.db.profile.pwsbar_shown ~= nil then
		settings.shown = self.db.profile.pwsbar_shown
	end
	if self.db.profile.lock_pwsbar ~= nil then
		settings.locked = self.db.profile.lock_pwsbar
	end
	if self.db.profile.pwsbar_texture ~= nil then
		settings.texture = self.db.profile.pwsbar_texture
	end
	if self.db.profile.pwsbar_border ~= nil then
		settings.border = self.db.profile.pwsbar_border
	end
	if self.db.profile.pwsbar_color ~= nil then
		settings.color = self.db.profile.pwsbar_color
	end
	if self.db.profile.pwsbar_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.pwsbar_bgcolor
	end
	if self.db.profile.pwsbar_textcolor ~= nil then
		settings.textcolor = self.db.profile.pwsbar_textcolor
	end
	if self.db.profile.pwsbar_x ~= nil then
		settings.x = self.db.profile.pwsbar_x
	end
	if self.db.profile.pwsbar_y ~= nil then
		settings.y = self.db.profile.pwsbar_y
	end
	if self.db.profile.pwsbar_width ~= nil then
		settings.width = self.db.profile.pwsbar_width
	end
	if self.db.profile.pwsbar_height ~= nil then
		settings.height = self.db.profile.pwsbar_height
	end
	if self.db.profile.pwsbar_scale ~= nil then
		settings.scale = self.db.profile.pwsbar_scale
	end
	if self.db.profile.pwsbar_includeda ~= nil then
		settings.included["DivineAegis"] = self.db.profile.pwsbar_includeda
	end

	self.db.profile.pwsbar_enabled = nil
	self.db.profile.pwsbar_shown = nil
	self.db.profile.lock_pwsbar = nil
	self.db.profile.pwsbar_texture = nil
	self.db.profile.pwsbar_border = nil
	self.db.profile.pwsbar_color = nil
	self.db.profile.pwsbar_bgcolor = nil
	self.db.profile.pwsbar_textcolor = nil
	self.db.profile.pwsbar_x = nil
	self.db.profile.pwsbar_y = nil
	self.db.profile.pwsbar_width = nil
	self.db.profile.pwsbar_height = nil
	self.db.profile.pwsbar_scale = nil
	self.db.profile.pwsbar_includeda = nil
end

function BloodShieldTracker:MigrateHealthBarSettings2()
	local settings = self.db.profile.bars["HealthBar"]
	if self.db.profile.healthbar_enabled ~= nil then
		settings.enabled = self.db.profile.healthbar_enabled
	end
	if self.db.profile.healthbar_shown ~= nil then
		settings.shown = self.db.profile.healthbar_shown
	end
	if self.db.profile.lock_healthbar ~= nil then
		settings.locked = self.db.profile.lock_healthbar
	end
	if self.db.profile.healthbar_texture ~= nil then
		settings.texture = self.db.profile.healthbar_texture
	end
	if self.db.profile.healthbar_border ~= nil then
		settings.border = self.db.profile.healthbar_border
	end
	if self.db.profile.healthbar_color ~= nil then
		settings.color = self.db.profile.healthbar_color
	end
	if self.db.profile.healthbar_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.healthbar_bgcolor
	end
	if self.db.profile.healthbar_textcolor ~= nil then
		settings.textcolor = self.db.profile.healthbar_textcolor
	end
	if self.db.profile.healthbar_x ~= nil then
		settings.x = self.db.profile.healthbar_x
	end
	if self.db.profile.healthbar_y ~= nil then
		settings.y = self.db.profile.healthbar_y
	end
	if self.db.profile.healthbar_width ~= nil then
		settings.width = self.db.profile.healthbar_width
	end
	if self.db.profile.healthbar_height ~= nil then
		settings.height = self.db.profile.healthbar_height
	end
	if self.db.profile.healthbar_scale ~= nil then
		settings.scale = self.db.profile.healthbar_scale
	end
	if self.db.profile.healthbar_hide_ooc ~= nil then
		settings.hide_ooc = self.db.profile.healthbar_hide_ooc
	end
	if self.db.profile.healthbar_low_color ~= nil then
		settings.alt_color = self.db.profile.healthbar_low_color
	end
	if self.db.profile.healthbar_low_textcolor ~= nil then
		settings.alt_textcolor = self.db.profile.healthbar_low_textcolor
	end
	if self.db.profile.healthbar_low_bgcolor ~= nil then
		settings.alt_bgcolor = self.db.profile.healthbar_low_bgcolor
	end
	if self.db.profile.healthbar_low_percent ~= nil then
		settings.low_percent = self.db.profile.healthbar_low_percent
	end
	if self.db.profile.healthbar_text_format ~= nil then
		settings.text_format = self.db.profile.healthbar_text_format
	end

	self.db.profile.healthbar_enabled = nil
	self.db.profile.healthbar_shown = nil
	self.db.profile.lock_healthbar = nil
	self.db.profile.healthbar_texture = nil
	self.db.profile.healthbar_border = nil
	self.db.profile.healthbar_color = nil
	self.db.profile.healthbar_bgcolor = nil
	self.db.profile.healthbar_textcolor = nil
	self.db.profile.healthbar_x = nil
	self.db.profile.healthbar_y = nil
	self.db.profile.healthbar_width = nil
	self.db.profile.healthbar_height = nil
	self.db.profile.healthbar_scale = nil
	self.db.profile.healthbar_hide_ooc = nil
	self.db.profile.healthbar_low_color  = nil
	self.db.profile.healthbar_low_textcolor  = nil
	self.db.profile.healthbar_low_bgcolor  = nil
	self.db.profile.healthbar_low_percent = nil
	self.db.profile.healthbar_text_format = nil
end

function BloodShieldTracker:MigrateEstimateBarSettings2()
	local settings = self.db.profile.bars["EstimateBar"]
	if self.db.profile.damage_bar_enabled ~= nil then
		settings.enabled = self.db.profile.damage_bar_enabled
	end
	if self.db.profile.hide_damage_bar_ooc ~= nil then
		settings.hide_ooc = self.db.profile.hide_damage_bar_ooc
	end
	if self.db.profile.lock_damage_bar ~= nil then
		settings.locked = self.db.profile.lock_damage_bar
	end
	if self.db.profile.damage_bar_width ~= nil then
		settings.width = self.db.profile.damage_bar_width
	end
	if self.db.profile.damage_bar_height ~= nil then
		settings.height = self.db.profile.damage_bar_height
	end
	if self.db.profile.estheal_bar_texture ~= nil then
		settings.texture = self.db.profile.estheal_bar_texture
	end
	if self.db.profile.estheal_bar_min_textcolor ~= nil then
		settings.textcolor = self.db.profile.estheal_bar_min_textcolor
	end
	if self.db.profile.estheal_bar_min_color ~= nil then
		settings.color = self.db.profile.estheal_bar_min_color
	end
	if self.db.profile.estheal_bar_min_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.estheal_bar_min_bgcolor
	end
	if self.db.profile.estheal_bar_opt_textcolor ~= nil then
		settings.alt_textcolor = self.db.profile.estheal_bar_opt_textcolor
	end
	if self.db.profile.estheal_bar_opt_color ~= nil then
		settings.alt_color = self.db.profile.estheal_bar_opt_color
	end
	if self.db.profile.estheal_bar_opt_bgcolor ~= nil then
		settings.alt_bgcolor = self.db.profile.estheal_bar_opt_bgcolor
	end
	if self.db.profile.estimate_bar_mode ~= nil then
		settings.bar_mode = self.db.profile.estimate_bar_mode
	end
	if self.db.profile.estheal_bar_border ~= nil then
		settings.border = self.db.profile.estheal_bar_border
	end
	if self.db.profile.estheal_bar_shown ~= nil then
		settings.shown = self.db.profile.estheal_bar_shown
	end
	if self.db.profile.estheal_bar_show_text ~= nil then
		settings.show_text = self.db.profile.estheal_bar_show_text
	end
	if self.db.profile.est_heal_x ~= nil then
		settings.x = self.db.profile.est_heal_x
	end
	if self.db.profile.est_heal_y ~= nil then
		settings.y = self.db.profile.est_heal_y
	end
	if self.db.profile.estheal_bar_scale ~= nil then
		settings.scale = self.db.profile.estheal_bar_scale
	end
	if self.db.profile.latencyMethod ~= nil then
		settings.latencyMethod = self.db.profile.latencyMethod
	end
	if self.db.profile.latencyFixed ~= nil then
		settings.latencyFixed = self.db.profile.latencyFixed
	end

    self.db.profile.damage_bar_enabled = nil
    self.db.profile.hide_damage_bar_ooc = nil
	self.db.profile.lock_damage_bar = nil
	self.db.profile.damage_bar_width = nil
	self.db.profile.damage_bar_height = nil
	self.db.profile.estheal_bar_texture = nil
	self.db.profile.estheal_bar_min_textcolor = nil
	self.db.profile.estheal_bar_min_color = nil
	self.db.profile.estheal_bar_min_bgcolor = nil
	self.db.profile.estheal_bar_opt_textcolor = nil
	self.db.profile.estheal_bar_opt_color = nil
	self.db.profile.estheal_bar_opt_bgcolor = nil
	self.db.profile.estimate_bar_mode = nil
	self.db.profile.estheal_bar_border = nil
	self.db.profile.estheal_bar_shown = nil
	self.db.profile.estheal_bar_show_text = nil
	self.db.profile.est_heal_x = nil
	self.db.profile.est_heal_y = nil
	self.db.profile.estheal_bar_scale = nil
	self.db.profile.latencyMethod = nil
	self.db.profile.latencyFixed = nil
end

function BloodShieldTracker:MigrateShieldBarSettings2()
	local settings = self.db.profile.bars["ShieldBar"]
	if self.db.profile.status_bar_enabled ~= nil then
		settings.enabled = self.db.profile.status_bar_enabled
	end
	if self.db.profile.lock_status_bar ~= nil then
		settings.locked = self.db.profile.lock_status_bar
	end
	if self.db.profile.status_bar_width ~= nil then
		settings.width = self.db.profile.status_bar_width
	end
	if self.db.profile.status_bar_height ~= nil then
		settings.height = self.db.profile.status_bar_height
	end
	if self.db.profile.shield_bar_progress ~= nil then
		settings.progress = self.db.profile.shield_bar_progress
	end
	if self.db.profile.shield_bar_show_time ~= nil then
		settings.show_time = self.db.profile.shield_bar_show_time
	end
	if self.db.profile.shield_bar_time_pos ~= nil then
		settings.time_pos = self.db.profile.shield_bar_time_pos
	end
	if self.db.profile.shield_sound_enabled ~= nil then
		settings.sound_enabled = self.db.profile.shield_sound_enabled
	end
	if self.db.profile.shield_applied_sound ~= nil then
		settings.sound_applied = self.db.profile.shield_applied_sound
	end
	if self.db.profile.shield_removed_sound ~= nil then
		settings.sound_removed = self.db.profile.shield_removed_sound
	end
	if self.db.profile.shield_bar_text_format ~= nil then
		settings.text_format = self.db.profile.shield_bar_text_format
	end
	if self.db.profile.status_bar_color ~= nil then
		settings.color = self.db.profile.status_bar_color
	end
	if self.db.profile.status_bar_textcolor ~= nil then
		settings.textcolor = self.db.profile.status_bar_textcolor
	end
	if self.db.profile.status_bar_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.status_bar_bgcolor
	end
	if self.db.profile.status_bar_texture ~= nil then
		settings.texture = self.db.profile.status_bar_texture
	end
	if self.db.profile.status_bar_border ~= nil then
		settings.border = self.db.profile.status_bar_border
	end
	if self.db.profile.status_bar_shown ~= nil then
		settings.shown = self.db.profile.status_bar_shown
	end
	if self.db.profile.shield_bar_x ~= nil then
		settings.x = self.db.profile.shield_bar_x
	end
	if self.db.profile.shield_bar_y ~= nil then
		settings.y = self.db.profile.shield_bar_y
	end
	if self.db.profile.status_bar_scale ~= nil then
		settings.scale = self.db.profile.status_bar_scale
	end

	self.db.profile.status_bar_enabled = nil
	self.db.profile.lock_status_bar = nil
	self.db.profile.status_bar_width = nil
	self.db.profile.status_bar_height = nil
	self.db.profile.shield_bar_progress = nil
	self.db.profile.shield_bar_show_time = nil
	self.db.profile.shield_bar_time_pos = nil
	self.db.profile.shield_sound_enabled = nil
	self.db.profile.shield_applied_sound = nil
	self.db.profile.shield_removed_sound = nil
	self.db.profile.shield_bar_text_format = nil
	self.db.profile.status_bar_color = nil
	self.db.profile.status_bar_textcolor = nil
	self.db.profile.status_bar_bgcolor = nil
	self.db.profile.status_bar_texture = nil
	self.db.profile.status_bar_border = nil
	self.db.profile.status_bar_shown = nil
	self.db.profile.shield_bar_x = nil
	self.db.profile.shield_bar_y = nil
	self.db.profile.status_bar_scale = nil
end

function BloodShieldTracker:MigrateSkinningSettings3()
	local elvui = self.db.profile.skinning.elvui
	local tukui = self.db.profile.skinning.tukui
	if self.db.profile.elvui_enabled ~= nil then
		elvui.enabled = self.db.profile.elvui_enabled
	end
	if self.db.profile.elvui_borders ~= nil then
		elvui.borders = self.db.profile.elvui_borders
	end
	if self.db.profile.elvui_texture ~= nil then
		elvui.texture = self.db.profile.elvui_texture
	end
	if self.db.profile.elvui_font ~= nil then
		elvui.font = self.db.profile.elvui_font
	end
	if self.db.profile.elvui_font_flags ~= nil then
		elvui.font_flags = self.db.profile.elvui_font_flags
	end
	if self.db.profile.tukui_enabled ~= nil then
		tukui.enabled = self.db.profile.tukui_enabled
	end
	if self.db.profile.tukui_borders ~= nil then
		tukui.borders = self.db.profile.tukui_borders
	end
	if self.db.profile.tukui_texture ~= nil then
		tukui.texture = self.db.profile.tukui_texture
	end
	if self.db.profile.tukui_font ~= nil then
		tukui.font = self.db.profile.tukui_font
	end
	if self.db.profile.tukui_font_flags ~= nil then
		tukui.font_flags = self.db.profile.tukui_font_flags
	end

    self.db.profile.tukui_enabled = nil
    self.db.profile.tukui_borders = nil
    self.db.profile.tukui_texture = nil
    self.db.profile.tukui_font = nil
    self.db.profile.tukui_font_flags = nil
    self.db.profile.elvui_enabled = nil
    self.db.profile.elvui_borders = nil
    self.db.profile.elvui_texture = nil
    self.db.profile.elvui_font = nil
    self.db.profile.elvui_font_flags = nil
end
