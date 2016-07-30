local _G = getfenv(0)
local ADDON_NAME, addon = ...

addon.MIN_UPDATE_TIME = 0.05

addon.DsHealAPModifiers = {
	--["Blood"] = 1.6,
	["Blood"] = 4,
	["Frost"] = 4,
	["Unholy"] = 4,
}

addon.MAX_BLOOD_CHARGES = 12
addon.MAX_BONESHIELD_CHARGES = 10
addon.LUCK_OF_THE_DRAW_MOD = 0.05
addon.DarkSuccorBuffValue = 2.0

addon.HealingDebuffs = {
	-- PvP healing debuffs
	[56112] = 0.20, -- Furious Attacks (Warrior)
	[54680] = 0.25, -- Monstrous Bite (Hunter: Devilsaur)
	[12294] = 0.25, -- Mortal Strike (Warrior)
	[82654] = 0.25, -- Widow Venom (Hunter)
	[13218] = 0.25, -- Wound Poison (Rogue)
	[48301] = 0.25, -- Mind Trauma (Priest)
	[11175] = 0.08, -- Permafrost (Mage)
	[12569] = 0.16, -- Permafrost (Mage)
	[12571] = 0.25, -- Permafrost (Mage)
	[30213] = 0.25, -- Legion Strike (Warlock)
	-- NPCs healing debuffs
	[69674] = 0.50, -- Rotface Mutated Infection
	[73023] = 0.75, -- Rotface Mutated Infection
	[73022] = 0.75, -- Rotface Mutated Infection
	[71224] = 0.50, -- Rotface Mutated Infection
	[71127] = 0.10, -- Stinky/Precious Mortal Wound
	[59455] = 0.75, -- Mortal Strike (NPC)
	[54716] = 0.50, -- Mortal Strike (NPC)
	[19643] = 0.50, -- Mortal Strike (NPC)
	[32736] = 0.50, -- Mortal Strike (NPC)
	[67542] = 0.50, -- Mortal Strike (NPC)
	[13737] = 0.50, -- Mortal Strike (NPC)
	[68784] = 0.50, -- Mortal Strike (NPC)
	[71552] = 0.50, -- Mortal Strike (NPC)
	[68782] = 0.50, -- Mortal Strike (NPC),
	[39171] = 0.06, -- Malevolent Strikes
	[83908] = 0.06, -- Malevolent Strikes
}
