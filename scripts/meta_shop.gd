class_name MetaShop
extends Control
## MetaShop – permanent upgrade shop, built dynamically.
## Instantiated from game.gd on the game over screen.
## Uses MetaManager for coin balances and upgrade levels.

signal shop_closed

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
	var ph  := minf(vp.y - 20.0, 560.0)

	var panel := PanelContainer.new()
	# Direct pixel center — works regardless of parent layout state
	panel.position = Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5)
	panel.size     = Vector2(pw, ph)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text                     = "⚡  META UPGRADES"
	title.horizontal_alignment     = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# Coin balance
	var coins_lbl := Label.new()
	coins_lbl.name                  = "CoinsLabel"
	coins_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	coins_lbl.add_theme_font_size_override("font_size", 16)
	coins_lbl.modulate              = Color(1.0, 0.9, 0.3)
	_refresh_coins_label(coins_lbl)
	vbox.add_child(coins_lbl)

	vbox.add_child(HSeparator.new())

	# Upgrade rows
	for upg in MetaManager.PERMANENT_UPGRADES:
		vbox.add_child(_build_row(upg, coins_lbl))

	vbox.add_child(HSeparator.new())

	# Close button
	var close_btn := Button.new()
	close_btn.text = "CLOSE  ✕"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(func() -> void:
		shop_closed.emit()
		queue_free()
	)
	vbox.add_child(close_btn)

func _build_row(upg: Dictionary, coins_lbl: Label) -> HBoxContainer:
	var row  := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Info label
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 13)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_info_label(info, upg)
	row.add_child(info)

	# Buy button
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 0)
	btn.add_theme_font_size_override("font_size", 14)
	_refresh_buy_btn(btn, upg)
	btn.pressed.connect(func() -> void:
		var lvl  := MetaManager.get_upgrade_level(upg["id"])
		var cost := int(upg["base_cost"]) + lvl * int(upg["cost_scale"])
		if MetaManager.purchase_upgrade(upg["id"], cost):
			_refresh_coins_label(coins_lbl)
			_refresh_info_label(info, upg)
			_refresh_buy_btn(btn, upg)
	)
	row.add_child(btn)
	return row

# ── Helpers ───────────────────────────────────────────────────────────────────
func _refresh_coins_label(lbl: Label) -> void:
	lbl.text = "🪙  " + str(MetaManager.total_coins) + " coins available"

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
		var cost     := int(upg["base_cost"]) + lvl * int(upg["cost_scale"])
		btn.text     = "BUY  🪙%d" % cost
		btn.disabled = MetaManager.total_coins < cost
