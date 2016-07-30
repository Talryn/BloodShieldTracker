local _G = getfenv(0)
local ADDON_NAME, addon = ...

addon.TalentsBySpec = {
    ["Blood"] = {
        ["Bloodworms"] = 19165,
        ["Heartbreaker"] = 19166,
        ["Exsanguinate"] = 19217,
        ["Rapid Decomposition"] = 19218,
        ["Soulgorge"] = 19219,
        ["Spectral Deflection"] = 19220,
        ["Ossuary"] = 19221,
        ["Blood Tap"] = 22134,
        ["Anti-Magic Barrier"] = 22135,
        ["Mark of Blood"] = 22013,
        ["Red Thirst"] = 22014,
        ["Tombstone"] = 22015,
        ["Tightening Grasp"] = 19227,
        ["Tremble Before Me"] = 19226,
        ["March of the Damned"] = 19228,
        ["Will of the Necropolis"] = 19230,
        ["Rune Tap"] = 19231,
        ["Foul Bulwark"] = 19232,
        ["Bonestorm"] = 21207,
        ["Blood Mirror"] = 21208,
        ["Purgatory"] = 21209,
    },
    ["Frost"] = {
        ["Shattering Strikes"] = 22016,
        ["Icy Talons"] = 22017,
        ["Murderous Efficiency"] = 22018,
        ["Freezing Fog"] = 22019,
        ["Frozen Pulse"] = 22020,
        ["Horn of Winter"] = 22021,
        ["Icecap"] = 22515,
        ["Hungering Rune Weapon"] = 22517,
        ["Avalanche"] = 22519,
        ["Abomination's Might"] = 22521,
        ["Blinding Sleet"] = 22523,
        ["Winter is Coming"] = 22525,
        ["Volatile Shielding"] = 22527,
        ["Permafrost"] = 22529,
        ["White Walker"] = 22031,
        ["Frostscythe"] = 22531,
        ["Runic Attenuation"] = 22533,
        ["Gathering Storm"] = 22535,
        ["Obliteration"] = 22023,
        ["Breath of Sindragosa"] = 22109,
        ["Glacial Advance"] = 22537,
    },
    ["Unholy"] = {
        ["All Will Serve"] = 22024,
        ["Bursting Sores"] = 22025,
        ["Ebon Fever"] = 22026,
        ["Epidemic"] = 22027,
        ["Pestilent Pustules"] = 22028,
        ["Blighted Rune Weapon"] = 22029,
        ["Unholy Frenzy"] = 22516,
        ["Castigator"] = 22518,
        ["Clawing Shadows"] = 22520,
        ["Sludge Belcher"] = 22522,
        ["Asphyxiate"] = 22524,
        ["Debilitating Infestation"] = 22526,
        ["Spell Eater"] = 22528,
        ["Corpse Shield"] = 22530,
        ["Lingering Apparition"] = 22022,
        ["Shadow Infusion"] = 22532,
        ["Necrosis"] = 22534,
        ["Infected Claws"] = 22536,
        ["Dark Arbiter"] = 22030,
        ["Defile"] = 22110,
        ["Soul Reaper"] = 22538,
    },
}
addon.Talents = {}

function addon.HasActiveTalent(talent)
	local activeGroup = _G.GetActiveSpecGroup()
	local talents = addon.TalentsBySpec[addon.currentSpec or ""] or {}
	local talentId = talents[talent]
	if not talentId or not activeGroup then return false end
	local id, name, iconTexture, selected, available, _, _, _, _, active = 
		_G.GetTalentInfoByID(talentId, activeGroup)
	return name and active
end
