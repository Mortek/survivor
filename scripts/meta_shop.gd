class_name MetaShop
extends Control
## MetaShop – permanent upgrade shop, built dynamically.
## Instantiated from game.gd on the game over screen.
## Uses MetaManager for coin balances and upgrade levels.

signal shop_closed

var _buy_buttons: Array = []   # Array of [Button, Dictionary] — refreshed on coin change

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fill the CanvasLayer so mouse blocking works
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size     = vp
	# Semi-transparent dark overlay — sized directly, not via anchors
	var bg := ColorRect.new()
	bg.position    = Vector2.ZERO
	bg.size        = vp
	bg.color       = Color(0.0, 0.0, 0.0, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_build_panel()

func _build_panel() -> void:
	var vp := get_viewport_rect().size
	var pw  := minf(vp.x - 16.0, 460.0)
	var ph  := vp.y - 40.0

	var panel := PanelContainer.new()
	panel.position = Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5)
	panel.size     = Vector2(pw, ph)
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	# Title
	var title := Label.new()
	title.text                 = "⚡  META UPGRADES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	outer.add_child(title)

	# Coin balance
	var coins_lbl := Label.new()
	coins_lbl.name                 = "CoinsLabel"
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_lbl.add_theme_font_size_override("font_size", 18)
	coins_lbl.modulate             = Color(1.0, 0.9, 0.3)
	_refresh_coins_label(coins_lbl)
	outer.add_child(coins_lbl)

	outer.add_child(HSeparator.new())

	# Scrollable upgrade list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical     = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode  = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	# Hide the scrollbar after it's created
	scroll.get_v_scroll_bar().modulate = Color(1.0, 1.0, 1.0, 0.0)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	var categories: Array = [
		["⚔  OFFENSE",  ["start_damage", "start_atk_speed", "start_crit", "start_multishot", "start_pierce"]],
		["🛡  DEFENSE",  ["start_health", "start_armor", "start_regen", "start_lifesteal", "start_shields", "battle_hardened"]],
		["✦  UTILITY",  ["start_speed", "xp_boost", "coin_bonus", "pickup_boost", "coin_magnet", "bounty_hunter"]],
		["★  SPECIALS", ["lucky_start", "start_dash", "start_lightning", "start_melee", "double_curse"]],
	]
	var upg_map: Dictionary = {}
	for upg in MetaManager.PERMANENT_UPGRADES:
		upg_map[upg["id"]] = upg

	for cat in categories:
		var header := Label.new()
		header.text     = cat[0]
		header.add_theme_font_size_override("font_size", 17)
		header.modulate = Color(1.0, 0.85, 0.3)
		inner.add_child(header)
		inner.add_child(HSeparator.new())
		for id in cat[1]:
			if upg_map.has(id):
				inner.add_child(_build_row(upg_map[id], coins_lbl))
		inner.add_child(Control.new())  # spacer

	outer.add_child(HSeparator.new())

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	outer.add_child(bottom_row)

	# Dev coin button
	var dev_btn := Button.new()
	dev_btn.text = "💰 +1M"
	dev_btn.add_theme_font_size_override("font_size", 14)
	dev_btn.modulate = Color(1.0, 0.85, 0.2)
	dev_btn.pressed.connect(func() -> void:
		MetaManager.add_coins(1_000_000)
		_refresh_coins_label(coins_lbl)
		_refresh_all_buttons()
	)
	bottom_row.add_child(dev_btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "CLOSE  ✕"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(func() -> void:
		shop_closed.emit()
		queue_free()
	)
	bottom_row.add_child(close_btn)

func _build_row(upg: Dictionary, coins_lbl: Label) -> HBoxContainer:
	var row  := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Info label
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 15)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_info_label(info, upg)
	row.add_child(info)

	# Buy button
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 0)
	btn.add_theme_font_size_override("font_size", 15)
	_refresh_buy_btn(btn, upg)
	_buy_buttons.append([btn, upg])
	btn.pressed.connect(func() -> void:
		var lvl  := MetaManager.get_upgrade_level(upg["id"])
		var cost := int(upg["base_cost"]) + (lvl * lvl) * int(upg["cost_scale"])
		if MetaManager.purchase_upgrade(upg["id"], cost):
			_refresh_coins_label(coins_lbl)
			_refresh_info_label(info, upg)
			_refresh_all_buttons()
	)
	row.add_child(btn)
	return row

# ── Helpers ───────────────────────────────────────────────────────────────────
func _fmt(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

func _refresh_all_buttons() -> void:
	for pair in _buy_buttons:
		_refresh_buy_btn(pair[0], pair[1])

func _refresh_coins_label(lbl: Label) -> void:
	lbl.text = "🪙  " + _fmt(MetaManager.total_coins) + " coins available"

func _refresh_info_label(lbl: Label, upg: Dictionary) -> void:
	var lvl   := MetaManager.get_upgrade_level(upg["id"])
	var maxed: bool = lvl >= int(upg["max_level"])
	var state := "  [MAXED]" if maxed else ("  Lvl %d/%d" % [lvl, upg["max_level"]])
	lbl.text = upg["name"] + state + "\n" + upg["desc"]
	lbl.modulate = Color(0.6, 0.6, 0.6) if maxed else Color.WHITE

func _refresh_buy_btn(btn: Button, upg: Dictionary) -> void:
	var lvl   := MetaManager.get_upgrade_level(upg["id"])
	var maxed: bool = lvl >= int(upg["max_level"])
	if maxed:
		btn.text     = "MAXED"
		btn.disabled = true
	else:
		var cost     := int(upg["base_cost"]) + (lvl * lvl) * int(upg["cost_scale"])
		btn.text     = "BUY  🪙%d" % cost
		btn.disabled = MetaManager.total_coins < cost
