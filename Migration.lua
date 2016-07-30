local _G = getfenv(0)
local ADDON_NAME, addon = ...

local BloodShieldTracker = LibStub("AceAddon-3.0"):GetAddon(addon.addonNameCondensed)

function BloodShieldTracker:MigrateSettings()
	local profile_version = self.db.profile.profile_version

	if profile_version == nil or profile_version < 3 then
		self:MigrateSkinningSettings3()
	end

	if profile_version == nil or profile_version < 2 then
		self:MigrateShieldBarSettings2()
		self:MigrateEstimateBarSettings2()
		self:MigratePWSBarSettings2()
		self:MigrateIllumBarSettings2()
		self:MigrateHealthBarSettings2()
	end

	if profile_version == nil or profile_version < 4 then
		self:MigrateSettings4()
	end

	self.db.profile.profile_version = 4
end

function BloodShieldTracker:MigrateSettings4()
	local pwsbar = self.db.profile.bars["PWSBar"]
	local absbar = self.db.profile.bars["TotalAbsorbsBar"]

	-- Rename
	if pwsbar.included["DivineAegis"] ~= nil then
		pwsbar.included["Divine Aegis"] = pwsbar.included["DivineAegis"]
		pwsbar.included["DivineAegis"] = nil
	end
	if absbar.included["DivineAegis"] ~= nil then
		absbar.included["Divine Aegis"] = absbar.included["DivineAegis"]
		absbar.included["DivineAegis"] = nil
	end
	if absbar.included["IlluminatedHealing"] ~= nil then
		absbar.included["Illuminated Healing"] = absbar.included["IlluminatedHealing"]
		absbar.included["IlluminatedHealing"] = nil
	end
	if absbar.included["IndomitablePride"] ~= nil then
		absbar.included["Indomitable Pride"] = absbar.included["IndomitablePride"]
		absbar.included["IndomitablePride"] = nil
	end

	if pwsbar.includeda ~= nil then
		pwsbar.included["Divine Aegis"] = pwsbar.includeda
		pwsbar.includeda = nil
	end

	if absbar.includebs ~= nil then
		absbar.included["Blood Shield"] = absbar.includebs
		absbar.includebs = nil
	end
end

function BloodShieldTracker:MigrateIllumBarSettings2()
	local settings = self.db.profile.bars["IllumBar"]
	if self.db.profile.illumbar_enabled ~= nil then
		settings.enabled = self.db.profile.illumbar_enabled
	end
	if self.db.profile.illumbar_shown ~= nil then
		settings.shown = self.db.profile.illumbar_shown
	end
	if self.db.profile.lock_illumbar ~= nil then
		settings.locked = self.db.profile.lock_illumbar
	end
	if self.db.profile.lock_illum ~= nil then
		settings.locked = self.db.profile.lock_illum
	end
	if self.db.profile.illumbar_texture ~= nil then
		settings.texture = self.db.profile.illumbar_texture
	end
	if self.db.profile.illumbar_border ~= nil then
		settings.border = self.db.profile.illumbar_border
	end
	if self.db.profile.illumbar_color ~= nil then
		settings.color = self.db.profile.illumbar_color
	end
	if self.db.profile.illumbar_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.illumbar_bgcolor
	end
	if self.db.profile.illumbar_textcolor ~= nil then
		settings.textcolor = self.db.profile.illumbar_textcolor
	end
	if self.db.profile.illumbar_x ~= nil then
		settings.x = self.db.profile.illumbar_x
	end
	if self.db.profile.illumbar_y ~= nil then
		settings.y = self.db.profile.illumbar_y
	end
	if self.db.profile.illumbar_width ~= nil then
		settings.width = self.db.profile.illumbar_width
	end
	if self.db.profile.illumbar_height ~= nil then
		settings.height = self.db.profile.illumbar_height
	end
	if self.db.profile.illumbar_scale ~= nil then
		settings.scale = self.db.profile.illumbar_scale
	end

	self.db.profile.illumbar_enabled = nil
	self.db.profile.illumbar_shown = nil
	self.db.profile.lock_illum = nil
	self.db.profile.lock_illumbar = nil
	self.db.profile.illumbar_texture = nil
	self.db.profile.illumbar_border = nil
	self.db.profile.illumbar_color = nil
	self.db.profile.illumbar_bgcolor = nil
	self.db.profile.illumbar_textcolor = nil
	self.db.profile.illumbar_x = nil
	self.db.profile.illumbar_y = nil
	self.db.profile.illumbar_width = nil
	self.db.profile.illumbar_height = nil
	self.db.profile.illumbar_scale = nil
end

function BloodShieldTracker:MigratePWSBarSettings2()
	local settings = self.db.profile.bars["PWSBar"]
	if self.db.profile.pwsbar_enabled ~= nil then
		settings.enabled = self.db.profile.pwsbar_enabled
	end
	if self.db.profile.pwsbar_shown ~= nil then
		settings.shown = self.db.profile.pwsbar_shown
	end
	if self.db.profile.lock_pwsbar ~= nil then
		settings.locked = self.db.profile.lock_pwsbar
	end
	if self.db.profile.pwsbar_texture ~= nil then
		settings.texture = self.db.profile.pwsbar_texture
	end
	if self.db.profile.pwsbar_border ~= nil then
		settings.border = self.db.profile.pwsbar_border
	end
	if self.db.profile.pwsbar_color ~= nil then
		settings.color = self.db.profile.pwsbar_color
	end
	if self.db.profile.pwsbar_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.pwsbar_bgcolor
	end
	if self.db.profile.pwsbar_textcolor ~= nil then
		settings.textcolor = self.db.profile.pwsbar_textcolor
	end
	if self.db.profile.pwsbar_x ~= nil then
		settings.x = self.db.profile.pwsbar_x
	end
	if self.db.profile.pwsbar_y ~= nil then
		settings.y = self.db.profile.pwsbar_y
	end
	if self.db.profile.pwsbar_width ~= nil then
		settings.width = self.db.profile.pwsbar_width
	end
	if self.db.profile.pwsbar_height ~= nil then
		settings.height = self.db.profile.pwsbar_height
	end
	if self.db.profile.pwsbar_scale ~= nil then
		settings.scale = self.db.profile.pwsbar_scale
	end
	if self.db.profile.pwsbar_includeda ~= nil then
		settings.included["DivineAegis"] = self.db.profile.pwsbar_includeda
	end

	self.db.profile.pwsbar_enabled = nil
	self.db.profile.pwsbar_shown = nil
	self.db.profile.lock_pwsbar = nil
	self.db.profile.pwsbar_texture = nil
	self.db.profile.pwsbar_border = nil
	self.db.profile.pwsbar_color = nil
	self.db.profile.pwsbar_bgcolor = nil
	self.db.profile.pwsbar_textcolor = nil
	self.db.profile.pwsbar_x = nil
	self.db.profile.pwsbar_y = nil
	self.db.profile.pwsbar_width = nil
	self.db.profile.pwsbar_height = nil
	self.db.profile.pwsbar_scale = nil
	self.db.profile.pwsbar_includeda = nil
end

function BloodShieldTracker:MigrateHealthBarSettings2()
	local settings = self.db.profile.bars["HealthBar"]
	if self.db.profile.healthbar_enabled ~= nil then
		settings.enabled = self.db.profile.healthbar_enabled
	end
	if self.db.profile.healthbar_shown ~= nil then
		settings.shown = self.db.profile.healthbar_shown
	end
	if self.db.profile.lock_healthbar ~= nil then
		settings.locked = self.db.profile.lock_healthbar
	end
	if self.db.profile.healthbar_texture ~= nil then
		settings.texture = self.db.profile.healthbar_texture
	end
	if self.db.profile.healthbar_border ~= nil then
		settings.border = self.db.profile.healthbar_border
	end
	if self.db.profile.healthbar_color ~= nil then
		settings.color = self.db.profile.healthbar_color
	end
	if self.db.profile.healthbar_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.healthbar_bgcolor
	end
	if self.db.profile.healthbar_textcolor ~= nil then
		settings.textcolor = self.db.profile.healthbar_textcolor
	end
	if self.db.profile.healthbar_x ~= nil then
		settings.x = self.db.profile.healthbar_x
	end
	if self.db.profile.healthbar_y ~= nil then
		settings.y = self.db.profile.healthbar_y
	end
	if self.db.profile.healthbar_width ~= nil then
		settings.width = self.db.profile.healthbar_width
	end
	if self.db.profile.healthbar_height ~= nil then
		settings.height = self.db.profile.healthbar_height
	end
	if self.db.profile.healthbar_scale ~= nil then
		settings.scale = self.db.profile.healthbar_scale
	end
	if self.db.profile.healthbar_hide_ooc ~= nil then
		settings.hide_ooc = self.db.profile.healthbar_hide_ooc
	end
	if self.db.profile.healthbar_low_color ~= nil then
		settings.alt_color = self.db.profile.healthbar_low_color
	end
	if self.db.profile.healthbar_low_textcolor ~= nil then
		settings.alt_textcolor = self.db.profile.healthbar_low_textcolor
	end
	if self.db.profile.healthbar_low_bgcolor ~= nil then
		settings.alt_bgcolor = self.db.profile.healthbar_low_bgcolor
	end
	if self.db.profile.healthbar_low_percent ~= nil then
		settings.low_percent = self.db.profile.healthbar_low_percent
	end
	if self.db.profile.healthbar_text_format ~= nil then
		settings.text_format = self.db.profile.healthbar_text_format
	end

	self.db.profile.healthbar_enabled = nil
	self.db.profile.healthbar_shown = nil
	self.db.profile.lock_healthbar = nil
	self.db.profile.healthbar_texture = nil
	self.db.profile.healthbar_border = nil
	self.db.profile.healthbar_color = nil
	self.db.profile.healthbar_bgcolor = nil
	self.db.profile.healthbar_textcolor = nil
	self.db.profile.healthbar_x = nil
	self.db.profile.healthbar_y = nil
	self.db.profile.healthbar_width = nil
	self.db.profile.healthbar_height = nil
	self.db.profile.healthbar_scale = nil
	self.db.profile.healthbar_hide_ooc = nil
	self.db.profile.healthbar_low_color  = nil
	self.db.profile.healthbar_low_textcolor  = nil
	self.db.profile.healthbar_low_bgcolor  = nil
	self.db.profile.healthbar_low_percent = nil
	self.db.profile.healthbar_text_format = nil
end

function BloodShieldTracker:MigrateEstimateBarSettings2()
	local settings = self.db.profile.bars["EstimateBar"]
	if self.db.profile.damage_bar_enabled ~= nil then
		settings.enabled = self.db.profile.damage_bar_enabled
	end
	if self.db.profile.hide_damage_bar_ooc ~= nil then
		settings.hide_ooc = self.db.profile.hide_damage_bar_ooc
	end
	if self.db.profile.lock_damage_bar ~= nil then
		settings.locked = self.db.profile.lock_damage_bar
	end
	if self.db.profile.damage_bar_width ~= nil then
		settings.width = self.db.profile.damage_bar_width
	end
	if self.db.profile.damage_bar_height ~= nil then
		settings.height = self.db.profile.damage_bar_height
	end
	if self.db.profile.estheal_bar_texture ~= nil then
		settings.texture = self.db.profile.estheal_bar_texture
	end
	if self.db.profile.estheal_bar_min_textcolor ~= nil then
		settings.textcolor = self.db.profile.estheal_bar_min_textcolor
	end
	if self.db.profile.estheal_bar_min_color ~= nil then
		settings.color = self.db.profile.estheal_bar_min_color
	end
	if self.db.profile.estheal_bar_min_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.estheal_bar_min_bgcolor
	end
	if self.db.profile.estheal_bar_opt_textcolor ~= nil then
		settings.alt_textcolor = self.db.profile.estheal_bar_opt_textcolor
	end
	if self.db.profile.estheal_bar_opt_color ~= nil then
		settings.alt_color = self.db.profile.estheal_bar_opt_color
	end
	if self.db.profile.estheal_bar_opt_bgcolor ~= nil then
		settings.alt_bgcolor = self.db.profile.estheal_bar_opt_bgcolor
	end
	if self.db.profile.estimate_bar_mode ~= nil then
		settings.bar_mode = self.db.profile.estimate_bar_mode
	end
	if self.db.profile.estheal_bar_border ~= nil then
		settings.border = self.db.profile.estheal_bar_border
	end
	if self.db.profile.estheal_bar_shown ~= nil then
		settings.shown = self.db.profile.estheal_bar_shown
	end
	if self.db.profile.estheal_bar_show_text ~= nil then
		settings.show_text = self.db.profile.estheal_bar_show_text
	end
	if self.db.profile.est_heal_x ~= nil then
		settings.x = self.db.profile.est_heal_x
	end
	if self.db.profile.est_heal_y ~= nil then
		settings.y = self.db.profile.est_heal_y
	end
	if self.db.profile.estheal_bar_scale ~= nil then
		settings.scale = self.db.profile.estheal_bar_scale
	end

    self.db.profile.damage_bar_enabled = nil
    self.db.profile.hide_damage_bar_ooc = nil
	self.db.profile.lock_damage_bar = nil
	self.db.profile.damage_bar_width = nil
	self.db.profile.damage_bar_height = nil
	self.db.profile.estheal_bar_texture = nil
	self.db.profile.estheal_bar_min_textcolor = nil
	self.db.profile.estheal_bar_min_color = nil
	self.db.profile.estheal_bar_min_bgcolor = nil
	self.db.profile.estheal_bar_opt_textcolor = nil
	self.db.profile.estheal_bar_opt_color = nil
	self.db.profile.estheal_bar_opt_bgcolor = nil
	self.db.profile.estimate_bar_mode = nil
	self.db.profile.estheal_bar_border = nil
	self.db.profile.estheal_bar_shown = nil
	self.db.profile.estheal_bar_show_text = nil
	self.db.profile.est_heal_x = nil
	self.db.profile.est_heal_y = nil
	self.db.profile.estheal_bar_scale = nil
end

function BloodShieldTracker:MigrateShieldBarSettings2()
	local settings = self.db.profile.bars["ShieldBar"]
	if self.db.profile.status_bar_enabled ~= nil then
		settings.enabled = self.db.profile.status_bar_enabled
	end
	if self.db.profile.lock_status_bar ~= nil then
		settings.locked = self.db.profile.lock_status_bar
	end
	if self.db.profile.status_bar_width ~= nil then
		settings.width = self.db.profile.status_bar_width
	end
	if self.db.profile.status_bar_height ~= nil then
		settings.height = self.db.profile.status_bar_height
	end
	if self.db.profile.shield_bar_progress ~= nil then
		settings.progress = self.db.profile.shield_bar_progress
	end
	if self.db.profile.shield_bar_show_time ~= nil then
		settings.show_time = self.db.profile.shield_bar_show_time
	end
	if self.db.profile.shield_bar_time_pos ~= nil then
		settings.time_pos = self.db.profile.shield_bar_time_pos
	end
	if self.db.profile.shield_sound_enabled ~= nil then
		settings.sound_enabled = self.db.profile.shield_sound_enabled
	end
	if self.db.profile.shield_applied_sound ~= nil then
		settings.sound_applied = self.db.profile.shield_applied_sound
	end
	if self.db.profile.shield_removed_sound ~= nil then
		settings.sound_removed = self.db.profile.shield_removed_sound
	end
	if self.db.profile.shield_bar_text_format ~= nil then
		settings.text_format = self.db.profile.shield_bar_text_format
	end
	if self.db.profile.status_bar_color ~= nil then
		settings.color = self.db.profile.status_bar_color
	end
	if self.db.profile.status_bar_textcolor ~= nil then
		settings.textcolor = self.db.profile.status_bar_textcolor
	end
	if self.db.profile.status_bar_bgcolor ~= nil then
		settings.bgcolor = self.db.profile.status_bar_bgcolor
	end
	if self.db.profile.status_bar_texture ~= nil then
		settings.texture = self.db.profile.status_bar_texture
	end
	if self.db.profile.status_bar_border ~= nil then
		settings.border = self.db.profile.status_bar_border
	end
	if self.db.profile.status_bar_shown ~= nil then
		settings.shown = self.db.profile.status_bar_shown
	end
	if self.db.profile.shield_bar_x ~= nil then
		settings.x = self.db.profile.shield_bar_x
	end
	if self.db.profile.shield_bar_y ~= nil then
		settings.y = self.db.profile.shield_bar_y
	end
	if self.db.profile.status_bar_scale ~= nil then
		settings.scale = self.db.profile.status_bar_scale
	end

	self.db.profile.status_bar_enabled = nil
	self.db.profile.lock_status_bar = nil
	self.db.profile.status_bar_width = nil
	self.db.profile.status_bar_height = nil
	self.db.profile.shield_bar_progress = nil
	self.db.profile.shield_bar_show_time = nil
	self.db.profile.shield_bar_time_pos = nil
	self.db.profile.shield_sound_enabled = nil
	self.db.profile.shield_applied_sound = nil
	self.db.profile.shield_removed_sound = nil
	self.db.profile.shield_bar_text_format = nil
	self.db.profile.status_bar_color = nil
	self.db.profile.status_bar_textcolor = nil
	self.db.profile.status_bar_bgcolor = nil
	self.db.profile.status_bar_texture = nil
	self.db.profile.status_bar_border = nil
	self.db.profile.status_bar_shown = nil
	self.db.profile.shield_bar_x = nil
	self.db.profile.shield_bar_y = nil
	self.db.profile.status_bar_scale = nil
end

function BloodShieldTracker:MigrateSkinningSettings3()
	local elvui = self.db.profile.skinning.elvui
	local tukui = self.db.profile.skinning.tukui
	if self.db.profile.elvui_enabled ~= nil then
		elvui.enabled = self.db.profile.elvui_enabled
	end
	if self.db.profile.elvui_borders ~= nil then
		elvui.borders = self.db.profile.elvui_borders
	end
	if self.db.profile.elvui_texture ~= nil then
		elvui.texture = self.db.profile.elvui_texture
	end
	if self.db.profile.elvui_font ~= nil then
		elvui.font = self.db.profile.elvui_font
	end
	if self.db.profile.elvui_font_flags ~= nil then
		elvui.font_flags = self.db.profile.elvui_font_flags
	end
	if self.db.profile.tukui_enabled ~= nil then
		tukui.enabled = self.db.profile.tukui_enabled
	end
	if self.db.profile.tukui_borders ~= nil then
		tukui.borders = self.db.profile.tukui_borders
	end
	if self.db.profile.tukui_texture ~= nil then
		tukui.texture = self.db.profile.tukui_texture
	end
	if self.db.profile.tukui_font ~= nil then
		tukui.font = self.db.profile.tukui_font
	end
	if self.db.profile.tukui_font_flags ~= nil then
		tukui.font_flags = self.db.profile.tukui_font_flags
	end

    self.db.profile.tukui_enabled = nil
    self.db.profile.tukui_borders = nil
    self.db.profile.tukui_texture = nil
    self.db.profile.tukui_font = nil
    self.db.profile.tukui_font_flags = nil
    self.db.profile.elvui_enabled = nil
    self.db.profile.elvui_borders = nil
    self.db.profile.elvui_texture = nil
    self.db.profile.elvui_font = nil
    self.db.profile.elvui_font_flags = nil
end
