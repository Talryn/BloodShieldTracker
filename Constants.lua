local _G = getfenv(0)
local ADDON_NAME, addon = ...

addon.DsHealAPModifiers = {
	--["Blood"] = 1.6,
	["Blood"] = 4,
	["Frost"] = 4,
	["Unholy"] = 4,
}

addon.BS_DURATION = 10  -- The duration of Blood Shield
addon.MAX_BLOOD_CHARGES = 12
addon.LUCK_OF_THE_DRAW_MOD = 0.05
addon.DarkSuccorBuffValue = 2.0

addon.BaselineDPSScaling = {
	[90] = 847.125,
	[91] = 1161.0,
	[92] = 1425.06,
	[93] = 1796.76,
	[94] = 2179.35,
	[95] = 2646,
	[96] = 3114.45,
	[97] = 3238.65,
	[98] = 3364.2,
	[99] = 3489.75,
	[100] = 3615.3,
}
