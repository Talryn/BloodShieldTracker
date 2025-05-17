local ADDON_NAME, addon = ...

local LookupOrKeyMT = { __index = function(t, k) return k end }

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
    ["Sanguine Ground"] = 391459, -- Talent
    ["Hemostasis"] = 273947,      -- Blood talent from BfA, passive buff
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
function addon.LoadSpellNames()
    for k, v in pairs(SpellIds) do
        if _G.rawget(SpellNames, k) == nil then
            if C_Spell.GetSpellInfo then
                local info = C_Spell.GetSpellInfo(v)
                if info then
                    SpellNames[k] = info.name
                end
            else
                local name = _G.GetSpellInfo(v)
                SpellNames[k] = name
            end
        end
    end
end

addon.LoadSpellNames()
addon.SpellIds = SpellIds
addon.SpellNames = SpellNames

local ItemIds = {
    ["Indomitable Pride"] = 77211,
}
local ItemNames = {}
function addon.LoadItemNames()
    for k, v in pairs(ItemIds) do
        local name = ItemNames[k]
        if not name then
            ItemNames[k] = (_G.GetItemInfo(ItemIds[k]))
        end
    end
end

addon.LoadItemNames()
addon.ItemNames = ItemNames

local GlyphIds = {
    ["Vampiric Blood"] = 58676,
}
addon.GlyphIds = GlyphIds
