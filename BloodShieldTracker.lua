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
local lastDSSuccess = nil
local masteryRating = 0

local GREEN = "|cff00ff00"
local YELLOW = "|cffffff00"
local BLUE = "|cff0198e1"
local ORANGE = "|cffff9933"

local L = LibStub("AceLocale-3.0"):GetLocale("BloodShieldTracker", true)
local LDB = LibStub("LibDataBroker-1.1")
local LibQTip = LibStub('LibQTip-1.0')

local DS_SPELL = (GetSpellInfo(49924))
local BS_SPELL = (GetSpellInfo(77535))

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

function Broker.obj:OnEnter()
	local tooltip = LibQTip:Acquire("BloodShieldTrackerTooltip", 4, "LEFT", "CENTER", "CENTER", "CENTER")
	self.tooltip = tooltip 

    tooltip:AddLine(YELLOW.."Damage Taken: "..(BloodShieldTracker.damageTaken or 0))

	tooltip:SmartAnchorTo(self)
	tooltip:Show()
end

function Broker.obj:OnLeave()
	LibQTip:Release(self.tooltip)
	self.tooltip = nil
end

local defaults = {
    profile = {
        verbose = false,
		lock_status_bar = false,
		lock_damage_bar = false,
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
                verbose = {
                    name = L["Verbose"],
                    desc = L["Toggles the display of informational messages"],
                    type = "toggle",
                    set = function(info, val) self.db.profile.verbose = val end,
                    get = function(info) return self.db.profile.verbose end,
                },
				lock_damage = {
					name = L["Lock damage bar"],
					desc = L["Lock the damage bar from moving."],
					type = "toggle",
					set = function(info, val) self.db.profile.lock_damage_bar = val 
						if BloodShieldTracker.damagebar then
							BloodShieldTracker.damagebar.locked = true
						end
					end,
                    get = function(info) return self.db.profile.lock_damage_bar end,
				},
				lock_status = {
					name = L["Lock status bar"],
					desc = L["Lock the status bar from moving."],
					type = "toggle",
					set = function(info, val) self.db.profile.lock_status_bar = val 
						if BloodShieldTracker.statusbar then
							BloodShieldTracker.statusbar.locked = true
						end					
					end,
                    get = function(info) return self.db.profile.lock_status_bar end,
				}
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

function BloodShieldTracker:OnInitialize()
    -- Load the settings
    self.db = LibStub("AceDB-3.0"):New("BloodShieldTrackerDB", defaults, "Default")
    -- Register the options table
    LibStub("AceConfig-3.0"):RegisterOptionsTable("BloodShieldTracker", self:GetOptions())
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("BloodShieldTracker", ADDON_NAME)
    self.statusbar = self:CreateStatusBar()
    self.damagebar = self:CreateDamageBar()
	self.damagebar.lock = self.db.profile.lock_damage_bar
	self.statusbar.lock = self.db.profile.lock_status_bar
	self:UpdateMastery()
end

function BloodShieldTracker:OnEnable()
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("COMBAT_RATING_UPDATE","UpdateMastery")
    self.damagebar:Show()
end

function BloodShieldTracker:OnDisable()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

-- Watch for combat rating updates so we can adjust mastery score as it changes,
-- i.e. trinket procs, buffs etc .. we only need to check this when it changes instead of every time we see damage
local GetMastery = GetMastery
function BloodshieldTracker:UpdateMastery()
	local masteryRating = GetMastery();
    masteryRating = format("%.2f", masteryRating);
end

function BloodShieldTracker:PLAYER_REGEN_DISABLED()
	-- Once combat stats, update the damage bar every lastSeconds.
	updateTimer = self:ScheduleRepeatingTimer("UpdateDamageBar", 0.5)
end

function BloodShieldTracker:PLAYER_REGEN_ENABLED()
    self.damagebar.value:SetText("0")
    self.damagebar:SetStatusBarColor(1, 0, 0)
    self.damagebar:SetMinMaxValues(0, 1)
    self.damagebar:SetValue(1)
    self:CancelTimer(updateTimer)
end

function BloodShieldTracker:UpdateDamageBar()
    local recentDamage = self:GetRecentDamageTaken()
    self.damagebar.value:SetText(recentDamage)

    local predictedHeal = recentDamage * 0.3 * 1.45
    local minimumHeal = floor(UnitHealthMax("player") / 10)

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
                self:Print("Absorbed swing for "..(param10 or "0"))
            end
        end
    end
	if eventtype == "SPELL_CAST_SUCCESS" and srcName == self.playerName and param10 == DS_SPELL then
        local recentDmg = self:GetRecentDamageTaken(timestamp)
        local predictedHeal = recentDmg * 0.3 * 1.45		
		self:Print("Estimating heal to be "..recentDmg.." before talents and glyph. "..predictedHeal)
	end
    if eventtype == "SPELL_HEAL" and dstName == self.playerName 
        and param10 == DS_SPELL then
        
        
        local shieldPercent = masteryRating*6.25/100
        local totalHeal = param12 or 0
        local overheal = param13 or 0
        local actualHeal = param12-param13
        local shieldValue = floor(totalHeal*shieldPercent)

        local recentDmg = self:GetRecentDamageTaken(timestamp)
        local predictedHeal = recentDmg * 0.3 * 1.45
        local shieldInd = ""
        local minimumHeal = floor(UnitHealthMax("player")/10)
        local minimumBS = minimumHeal * 0.3 * .145
        if minimumBS == shieldValue then
            shieldInd = "(min)"
        end

        if self.db.profile.verbose then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Last5:%d, Pred:%d]"
            self:Print(dsHealFormat:format(
                totalHeal,actualHeal,overheal,recentDmg,predictedHeal))
            local shieldFormat = "Blood Shield Amount: %d %s"
            self:Print(shieldFormat:format(shieldValue,shieldInd))
        end

        self.statusbar:SetMinMaxValues(0, shieldValue)
        self.statusbar:SetValue(shieldValue)
        local statusBarFormat = "%d/%d (%d%%)"
        self.statusbar.value:SetText(statusBarFormat:format(shieldValue, shieldValue, "100"))
        self.statusbar:Show()
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
    statusbar:SetWidth(150)
    statusbar:SetHeight(15)
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
    statusbar.value:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
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

    statusbar:EnableMouse(true)
    statusbar:Hide()
    return statusbar
end

function BloodShieldTracker:CreateDamageBar()
    local statusbar = CreateFrame("StatusBar", "BloodShieldTracker_DamageBar", UIParent)
    statusbar:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    statusbar:SetWidth(100)
    statusbar:SetHeight(15)
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
    statusbar.value:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
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
    statusbar.value:SetText("0")

    statusbar:EnableMouse(true)
    statusbar:Hide()
    return statusbar
end