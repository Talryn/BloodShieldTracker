local _G = getfenv(0)
local ADDON_NAME, addon = ...

local string = _G.string
local table = _G.table
local math = _G.math
local pairs = _G.pairs
local ipairs = _G.ipairs
local select = _G.select

local BloodShieldTracker = _G.LibStub("AceAddon-3.0"):NewAddon(addon.addonNameCondensed, 
	"AceConsole-3.0", "AceEvent-3.0","AceTimer-3.0")
local BST = BloodShieldTracker
addon.BloodShieldTracker = BloodShieldTracker

local L = _G.LibStub("AceLocale-3.0"):GetLocale(addon.addonNameCondensed, true)
local LDB = _G.LibStub("LibDataBroker-1.1")
local LibQTip = _G.LibStub("LibQTip-1.0")
local icon = _G.LibStub("LibDBIcon-1.0")
local LSM = _G.LibStub:GetLibrary("LibSharedMedia-3.0")
local AGU = _G.LibStub("AceGUI-3.0")

addon.DEBUG_OUTPUT = false
addon.DEBUG_BUFFER = ""

-- Make Print accessible to other parts of the addon.
addon.Print = function(self, ...) return BloodShieldTracker:Print(...) end

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

-- Local versions of WoW API calls.
local UnitAura = _G.UnitAura
local GetTime = _G.GetTime
local UnitHealthMax = _G.UnitHealthMax
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitAttackPower = _G.UnitAttackPower
local GetMasteryEffect = _G.GetMasteryEffect
local GetVersatilityBonus = _G.GetVersatilityBonus
local GetCombatRatingBonus = _G.GetCombatRatingBonus
local GetSpellCooldown = _G.GetSpellCooldown

-- Use BfA+ version to search by name.
local UnitBuff = addon.UnitBuff
local UnitDebuff = addon.UnitDebuff

BloodShieldTracker.loaded = false
addon.playerName = UnitName("player")
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
	["Anti-Magic Shell"] = 48707,
	["Bone Shield"] = 195181,
	["Bone Wall"] = 144948,
	["Heart Strike"] = 55050,
	["Death Coil"] = 47541,
	["Rune Strike"] = 56815,
	["Blood Boil"] = 48721,
	["Sacred Shield"] = 65148,
	["Marrowrend"] = 195182,
	["Protection of Tyr"] = 200430,
	["Lana'thel's Lament"] = 212974,
	["Divine Hymn"] = 64844,
	["Haemostasis"] = 235559,
	["Hemostasis"] = 273947,  -- Blood talent from BfA, passive buff
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

function addon.HasActiveTalent(talent)
	local activeGroup = _G.GetActiveSpecGroup()
	local talentId = addon.Talents[talent]
	if not talentId or not activeGroup then return false end
	local id, name, iconTexture, selected, available, _, _, _, _, active = 
		_G.GetTalentInfoByID(talentId, activeGroup)
	return name and active
end

local AbsorbShieldsOrdered = {
	"Blood Shield",
	"Power Word: Shield",
	"Clarity of Will",
	--"Divine Aegis",
	"Life Cocoon",
	--"Spirit Shell",
	--"Guard",
	--"Saved by the Light",
	--"Sacred Shield",
	"Anti-Magic Shell",
	--"Indomitable Pride",
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
		debugdmg = false,
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
			    progress = "Time",
			    show_time = false,
			    time_pos = "RIGHT",
				color = {r = 0.03, g = 0.54, b = 0.03, a = 1},
				bgcolor = {r = 0.02, g = 0.4, b = 0.01, a = 0.7},
				x = -90,
				y = -90,
			},
			["TargetSwingTimerBar"] = {
				enabled = false,
				color = { r = 0.7, g = 0.7, b = 0.7, a = 1.0 },
				bgcolor = { r = 0.2, g = 0.2, b = 0.2, a = 1.0 },
				userPlaced = true,
				x = 0,
				y = -30,
				width = 100,
				height = 15,
				numericTimer = true,
				specs = {
					["Blood"] = true,
					["Frost"] = false,
					["Unholy"] = false,
				},
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
			elseif cmds[2] and cmds[2] == "dmg" then
				if cmds[3] and cmds[3] == "on" then
					self.db.profile.debugdmg = true
					self:Print("Debugging: damage on.")
				elseif cmds[3] and cmds[3] == "off" then
					self.db.profile.debugdmg = false
					self:Print("Debugging: damage off.")
				else
					self:Print("Debugging: damage is "..(self.db.profile.debugdmg and "on." or "off."))
				end
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

function addon.IsFrame(frame)
	if frame and _G.type(frame) == "string" then
		local f = _G.GetClickFrame(frame)
		if f and _G.type(f) == "table" and f.SetPoint and f.GetName then
			return true
		end
	end
	return false
end

function addon.SetPointWithAnchor(self)
	local anchorFrame = addon.FrameNames[self.db.anchorFrame]
	if not anchorFrame and self.db.anchorFrame == "Custom" then
		anchorFrame = self.db.anchorFrameCustom
	end

	self.anchorTries = self.anchorTries or 0
	self.bar:ClearAllPoints()

	local isFrame = addon.IsFrame(anchorFrame)
	if anchorFrame and isFrame then
		if addon.db.profile.debug then
			addon:Print("Found anchor for bar '".._G.tostring(self.name).."'.")
		end
		self.bar:SetPoint(
			self.db.anchorPt, anchorFrame, self.db.anchorFramePt, 
			self.db.anchorX, self.db.anchorY)
		self.anchorTries = 0
	else
		self.bar:SetPoint("CENTER", _G.UIParent, "CENTER", self.db.x, self.db.y)
		if anchorFrame and not isFrame and self.anchorTries < 13 then
			if addon.db.profile.debug then
				addon:Print("Waiting for anchor for bar '".._G.tostring(self.name).."'.")
			end
	    	_G.C_Timer.After(5, function()
				self:SetPoint()
			end)
			self.anchorTries = (self.anchorTries or 0) + 1
		else
			self.anchorTries = 0
		end
	end
end

function addon.SetSecondaryValuePoint(self)
	self.bar.secondaryValue:SetPoint(self.db.time_pos or "RIGHT")
	self.bar.secondaryValue:SetJustifyH(self.db.time_pos or "RIGHT")
end

function BloodShieldTracker:CreateDisplay()
	-- Create the bars
	self.shieldbar = Bar:Create({
		name = "ShieldBar",
		friendlyName = "Shield Bar",
		initTimer = true,
		disableAnchor = true,
		hasSecondaryValue = true,
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
			SetSecondaryValuePoint = addon.SetSecondaryValuePoint,
			IsEnabled = function(self)
				return addon.IsBloodTank and self.db.enabled and hasBloodShield
			end,
			OnTalentUpdate = function(self)
				if self.IsEnabled and self:IsEnabled() then
					self.active = true
					addon:BarDisplayAdd("PlayerAura", self)
					self:UpdateBarConfig()
					self:UpdateDisplay()
				else
					self.active = false
					addon:BarDisplayRemove("PlayerAura", self)
					self:Hide()
				end
			end,
			UpdateDisplay = function(self)
				if self.active then
					local name, icon, count, dispelType, duration, expires, 
					caster, isStealable, shouldConsolidate, spellId, canApplyAura, 
					isBossDebuff, castByPlayer, new1, new2, value1 
						= UnitBuff("player", SpellNames["Blood Shield"])
					if name then
						local timeLeft = expires - GetTime()
						self.bar.timer = timeLeft
						self.bar.active = true 
						if value1 ~= self.bar.value1 then
							self.bar.value:SetText(addon.FormatNumber(value1))
						end
						self.bar.value1 = value1
						self.bar:SetMinMaxValues(0, duration)
						self.bar:SetAlpha(1)
						self.bar.value:Show()
						self.bar:Show()
						self.bar:SetScript("OnUpdate", self.OnUpdate)
					else
						self.bar.active = false 
						self.bar.timer = 0
						self.bar:SetScript("OnUpdate", nil)
						self.bar:Hide()
					end
				else
					self.bar:Hide()
				end
			end,
			UpdateBarConfig = function(self)
				if self.db.show_time then
					self.bar.secondaryValue:Show()
				else
					self.bar.secondaryValue:Hide()
				end
				self:SetSecondaryValuePoint()
			end,
			OnUpdate = function(self, elapsed)
				self.lastUpdate = (self.lastUpdate or 0) + elapsed
				self.timer = self.timer - elapsed
				if self.lastUpdate >= 0.1 then
					if self.active then
						local profile = self.parent.db
						if self.timer < 0 then
							self.timer = 0
							self.active = false
							self:SetScript("OnUpdate", nil)
							self:Hide()
						else
							if profile.show_time then
								self.secondaryValue:SetText(tostring(round(self.timer)))
							end
							self:SetValue(self.timer)
							self:Show()
						end
					else
						self:Hide()
					end
					self.lastUpdate = 0
				end
			end,
		},
	})

	self.pwsbar = Bar:Create({
		name = "PWSBar",
		friendlyName = "PW:S Bar",
		initTimer = true,
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
			IsEnabled = function(self)
				return addon.IsBloodTank and self.db.enabled
			end,
			OnTalentUpdate = function(self)
				if self.IsEnabled and self:IsEnabled() then
					self.active = true
					addon:BarDisplayAdd("PlayerAura", self)
					self:UpdateBarConfig()
					self:UpdateDisplay()
				else
					self.active = false
					addon:BarDisplayRemove("PlayerAura", self)
					self:Hide()
				end
			end,
			UpdateDisplay = function(self)
				if self.active then
					local shields = 0
					local OtherShields = addon.OtherShields
					local included = self.db.included
					for k,v in pairs(included) do
						if v then
							shields = shields + (OtherShields[k] or 0)
						end
					end
					if shields > 0 then
						if shields ~= self.shields then
							self.bar.value:SetText(addon.FormatNumber(shields))
						end
						self.bar:Show()
					else
						self.bar:Hide()
					end
					self.shields = shields
				else
					self.bar:Hide()
				end
			end,
			UpdateBarConfig = function(self)
			end,
		},
	})

	self.absorbsbar = Bar:Create({
		name = "TotalAbsorbsBar",
		friendlyName = "Total Absorbs Bar",
		initTimer = true,
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
			IsEnabled = function(self)
				return addon.IsBloodTank and self.db.enabled
			end,
			OnTalentUpdate = function(self)
				if self.IsEnabled and self:IsEnabled() then
					self.active = true
					addon:BarDisplayAdd("PlayerAura", self)
					self:UpdateBarConfig()
					self:UpdateDisplay()
				else
					self.active = false
					addon:BarDisplayRemove("PlayerAura", self)
					self:Hide()
				end
			end,
			UpdateDisplay = function(self)
				if self.active then
					local shields = 0
					local OtherShields = addon.OtherShields
					local tracked = self.db.tracked
					if tracked ~= "All" then
						local included = self.db.included
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
						if shields ~= self.shields then
							self.bar.value:SetText(addon.FormatNumber(shields))
						end
						self.bar:Show()
					else
						self.bar:Hide()
					end
					self.shields = shields
				else
					self.bar:Hide()
				end
			end,
			UpdateBarConfig = function(self)
			end,
		},
	})

	self.purgatorybar = Bar:Create({
		name = "PurgatoryBar",
		friendlyName = "Purgatory Bar",
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
			IsEnabled = function(self)
				return addon:IsTrackerEnabled() and self.db.enabled and 
					addon.HasActiveTalent("Purgatory")
			end,
			OnTalentUpdate = function(self)
				if self.IsEnabled and self:IsEnabled() then
					self.active = true
					addon:BarDisplayAdd("PlayerAura", self)
					self:UpdateBarConfig()
					self:UpdateDisplay()
				else
					self.active = false
					addon:BarDisplayRemove("PlayerAura", self)
					self:Hide()
				end
			end,
			UpdateDisplay = function(self)
				if self.active then
					local name, icon, count, dispelType, duration, expires, 
					caster, isStealable, shouldConsolidate, spellId, canApplyAura, 
					isBossDebuff, castByPlayer, new1, new2, value1 
						= UnitDebuff("player", SpellNames["Shroud of Purgatory"])
					if name then
						--local timeLeft = expires - GetTime()
						--self.bar.timer = timeLeft
						--self.bar.active = true 
						if value1 ~= self.bar.value1 then
							self.bar.value:SetText(addon.FormatNumber(value1))
						end
						self.bar.value1 = value1
						--self.bar:SetMinMaxValues(0, duration)
						self.bar:SetAlpha(1)
						self.bar.value:Show()
						self.bar:Show()
						--self.bar:SetScript("OnUpdate", self.OnUpdate)
					else
						self.bar.active = false 
						--self.bar.timer = 0
						--self.bar:SetScript("OnUpdate", nil)
						self.bar:Hide()
					end
				else
					self.bar:Hide()
				end
			end,
			UpdateBarConfig = function(self)
			end,
		},
	})

	self.boneshieldbar = Bar:Create({
		name = "BoneShieldBar",
		friendlyName = "Bone Shield Bar",
		initTimer = true,
		disableAnchor = true,
		hasSecondaryValue = true,
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
			SetSecondaryValuePoint = addon.SetSecondaryValuePoint,
			IsEnabled = function(self)
				return addon.currentSpec == "Blood" and self.db.enabled and 
					_G.IsSpellKnown(SpellIds["Marrowrend"])
			end,
			OnTalentUpdate = function(self)
				if self.IsEnabled and self:IsEnabled() then
					self.active = true
					addon:BarDisplayAdd("PlayerAura", self)
					self:UpdateBarConfig()
					self:UpdateDisplay()
				else
					self.active = false
					addon:BarDisplayRemove("PlayerAura", self)
					self:Hide()
				end
			end,
			UpdateDisplay = function(self)
				if self.active then
					local name, icon, count, dispelType, duration, expires, 
					caster, isStealable, shouldConsolidate, spellId, canApplyAura, 
					isBossDebuff, castByPlayer, new1, new2, value1 
						= UnitBuff("player", SpellNames["Bone Shield"])
					if name then
						local timeLeft = expires - GetTime()
						self.bar.timer = timeLeft
						self.bar.active = true 
						if count ~= self.bar.count then
							self.bar.value:SetText(tostring(count))
						end
						self.bar.count = count

						if self.db.progress == "Time" then
							self.bar:SetMinMaxValues(0, duration)
						elseif self.db.progress == "Charges" then
							self.bar:SetMinMaxValues(0, addon.MAX_BONESHIELD_CHARGES)
						else
							self.bar:SetMinMaxValues(0, 1)
							self.bar:SetValue(1)
						end
						self.bar:SetAlpha(1)
						self.bar.value:Show()
						self.bar:Show()
						self.bar:SetScript("OnUpdate", self.OnUpdate)
					else
						self.bar.active = false 
						self.bar.timer = 0
						self.bar:SetScript("OnUpdate", nil)
						self.bar:Hide()
					end
				else
					self.bar:Hide()
				end
			end,
			UpdateBarConfig = function(self)
				if self.db.progress == "Time" then
					self.bar:SetMinMaxValues(0, 1)
				elseif self.db.progress == "Charges" then
					self.bar:SetMinMaxValues(0, addon.MAX_BONESHIELD_CHARGES)
				elseif self.db.progress == "None" then
					self.bar:SetMinMaxValues(0, 1)
					self.bar:SetValue(1)
				end
				if self.db.show_time then
					self.bar.secondaryValue:Show()
				else
					self.bar.secondaryValue:Hide()
				end
				self:SetSecondaryValuePoint()
			end,
			OnUpdate = function(self, elapsed)
				self.lastUpdate = (self.lastUpdate or 0) + elapsed
				self.timer = self.timer - elapsed
				if self.lastUpdate >= 0.1 then
					if self.active then
						local profile = self.parent.db
						if self.timer > 0 then
							if profile.show_time then
								self.secondaryValue:SetText(tostring(round(self.timer)))
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
					else
						self:Hide()
					end
					self.lastUpdate = 0
				end
			end
		},
	})

	self.amsbar = Bar:Create({
		name = "AMSBar",
		friendlyName = "Anti-Magic Shell Bar",
		initTimer = true,
		disableAnchor = true,
		hasSecondaryValue = true,
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
			SetSecondaryValuePoint = addon.SetSecondaryValuePoint,
			IsEnabled = function(self)
				return addon:IsTrackerEnabled() and self.db.enabled and 
					_G.IsSpellKnown(SpellIds["Anti-Magic Shell"])
			end,
			OnTalentUpdate = function(self)
				if self.IsEnabled and self:IsEnabled() then
					self.active = true
					addon:BarDisplayAdd("PlayerAura", self)
					self:UpdateBarConfig()
					self:UpdateDisplay()
				else
					self.active = false
					addon:BarDisplayRemove("PlayerAura", self)
					self:Hide()
				end
			end,
			UpdateDisplay = function(self)
				if self.active then
					local name, icon, count, dispelType, duration, expires, 
					caster, isStealable, shouldConsolidate, spellId, canApplyAura, 
					isBossDebuff, castByPlayer, new1, new2, value1 
						= UnitBuff("player", SpellNames["Anti-Magic Shell"])
					if name then
						local timeLeft = expires - GetTime()
						self.bar.timer = timeLeft
						self.bar.active = true 
						if value1 ~= self.bar.value1 then
							self.bar.value:SetText(addon.FormatNumber(value1))
						end
						self.bar.value1 = value1
						self.bar:SetMinMaxValues(0, duration)
						self.bar:SetAlpha(1)
						self.bar.value:Show()
						self.bar:Show()
						self.bar:SetScript("OnUpdate", self.OnUpdate)
					else
						self.bar.active = false 
						self.bar.timer = 0
						self.bar:SetScript("OnUpdate", nil)
						self.bar:Hide()
					end
				else
					self.bar:Hide()
				end
			end,
			UpdateBarConfig = function(self)
				if self.db.show_time then
					self.bar.secondaryValue:Show()
				else
					self.bar.secondaryValue:Hide()
				end
				self:SetSecondaryValuePoint()
			end,
			OnUpdate = function(self, elapsed)
				self.lastUpdate = (self.lastUpdate or 0) + elapsed
				self.timer = self.timer - elapsed
				if self.lastUpdate >= 0.1 then
					if self.active then
						local profile = self.parent.db
						if self.timer < 0 then
							self.timer = 0
							self.active = false
							self:SetScript("OnUpdate", nil)
							self:Hide()
						else
							if profile.show_time then
								self.secondaryValue:SetText(tostring(round(self.timer)))
							end
							self:SetValue(self.timer)
							self:Show()
						end
					else
						self:Hide()
					end
					self.lastUpdate = 0
				end
			end,
		},
	})

end

function BloodShieldTracker:OnInitialize()
	self:CheckClass()
	if not addon.isDK then return end

  	-- Load the settings
  	self.db = _G.LibStub("AceDB-3.0"):New(
		"BloodShieldTrackerDB", addon.defaults, "Default")
	addon.db = self.db

	-- Migrate the settings
	self:MigrateSettings()

	addon.DEBUG_OUTPUT = self.db.profile.debug

	-- Set the number format
	addon:SetNumberFormat(self.db.profile.numberFormat)

    -- Set the precision
	addon:SetNumberPrecision()

	self:CreateDisplay()

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
	addon.db = self.db
	-- Reset positions
	for name,bar in pairs(addon.bars) do
		bar.db = self.db.profile.bars[bar.name]
		bar:Reset()
	end

	self:ResetFonts()
	self:ResetStats()
	addon:FireCallback("ProfileUpdate")
end

function addon:GetFontFlags()
    local flags = {}
    if addon.db.profile.font_outline then
        tinsert(flags, "OUTLINE")
    end
    if addon.db.profile.font_monochrome then
        tinsert(flags, "MONOCHROME")
    end
    if addon.db.profile.font_thickoutline then
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
	    ff = LSM:Fetch("font", addon.db.profile.font_face)
    end
    if CustomUI.fontSize then
        fh = CustomUI.fontSize
    else
        fh = addon.db.profile.font_size
    end
    if CustomUI.fontFlags then
        fontFlags = CustomUI.fontFlags
    else
        fontFlags = addon:GetFontFlags()
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
				for name, bar in pairs(addon.bars) do
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
				for name, bar in pairs(addon.bars) do
					bar.bar:CreateBackdrop()
				end
            end
        else
            self:Print("Could not find the ElvUI config.")
        end
    end
end

function addon.SkinFrame(frame)
	local skinning = addon.db.profile.skinning
	local tukui = Tukui and skinning.tukui.enabled and skinning.tukui.borders
	local elvui = ElvUI and skinning.elvui.enabled and skinning.elvui.borders
	if (tukui or elvui) and frame.CreateBackdrop then
		frame:CreateBackdrop()
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
	for name, bar in pairs(addon.bars) do
		bar:ResetFonts()
	end
end

function BloodShieldTracker:UpdateTextures()
	for name, bar in pairs(addon.bars) do
		bar:UpdateTexture()
	end
end

function BloodShieldTracker:UpdateBorders()
	for name, bar in pairs(addon.bars) do
		bar:UpdateBorder()
	end
end

function BloodShieldTracker:UpdatePositions()
	for name, bar in pairs(addon.bars) do
		if bar.SetPoint then
			bar:SetPoint()
		end
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
	if not addon.isDK then return end

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

	for k, v in pairs(addon.bars) do
		if v then
			v.bar:Hide()
		end
	end
end

function BloodShieldTracker:OnDisable()
end

function addon:UpdateBarsForTalents()
	for name, bar in pairs(addon.bars) do
		if bar and bar.OnTalentUpdate and type(bar.OnTalentUpdate) == "function" then
			bar:OnTalentUpdate()
		end
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
	addon:FireCallback("WeaponUpdate")
	addon:FireCallback("TalentUpdate")
	addon:UpdateBarsForTalents()

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
			if id == 250 then
				addon.currentSpec = "Blood"
			elseif id == 251 then
				addon.currentSpec = "Frost"
			elseif id == 252 then
				addon.currentSpec = "Unholy"
			else
				if addon.db.profile.debug then
					local fmt = "Could not detect player spec. [%s,%s,%s,%s]"
					self:Print(fmt:format(_G.tostring(activeSpecNum), _G.tostring(id), 
						_G.tostring(name), _G.tostring(texture)))
				end
				addon.currentSpec = addon.currentSpec or "Blood"
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
		addon.Talents = addon.TalentsBySpec[addon.currentSpec] or {}
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
	if slot == _G.INVSLOT_MAINHAND then
		addon:FireCallback("WeaponUpdate")
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

	addon:FireCallback("CombatStart")
	addon:BarDisplayUpdateForEvent("CombatStart")
end

function BloodShieldTracker:PLAYER_REGEN_ENABLED()
	LastFightStats:EndCombat()
	addon:FireCallback("CombatEnd")
	addon:BarDisplayUpdateForEvent("CombatEnd")
end

function BloodShieldTracker:PLAYER_ENTERING_WORLD()
	self:CheckAuras()
end

function BloodShieldTracker:PLAYER_ALIVE()
	self:CheckAuras()
	addon:FireCallback("PlayerAlive")
end

function BloodShieldTracker:PLAYER_DEAD()
	self:CheckAuras()
	addon:FireCallback("PlayerDead")
end

function BloodShieldTracker:COMBAT_LOG_EVENT_UNFILTERED(...)
	local event, timestamp, eventtype, hideCaster, 
		srcGUID, srcName, srcFlags, srcRaidFlags, 
		destGUID, destName, destFlags, destRaidFlags, 
		param9, param10, param11, param12, param13, param14, 
		param15, param16, param17, param18, param19, param20

	timestamp, eventtype, hideCaster, 
	srcGUID, srcName, srcFlags, srcRaidFlags,
	destGUID, destName, destFlags, destRaidFlags,
	param9, param10, param11, param12, param13, param14, 
	param15, param16, param17, param18, param19, param20 = CombatLogGetCurrentEventInfo()
	event = "COMBAT_LOG_EVENT_UNFILTERED"

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
    --self:ShowShieldBar()

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
			--self.shieldbar.bar:Hide()
			self:UpdateStatsRemoveShield()
			self.shieldbar.shield_max = 0
			self.shieldbar.shield_curr = 0

			if self.shieldbar.db.sound_enabled and self.shieldbar.db.sound_removed then
				_G.PlaySoundFile(LSM:Fetch("sound", self.shieldbar.db.sound_removed))
			end
		end
	end

function BloodShieldTracker:ResetStats()
    TotalShieldStats:Reset()
    LastFightStats:Reset()
end

function BloodShieldTracker:UNIT_AURA(event, unit, ...)
	if unit == "player" then
		self:CheckAuras(unit)
		addon:BarDisplayUpdateForEvent("PlayerAura")
	end
end

-- Define auras which require extra data.  Boolean indicates if an absorb.
local TrackWithDataNames = {
	["Blood Shield"] = true,
--	["Bone Shield"] = false,
	["Anti-Magic Shell"] = true,
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
addon.OtherShields = OtherShields

local errorReadingFmt = "Error reading the %s value."
function BloodShieldTracker:CheckAuras(unit)
	local name, icon, count, dispelType, duration, expires,
		caster, stealable, consolidate, spellId, canApplyAura, isBossDebuff,
		castByPlayer, value, value2, value3
	
	-- Reset variables
	wipe(AurasFound)
	wipe(OtherShields)

	local Results

	-- Loop through unit auras to find ones of interest.
	local i = 1
	repeat
		name, icon, count, dispelType, duration, expires, caster, 
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
		bar.parent:Hide()
	end

	addon:FireCallback("Auras")
end
