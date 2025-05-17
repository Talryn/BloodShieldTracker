local _G = getfenv(0)
local ADDON_NAME, addon = ...
local LibStub = _G.LibStub
local BST = LibStub("AceAddon-3.0"):GetAddon(addon.addonNameCondensed)
local L = LibStub("AceLocale-3.0"):GetLocale(addon.addonNameCondensed)

-- Local versions for performance
local ceil = _G.math.ceil
local table = _G.table
local tostring = _G.tostring
local ipairs = _G.ipairs
local pairs = _G.pairs
local tinsert, tremove = table.insert, table.remove
local wipe = _G.wipe
local round = addon.round
local max = _G.math.max

-- Local versions of WoW API calls
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local GetTime = _G.GetTime
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitAttackPower = _G.UnitAttackPower
local GetMastery = _G.GetMastery
local GetMasteryEffect = _G.GetMasteryEffect
local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo

local SpellIds = addon.SpellIds
local SpellNames = addon.SpellNames

local formatStandard = "%s%s%s"
local formatPercent = "%s%%"

local AurasFound = {}
local HealingBuffsFound = {}

local module = {}
module.name = "EstimateBar"
addon:RegisterModule(module.name, module)
module.enabled = false

addon.defaults.profile.bars["EstimateBar"] = {
    enabled = true,
    hide_ooc = false,
    show_text = true,
    bar_mode = "DS",
    usePercent = false,
    alternateMinimumMode = "None",
    alternateMinimumValue = 0,
    alternateMinimumPercent = 0,
    show_stacks = true,
    stacks_pos = "LEFT",
    latencyMethod = "None",
    latencyFixed = 0,
    color = { r = 1.0, g = 0.0, b = 0.0, a = 1 },
    bgcolor = { r = 0.65, g = 0.0, b = 0.0, a = 0.8 },
    alt_color = { r = 0.0, g = 1.0, b = 0.0, a = 1 },
    alt_bgcolor = { r = 0.0, g = 0.65, b = 0.0, a = 0.8 },
    alt_textcolor = { r = 1.0, g = 1.0, b = 1.0, a = 1 },
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
local afterTimer = nil
local lastSeconds = 5
local damageTaken = {}
local removeList = {}

-- Constants from abilities / gear.
local dsHealModifierBase = addon.Cata and 0.20 or 0.25 -- Percent of the DS Heal from the tooltip.
local dsHealModifier = dsHealModifierBase
local dsMinHealPercent = 0.07
local dsMinHealPercentSuccor = 0.20
local bsStaticModifier = 1.0
local impDSModifierCurrent = 1.0
local BaseVBHealingBonus = 0.30
local staticModifiers = {
    ds = {
        ["Voracious"] = 0.15,
        ["Improved Death Strike"] = 0.05,
    },
    bs = {
        ["Gloom Ward"] = 0.15,
        ["Iron Heart"] = 0.20,
    },
}
local vbHealingBonus = BaseVBHealingBonus
local guardianSpiritHealBuff = 0.40
local HealingBuffs = {
    [SpellIds["Guardian Spirit"]] = 0.40,
    [SpellIds["Divine Hymn"]] = 0.04,
    [SpellIds["Protection of Tyr"]] = 0.15,
    [SpellIds["Lana'thel's Lament"]] = 0.05,
    [SpellIds["Hellscream's Warsong 30"]] = 0.30, -- Horde ICC Bonus
    [SpellIds["Strength of Wrynn 30"]] = 0.30, -- Alliance ICC Bonus
    [SpellIds["Hemostasis"]] = 0.08,           -- Talent
    [SpellIds["Sanguine Ground"]] = 0.05,      -- Talent
}

-- Curent state information
local DarkSuccorBuff = false
local DS_SentTime = nil
local DS_Latency = nil
addon.maxHealth = 1
local dsHealMin = 0
local bsMinimum = 0
-- End --

-- Alternative minimum
local altMinMode = ""
local altMinValue = 0
local altMinPercent = 0

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
local voraciousBonus = 0
local dsMinHealCurrent = 0

function module:SetProfile()
    self.profile = addon.db.profile.bars.EstimateBar
end

function module.ProfileUpdate()
    module:SetProfile()
end

function module:OnInitialize()
    addon:RegisterCallback("ProfileUpdate", module.name, module.ProfileUpdate)
    self:SetProfile()
end

function module.TalentUpdate()
    module:Toggle()
end

function module:Enable()
    addon:RegisterCallback("TalentUpdate", module.name, module.TalentUpdate)
    self:Toggle()
end

function module:Disable()
    addon:UnregisterCallback("TalentUpdate", module.name)
    self:OnDisable()
end

function module.GearUpdate()
    -- local currentBonus = Tier14Bonus
    -- Tier14Bonus = 1 + (addon.tierCount["T14 Tank"] >= 4 and T14BonusAmt or 0)
    -- if currentBonus ~= Tier14Bonus then
    -- 	module:UpdateMinHeal("CheckGear", "player")
    -- 	if addon.db.profile.verbose and addon.idle then
    -- 		local fmt = "T14 Bonus: %d%%"
    -- 		BST:Print(fmt:format(Tier14Bonus*100-100))
    -- 	end
    -- end
end

function module:ArtifactUpdate()
end

function module.WeaponUpdate()
    module:ArtifactUpdate()
end

local UnitEventsClassic = {
    ["any"] = {
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_ALIVE",
        "PLAYER_DEAD",
        "COMBAT_LOG_EVENT_UNFILTERED",
        "PLAYER_ENTERING_WORLD",
        "COMBAT_RATING_UPDATE",
        "MASTERY_UPDATE",
        "UNIT_SPELLCAST_SENT",
    },
    ["player"] = {
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_MAXHEALTH",
        -- "UNIT_AURA",
    },
}

local UnitEventsCurrent = {
    ["any"] = {
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_ALIVE",
        "PLAYER_DEAD",
        "COMBAT_LOG_EVENT_UNFILTERED",
        "PLAYER_ENTERING_WORLD",
        "COMBAT_RATING_UPDATE",
        "MASTERY_UPDATE",
        "ARTIFACT_UPDATE",
        "ARTIFACT_XP_UPDATE",
        "UNIT_SPELLCAST_SENT",
    },
    ["player"] = {
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_MAXHEALTH",
        -- "UNIT_AURA",
    },
}
local UnitEvents = addon.Cata and UnitEventsClassic or UnitEventsCurrent

local function EventFrame_OnEvent(frame, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        module:PLAYER_REGEN_DISABLED(event, ...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        module:PLAYER_REGEN_ENABLED(event, ...)
    elseif event == "PLAYER_ALIVE" then
        module:PLAYER_ALIVE(event, ...)
    elseif event == "PLAYER_DEAD" then
        module:PLAYER_DEAD(event, ...)
    elseif event == "UNIT_SPELLCAST_SENT" then
        module:UNIT_SPELLCAST_SENT(event, ...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        module:UNIT_SPELLCAST_SUCCEEDED(event, ...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        module:PLAYER_ENTERING_WORLD(event, ...)
    elseif event == "UNIT_MAXHEALTH" then
        module:UNIT_MAXHEALTH(event, ...)
        -- elseif event == "UNIT_AURA" then
        -- 	module:UNIT_AURA(event, ...)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        module:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
        -- Send directly to particular functions
    elseif event == "COMBAT_RATING_UPDATE" then
        module:UpdateRatings(event, ...)
    elseif event == "MASTERY_UPDATE" then
        module:UpdateRatings(event, ...)
    elseif event == "ARTIFACT_UPDATE" then
        module:ArtifactUpdate(event, ...)
    elseif event == "ARTIFACT_XP_UPDATE" then
        module:ArtifactUpdate(event, ...)
    end
end
local EventFrames = {}

function module:CreateDisplay()
    self.estimatebar = addon.Bar:Create({
        name = "EstimateBar",
        friendlyName = "Estimate Bar",
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
            PostInitialize = function(self)
                addon.SkinFrame(self.bar)
            end,
        },
    })
    self.estimatebar:Hide()
end

function module:GetDSModifier()
    local modifier = dsHealModifierBase
    for key, value in pairs(staticModifiers.ds) do
        if addon.HasActiveTalent(key) then
            if _G.type(value) == "number" then
                modifier = modifier * (1 + value)
            end
        end
    end
    if addon.Cata then
        -- Add the appropriate modifier for damage-based heals.
        local impDSRanks = _G.select(5, _G.GetTalentInfo(1, 12)) or 0
        if _G.type(impDSRanks) == "number" and impDSRanks <= 3 then
            local impDSMod = impDSRanks * 0.15
            modifier = modifier * (1 + impDSMod)
        else
            if addon.db.profile.debug then
                addon:Print("Invalid Improved Death Strike ranks!")
            end
        end
    end
    return modifier
end

function module:GetShieldModifier()
    local modifier = 1.0
    for key, value in pairs(staticModifiers.bs) do
        if addon.HasActiveTalent(key) then
            if _G.type(value) == "number" then
                modifier = modifier * (1 + value)
            end
        end
    end
    return modifier
end

function module:OnEnable()
    if not self.estimatebar then self:CreateDisplay() end
    addon:RegisterCallback("Auras", module.name, module.CheckAuras)
    addon:RegisterCallback("GearUpdate", module.name, module.GearUpdate)
    addon:RegisterCallback("WeaponUpdate", module.name, module.WeaponUpdate)

    vbHealingBonus = self:GetVBBonus()
    voraciousBonus = self:GetVoraciousBonus()

    if addon.Cata then
        -- Cata's Improved DS does not affect minimum heal
        impDSModifierCurrent = 1.0
        dsMinHealCurrent = dsMinHealPercent
    else
        impDSModifierCurrent = addon.HasActiveTalent("Improved Death Strike") and
        (1 + staticModifiers.ds["Improved Death Strike"]) or 1.0
        dsMinHealCurrent = dsMinHealPercent * (1 + voraciousBonus) * impDSModifierCurrent
    end

    dsHealModifier = self:GetDSModifier()
    bsStaticModifier = self:GetShieldModifier()

    if addon.db.profile.debug then
        addon:Print("DS Min Heal: " .. _G.tostring(dsMinHealCurrent))
        addon:Print("DS Heal Modifier: " .. _G.tostring(dsHealModifier))
        addon:Print("BS Modifier: " .. _G.tostring(bsStaticModifier))
        addon:Print("VB Healing Bonus: " .. _G.tostring(vbHealingBonus))
        addon:Print("Voracious Bonus: " .. _G.tostring(voraciousBonus))
    end
    module.UpdateRatings = addon.Cata and module.UpdateRatingsClassic or module.UpdateRatingsCurrent
    self:UpdateRatings()
    self:UpdateAlternateMinimum()

    for unit, events in _G.pairs(UnitEvents) do
        local frame = EventFrames[unit] or _G.CreateFrame("Frame",
            ADDON_NAME .. "_ESTBAR_EventFrame_" .. unit)
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
    addon.idle = not _G.UnitAffectingCombat("player")
    if not self.estimatebar.db.hide_ooc or not addon.idle then
        self.estimatebar:Show()
    end
    if addon.idle then
        self:UpdateMinHeal("PLAYER_ENTERING_WORLD", "player")
    else
        self:UpdateEstimateBar()
    end
    self.estimatebar:UpdateVisibility()
    self.enabled = true
end

function module:OnDisable()
    addon:UnregisterCallback("Auras", module.name)
    addon:UnregisterCallback("GearUpdate", module.name)
    addon:UnregisterCallback("WeaponUpdate", module.name)
    for unit, frame in _G.pairs(EventFrames) do
        if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    end
    if self.estimatebar then self.estimatebar:Hide() end
    self.enabled = false
end

function module:Toggle()
    if self.profile.enabled and addon:IsTrackerEnabled() then
        self:OnEnable()
    else
        self:OnDisable()
    end
end

local function UpdateTime(self, elapsed)
    currentTime = currentTime + elapsed
end

function module:UpdateAfterCombat()
    if afterTimer then
        afterTimer:Cancel()
        afterTimer = nil
    end
    if not _G.UnitAffectingCombat("player") then
        module:UpdateMinHeal("CombatEnd", "player")
        module.estimatebar.altcolor = false
        module.estimatebar:UpdateGraphics()
    end
end

function module:UpdateBars(timestamp)
    if addon.idle then
        if updateTimer then
            updateTimer:Cancel()
            updateTimer = nil
            if not afterTimer then
                afterTimer = _G.C_Timer.NewTimer(6.0, module.UpdateAfterCombat)
            end
        end
    end
    module:UpdateEstimateBar(timestamp)
end

function module:UpdateEstimateBar(timestamp)
    if self.estimatebar.db.enabled and not addon.idle then
        local recentDamage = self:GetRecentDamageTaken(timestamp)

        local predictedValue, minimumValue = 0, 0
        local baseValue = recentDamage * dsHealModifier *
            (1 + versatilityPercent)

        if self.estimatebar.db.bar_mode == "BS" then
            predictedValue = round(baseValue * shieldPercent * bsStaticModifier)
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
        local predictedPercent = predictedValue / addon.maxHealth

        self:UpdateEstimateBarText(estimate)
        self.estimatebar.bar:SetMinMaxValues(0, minimumValue)

        if altMinMode == "V" and predictedValue >= altMinValue then
            self.estimatebar.altcolor = true
            self.estimatebar.bar:SetValue(predictedValue)
        elseif altMinMode == "%" and predictedPercent >= altMinPercent then
            self.estimatebar.altcolor = true
            self.estimatebar.bar:SetValue(predictedValue)
        elseif altMinMode == "" and predictedValue > minimumValue then
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

function module:UpdateEstimateBarText(estimate)
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

function module:UpdateEstimateBarTextWithMin()
    local value = 0
    if self.estimatebar.db.bar_mode == "BS" then
        value = bsMinimum
    else
        value = dsHealMin
    end
    self:UpdateEstimateBarText(value)
end

function module:UpdateMinHeal(event, unit)
    if unit == "player" then
        local baseValue
        local maxHealth = UnitHealthMax("player")
        baseValue = maxHealth *
            (DarkSuccorBuff and dsMinHealPercentSuccor or dsMinHealCurrent) *
            (1 + versatilityPercent)
        local newMin = round(baseValue *
            self:GetEffectiveHealingBuffModifiers() *
            self:GetEffectiveHealingDebuffModifiers())
        bsMinimum = round(baseValue * shieldPercent * bsStaticModifier)
        if newMin ~= dsHealMin then
            local newMinFnt = "DS Heal Min: %d, BS Min: %d"
            if addon.db.profile.debug then
                addon:Print(newMinFnt:format(newMin, bsMinimum))
            end
            if addon.DEBUG_OUTPUT == true then
                addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. currentTime .. "   " ..
                    newMinFnt:format(newMin) .. "\n"
            end
        end
        dsHealMin = newMin
        if addon.idle then
            self:UpdateEstimateBarTextWithMin()
        end
    end
end

function module:UpdateEstimates(event, unit)
    if unit == "player" then
        --if addon.idle then
        self:UpdateEstimateBar()
        --end
    end
end

function module:PLAYER_REGEN_DISABLED()
    addon.idle = false

    if addon:IsTrackerEnabled() and self.estimatebar.db.enabled then
        if afterTimer then
            afterTimer:Cancel()
            afterTimer = nil
        end
        updateTimer = _G.C_Timer.NewTicker(UPDATE_TIMER_FREQUENCY, module.UpdateBars)
        self.estimatebar.bar:Show()
        self.estimatebar.bar:SetScript("OnUpdate", UpdateTime)
    end
end

function module:PLAYER_REGEN_ENABLED()
    addon.idle = true
    if self.estimatebar.db.hide_ooc then
        self.estimatebar.bar:Hide()
    end
end

function module:PLAYER_DEAD()
    -- Hide the health bar if configured to do so for OOC
    if self.estimatebar.db.hide_ooc then
        if self.estimatebar.bar:IsVisible() then
            self.estimatebar.bar:Hide()
        end
    end
end

function module:GetRecentDamageTaken(timestamp)
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

function module:AddDamageTaken(timestamp, damage)
    -- Add the new damage taken data
    tinsert(damageTaken, { timestamp, damage })
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

local function GetSpellDescription(name)
    if C_Spell.GetSpellDescription then
        return C_Spell.GetSpellDescription(name)
    else
        return _G.GetSpellDescription(name)
    end
end

module.vampBloodBonuses = {
    ["30"] = 0.3,
    ["35"] = 0.35,
    ["40"] = 0.40,
    ["45"] = 0.45,
    ["50"] = 0.50,
    ["55"] = 0.55,
    ["60"] = 0.60,
    ["65"] = 0.65,
}
function module:GetVBBonus()
    if addon.currentSpec ~= "Blood" then return 0 end

    local desc = GetSpellDescription(SpellIds["Vampiric Blood"])
    local matches = _G.string.gmatch(desc, "(%d%d)%%")
    local healthBonus = matches()
    local healingBonus = matches()
    if addon.db.profile.debug then
        local fmt = "Vampiric Blood healing bonus: %s"
        addon:Print(fmt:format(_G.tostring(healingBonus)))
    end
    if healingBonus ~= nil then
        local value = self.vampBloodBonuses[healingBonus]
        if value ~= nil then
            return value
        end
    end
    return BaseVBHealingBonus
end

function module:GetVoraciousBonus()
    if addon.currentSpec ~= "Blood" then return 0 end
    if addon.HasActiveTalent("Voracious") then
        return staticModifiers.ds["Voracious"] or 0
    else
        return 0
    end
end

local CR_VERSATILITY_DAMAGE_DONE = _G.CR_VERSATILITY_DAMAGE_DONE or 29
function module:UpdateRatingsCurrent()
    local update = false
    local mastery = GetMasteryEffect()
    if mastery ~= masteryRating then
        masteryRating = mastery
        shieldPercent = masteryRating / 100
        update = true
    end

    local vers = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) +
        GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
    if vers ~= versatilityBonus then
        versatilityBonus = vers
        versatilityPercent = versatilityBonus / 100
        update = true
    end

    if update then
        if addon.db.profile.debug then
            local fmt = "Versatility: %0.4f%%"
            addon:Print(fmt:format(versatilityBonus))
        end
        self:UpdateEstimates("UpdateRatings", "player")
    end
end

function module:UpdateRatingsClassic()
    local update = false
    local mastery = GetMastery()
    if mastery ~= masteryRating then
        masteryRating = mastery
        shieldPercent = masteryRating / 100 * 6.25
        update = true
    end
    if update then
        self:UpdateEstimates("UpdateRatings", "player")
    end
end

function module:UpdateAlternateMinimum()
    local bar = addon.db.profile.bars["EstimateBar"]
    if bar.alternateMinimumMode == "Value" then
        altMinMode = "V"
        altMinValue = bar.alternateMinimumValue or 0
        altMinPercent = 0
    elseif bar.alternateMinimumMode == "Percent" then
        altMinMode = "%"
        altMinValue = 0
        altMinPercent = bar.alternateMinimumPercent or 0
    else
        altMinMode = ""
        altMinValue = 0
        altMinPercent = 0
    end
end

function module:PLAYER_ENTERING_WORLD()
    self:UNIT_MAXHEALTH("PLAYER_ENTERING_WORLD", "player")
end

function module:PLAYER_ALIVE()
    self:UNIT_MAXHEALTH("PLAYER_ALIVE", "player")
    self:UpdateEstimateBar()
end

function module:UNIT_MAXHEALTH(event, unit)
    if unit == "player" then
        local maxHealth = UnitHealthMax("player")
        if maxHealth ~= addon.maxHealth then
            addon.maxHealth = maxHealth or 1
        end
        self:UpdateMinHeal(event, unit)
    end
end

local EstDSHealFmt = "Estimated DS Heal: %d"
function module:UNIT_SPELLCAST_SENT(event, unit, target, castGUID, spellId)
    if unit == "player" and spellId == SpellIds["Death Strike"] then
        DS_SentTime = GetTime()
        if addon.db.profile.debug then
            addon:Print(EstDSHealFmt:format(estimatedDS))
        end
    end
end

function module:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellId)
    if unit == "player" then
        if spellId == SpellIds["Death Strike"] then
            local succeededTime = GetTime()
            if DS_SentTime then
                local diff = succeededTime - DS_SentTime
                if diff > 0 then
                    DS_Latency = diff
                    if addon.db.profile.debug then
                        addon:Print("DS Latency: " .. DS_Latency)
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

function module:CheckAuras()
    wipe(AurasFound)
    wipe(HealingBuffsFound)

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
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i)
        if not aura then break end
        local spellId = aura.spellId

        if spellId == SpellIds["Dark Succor"] then
            DarkSuccorBuff = true
        elseif spellId == SpellIds["Luck of the Draw"] then
            luckOfTheDrawBuff = true
            local stacks = max(aura.applications or 0, 1)
            luckOfTheDrawAmt = addon.LUCK_OF_THE_DRAW_MOD * stacks
        elseif spellId == SpellIds["Vampiric Blood"] then
            vampBloodFound = true
            vbBuff = true
            vbHealingInc = vbHealingBonus
        elseif HealingBuffs[spellId] then
            local stacks = max(aura.applications or 0, 1)
            HealingBuffsFound[spellId] = HealingBuffs[spellId] * stacks
        else
            local amount = addon.HealingDebuffs[spellId]
            if amount then
                local stacks = max(aura.applications or 0, 1)
                healingDebuff = amount * stacks
                if healingDebuff > healingDebuffMultiplier then
                    healingDebuffMultiplier = healingDebuff
                end
            end
        end

        i = i + 1
    until aura == nil

    if not vampBloodFound then
        vbBuff = false
        vbHealingInc = 0.0
    end

    -- Just in case make sure the healing modifier is a sane value
    if healingDebuffMultiplier > 1 then
        healingDebuffMultiplier = 1
    end

    module:UpdateMinHeal("UNIT_MAXHEALTH", "player")
end

local function UpdateTime(self, elapsed)
    currentTime = currentTime + elapsed
end

function module:GetEffectiveHealingBuffModifiers()
    local healingBuffs = 1.0
    for id, bonus in pairs(HealingBuffsFound) do
        if bonus and bonus > 0 then
            healingBuffs = healingBuffs * (1 + bonus)
        end
    end
    return (1 + vbHealingInc) * (1 + luckOfTheDrawAmt) * healingBuffs
end

function module:GetEffectiveHealingDebuffModifiers()
    return (1 - healingDebuffMultiplier)
end

function module:COMBAT_LOG_EVENT_UNFILTERED(...)
    local event = "COMBAT_LOG_EVENT_UNFILTERED"

    local timestamp, eventtype, hideCaster,
    srcGUID, srcName, srcFlags, srcRaidFlags,
    destGUID, destName, destFlags, destRaidFlags,
    param9, param10, param11, param12, param13, param14,
    param15, param16, param17, param18, param19, param20 = CombatLogGetCurrentEventInfo()

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
            if addon.db.profile.debugdmg then
                local spellAbsFmt = "Spell Absorbed (%s-%s,%d) %d by %s"
                if addon.db.profile.debug then
                    addon:Print(spellAbsFmt:format(spellName, schoolName, school, absorbed, absorbName))
                end
                if addon.DEBUG_OUTPUT == true then
                    addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " ..
                        spellAbsFmt:format(spellName, schoolName, school, absorbed, absorbName) .. "\n"
                end
            end
        else
            absorbed = param16
            absorbId = param13
            absorbName = param14
            if addon.db.profile.debugdmg then
                local spellAbsFmt = "Spell Absorbed (None) %d by %s"
                if addon.db.profile.debug then
                    addon:Print(spellAbsFmt:format(absorbed, absorbName))
                end
                if addon.DEBUG_OUTPUT == true then
                    addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " ..
                        spellAbsFmt:format(absorbed, absorbName) .. "\n"
                end
            end
        end

        if absorbed and absorbId ~= SpellIds["Shroud of Purgatory"] then
            self:AddDamageTaken(timestamp, absorbed)
        end

        --         if addon.db.profile.debug then
        -- 	local fmt = "SPELL_ABSORBED %s %s %s %s %s %s %s %s %s %s %s %s"
        -- 	addon:Print(fmt:format(
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

            if addon.db.profile.debugdmg then
                local swingDmgFmt = "Swing Damage for %d [%d absorbed, %s]"
                if addon.db.profile.debug then
                    addon:Print(swingDmgFmt:format(damage, absorb, eventtype))
                end
                if addon.DEBUG_OUTPUT == true then
                    addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " ..
                        swingDmgFmt:format(damage, absorb, eventtype) .. "\n"
                end
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
                        "] of " .. (damage or 0))
                end
            end

            -- Do not count Spirit Link damage since it doesn't affect DS.
            if spellName == SpellIds["Spirit Link"] and
                srcName == SpellNames["Spirit Link Totem"] then
                countDamage = false
                if addon.db.profile.debug and addon.db.profile.debugdmg then
                    BST:Print("Ignoring Spirit Link damage of " .. (damage or 0))
                end
            end

            if countDamage == true then
                self:AddDamageTaken(timestamp, damage)
            end

            if addon.db.profile.debugdmg then
                local spellDmgFmt = "%s Damage (%s-%s,%d) for %d [%d absorbed] cnt: %s"
                if addon.db.profile.debug then
                    BST:Print(spellDmgFmt:format(
                        type, spellName, schoolName, school, damage, absorb, tostring(countDamage)))
                end
                if addon.DEBUG_OUTPUT == true then
                    addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " ..
                        spellDmgFmt:format(type, spellName, schoolName, school,
                            damage, absorb, tostring(countDamage)) .. "\n"
                end
            end
        end
    end

    if eventtype:find("_MISSED") and destName == addon.playerName then
        if eventtype == "SWING_MISSED" then
            if param9 and param9 == "ABSORB" then
                local damage = 0
                damage = param11 or 0

                if addon.db.profile.debugdmg then
                    local absorbFmt = "Absorbed swing for %d"
                    if addon.db.profile.debug then
                        BST:Print(absorbFmt:format(damage))
                    end
                    if addon.DEBUG_OUTPUT == true then
                        addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " ..
                            absorbFmt:format(damage) .. "\n"
                    end
                end
            end
        elseif eventtype:find("SPELL_") then
            if param12 and param12 == 'ABSORB' then
                local damage = 0
                damage = param14 or 0

                local spellName, school = param10 or "n/a", param11 or 0
                local schoolName = addon.GetSpellSchool(school) or "N/A"

                if addon.db.profile.debugdmg then
                    local absorbFmt = "Absorbed spell (%s-%s,%d) for %d"
                    if addon.db.profile.debug then
                        BST:Print(absorbFmt:format(spellName, schoolName, school, damage))
                    end
                    if addon.DEBUG_OUTPUT == true then
                        addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " ..
                            absorbFmt:format(spellName, schoolName, school, damage) .. "\n"
                    end
                end
            end
        end
    end

    if eventtype == "SPELL_CAST_SUCCESS" and srcName == addon.playerName and
        param9 == SpellIds["Death Strike"] then
        if addon.db.profile.debug or addon.DEBUG_OUTPUT == true then
            local dsHealFormat = "Estimated damage: %d will be a heal for: %d"
            local recentDmg = self:GetRecentDamageTaken(timestamp)
            local predictedHeal = 0
            if healingDebuffMultiplier ~= 1 then
                predictedHeal = round(
                    recentDmg * dsHealModifier *
                    (1 + versatilityPercent) *
                    self:GetEffectiveHealingBuffModifiers() *
                    self:GetEffectiveHealingDebuffModifiers())
            end
            if addon.db.profile.debug then
                BST:Print(dsHealFormat:format(recentDmg, predictedHeal))
            end
            if addon.DEBUG_OUTPUT == true then
                addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " ..
                    dsHealFormat:format(recentDmg, predictedHeal) .. "\n"
            end
        end
    end

    if eventtype == "SPELL_HEAL" and destName == addon.playerName
        and param9 == SpellIds["Death Strike Heal"] then
        local totalHeal = param12 or 0
        local overheal = param13 or 0
        local actualHeal = param12 - param13

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
            shieldValue = round(totalHeal * shieldPercent *
                bsStaticModifier /
                self:GetEffectiveHealingBuffModifiers() /
                self:GetEffectiveHealingDebuffModifiers())
            if shieldValue <= bsMinimum then
                isMinimum = true
                shieldValue = bsMinimum
            end
            predictedHeal = round(
                recentDmg * dsHealModifier *
                (1 + versatilityPercent) *
                self:GetEffectiveHealingBuffModifiers() *
                self:GetEffectiveHealingDebuffModifiers()
            )
        end

        if addon.db.profile.debug then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Pred:%d, Recent: %d, Mast: %0.2f%%, Vers: %0.2f%%]"
            BST:Print(dsHealFormat:format(totalHeal, actualHeal, overheal,
                predictedHeal, recentDmg, masteryRating, versatilityBonus))
        end

        if addon.DEBUG_OUTPUT == true then
            local dsHealFormat = "DS [Tot:%d, Act:%d, O:%d, Pred:%d, Recent: %d, Mast: %0.2f%%, Vers: %0.2f%%]"
            addon.DEBUG_BUFFER = addon.DEBUG_BUFFER .. timestamp .. "   " ..
                dsHealFormat:format(totalHeal, actualHeal, overheal,
                    predictedHeal, recentDmg, masteryRating, versatilityBonus) .. "\n"
        end
    end
end

function module:MigrateSettings(version)
    if version < 2 then
        self:MigrateEstimateBarSettings2()
    end
    if version < 5 then
        self:MigrateAlternateMin()
    end
end

function module:MigrateAlternateMin()
    local bar = addon.db.profile.bars["EstimateBar"]
    local value = bar.alternateMinimum
    if value ~= nil and value > 0 then
        addon.db.profile.bars["EstimateBar"].alternateMinimumMode = "Value"
        addon.db.profile.bars["EstimateBar"].alternateMinimumValue = value
    end
    addon.db.profile.bars["EstimateBar"].alternateMinimum = nil
end

function module:GetOptions()
    return "estimateBarOpts", self:GetModuleOptions()
end

function module:AddOptions()
    return "EstimateBar", L["Estimate Bar"], "estimateBarOpts"
end

function module:GetModuleOptions()
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
                    if val then self:OnEnable() else self:OnDisable() end
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
                    self.estimatebar:Lock(val)
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
            altMinHdr = {
                order = 100,
                type = "header",
                name = L["Alternate Minimum"],
            },
            altMinDescription = {
                order = 105,
                type = "description",
                name = L["AlternateMinimumHdr_Desc"],
            },
            altMinMode = {
                name = L["Mode"],
                desc = L["AltMinMode_Desc"],
                type = "select",
                values = {
                    ["None"] = L["None"],
                    ["Value"] = L["Value"],
                    ["Percent"] = L["Percent"],
                },
                order = 110,
                set = function(info, val)
                    addon.db.profile.bars["EstimateBar"].alternateMinimumMode = val
                    self:UpdateAlternateMinimum()
                end,
                get = function(info)
                    return addon.db.profile.bars["EstimateBar"].alternateMinimumMode
                end,
            },
            alternateMinimumValue = {
                order = 120,
                name = L["Value"],
                desc = L["AlternateMinimum_OptDesc"],
                type = "range",
                min = 0,
                max = 1000000,
                step = 1,
                bigStep = 1000,
                set = function(info, val)
                    addon.db.profile.bars["EstimateBar"].alternateMinimumValue = val
                    self:UpdateAlternateMinimum()
                end,
                get = function(info)
                    return addon.db.profile.bars["EstimateBar"].alternateMinimumValue
                end,
                disabled = function(info)
                    return addon.db.profile.bars["EstimateBar"].alternateMinimumMode ~= "Value"
                end,
            },
            alternateMinimumPercent = {
                order = 130,
                name = L["Percent"],
                desc = L["AltMinPercent_OptDesc"],
                type = "range",
                isPercent = true,
                min = 0.0,
                max = 1,
                step = 0.01,
                bigStep = 0.05,
                set = function(info, val)
                    addon.db.profile.bars["EstimateBar"].alternateMinimumPercent = val
                    self:UpdateAlternateMinimum()
                end,
                get = function(info)
                    return addon.db.profile.bars["EstimateBar"].alternateMinimumPercent
                end,
                disabled = function(info)
                    return addon.db.profile.bars["EstimateBar"].alternateMinimumMode ~= "Percent"
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

function module:MigrateEstimateBarSettings2()
    local settings = addon.db.profile.bars["EstimateBar"]
    if addon.db.profile.damage_bar_enabled ~= nil then
        settings.enabled = addon.db.profile.damage_bar_enabled
    end
    if addon.db.profile.hide_damage_bar_ooc ~= nil then
        settings.hide_ooc = addon.db.profile.hide_damage_bar_ooc
    end
    if addon.db.profile.lock_damage_bar ~= nil then
        settings.locked = addon.db.profile.lock_damage_bar
    end
    if addon.db.profile.damage_bar_width ~= nil then
        settings.width = addon.db.profile.damage_bar_width
    end
    if addon.db.profile.damage_bar_height ~= nil then
        settings.height = addon.db.profile.damage_bar_height
    end
    if addon.db.profile.estheal_bar_texture ~= nil then
        settings.texture = addon.db.profile.estheal_bar_texture
    end
    if addon.db.profile.estheal_bar_min_textcolor ~= nil then
        settings.textcolor = addon.db.profile.estheal_bar_min_textcolor
    end
    if addon.db.profile.estheal_bar_min_color ~= nil then
        settings.color = addon.db.profile.estheal_bar_min_color
    end
    if addon.db.profile.estheal_bar_min_bgcolor ~= nil then
        settings.bgcolor = addon.db.profile.estheal_bar_min_bgcolor
    end
    if addon.db.profile.estheal_bar_opt_textcolor ~= nil then
        settings.alt_textcolor = addon.db.profile.estheal_bar_opt_textcolor
    end
    if addon.db.profile.estheal_bar_opt_color ~= nil then
        settings.alt_color = addon.db.profile.estheal_bar_opt_color
    end
    if addon.db.profile.estheal_bar_opt_bgcolor ~= nil then
        settings.alt_bgcolor = addon.db.profile.estheal_bar_opt_bgcolor
    end
    if addon.db.profile.estimate_bar_mode ~= nil then
        settings.bar_mode = addon.db.profile.estimate_bar_mode
    end
    if addon.db.profile.estheal_bar_border ~= nil then
        settings.border = addon.db.profile.estheal_bar_border
    end
    if addon.db.profile.estheal_bar_shown ~= nil then
        settings.shown = addon.db.profile.estheal_bar_shown
    end
    if addon.db.profile.estheal_bar_show_text ~= nil then
        settings.show_text = addon.db.profile.estheal_bar_show_text
    end
    if addon.db.profile.est_heal_x ~= nil then
        settings.x = addon.db.profile.est_heal_x
    end
    if addon.db.profile.est_heal_y ~= nil then
        settings.y = addon.db.profile.est_heal_y
    end
    if addon.db.profile.estheal_bar_scale ~= nil then
        settings.scale = addon.db.profile.estheal_bar_scale
    end
    addon.db.profile.damage_bar_enabled = nil
    addon.db.profile.hide_damage_bar_ooc = nil
    addon.db.profile.lock_damage_bar = nil
    addon.db.profile.damage_bar_width = nil
    addon.db.profile.damage_bar_height = nil
    addon.db.profile.estheal_bar_texture = nil
    addon.db.profile.estheal_bar_min_textcolor = nil
    addon.db.profile.estheal_bar_min_color = nil
    addon.db.profile.estheal_bar_min_bgcolor = nil
    addon.db.profile.estheal_bar_opt_textcolor = nil
    addon.db.profile.estheal_bar_opt_color = nil
    addon.db.profile.estheal_bar_opt_bgcolor = nil
    addon.db.profile.estimate_bar_mode = nil
    addon.db.profile.estheal_bar_border = nil
    addon.db.profile.estheal_bar_shown = nil
    addon.db.profile.estheal_bar_show_text = nil
    addon.db.profile.est_heal_x = nil
    addon.db.profile.est_heal_y = nil
    addon.db.profile.estheal_bar_scale = nil
end
