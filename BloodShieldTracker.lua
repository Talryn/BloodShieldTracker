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

local DEBUG_OUTPUT = false
local DEBUG_BUFFER = ""

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
local UnitStat = _G.UnitStat
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
BloodShieldTracker.illumbar = nil

-- Player class, talent, and spec info
addon.isDK = nil
addon.currentSpec = ""
addon.IsBloodTank = false
local hasBloodShield = false
local HasVampBlood = false
local hasVBGlyphed = false
local Tier14Count = 0
local Tier14Bonus = 1
BloodShieldTracker.tierCount = {
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

-- Keep track of time.  Start with current client time
-- but will use the combat log timestamps after that.
local currentTime = time()
addon.idle = true
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
	["Resolve"] = 158300,
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
	"Illuminated Healing",
	"Divine Aegis",
	"Life Cocoon",
	"Spirit Shell",
	"Guard",
	"Indomitable Pride",
	"Sacred Shield",
	"Anti-Magic Shell",
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

-- MoP Constants
local dsHealModifier = 0.20  -- Percent of the DS Heal from the tooltip.
local dsMinHealPercent = 0.07
local dsMinHealPercentSuccor = 0.20

local scentBloodStackBuff = 0.2
local vbGlyphedHealthInc = 0.0
local vbGlyphedHealingInc = 0.4
local vbUnglyphedHealthInc = 0.15
local vbUnglyphedHealingInc = 0.25
if addon.WoD then
	vbGlyphedHealingInc = 0.25
	vbUnglyphedHealingInc = 0.15
end

local guardianSpiritHealBuff = 0.40
if addon.WoD then
	guardianSpiritHealBuff = 0.60
end

local T14BonusAmt = 0.1

-- Curent state information
local DarkSuccorBuff = false
local DS_SentTime = nil
local DS_Latency = nil

-- MoP Variables --
-- The actual minimum DS heal percent, based on spec, glyphs, and presence.
local actualDsMinHeal = dsMinHealPercent
local dsHealMin = 0
local bsMinimum = 0
-- End --

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
local versatilityBonus = 0
local versatilityPercent = 0
local shieldPercent = 0
addon.effectiveAP = 0
addon.resolve = 0
addon.resolveInt = 0
addon.resolveDmg = 0
addon.resolveDmg2 = 0
addon.playerLevel = _G.UnitLevel("player")
addon.baselineDPS = addon.BaselineDPSScaling[addon.playerLevel] or 1
local dsHealAPMod = 1

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
	vengeance = 0,
	resolve = 0,
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
	elseif DataFeed.display == "Vengeance" then
		Broker.obj.text = addon.FormatNumber(DataFeed.vengeance)
	elseif DataFeed.display == "Resolve" then
		Broker.obj.text = addon.FormatNumber(percentFormat:format(addon.resolve))
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
local dataLine2 = YELLOW..L["Number of Minimum Shields:"]
local shieldDataMinShld = "%d (%d%%)"
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

addon.ResolveModes = {
	["Actual"] = true,
	["Calculated"] = true,
}

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
		useAuraForShield = true,
		resolveMode = "Actual",
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
				tracked = "Selected",
				included = {
					["Blood Shield"] = false,
					["Power Word: Shield"] = true,
					["Divine Aegis"] = true,
					["Illuminated Healing"] = true,
					["Life Cocoon"] = true,
					["Guard"] = true,
					["Indomitable Pride"] = true,
					["Spirit Shell"] = true,
					["Sacred Shield"] = true,
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
			["ResolveBar"] = {
				enabled = false,
				x = -125,
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
    elseif cmds[1] and cmds[1] == "resolveMode" then
			local isSet = false
			if cmds[2] and addon.ResolveModes[cmds[2]] then
				self.db.profile.resolveMode = cmds[2]
				isSet = true
			end
			self:Print("Resolve Mode: "..tostring(self.db.profile.resolveMode))
			if not isSet then
				local availModes = "Available Modes: "
				local first = true
				for k,v in pairs(addon.ResolveModes) do
					if not first then
						availModes = availModes .. ", "
					else
						first = false
					end
					availModes = availModes .. tostring(k)
				end
				self:Print(availModes)
			end
        end
        --_G.LibStub("AceConfigCmd-3.0").HandleCommand(BloodShieldTracker, "bst", "BloodShieldTracker", input)
    end
end

function BloodShieldTracker:OnInitialize()
  -- Load the settings
  self.db = _G.LibStub("AceDB-3.0"):New("BloodShieldTrackerDB", 
		addon.defaults, "Default")
	addon.db = self.db

	-- Migrate the settings
	self:MigrateSettings()

	DEBUG_OUTPUT = self.db.profile.debug

	-- Set the number format
	addon:SetNumberFormat(self.db.profile.numberFormat)

    -- Set the precision
	addon:SetNumberPrecision()

	-- Set Resolve Mode
	addon.SetResolveMode()

	-- Create the bars
	self.shieldbar = Bar:Create("ShieldBar", "Shield Bar", true)
	self:UpdateShieldBarMode()
  self:UpdateShieldBarText(0, 0, 0)
  self.estimatebar = Bar:Create("EstimateBar", "Estimate Bar", false)
	self.pwsbar = Bar:Create("PWSBar", "PW:S Bar", false)
	self.illumbar = Bar:Create("IllumBar", "Illuminated Healing Bar", false)
	self.absorbsbar = Bar:Create("TotalAbsorbsBar", "Total Absorbs Bar", false)
	self.purgatorybar = Bar:Create("PurgatoryBar", "Purgatory Bar", false)
	self.bloodchargebar = Bar:Create("BloodChargeBar", "Blood Charge Bar", true)
	self.boneshieldbar = Bar:Create("BoneShieldBar", "Bone Shield Bar", true)
	self.amsbar = Bar:Create("AMSBar", "Anti-Magic Shell Bar", true)
	self.resolvebar = Bar:Create("ResolveBar", "Resolve Bar", false)

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

function addon.SetResolveActual()
	addon.resolve = addon.resolveInt / 100.0
end
function addon.SetResolveCalculated()
	local dmgMod = addon.resolveDmg2 / (addon.baselineDPS * 10)
	--addon.resolve = max(0, 8.5 * (1 - exp(-0.045*dmgMod)) - 1)
	addon.resolve = max(0, 3.4 * (1 - exp(-0.045*dmgMod)) - 1)
end
function addon.SetResolveMode()
	local mode = addon.db.profile.resolveMode
	if mode == "Calculated" then
		addon.SetResolve = addon.SetResolveCalculated
	else
		addon.SetResolve = addon.SetResolveActual
	end
end
addon.SetResolve = addon.SetResolveActual

local resolveFmt = "Resolve: %.1f [%d,%d,%d]"
function BloodShieldTracker:UpdateResolve()
	addon.SetResolve()
	--if self.db.profile.debug then
	--	self:Print(resolveFmt:format(addon.resolve*100, 
	--		addon.resolveInt or 0, addon.resolveDmg or 0, addon.resolveDmg2 or 0))
	--end
	self:UpdateEstimateBar()
	self:UpdateMinHeal()
  if addon.LDBDataFeed then
      addon:UpdateLDBData()
  end
end

function BloodShieldTracker:UpdateStats()
	local update = false
	local base, posBuff, negBuff = UnitAttackPower("player")
	local effAP = base + posBuff - negBuff
	if effAP ~= addon.effectiveAP then
		addon.effectiveAP = effAP
		update = true
	end

	local stam, effStam, posBuff, negBuff = UnitStat("player", 3)
	if effStam ~= addon.stamina then
		addon.stamina = effStam
		update = true
	end

	if update then
		self:UpdateResolve()
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
		self.optionsFrame.ResolveBar = ACD:AddToBlizOptions(
		    displayName, L["Resolve Bar"], displayName, "resolveBarOpts")

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
	self:UpdateRatings()
	-- Force update to max health and update the estimated heal
	self:UNIT_MAXHEALTH("UNIT_MAXHEALTH", "player")
	self:CheckTalents()
	self:RegisterEvent("PLAYER_TALENT_UPDATE", "CheckTalents")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","CheckTalents")
	self:RegisterEvent("GLYPH_ADDED", "CheckGlyphs")
	self:RegisterEvent("GLYPH_REMOVED", "CheckGlyphs")
	self:RegisterEvent("GLYPH_UPDATED", "CheckGlyphs")
	
	for name, obj in pairs(addon.modules) do
		if obj and obj.Enable then
			obj:Enable()
		end
	end
end

local UnitEvents = {
	["player"] = {
		["UNIT_AURA"] = true,
		["UNIT_SPELLCAST_SUCCEEDED"] = true,
		["UNIT_ATTACK_POWER"] = true,
		["UNIT_STATS"] = true,
		["UNIT_LEVEL"] = true,
		["UNIT_MAXHEALTH"] = true,
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
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("COMBAT_RATING_UPDATE","UpdateRatings")
	self:RegisterEvent("MASTERY_UPDATE","UpdateRatings")
	self:RegisterEvent("PLAYER_DEAD")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckAuras")
	self:RegisterEvent("PLAYER_ALIVE", "CheckAuras")
	self:RegisterEvent("UNIT_SPELLCAST_SENT")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

	addon.RegisterUnitEvents(EventFrames, UnitEvents)
	self:UpdateStats()

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
	self:UnregisterEvent("PLAYER_DEAD")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("PLAYER_ALIVE")
    self:UnregisterEvent("UNIT_SPELLCAST_SENT")
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

local CR_VERSATILITY_DAMAGE_DONE = _G.CR_VERSATILITY_DAMAGE_DONE or 29
function BloodShieldTracker:UpdateRatings()
	masteryRating = GetMasteryEffect()
	shieldPercent = masteryRating/100
	if addon.WoD then
		versatilityBonus = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) + 
			GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
		versatilityPercent = versatilityBonus/100
	end
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

	self.bars["EstimateBar"]:UpdateVisibility()
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
				-- For WoD, the Mastery spell isn't known, just use level for now
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
		self:CheckGlyphs()
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

		if count ~= self.tierCount[tier] then
			self.tierCount[tier] = count
			if self.db.profile.debug and not _G.UnitAffectingCombat("player") then
				local fmt = "%s Detected: %d/5"
				self:Print(fmt:format(tier, self.tierCount[tier]))
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
	local currentBonus = Tier14Bonus
	Tier14Bonus = 1 + (self.tierCount["T14 Tank"] >= 4 and T14BonusAmt or 0)
	if currentBonus ~= Tier14Bonus then
		self:UpdateMinHeal("CheckGear", "player")
		if self.db.profile.verbose and addon.idle then
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

function BloodShieldTracker:UNIT_MAXHEALTH(event, unit)
	if unit == "player" then
		local maxHealth = UnitHealthMax("player")
		if maxHealth ~= addon.maxHealth then
			addon.maxHealth = maxHealth or 1
		end
		self:UpdateMinHeal(event, unit)
	end
end

function BloodShieldTracker:UpdateMinHeal(event, unit)
	if unit == "player" then
		local baseValue
		if addon.WoD then
			baseValue = addon.effectiveAP * dsHealAPMod * (1+addon.resolve) * 
				(1 + scentBloodStacks * scentBloodStackBuff) * (1+versatilityPercent)
				if DarkSuccorBuff then
					baseValue = baseValue * addon.DarkSuccorBuffValue
				end
		else
			local maxHealth = UnitHealthMax("player")
			actualDsMinHeal = dsMinHealPercent
			if DarkSuccorBuff == true and 
				(CurrentPresence == "Unholy" or CurrentPresence == "Frost") then
				actualDsMinHeal = dsMinHealPercentSuccor
			end
			baseValue = maxHealth * actualDsMinHeal * Tier14Bonus *
				(1 + scentBloodStacks * scentBloodStackBuff)
		end
		dsHealMin = round(baseValue *
			self:GetEffectiveHealingBuffModifiers() * 
			self:GetEffectiveHealingDebuffModifiers())
		bsMinimum = round(baseValue * shieldPercent)
		if addon.idle then
			self:UpdateEstimateBarTextWithMin()
		end
	end
end

local function UpdateTime(self, elapsed)
    currentTime = currentTime + elapsed
end

function BloodShieldTracker:PLAYER_REGEN_DISABLED()
	-- Once combat starts, update the damage bar.
	addon.idle = false
	if addon:IsTrackerEnabled() then
    	updateTimer = self:ScheduleRepeatingTimer("UpdateBars", 0.5)
        if self.estimatebar.db.enabled then
	        self.estimatebar.bar:Show()
	        self.estimatebar.bar:SetScript("OnUpdate", UpdateTime)
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
	addon.idle = true
	self:UpdateEstimateBarTextWithMin()
    self.estimatebar.altcolor = false
    self.estimatebar:UpdateGraphics()
    self.estimatebar.bar:SetMinMaxValues(0, 1)
    self.estimatebar.bar:SetValue(1)
    
    if self.estimatebar.db.hide_ooc then
        self.estimatebar.bar:Hide()
    end

    self.estimatebar.bar:SetScript("OnUpdate", nil)
    LastFightStats:EndCombat()
end

function BloodShieldTracker:PLAYER_DEAD()
    -- Just in case, hide the BS bar if the player dies
    --self.shieldbar.bar.timer = 0
    self:CheckAuras()
    --self.shieldbar.bar:Hide()
    -- Hide the estimate bar if configured to do so for OOC
    if self.estimatebar.db.hide_ooc then
        if self.estimatebar.bar:IsVisible() then
            self.estimatebar.bar:Hide()
        end
    end
	if DataFeed.vengeance > 0 then
		DataFeed.vengeance = 0
		addon:UpdateLDBData()
	end
end

function BloodShieldTracker:UpdateBars(timestamp)
    -- If we're out of combat and no Blood Shields are present, stop the timer
    if addon.idle then
    	if updateTimer then
            self:CancelTimer(updateTimer)
            updateTimer = nil
        end
    end
    self:UpdateEstimateBar(timestamp)
end

function BloodShieldTracker:UpdateEstimateBarWoD()
	local db = self.estimatebar.db
    if not db.enabled or addon.idle then return end

	local baseValue = addon.effectiveAP * dsHealAPMod * (1+addon.resolve) * 
		(1 + scentBloodStacks * scentBloodStackBuff) * (1+versatilityPercent)
	local estimate

    if self.estimatebar.db.bar_mode == "BS" then
        estimate = round(baseValue * shieldPercent)
    else
        estimate = round(baseValue *
            self:GetEffectiveHealingBuffModifiers() * 
            self:GetEffectiveHealingDebuffModifiers())
    end

    self:UpdateEstimateBarText(estimate)
    --self.estimatebar.bar:SetMinMaxValues(0, estimate)
    DataFeed.estimateBar = estimate
    if addon.LDBDataFeed then
        addon:UpdateLDBData()
    end
end

function BloodShieldTracker:UpdateEstimateBarMoP(timestamp)
    if self.estimatebar.db.enabled and not addon.idle then
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
        if addon.LDBDataFeed then
            addon:UpdateLDBData()
        end
    end
end

BloodShieldTracker.UpdateEstimateBar = addon.WoD and 
 BloodShieldTracker.UpdateEstimateBarWoD or BloodShieldTracker.UpdateEstimateBarMoP

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
			addon.FormatWithPrecision(estimate / addon.maxHealth * 100))
	else
		val = addon.FormatNumber(estimate)
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

function BloodShieldTracker:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, rank, lineId, spellId)
    if unit == "player" then
		if spellName == SpellNames["Death Strike"] then
	        local succeededTime = GetTime()
	        if DS_SentTime then
	            local diff = succeededTime - DS_SentTime
	            if diff > 0 then
	                DS_Latency = diff
	                if self.db.profile.debug and not addon.WoD then
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
                local swingDmgFmt = "Swing Damage for %d [%d absorbed, %s]"
                self:Print(swingDmgFmt:format(damage, absorb, eventtype))
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

        if self.db.profile.debug and not addon.WoD then
            local dsHealFormat = "Estimated damage: %d will be a heal for: %d"
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
        if addon.LDBDataFeed then
            addon:UpdateLDBData()
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
            predictedHeal = addon.WoD and dsHealMin or round(
                recentDmg * dsHealModifier * Tier14Bonus * 
					(1 + scentBloodStacks * scentBloodStackBuff) *
                    self:GetEffectiveHealingBuffModifiers() * 
                    self:GetEffectiveHealingDebuffModifiers())
        end

        if self.db.profile.debug then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Pred:%d, Mast: %0.2f%%, Vers: %0.2f%%, SoB: %0.2f%%]"
			local sobValue = scentBloodStacks * scentBloodStackBuff
            self:Print(dsHealFormat:format(
				totalHeal,actualHeal,overheal,predictedHeal,shieldPercent*100,
				versatilityBonus,sobValue))
        end
        
        if DEBUG_OUTPUT == true then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Pred:%d, Mast: %0.2f%%, Vers: %0.2f%%, SoB: %0.2f%%]"
			local sobValue = scentBloodStacks * scentBloodStackBuff
            DEBUG_BUFFER = DEBUG_BUFFER .. timestamp .. "   " .. 
                dsHealFormat:format(totalHeal,actualHeal,overheal,
                predictedHeal,shieldPercent*100,versatilityBonus,
								sobValue) .. "\n"
        end
    end

    if eventtype == "SPELL_AURA_APPLIED" and destName == self.playerName and param10 then
        if param10 then spellName = param10 end
        if param13 then spellAbsorb = param13 end

        if param9 == SpellIds["Blood Shield"] then
            if self.db.profile.debug and not addon.WoD then
                if spellAbsorb and spellAbsorb ~= "" then
                    self:Print("Blood Shield applied.  Value = "..spellAbsorb)
                else
                    self:Print("Blood Shield applied.  No value present.")
                end
            end

            if self.db.profile.useAuraForShield == false then
                self:NewBloodShield(timestamp, spellAbsorb, 
					GetTime() + addon.BS_DURATION)
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
                if self.db.profile.debug and not addon.WoD and
					spellAbsorb and spellAbsorb ~= "" then
                    self:Print("Blood Shield refresh.  New value = "..spellAbsorb)
                end

                if self.db.profile.useAuraForShield == false then
                    self:BloodShieldUpdated("refreshed", timestamp, 
						spellAbsorb or 0, GetTime() + addon.BS_DURATION)
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

            if self.db.profile.debug and not addon.WoD and
			 	spellAbsorb and spellAbsorb ~= "" then
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

    if not addon.IsBloodTank or not hasBloodShield then return end

	local isMinimum = false
	-- Calculate the minimum shield value.  Use the previous SoB stack value.
	local minimumBS = round(addon.maxHealth * actualDsMinHeal * Tier14Bonus *
		(1 + dsScentBloodStacks * scentBloodStackBuff) * shieldPercent)
	if shieldValue <= minimumBS then
		isMinimum = true
	end

    self.shieldbar.shield_max = self.shieldbar.shield_max + shieldValue
    self.shieldbar.shield_curr = self.shieldbar.shield_curr + shieldValue

    -- Update the LDB data feed
    DataFeed.lastBS = shieldValue
    if addon.LDBDataFeed then
        addon:UpdateLDBData()
    end

    if self.db.profile.debug or DEBUG_OUTPUT then
        local shieldInd = ""
        if isMinimum then
            shieldInd = " (min)"
        end

        local shieldFormat = "Blood Shield Amount: %d%s"
        if self.db.profile.debug and not addon.WoD then
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
    if not addon.IsBloodTank then return end

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
		local minimumBS = round(addon.maxHealth * actualDsMinHeal * Tier14Bonus *
			(1 + dsScentBloodStacks * scentBloodStackBuff) * shieldPercent)
        if added <= minimumBS then
            isMinimum = true
        end
        self:UpdateStatsNewShield(added, isMinimum, true)
        self.shieldbar.expires = expires
        self.shieldbar.shield_max = self.shieldbar.shield_max + added

        -- Update the LDB data feed
        DataFeed.lastBS = added
        if addon.LDBDataFeed then
            addon:UpdateLDBData()
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

function BloodShieldTracker:UNIT_ATTACK_POWER(event, unit)
	if unit == "player" then
		if addon.WoD then
			self:UpdateStats()
		end
	end
end

function BloodShieldTracker:UNIT_STATS(event, unit)
	if unit == "player" then
		if addon.WoD then
			self:UpdateStats()
		end
	end
end

function BloodShieldTracker:UNIT_LEVEL(event, unit)
	if unit == "player" then
		addon.playerLevel = _G.UNIT_LEVEL("player")
		addon.baselineDPS = addon.BaselineDPSScaling[addon.playerLevel] or 1
		if addon.WoD then
			self:UpdateStats()
		end
	end
end

function BloodShieldTracker:UNIT_AURA(event, unit, ...)
    if unit == "player" then
        self:CheckAuras()
    end
end

local TrackWithDataNames = {
	"Blood Shield",
	"Bone Shield",
	"Anti-Magic Shell",
	"Blood Charge"
}
local TrackWithData = {}
for i, k in ipairs(TrackWithDataNames) do
	TrackWithData[SpellIds[k]] = k
end
local BSAuraPresent = false
local BSAuraValue = 0
local BSAuraExpires = 0
local AurasFound = {}
local AuraData = {}
for i, k in ipairs(TrackWithDataNames) do
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

    local iccBuffFound = false
    local vampBloodFound = false
    local healingDebuff = 0
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
		local trackedWithData = TrackWithData[spellId]

		if spellId == SpellIds["Scent of Blood"] then
			scentBloodStacks = count

		elseif trackedWithData then
			AurasFound[trackedWithData] = true
			AuraData[trackedWithData].value = value
			AuraData[trackedWithData].expires = expires
			AuraData[trackedWithData].duration = duration
			AuraData[trackedWithData].count = count

        elseif tracked then
            AurasFound[tracked] = true
            if value then
                OtherShields[tracked] = 
					(OtherShields[tracked] or 0) + value
			elseif self.db.profile.debug == true then
                self:Print(errorReadingFmt:format(SpellNames[tracked]))
            end

		elseif spellId == SpellIds["Resolve"] then
			AurasFound["Resolve"] = true
			if value ~= addon.resolveInt or value2 ~= addon.resolveDmg or 
				value3 ~= addon.resolveDmg2 then
				addon.resolveInt = value or 0
				addon.resolveDmg = value2 or 0
				addon.resolveDmg2 = value3 or 0
				self:UpdateResolve()
			end
			--addon:UpdateLDBData()

		elseif spellId == SpellIds["Vengeance"] then
			AurasFound["Vengeance"] = true
			DataFeed.vengeance = value or 0
			addon:UpdateLDBData()

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
            luckOfTheDrawAmt = addon.LUCK_OF_THE_DRAW_MOD * count

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
					self:Print("Purgatory! ["..tostring(value or 0).."]")
				end
				PurgatoryActive = true
			end

			PurgatoryAbsorb = value or 0
		end

        i = i + 1
    until name == nil

	if AurasFound["Resolve"] then
		if self.resolvebar.db.enabled then
			local fmt = "%.1f%%"
			self.resolvebar:SetValue(fmt:format(addon.resolve*100))
			self.resolvebar.bar:Show()
		end
	else
		self.resolvebar.bar:Hide()
	end

	if not AurasFound["Vengeance"] then
		if DataFeed.vengeance > 0 then
			DataFeed.vengeance = 0
			addon:UpdateLDBData()
		end
	end

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
			self.pwsbar.bar:Hide()
		end

		PreviousShieldValues["PWSBar"] = shields
    end

    if self.illumbar.db.enabled and addon.IsBloodTank then
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
			self.absorbsbar.bar:Hide()
		end

		PreviousShieldValues["TotalAbsorbsBar"] = shields
	end

    if self.estimatebar.db.enabled and 
		self.estimatebar.db.show_stacks and addon.IsBloodTank then
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
			bcBar.bar:Hide()
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
			--bar.bar:Hide()

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
					bar.bar:SetValue(select(2, bar.bar:GetMinMaxValues()))
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
					bar.bar:SetValue(select(2, bar.bar:GetMinMaxValues()))
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
			bar.bar:Hide()
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
	                -- Blood Shield refreshed
	                if self.db.profile.debug == true then
	                    self:Print("AURA: Blood Shield refreshed. "..data.value
	                        .." ["..(data.value - BSAuraValue).."]")
	                end
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
            if self.db.profile.debug == true then
                self:Print("AURA: Blood Shield removed. "..BSAuraValue)
            end
            self:BloodShieldUpdated("removed", GetTime(), BSAuraValue, 0)
        end
        BSAuraPresent = false
        BSAuraValue = 0

		local bar = self.shieldbar.bar
		bar.active = false
		bar.timer = 0
		bar:SetScript("OnUpdate", nil)
		bar:Hide()
    end

	addon:FireCallback("Auras")
end
