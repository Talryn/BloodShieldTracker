local _G = getfenv(0)
local ADDON_NAME, addon = ...
local LibStub = _G.LibStub
local BST = LibStub("AceAddon-3.0"):GetAddon(addon.addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonName)

-- Local versions for performance
local ceil = _G.math.ceil
local table = _G.table
local tostring = _G.tostring
local ipairs = _G.ipairs
local tinsert, tremove = table.insert, table.remove
local wipe = _G.wipe
local round = addon.round

-- Local versions of WoW API calls
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local GetTime = _G.GetTime
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitAttackPower = _G.UnitAttackPower
local GetMasteryEffect = _G.GetMasteryEffect
local GetSpellCooldown = _G.GetSpellCooldown

local SpellIds = addon.SpellIds
local SpellNames = addon.SpellNames

local formatStandard = "%s%s%s"
local formatPercent = "%s%%"

local EstimateBar = {}
addon:RegisterModule("EstimateBar", EstimateBar)
EstimateBar.enabled = false

addon.defaults.profile.bars["EstimateBar"] = {
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
}

-- Keep track of time.  Start with current client time
-- but will use the combat log timestamps after that.
local UPDATE_TIMER_FREQUENCY = 0.3
local currentTime = time()
addon.idle = true
local updateTimer = nil
local lastSeconds = 5
local damageTaken = {}
local removeList = {}

-- Constants from abilities / gear.
local dsHealModifier = 0.20  -- Percent of the DS Heal from the tooltip.
local dsMinHealPercent = 0.07
local dsMinHealPercentSuccor = 0.20
local vbHealingBonus = 0.30
local guardianSpiritHealBuff = 0.60

local T14BonusAmt = 0.1

-- Curent state information
local DarkSuccorBuff = false
local DS_SentTime = nil
local DS_Latency = nil

local Tier14Bonus = 1

-- MoP Variables --
-- The actual minimum DS heal percent, based on spec.
addon.maxHealth = 1
local actualDsMinHeal = dsMinHealPercent
local dsHealMin = 0
local bsMinimum = 0
-- End --

local iccBuff = false
local iccBuffAmt = 0.0
local vbBuff = false
local vbHealingInc = 0.0
local gsHealModifier = 0.0
local healingDebuffMultiplier = 1
local lastDSSuccess = nil
local masteryRating = 0
local versatilityBonus = 0
local versatilityPercent = 0
local shieldPercent = 0
local luckOfTheDrawBuff = false
local luckOfTheDrawAmt = 0

function EstimateBar:OnInitialize()
	self.estimatebar = addon.Bar:Create("EstimateBar", "Estimate Bar", false)
end

function EstimateBar:Enable()
	if BST.db.profile.bars["EstimateBar"].enabled then
		self:OnEnable()
	else
		self:OnDisable()
	end
end

function EstimateBar:OnEnable()
	if self.enabled then return end
	self.enabled = true
	self:ToggleEstimateBar()

	addon:RegisterCallback("Auras", "EstimateBar", EstimateBar.CheckAuras)
	addon:RegisterCallback("GearUpdate", "EstimateBar", EstimateBar.GearUpdate)
end

function EstimateBar:OnDisable()
	if not self.enabled then return end
	self.enabled = false
	self:ToggleEstimateBar()
	addon:UnregisterCallback("Auras", "EstimateBar")
	addon:UnregisterCallback("GearUpdate", "EstimateBar")
end

function EstimateBar:GearUpdate()
	local currentBonus = Tier14Bonus
	Tier14Bonus = 1 + (addon.tierCount["T14 Tank"] >= 4 and T14BonusAmt or 0)
	if currentBonus ~= Tier14Bonus then
		self:UpdateMinHeal("CheckGear", "player")
		if addon.db.profile.verbose and addon.idle then
			local fmt = "T14 Bonus: %d%%"
			BST:Print(fmt:format(Tier14Bonus*100-100))
		end
	end

end

local UnitEvents = {
	["any"] = {
		"PLAYER_REGEN_DISABLED",
		"PLAYER_REGEN_ENABLED",
		"PLAYER_ALIVE",
		"PLAYER_DEAD",
		"COMBAT_LOG_EVENT_UNFILTERED",
		"PLAYER_ENTERING_WORLD",
		"COMBAT_RATING_UPDATE",
		"MASTERY_UPDATE"
	},
	["player"] = {
		"UNIT_SPELLCAST_SUCCEEDED",
		"UNIT_MAXHEALTH",
		-- "UNIT_AURA",
	},
}
local function EventFrame_OnEvent(frame, event, ...)
	if event == "PLAYER_REGEN_DISABLED" then
		EstimateBar:PLAYER_REGEN_DISABLED(event, ...)
	elseif event == "PLAYER_REGEN_ENABLED" then
		EstimateBar:PLAYER_REGEN_ENABLED(event, ...)
	elseif event == "PLAYER_ALIVE" then
		EstimateBar:PLAYER_ALIVE(event, ...)
	elseif event == "PLAYER_DEAD" then
		EstimateBar:PLAYER_DEAD(event, ...)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		EstimateBar:UNIT_SPELLCAST_SUCCEEDED(event, ...)
	elseif event == "PLAYER_ENTERING_WORLD" then
		EstimateBar:PLAYER_ENTERING_WORLD(event, ...)
	elseif event == "UNIT_MAXHEALTH" then
		EstimateBar:UNIT_MAXHEALTH(event, ...)
	-- elseif event == "UNIT_AURA" then
	-- 	EstimateBar:UNIT_AURA(event, ...)
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		EstimateBar:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
	-- Send directly to particular functions
	elseif event == "COMBAT_RATING_UPDATE" then
		EstimateBar:UpdateRatings(event, ...)
	elseif event == "MASTERY_UPDATE" then
		EstimateBar:UpdateRatings(event, ...)
	end
end
local EventFrames = {}

function EstimateBar:ToggleEstimateBar()
	if BST.db.profile.bars["EstimateBar"].enabled then
		for unit, events in _G.pairs(UnitEvents) do
			local frame = EventFrames[unit] or _G.CreateFrame("Frame",
					ADDON_NAME.."_ESTBAR_EventFrame_"..unit)
			if frame then
				frame:SetScript("OnEvent", EventFrame_OnEvent)
				EventFrames[unit] = frame
				for i, event in _G.ipairs(events) do
					if unit == "any" then
						frame:RegisterEvent(event)
					else
						frame:RegisterUnitEvent(event, unit)
					end
				end
			end
		end
		self:UpdateEstimateBar(true)
	else
		for unit, frame in _G.pairs(EventFrames) do
			if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
		end
	end
	BST.bars["EstimateBar"]:UpdateVisibility()
end

local function UpdateTime(self, elapsed)
    currentTime = currentTime + elapsed
end

function EstimateBar:UpdateBars(timestamp)
    if addon.idle then
    	if updateTimer then
            updateTimer:Cancel()
            updateTimer = nil
        end
    end
    EstimateBar:UpdateEstimateBar(timestamp)
end

function EstimateBar:UpdateEstimateBar(timestamp)
    if self.estimatebar.db.enabled and not addon.idle then
        local recentDamage = self:GetRecentDamageTaken(timestamp)

        local predictedValue, minimumValue = 0, 0
		local baseValue = recentDamage * dsHealModifier * Tier14Bonus * (1+versatilityPercent)

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

        addon.DataFeed.estimateBar = estimate
        if addon.LDBDataFeed then
            addon:UpdateLDBData()
        end
    end
end

function EstimateBar:UpdateEstimateBarText(estimate)
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
		val = formatPercent:format(
			addon.FormatWithPrecision(estimate / addon.maxHealth * 100))
	else
		val = addon.FormatNumber(estimate)
	end

    self.estimatebar.bar.value:SetText(
        formatStandard:format(
            text, sep, val))
end

function EstimateBar:UpdateEstimateBarTextWithMin()
	local value = 0
    if self.estimatebar.db.bar_mode == "BS" then
        value = bsMinimum
    else
        value = dsHealMin
    end
	self:UpdateEstimateBarText(value)
end

function EstimateBar:UpdateMinHeal(event, unit)
	if unit == "player" then
		local baseValue
		local maxHealth = UnitHealthMax("player")
		actualDsMinHeal = dsMinHealPercent
		if DarkSuccorBuff == true then
			actualDsMinHeal = dsMinHealPercentSuccor
		end
		baseValue = maxHealth * actualDsMinHeal * Tier14Bonus * (1+versatilityPercent)
		dsHealMin = round(baseValue *
			self:GetEffectiveHealingBuffModifiers() * 
			self:GetEffectiveHealingDebuffModifiers())
		bsMinimum = round(baseValue * shieldPercent)
		if addon.idle then
			self:UpdateEstimateBarTextWithMin()
		end
	end
end

function EstimateBar:UpdateEstimates(event, unit)
	if unit == "player" then
		--if addon.idle then
		self:UpdateEstimateBar()
		--end
	end
end

function EstimateBar:PLAYER_REGEN_DISABLED()
	addon.idle = false

	if addon:IsTrackerEnabled() and self.estimatebar.db.enabled then
		updateTimer = _G.C_Timer.NewTicker(UPDATE_TIMER_FREQUENCY, EstimateBar.UpdateBars)
        self.estimatebar.bar:Show()
        self.estimatebar.bar:SetScript("OnUpdate", UpdateTime)
    end
end

function EstimateBar:PLAYER_REGEN_ENABLED()
	addon.idle = true
    if self.estimatebar.db.hide_ooc then
        self.estimatebar.bar:Hide()
    end
end

function EstimateBar:PLAYER_DEAD()
    -- Hide the health bar if configured to do so for OOC
    if self.estimatebar.db.hide_ooc then
        if self.estimatebar.bar:IsVisible() then
            self.estimatebar.bar:Hide()
        end
    end
end

function EstimateBar:GetRecentDamageTaken(timestamp)
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

function EstimateBar:AddDamageTaken(timestamp, damage)
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

local CR_VERSATILITY_DAMAGE_DONE = _G.CR_VERSATILITY_DAMAGE_DONE or 29
function EstimateBar:UpdateRatings()
	local update = false
	local mastery = GetMasteryEffect()
	if mastery ~= masteryRating then
		masteryRating = mastery
		shieldPercent = masteryRating/100
		update = true
	end

	local vers = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) + 
		GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
	if vers ~= versatilityBonus then
		versatilityBonus = vers
		versatilityPercent = versatilityBonus/100
		update = true
	end

	if update then
		self:UpdateEstimates("UpdateRatings", "player")
	end
end

function EstimateBar:PLAYER_ENTERING_WORLD()
	self:UNIT_MAXHEALTH("PLAYER_ENTERING_WORLD", "player")
end

function EstimateBar:PLAYER_ALIVE()
	self:UNIT_MAXHEALTH("PLAYER_ALIVE", "player")
	self:UpdateEstimateBar()
end

function EstimateBar:UNIT_MAXHEALTH(event, unit)
	if unit == "player" then
		local maxHealth = UnitHealthMax("player")
		if maxHealth ~= addon.maxHealth then
			addon.maxHealth = maxHealth or 1
		end
		self:UpdateMinHeal(event, unit)
	end
end

local EstDSHealFmt = "Estimated DS Heal: %d"
function EstimateBar:UNIT_SPELLCAST_SENT(event, unit, spellName)
	if unit == "player" and spellName == SpellNames["Death Strike"] then
		DS_SentTime = GetTime()
		if addon.db.profile.debug then
			BST:Print(EstDSHealFmt:format(estimatedDS))
		end
	end
end

function EstimateBar:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, rank, lineId, spellId)
    if unit == "player" then
		if spellName == SpellNames["Death Strike"] then
	        local succeededTime = GetTime()
	        if DS_SentTime then
	            local diff = succeededTime - DS_SentTime
	            if diff > 0 then
	                DS_Latency = diff
	                if addon.db.profile.debug then
	                    BST:Print("DS Latency: "..DS_Latency)
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

function EstimateBar:CheckAuras()
    local name, rank, icon, count, dispelType, duration, expires,
        caster, stealable, consolidate, spellId, canApplyAura, isBossDebuff,
		castByPlayer, value, value2, value3

    local iccBuffFound = false
    local vampBloodFound = false
    local healingDebuff = 0
	DarkSuccorBuff = false
    luckOfTheDrawBuff = false
    luckOfTheDrawAmt = 0
	healingDebuffMultiplier = 0
    gsHealModifier = 0.0

    -- Loop through unit auras to find ones of interest.
    local i = 1
    repeat
        name, rank, icon, count, dispelType, duration, expires, caster, 
			stealable, consolidate, spellId, canApplyAura, isBossDebuff, 
			castByPlayer, value, value2, value3 = UnitAura("player", i)
        if name == nil or spellId == nil then break end

        if spellId == SpellIds["Dark Succor"] then
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
            vbHealingInc = vbHealingBonus

		elseif spellId == SpellIds["Guardian Spirit"] then
			AurasFound["Guardian Spirit"] = true
			gsHealModifier = guardianSpiritHealBuff

		else
			-- Check for various healing debuffs
			for k,v in pairs(addon.HealingDebuffs) do
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

    -- If the ICC buff isn't present, reset the values
    if not iccBuffFound then
        iccBuff = false
        iccBuffAmt = 0.0
    end

    if not vampBloodFound then
        vbBuff = false
        vbHealingInc = 0.0
    end

	-- Just in case make sure the healing modifier is a sane value
	if healingDebuffMultiplier > 1 then
	    healingDebuffMultiplier = 1
    end

	EstimateBar:UpdateMinHeal("UNIT_MAXHEALTH", "player")
end

local function UpdateTime(self, elapsed)
    currentTime = currentTime + elapsed
end

function EstimateBar:GetEffectiveHealingBuffModifiers()
    return (1+iccBuffAmt) * (1+vbHealingInc) * (1+gsHealModifier) * (1+luckOfTheDrawAmt) * (1+versatilityPercent)
end

function EstimateBar:GetEffectiveHealingDebuffModifiers()
    return (1-healingDebuffMultiplier)
end

function EstimateBar:COMBAT_LOG_EVENT_UNFILTERED(...)
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

	if eventtype:find("SPELL_ABSORBED") and destName == addon.playerName then
		local absorbed
		local absorbId, absorbName
		if param19 then
			absorbed = param19
			absorbId = param16
			absorbName = param17
	        local spellName = param10 or "n/a"
			local school = param11
	        local schoolName = addon.GetSpellSchool(school) or "N/A"
	        if addon.db.profile.debug then
	            local spellAbsFmt = "Spell Absorbed (%s-%s,%d) %d by %s"
	            BST:Print(spellAbsFmt:format(spellName, schoolName, school, absorbed, absorbName))
	        end
		else
			absorbed = param16
			absorbId = param13
			absorbName = param14
	        if addon.db.profile.debug then
	            local spellAbsFmt = "Spell Absorbed (None) %d by %s"
	            BST:Print(spellAbsFmt:format(absorbed, absorbName))
	        end
		end

		if absorbed and absorbId ~= SpellIds["Shroud of Purgatory"] then
			self:AddDamageTaken(timestamp, absorbed)
		end

		--         if addon.db.profile.debug then
		-- 	local fmt = "SPELL_ABSORBED %s %s %s %s %s %s %s %s %s %s %s %s"
		-- 	BST:Print(fmt:format(
		-- 		_G.tostring(param9),
		-- 		_G.tostring(param10),
		-- 		_G.tostring(param11),
		-- 		_G.tostring(param12),
		-- 		_G.tostring(param13),
		-- 		_G.tostring(param14),
		-- 		_G.tostring(param15),
		-- 		_G.tostring(param16),
		-- 		_G.tostring(param17),
		-- 		_G.tostring(param18),
		-- 		_G.tostring(param19),
		-- 		_G.tostring(param20)
		-- 		))
		-- end
	end

    if eventtype:find("_DAMAGE") and destName == addon.playerName then
        if eventtype:find("SWING_") and param9 then
            local damage, absorb = param9, param14 or 0

            if addon.db.profile.debug then
                local swingDmgFmt = "Swing Damage for %d [%d absorbed, %s]"
                BST:Print(swingDmgFmt:format(damage, absorb, eventtype))
            end

            self:AddDamageTaken(timestamp, damage)
        elseif eventtype:find("SPELL_") or eventtype:find("RANGE_") then
            local type
            if eventtype:find("SPELL_") then type = "Spell" end
            if eventtype:find("RANGE_") then type = "Range" end        
            local damage, absorb, school = param12 or 0, param17 or 0, param14 or 0
            local spellName = param10 or "n/a"
            local schoolName = addon.GetSpellSchool(school) or "N/A"

            local countDamage = true
            -- Do not count damage from no source or maybe this is just
            -- particular items like Shannox's Jagged Tear?
            if srcName == nil then
                countDamage = false
                if addon.db.profile.debug then
                    BST:Print("Ignoring no source damage [" .. spellName .. 
                        "] of "..(damage or 0))
                end
            end

            -- Do not count Spirit Link damage since it doesn't affect DS.
            if spellName == SpellIds["Spirit Link"] and 
				srcName == SpellNames["Spirit Link Totem"] then
                countDamage = false
                if addon.db.profile.debug then
                    BST:Print("Ignoring Spirit Link damage of "..(damage or 0))
                end
            end

            if countDamage == true then
                self:AddDamageTaken(timestamp, damage)
            end

            if addon.db.profile.debug then
                local spellDmgFmt = "%s Damage (%s-%s,%d) for %d [%d absorbed]"
                BST:Print(spellDmgFmt:format(
                    type, spellName, schoolName, school, damage, absorb))
            end
        end
    end    

    if eventtype:find("_MISSED") and destName == addon.playerName then
        if eventtype == "SWING_MISSED" then
            if param9 and param9 == "ABSORB" then
    			local damage = 0
   			    damage = param11 or 0

                if addon.db.profile.debug then
                    local absorbFmt = "Absorbed swing for %d"
                    BST:Print(absorbFmt:format(damage))
                end
            end
        elseif eventtype:find("SPELL_") then
            if param12 and param12 == 'ABSORB' then
                local damage = 0
                damage = param14 or 0

                local spellName, school = param10 or "n/a", param11 or 0
                local schoolName = addon.GetSpellSchool(school) or "N/A"

                if addon.db.profile.debug then
                    local absorbFmt = "Absorbed spell (%s-%s,%d) for %d"
                    BST:Print(absorbFmt:format(spellName, schoolName, school, damage))
                end
            end
        end
    end

	if eventtype == "SPELL_CAST_SUCCESS" and srcName == addon.playerName and 
	    param9 == SpellIds["Death Strike"] then

        if addon.db.profile.debug then
            local dsHealFormat = "Estimated damage: %d will be a heal for: %d"
            local recentDmg = self:GetRecentDamageTaken(timestamp)
            local predictedHeal = 0
            if healingDebuffMultiplier ~= 1 then 
                predictedHeal = round(
                    recentDmg * dsHealModifier * Tier14Bonus  *
                    self:GetEffectiveHealingBuffModifiers() * 
                    self:GetEffectiveHealingDebuffModifiers())
            end
    		BST:Print(dsHealFormat:format(recentDmg, predictedHeal))
        end
	end

    if eventtype == "SPELL_HEAL" and destName == addon.playerName 
        and param9 == SpellIds["Death Strike Heal"] then
        
        local totalHeal = param12 or 0
        local overheal = param13 or 0
        local actualHeal = param12-param13

        -- Update the LDB data feed
        addon.DataFeed.lastDS = totalHeal
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
            predictedHeal = round(recentDmg * dsHealModifier * Tier14Bonus *
                self:GetEffectiveHealingBuffModifiers() * 
                self:GetEffectiveHealingDebuffModifiers())
        end

        if addon.db.profile.debug then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Pred:%d, Mast: %0.2f%%, Vers: %0.2f%%]"
            BST:Print(dsHealFormat:format(
				totalHeal,actualHeal,overheal,predictedHeal,masteryRating, versatilityBonus))
        end
        
        if addon.DEBUG_OUTPUT == true then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Pred:%d, Mast: %0.2f%%, Vers: %0.2f%%]"
            addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " .. 
                dsHealFormat:format(totalHeal,actualHeal,overheal, predictedHeal, 
				masteryRating, versatilityBonus) .. "\n"
        end
    end
end

function EstimateBar:GetOptions()
	return "estimateBarOpts", self:GetEstimateBarOptions()
end

function EstimateBar:AddOptions()
	return "EstimateBar", L["Estimate Bar"], "estimateBarOpts"
end

function EstimateBar:GetEstimateBarOptions()
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
				    addon.db.profile.bars["EstimateBar"].enabled = val
					addon.bars["EstimateBar"]:UpdateVisibility()
				end,
	            get = function(info)
					return addon.db.profile.bars["EstimateBar"].enabled 
				end,
			},
			lock_bar = {
				name = L["Lock bar"],
				desc = L["LockBarDesc"],
				type = "toggle",
				order = 30,
				set = function(info, val)
				    addon.db.profile.bars["EstimateBar"].locked = val 
					self.estimatebar:Lock()
				end,
	            get = function(info)
					return addon.db.profile.bars["EstimateBar"].locked
				end,
			},
			hide_ooc = {
				name = L["Hide out of combat"],
				desc = L["HideOOC_OptionDesc"],
				type = "toggle",
				order = 40,
				set = function(info, val)
				    addon.db.profile.bars["EstimateBar"].hide_ooc = val
					if not _G.InCombatLockdown() then
					    if val then
					        self.estimatebar.bar:Hide()
				        elseif addon:IsTrackerEnabled() then
				            self.estimatebar.bar:Show()
			            end
			        end
				end,
	            get = function(info)
	                return addon.db.profile.bars["EstimateBar"].hide_ooc
	            end,
			},
			show_text = {
				name = L["Show Text"],
				desc = L["EstHealBarShowText_OptDesc"],
				type = "toggle",
				order = 50,
				set = function(info, val)
				    addon.db.profile.bars["EstimateBar"].show_text = val
				    self:UpdateMinHeal("UpdateShowText", "player")
				end,
	            get = function(info)
					return addon.db.profile.bars["EstimateBar"].show_text
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
				    addon.db.profile.bars["EstimateBar"].bar_mode = val
				end,
	            get = function(info)
	                return addon.db.profile.bars["EstimateBar"].bar_mode
	            end,
			},
			usePercent = {
				name = L["Percent"],
				desc = L["Percent_OptDesc"],
				type = "toggle",
				order = 70,
				set = function(info, val)
				    addon.db.profile.bars["EstimateBar"].usePercent = val
				end,
	            get = function(info)
					return addon.db.profile.bars["EstimateBar"].usePercent 
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
				    addon.db.profile.bars["EstimateBar"].alternateMinimum = val
				end,
	            get = function(info)
					return addon.db.profile.bars["EstimateBar"].alternateMinimum 
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
				    local c = addon.db.profile.bars["EstimateBar"].textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
					self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["EstimateBar"].textcolor
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
				    local c = addon.db.profile.bars["EstimateBar"].color
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["EstimateBar"].color
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
				    local c = addon.db.profile.bars["EstimateBar"].bgcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["EstimateBar"].bgcolor
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
				    local c = addon.db.profile.bars["EstimateBar"].alt_textcolor
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["EstimateBar"].alt_textcolor
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
				    local c = addon.db.profile.bars["EstimateBar"].alt_color
				    c.r, c.g, c.b, c.a = r, g, b, a
			        self.estimatebar:UpdateGraphics()
				end,
				get = function(info)
			        local c = addon.db.profile.bars["EstimateBar"].alt_color
				    return c.r, c.g, c.b, c.a
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
				    addon.db.profile.bars["EstimateBar"].latencyMethod = val
				end,
	            get = function(info)
	                return addon.db.profile.bars["EstimateBar"].latencyMethod
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
				    addon.db.profile.bars["EstimateBar"].latencyFixed = val 
				end,
				get = function(info, val)
				    return addon.db.profile.bars["EstimateBar"].latencyFixed
				end,					
			},
		}
	}

	BST:AddDimensionOptions(estimateBarOpts, "EstimateBar", 200)
	BST:AddPositionOptions(estimateBarOpts, "EstimateBar", 300)
	BST:AddAppearanceOptions(estimateBarOpts, "EstimateBar")
	BST:AddAdvancedPositioning(estimateBarOpts, "EstimateBar")
	return estimateBarOpts
end
