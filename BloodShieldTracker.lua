local BloodShieldTracker = LibStub("AceAddon-3.0"):NewAddon("BloodShieldTracker", "AceConsole-3.0", "AceEvent-3.0","AceTimer-3.0")

local ADDON_NAME = ...
local ADDON_VERSION = "@project-version@"

-- Local versions for performance
local tinsert, tremove, tgetn = table.insert, table.remove, table.getn
local pairs, ipairs = pairs, ipairs
local floor = math.floor

BloodShieldTracker.damageTaken = 0
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
local minShieldMaxValue = 0
local maxShieldMaxValue = 0

local shields = {}
local lastDSSuccess = nil
local masteryRating = 0

local GREEN = "|cff00ff00"
local YELLOW = "|cffffff00"
local BLUE = "|cff0198e1"
local ORANGE = "|cffff9933"
local statusBarFormat = "%d/%d (%d%%)"
local healBarFormat = "%s: %d"
local healBarText = "Self Heal"

local L = LibStub("AceLocale-3.0"):GetLocale("BloodShieldTracker", true)
local LDB = LibStub("LibDataBroker-1.1")
local LibQTip = LibStub("LibQTip-1.0")
local icon = LibStub("LibDBIcon-1.0")
-- Load LibsharedMedia if it exists
local LSM = LibStub:GetLibrary("LibSharedMedia-3.0",true)
local default_font = "Fonts\\FRIZQT__.TTF"
-- Shim if we are missing LibSharedMedia so options dont barf.
if not LSM then
	LSM = {}
	LSM.HashTable = function() 
		ht = {} 
		ht[L["Blizzard"]] = default_font
		return ht
	end
end

local DS_SPELL_DMG = (GetSpellInfo(49998))
local DS_SPELL_HEAL = (GetSpellInfo(45470))
local BS_SPELL = (GetSpellInfo(77535))
local IMP_DS_TALENT = (GetSpellInfo(81138))
local ImpDSModifier = 1
local dsHealModifier = 0.3
local shieldPerMasteryPoint = 6.25


local Broker = CreateFrame("Frame")
Broker.obj = LDB:NewDataObject("Blood Shield Tracker", {
    type = "data source",
    icon = "Interface\\Icons\\Spell_DeathKnight_DeathStrike",
    label = ADDON_NAME,
    text = ADDON_NAME,
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
				InterfaceOptionsFrame_OpenToCategory(BloodShieldTracker.optionsFrame)
			end
		elseif button == "LeftButton" then
        end
	end
} )

local shieldDataHdr = GREEN.."Blood Shield Data"
local shieldDataLine1 = YELLOW.."Number of Shields:"
local shieldDataLine2 = YELLOW.."Number of Minimum Shields:"
local shieldDataMinShld = "%d (%d%%)"

local shieldMaxValueHdr = GREEN.."Blood Shield Max Value"
local shieldMaxValueLine1 = YELLOW.."Minimum Shield Value:"
local shieldMaxValueLine2 = YELLOW.."Maximum Shield Value:"
local shieldMaxValueLine3 = YELLOW.."Average Shield Value:"

function Broker.obj:OnEnter()
	local tooltip = LibQTip:Acquire("BloodShieldTrackerTooltip", 2, "LEFT", "RIGHT")
	self.tooltip = tooltip 

    local percentMinimum = 0
    if numShields > 0 then
        percentMinimum = numMinShields / numShields * 100
    end

    tooltip:AddHeader(shieldDataHdr)
    tooltip:AddSeparator(1)
    tooltip:AddLine(shieldDataLine1, numShields)
    tooltip:AddLine(shieldDataLine2, 
        shieldDataMinShld:format(numMinShields, percentMinimum))

    tooltip:AddLine()

    tooltip:AddHeader(shieldMaxValueHdr)
    tooltip:AddSeparator(1)
    tooltip:AddLine(shieldMaxValueLine1, minShieldMaxValue)
    tooltip:AddLine(shieldMaxValueLine2, maxShieldMaxValue)
    tooltip:AddLine(shieldMaxValueLine3, avgShieldMaxValue)

	tooltip:SmartAnchorTo(self)
	tooltip:Show()
end

function Broker.obj:OnLeave()
	LibQTip:Release(self.tooltip)
	self.tooltip = nil
end


local defaults = {
    profile = {
		minimap = {
			hide = true,
		},
        verbose = false,
        status_bar_enabled = true,
        damage_bar_enabled = true,
		lock_status_bar = false,
		lock_damage_bar = false,
		damage_bar_width = 100,
		damage_bar_height = 15,
		status_bar_width = 150,
		status_bar_height = 15,
		font_size = 12,
		font_face = "",
    }
}


local options

function BloodShieldTracker:GetOptions()
    if not options then
        options = {
            name = "BloodShieldTracker",
            handler = BloodShieldTracker,
            type = 'group',
            args = {
        		generalOptions = {
        			order = 0,
        			type = "header",
        			name = L["General Options"],
        		},
                verbose = {
                    name = L["Verbose"],
					order = 1,
                    desc = L["Toggles the display of informational messages"],
                    type = "toggle",
                    set = function(info, val) self.db.profile.verbose = val end,
                    get = function(info) return self.db.profile.verbose end,
                },
				bar_font_size = {
					order = 2,
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
					order = 3,
					type = "select",
					name = L["Font"],
					desc = L["Font to use."],
					values = LSM:HashTable("font"),
					dialogControl = 'LSM30_Font',
					disabled = function() return not IsAddOnLoaded("LibSharedMedia-3.0") end,
					get = function() 
						if strlen(self.db.profile.font_face) < 1 then
							return L["Blizzard"]
						else
							return self.db.profile.font_face
						end
					end,
					set = function(info, val) 
						if val ~= L["Blizzard"] then
							self.db.profile.font_face = val; 
						end
						BloodShieldTracker:ResetFonts()
					end
				},
        	    minimap = {
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
        			order = 4
                },
				config_mode = {
					name = L["Config Mode"],
					desc = L["Toggle config mode"],
					type = "execute",
					order = 5,
					func = function()
						if BloodShieldTracker.statusbar:IsShown() then
							BloodShieldTracker.statusbar:Hide()
						else
							BloodShieldTracker.statusbar:Show()
						end
					end,
				},
        		bloodshieldBar = {
        			order = 10,
        			type = "header",
        			name = L["Blood Shield Bar"],
        		},
        		status_bar_enabled = {
					name = L["Enabled"],
					desc = L["Enable the Blood Shield Bar."],
					type = "toggle",
					order = 11,
					set = function(info, val)
					    self.db.profile.status_bar_enabled = val
					    if not val then
						    BloodShieldTracker.statusbar:Hide()
						end
					end,
                    get = function(info) return self.db.profile.status_bar_enabled end,
				},
				lock_damage = {
					name = L["Lock shield bar"],
					desc = L["Lock the shield bar from moving."],
					type = "toggle",
					order = 12,
					set = function(info, val) self.db.profile.lock_status_bar = val 
						if BloodShieldTracker.statusbar then
							BloodShieldTracker.statusbar.lock = val
						end
					end,
                    get = function(info) return self.db.profile.lock_status_bar end,
				},
				damage_bar_width = {
					order = 13,
					name = L["Blood Shield bar width"],
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
				damage_bar_height = {
					order = 14,
					name = L["Blood Shield bar height"],
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
        		estHealBar = {
        			order = 20,
        			type = "header",
        			name = L["Estimated Healing Bar"],
        		},
        		damage_bar_enabled = {
					name = L["Enabled"],
					desc = L["Enable the Estimated Healing Bar."],
					type = "toggle",
					order = 21,
					set = function(info, val)
					    self.db.profile.damage_bar_enabled = val
					    if not val then
						    BloodShieldTracker.damagebar:Hide()
						end
					end,
                    get = function(info) return self.db.profile.damage_bar_enabled end,
				},
				lock_status = {
					name = L["Lock estimated healing bar"],
					desc = L["Lock the estimated healing bar from moving."],
					type = "toggle",
					order = 22,
					set = function(info, val) self.db.profile.lock_damage_bar = val 
						if BloodShieldTracker.damagebar then
							BloodShieldTracker.damagebar.lock = val
						end					
					end,
                    get = function(info) return self.db.profile.lock_damage_bar end,
				},
				status_bar_width = {
					order = 23,
					name = L["Estimated Healing bar width"],
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
				status_bar_height = {
					order = 24,
					name = L["Estimated Healing bar height"],
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
            }
        }
    end
    
    return options
end

function BloodShieldTracker:ChatCommand(input)
    if not input or input:trim() == "" then
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    else
        LibStub("AceConfigCmd-3.0").HandleCommand(BloodShieldTracker, "bst", "BloodShieldTracker", input)
    end
end

local IsBloodTank = false

function BloodShieldTracker:OnInitialize()
    -- Load the settings
    self.db = LibStub("AceDB-3.0"):New("BloodShieldTrackerDB", defaults, "Default")
    -- Register the options table
    LibStub("AceConfig-3.0"):RegisterOptionsTable("BloodShieldTracker", self:GetOptions())
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("BloodShieldTracker", ADDON_NAME)

	icon:Register("BloodShieldTrackerLDB", Broker.obj, self.db.profile.minimap)
	if LSM then
		LSM.RegisterCallback(BloodShieldTracker, "LibSharedMedia_Registered")
	end
    self.statusbar = self:CreateStatusBar()
    self.statusbar.shield_curr = 0
    self.damagebar = self:CreateDamageBar()
	self.damagebar.lock = self.db.profile.lock_damage_bar
	self.statusbar.lock = self.db.profile.lock_status_bar
	self:UpdateMastery()
	self:CheckImpDeathStrike()
end

function BloodShieldTracker:ResetFonts()
	local fontName, fontHeight, fontFlags = BloodShieldTracker.statusbar.value:GetFont()
	local ff = fontName
	if LSM and LSM.Fetch and strlen(self.db.profile.font_face) > 1 then
		ff = LSM:Fetch("font",self.db.profile.font_face)
	end
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
end

function BloodShieldTracker:OnEnable()
	if IsBloodTank then
		self:Load()
	end

	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED","CheckImpDeathStrike")
	self:RegisterEvent("CHARACTER_POINTS_CHANGED","CheckImpDeathStrike")
	self:RegisterEvent("PLAYER_TALENT_UPDATE","CheckImpDeathStrike")
end

function BloodShieldTracker:Load()
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("COMBAT_RATING_UPDATE","UpdateMastery")
	self:RegisterEvent("MASTERY_UPDATE","UpdateMastery")
    self.damagebar:Show()
end

function BloodShieldTracker:Unload()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:UnregisterEvent("COMBAT_RATING_UPDATE")
	self:UnregisterEvent("MASTERY_UPDATE")
	self.damagebar:Hide()
end

function BloodShieldTracker:OnDisable()
	-- We dont need to unregister events as OnDisable tells all the ace embed to disable and unregister
end

-- Watch for combat rating updates so we can adjust mastery score as it changes,
-- i.e. trinket procs, buffs etc .. we only need to check this when it changes instead of every time we see damage
local GetMastery = GetMastery
function BloodShieldTracker:UpdateMastery()
    masteryRating = format("%.2f", GetMastery());
end

function BloodShieldTracker:CheckImpDeathStrike()
	ImpDSModifier = 1
	for t = 1, GetNumTalentTabs() do
		for i = 1, GetNumTalents(t) do
			local talentName, _, _, _, currRank, maxRank = GetTalentInfo(t, i)
			if talentName == IMP_DS_TALENT and currRank > 0 then
				ImpDSModifier = 1 + (0.15 * currRank)
			end
		end
	end
	local id, name, desc, texture = GetTalentTabInfo(GetPrimaryTalentTree())
	if texture == "Interface\\Icons\\Spell_Deathknight_BloodPresence" then
		if not IsBloodTank then self:Load() end
		IsBloodTank = true
	else
		if isBloodTank then self:Unload() end
		IsBloodTank = false
	end
end

function BloodShieldTracker:GetMinimumDSHeal()
    return floor(UnitHealthMax("player") * 0.1)
end

function BloodShieldTracker:PLAYER_REGEN_DISABLED()
	-- Once combat stats, update the damage bar.
	updateTimer = self:ScheduleRepeatingTimer("UpdateDamageBar", 0.5)
end

function BloodShieldTracker:PLAYER_REGEN_ENABLED()
	-- cancel timer before hand
    self:CancelTimer(updateTimer)
    self.damagebar.value:SetText(healBarFormat:format(healBarText, self:GetMinimumDSHeal()))
    self.damagebar:SetStatusBarColor(1, 0, 0)
    self.damagebar:SetMinMaxValues(0, 1)
    self.damagebar:SetValue(1)
end

function BloodShieldTracker:UpdateDamageBar()
    if not self.db.profile.damage_bar_enabled then return end
    
    local recentDamage = self:GetRecentDamageTaken()

    local predictedHeal = recentDamage * dsHealModifier * ImpDSModifier
    local minimumHeal = self:GetMinimumDSHeal()
	if recentDamage < minimumHeal then
    	self.damagebar.value:SetText(healBarFormat:format(healBarText, minimumHeal))
	else
    	self.damagebar.value:SetText(healBarFormat:format(healBarText, predictedHeal))		
	end

    self.damagebar:SetMinMaxValues(0, minimumHeal)

    if predictedHeal > minimumHeal then
        self.damagebar:SetStatusBarColor(0, 1, 0)
        self.damagebar:SetValue(minimumHeal)        
    else
        self.damagebar:SetStatusBarColor(1, 0, 0)        
        self.damagebar:SetValue(predictedHeal)
    end
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

function BloodShieldTracker:COMBAT_LOG_EVENT_UNFILTERED(...)
    local event, timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, 
        dstName, dstFlags, param9, param10, param11, param12, param13, param14,
        param15, param16, param17, param18, param19, param20 = ...
    local damage = 0
    
    if not event or not dstName then return end

    if eventtype:find("_DAMAGE") and dstName == self.playerName then
        if eventtype:find("SWING_") and param9 then
            if self.db.profile.verbose then
                self:Print("Swing Damage for "..param9.." ["..(param14 or "0").." absorbed]")
            end
            self.damageTaken = self.damageTaken + param9
            self:AddDamageTaken(timestamp, param9)
        elseif eventtype:find("SPELL_") then
            if self.db.profile.verbose then
                self:Print("Spell Damage for "..param12.." ["..(param17 or "0").." absorbed]")
            end
            self.damageTaken = self.damageTaken + param12            
            self:AddDamageTaken(timestamp, param12)
        end
    end    

    if eventtype == "SWING_MISSED" and dstName == self.playerName then
        if param9 and param9 == "ABSORB" then
            if self.db.profile.verbose then
				local damage = param10 or 0
                self:Print("Absorbed swing for "..(param10 or "0"))
				self.statusbar.shield_curr = self.statusbar.shield_curr - damage
				self.statusbar:SetValue(self.statusbar.shield_curr)
				local diff = floor( (self.statusbar.shield_curr/self.statusbar.shield_max) * 100)
				self.statusbar.value:SetText(statusBarFormat:format(self.statusbar.shield_curr, self.statusbar.shield_max, diff))
            end
        end
    end
	if eventtype == "SPELL_CAST_SUCCESS" and srcName == self.playerName and 
	    param10 == DS_SPELL_DMG then

        if self.db.profile.verbose then
            local recentDmg = self:GetRecentDamageTaken(timestamp)
            local predictedHeal = recentDmg * dsHealModifier * ImpDSModifier
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
        local shieldValue = floor(totalHeal*shieldPercent)

        local recentDmg = self:GetRecentDamageTaken(timestamp)
        local predictedHeal = recentDmg * dsHealModifier * ImpDSModifier
        local minimumHeal = self:GetMinimumDSHeal()
        local shieldInd = ""
        local minimumBS = floor(minimumHeal * shieldPercent)
        if minimumBS == shieldValue then
            shieldInd = "(min)"
            numMinShields = numMinShields + 1
        end
        if self.db.profile.verbose then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Last5:%d, Pred:%d]"
            self:Print(dsHealFormat:format(
                totalHeal,actualHeal,overheal,recentDmg,predictedHeal))
            local shieldFormat = "Blood Shield Amount: %d %s"
            self:Print(shieldFormat:format(shieldValue,shieldInd))
        end

        numShields = numShields + 1
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

    if eventtype == "SPELL_AURA_APPLIED" and dstName == self.playerName then
        if param10 and param10 == BS_SPELL then
            if self.db.profile.verbose then
                self:Print("Blood Shield applied.")
            end
        end
    end

    if eventtype == "SPELL_AURA_REFRESH" and dstName == self.playerName then
        if param10 and param10 == BS_SPELL then
            if self.db.profile.verbose then
                self:Print("Blood Shield refreshed.")
            end
        end
    end
    if eventtype == "SPELL_AURA_REMOVED" and dstName == self.playerName then
        if param10 and param10 == BS_SPELL then
            if self.db.profile.verbose then
                self:Print("Blood Shield removed.")
            end
            self.statusbar:Hide()
        end
    end
end

function BloodShieldTracker:CreateStatusBar()
    local statusbar = CreateFrame("StatusBar", "BloodShieldTracker_StatusBar", UIParent)
    statusbar:SetPoint("CENTER")
    statusbar:SetOrientation("HORIZONTAL")
    statusbar:SetWidth(self.db.profile.status_bar_width)
    statusbar:SetHeight(self.db.profile.status_bar_height)
    statusbar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    statusbar:GetStatusBarTexture():SetHorizTile(false)
    statusbar:GetStatusBarTexture():SetVertTile(false)
    statusbar:SetStatusBarColor(1, 0, 0)

    statusbar.bg = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    statusbar.bg:SetAllPoints(true)
    statusbar.bg:SetVertexColor(0.65, 0, 0)

    statusbar.border = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.border:SetPoint("CENTER")
    statusbar.border:SetWidth(statusbar:GetWidth()+9)
    statusbar.border:SetHeight(statusbar:GetHeight()+8)
    statusbar.border:SetTexture("Interface\\Tooltips\\UI-StatusBar-Border")
	local font = default_font
	if LSM and LSM.Fetch and strlen(self.db.profile.font_face) > 1 then
		font = LSM:Fetch("font",self.db.profile.font_face)
	end
    statusbar.value = statusbar:CreateFontString(nil, "OVERLAY")
    statusbar.value:SetPoint("CENTER")
    statusbar.value:SetFont(font, self.db.profile.font_size, "OUTLINE")
    statusbar.value:SetJustifyH("CENTER")
    statusbar.value:SetShadowOffset(1, -1)
    statusbar.value:SetTextColor(1, 1, 1)
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
        end)

    statusbar:EnableMouse(true)
    statusbar:Hide()
	statusbar.shield_curr = 0
	statusbar.shield_max = 0
    return statusbar
end

function BloodShieldTracker:CreateDamageBar()
    local statusbar = CreateFrame("StatusBar", "BloodShieldTracker_DamageBar", UIParent)
    statusbar:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    statusbar:SetWidth(self.db.profile.damage_bar_width)
    statusbar:SetHeight(self.db.profile.damage_bar_height)
    statusbar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    statusbar:GetStatusBarTexture():SetHorizTile(false)
    statusbar:GetStatusBarTexture():SetVertTile(false)
    statusbar:SetStatusBarColor(1, 0, 0)

    statusbar.bg = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    statusbar.bg:SetAllPoints(true)
    statusbar.bg:SetVertexColor(0.65, 0, 0)

    statusbar.border = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.border:SetPoint("CENTER")
    statusbar.border:SetWidth(statusbar:GetWidth()+9)
    statusbar.border:SetHeight(statusbar:GetHeight()+8)
    statusbar.border:SetTexture("Interface\\Tooltips\\UI-StatusBar-Border")

    statusbar.value = statusbar:CreateFontString(nil, "OVERLAY")
    statusbar.value:SetPoint("CENTER")
	local font = default_font
	if LSM and LSM.Fetch and strlen(self.db.profile.font_face) > 1 then
		font = LSM:Fetch("font",self.db.profile.font_face)
	end
    statusbar.value:SetFont(font, self.db.profile.font_size, "OUTLINE")
    statusbar.value:SetJustifyH("CENTER")
    statusbar.value:SetShadowOffset(1, -1)
    statusbar.value:SetTextColor(1, 1, 1)
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
        end)

    statusbar:SetMinMaxValues(0,1)
    statusbar:SetValue(1)
    statusbar.value:SetText(healBarFormat:format(healBarText, self:GetMinimumDSHeal()))

    statusbar:EnableMouse(true)
    statusbar:Hide()
    return statusbar
end