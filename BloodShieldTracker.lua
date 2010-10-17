local BloodShieldTracker = LibStub("AceAddon-3.0"):NewAddon("BloodShieldTracker", "AceConsole-3.0", "AceEvent-3.0","AceTimer-3.0")

local ADDON_NAME = ...
local ADDON_VERSION = "@project-version@"

-- Local versions for performance
local tinsert, tremove, tgetn = table.insert, table.remove, table.getn
local pairs, ipairs = pairs, ipairs
local floor, ceil = math.floor, math.ceil

BloodShieldTracker.playerName = UnitName("player")
BloodShieldTracker.statusbar = nil
BloodShieldTracker.damagebar = nil

local updateTimer = nil
local lastSeconds = 5
local damageTaken = {}
local recentDamage = 0
local removeList = {}

local numShields = 0
local numMinShields = 0
local numRemovedShields = 0
local numRefreshedShields = 0
local minShieldMaxValue = 0
local maxShieldMaxValue = 0
local totalShieldMaxValue = 0
local minShieldUsedPerc = nil
local maxShieldUsedPerc = 0
local totalShieldUsedPerc = 0

local lastDSSuccess = nil
local masteryRating = 0

local GREEN = "|cff00ff00"
local YELLOW = "|cffffff00"
local BLUE = "|cff0198e1"
local ORANGE = "|cffff9933"
local statusBarFormat = "%d/%d (%d%%)"
local healBarFormat = "%s: %d"

local L = LibStub("AceLocale-3.0"):GetLocale("BloodShieldTracker", true)
local LDB = LibStub("LibDataBroker-1.1")
local LibQTip = LibStub("LibQTip-1.0")
local icon = LibStub("LibDBIcon-1.0")
-- Load LibsharedMedia we package it with the addon so it should be available
local LSM = LibStub:GetLibrary("LibSharedMedia-3.0")

local DS_SPELL_DMG = (GetSpellInfo(49998))
local DS_SPELL_HEAL = (GetSpellInfo(45470))
local BS_SPELL = (GetSpellInfo(77535))
local IMP_DS_TALENT = (GetSpellInfo(81138))
local ImpDSModifier = 1
local HasVampTalent = false
local dsHealModifier = 0.3
local shieldPerMasteryPoint = 6.25
local dsHealMin = 0

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
local VB_BUFF = (GetSpellInfo(55233))
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
local shieldDataHdr = ORANGE..L["Blood Shield Data"]
local shieldDataLine1 = YELLOW..L["Shields Total/Refreshed/Removed:"]
local shieldDataLine2 = YELLOW..L["Number of Minimum Shields:"]
local shieldDataMinShld = "%d (%d%%)"
local shieldDataLine1Fmt = "%d / %d / %d"

local shieldMaxValueHdr = ORANGE..L["Blood Shield Max Value"]
local shieldMaxValueLine1 = YELLOW..L["Min - Max / Avg:"]
local rangeWithAvgFmt = "%d - %d / %d"
local rangeWithAvgPercFmt = "%.1f%% - %.1f%% / %.1f%%"

local shieldUsageHdr = ORANGE..L["Blood Shield Usage"]
local shieldUsageLine1 = YELLOW..L["Usage Min - Max / Avg:"]
local percentFormat = "%.1f%%"

function Broker.obj:OnEnter()
	local tooltip = LibQTip:Acquire("BloodShieldTrackerTooltip", 2, "LEFT", "RIGHT")
	self.tooltip = tooltip 

    local percentMinimum = 0
    local avgShieldMaxValue
    local avgShieldUsedPerc
    if numShields > 0 then
        percentMinimum = numMinShields / numShields * 100
        avgShieldMaxValue = totalShieldMaxValue / numShields
        avgShieldUsedPerc = totalShieldUsedPerc / numShields
    end

    tooltip:AddHeader(addonHdr:format(GetAddOnMetadata(ADDON_NAME,"Title"), ADDON_VERSION))
    tooltip:AddLine()
    tooltip:AddLine(L["Shift + Left-Click to reset."], "", 1, 1, 1)
    tooltip:AddLine()

    tooltip:AddLine(shieldDataHdr)
    tooltip:AddSeparator(1)
    tooltip:AddLine(shieldDataLine1, 
        shieldDataLine1Fmt:format(numShields,numRefreshedShields,numRemovedShields))
    tooltip:AddLine(shieldDataLine2, 
        shieldDataMinShld:format(numMinShields, percentMinimum))

    tooltip:AddLine()

    tooltip:AddLine(shieldMaxValueHdr)
    tooltip:AddSeparator(1)
    tooltip:AddLine(shieldMaxValueLine1, 
        rangeWithAvgFmt:format(
            minShieldMaxValue, maxShieldMaxValue, avgShieldMaxValue or 0))

    tooltip:AddLine()

    tooltip:AddLine(shieldUsageHdr)
    tooltip:AddSeparator(1)
    tooltip:AddLine(shieldUsageLine1, 
        rangeWithAvgPercFmt:format(
            minShieldUsedPerc or 0, maxShieldUsedPerc, avgShieldUsedPerc or 0))

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
        status_bar_enabled = true,
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
		estheal_bar_border = true,
		estheal_bar_shown = true,
		status_bar_shown = true,
		est_heal_x = 0, est_heal_y = -40,
		shield_bar_x = 0, shield_bar_y = 0,
		estheal_bar_scale = 1,
		status_bar_scale = 1,
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
        				config_mode = {
        					name = L["Config Mode"],
        					desc = L["Toggle config mode"],
        					type = "execute",
        					order = 40,
        					func = function()
        					    configMode = not configMode
        						if configMode then
        							self.statusbar:Show()
        							self.damagebar:Show()
        						else
        							self.statusbar:Hide()
        							if self.damagebar.hideooc and not InCombatLockdown() then
        							    self.damagebar:Hide()
                                    end
        						end
        					end,
        				},
					    fonts = {
					        order = 40,
					        type = "header",
					        name = L["Font"],
					    },
        				bar_font_size = {
        					order = 50,
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
        					order = 60,
        					type = "select",
        					name = L["Font"],
        					desc = L["Font to use."],
        					values = LSM:HashTable("font"),
        					dialogControl = 'LSM30_Font',
        					get = function() return self.db.profile.font_face end,
        					set = function(info, val) self.db.profile.font_face = val; BloodShieldTracker:ResetFonts() end
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
        					desc = L["Lock the shield bar from moving."],
        					type = "toggle",
        					order = 20,
        					set = function(info, val) self.db.profile.lock_status_bar = val 
        						if BloodShieldTracker.statusbar then
        							BloodShieldTracker.statusbar.lock = val
        						end
        					end,
                            get = function(info) return self.db.profile.lock_status_bar end,
        				},
                        dimensions = {
                            order = 29,
                            type = "header",
                            name = L["Dimensions"],
                        },
        				status_bar_width = {
        					order = 30,
        					name = L["Width"],
        					desc = L["Change the width of the blood shield bar."],	
        					type = "range",
        					min = 50,
        					max = 300,
        					step = 1,
        					set = function(info, val) self.db.profile.status_bar_width = val 
        						BloodShieldTracker.statusbar:SetWidth(val)
        						BloodShieldTracker.statusbar.border:SetWidth(val+9)
        					end,
        					get = function(info, val) return self.db.profile.status_bar_width end,
        				},
        				status_bar_height = {
        					order = 40,
        					name = L["Height"],
        					desc = L["Change the height of the blood shield bar."],
        					type = "range",
        					min = 10,
        					max = 30,
        					step = 1,
        					set = function(info, val) self.db.profile.status_bar_height = val 
        						BloodShieldTracker.statusbar:SetHeight(val)
        						BloodShieldTracker.statusbar.border:SetHeight(val + 8)
        					end,
        					get = function(info, val) return self.db.profile.status_bar_height end,					
        				},
        				status_bar_scaling = {
        					order = 45,
        					name = L["Scale"],
        					desc = L["ScaleDesc"],
        					type = "range",
        					min = 0.1,
        					max = 3,
        					step = 0.1,
        					get = function() return self.db.profile.status_bar_scale end,
        					set = function(info, val) self.db.profile.status_bar_scale = val; self.statusbar:SetScale(val); end
        				},
                        colors = {
                            order = 49,
                            type = "header",
                            name = L["Colors"],
                        },
        				status_bar_textcolor = {
        					order = 50,
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
        					order = 60,
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
        					order = 70,
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
                            order = 79,
                            type = "header",
                            name = L["Appearance"],
                        },
        				status_bar_texture_opt = {
        					order = 80,
        					name = L["Texture"],
        					desc = L["StatusBarTextureDesc"],
        					type = "select",
        					values = LSM:HashTable("statusbar"),
        					dialogControl = 'LSM30_Statusbar',
        					get = function() return self.db.profile.status_bar_texture	end,
        					set = function(info, val) self.db.profile.status_bar_texture = val; BloodShieldTracker:UpdateShieldBarTexture()	end
        				},
        				status_bar_border_visible_opt = {
        					order = 90,
        					name = L["ShowBorder"],
        					desc = L["ShowBorderDesc"],
        					type = "toggle",
        					get = function() return self.db.profile.status_bar_border end,
        					set = function(info, val) self.db.profile.status_bar_border = val; self:UpdateShieldBarBorder() end,
        				},
        				status_bar_visible_opt = {
        					order = 100,
        					name = L["ShowBar"],
        					desc = L["ShowBarDesc"],
        					type = "toggle",
        					get = function() return self.db.profile.status_bar_shown end,
        					set = function(info,val) self.db.profile.status_bar_shown = val; self:UpdateShieldBarVisiblity() end,
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
        						    BloodShieldTracker.damagebar:Hide()
        						end
        					end,
                            get = function(info) return self.db.profile.damage_bar_enabled end,
        				},
        				lock_estheal_bar = {
        					name = L["Lock bar"],
        					desc = L["Lock the estimated healing bar from moving."],
        					type = "toggle",
        					order = 20,
        					set = function(info, val) self.db.profile.lock_damage_bar = val 
        						if BloodShieldTracker.damagebar then
        							BloodShieldTracker.damagebar.lock = val
        						end					
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
        						        elseif self:IsEnabled() then
        						            self.damagebar:Show()
        					            end
        					        end
        						end					
        					end,
                            get = function(info) return self.db.profile.hide_damage_bar_ooc end,
        				},
                        dimensions = {
                            order = 39,
                            type = "header",
                            name = L["Dimensions"],
                        },
        				estheal_bar_width = {
        					order = 40,
        					name = L["Width"],
        					desc = L["Change the width of the estimated healing bar."],	
        					type = "range",
        					min = 10,
        					max = 200,
        					set = function(info, val) self.db.profile.damage_bar_width = val 
        						BloodShieldTracker.damagebar:SetWidth(val)
        						BloodShieldTracker.damagebar.border:SetWidth(val+9)
        					end,
        					get = function(info, val) return self.db.profile.damage_bar_width end,
        				},
        				estheal_bar_height = {
        					order = 50,
        					name = L["Height"],
        					desc = L["Change the height of the estimated healing bar."],	
        					type = "range",
        					min = 8,
        					max = 30,
        					step = 1,
        					set = function(info, val) self.db.profile.damage_bar_height = val 
        						BloodShieldTracker.damagebar:SetHeight(val)
        						BloodShieldTracker.damagebar.border:SetHeight(val + 8)
        					end,
        					get = function(info, val) return self.db.profile.damage_bar_height end,
        				},
        				estheal_bar_scaling = {
        					order = 55,
        					name = L["Scale"],
        					desc = L["ScaleDesc"],
        					type = "range",
        					min = 0.1,
        					max = 3,
        					step = 0.1,
        					get = function() return self.db.profile.estheal_bar_scale end,
        					set = function(info, val) self.db.profile.estheal_bar_scale = val; self.damagebar:SetScale(val); end
        				},
                        colorsMinimum = {
                            order = 59,
                            type = "header",
                            name = L["Colors for Minimum Heal"],
                        },
        				estheal_bar_min_textcolor = {
        					order = 60,
        					name = L["Minimum Text Color"],
        					desc = L["EstHealBarMinTextColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_min_textcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_min_textcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				estheal_bar_min_color = {
        					order = 70,
        					name = L["Minimum Bar Color"],
        					desc = L["EstHealBarMinColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_min_color
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_min_color
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				estheal_bar_min_bgcolor = {
        					order = 80,
        					name = L["Minimum Bar Background Color"],
        					desc = L["EstHealBarMinBackgroundColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_min_bgcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_min_bgcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
                        colorsOptimal = {
                            order = 89,
                            type = "header",
                            name = L["Colors for Optimal Heal"],
                        },
        				estheal_bar_opt_textcolor = {
        					order = 90,
        					name = L["Optimal Text Color"],
        					desc = L["EstHealBarOptTextColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_opt_textcolor
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_opt_textcolor
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
        				estheal_bar_opt_color = {
        					order = 100,
        					name = L["Optimal Bar Color"],
        					desc = L["EstHealBarOptColor_OptionDesc"],
        					type = "color",
        					hasAlpha = true,
        					set = function(info, r, g, b, a)
        					    local c = self.db.profile.estheal_bar_opt_color
        					    c.r, c.g, c.b, c.a = r, g, b, a
        					    if self.damagebar then
        					        self:UpdateDamageBarColors(self.damagebar.minheal or true)
        					    end
        					end,
        					get = function(info)
        				        local c = self.db.profile.estheal_bar_opt_color
        					    return c.r, c.g, c.b, c.a
        					end,					
        				},
                        appearance = {
                            order = 109,
                            type = "header",
                            name = L["Appearance"],
                        },
        				estheal_bar_texture_opt = {
        					order = 110,
        					name = L["Texture"],
        					desc = L["StatusBarTextureDesc"],
        					type = "select",
        					values = LSM:HashTable("statusbar"),
        					dialogControl = 'LSM30_Statusbar',
        					get = function() return self.db.profile.estheal_bar_texture	end,
        					set = function(info, val) self.db.profile.estheal_bar_texture = val; BloodShieldTracker:UpdateDamageBarTexture() end
        				},
        				estheal_bar_border_visible_opt = {
        					order = 120,
        					name = L["ShowBorder"],
        					desc = L["ShowBorderDesc"],
        					type = "toggle",
        					get = function() return self.db.profile.estheal_bar_border end,
        					set = function(info, val) self.db.profile.estheal_bar_border = val; self:UpdateDamageBarBorder() end,
        				},
        				estheal_bar_visible_opt = {
        					order = 130,
        					name = L["ShowBar"],
        					desc = L["ShowBarDesc"],
        					type = "toggle",
        					get = function() return self.db.profile.estheal_bar_shown end,
        					set = function(info,val) self.db.profile.estheal_bar_shown = val; self:UpdateDamageBarVisiblity() end,
        				},
        			}
        		}
            }
        }
	options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    end
    return options
end

function BloodShieldTracker:ChatCommand(input)
    if not input or input:trim() == "" then
        self:ShowOptions()
    else
        --LibStub("AceConfigCmd-3.0").HandleCommand(BloodShieldTracker, "bst", "BloodShieldTracker", input)
    end
end

local isDK = nil
local IsBloodTank = true

function BloodShieldTracker:OnInitialize()
    -- Load the settings
    self.db = LibStub("AceDB-3.0"):New("BloodShieldTrackerDB", defaults, "Default")
	-- Create our bars
    self.statusbar = self:CreateStatusBar()
	self.statusbar.lock = self.db.profile.lock_status_bar
    self.statusbar.shield_curr = 0
    self.damagebar = self:CreateDamageBar()
	self.damagebar.lock = self.db.profile.lock_damage_bar
	self.damagebar.hideooc = self.db.profile.hide_damage_bar_ooc
	self.damagebar.minheal = true
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
    	self.damagebar.lock = self.db.profile.lock_damage_bar
    	self.damagebar.hideooc = self.db.profile.hide_damage_bar_ooc
		self:UpdateDamageBarTexture()
		self:UpdateDamageBarBorder()
		self:UpdateDamageBarVisiblity()
		self:UpdateDamageBarColors()
	end
	if self.statusbar then
		self.statusbar:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.shield_bar_x, self.db.profile.shield_bar_y)
    	self.statusbar.lock = self.db.profile.lock_status_bar
		self:UpdateShieldBarTexture()
		self:UpdateShieldBarBorder()
		self:UpdateShieldBarVisiblity()
		self:UpdateShieldBarGraphics()
	end
	self:ResetFonts()
	self:ResetStats()
end

function BloodShieldTracker:ResetFonts()
	local fontName, fontHeight, fontFlags = BloodShieldTracker.statusbar.value:GetFont()
	local ff = LSM:Fetch("font",self.db.profile.font_face)
	local fh = self.db.profile.font_size
	BloodShieldTracker.statusbar.value:SetFont(ff,fh,fontFlags)
	BloodShieldTracker.statusbar.value:SetText(BloodShieldTracker.statusbar.value:GetText())
	BloodShieldTracker.damagebar.value:SetFont(ff,fh,fontFlags)						
	BloodShieldTracker.damagebar.value:SetText(BloodShieldTracker.damagebar.value:GetText())
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
	end
end

function BloodShieldTracker:OnEnable()
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
    if self:IsEnabled() and (not self.damagebar.hideooc or InCombatLockdown()) then
        self.damagebar:Show()
    end
	self:UpdateDamageBarVisiblity()
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
        	else
        		IsBloodTank = false
        	end
        else
            if self.db.profile.verbose then
                self:Print(L["Could not determine talents."])
            end
        end
    	if HasVampTalent then
        	self:CheckGlyphs()
    	end
    else
        IsBloodTank = false
	end

	if self:IsEnabled() then
	    self:Load()
    else
        self:Unload()
    end
end

function BloodShieldTracker:IsEnabled()
    if IsBloodTank or (isDK and not self.db.profile.enable_only_for_blood) then
        return true
    else
        return false
    end
end

function BloodShieldTracker:CheckGlyphs()
    vbGlyphed = false
	if not HasVampTalent then return end -- Dont bother with glyph check if he doesnt have the talent
    for id = 1, GetNumGlyphSockets() do
        local enabled, glyphType, glyphTooltipIndex, 
            glyphSpell, iconFilename = GetGlyphSocketInfo(id, nil)
        if enabled and glyphSpell == VB_GLYPH_ID then
            vbGlyphed = true
        end
    end
end

function BloodShieldTracker:UpdateMinHeal(event,unit)
	if unit == "player" then
		dsHealMin = ceil(
		    (UnitHealthMax("player") * 0.1 * (1+iccBuffAmt) * (1+vbHealingInc))-0.5)
		if idle then
			self.damagebar.value:SetText(healBarFormat:format(L["HealBarText"], dsHealMin))
		end
	end
end

function BloodShieldTracker:PLAYER_REGEN_DISABLED()
	-- Once combat stats, update the damage bar.
	idle = false
	if self.damagebar and self:IsEnabled() then
    	updateTimer = self:ScheduleRepeatingTimer("UpdateDamageBar", 0.5)
	    self.damagebar:Show()
    end
end

function BloodShieldTracker:PLAYER_REGEN_ENABLED()
	-- cancel timer before hand
	if updateTimer then
        self:CancelTimer(updateTimer)
    end
	idle = true 
    self.damagebar.value:SetText(healBarFormat:format(L["HealBarText"], dsHealMin))
    self.damagebar.minheal = true
    self:UpdateDamageBarColors(true)
    self.damagebar:SetMinMaxValues(0, 1)
    self.damagebar:SetValue(1)
    
    if self.damagebar.hideooc then
        self.damagebar:Hide()
    end
end

function BloodShieldTracker:PLAYER_DEAD()
    -- Just in case, hide the BS bar if the player dies
    self:CheckAuras()
    self.statusbar:Hide()
    -- Hide the heal bar if configured to do so for OOC
    if self.damagebar.hideooc then
        self.damagebar:Hide()
    end
end

function BloodShieldTracker:UpdateDamageBar()
    if not self.db.profile.damage_bar_enabled then return end
    
    local recentDamage = self:GetRecentDamageTaken()

    local predictedHeal = recentDamage * dsHealModifier * ImpDSModifier
    local minimumHeal = dsHealMin
	if recentDamage < minimumHeal then
    	self.damagebar.value:SetText(healBarFormat:format(L["HealBarText"], minimumHeal))
	else
    	self.damagebar.value:SetText(healBarFormat:format(L["HealBarText"], predictedHeal))		
	end

    self.damagebar:SetMinMaxValues(0, minimumHeal)

    if predictedHeal > minimumHeal then
        self.damagebar.minheal = false
        self:UpdateDamageBarColors(false)
        self.damagebar:SetValue(minimumHeal)        
    else
        self.damagebar.minheal = true
        self:UpdateDamageBarColors(true)
        self.damagebar:SetValue(predictedHeal)
    end
end

function BloodShieldTracker:UpdateShieldBar(damage)
    if not IsBloodTank then return end

	self.statusbar.shield_curr = self.statusbar.shield_curr - damage
	if self.statusbar.shield_curr < 0 and self.db.profile.verbose then
        local badShieldValueFmt = "Bad shield value [Cur=%d, Dmg=%d, Max=%d]"
        self:Print(badShieldValueFmt:format(
            self.statusbar.shield_curr, damage, self.statusbar.shield_max))
    end
	self.statusbar:SetValue(self.statusbar.shield_curr)
	local diff
	if self.statusbar.shield_max > 0 then
	    diff = ceil((self.statusbar.shield_curr/self.statusbar.shield_max*100)-0.5)
    else
        diff = 0
    end
	self.statusbar.value:SetText(statusBarFormat:format(self.statusbar.shield_curr, self.statusbar.shield_max, diff))
end

function BloodShieldTracker:GetRecentDamageTaken(timestamp)
    local damage = 0
    
    if not timestamp then
        timestamp = time()
    end

    for i, v in ipairs(damageTaken) do
        if v and v[1] and v[2] then
            if timestamp - v[1] <= lastSeconds then
                damage = damage + v[2]
            end
        end
    end
    
    recentDamage = damage
    return damage
end

function BloodShieldTracker:AddDamageTaken(timestamp, damage)
    -- Add the new damage taken data
    tinsert(damageTaken, {timestamp,damage})

    wipe(removeList)

    -- Remove any data older than lastSeconds
    for i, v in ipairs(damageTaken) do
        if v and v[1] then
            if timestamp - v[1] > lastSeconds then
                tinsert(removeList, i)
            end
        end
    end
    
    for i, v in ipairs(removeList) do
        if v then
            tremove(damageTaken, v)
        end
    end
    
    self:UpdateDamageBar()
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

function BloodShieldTracker:COMBAT_LOG_EVENT_UNFILTERED(...)
    local event, timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, 
        dstName, dstFlags, param9, param10, param11, param12, param13, param14,
        param15, param16, param17, param18, param19, param20 = ...
    
    if not event or not eventtype or not dstName then return end

    if eventtype:find("_DAMAGE") and dstName == self.playerName then
        if eventtype:find("SWING_") and param9 then
            local damage, absorb = param9, param14 or 0

            if self.db.profile.verbose then
                local swingDmgFmt = "Swing Damage for %d [%d absorbed]"
                self:Print(swingDmgFmt:format(damage, absorb))
            end

            self:AddDamageTaken(timestamp, damage)
            if absorb > 0 then
                self:UpdateShieldBar(absorb)
            end
        elseif eventtype:find("SPELL_") or eventtype:find("RANGE_") then
            local type
            if eventtype:find("SPELL_") then type = "Spell" end
            if eventtype:find("RANGE_") then type = "Range" end        
            local damage, absorb, school = param12 or 0, param17 or 0, param14 or 0
            local spellName = param10 or "n/a"
            local schoolName = self:GetSpellSchool(school) or "N/A"

            self:AddDamageTaken(timestamp, damage)

            if self.db.profile.verbose then
                local spellDmgFmt = "%s Damage (%s-%s,%d) for %d [%d absorbed]"
                self:Print(spellDmgFmt:format(
                    type, spellName, schoolName, school, damage, absorb))
            end

            -- If it is physical, then the shield absorbs it.
            if school == 1 and absorb > 0 then
                self:UpdateShieldBar(absorb)
            end            
        end
    end    

    if eventtype:find("_MISSED") and dstName == self.playerName then
        if eventtype == "SWING_MISSED" then
            if param9 and param9 == "ABSORB" then
    			local damage = param10 or 0

                if self.db.profile.verbose then
                    local absorbFmt = "Absorbed swing for %d"
                    self:Print(absorbFmt:format(damage))
                end

                self:UpdateShieldBar(damage)
            end
        elseif eventtype:find("SPELL_") then
            if param12 and param12 == 'ABSORB' then
                local damage = param13
                local spellName, school = param10 or "n/a", param11 or 0
                local schoolName = self:GetSpellSchool(school) or "N/A"

                if self.db.profile.verbose then
                    local absorbFmt = "Absorbed spell (%s-%s,%d) for %d"
                    self:Print(absorbFmt:format(spellName, schoolName, school, damage))
                end
                
                if school == 1 then
                    self:UpdateShieldBar(damage)
                end
            end
        end
    end

	if eventtype == "SPELL_CAST_SUCCESS" and srcName == self.playerName and 
	    param10 == DS_SPELL_DMG then

        if self.db.profile.verbose then
            local recentDmg = self:GetRecentDamageTaken(timestamp)
            local predictedHeal = ceil(
                (recentDmg * dsHealModifier * ImpDSModifier * 
                    (1+iccBuffAmt) * (1+vbHealingInc))-0.5)
            local dsHealFormat = "Estimated damage of %d will be a heal for %d"
    		self:Print(dsHealFormat:format(recentDmg, predictedHeal))
        end
	end
    if eventtype == "SPELL_HEAL" and dstName == self.playerName 
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
        local shieldValue = ceil((totalHeal*shieldPercent / 
            (1+iccBuffAmt) / (1+vbHealingInc))-0.5)

        local recentDmg = self:GetRecentDamageTaken(timestamp)
        local predictedHeal = ceil(
            (recentDmg * dsHealModifier * ImpDSModifier * 
                (1+iccBuffAmt) * (1+vbHealingInc))-0.5)
        local minimumHeal = dsHealMin
        local shieldInd = ""
        local minimumBS = ceil((minimumHeal * shieldPercent / 
            (1+iccBuffAmt) / (1+vbHealingInc))-0.5)
        local isMinimum = false
        if totalHeal == minimumHeal then
            shieldInd = "(min)"
            isMinimum = true
        end
        if self.db.profile.verbose then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Last5:%d, Pred:%d]"
            self:Print(dsHealFormat:format(
                totalHeal,actualHeal,overheal,recentDmg,predictedHeal))
            local shieldFormat = "Blood Shield Amount: %d %s"
            self:Print(shieldFormat:format(shieldValue,shieldInd))
        end

        self:NewBloodShield(timestamp, shieldValue, isMinimum)
    end

    if eventtype == "SPELL_AURA_APPLIED" and dstName == self.playerName then
        if param10 and param10 == BS_SPELL then
            if self.db.profile.verbose then
                self:Print("Blood Shield applied.")
            end
        end
    end

    if eventtype == "SPELL_AURA_REFRESH" and dstName == self.playerName then
        if param10 and param10 == BS_SPELL then
            self:BloodShieldRemoved("refreshed", timestamp)
        end
    end
    if eventtype == "SPELL_AURA_REMOVED" and dstName == self.playerName then
        if param10 and param10 == BS_SPELL then
            self:BloodShieldRemoved("removed", timestamp)
        end
    end
end

function BloodShieldTracker:NewBloodShield(timestamp, shieldValue, isMinimum)
    if not IsBloodTank then return end

    numShields = numShields + 1
    totalShieldMaxValue = totalShieldMaxValue + shieldValue

    if isMinimum then
        numMinShields = numMinShields + 1
    end

    if minShieldMaxValue == 0 or shieldValue < minShieldMaxValue then
        minShieldMaxValue = shieldValue
    end
    if shieldValue > maxShieldMaxValue then
        maxShieldMaxValue = shieldValue
    end

	self.statusbar.shield_max = shieldValue
	self.statusbar.shield_curr = shieldValue
    
    if self.db.profile.status_bar_enabled then
        self.statusbar:SetMinMaxValues(0, shieldValue)
        self.statusbar:SetValue(shieldValue)
    
        self.statusbar.value:SetText(statusBarFormat:format(shieldValue, shieldValue, "100"))
        self.statusbar:Show()
    end
end

function BloodShieldTracker:BloodShieldRemoved(type, timestamp)
    if not IsBloodTank then return end

    local max = self.statusbar.shield_max or 0
    local curr = self.statusbar.shield_curr or 0
    if curr < 0 then curr = 0 end
    local used, usedPerc = 0, 0
    if max > 0 then
        used = max - curr
        usedPerc = used / max * 100
    end

    if self.db.profile.verbose then
        local bsRemovedFmt = "Blood Shield %s [Usage=%d/%d %d%%]"
        self:Print(bsRemovedFmt:format(type, used, max, usedPerc))
    end

    totalShieldUsedPerc = totalShieldUsedPerc + usedPerc
    
    if not minShieldUsedPerc then
        minShieldUsedPerc = usedPerc
    elseif usedPerc < minShieldUsedPerc then
        minShieldUsedPerc = usedPerc
    end

    if usedPerc > maxShieldUsedPerc then
        maxShieldUsedPerc = usedPerc
    end

    if type == "refreshed" then
        numRefreshedShields = numRefreshedShields + 1
    end

    if type == "removed" then
        numRemovedShields = numRemovedShields + 1
        self.statusbar:Hide()
    end
end

function BloodShieldTracker:ResetStats()
    numShields = 0
    numMinShields = 0
    numRemovedShields = 0
    numRefreshedShields = 0
    minShieldMaxValue = 0
    maxShieldMaxValue = 0
    totalShieldMaxValue = 0
    minShieldUsedPerc = nil
    maxShieldUsedPerc = 0
    totalShieldUsedPerc = 0
end

function BloodShieldTracker:UNIT_AURA(...)
    local event, unit = ...
    if unit == "player" then
        self:CheckAuras()
    end
end

function BloodShieldTracker:CheckAuras()
    local name, rank, icon, count, dispelType, duration, expires,
        caster, stealable, consolidate, spellId

    local iccBuffFound = false

    -- Check for Hellscream's Warsong ICC buff
    name, rank, icon, count, dispelType, duration, expires, caster, stealable, 
        consolidate,spellId = UnitAura("player", HELLSCREAM_BUFF)
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
        consolidate,spellId = UnitAura("player", VB_BUFF)
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

    self:UpdateMinHeal("CheckAura", "player")
end

function BloodShieldTracker:UpdateShieldBarVisiblity()
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

function BloodShieldTracker:UpdateDamageBarVisiblity()
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


function BloodShieldTracker:UpdateShieldBarGraphics()
    if self.statusbar then
        local bc = self.db.profile.status_bar_color
        self.statusbar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a)
        local bgc = self.db.profile.status_bar_bgcolor
        self.statusbar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
        local tc = self.db.profile.status_bar_textcolor
        self.statusbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
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

function BloodShieldTracker:CreateStatusBar()
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
    statusbar.value:SetFont(font, self.db.profile.font_size, "OUTLINE")
    statusbar.value:SetJustifyH("CENTER")
    statusbar.value:SetShadowOffset(1, -1)
    local tc = self.db.profile.status_bar_textcolor
    statusbar.value:SetTextColor(tc.r, tc.g, tc.b, tc.a)
    statusbar.lock = false
	statusbar.value:SetText(statusBarFormat:format(0, 0, "0"))
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

function BloodShieldTracker:CreateDamageBar()
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
    statusbar.value:SetFont(font, self.db.profile.font_size, "OUTLINE")
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
    statusbar.value:SetText(healBarFormat:format(L["HealBarText"], dsHealMin))
    statusbar:EnableMouse(true)
    statusbar:Hide()
    return statusbar
end