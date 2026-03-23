extends Node2D
## Main Menu – title screen shown at game launch.
## All UI is built in code, consistent with the rest of the project.

var _ui_layer: CanvasLayer = null

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	const VP := Vector2(540.0, 960.0)
	const CX := VP.x * 0.5  # 270 — horizontal centre

	# ── Background ──────────────────────────────────────────────────────────────
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)

	var bg := ColorRect.new()
	bg.color    = Color(0.06, 0.06, 0.14, 1.0)
	bg.position = Vector2.ZERO
	bg.size     = VP
	bg_layer.add_child(bg)

	# Starfield
	for _i in 50:
		var star := ColorRect.new()
		star.size     = Vector2(randf_range(1.0, 2.5), randf_range(1.0, 2.5))
		star.position = Vector2(randf_range(0.0, VP.x), randf_range(0.0, VP.y))
		star.color    = Color(1.0, 1.0, 1.0, randf_range(0.15, 0.65))
		bg_layer.add_child(star)

	# ── UI Layer ─────────────────────────────────────────────────────────────────
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)

	# Root control — explicit size so child pixel positions are reliable
	var root := Control.new()
	root.position = Vector2.ZERO
	root.size     = VP
	_ui_layer.add_child(root)

	# ── Title ────────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text                 = "SURVIVOR"
	title.add_theme_font_size_override("font_size", 58)
	title.modulate             = Color(0.30, 0.88, 1.00)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position             = Vector2(20.0, 130.0)
	title.size                 = Vector2(VP.x - 40.0, 75.0)
	root.add_child(title)

	var sub := Label.new()
	sub.text                 = "Survive. Level up. Evolve."
	sub.add_theme_font_size_override("font_size", 17)
	sub.modulate             = Color(0.62, 0.62, 0.76)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position             = Vector2(20.0, 210.0)
	sub.size                 = Vector2(VP.x - 40.0, 26.0)
	root.add_child(sub)

	# ── Stats strip ──────────────────────────────────────────────────────────────
	var meta := get_node_or_null("/root/MetaManager")
	if meta:
		var coin_lbl := Label.new()
		coin_lbl.text                 = "🪙  " + str(meta.total_coins) + " lifetime coins"
		coin_lbl.add_theme_font_size_override("font_size", 18)
		coin_lbl.modulate             = Color(1.0, 0.88, 0.25)
		coin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		coin_lbl.position             = Vector2(20.0, 274.0)
		coin_lbl.size                 = Vector2(VP.x - 40.0, 26.0)
		root.add_child(coin_lbl)

		var ach_lbl := Label.new()
		ach_lbl.text                 = "Achievements: %d / 8" % meta.achievements.size()
		ach_lbl.add_theme_font_size_override("font_size", 15)
		ach_lbl.modulate             = Color(0.72, 0.72, 0.72)
		ach_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ach_lbl.position             = Vector2(20.0, 305.0)
		ach_lbl.size                 = Vector2(VP.x - 40.0, 23.0)
		root.add_child(ach_lbl)

		if meta.best_wave > 0:
			var best_lbl := Label.new()
			best_lbl.text                 = meta.get_best_run_string()
			best_lbl.add_theme_font_size_override("font_size", 13)
			best_lbl.modulate             = Color(0.62, 0.82, 0.62)
			best_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			best_lbl.position             = Vector2(20.0, 330.0)
			best_lbl.size                 = Vector2(VP.x - 40.0, 22.0)
			root.add_child(best_lbl)

	# ── PLAY button ──────────────────────────────────────────────────────────────
	var play_btn := Button.new()
	play_btn.text                = "▶  PLAY"
	play_btn.add_theme_font_size_override("font_size", 32)
	play_btn.position            = Vector2(CX - 120.0, 420.0)
	play_btn.size                = Vector2(240.0, 72.0)
	play_btn.pressed.connect(_on_play)
	root.add_child(play_btn)

	# ── META UPGRADES button ──────────────────────────────────────────────────────
	var meta_btn := Button.new()
	meta_btn.text                = "⚡  META UPGRADES"
	meta_btn.add_theme_font_size_override("font_size", 20)
	meta_btn.position            = Vector2(CX - 120.0, 508.0)
	meta_btn.size                = Vector2(240.0, 54.0)
	meta_btn.pressed.connect(_on_meta_shop)
	root.add_child(meta_btn)

	# ── SETTINGS button ──────────────────────────────────────────────────────────
	var settings_btn := Button.new()
	settings_btn.text                = "⚙  SETTINGS"
	settings_btn.add_theme_font_size_override("font_size", 20)
	settings_btn.position            = Vector2(CX - 120.0, 574.0)
	settings_btn.size                = Vector2(240.0, 54.0)
	settings_btn.pressed.connect(_on_settings)
	root.add_child(settings_btn)

	# ── DAILY CHALLENGE button ─────────────────────────────────────────────────
	var daily_btn := Button.new()
	daily_btn.text                = "📅  DAILY CHALLENGE"
	daily_btn.add_theme_font_size_override("font_size", 18)
	daily_btn.position            = Vector2(CX - 120.0, 640.0)
	daily_btn.size                = Vector2(240.0, 54.0)
	daily_btn.pressed.connect(_on_daily_challenge)
	root.add_child(daily_btn)

	# ── Tip ─────────────────────────────────────────────────────────────────────
	var tip := Label.new()
	tip.text                 = "Tip: Reach evolution conditions to unlock\nCrimson Reaper, Death Orbit, or Thunder God"
	tip.add_theme_font_size_override("font_size", 13)
	tip.modulate             = Color(0.55, 0.55, 0.65)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	tip.position             = Vector2(20.0, 712.0)
	tip.size                 = Vector2(VP.x - 40.0, 60.0)
	root.add_child(tip)

	# ── Version ──────────────────────────────────────────────────────────────────
	var ver := Label.new()
	ver.text                 = "v0.2"
	ver.add_theme_font_size_override("font_size", 13)
	ver.modulate             = Color(0.42, 0.42, 0.42)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.position             = Vector2(VP.x - 55.0, VP.y - 28.0)
	ver.size                 = Vector2(49.0, 22.0)
	root.add_child(ver)

# ── Actions ─────────────────────────────────────────────────────────────────────
func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_meta_shop() -> void:
	var shop := MetaShop.new()
	_ui_layer.add_child(shop)
	shop.shop_closed.connect(shop.queue_free)

func _on_settings() -> void:
	var overlay := _build_settings_overlay()
	_ui_layer.add_child(overlay)

func _build_settings_overlay() -> Control:
	var vp  := Vector2(540.0, 960.0)
	var root := Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.position     = Vector2.ZERO
	root.size         = vp

	var bg := ColorRect.new()
	bg.color        = Color(0, 0, 0, 0.80)
	bg.position     = Vector2.ZERO
	bg.size         = vp
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)

	var pw := 360.0
	var ph := 260.0
	var panel := PanelContainer.new()
	panel.position = Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5)
	panel.size     = Vector2(pw, ph)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text                 = "⚙  SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# Volume row
	var vol_row := HBoxContainer.new()
	var vol_lbl := Label.new()
	vol_lbl.text                  = "Volume"
	vol_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_lbl.add_theme_font_size_override("font_size", 15)
	vol_row.add_child(vol_lbl)
	var vol_slider := HSlider.new()
	vol_slider.min_value           = 0.0
	vol_slider.max_value           = 1.0
	vol_slider.step                = 0.05
	vol_slider.value               = _load_setting("volume", 0.8)
	vol_slider.custom_minimum_size = Vector2(120, 0)
	vol_slider.value_changed.connect(func(v: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(v))
		_save_setting("volume", v)
	)
	vol_row.add_child(vol_slider)
	vbox.add_child(vol_row)

	# Vibration row
	var vib_row := HBoxContainer.new()
	var vib_lbl := Label.new()
	vib_lbl.text                  = "Vibration"
	vib_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vib_lbl.add_theme_font_size_override("font_size", 15)
	vib_row.add_child(vib_lbl)
	var vib_check := CheckButton.new()
	vib_check.button_pressed = _load_setting("vibration", 1.0) > 0.5
	vib_check.toggled.connect(func(on: bool) -> void:
		_save_setting("vibration", 1.0 if on else 0.0)
	)
	vib_row.add_child(vib_check)
	vbox.add_child(vib_row)

	vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "CLOSE  ✕"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(root.queue_free)
	vbox.add_child(close_btn)

	# Apply saved volume
	AudioServer.set_bus_volume_db(0, linear_to_db(_load_setting("volume", 0.8)))

	return root

func _on_daily_challenge() -> void:
	var date := Time.get_date_dict_from_system()
	var seed_val: int = int(date["year"]) * 10000 + int(date["month"]) * 100 + int(date["day"])
	var curse_names: Array[String] = ["Glass Cannon", "Blood Price", "Berserker Pact",
		"Chaos Form", "Iron Burden", "Cursed Knowledge",
		"Giant Form", "Time Warp", "Wraith Pact", "Corruption"]
	var idx: int = seed_val % curse_names.size()
	var curse_name: String = curse_names[idx]
	var popup := _build_challenge_popup(curse_name)
	_ui_layer.add_child(popup)

func _build_challenge_popup(curse_name: String) -> Control:
	var vp   := Vector2(540.0, 960.0)
	var root := Control.new()
	root.position = Vector2.ZERO
	root.size     = vp
	root.process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color        = Color(0, 0, 0, 0.80)
	bg.position     = Vector2.ZERO
	bg.size         = vp
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)

	var pw := 340.0
	var ph := 240.0
	var panel := PanelContainer.new()
	panel.position = Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5)
	panel.size     = Vector2(pw, ph)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text                 = "📅  DAILY CHALLENGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.modulate             = Color(1.0, 0.9, 0.2)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text                 = "Today's curse:\n" + curse_name
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 16)
	desc.modulate             = Color(1.0, 0.5, 0.2)
	desc.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var sub := Label.new()
	sub.text                 = "This curse is automatically applied.\nCan you survive it?"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.modulate             = Color(0.75, 0.75, 0.75)
	sub.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var play_btn := Button.new()
	play_btn.text = "▶  PLAY"
	play_btn.add_theme_font_size_override("font_size", 18)
	play_btn.pressed.connect(func() -> void:
		GameManager.daily_challenge_active = true
		GameManager.daily_challenge_curse  = curse_name
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	)
	btn_row.add_child(play_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(root.queue_free)
	btn_row.add_child(cancel_btn)

	return root

func _save_setting(key: String, value: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("settings", key, value)
	cfg.save("user://settings.cfg")

func _load_setting(key: String, default_val: float) -> float:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return default_val
	return float(cfg.get_value("settings", key, default_val))
