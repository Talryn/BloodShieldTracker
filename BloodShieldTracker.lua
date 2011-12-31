local BloodShieldTracker = LibStub("AceAddon-3.0"):NewAddon("BloodShieldTracker", "AceConsole-3.0", "AceEvent-3.0","AceTimer-3.0")

local ADDON_NAME = ...
local ADDON_VERSION = "@project-version@"

local DEBUG_OUTPUT = false
local DEBUG_BUFFER = ""

local AGU = LibStub("AceGUI-3.0")

-- Local versions for performance
local tinsert, tremove, tgetn = table.insert, table.remove, table.getn
local tconcat = table.concat
local pairs, ipairs = pairs, ipairs
local floor, ceil = math.floor, math.ceil

BloodShieldTracker.playerName = UnitName("player")
BloodShieldTracker.statusbar = nil
BloodShieldTracker.damagebar = nil
BloodShieldTracker.pwsbar = nil
BloodShieldTracker.illumbar = nil

local isDK = nil
local IsBloodTank = false
local hasBloodShield = false

-- Create the frame used to get the BS tooltip text
local TipFrame = CreateFrame("GameTooltip", "BST_Tooltip", nil, "GameTooltipTemplate")
TipFrame:SetOwner(UIParent, "ANCHOR_NONE")

-- Keep track of time.  Start with current client time
-- but will use the combat log timestamps after that.
local currentTime = time()

local updateTimer = nil
local lastSeconds = 5
local damageTaken = {}
local removeList = {}

-- Define a simplistic class for shield statistics
ShieldStats = {}
ShieldStats.__index = ShieldStats

function ShieldStats:new()
    local stats = {}
    setmetatable(stats, ShieldStats)
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
TotalShieldStats = ShieldStats:new()

-- Last fight stats
LastFightStats = ShieldStats:new()

local lastDSSuccess = nil
local masteryRating = 0

local GREEN = "|cff00ff00"
local YELLOW = "|cffffff00"
local BLUE = "|cff0198e1"
local ORANGE = "|cffff9933"
local statusBarFormatFull = "%s/%s (%d%%)"
local statusBarFormatNoPer = "%s/%s"

local healBarFormat = "%s: %d"
local healBarNoTextFormat = "%d"

local L = LibStub("AceLocale-3.0"):GetLocale("BloodShieldTracker", true)
local LDB = LibStub("LibDataBroker-1.1")
local LibQTip = LibStub("LibQTip-1.0")
local icon = LibStub("LibDBIcon-1.0")
-- Load LibsharedMedia we package it with the addon so it should be available
local LSM = LibStub:GetLibrary("LibSharedMedia-3.0")

local CURRENT_BUILD, CURRENT_INTERNAL, 
    CURRENT_BUILD_DATE, CURRENT_UI_VERSION = GetBuildInfo()

local DS_SPELL_DMG = (GetSpellInfo(49998))
local DS_SPELL_HEAL = (GetSpellInfo(45470))
local BS_SPELL_ID = 77535
local BS_SPELL = (GetSpellInfo(BS_SPELL_ID))
local IMP_DS_TALENT = (GetSpellInfo(81138))
local DARK_SUCCOR_GLYPH_ID = 96279
-- New buff for 4.2
local DARK_SUCCOR_BUFF_ID = 101568
local DARK_SUCCOR_BUFF_NAME = (GetSpellInfo(DARK_SUCCOR_BUFF_ID))
local DarkSuccorBuff = false
local ImpDSModifier = 1
local HasVampTalent = false
local HasSuccorGlyphed = false
-- The duration of Blood Shield
local BS_DURATION = 10
-- This should be the percent of the DS Heal from the tooltip.
local dsHealModifier = 0.20
-- This should be the percent of max health a minimum DS heal will be.
local dsMinHealPercent = 0.07
-- The minimum DS heal with the Dark Succor Glyph
local dsMinHealPercentSuccor = 0.20
-- The minimum DS heal with the Dark Succor Glyph in 4.1
local dsMinHealPercentSuccor41 = 0.15
-- The actual minimum DS heal percent. Determined based on spec, glyphs, and presence.
local actualDsMinHeal = dsMinHealPercent
local shieldPerMasteryPoint = 6.25
local maxHealth = 0
local dsHealMin = 0

-- Other Shields
local PWS_SPELL_ID = 17
local PWS_SPELL = (GetSpellInfo(PWS_SPELL_ID)) or "Power Word: Shield"
local OtherShields = {}
local ILLUMINATED_HEALING_BUFF_ID = 86273
local ILLUMINATED_HEALING_BUFF = (GetSpellInfo(ILLUMINATED_HEALING_BUFF_ID)) or "Illuminated Healing"

local CurrentPresence = nil
local BLOOD_PRESENCE_BUFF_ID = 48263
local UNHOLY_PRESENCE_BUFF_ID = 48265
local FROST_PRESENCE_BUFF_ID = 48266
local BLOOD_PRESENCE_BUFF = (GetSpellInfo(BLOOD_PRESENCE_BUFF_ID))
local UNHOLY_PRESENCE_BUFF = (GetSpellInfo(UNHOLY_PRESENCE_BUFF_ID))
local FROST_PRESENCE_BUFF = (GetSpellInfo(FROST_PRESENCE_BUFF_ID))

local LUCK_OF_THE_DRAW_BUFF_ID = 72221
local LUCK_OF_THE_DRAW_BUFF = (GetSpellInfo(LUCK_OF_THE_DRAW_BUFF_ID))
local LUCK_OF_THE_DRAW_MOD = 0.05
local luckOfTheDrawBuff = false
local luckOfTheDrawAmt = 0

local SPIRIT_LINK_SPELL = (GetSpellInfo(98017))
local SPIRIT_LINK_TOTEM = (GetSpellInfo(98007))

local HELLSCREAM_BUFF_05 = 73816
local HELLSCREAM_BUFF_10 = 73818
local HELLSCREAM_BUFF_15 = 73819
local HELLSCREAM_BUFF_20 = 73820
local HELLSCREAM_BUFF_25 = 73821
local HELLSCREAM_BUFF_30 = 73822
local hellscreamBuffs = {
    [HELLSCREAM_BUFF_05] = 0.05,
    [HELLSCREAM_BUFF_10] = 0.10,
    [HELLSCREAM_BUFF_15] = 0.15,
    [HELLSCREAM_BUFF_20] = 0.20,
    [HELLSCREAM_BUFF_25] = 0.25,
    [HELLSCREAM_BUFF_30] = 0.30,    
}
local HELLSCREAM_BUFF = (GetSpellInfo(HELLSCREAM_BUFF_30))
local WRYNN_BUFF_05 = 73816
local WRYNN_BUFF_10 = 73818
local WRYNN_BUFF_15 = 73819
local WRYNN_BUFF_20 = 73820
local WRYNN_BUFF_25 = 73821
local WRYNN_BUFF_30 = 73822
local wrynnBuffs = {
    [WRYNN_BUFF_05] = 0.05,
    [WRYNN_BUFF_10] = 0.10,
    [WRYNN_BUFF_15] = 0.15,
    [WRYNN_BUFF_20] = 0.20,
    [WRYNN_BUFF_25] = 0.25,
    [WRYNN_BUFF_30] = 0.30,    
}
local WRYNN_BUFF = (GetSpellInfo(WRYNN_BUFF_30))
local VB_BUFF_ID = 55233
local VB_BUFF = (GetSpellInfo(VB_BUFF_ID))
local VB_GLYPH_ID = 58676
local iccBuff = false
local iccBuffAmt = 0.0
local vbBuff = false
local vbGlyphed = false
local vbGlyphedHealthInc = 0.0
local vbGlyphedHealingInc = 0.4
local vbUnglyphedHealthInc = 0.15
local vbUnglyphedHealingInc = 0.25
local vbHealthInc = 0.0
local vbHealingInc = 0.0

local GUARDIAN_SPIRIT_BUFF_ID = 47788
local GUARDIAN_SPIRIT_BUFF = (GetSpellInfo(GUARDIAN_SPIRIT_BUFF_ID))
local guardianSpiritHealBuff = 0.40
local gsHealModifier = 0.0

local healingDebuffMultiplier = 1

local HEALING_DEBUFFS = {
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

local healing_debuff_names = {}

local function round(number)
    if not number then return 0 end
    return ceil(number-0.5)
end

local Broker = CreateFrame("Frame")
Broker.obj = LDB:NewDataObject(GetAddOnMetadata(ADDON_NAME,"Title"), {
    type = "data source",
    icon = "Interface\\Icons\\Spell_DeathKnight_DeathStrike",
    label = GetAddOnMetadata(ADDON_NAME,"Title"),
    text = GetAddOnMetadata(ADDON_NAME,"Title"),
    barValue = 0,
    barR = 0,
    barG = 0,
    barB = 1,
	OnClick = function(clickedframe, button)
		if button == "RightButton" then
			local optionsFrame = InterfaceOptionsFrame

			if optionsFrame:IsVisible() then
				optionsFrame:Hide()
			else
				BloodShieldTracker:ShowOptions()
			end
		elseif button == "LeftButton" and IsShiftKeyDown() then
		    BloodShieldTracker:ResetStats()
        end
	end
} )

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

function AddStats(tooltip, stats)
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
            BloodShieldTracker:FormatNumber(stats.totalAbsorbs), 
            BloodShieldTracker:FormatNumber(stats.totalShields), shieldUsagePerc))
end

function Broker.obj:OnEnter()
	local tooltip = LibQTip:Acquire("BloodShieldTrackerTooltip", 2, "LEFT", "RIGHT")
	self.tooltip = tooltip 

    tooltip:AddHeader(addonHdr:format(GetAddOnMetadata(ADDON_NAME,"Title"), ADDON_VERSION))
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

local configMode = false

local defaults = {
    profile = {
		minimap = {
			hide = true,
		},
        verbose = false,
        enable_only_for_blood = true,
        shield_bar_progress = "Time",
        shield_bar_show_time = true,
        shield_bar_time_pos = "RIGHT",
        shield_sound_enabled = false,
        shield_applied_sound = "None",
        shield_removed_sound = "None",
        status_bar_enabled = true,
        shield_bar_text_format = "OnlyCurrent",
        damage_bar_enabled = true,
        hide_damage_bar_ooc = true,
		lock_status_bar = false,
		lock_damage_bar = false,
		damage_bar_width = 100,
		damage_bar_height = 15,
		status_bar_width = 150,
		status_bar_height = 15,
		font_size = 12,
		font_face = "Friz Quadrata TT",
		font_outline = true,
		font_monochrome = false,
		font_thickoutline = false,
		status_bar_color = {r = 1.0, g = 0.0, b = 0.0, a = 1},
		status_bar_textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
		status_bar_bgcolor = {r = 0.65, g = 0.0, b = 0.0, a = 0.8},
		estheal_bar_min_textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
		estheal_bar_min_color = {r = 1.0, g = 0.0, b = 0.0, a = 1},
		estheal_bar_min_bgcolor = {r = 0.65, g = 0.0, b = 0.0, a = 0.8},
		estheal_bar_opt_textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
		estheal_bar_opt_color = {r = 0.0, g = 1.0, b = 0.0, a = 1},
		estheal_bar_opt_bgcolor = {r = 0.0, g = 0.65, b = 0.0, a = 0.8},
		status_bar_texture = "Blizzard",
		estheal_bar_texture = "Blizzard",
		status_bar_border = true,
		estimate_bar_mode = "DS",
		estheal_bar_border = true,
		estheal_bar_shown = true,
		estheal_bar_show_text = true,
		status_bar_shown = true,
		est_heal_x = 0, est_heal_y = -40,
		shield_bar_x = 0, shield_bar_y = 0,
		estheal_bar_scale = 1,
		status_bar_scale = 1,
		useAuraForShield = true,
		latencyMethod = "None",
		latencyFixed = 0,
        -- Setting for the PW:S Bar
		pwsbar_enabled = false,
		pwsbar_color = {r = 1.0, g = 1.0, b = 1.0, a = 1},
		pwsbar_textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
		pwsbar_bgcolor = {r = 0.65, g = 0.65, b = 0.65, a = 0.8},
		pwsbar_texture = "Blizzard",
		pwsbar_border = true,
		pwsbar_shown = true,
		pwsbar_x = 0, pwsbar_y = 0,
		pwsbar_scale = 1,
		lock_pwsbar = false,
		pwsbar_width = 75,
		pwsbar_height = 15,
        -- Setting for the Illum. Heal Bar
		illumbar_enabled = false,
		illumbar_color = {r = 0.96, g = 0.55, b = 0.73, a = 1},
		illumbar_textcolor = {r = 1.0, g = 1.0, b = 1.0, a = 1},
		illumbar_bgcolor = {r = 0.96, g = 0.55, b = 0.73, a = 0.7},
		illumbar_texture = "Blizzard",
		illumbar_border = true,
		illumbar_shown = true,
		illumbar_x = 0, illumbar_y = 0,
		illumbar_scale = 1,
		lock_illum = false,
		illumbar_width = 75,
		illumbar_height = 15,
    }
}


local options

function BloodShieldTracker:ShowOptions()
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.ShieldBar)
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.Main)
end

function BloodShieldTracker:GetOptions()
    if not options then
        options = {
            type = "group",
            name = GetAddOnMetadata(ADDON_NAME, "Title"),
--			childGroups = "tree",
            args = {
				core = {
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
                                self:CheckImpDeathStrike()
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
                        useAuraForShield = {
                            name = L["Use Aura"],
        					order = 40,
                            desc = L["UseAura_OptionDesc"],
                            type = "toggle",
                            set = function(info, val) self.db.profile.useAuraForShield = val end,
                            get = function(info) return self.db.profile.useAuraForShield end,
                        },
        				config_mode = {
        					name = L["Config Mode"],
        					desc = L["Toggle config mode"],
        					type = "execute",
        					order = 50,
        					func = function()
        					    configMode = not configMode
        						if configMode then
        							self.statusbar:Show()
        							self.damagebar:Show()
        							self.pwsbar:Show()
        							self.illumbar:Show()
        						else
        							self.statusbar:Hide()
        							if self.damagebar.hideooc and not InCombatLockdown() then
        							    self.damagebar:Hide()
                                    end
                                    self.pwsbar:Hide()
                                    self.illumbar:Hide()
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
        			},
        		},
        		shieldBarOpts = {
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
        					    self.db.profile.status_bar_enabled = val
        					    if not val then
        						    BloodShieldTracker.statusbar:Hide()
        						end
        					end,
                            get = function(info) return self.db.profile.status_bar_enabled end,
        				},
        				lock_status_bar = {
        					name = L["Lock bar"],
        					desc = L["LockBarDesc"],
        					type = "toggle",
        					order = 20,
        					set = function(info, val)
        					    self.db.profile.lock_status_bar = val 
        						BloodShieldTracker:ShieldBarLock(val)
        					end,
                            get = function(info) return self.db.profile.lock_status_bar end,
        				},
        				shield_bar_text_format = {
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
        					    self.db.profile.shield_bar_text_format = val
        					end,
                            get = function(info)
                                return self.db.profile.shield_bar_text_format
                            end,
        				},
        				shield_bar_progress = {
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
        					    self.db.profile.shield_bar_progress = val
        					    if val == "Time" or val == "None" then
        					        self:UpdateShieldBarMode()
    					        end
        					end,
                            get = function(info)
                                return self.db.profile.shield_bar_progress
                            end,
        				},
                        timeRemaining = {
                            order = 100,
                            type = "header",
                            name = L["Time Remaining"],
                        },
        				shield_bar_show_time = {
        					name = L["Show Time"],
        					desc = L["ShowTime_OptionDesc"],
        					type = "toggle",
        					order = 110,
        					set = function(info, val)
        					    self.db.profile.shield_bar_show_time = val
        					    if val then
        					        self.statusbar.time:Show()
    					        else
    					            self.statusbar.time:Hide()
					            end
        					end,
                            get = function(info)
                                return self.db.profile.shield_bar_show_time
                            end,
        				},
        				shield_bar_time_pos = {
        					name = L["Position"],
        					desc = L["TimePosition_OptionDesc"],
        					type = "select",
        					values = {
        					    ["RIGHT"] = L["Right"],
        					    ["LEFT"] = L["Left"],
        					},
        					order = 120,
        					set = function(info, val)
        					    self.db.profile.shield_bar_time_pos = val
    					        self.statusbar.time:SetPoint(val or "RIGHT")
    					        self.statusbar.time:SetJustifyH(val or "RIGHT")
        					end,
                            get = function(info)
                                return self.db.profile.shield_bar_time_pos
                            end,
                            disabled = function()
                                return not self.db.profile.shield_bar_show_time
                            end,
        				},
                        sound = {
                            order = 200,
                            type = "header",
                            name = L["Sound"],
                        },
        				shield_sound_enabled = {
        					name = L["Enabled"],
        					desc = L["ShieldSoundEnabledDesc"],
        					type = "toggle",
        					order = 210,
        					set = function(info, val)
        					    self.db.profile.shield_sound_enabled = val
        					end,
                            get = function(info)
                                return self.db.profile.shield_sound_enabled
                            end,
        				},
        				shield_bar_applied_sound = {
        					order = 220,
        					name = L["Applied Sound"],
        					desc = L["AppliedSoundDesc"],
        					type = "select",
        					values = LSM:HashTable("sound"),
        					dialogControl = 'LSM30_Sound',
        					get = function()
        					    return self.db.profile.shield_applied_sound
        					end,
        					set = function(info, val)
        					    self.db.profile.shield_applied_sound = val
        					end,
        					disabled = function()
        					    return not self.db.profile.shield_sound_enabled
        					end,
        				},
        				shield_bar_removed_sound = {
        					order = 230,
        					name = L["Removed Sound"],
        					desc = L["RemovedSoundDesc"],
        					type = "select",
        					values = LSM:HashTable("sound"),
        					dialogControl = 'LSM30_Sound',
        					get = function()
        					    return self.db.profile.shield_removed_sound
        					end,
        					set = function(info, val)
        					    self.db.profile.shield_removed_sound = val
        					end,
        					disabled = function()
        					    return not self.db.profile.shield_sound_enabled
        					end,
        				},
                        dimensions = {
                            order = 300,
                            type = "header",
                            name = L["Dimensions"],
                        },
        				status_bar_width = {
        					order = 310,
        					name = L["Width"],
        					desc = L["BarWidth_Desc"],	
        					type = "range",
        					min = 50,
        					max = 300,
        					step = 1,
        					set = function(info, val)
        					    self.db.profile.status_bar_width = val 
        						self.statusbar:SetWidth(val)
        						self.statusbar.border:SetWidth(val+9)
        					end,
        					get = function(info, val)
        					    return self.db.profile.status_bar_width
        					end,
        				},
        				status_bar_height = {
        					order = 320,
        					name = L["Height"],
        					desc = L["BarHeight_Desc"],
        					type = "range",
        					min = 10,
        					max = 30,
        					step = 1,
        					set = function(info, val)
        					    self.db.profile.status_bar_height = val 
        						self.statusbar:SetHeight(val)
        						self.statusbar.border:SetHeight(val + 8)
        					end,
        					get = function(info, val)
        					    return self.db.profile.status_bar_height
        					end,					
        				},
        				status_bar_scaling = {
        					order = 330,
        					name = L["Scale"],
        					desc = L["ScaleDesc"],
        					type = "range",
        					min = 0.1,
        					max = 3,
        					step = 0.1,
        					get = function() return self.db.profile.status_bar_scale end,
        					set = function(info, val)
        					    self.db.profile.status_bar_scale = val
        					    self.statusbar:SetScale(val)
        					end
        				},
                        colors = {
                            order = 400,
                            type = "header",
                            name = L["Colors"],
                        },
        				status_bar_textcolor = {
        					order = 410,
        					name = L["Text Color"],
        					desc = L["BloodShieldBarTextColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.status_bar_textcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    self:UpdateShieldBarGraphics()
        					end,
        					get = function(info)
        				        local c = self.db.profile.status_bar_textcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				status_bar_color = {
        					order = 420,
        					name = L["Bar Color"],
        					desc = L["BloodShieldBarColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.status_bar_color
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    self:UpdateShieldBarGraphics()
        					end,
        					get = function(info)
        				        local c = self.db.profile.status_bar_color
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				status_bar_bgcolor = {
        					order = 430,
        					name = L["Bar Depleted Color"],
        					desc = L["BloodShieldDepletedBarColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.status_bar_bgcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    self:UpdateShieldBarGraphics()
        					end,
        					get = function(info)
        				        local c = self.db.profile.status_bar_bgcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
                        appearance = {
                            order = 500,
                            type = "header",
                            name = L["Appearance"],
                        },
        				status_bar_texture_opt = {
        					order = 510,
        					name = L["Texture"],
        					desc = L["BarTexture_OptionDesc"],
        					type = "select",
        					values = LSM:HashTable("statusbar"),
        					dialogControl = 'LSM30_Statusbar',
        					get = function()
        					    return self.db.profile.status_bar_texture
        					end,
        					set = function(info, val)
        					    self.db.profile.status_bar_texture = val
        					    self:UpdateShieldBarTexture()
        					end,
        					disabled = function()
        					    return not self.db.profile.status_bar_shown
        					end,
        				},
        				status_bar_border_visible_opt = {
        					order = 520,
        					name = L["ShowBorder"],
        					desc = L["ShowBorderDesc"],
        					type = "toggle",
        					get = function()
        					    return self.db.profile.status_bar_border
        					end,
        					set = function(info, val)
        					    self.db.profile.status_bar_border = val
        					    self:UpdateShieldBarBorder()
        					end,
        				},
        				status_bar_visible_opt = {
        					order = 530,
        					name = L["ShowBar"],
        					desc = L["ShowBarDesc"],
        					type = "toggle",
        					get = function() return self.db.profile.status_bar_shown end,
        					set = function(info,val) 
        				        self.db.profile.status_bar_shown = val
        				        self:UpdateShieldBarVisibility()
        				    end,
        				},
        			},
    			},
    			estHealBarOpts = {
    			    order = 3,
    			    type = "group",
    			    name = L["Estimated Healing Bar"],
    			    desc = L["Estimated Healing Bar"],
    			    args = {
        				-- Estimated Healing
					    description = {
					        order = 1,
					        type = "description",
					        name = L["EstimatedHealingBar_Desc"],
					    },
                        generalOptions = {
                            order = 2,
                            type = "header",
                            name = L["General Options"],
                        },
                		estheal_bar_enabled = {
        					name = L["Enabled"],
        					desc = L["Enable the Estimated Healing Bar."],
        					type = "toggle",
        					order = 10,
        					set = function(info, val)
        					    self.db.profile.damage_bar_enabled = val
        					    if not val then
        						    self.damagebar:Hide()
        						end
        					end,
                            get = function(info) return self.db.profile.damage_bar_enabled end,
        				},
        				lock_estheal_bar = {
        					name = L["Lock bar"],
        					desc = L["LockBarDesc"],
        					type = "toggle",
        					order = 20,
        					set = function(info, val)
        					    self.db.profile.lock_damage_bar = val 
        						BloodShieldTracker:EstHealBarLock(val)
        					end,
                            get = function(info) return self.db.profile.lock_damage_bar end,
        				},
        				hide_damage_bar_ooc = {
        					name = L["Hide out of combat"],
        					desc = L["HideOOC_OptionDesc"],
        					type = "toggle",
        					order = 30,
        					set = function(info, val)
        					    self.db.profile.hide_damage_bar_ooc = val 
        						if BloodShieldTracker.damagebar then
        							BloodShieldTracker.damagebar.hideooc = val
        							if not InCombatLockdown() then
        							    if val then
        							        self.damagebar:Hide()
        						        elseif self:IsTrackerEnabled() then
        						            self.damagebar:Show()
        					            end
        					        end
        						end					
        					end,
                            get = function(info)
                                return self.db.profile.hide_damage_bar_ooc
                            end,
        				},
        				estimate_bar_mode = {
        					name = L["Mode"],
        					desc = L["Mode"],
        					type = "select",
        					values = {
        					    ["DS"] = L["Death Strike Heal"],
        					    ["BS"] = L["Blood Shield"],
        					},
        					order = 40,
        					set = function(info, val)
        					    self.db.profile.estimate_bar_mode = val
        					end,
                            get = function(info)
                                return self.db.profile.estimate_bar_mode
                            end,
        				},
        				estheal_bar_show_text = {
        					name = L["Show Text"],
        					desc = L["EstHealBarShowText_OptDesc"],
        					type = "toggle",
        					order = 35,
        					set = function(info, val)
        					    self.db.profile.estheal_bar_show_text = val
        					    self:UpdateMinHeal("UpdateShowText", "player")
        					end,
                            get = function(info) return self.db.profile.estheal_bar_show_text end,
        				},
                        dimensions = {
                            order = 50,
                            type = "header",
                            name = L["Dimensions"],
                        },
        				estheal_bar_width = {
        					order = 60,
        					name = L["Width"],
        					desc = L["Change the width of the estimated healing bar."],	
        					type = "range",
        					min = 10,
        					max = 200,
        					set = function(info, val)
        					    self.db.profile.damage_bar_width = val 
        						self.damagebar:SetWidth(val)
        						self.damagebar.border:SetWidth(val+9)
        					end,
        					get = function(info, val)
        					    return self.db.profile.damage_bar_width
        					end,
        				},
        				estheal_bar_height = {
        					order = 70,
        					name = L["Height"],
        					desc = L["Change the height of the estimated healing bar."],	
        					type = "range",
        					min = 8,
        					max = 30,
        					step = 1,
        					set = function(info, val)
        					    self.db.profile.damage_bar_height = val 
        						self.damagebar:SetHeight(val)
        						self.damagebar.border:SetHeight(val + 8)
        					end,
        					get = function(info, val)
        					    return self.db.profile.damage_bar_height
        					end,
        				},
        				estheal_bar_scaling = {
        					order = 80,
        					name = L["Scale"],
        					desc = L["ScaleDesc"],
        					type = "range",
        					min = 0.1,
        					max = 3,
        					step = 0.1,
        					get = function()
        					    return self.db.profile.estheal_bar_scale
        					end,
        					set = function(info, val)
        					    self.db.profile.estheal_bar_scale = val
        					    self.damagebar:SetScale(val)
        					end
        				},
                        colorsMinimum = {
                            order = 90,
                            type = "header",
                            name = L["Colors for Minimum Heal"],
                        },
        				estheal_bar_min_textcolor = {
        					order = 100,
        					name = L["Minimum Text Color"],
        					desc = L["EstHealBarMinTextColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_min_textcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(
        					            self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_min_textcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				estheal_bar_min_color = {
        					order = 110,
        					name = L["Minimum Bar Color"],
        					desc = L["EstHealBarMinColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_min_color
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(
        					            self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_min_color
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				estheal_bar_min_bgcolor = {
        					order = 120,
        					name = L["Minimum Bar Background Color"],
        					desc = L["EstHealBarMinBackgroundColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_min_bgcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(
        					            self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_min_bgcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
                        colorsOptimal = {
                            order = 130,
                            type = "header",
                            name = L["Colors for Optimal Heal"],
                        },
        				estheal_bar_opt_textcolor = {
        					order = 140,
        					name = L["Optimal Text Color"],
        					desc = L["EstHealBarOptTextColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_opt_textcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(
        					            self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_opt_textcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				estheal_bar_opt_color = {
        					order = 150,
        					name = L["Optimal Bar Color"],
        					desc = L["EstHealBarOptColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_opt_color
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(
        					            self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_opt_color
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
                        appearance = {
                            order = 160,
                            type = "header",
                            name = L["Appearance"],
                        },
        				estheal_bar_texture_opt = {
        					order = 170,
        					name = L["Texture"],
        					desc = L["BarTexture_OptionDesc"],
        					type = "select",
        					values = LSM:HashTable("statusbar"),
        					dialogControl = 'LSM30_Statusbar',
        					get = function()
        					    return self.db.profile.estheal_bar_texture
        					end,
        					set = function(info, val)
        					    self.db.profile.estheal_bar_texture = val
        					    self:UpdateDamageBarTexture()
        					end,
        					disabled = function()
        					    return not self.db.profile.estheal_bar_shown
        					end,
        				},
        				estheal_bar_border_visible_opt = {
        					order = 180,
        					name = L["ShowBorder"],
        					desc = L["ShowBorderDesc"],
        					type = "toggle",
        					get = function()
        					    return self.db.profile.estheal_bar_border
        					end,
        					set = function(info, val)
        					    self.db.profile.estheal_bar_border = val
        					    self:UpdateDamageBarBorder()
        					end,
        				},
        				estheal_bar_visible_opt = {
        					order = 190,
        					name = L["ShowBar"],
        					desc = L["ShowBarDesc"],
        					type = "toggle",
        					get = function()
        					    return self.db.profile.estheal_bar_shown
        					end,
        					set = function(info,val)
        					    self.db.profile.estheal_bar_shown = val
        					    self:UpdateDamageBarVisibility()
        					end,
        				},
                        latencyOptions = {
                            order = 500,
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
        					order = 510,
        					set = function(info, val)
        					    self.db.profile.latencyMethod = val
        					end,
                            get = function(info)
                                return self.db.profile.latencyMethod
                            end,
        				},
        				latencyFixed = {
        					order = 520,
        					name = L["Fixed"],
        					desc = L["Fixed"],
        					type = "range",
        					min = 0,
        					max = 2000,
        					step = 1,
        					set = function(info, val)
        					    self.db.profile.latencyFixed = val 
        					end,
        					get = function(info, val)
        					    return self.db.profile.latencyFixed
        					end,					
        				},

        			}
        		},

        		pwsBarOpts = {
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
                		pwsbar_enabled = {
        					name = L["Enabled"],
        					desc = L["EnableBarDesc"],
        					type = "toggle",
        					order = 10,
        					set = function(info, val)
        					    self.db.profile.pwsbar_enabled = val
        					    if not val then
        						    BloodShieldTracker.pwsbar:Hide()
        						end
        					end,
                            get = function(info) return self.db.profile.pwsbar_enabled end,
        				},
        				lock_pwsbar = {
        					name = L["Lock bar"],
        					desc = L["LockBarDesc"],
        					type = "toggle",
        					order = 20,
        					set = function(info, val)
        					    self.db.profile.lock_pwsbar = val 
        						BloodShieldTracker:PWSBarLock(val)
        					end,
                            get = function(info) return self.db.profile.lock_pwsbar end,
        				},
                        dimensions = {
                            order = 300,
                            type = "header",
                            name = L["Dimensions"],
                        },
        				pwsbar_width = {
        					order = 310,
        					name = L["Width"],
        					desc = L["BarWidth_Desc"],	
        					type = "range",
        					min = 50,
        					max = 300,
        					step = 1,
        					set = function(info, val)
        					    self.db.profile.pwsbar_width = val 
        						self.pwsbar:SetWidth(val)
        						self.pwsbar.border:SetWidth(val+9)
        					end,
        					get = function(info, val)
        					    return self.db.profile.pwsbar_width
        					end,
        				},
        				pwsbar_height = {
        					order = 320,
        					name = L["Height"],
        					desc = L["BarHeight_Desc"],
        					type = "range",
        					min = 10,
        					max = 30,
        					step = 1,
        					set = function(info, val)
        					    self.db.profile.pwsbar_height = val 
        						self.pwsbar:SetHeight(val)
        						self.pwsbar.border:SetHeight(val + 8)
        					end,
        					get = function(info, val)
        					    return self.db.profile.pwsbar_height
        					end,					
        				},
        				pwsbar_scaling = {
        					order = 330,
        					name = L["Scale"],
        					desc = L["ScaleDesc"],
        					type = "range",
        					min = 0.1,
        					max = 3,
        					step = 0.1,
        					get = function() return self.db.profile.pwsbar_scale end,
        					set = function(info, val)
        					    self.db.profile.pwsbar_scale = val
        					    self.pwsbar:SetScale(val)
        					end
        				},
                        colors = {
                            order = 400,
                            type = "header",
                            name = L["Colors"],
                        },
        				pwsbar_textcolor = {
        					order = 410,
        					name = L["Text Color"],
        					desc = L["BarTextColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.pwsbar_textcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    self:UpdatePWSBarGraphics()
        					end,
        					get = function(info)
        				        local c = self.db.profile.pwsbar_textcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				pwsbar_color = {
        					order = 420,
        					name = L["Bar Color"],
        					desc = L["BarColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.pwsbar_color
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    self:UpdatePWSBarGraphics()
        					end,
        					get = function(info)
        				        local c = self.db.profile.pwsbar_color
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
                        appearance = {
                            order = 500,
                            type = "header",
                            name = L["Appearance"],
                        },
        				pwsbar_texture_opt = {
        					order = 510,
        					name = L["Texture"],
        					desc = L["BarTexture_OptionDesc"],
        					type = "select",
        					values = LSM:HashTable("statusbar"),
        					dialogControl = 'LSM30_Statusbar',
        					get = function()
        					    return self.db.profile.pwsbar_texture
        					end,
        					set = function(info, val)
        					    self.db.profile.pwsbar_texture = val
        					    self:UpdatePWSBarTexture()
        					end,
        					disabled = function()
        					    return not self.db.profile.pwsbar_shown
        					end,
        				},
        				pwsbar_border_visible_opt = {
        					order = 520,
        					name = L["ShowBorder"],
        					desc = L["ShowBorderDesc"],
        					type = "toggle",
        					get = function()
        					    return self.db.profile.pwsbar_border
        					end,
        					set = function(info, val)
        					    self.db.profile.pwsbar_border = val
        					    self:UpdatePWSBarBorder()
        					end,
        				},
        				pwsbar_visible_opt = {
        					order = 530,
        					name = L["ShowBar"],
        					desc = L["ShowBarDesc"],
        					type = "toggle",
        					get = function() return self.db.profile.pwsbar_shown end,
        					set = function(info,val) 
        				        self.db.profile.pwsbar_shown = val
        				        self:UpdatePWSBarVisibility()
        				    end,
        				},
        			},
        		},

        		illumBarOpts = {
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
        					    self.db.profile.illumbar_enabled = val
        					    if not val then
        						    BloodShieldTracker.illumbar:Hide()
        						end
        					end,
                            get = function(info) return self.db.profile.illumbar_enabled end,
        				},
        				lock_bar = {
        					name = L["Lock bar"],
        					desc = L["LockBarDesc"],
        					type = "toggle",
        					order = 20,
        					set = function(info, val)
        					    self.db.profile.lock_illumbar = val 
        						BloodShieldTracker:IllumBarLock(val)
        					end,
                            get = function(info) return self.db.profile.lock_illumbar end,
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
        					    self.db.profile.illumbar_width = val 
        						self.illumbar:SetWidth(val)
        						self.illumbar.border:SetWidth(val+9)
        					end,
        					get = function(info, val)
        					    return self.db.profile.illumbar_width
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
        					    self.db.profile.illumbar_height = val 
        						self.illumbar:SetHeight(val)
        						self.illumbar.border:SetHeight(val + 8)
        					end,
        					get = function(info, val)
        					    return self.db.profile.illumbar_height
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
        					get = function() return self.db.profile.illumbar_scale end,
        					set = function(info, val)
        					    self.db.profile.illumbar_scale = val
        					    self.illumbar:SetScale(val)
        					end
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
        					    local c = self.db.profile.illumbar_textcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    self:UpdateIllumBarGraphics()
        					end,
        					get = function(info)
        				        local c = self.db.profile.illumbar_textcolor
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
        					    local c = self.db.profile.illumbar_color
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    self:UpdateIllumBarGraphics()
        					end,
        					get = function(info)
        				        local c = self.db.profile.illumbar_color
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
        					    return self.db.profile.illumbar_texture
        					end,
        					set = function(info, val)
        					    self.db.profile.illumbar_texture = val
        					    self:UpdateIllumBarTexture()
        					end,
        					disabled = function()
        					    return not self.db.profile.illumbar_shown
        					end,
        				},
        				bar_border_visible_opt = {
        					order = 520,
        					name = L["ShowBorder"],
        					desc = L["ShowBorderDesc"],
        					type = "toggle",
        					get = function()
        					    return self.db.profile.illumbar_border
        					end,
        					set = function(info, val)
        					    self.db.profile.illumbar_border = val
        					    self:UpdateIllumBarBorder()
        					end,
        				},
        				bar_visible_opt = {
        					order = 530,
        					name = L["ShowBar"],
        					desc = L["ShowBarDesc"],
        					type = "toggle",
        					get = function() return self.db.profile.illumbar_shown end,
        					set = function(info,val) 
        				        self.db.profile.illumbar_shown = val
        				        self:UpdateIllumBarVisibility()
        				    end,
        				},
        			},
        		},
        		
            }
        }
	options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    end
    return options
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

function BloodShieldTracker:ChatCommand(input)
    if not input or input:trim() == "" then
        self:ShowOptions()
    else
        if input == "debug" then
            if DEBUG_OUTPUT == false then
                DEBUG_OUTPUT = true
                self:Print("Debugging on.")
            else
                DEBUG_OUTPUT = false
                self:Print("Debugging off.")
            end
        elseif input == "showdebug" then
            self:ShowDebugOutput()
        end
        --LibStub("AceConfigCmd-3.0").HandleCommand(BloodShieldTracker, "bst", "BloodShieldTracker", input)
    end
end

function BloodShieldTracker:OnInitialize()
    -- Load the settings
    self.db = LibStub("AceDB-3.0"):New("BloodShieldTrackerDB", defaults, "Default")
	-- Create the shield bar
    self.statusbar = self:CreateShieldBar()
	self:ShieldBarLock(self.db.profile.lock_status_bar)
    self.statusbar.shield_curr = 0
    self.statusbar.expires = 0
    self.statusbar.active = false
	self:UpdateShieldBarMode()
    self:UpdateShieldBarText(0, 0, 0)
    -- Create the estimate/damage bar
    self.damagebar = self:CreateEstimateBar()
	self:EstHealBarLock(self.db.profile.lock_damage_bar)
	self.damagebar.hideooc = self.db.profile.hide_damage_bar_ooc
	self.damagebar.minheal = true
	-- Create the PW:S bar
    self.pwsbar = self:CreatePWSBar()
	self:PWSBarLock(self.db.profile.lock_pwsbar)
	-- Create the Illum. Heal bar
    self.illumbar = self:CreateIllumBar()
	self:IllumBarLock(self.db.profile.lock_illumbar)

	-- Register for profile callbacks
	self.db.RegisterCallback(self, "OnProfileChanged", "Reset")
	self.db.RegisterCallback(self, "OnProfileCopied", "Reset")
	self.db.RegisterCallback(self, "OnProfileReset", "Reset")
	-- Register Options
    local displayName = GetAddOnMetadata(ADDON_NAME, "Title")
	local options = self:GetOptions()
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(displayName, options)

    self.optionsFrame = {}
    local ACD = LibStub("AceConfigDialog-3.0")
	self.optionsFrame.Main = ACD:AddToBlizOptions(
	    displayName, displayName, nil, "core")
	self.optionsFrame.ShieldBar = ACD:AddToBlizOptions(
	    displayName, L["Blood Shield Bar"], displayName, "shieldBarOpts")
	self.optionsFrame.EstHealBar = ACD:AddToBlizOptions(
	    displayName, L["Estimated Healing Bar"], displayName, "estHealBarOpts")
	self.optionsFrame.ShieldBar = ACD:AddToBlizOptions(
	    displayName, L["PW:S Bar"], displayName, "pwsBarOpts")
	self.optionsFrame.ShieldBar = ACD:AddToBlizOptions(
	    displayName, L["Illuminated Healing Bar"], displayName, "illumBarOpts")

	ACD:AddToBlizOptions(
	    displayName, options.args.profile.name, displayName, "profile")

    -- Register the chat command
    self:RegisterChatCommand("bst", "ChatCommand")
    self:RegisterChatCommand("bloodshield", "ChatCommand")

	icon:Register("BloodShieldTrackerLDB", Broker.obj, self.db.profile.minimap)
	LSM.RegisterCallback(BloodShieldTracker, "LibSharedMedia_Registered")
end

function BloodShieldTracker:Reset()
	-- Reset positions
	if self.damagebar then
		self.damagebar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.est_heal_x, self.db.profile.est_heal_y)
    	self:EstHealBarLock(self.db.profile.lock_damage_bar)
    	self.damagebar.hideooc = self.db.profile.hide_damage_bar_ooc
		self:UpdateDamageBarTexture()
		self:UpdateDamageBarBorder()
		self:UpdateDamageBarVisibility()
		self:UpdateDamageBarColors()
	end
	if self.statusbar then
		self.statusbar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.shield_bar_x, self.db.profile.shield_bar_y)
    	self:ShieldBarLock(self.db.profile.lock_status_bar)
		self:UpdateShieldBarTexture()
		self:UpdateShieldBarBorder()
		self:UpdateShieldBarVisibility()
		self:UpdateShieldBarGraphics()
	end
	if self.pwsbar then
		self.pwsbar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.pwsbar_x, self.db.profile.pwsbar_y)
    	self:PWSBarLock(self.db.profile.lock_pwsbar)
		self:UpdatePWSBarTexture()
		self:UpdatePWSBarBorder()
		self:UpdatePWSBarVisibility()
		self:UpdatePWSBarGraphics()
	end
	if self.illumbar then
		self.illumbar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.illumbar_x, self.db.profile.illumbar_y)
    	self:IllumBarLock(self.db.profile.lock_illumbar)
		self:UpdateIllumBarTexture()
		self:UpdateIllumBarBorder()
		self:UpdateIllumBarVisibility()
		self:UpdateIllumBarGraphics()
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

function BloodShieldTracker:ResetFonts()
	local fontName, fontHeight = self.statusbar.value:GetFont()
	local fontFlags = self:GetFontFlags()
	local ff = LSM:Fetch("font",self.db.profile.font_face)
	local fh = self.db.profile.font_size
	self.statusbar.value:SetFont(ff,fh,fontFlags)
	self.statusbar.value:SetText(self.statusbar.value:GetText())
	self.statusbar.time:SetFont(ff,fh,fontFlags)
	self.statusbar.time:SetText(self.statusbar.time:GetText())
	self.damagebar.value:SetFont(ff,fh,fontFlags)						
	self.damagebar.value:SetText(self.damagebar.value:GetText())
    if self.pwsbar then
    	self.pwsbar.value:SetFont(ff,fh,fontFlags)						
    	self.pwsbar.value:SetText(self.pwsbar.value:GetText())
    end
    if self.illumbar then
    	self.illumbar.value:SetFont(ff,fh,fontFlags)						
    	self.illumbar.value:SetText(self.illumbar.value:GetText())
    end
end

function BloodShieldTracker:LibSharedMedia_Registered(event, mediatype, key)
	if strlen(self.db.profile.font_face) > 1 and mediatype == "font" then
		if self.db.profile.font_face == key then
			self:ResetFonts()
		end
	end
	if mediatype == "statusbar" then
		if self.db.profile.estheal_bar_shown then
			self:UpdateDamageBarTexture()
		end
		if self.db.profile.status_bar_shown then
			self:UpdateShieldBarTexture()
		end
		if self.db.profile.pwsbar_shown then
			self:UpdatePWSBarTexture()
		end
		if self.db.profile.illumbar_shown then
			self:UpdateIllumBarTexture()
		end
	end
end

function BloodShieldTracker:UpdateHealingDebuffs()
    for k,v in pairs(HEALING_DEBUFFS) do
        local spellName = (GetSpellInfo(k))
        if spellName and #spellName > 0 then
    	    healing_debuff_names[spellName] = true
        end
    end
end

function BloodShieldTracker:OnEnable()
    self:UpdateHealingDebuffs()
    self:CheckClass()
	self:UpdateMinHeal("UNIT_MAXHEALTH", "player")
	self:UpdateMastery()
	self:CheckImpDeathStrike()
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED","CheckImpDeathStrike")
	self:RegisterEvent("CHARACTER_POINTS_CHANGED","CheckImpDeathStrike")
	self:RegisterEvent("PLAYER_TALENT_UPDATE","CheckImpDeathStrike")
	self:RegisterEvent("GLYPH_ADDED", "CheckGlyphs")
	self:RegisterEvent("GLYPH_REMOVED", "CheckGlyphs")
	self:RegisterEvent("GLYPH_UPDATED", "CheckGlyphs")
end

function BloodShieldTracker:Load()
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
    if self:IsTrackerEnabled() and (not self.damagebar.hideooc or InCombatLockdown()) then
        self.damagebar:Show()
    end
    self:UpdateShieldBarVisibility()
	self:UpdateDamageBarVisibility()
end

function BloodShieldTracker:Unload()
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
	self.damagebar:Hide()
end

function BloodShieldTracker:OnDisable()
	-- We dont need to unregister events as OnDisable tells all the ace embed to disable and unregister
end

-- Watch for combat rating updates so we can adjust mastery score as it changes,
-- i.e. trinket procs, buffs etc .. we only need to check this when it changes instead of every time we see damage
local GetMastery = GetMastery
local idle = true

function BloodShieldTracker:UpdateMastery()
    masteryRating = GetMastery()
end

function BloodShieldTracker:CheckClass()
    local class, className = UnitClass("player")
    if className then
        if (className == 'DEATH KNIGHT' or className == 'DEATHKNIGHT') then
            isDK = true
        else
            isDK = false
        end
    end
end

function BloodShieldTracker:CheckImpDeathStrike()
    if isDK == nil then
        self:CheckClass()
    end

	ImpDSModifier = 1
	IsBloodTank = false
	hasBloodShield = false

	if isDK then
    	for t = 1, GetNumTalentTabs() do
    		for i = 1, GetNumTalents(t) do
    			local talentName, _, _, _, currRank, maxRank = GetTalentInfo(t, i)
    			if talentName == IMP_DS_TALENT and currRank > 0 then
    				ImpDSModifier = 1 + (0.15 * currRank)
    			end
    			if talentName == VB_BUFF and currRank > 0 then
    				HasVampTalent = true
    			end
    		end
    	end
    	local primaryTalentTree = GetPrimaryTalentTree()
    	if primaryTalentTree then
        	local id, name, desc, texture = GetTalentTabInfo(primaryTalentTree, false)
        	if texture == "Interface\\Icons\\Spell_Deathknight_BloodPresence" then
        		IsBloodTank = true
        		-- Check if the player knows Mastery as it is needed to get Blood Shield
                if IsSpellKnown(86471) then
                    hasBloodShield = true
                end
        	end
        else
            if self.db.profile.verbose then
                self:Print(L["Could not determine talents."])
            end
        end
    	--if HasVampTalent then
        	self:CheckGlyphs()
    	--end
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
    vbGlyphed = false
    HasSuccorGlyphed = false
	--if not HasVampTalent then return end -- Dont bother with glyph check if he doesnt have the talent
    for id = 1, GetNumGlyphSockets() do
        local enabled, glyphType, glyphTooltipIndex, 
            glyphSpell, iconFilename = GetGlyphSocketInfo(id, nil)
        if enabled then
            if glyphSpell == VB_GLYPH_ID then
                vbGlyphed = true
            elseif glyphSpell == DARK_SUCCOR_GLYPH_ID then
                HasSuccorGlyphed = true
            end
        end
    end
end

function BloodShieldTracker:GetEffectiveHealingBuffModifiers()
    return (1+iccBuffAmt) * (1+vbHealingInc) * (1+gsHealModifier) * (1+luckOfTheDrawAmt)
end

function BloodShieldTracker:GetEffectiveHealingDebuffModifiers()
    return (1-healingDebuffMultiplier)
end

function BloodShieldTracker:UpdateMinHeal(event,unit)
	if unit == "player" then
	    maxHealth = UnitHealthMax("player")
	    actualDsMinHeal = dsMinHealPercent

        -- Check for Dark Succor
        if CurrentPresence == "Unholy" or CurrentPresence == "Frost" then
    	    if CURRENT_UI_VERSION < 40200 and HasSuccorGlyphed == true then
    	        actualDsMinHeal = dsMinHealPercentSuccor41
            end
            if DarkSuccorBuff == true then
    	        actualDsMinHeal = dsMinHealPercentSuccor
            end
        end
        
		dsHealMin = round(
		    maxHealth * actualDsMinHeal * 
		    self:GetEffectiveHealingBuffModifiers() * 
		    self:GetEffectiveHealingDebuffModifiers())
		if idle then
		    self:UpdateEstHealBarText(dsHealMin)
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
        if self.db.profile.damage_bar_enabled and self.damagebar then
	        self.damagebar:Show()
	        self.damagebar:SetScript("OnUpdate", UpdateTime)
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
	self:UpdateEstHealBarText(dsHealMin)
    self.damagebar.minheal = true
    self:UpdateDamageBarColors(true)
    self.damagebar:SetMinMaxValues(0, 1)
    self.damagebar:SetValue(1)
    
    if self.damagebar.hideooc then
        self.damagebar:Hide()
    end

    self.damagebar:SetScript("OnUpdate", nil)

    LastFightStats:EndCombat()
end

function BloodShieldTracker:PLAYER_DEAD()
    -- Just in case, hide the BS bar if the player dies
    self.statusbar.expires = 0
    self:CheckAuras()
    self.statusbar:Hide()
    -- Hide the heal bar if configured to do so for OOC
    if self.damagebar.hideooc then
        self.damagebar:Hide()
    end
end

function BloodShieldTracker:UpdateBars(timestamp)
    -- If we're out of combat and no Blood Shields are present, stop the timer
    if idle and self.statusbar.expires == 0 then
    	if updateTimer then
            self:CancelTimer(updateTimer)
            updateTimer = nil
        end
    end

    if self.db.profile.status_bar_enabled then
        local expires = self.statusbar.expires
        local timeleft = 0
        local timeLeftFmt = "%d"
        local current = GetTime()
        if expires > 0 then
            timeleft = expires - current
            if timeleft < 0 or timeleft > 10 then
                timeleft = 0
            end
        
            timeleft = floor(timeleft)
        end

        if self.db.profile.shield_bar_progress == "Time" then
            self.statusbar:SetValue(timeleft)
        end

        self.statusbar.time:SetText(timeLeftFmt:format(timeleft))
    end

    self:UpdateEstHealBar(timestamp)
end

function BloodShieldTracker:UpdateEstHealBar(timestamp)
    if self.db.profile.damage_bar_enabled and not idle then
        local recentDamage = self:GetRecentDamageTaken(timestamp)
        local shieldPercent = masteryRating*shieldPerMasteryPoint/100

        local predictedValue, minimumValue = 0, 0

        if self.db.profile.estimate_bar_mode == "BS" then
            predictedValue = round(
                recentDamage * dsHealModifier * ImpDSModifier * shieldPercent)
            minimumValue = maxHealth * dsMinHealPercent * shieldPercent
        else
            predictedValue = round(
                recentDamage * dsHealModifier * ImpDSModifier *
                self:GetEffectiveHealingBuffModifiers() * 
                self:GetEffectiveHealingDebuffModifiers())
            minimumValue = dsHealMin
        end

        local estimate = minimumValue
    	if predictedValue > minimumValue then
    	    estimate = predictedValue
    	end

        self:UpdateEstHealBarText(estimate)
        self.damagebar:SetMinMaxValues(0, minimumValue)

        if predictedValue > minimumValue then
            self.damagebar.minheal = false
            self:UpdateDamageBarColors(false)
            self.damagebar:SetValue(minimumValue)        
        else
            self.damagebar.minheal = true
            self:UpdateDamageBarColors(true)
            self.damagebar:SetValue(predictedValue)
        end
    end
end

function BloodShieldTracker:UpdateEstHealBarText(estimate)
    if self.db.profile.estheal_bar_show_text then
        local text = ""
        if self.db.profile.estimate_bar_mode == "BS" then
            text = L["EstimateBarBSText"]
        else
            text = L["HealBarText"]
        end
        self.damagebar.value:SetText(healBarFormat:format(text, estimate))
    else
	    self.damagebar.value:SetText(healBarNoTextFormat:format(estimate))
    end
end

function BloodShieldTracker:UpdatePWSBarText(value)
    if self.db.profile.pwsbar_enabled then
        self.pwsbar.value:SetText(self:FormatNumber(value))
    end
end

function BloodShieldTracker:UpdateIllumBarText(value)
    if self.db.profile.illumbar_enabled then
        self.illumbar.value:SetText(self:FormatNumber(value))
    end
end

function BloodShieldTracker:UpdateShieldBarMode()
    if self.statusbar and self.db.profile.shield_bar_progress == "Time" then
        self.statusbar:SetMinMaxValues(0, BS_DURATION)
        self.statusbar:SetValue(BS_DURATION)
    elseif self.db.profile.shield_bar_progress == "None" then
        self.statusbar:SetMinMaxValues(0, 1)
        self.statusbar:SetValue(1)        
    end
end

function BloodShieldTracker:ShowShieldBar()
    if self.db.profile.status_bar_enabled then
        if self.db.profile.shield_bar_progress == "Time" then
            self.statusbar:SetValue(BS_DURATION)
        elseif self.db.profile.shield_bar_progress == "Current" then
            self.statusbar:SetMinMaxValues(0, self.statusbar.shield_max)
            self.statusbar:SetValue(self.statusbar.shield_curr)
        end

        self:UpdateShieldBarText(
            self.statusbar.shield_curr, self.statusbar.shield_max, 100)
        self.statusbar:Show()
    end
end

function BloodShieldTracker:UpdateShieldBar()
    if not IsBloodTank then return end

	if self.statusbar.shield_curr < 0 and self.db.profile.verbose then
        local badShieldValueFmt = "Bad shield value [Cur=%d, Dmg=%d, Max=%d]"
        self:Print(badShieldValueFmt:format(
            self.statusbar.shield_curr, damage, self.statusbar.shield_max))
    end

    if self.db.profile.shield_bar_progress == "Current" then
        self.statusbar:SetMinMaxValues(0, self.statusbar.shield_max)
	    self.statusbar:SetValue(self.statusbar.shield_curr)
    end

	local diff
	if self.statusbar.shield_max > 0 and self.statusbar.shield_curr > 0 then
	    diff = round(self.statusbar.shield_curr/self.statusbar.shield_max*100)
    else
        diff = 0
    end
    self:UpdateShieldBarText(self.statusbar.shield_curr, self.statusbar.shield_max, diff)
end

function BloodShieldTracker:FormatNumber(number)
    if tonumber(number) == nil then
        return number
    end
    
    local millFmt = "%.1fm"
    local thousandFmt = "%.1fk"
    if number > 1000000 then
        return millFmt:format(number / 1000000)
    elseif number > 1000 then
        return thousandFmt:format(number / 1000)
    end
    
    return number
end

function BloodShieldTracker:UpdateShieldBarText(current, maximum, percent)
    local newText = ""
    local percentFormat = "%d%%"
    
    local currentTxt = BloodShieldTracker:FormatNumber(current)
    local maximumTxt = BloodShieldTracker:FormatNumber(maximum)
    
    if self.db.profile.shield_bar_text_format == "Full" then
        newText = statusBarFormatFull:format(currentTxt, maximumTxt, percent)
    elseif self.db.profile.shield_bar_text_format == "OnlyCurrent" then
        newText = currentTxt
    elseif self.db.profile.shield_bar_text_format == "OnlyMax" then
        newText = maximumTxt
    elseif self.db.profile.shield_bar_text_format == "OnlyPerc" then
        newText = percentFormat:format(percent)
    elseif self.db.profile.shield_bar_text_format == "CurrMax" then
        newText = statusBarFormatNoPer:format(currentTxt, maximumTxt)
    else
        newText = statusBarFormatFull:format(currentTxt, maximumTxt, percent)
    end

	self.statusbar.value:SetText(newText)
end

function BloodShieldTracker:GetRecentDamageTaken(timestamp)
    local latency = 0
    local damage = 0
    local current = timestamp
    
    if not current or current <= 0 then
        current = currentTime
    end

    if self.db.profile.latencyMethod == "DS" then
        if DS_Latency and DS_Latency > 0 and DS_Latency <= 2 then
            latency = DS_Latency
        end
    elseif self.db.profile.latencyMethod == "Fixed" then
        latency = self.db.profile.latencyFixed / 1000
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

local DS_SentTime = nil
local DS_Latency = nil

function BloodShieldTracker:UNIT_SPELLCAST_SENT(event, unit, spellName)
    if unit == "player" and spellName == DS_SPELL_DMG then
        DS_SentTime = GetTime()
    end
end

function BloodShieldTracker:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName)
    if unit == "player" and spellName == DS_SPELL_DMG then
        local succeededTime = GetTime()
        if DS_SentTime then
            local diff = succeededTime - DS_SentTime
            if diff > 0 then
                DS_Latency = diff
                if self.db.profile.verbose then
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

    if CURRENT_UI_VERSION >= 40200 then
        event, timestamp, eventtype, hideCaster, 
        srcGUID, srcName, srcFlags, srcRaidFlags,
        destGUID, destName, destFlags, destRaidFlags,
        param9, param10, param11, param12, param13, param14, 
        param15, param16, param17, param18, param19, param20 = ...
    else
        event, timestamp, eventtype, hideCaster, 
        srcGUID, srcName, srcFlags,  
        destGUID, destName, destFlags, 
        param9, param10, param11, param12, param13, param14, 
        param15, param16, param17, param18, param19, param20 = ...
    end

    if not event or not eventtype or not destName then return end

    local spellName, spellAbsorb = "", ""

    currentTime = timestamp

    if eventtype:find("_DAMAGE") and destName == self.playerName then
        if eventtype:find("SWING_") and param9 then
            local damage, absorb = param9, param14 or 0

            if self.db.profile.verbose then
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
                if self.db.profile.verbose then
                    self:Print("Ignoring no source damage [" .. spellName .. 
                        "] of "..(damage or 0))
                end
            end

            -- Do not count Spirit Link damage since it doesn't affect DS.
            if spellName == SPIRIT_LINK_SPELL and srcName == SPIRIT_LINK_TOTEM then
                countDamage = false
                if self.db.profile.verbose then
                    self:Print("Ignoring Spirit Link damage of "..(damage or 0))
                end
            end

            if countDamage == true then
                self:AddDamageTaken(timestamp, damage)
            end

            if self.db.profile.verbose then
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
    			-- For some reason in 4.3 the amount has been moved.
    			if CURRENT_UI_VERSION >= 40300 then
    			    damage = param11 or 0
			    else
    			    damage = param10 or 0
                end

                if self.db.profile.verbose then
                    local absorbFmt = "Absorbed swing for %d"
                    self:Print(absorbFmt:format(damage))
                end
            end
        elseif eventtype:find("SPELL_") then
            if param12 and param12 == 'ABSORB' then
                local damage = 0
    			-- For some reason in 4.3 the amount has been moved.
    			if CURRENT_UI_VERSION >= 40300 then
                    damage = param14 or 0
                else
                    damage = param13 or 0
                end

                local spellName, school = param10 or "n/a", param11 or 0
                local schoolName = self:GetSpellSchool(school) or "N/A"

                if self.db.profile.verbose then
                    local absorbFmt = "Absorbed spell (%s-%s,%d) for %d"
                    self:Print(absorbFmt:format(spellName, schoolName, school, damage))
                end
            end
        end
    end

	if eventtype == "SPELL_CAST_SUCCESS" and srcName == self.playerName and 
	    param10 == DS_SPELL_DMG then

        if self.db.profile.verbose then
            local dsHealFormat = "Estimated damage of %d will be a heal for %d"
            local recentDmg = self:GetRecentDamageTaken(timestamp)
            local predictedHeal = 0
            if healingDebuffMultiplier ~= 1 then 
                predictedHeal = round(
                    recentDmg * dsHealModifier * ImpDSModifier * 
                    self:GetEffectiveHealingBuffModifiers() * 
                    self:GetEffectiveHealingDebuffModifiers())
            end
    		self:Print(dsHealFormat:format(recentDmg, predictedHeal))
        end
	end
    if eventtype == "SPELL_HEAL" and destName == self.playerName 
        and param10 == DS_SPELL_HEAL then
        
        local shieldPercent = masteryRating*shieldPerMasteryPoint/100
        local totalHeal = param12 or 0
        local overheal = param13 or 0
        local actualHeal = param12-param13
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
        local minimumBS = round(maxHealth * actualDsMinHeal * shieldPercent)
        
        if healingDebuffMultiplier == 1 then
            shieldValue = minimumBS
            predictedHeal = 0
            isMinimum = true
        else
            shieldValue = round(totalHeal*shieldPercent / 
                self:GetEffectiveHealingBuffModifiers() / 
                self:GetEffectiveHealingDebuffModifiers())
            if shieldValue <= minimumBS then
                isMinimum = true
                shieldValue = minimumBS
            end
            predictedHeal = round(
                recentDmg * dsHealModifier * ImpDSModifier * 
                    self:GetEffectiveHealingBuffModifiers() * 
                    self:GetEffectiveHealingDebuffModifiers())
        end

        if self.db.profile.verbose then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Last5:%d, Pred:%d]"
            self:Print(dsHealFormat:format(
                totalHeal,actualHeal,overheal,recentDmg,predictedHeal))
        end
        
        if DEBUG_OUTPUT == true then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Last5:%d, Pred:%d]"
            DEBUG_BUFFER = DEBUG_BUFFER .. timestamp .. "   " .. 
                dsHealFormat:format(totalHeal,actualHeal,overheal,
                recentDmg,predictedHeal) .. "\n"
        end
    end

    if eventtype == "SPELL_AURA_APPLIED" and destName == self.playerName and param10 then
        if param10 then spellName = param10 end
        if param13 then spellAbsorb = param13 end

        if param10 == BS_SPELL then
            if self.db.profile.verbose then
                if spellAbsorb and spellAbsorb ~= "" then
                    self:Print("Blood Shield applied.  Value = "..spellAbsorb)
                else
                    self:Print("Blood Shield applied.  No value present.")
                end
            end

            if self.db.profile.useAuraForShield == false then
                self:NewBloodShield(timestamp, spellAbsorb)
            end
        elseif param10 == VB_BUFF then
            if self.db.profile.verbose then
                self:Print("Vampiric Blood applied.")
            end
        elseif param10 == GUARDIAN_SPIRIT_BUFF then
            if self.db.profile.verbose then
                self:Print("Guardian Spirit applied.")
            end
        end
    end

    if eventtype == "SPELL_AURA_REFRESH" and destName == self.playerName then
        if param10 then spellName = param10 end
        if param13 then spellAbsorb = param13 end

        if param10 then
            if param10 == BS_SPELL then
                if self.db.profile.verbose and spellAbsorb and spellAbsorb ~= "" then
                    self:Print("Blood Shield refresh.  New value = "..spellAbsorb)
                end

                if self.db.profile.useAuraForShield == false then
                    self:BloodShieldUpdated("refreshed", timestamp, spellAbsorb or 0)
                end
            end
        end
    end

    if eventtype == "SPELL_AURA_REMOVED" and destName == self.playerName and param10 then
        if param10 then spellName = param10 end
        if param13 then spellAbsorb = param13 end

        if param10 == BS_SPELL then
            if self.db.profile.useAuraForShield == false then
                self:BloodShieldUpdated("removed", timestamp, spellAbsorb or 0)
            end

            if self.db.profile.verbose and spellAbsorb and spellAbsorb ~= "" then
                self:Print("Blood Shield removed.  Remaining = "..spellAbsorb)
            end
        elseif param10 == VB_BUFF then
            if self.db.profile.verbose then
                self:Print("Vampiric Blood removed.")
            end
        elseif param10 == GUARDIAN_SPIRIT_BUFF then
            if self.db.profile.verbose then
                self:Print("Guardian Spirit removed.")
            end
        end
    end
end

function BloodShieldTracker:NewBloodShield(timestamp, shieldValue)
    self.statusbar.active = true
    self.statusbar.shield_curr = 0
    self.statusbar.shield_max = 0
    self.statusbar.expires = GetTime() + 10

    if not IsBloodTank or not hasBloodShield then return end

    local isMinimum = false
    local shieldPercent = masteryRating*shieldPerMasteryPoint/100
    local minimumBS = round(maxHealth * actualDsMinHeal * shieldPercent)

    if shieldValue <= minimumBS then
        isMinimum = true
    end

    self.statusbar.shield_max = self.statusbar.shield_max + shieldValue
    self.statusbar.shield_curr = self.statusbar.shield_curr + shieldValue

    if self.db.profile.verbose or DEBUG_OUPUT then
        local shieldInd = ""
        if isMinimum then
            shieldInd = " (min)"
        end

        local shieldFormat = "Blood Shield Amount: %d%s"
        if self.db.profile.verbose then
            self:Print(shieldFormat:format(shieldValue,shieldInd))
        end

        if DEBUG_OUTPUT then
            DEBUG_BUFFER = DEBUG_BUFFER .. 
                shieldFormat:format(shieldValue,shieldInd) .."\n"
        end
    end

    self:UpdateStatsNewShield(shieldValue, isMinimum, false)
    self:ShowShieldBar()

    if self.db.profile.shield_sound_enabled and self.db.profile.shield_applied_sound then
        PlaySoundFile(LSM:Fetch("sound", self.db.profile.shield_applied_sound))
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

function BloodShieldTracker:BloodShieldUpdated(type, timestamp, current)
    if not IsBloodTank then return end

    if type == "refreshed" then
        self.statusbar.active = true
    elseif type == "removed" then
        self.statusbar.active = false
    end

    local curr = self.statusbar.shield_curr or 0
    local isMinimum = false

    -- Calculate how much was added or absorbed
    local added = 0
    local absorbed = 0
    -- Check if the shield was increased due to a new DS/BS
    if current > curr then
        -- A new BS shield amount was added.  Update all of the stats.
        added = current - curr
        -- Check if it is a minimum heal.
        local shieldPercent = masteryRating*shieldPerMasteryPoint/100
        local minimumBS = round(maxHealth * actualDsMinHeal * shieldPercent)
        if added <= minimumBS then
            isMinimum = true
        end
        self:UpdateStatsNewShield(added, isMinimum, true)
        self.statusbar.expires = GetTime() + 10
        self.statusbar.shield_max = self.statusbar.shield_max + added

        if DEBUG_OUTPUT then
            local shieldRefreshedFormat = "Blood Shield Refreshed: %d%s"

            if isMinimum then
                shieldInd = " (min)"
            end

            DEBUG_BUFFER = DEBUG_BUFFER .. 
                shieldRefreshedFormat:format(added,shieldInd) .. "\n"
        end

        if self.db.profile.shield_sound_enabled and self.db.profile.shield_applied_sound then
            PlaySoundFile(LSM:Fetch("sound", self.db.profile.shield_applied_sound))
        end
    elseif current == curr and type == "refreshed" then
        -- No damage taken but refresh the time.
        -- This can happen if we hit the max shield value of maximum health.
        self.statusbar.expires = GetTime() + 10
    else
        absorbed = curr - current
        self:UpdateStatsShieldAbsorb(absorbed)
    end

    self.statusbar.shield_curr = current
    curr = current

    local max = self.statusbar.shield_max

    local currPerc = 0
    if max > 0 then
        currPerc = curr / max * 100
    end

    if self.db.profile.verbose then
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
        self.statusbar.expires = 0
        self.statusbar:Hide()
        self:UpdateStatsRemoveShield()
        self.statusbar.shield_max = 0
        self.statusbar.shield_curr = 0

        if self.db.profile.shield_sound_enabled and self.db.profile.shield_removed_sound then
            PlaySoundFile(LSM:Fetch("sound", self.db.profile.shield_removed_sound))
        end
    end

    self:UpdateShieldBar()
end

function BloodShieldTracker:ResetStats()
    TotalShieldStats:Reset()
    LastFightStats:Reset()
end

function BloodShieldTracker:UNIT_AURA(...)
    local event, unit = ...
    if unit == "player" then
        self:CheckAuras()
    end
end

local function GetNumericValue(...)
    local value
    local valueText
    local region
    local regionText

    for i = 1, select("#", ...) do
        region = select(i, ...)
        if region and region:GetObjectType() == "FontString" then
            regionText = region:GetText()
            if regionText then
                valueText = regionText:match("%d+")
                if valueText then
                    value = tonumber(valueText)
                    if value then
                        return value
                    end
                end
            end
        end
    end
end

local BSAuraPresent = false
local BSAuraValue = 0
local BSAuraExpires = 0
local PWSAuraPresent = false
local PWSAuraValue = 0

function BloodShieldTracker:CheckAuras()
    local name, rank, icon, count, dispelType, duration, expires,
        caster, stealable, consolidate, spellId

    local bsFound = false
    local pwsFound = false
    local pwsValue = OtherShields["PWS"]
    local illumHealFound = false
    local illumPrevValue = OtherShields["IlluminatedHealing"] or 0
    OtherShields["IlluminatedHealing"] = 0
    local iccBuffFound = false
    local vampBloodFound = false
    local healingDebuff = 0

    CurrentPresence = nil
    DarkSuccorBuff = false
    luckOfTheDrawBuff = false
    luckOfTheDrawAmt = 0
	healingDebuffMultiplier = 0
    gsBuff = false
    gsHealModifier = 0.0

    -- Loop through unit auras to find ones of interest.
    i = 1
    repeat
        name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
            consolidate, spellId = UnitAura("player", i)
        if name == nil or spellId == nil then break end

        if spellId == BS_SPELL_ID then
            -- Blood Shield present.  Get the value next from the tooltip.
            bsFound = true
            TipFrame:ClearLines()
            TipFrame:SetUnitBuff("player", name)
            local value = GetNumericValue(TipFrame:GetRegions())
            if value then
                if BSAuraPresent == false then
                    -- Blood Shield applied
                    if self.db.profile.verbose == true then
                        self:Print("AURA: Blood Shield applied. "..value)
                    end
                    self:NewBloodShield(GetTime(), value)
                else
                    if value ~= BSAuraValue or 
                        (expires ~= BSAuraExpires and value > 0) then
                        -- Blood Shield refreshed
                        if self.db.profile.verbose == true then
                            self:Print("AURA: Blood Shield refreshed. "..value
                                .." ["..(value - BSAuraValue).."]")
                        end
                        self:BloodShieldUpdated("refreshed", GetTime(), value)
                    end
                end

                BSAuraValue = value
                BSAuraExpires = expires
            else
                if self.db.profile.verbose == true then
                    if self.db.profile.verbose == true then
                        self:Print("Error reading the Blood Shield tooltip.")
                    end
                end
            end
            BSAuraPresent = true

        elseif spellId == PWS_SPELL_ID then
            -- Check for a Power Word: Shield
            if self.db.profile.pwsbar_enabled == true and IsBloodTank then
                pwsFound = true
                TipFrame:ClearLines()
                TipFrame:SetUnitBuff("player", name)
                local value = GetNumericValue(TipFrame:GetRegions())
                if value then
                    OtherShields["PWS"] = value
                    if pwsValue and pwsValue ~= value then
                        self:UpdatePWSBarText(value)
                    end
                    
                    self.pwsbar:Show()
                else
                    if self.db.profile.verbose == true then
                        self:Print("Error reading the Power Word: Shield tooltip.")
                    end
                end
            end
        elseif spellId == ILLUMINATED_HEALING_BUFF_ID then
            if self.db.profile.illumbar_enabled == true and IsBloodTank then
                illumHealFound = true
                TipFrame:ClearLines()
                TipFrame:SetUnitBuff("player", name)
                local value = GetNumericValue(TipFrame:GetRegions())
                if value then
                    OtherShields["IlluminatedHealing"] = 
                        OtherShields["IlluminatedHealing"] + value
                else
                    if self.db.profile.verbose == true then
                        self:Print("Error reading the Illuminated Healing tooltip.")
                    end
                end
            end

        elseif spellId == FROST_PRESENCE_BUFF_ID then
            CurrentPresence = "Frost"

        elseif spellId == UNHOLY_PRESENCE_BUFF_ID then
            CurrentPresence = "Unholy"

        elseif spellId == BLOOD_PRESENCE_BUFF_ID then
            CurrentPresence = "Blood"

        elseif spellId == DARK_SUCCOR_BUFF_ID then
            DarkSuccorBuff = true

        elseif spellId == LUCK_OF_THE_DRAW_BUFF_ID then
            luckOfTheDrawBuff = true
    	    if not count or count == 0 then
    	        count = 1
            end
            luckOfTheDrawAmt = LUCK_OF_THE_DRAW_MOD * count

        elseif name == HELLSCREAM_BUFF then
            iccBuffFound = true
            iccBuff = true
            iccBuffAmt = hellscreamBuffs[spellId] or hellscreamBuffs[HELLSCREAM_BUFF_30]

        elseif name == WRYNN_BUFF then
            iccBuffFound = true
            iccBuff = true
            iccBuffAmt = wrynnBuffs[spellId] or wrynnBuffs[WRYNN_BUFF_30]

        elseif spellId == VB_BUFF_ID then
            vbBuff = true
    		-- No Need to check how much bonus health we get from VB since we listen
    		-- for Unit Max Health updates
            if vbGlyphed then
                vbHealthInc = vbGlyphedHealthInc
                vbHealingInc = vbGlyphedHealingInc
            else
                vbHealthInc = vbUnglyphedHealthInc
                vbHealingInc = vbUnglyphedHealingInc
            end

        elseif spellId == GUARDIAN_SPIRIT_BUFF_ID then
            gsBuff = true
            gsHealModifier = guardianSpiritHealBuff

        else
            -- Check for various healing debuffs
        	for k,v in pairs(HEALING_DEBUFFS) do
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

    if not bsFound then
        if BSAuraPresent == true then
            -- Blood Shield removed
            if self.db.profile.verbose == true then
                self:Print("AURA: Blood Shield removed. "..BSAuraValue)
            end

            self:BloodShieldUpdated("removed", GetTime(), BSAuraValue)
        end
            
        BSAuraPresent = false
        BSAuraValue = 0
    end
    
    if not pwsFound then
        OtherShields["PWS"] = 0
        self.pwsbar:Hide()
    end

    if self.db.profile.illumbar_enabled == true and IsBloodTank then
        local illumValue = OtherShields["IlluminatedHealing"]
        if illumHealFound then
            if illumValue and illumValue ~= illumPrevValue then
                self:UpdateIllumBarText(illumValue)
            end
            self.illumbar:Show()
        else
            self.illumbar:Hide()
        end
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
end

function BloodShieldTracker:CheckAurasOld()
    local name, rank, icon, count, dispelType, duration, expires,
        caster, stealable, consolidate, spellId

    -- Check for the Blood Shield
    if self.db.profile.useAuraForShield == true then
        name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
            consolidate, spellId = UnitAura("player", BS_SPELL)
        if spellId then
            -- Blood Shield present.  Get the value next from the tooltip.
            TipFrame:ClearLines()
            TipFrame:SetUnitBuff("player", name)
            local value = GetNumericValue(TipFrame:GetRegions())
            if value then
                if BSAuraPresent == false then
                    -- Blood Shield applied
                    if self.db.profile.verbose == true then
                        self:Print("AURA: Blood Shield applied. "..value)
                    end
                    self:NewBloodShield(GetTime(), value)
                else
                    if value ~= BSAuraValue then
                        -- Blood Shield refreshed
                        if self.db.profile.verbose == true then
                            self:Print("AURA: Blood Shield refreshed. "..value
                                .." ["..(value - BSAuraValue).."]")
                        end
                        self:BloodShieldUpdated("refreshed", GetTime(), value)
                    end
                end

                BSAuraValue = value
            else
                if self.db.profile.verbose == true then
                    self:Print("Error reading the Blood Shield tooltip.")
                end
            end
            BSAuraPresent = true
        else
            if BSAuraPresent == true then
                -- Blood Shield removed
                if self.db.profile.verbose == true then
                    self:Print("AURA: Blood Shield removed. "..BSAuraValue)
                end

                self:BloodShieldUpdated("removed", GetTime(), BSAuraValue)
            end
                
            BSAuraPresent = false
            BSAuraValue = 0
        end
    end

    -- Check for a Power Word: Shield
    if self.db.profile.pwsbar_enabled == true then
        local pwsValue = OtherShields["PWS"]
        name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
            consolidate, spellId = UnitAura("player", PWS_SPELL)
        if spellId then
            TipFrame:ClearLines()
            TipFrame:SetUnitBuff("player", name)
            local value = GetNumericValue(TipFrame:GetRegions())
            if value then
                OtherShields["PWS"] = value
                pwsbar:Show()
                if pwsValue and pwsValue ~= value then
                    pwsbar.value:SetText(self:FormatNumber(value))
                end
            else
                if self.db.profile.verbose == true then
                    self:Print("Error reading the Power Word: Shield tooltip.")
                end
            end
        else
            OtherShields["PWS"] = 0
            pwsbar:Hide()
        end
    end

    -- Determine the presence
    CurrentPresence = nil
    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate, spellId = UnitAura("player", FROST_PRESENCE_BUFF)
    if spellId then
        CurrentPresence = "Frost"
    end
    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate, spellId = UnitAura("player", UNHOLY_PRESENCE_BUFF)
    if spellId then
        CurrentPresence = "Unholy"
    end
    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate, spellId = UnitAura("player", BLOOD_PRESENCE_BUFF)
    if spellId then
        CurrentPresence = "Blood"
    end

    -- Check for the Dark Succor buff
    DarkSuccorBuff = false
    if DARK_SUCCOR_BUFF_NAME and #DARK_SUCCOR_BUFF_NAME > 0 then
        name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
            consolidate, spellId = UnitAura("player", DARK_SUCCOR_BUFF_NAME)
        if spellId then
            DarkSuccorBuff = true
        end
    end

    -- Check for the Luck of the Draw buff
    luckOfTheDrawBuff = false
    luckOfTheDrawAmt = 0
    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate, spellId = UnitAura("player", LUCK_OF_THE_DRAW_BUFF)
    if spellId then
        luckOfTheDrawBuff = true
	    if not count or count == 0 then
	        count = 1
        end
        luckOfTheDrawAmt = LUCK_OF_THE_DRAW_MOD * count
    end

    local iccBuffFound = false

    -- Check for Hellscream's Warsong ICC buff
    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate, spellId = UnitAura("player", HELLSCREAM_BUFF)
    if spellId then
        iccBuffFound = true
        iccBuff = true
        iccBuffAmt = hellscreamBuffs[spellId] or hellscreamBuffs[HELLSCREAM_BUFF_30]
    end

    -- Check for Strength of Wrynn ICC buff
    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate,spellId = UnitAura("player", WRYNN_BUFF)
    if spellId then
        iccBuffFound = true
        iccBuff = true
        iccBuffAmt = wrynnBuffs[spellId] or wrynnBuffs[WRYNN_BUFF_30]
    end

    -- If the ICC buff isn't present, reset the values
    if not iccBuffFound then
        iccBuff = false
        iccBuffAmt = 0.0
    end

    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate, spellId = UnitAura("player", VB_BUFF)
    if name then
        vbBuff = true
		-- No Need to check how much bonus health we get from VB since we listen
		-- for Unit Max Health updates
        if vbGlyphed then
            vbHealthInc = vbGlyphedHealthInc
            vbHealingInc = vbGlyphedHealingInc
        else
            vbHealthInc = vbUnglyphedHealthInc
            vbHealingInc = vbUnglyphedHealingInc
        end
    else
        vbBuff = false
        vbHealthInc = 0.0
        vbHealingInc = 0.0
    end

    local healingDebuff = 0
	healingDebuffMultiplier = 0
	-- Scan for healing debuffs
	for k,v in pairs(healing_debuff_names) do
		name, rank, icon, count, dispelType, duration, expires, caster, 
		    stealable, consolidate, spellId = UnitDebuff("player", k)
		if spellId and HEALING_DEBUFFS[spellId] then
		    if not count or count == 0 then
		        count = 1
	        end
			healingDebuff = HEALING_DEBUFFS[spellId] * count
			if healingDebuff > healingDebuffMultiplier then
			    healingDebuffMultiplier = healingDebuff
			end
		end
	end
	-- Just in case make sure the modifier is a sane value
	if healingDebuffMultiplier > 1 then
	    healingDebuffMultiplier = 1
    end

    --
    -- Check for other healing buffs
    --
    -- Check for Guardian Spirit
    gsBuff = false
    gsHealModifier = 0.0
    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate, spellId = UnitAura("player", GUARDIAN_SPIRIT_BUFF)
    if name then
        gsBuff = true
        gsHealModifier = guardianSpiritHealBuff
    end

    self:UpdateMinHeal("CheckAura", "player")
end

function BloodShieldTracker:UpdateShieldBarVisibility()
	if self.statusbar then
		local show = self.db.profile.status_bar_shown
		if not show then
			self.statusbar:SetStatusBarTexture("")
			self.statusbar.bg:SetTexture("")
			self.statusbar.border:Hide()
		else
			self:UpdateShieldBarTexture()
			self:UpdateShieldBarBorder()
		end
	end
end

function BloodShieldTracker:UpdateDamageBarVisibility()
	if self.damagebar then
		local show = self.db.profile.estheal_bar_shown
		if not show then
			self.damagebar:SetStatusBarTexture("")
			self.damagebar.bg:SetTexture("")
			self.damagebar.border:Hide()
		else
			self:UpdateDamageBarTexture()
			self:UpdateDamageBarBorder()
		end
	end
end

function BloodShieldTracker:UpdatePWSBarVisibility()
	if self.pwsbar then
		local show = self.db.profile.pwsbar_shown
		if not show then
			self.pwsbar:SetStatusBarTexture("")
			self.pwsbar.bg:SetTexture("")
			self.pwsbar.border:Hide()
		else
			self:UpdatePWSBarTexture()
			self:UpdatePWSBarBorder()
		end
	end
end

function BloodShieldTracker:UpdateIllumBarVisibility()
	if self.illumbar then
		local show = self.db.profile.illumbar_shown
		if not show then
			self.illumbar:SetStatusBarTexture("")
			self.illumbar.bg:SetTexture("")
			self.illumbar.border:Hide()
		else
			self:UpdateIllumBarTexture()
			self:UpdateIllumBarBorder()
		end
	end
end

-- show/hide borders
function BloodShieldTracker:UpdateShieldBarBorder()
	if self.statusbar then
		if self.db.profile.status_bar_border then
			self.statusbar.border:Show()
		else
			self.statusbar.border:Hide()
		end
	end
end
function BloodShieldTracker:UpdateDamageBarBorder()
	if self.damagebar then
		if self.db.profile.estheal_bar_border then
			self.damagebar.border:Show()
		else
			self.damagebar.border:Hide()
		end
	end
end
function BloodShieldTracker:UpdatePWSBarBorder()
	if self.pwsbar then
		if self.db.profile.pwsbar_border then
			self.pwsbar.border:Show()
		else
			self.pwsbar.border:Hide()
		end
	end
end
function BloodShieldTracker:UpdateIllumBarBorder()
	if self.illumbar then
		if self.db.profile.illumbar_border then
			self.illumbar.border:Show()
		else
			self.illumbar.border:Hide()
		end
	end
end

-- Update Status bar status texture
function BloodShieldTracker:UpdateShieldBarTexture()
	if self.statusbar then
		local bt = LSM:Fetch("statusbar",self.db.profile.status_bar_texture)
		self.statusbar:SetStatusBarTexture(bt)
		self.statusbar.bg:SetTexture(bt)
	    self.statusbar:GetStatusBarTexture():SetHorizTile(false)
	    self.statusbar:GetStatusBarTexture():SetVertTile(false)
		self:UpdateShieldBarGraphics()
	end
end
-- Update EstHeal bar status texture
function BloodShieldTracker:UpdateDamageBarTexture()
	if self.damagebar then
		local bt = LSM:Fetch("statusbar",self.db.profile.estheal_bar_texture)
		self.damagebar:SetStatusBarTexture(bt)
		self.damagebar.bg:SetTexture(bt)
	    self.damagebar:GetStatusBarTexture():SetHorizTile(false)
	    self.damagebar:GetStatusBarTexture():SetVertTile(false)
		self:UpdateDamageBarColors(true)
	end
end
function BloodShieldTracker:UpdatePWSBarTexture()
	if self.pwsbar then
		local bt = LSM:Fetch("statusbar",self.db.profile.pwsbar_texture)
		self.pwsbar:SetStatusBarTexture(bt)
		self.pwsbar.bg:SetTexture(bt)
	    self.pwsbar:GetStatusBarTexture():SetHorizTile(false)
	    self.pwsbar:GetStatusBarTexture():SetVertTile(false)
		self:UpdatePWSBarGraphics()
	end
end
function BloodShieldTracker:UpdateIllumBarTexture()
	if self.illumbar then
		local bt = LSM:Fetch("statusbar",self.db.profile.illumbar_texture)
		self.illumbar:SetStatusBarTexture(bt)
		self.illumbar.bg:SetTexture(bt)
	    self.illumbar:GetStatusBarTexture():SetHorizTile(false)
	    self.illumbar:GetStatusBarTexture():SetVertTile(false)
		self:UpdateIllumBarGraphics()
	end
end


function BloodShieldTracker:UpdateShieldBarGraphics()
    if self.statusbar then
        if self.db.profile.shield_bar_show_time then
            self.statusbar.time:Show()
        else
            self.statusbar.time:Hide()
        end
        
        self.statusbar.time:SetPoint(self.db.profile.shield_bar_time_pos or "RIGHT")

        local bc = self.db.profile.status_bar_color
        self.statusbar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
        local bgc = self.db.profile.status_bar_bgcolor
        self.statusbar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
        local tc = self.db.profile.status_bar_textcolor
        self.statusbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
        self.statusbar.time:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    end
end

function BloodShieldTracker:UpdateDamageBarColors(min)
    if min then
        local bc = self.db.profile.estheal_bar_min_color
        self.damagebar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
        local bgc = self.db.profile.estheal_bar_min_bgcolor
        self.damagebar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
        local tc = self.db.profile.estheal_bar_min_textcolor
        self.damagebar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    else
        local bc = self.db.profile.estheal_bar_opt_color
        self.damagebar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
        local bgc = self.db.profile.estheal_bar_opt_bgcolor
        self.damagebar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
        local tc = self.db.profile.estheal_bar_opt_textcolor
        self.damagebar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    end
end

function BloodShieldTracker:UpdatePWSBarGraphics()
    if self.pwsbar then
        local bc = self.db.profile.pwsbar_color
        self.pwsbar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
        local bgc = self.db.profile.pwsbar_bgcolor
        self.pwsbar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
        local tc = self.db.profile.pwsbar_textcolor
        self.pwsbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    end
end

function BloodShieldTracker:UpdateIllumBarGraphics()
    if self.illumbar then
        local bc = self.db.profile.illumbar_color
        self.illumbar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
        local bgc = self.db.profile.illumbar_bgcolor
        self.illumbar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
        local tc = self.db.profile.illumbar_textcolor
        self.illumbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    end
end

function BloodShieldTracker:ShieldBarLock(locked)
    if self.statusbar then
        self.statusbar.lock = locked
        if locked then
            self.statusbar:EnableMouse(false)
        else
            self.statusbar:EnableMouse(true)
        end
    end
end

function BloodShieldTracker:EstHealBarLock(locked)
    if self.damagebar then
        self.damagebar.lock = locked
        if locked then
            self.damagebar:EnableMouse(false)
        else
            self.damagebar:EnableMouse(true)
        end
    end
end

function BloodShieldTracker:PWSBarLock(locked)
    if self.pwsbar then
        self.pwsbar.lock = locked
        if locked then
            self.pwsbar:EnableMouse(false)
        else
            self.pwsbar:EnableMouse(true)
        end
    end
end

function BloodShieldTracker:IllumBarLock(locked)
    if self.illumbar then
        self.illumbar.lock = locked
        if locked then
            self.illumbar:EnableMouse(false)
        else
            self.illumbar:EnableMouse(true)
        end
    end
end

function BloodShieldTracker:CreateShieldBar()
    local statusbar = CreateFrame("StatusBar", "BloodShieldTracker_StatusBar", UIParent)
    statusbar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.shield_bar_x, self.db.profile.shield_bar_y)
	statusbar:SetScale(self.db.profile.status_bar_scale)
    statusbar:SetOrientation("HORIZONTAL")
    statusbar:SetWidth(self.db.profile.status_bar_width)
    statusbar:SetHeight(self.db.profile.status_bar_height)
	local bt = LSM:Fetch("statusbar",self.db.profile.status_bar_texture)
    statusbar:SetStatusBarTexture(bt)
    statusbar:GetStatusBarTexture():SetHorizTile(false)
    statusbar:GetStatusBarTexture():SetVertTile(false)
    local bc = self.db.profile.status_bar_color
    statusbar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
    statusbar.bg = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.bg:SetTexture(bt)
    statusbar.bg:SetAllPoints(true)
    local bgc = self.db.profile.status_bar_bgcolor
    statusbar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
    statusbar.border = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.border:SetPoint("CENTER")
    statusbar.border:SetWidth(statusbar:GetWidth()+9)
    statusbar.border:SetHeight(statusbar:GetHeight()+8)
    statusbar.border:SetTexture("Interface\\Tooltips\\UI-StatusBar-Border")
	if not self.db.profile.status_bar_border then
		statusbar.border:Hide()
	end
	local font = LSM:Fetch("font",self.db.profile.font_face)
    statusbar.value = statusbar:CreateFontString(nil, "OVERLAY")
    statusbar.value:SetPoint("CENTER")
    statusbar.value:SetFont(font, self.db.profile.font_size, self:GetFontFlags())
    statusbar.value:SetJustifyH("CENTER")
    statusbar.value:SetShadowOffset(1, -1)
    local tc = self.db.profile.status_bar_textcolor
    statusbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    statusbar.lock = false

    statusbar.time = statusbar:CreateFontString(nil, "OVERLAY")
    statusbar.time:SetPoint(self.db.profile.shield_bar_time_pos or "RIGHT")
    statusbar.time:SetFont(font, self.db.profile.font_size, self:GetFontFlags())
    statusbar.time:SetJustifyH(self.db.profile.shield_bar_time_pos or "RIGHT")
    statusbar.time:SetShadowOffset(1, -1)
    statusbar.time:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    statusbar.time:SetText("0")
    if self.db.profile.shield_bar_show_time then
        statusbar.time:Show()
    else
        statusbar.time:Hide()
    end

    statusbar:SetMovable()
    statusbar:RegisterForDrag("LeftButton")
    statusbar:SetScript("OnDragStart",
        function(self,button)
			if not self.lock then
            	self:StartMoving()
			end
        end)
    statusbar:SetScript("OnDragStop",
        function(self)
            self:StopMovingOrSizing()
			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local x, y = self:GetCenter()
			x, y = x * scale, y * scale
			x = x - GetScreenWidth()/2
			y = y - GetScreenHeight()/2
			x = x / self:GetScale()
			y = y / self:GetScale()
			BloodShieldTracker.db.profile.shield_bar_x, BloodShieldTracker.db.profile.shield_bar_y = x, y
			self:SetUserPlaced(false);
        end)
    statusbar:EnableMouse(true)
    statusbar:Hide()
	statusbar.shield_curr = 0
	statusbar.shield_max = 0

    return statusbar
end

function BloodShieldTracker:CreatePWSBar()
    local pwsbar = CreateFrame("StatusBar", "BloodShieldTracker_Shield_PWS", UIParent)
    pwsbar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.pwsbar_x, self.db.profile.pwsbar_y)
	pwsbar:SetScale(self.db.profile.pwsbar_scale)
    pwsbar:SetOrientation("HORIZONTAL")
    pwsbar:SetWidth(self.db.profile.pwsbar_width)
    pwsbar:SetHeight(self.db.profile.pwsbar_height)
	local bt = LSM:Fetch("statusbar",self.db.profile.pwsbar_texture)
    pwsbar:SetStatusBarTexture(bt)
    pwsbar:GetStatusBarTexture():SetHorizTile(false)
    pwsbar:GetStatusBarTexture():SetVertTile(false)
    local bc = self.db.profile.pwsbar_color
    pwsbar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
    pwsbar.bg = pwsbar:CreateTexture(nil, "BACKGROUND")
    pwsbar.bg:SetTexture(bt)
    pwsbar.bg:SetAllPoints(true)
    local bgc = self.db.profile.pwsbar_bgcolor
    pwsbar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
    pwsbar.border = pwsbar:CreateTexture(nil, "BACKGROUND")
    pwsbar.border:SetPoint("CENTER")
    pwsbar.border:SetWidth(pwsbar:GetWidth()+9)
    pwsbar.border:SetHeight(pwsbar:GetHeight()+8)
    pwsbar.border:SetTexture("Interface\\Tooltips\\UI-StatusBar-Border")
	if not self.db.profile.pwsbar_border then
		pwsbar.border:Hide()
	end
	local font = LSM:Fetch("font",self.db.profile.font_face)
    pwsbar.value = pwsbar:CreateFontString(nil, "OVERLAY")
    pwsbar.value:SetPoint("CENTER")
    pwsbar.value:SetFont(font, self.db.profile.font_size, self:GetFontFlags())
    pwsbar.value:SetJustifyH("CENTER")
    pwsbar.value:SetShadowOffset(1, -1)
    local tc = self.db.profile.pwsbar_textcolor
    pwsbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    pwsbar.value:SetText("0")
    pwsbar.lock = false

    pwsbar:SetMovable()
    pwsbar:RegisterForDrag("LeftButton")
    pwsbar:SetScript("OnDragStart",
        function(self,button)
			if not self.lock then
            	self:StartMoving()
			end
        end)
    pwsbar:SetScript("OnDragStop",
        function(self)
            self:StopMovingOrSizing()
			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local x, y = self:GetCenter()
			x, y = x * scale, y * scale
			x = x - GetScreenWidth()/2
			y = y - GetScreenHeight()/2
			x = x / self:GetScale()
			y = y / self:GetScale()
			BloodShieldTracker.db.profile.pwsbar_x, BloodShieldTracker.db.profile.pwsbar_y = x, y
			self:SetUserPlaced(false);
        end)
    pwsbar:EnableMouse(true)
    pwsbar:SetMinMaxValues(0, 1)
    pwsbar:SetValue(1)
    pwsbar:Hide()

    return pwsbar
end

function BloodShieldTracker:CreateIllumBar()
    local illumbar = CreateFrame("StatusBar", "BloodShieldTracker_Shield_IllumHeal", UIParent)
    illumbar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.illumbar_x, self.db.profile.illumbar_y)
	illumbar:SetScale(self.db.profile.illumbar_scale)
    illumbar:SetOrientation("HORIZONTAL")
    illumbar:SetWidth(self.db.profile.illumbar_width)
    illumbar:SetHeight(self.db.profile.illumbar_height)
	local bt = LSM:Fetch("statusbar",self.db.profile.illumbar_texture)
    illumbar:SetStatusBarTexture(bt)
    illumbar:GetStatusBarTexture():SetHorizTile(false)
    illumbar:GetStatusBarTexture():SetVertTile(false)
    local bc = self.db.profile.illumbar_color
    illumbar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
    illumbar.bg = illumbar:CreateTexture(nil, "BACKGROUND")
    illumbar.bg:SetTexture(bt)
    illumbar.bg:SetAllPoints(true)
    local bgc = self.db.profile.illumbar_bgcolor
    illumbar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
    illumbar.border = illumbar:CreateTexture(nil, "BACKGROUND")
    illumbar.border:SetPoint("CENTER")
    illumbar.border:SetWidth(illumbar:GetWidth()+9)
    illumbar.border:SetHeight(illumbar:GetHeight()+8)
    illumbar.border:SetTexture("Interface\\Tooltips\\UI-StatusBar-Border")
	if not self.db.profile.illumbar_border then
		illumbar.border:Hide()
	end
	local font = LSM:Fetch("font",self.db.profile.font_face)
    illumbar.value = illumbar:CreateFontString(nil, "OVERLAY")
    illumbar.value:SetPoint("CENTER")
    illumbar.value:SetFont(font, self.db.profile.font_size, self:GetFontFlags())
    illumbar.value:SetJustifyH("CENTER")
    illumbar.value:SetShadowOffset(1, -1)
    local tc = self.db.profile.illumbar_textcolor
    illumbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    illumbar.value:SetText("0")
    illumbar.lock = false

    illumbar:SetMovable()
    illumbar:RegisterForDrag("LeftButton")
    illumbar:SetScript("OnDragStart",
        function(self,button)
			if not self.lock then
            	self:StartMoving()
			end
        end)
    illumbar:SetScript("OnDragStop",
        function(self)
            self:StopMovingOrSizing()
			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local x, y = self:GetCenter()
			x, y = x * scale, y * scale
			x = x - GetScreenWidth()/2
			y = y - GetScreenHeight()/2
			x = x / self:GetScale()
			y = y / self:GetScale()
			BloodShieldTracker.db.profile.illumbar_x, BloodShieldTracker.db.profile.illumbar_y = x, y
			self:SetUserPlaced(false);
        end)
    illumbar:EnableMouse(true)
    illumbar:SetMinMaxValues(0, 1)
    illumbar:SetValue(1)
    illumbar:Hide()

    return illumbar
end

function BloodShieldTracker:CreateEstimateBar()
    local statusbar = CreateFrame("StatusBar", "BloodShieldTracker_DamageBar", UIParent)
	local scale = self.db.profile.estheal_bar_scale
    statusbar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.est_heal_x, self.db.profile.est_heal_y)
	statusbar:SetScale(scale)
    statusbar:SetWidth(self.db.profile.damage_bar_width)
    statusbar:SetHeight(self.db.profile.damage_bar_height)
	local bt = LSM:Fetch("statusbar",self.db.profile.estheal_bar_texture)
   	statusbar:SetStatusBarTexture(bt)
    statusbar:GetStatusBarTexture():SetHorizTile(false)
    statusbar:GetStatusBarTexture():SetVertTile(false)
    local bc = self.db.profile.estheal_bar_min_color
    statusbar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
    statusbar.bg = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.bg:SetTexture(bt)
    statusbar.bg:SetAllPoints(true)
    local bgc = self.db.profile.estheal_bar_min_bgcolor
    statusbar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
    statusbar.border = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.border:SetPoint("CENTER")
    statusbar.border:SetWidth(statusbar:GetWidth()+9)
    statusbar.border:SetHeight(statusbar:GetHeight()+8)
    statusbar.border:SetTexture("Interface\\Tooltips\\UI-StatusBar-Border")
	if not self.db.profile.estheal_bar_border then
		statusbar.border:Hide()
	end
    statusbar.value = statusbar:CreateFontString(nil, "OVERLAY")
    statusbar.value:SetPoint("CENTER")
	local font = LSM:Fetch("font",self.db.profile.font_face)
    statusbar.value:SetFont(font, self.db.profile.font_size, self:GetFontFlags())
    statusbar.value:SetJustifyH("CENTER")
    statusbar.value:SetShadowOffset(1, -1)
    local tc = self.db.profile.estheal_bar_min_textcolor
    statusbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    statusbar.lock = false
    statusbar:SetMovable()
    statusbar:RegisterForDrag("LeftButton")
    statusbar:SetScript("OnDragStart",
        function(self,button)
			if not self.lock then
            	self:StartMoving()
			end
        end)
    statusbar:SetScript("OnDragStop",
        function(self)
            self:StopMovingOrSizing()
			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local x, y = self:GetCenter()
			x, y = x * scale, y * scale
			x = x - GetScreenWidth()/2
			y = y - GetScreenHeight()/2
			x = x / self:GetScale()
			y = y / self:GetScale()
			BloodShieldTracker.db.profile.est_heal_x, BloodShieldTracker.db.profile.est_heal_y = x, y
			self:SetUserPlaced(false);
        end)

    statusbar:SetMinMaxValues(0,1)
    statusbar:SetValue(1)

    local text = ""
    if self.db.profile.estimate_bar_mode == "BS" then
        text = L["EstimateBarBSText"]
    else
        text = L["HealBarText"]
    end
    statusbar.value:SetText(healBarFormat:format(text, dsHealMin))
    statusbar:EnableMouse(true)
    statusbar:Hide()
    return statusbar
end
