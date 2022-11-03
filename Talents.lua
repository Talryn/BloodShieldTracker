local _G = getfenv(0)
local ADDON_NAME, addon = ...

addon.Talents = {
    ["Gloom Ward"] = 391571,
    ["Tightening Grasp"] = 206970,
    ["Coagulopathy"] = 391477,
    ["Dancing Rune Weapon"] = 49028,
    ["Might of Thassarian"] = 374111,
    ["Control Undead"] = 111673,
    ["Improved Bone Shield"] = 374715,
    ["Everlasting Bond"] = 377668,
    ["Suppression"] = 374049,
    ["Insatiable Blade"] = 377637,
    ["Mark of Blood"] = 206940,
    ["Merciless Strikes"] = 373923,
    ["Improved Heart Strike"] = 374717,
    ["Blood Feast"] = 391386,
    ["Empower Rune Weapon"] = 47568,
    ["Bonestorm"] = 194844,
    ["Asphyxiate"] = 221562,
    ["Shattering Bone"] = 377640,
    ["Death Pact"] = 48743,
    ["Acclimation"] = 373926,
    ["Coldthirst"] = 378848,
    ["Foul Bulwark"] = 206974,
    ["Veteran of the Third War"] = 48263,
    ["Improved Death Strike"] = 374277,
    ["Icy Talons"] = 194878,
    ["Enfeeble"] = 392566,
    ["Sacrificial Pact"] = 327574,
    ["Proliferating Chill"] = 373930,
    ["Clenching Grasp"] = 389679,
    ["Blood Draw"] = 374598,
    ["Blinding Sleet"] = 207167,
    ["Death's Reach"] = 276079,
    ["Grip of the Dead"] = 273952,
    ["Runic Attenuation"] = 207104,
    ["Red Thirst"] = 205723,
    ["Voracious"] = 273953,
    ["Unholy Endurance"] = 389682,
    ["Heart Strike"] = 206930,
    ["Abomination Limb"] = 383269,
    ["Blood Scent"] = 374030,
    ["Bloodshot"] = 391398,
    ["Heartbreaker"] = 221536,
    ["Icebound Fortitude"] = 48792,
    ["Bloodworms"] = 195679,
    ["Vampiric Blood"] = 55233,
    ["Iron Heart"] = 391395,
    ["Perseverance of the Ebon Blade"] = 374747,
    ["Assimilation"] = 374383,
    ["Wraith Walk"] = 212552,
    ["Cleaving Strikes"] = 316916,
    ["Blood Boil"] = 50842,
    ["Marrowrend"] = 195182,
    ["Umbilicus Eternus"] = 391517,
    ["Reinforced Bones"] = 374737,
    ["Heartrend"] = 377655,
    ["Relish in Blood"] = 317610,
    ["Death's Caress"] = 195292,
    ["Rapid Decomposition"] = 194662,
    ["Anti-Magic Barrier"] = 205727,
    ["Hemostasis"] = 273946,
    ["Ossuary"] = 219786,
    ["Sanguine Ground"] = 391458,
    ["Blooddrinker"] = 206931,
    ["Blood Tap"] = 221699,
    ["Improved Vampiric Blood"] = 317133,
    ["Tombstone"] = 219809,
    ["Rune Tap"] = 194679,
    ["Unholy Bond"] = 374261,
    ["Gorefiend's Grasp"] = 108199,
    ["Anti-Magic Zone"] = 51052,
    ["Mind Freeze"] = 47528,
    ["Brittle"] = 374504,
    ["Will of the Necropolis"] = 206967,
    ["Permafrost"] = 207200,
    ["March of Darkness"] = 391546,
    ["Chains of Ice"] = 45524,
    ["Purgatory"] = 114556,
    ["Leeching Strike"] = 377629,
    ["Consumption"] = 274156,
    ["Rune Mastery"] = 374574,
    ["Crimson Scourge"] = 81136,
    ["Insidious Chill"] = 391566,
    ["Soul Reaper"] = 343294,
    ["Unholy Ground"] = 374265,
    ["Death's Echo"] = 356367,
    ["Raise Dead"] = 46585,
    ["Death Strike"] = 49998,
    ["Anti-Magic Shell"] = 48707,
}

local function HasTalent(talentId)
	local configId = C_ClassTalents.GetActiveConfigID()
	if not configId then return false, -1 end
	local configInfo = C_Traits.GetConfigInfo(configId)
	if not configInfo then return false, -1 end
	for _, treeId in ipairs(configInfo.treeIDs) do
		local nodes = C_Traits.GetTreeNodes(treeId)
		for i, nodeId in ipairs(nodes) do
			nodeInfo = C_Traits.GetNodeInfo(configId, nodeId)
            if nodeInfo.ranksPurchased and nodeInfo.ranksPurchased > 0 then
    			local activeEntry = nodeInfo.activeEntry
	    		for _, entryId in ipairs(nodeInfo.entryIDs) do
		    	   local entryInfo = C_Traits.GetEntryInfo(configId, entryId)
			       if entryInfo and entryInfo.definitionID then
				      local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                        if definitionInfo.spellID then
                            if definitionInfo.spellID == talentId then
                                local activeEntryId = activeEntry.entryID
                                if activeEntryId == entryId then
                                    return true, nodeInfo.ranksPurchased, nodeInfo.maxRanks
                                end
                            end
                        end
                    end
                end
            end
		end
	end
	return false
end

function addon.HasActiveTalent(talent)
	local talentId = addon.Talents[talent]
	if not talentId then return false end
    local enabled, rank, maxRanks = HasTalent(talentId)
    if addon.db.profile.debug then
        local fmt = "%s talent: %s [%s,%s]"
        addon:Print(fmt:format(talent, _G.tostring(enabled), _G.tostring(rank), _G.tostring(maxRanks)))
    end
    return enabled, rank, maxRanks
end
