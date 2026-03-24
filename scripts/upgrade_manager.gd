extends Control
## Upgrade selection screen shown on level-up (game is paused during display).
## Cards are stacked vertically. Panel is centered via direct pixel coords.

@onready var title_label: Label = $Panel/VBox/TitleLabel

var _card_vbox: VBoxContainer = null   # built fresh each show

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	GameManager.upgrade_available.connect(_show_upgrades)

func _show_upgrades(choices: Array) -> void:
	# Fill the CanvasLayer so the backdrop covers everything
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size     = vp
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Hide the scene panel; we manage layout entirely in code
	$Panel.hide()

	# Remove any previously built overlay and old ColorRects
	var old := get_node_or_null("DynamicPanel")
	if old:
		old.queue_free()
	for ch in get_children():
		if ch is ColorRect:
			ch.queue_free()

	# ── Dark overlay ──────────────────────────────────────────────────────────
	var overlay := ColorRect.new()
	overlay.position    = Vector2.ZERO
	overlay.size        = vp
	overlay.color       = Color(0.0, 0.0, 0.0, 0.65)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ── Centered panel ────────────────────────────────────────────────────────
	var pw := minf(vp.x - 16.0, 460.0)
	var ph := minf(float(choices.size()) * 96.0 + 80.0, vp.y - 40.0)

	var panel := PanelContainer.new()
	panel.name     = "DynamicPanel"
	panel.position = Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5)
	panel.size     = Vector2(pw, ph)
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	# Title
	var title := Label.new()
	var title_str := GameManager._upgrade_title
	if title_str.is_empty():
		title_str = "LEVEL UP!  Lvl %d" % GameManager.current_level
	title.text                 = title_str
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	outer.add_child(title)

	outer.add_child(HSeparator.new())

	# Scrollable card area so content never clips outside the panel
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_card_vbox = VBoxContainer.new()
	_card_vbox.add_theme_constant_override("separation", 6)
	_card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_card_vbox)

	for upgrade in choices:
		_card_vbox.add_child(_build_card(upgrade))

	show()

## Full-width horizontal card: [name + desc | SELECT button]
func _build_card(upgrade: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hbox.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text          = upgrade["name"]
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_lbl)

	var uid: String = upgrade.get("id", "")
	if not uid.is_empty() and not GameManager.is_upgrade_taken(uid):
		var badge := Label.new()
		badge.text     = "✦ NEW"
		badge.add_theme_font_size_override("font_size", 11)
		badge.modulate = Color(0.3, 1.0, 0.5)
		info.add_child(badge)

	var desc_lbl := Label.new()
	desc_lbl.text          = upgrade["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.modulate      = Color(0.8, 0.9, 1.0)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_lbl)

	var btn := Button.new()
	btn.text                = "SELECT"
	btn.custom_minimum_size = Vector2(80, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void: _on_select(upgrade))
	hbox.add_child(btn)

	return card

func _on_select(upgrade: Dictionary) -> void:
	hide()
	# Clean up dynamic nodes before hiding
	var old := get_node_or_null("DynamicPanel")
	if old:
		old.queue_free()
	for ch in get_children():
		if ch is ColorRect:
			ch.queue_free()
	GameManager.apply_upgrade(upgrade)
