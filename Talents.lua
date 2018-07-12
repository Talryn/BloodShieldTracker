local _G = getfenv(0)
local ADDON_NAME, addon = ...

addon.TalentsBySpec = {
    ["Blood"] = {
        ["Heartbreaker"] = 19165,
        ["Blooddrinker"] = 19166,
        ["Rune Strike"] = 19217,
        ["Rapid Decomposition"] = 19218,
        ["Hemostasis"] = 19219,
        ["Consumption"] = 19220,
        ["Foul Bulwark"] = 19221,
        ["Ossuary"] = 22134,
        ["Tombstone"] = 22135,
        ["Will of the Necropolis"] = 22013,
        ["Anti-Magic Barrier"] = 22014,
        ["Rune Tap"] = 22015,
        ["Grip of the Dead"] = 19227,
        ["Tightening Grasp"] = 19226,
        ["Wraith Walk"] = 19228,
        ["Voracious"] = 19230,
        ["Bloodworms"] = 19231,
        ["Mark of Blood"] = 19232,
        ["Purgatory"] = 21207,
        ["Red Thirst"] = 21208,
        ["Bonestorm"] = 21209,
    },
    ["Frost"] = {
        ["Runic Attenuation"] = 22016,
        ["Icy Talons"] = 22017,
        ["Shattering Strikes"] = 22018,
        ["Freezing Fog"] = 22019,
        ["Murderous Efficiency"] = 22020,
        ["Horn of Winter"] = 22021,
        ["Abomination's Might"] = 22515,
        ["Winter is Coming"] = 22517,
        ["Blinding Sleet"] = 22519,
        ["Icecap"] = 22521,
        ["Avalanche"] = 22523,
        ["Glacial Advance"] = 22525,
        ["Permafrost"] = 22527,
        ["Inexorable Assault"] = 22530,
        ["Wraith Walk"] = 19228,
        ["Gathering Storm"] = 22531,
        ["Frozen Pulse"] = 22533,
        ["Frostscythe"] = 22535,
        ["Hungering Rune Weapon"] = 22023,
        ["Obliteration"] = 22109,
        ["Breath of Sindragosa"] = 22537,
    },
    ["Unholy"] = {
        ["Infected Claws"] = 22024,
        ["All Will Serve"] = 22025,
        ["Clawing Shadows"] = 22026,
        ["Bursting Sores"] = 22027,
        ["Ebon Fever"] = 22028,
        ["Unholy Blight"] = 22029,
        ["Grip of the Dead"] = 22516,
        ["Death's Reach"] = 22518,
        ["Asphyxiate"] = 22520,
        ["Pestilent Pustules"] = 22522,
        ["Harbinger of Doom"] = 22524,
        ["Soul Reaper"] = 22526,
        ["Spell Eater"] = 22528,
        ["Death Pact"] = 22529,
        ["Wraith Walk"] = 19228,
        ["Pestilence"] = 22532,
        ["Defile"] = 22534,
        ["Epidemic"] = 22536,
        ["Army of the Damned"] = 22030,
        ["Unholy Frenzy"] = 22110,
        ["Summon Gargoyle"] = 22538,
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
