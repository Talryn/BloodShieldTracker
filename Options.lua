local _G = getfenv(0)
local ADDON_NAME, addon = ...

local ipairs = _G.ipairs
local pairs = _G.pairs
local floor = _G.math.floor
local select = _G.select

local SpellNames = addon.SpellNames
local ItemNames = addon.ItemNames

local BloodShieldTracker = LibStub("AceAddon-3.0"):GetAddon(addon.addonNameCondensed)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonNameCondensed)
local LSM = _G.LibStub:GetLibrary("LibSharedMedia-3.0")
local icon = _G.LibStub("LibDBIcon-1.0")

addon.configMode = false

local PriestAbsorbsOrdered = {
	"Power Word: Shield",
	"Divine Aegis",
	"Spirit Shell",
	"Clarity of Will",
}

local AbsorbShieldsOrdered = addon.AbsorbShieldsOrdered

function BloodShieldTracker:ShowOptions()
	_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.ShieldBar)
	_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.Main)
end

function BloodShieldTracker:GetOptions()
	if not addon.options then
		addon.options = {
	    	type = "group",
			name = _G.GetAddOnMetadata(ADDON_NAME, "Title"),
			args = {
				core = self:GetGeneralOptions(),
				shieldBarOpts = self:GetShieldBarOptions(),
				boneShieldOpts = self:GetBoneShieldBarOptions(),
				pwsBarOpts = self:GetPWSBarOptions(),
				absorbsBarOpts = self:GetAbsorbsBarOptions(),
				purgatoryBarOpts = self:GetPurgatoryBarOptions(),
				amsBarOpts = self:GetAMSBarOptions(),
				skinningOpts = self:GetSkinningOptions(),
	    	}
	  	}

		addon.options.args.profile = 
			_G.LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

		-- Add additional options for modules
		for name, obj in pairs(addon.modules) do
			if obj and obj.GetOptions then
				local name, opts = obj:GetOptions()
				addon.options.args[name] = opts
			end
		end
	end
	return addon.options
end

function BloodShieldTracker:AddDimensionOptions(opts, barName, order)
	local seq = order or 300
    opts.args.dimensions = {
        order = seq,
        type = "header",
        name = L["Dimensions"],
    }
	opts.args.width = {
		order = seq + 10,
		name = L["Width"],
		desc = L["BarWidth_Desc"],	
		type = "range",
		min = 50,
		max = 300,
		step = 1,
		set = function(info, val)
		    self.db.profile.bars[barName].width = val 
			addon.bars[barName].bar:SetWidth(val)
			addon.bars[barName].bar.border:SetWidth(val+9)
		end,
		get = function(info, val)
		    return self.db.profile.bars[barName].width
		end,
	}
	opts.args.height = {
		order = seq + 20,
		name = L["Height"],
		desc = L["BarHeight_Desc"],
		type = "range",
		min = 10,
		max = 30,
		step = 1,
		set = function(info, val)
		    self.db.profile.bars[barName].height = val 
			addon.bars[barName].bar:SetHeight(val)
			addon.bars[barName].bar.border:SetHeight(val + 8)
		end,
		get = function(info, val)
		    return self.db.profile.bars[barName].height
		end,					
	}
	opts.args.scale = {
		order = seq + 30,
		name = L["Scale"],
		desc = L["ScaleDesc"],
		type = "range",
		min = 0.1,
		max = 3,
		step = 0.1,
		get = function()
			return self.db.profile.bars[barName].scale
		end,
		set = function(info, val)
		    self.db.profile.bars[barName].scale = val
		    addon.bars[barName].bar:SetScale(val)
		end
	}
end

function BloodShieldTracker:AddPositionOptions(opts, barName, order)
	local seq = order or 400

    opts.args.position = {
        order = seq,
        type = "header",
        name = L["Position"],
    }
	opts.args.x = {
		order = seq + 10,
		name = L["X Offset"],
		desc = L["XOffset_Desc"],	
		type = "range",
		softMin = -floor(_G.GetScreenWidth()/2),
		softMax = floor(_G.GetScreenWidth()/2),
		bigStep = 1,
		set = function(info, val)
		    self.db.profile.bars[barName].x = val
			addon.bars[barName].bar:SetPoint(
				"CENTER", _G.UIParent, "CENTER", 
				self.db.profile.bars[barName].x, 
				self.db.profile.bars[barName].y)
		end,
		get = function(info, val)
		    return self.db.profile.bars[barName].x
		end,
	}
	opts.args.y = {
		order = seq + 20,
		name = L["Y Offset"],
		desc = L["YOffset_Desc"],	
		type = "range",
		softMin = -floor(_G.GetScreenHeight()/2),
		softMax = floor(_G.GetScreenHeight()/2),
		bigStep = 1,
		set = function(info, val)
		    self.db.profile.bars[barName].y = val
			addon.bars[barName].bar:SetPoint(
				"CENTER", _G.UIParent, "CENTER", 
				self.db.profile.bars[barName].x, 
				self.db.profile.bars[barName].y)
		end,
		get = function(info, val)
		    return self.db.profile.bars[barName].y
		end,
	}
end

function BloodShieldTracker:AddColorsOptions(opts, barName, order)
	local seq = order or 500
    opts.args.colors = {
        order = seq,
        type = "header",
        name = L["Colors"],
    }
	opts.args.textcolor = {
		order = seq + 10,
		name = L["Text Color"],
		desc = L["BarTextColor_OptionDesc"],
		type = "color",
		hasAlpha = true,
		set = function(info, r, g, b, a)
		    local c = self.db.profile.bars[barName].textcolor
		    c.r, c.g, c.b, c.a = r, g, b, a
		    addon.bars[barName]:UpdateGraphics()
		end,
		get = function(info)
	        local c = self.db.profile.bars[barName].textcolor
		    return c.r, c.g, c.b, c.a
		end,					
	}
	opts.args.color = {
		order = seq + 20,
		name = L["Bar Color"],
		desc = L["BarColor_OptionDesc"],
		type = "color",
		hasAlpha = true,
		set = function(info, r, g, b, a)
		    local c = self.db.profile.bars[barName].color
		    c.r, c.g, c.b, c.a = r, g, b, a
		    addon.bars[barName]:UpdateGraphics()
		end,
		get = function(info)
	        local c = self.db.profile.bars[barName].color
		    return c.r, c.g, c.b, c.a
		end,					
	}
	opts.args.bgcolor = {
		order = seq + 30,
		name = L["Bar Background Color"],
		desc = L["BarBackgroundColor_OptionDesc"],
		type = "color",
		hasAlpha = true,
		set = function(info, r, g, b, a)
		    local c = self.db.profile.bars[barName].bgcolor
		    c.r, c.g, c.b, c.a = r, g, b, a
		    addon.bars[barName]:UpdateGraphics()
		end,
		get = function(info)
	        local c = self.db.profile.bars[barName].bgcolor
		    return c.r, c.g, c.b, c.a
		end,					
	}
end

function BloodShieldTracker:AddAppearanceOptions(opts, barName, order)
	local seq = order or 600
    opts.args.appearance = {
        order = seq,
        type = "header",
        name = L["Appearance"],
    }
	opts.args.texture_opt = {
		order = seq + 10,
		name = L["Texture"],
		desc = L["BarTexture_OptionDesc"],
		type = "select",
		values = LSM:HashTable("statusbar"),
		dialogControl = 'LSM30_Statusbar',
		get = function()
		    return self.db.profile.bars[barName].texture
		end,
		set = function(info, val)
		    self.db.profile.bars[barName].texture = val
		    addon.bars[barName]:UpdateTexture()
		end,
		disabled = function()
		    return not self.db.profile.bars[barName].shown
		end,
	}
	opts.args.border_visible_opt = {
		order = seq + 20,
		name = L["ShowBorder"],
		desc = L["ShowBorderDesc"],
		type = "toggle",
		get = function()
		    return self.db.profile.bars[barName].border
		end,
		set = function(info, val)
		    self.db.profile.bars[barName].border = val
		    addon.bars[barName]:UpdateBorder()
		end,
	}
	opts.args.visible_opt = {
		order = seq + 30,
		name = L["ShowBar"],
		desc = L["ShowBarDesc"],
		type = "toggle",
		get = function()
			return self.db.profile.bars[barName].shown
		end,
		set = function(info,val) 
	        self.db.profile.bars[barName].shown = val
	        addon.bars[barName]:UpdateUI()
	    end,
	}
end

local function GetAnchorFrames(frames, barName)
	_G.wipe(frames)
	frames["None"] = L["None"]
	frames["Custom"] = L["Custom"]

	for k, v in pairs(addon.FrameNames) do
		if k and v and k ~= "Compact Runes" and 
			addon.bars[barName] and
			k ~= addon.bars[barName].friendlyName then
			frames[k] = L[k]
		end
	end

	if addon.GetAddOnInfoByName("CompactRunes") or 
		BloodShieldTracker.db.profile.bars[barName].anchorFrame == "Compact Runes" then
		frames["Compact Runes"] = L["Compact Runes"]
	end

	return frames
end

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

	local frames = {}
	options.args.anchorFrame = {
		name = L["Anchor"],
		desc = L["Anchor_OptDesc"],
		type = "select",
		values = function() return GetAnchorFrames(frames, barName) end,
		--values = {
		--	["None"] = L["None"],
		--	["Custom"] = L["Custom"],
		--	["Shield Bar"] = L["Shield Bar"],
		--	["PW:S Bar"] = L["PW:S Bar"],
		--	["Total Absorbs Bar"] = L["Total Absorbs Bar"],
		--	["Anti-Magic Shell Bar"] = L["Anti-Magic Shell Bar"],
		--	["Blood Charge Bar"] = L["Blood Charge Bar"],
		--	["Bone Shield Bar"] = L["Bone Shield Bar"],
		--	["Bone Wall Bar"] = L["Bone Wall Bar"],
		--	["Purgatory Bar"] = L["Purgatory Bar"],
		--},
		order = 1010,
		set = function(info, val)
			self.db.profile.bars[barName].anchorFrame = val
			addon.bars[barName]:SetPoint()
		end,
			get = function(info)
      	return self.db.profile.bars[barName].anchorFrame
    	end,
	}
	--if addon.GetAddOnInfoByName("CompactRunes") or 
	--	self.db.profile.bars[barName].anchorFrame == "Compact Runes" then
	--	options.args.anchorFrame.values["Compact Runes"] = 
	--		L["Compact Runes"]
	--end

	options.args.anchorFrameCustom = {
		name = L["Frame"],
		desc = L["Frame_OptDesc"],
		type = "input",
		width = "double",
		order = 1020,
		set = function(info, val)
		    self.db.profile.bars[barName].anchorFrameCustom = val
			addon.bars[barName]:SetPoint()
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
			addon.bars[barName]:SetPoint()
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
			addon.bars[barName]:SetPoint()
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
			addon.bars[barName]:SetPoint()
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
			addon.bars[barName]:SetPoint()
		end,
		get = function(info, val)
		    return self.db.profile.bars[barName].anchorY
		end,
		disabled = function()
			return self.db.profile.bars[barName].anchorFrame == "None"
		end,
	}
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
						" (" .. addon.FormatNumberRaw(testNumber) .. ")",
				    ["Delimited"] = L["Delimited"] .. 
						" (" .. addon.FormatNumberDelimited(testNumber) .. ")",
				    ["Abbreviated"] = L["Abbreviated"] .. 
						" (" .. addon.FormatNumberAbbreviated(testNumber) .. ")"
				},
				order = 34,
				set = function(info, val)
				    self.db.profile.numberFormat = val
					addon:SetNumberFormat(val)
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
					addon:SetNumberPrecision()
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
				    addon.configMode = not addon.configMode
					if addon.configMode then
						for name, bar in pairs(addon.bars) do
							bar.bar:Show()
						end
					else
						for name, bar in pairs(addon.bars) do
							if bar.db.enabled and bar.db.hide_ooc ~= nil then
								if bar.db.hide_ooc and 
									not _G.InCombatLockdown() then
									bar.bar:Hide()
								end
							else
								bar.bar:Hide()
							end
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
				    addon:SetBrokerLabel()
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
				    addon.DataFeed.display = val
				    if val == "None" then
				        addon.LDBDataFeed = false
			        else
			            addon.LDBDataFeed = true
		            end
				    addon:UpdateLDBData()
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
					addon.bars["ShieldBar"]:UpdateVisibility()
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
					self.shieldbar:Lock(val)
				end,
                get = function(info)
					return self.db.profile.bars["ShieldBar"].locked
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
					self.shieldbar:UpdateBarConfig()
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
					self.shieldbar:UpdateBarConfig()
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
		},
	}
	self:AddDimensionOptions(shieldBarOpts, "ShieldBar")
	self:AddPositionOptions(shieldBarOpts, "ShieldBar")
	self:AddColorsOptions(shieldBarOpts, "ShieldBar")
	self:AddAppearanceOptions(shieldBarOpts, "ShieldBar")
	self:AddAdvancedPositioning(shieldBarOpts, "ShieldBar")
	return shieldBarOpts
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
					addon.bars["BoneShieldBar"]:UpdateVisibility()
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
					addon.bars["BoneShieldBar"]:Lock(val)
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
			        self.boneshieldbar:UpdateBarConfig()
				end,
                get = function(info)
                    return self.db.profile.bars["BoneShieldBar"].progress
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
			        self.boneshieldbar:UpdateBarConfig()
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
			        self.boneshieldbar:UpdateBarConfig()
				end,
                get = function(info)
                    return self.db.profile.bars["BoneShieldBar"].time_pos
                end,
                disabled = function()
                    return not self.db.profile.bars["BoneShieldBar"].show_time
                end,
			},
		},
	}
	self:AddDimensionOptions(boneShieldOpts, "BoneShieldBar")
	self:AddPositionOptions(boneShieldOpts, "BoneShieldBar")
	self:AddColorsOptions(boneShieldOpts, "BoneShieldBar")
	self:AddAppearanceOptions(boneShieldOpts, "BoneShieldBar")
	self:AddAdvancedPositioning(boneShieldOpts, "BoneShieldBar")
	return boneShieldOpts
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
					addon.bars["PWSBar"]:UpdateVisibility()
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
					addon.bars["PWSBar"]:Lock(val)
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
	self:AddDimensionOptions(pwsBarOpts, "PWSBar")
	self:AddPositionOptions(pwsBarOpts, "PWSBar")
	self:AddColorsOptions(pwsBarOpts, "PWSBar")
	self:AddAppearanceOptions(pwsBarOpts, "PWSBar")
	self:AddAdvancedPositioning(pwsBarOpts, "PWSBar")
	return pwsBarOpts
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
					addon.bars["TotalAbsorbsBar"]:UpdateVisibility()
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
					addon.bars["TotalAbsorbsBar"]:Lock(val)
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
			absorbsTracked = {
				order = 101,
				name = L["Absorbs Tracked"],
				desc = L["AbsorbsTracked_OptionDesc"],
				type = "select",
				values = {
				    ["All"] = L["All"],
				    ["Selected"] = L["Selected"],
				    ["Excluding"] = L["All Minus Selected"],
				},
				set = function(info, val)
				    self.db.profile.bars["TotalAbsorbsBar"].tracked = val
				end,
                get = function(info)
                    return self.db.profile.bars["TotalAbsorbsBar"].tracked
                end,
			},
		},
	}

	-- Add included absorbs
	local orderid = 101
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
			disabled = function()
				return self.db.profile.bars["TotalAbsorbsBar"].tracked == "All"
			end,
		}
	end
	self:AddDimensionOptions(absorbsBarOpts, "TotalAbsorbsBar")
	self:AddPositionOptions(absorbsBarOpts, "TotalAbsorbsBar")
	self:AddColorsOptions(absorbsBarOpts, "TotalAbsorbsBar")
	self:AddAppearanceOptions(absorbsBarOpts, "TotalAbsorbsBar")
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
					addon.bars["PurgatoryBar"]:UpdateVisibility()
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
					addon.bars["PurgatoryBar"]:Lock(val)
				end,
                get = function(info)
					return self.db.profile.bars["PurgatoryBar"].locked
				end,
			},
		},
	}
	self:AddDimensionOptions(purgatoryBarOpts, "PurgatoryBar")
	self:AddPositionOptions(purgatoryBarOpts, "PurgatoryBar")
	self:AddColorsOptions(purgatoryBarOpts, "PurgatoryBar")
	self:AddAppearanceOptions(purgatoryBarOpts, "PurgatoryBar")
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
					addon.bars["AMSBar"]:UpdateVisibility()
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
					addon.bars["AMSBar"]:Lock(val)
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
			        self.amsbar:UpdateBarConfig()
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
					self.amsbar:UpdateBarConfig()
				end,
                get = function(info)
                    return self.db.profile.bars["AMSBar"].time_pos
                end,
                disabled = function()
                    return not self.db.profile.bars["AMSBar"].show_time
                end,
			},
		},
	}
	self:AddDimensionOptions(amsBarOpts, "AMSBar")
	self:AddPositionOptions(amsBarOpts, "AMSBar")
	self:AddColorsOptions(amsBarOpts, "AMSBar")
	self:AddAppearanceOptions(amsBarOpts, "AMSBar")
	self:AddAdvancedPositioning(amsBarOpts, "AMSBar")
	return amsBarOpts
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
