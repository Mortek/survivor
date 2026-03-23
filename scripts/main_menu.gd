extends Node2D
## Main Menu – title screen shown at game launch.
## All UI is built in code, consistent with the rest of the project.

var _ui_layer: CanvasLayer = null

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var vp := Vector2(540.0, 960.0)

	# ── Background ──────────────────────────────────────────────────────────────
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.14, 1.0)
	bg.size  = vp
	bg_layer.add_child(bg)

	# Starfield
	for _i in 50:
		var star := ColorRect.new()
		star.size     = Vector2(randf_range(1.0, 2.5), randf_range(1.0, 2.5))
		star.position = Vector2(randf_range(0.0, vp.x), randf_range(0.0, vp.y))
		star.color    = Color(1.0, 1.0, 1.0, randf_range(0.15, 0.65))
		bg_layer.add_child(star)

	# ── UI Layer ─────────────────────────────────────────────────────────────────
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(root)

	# ── Title ────────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text                 = "SURVIVOR"
	title.add_theme_font_size_override("font_size", 58)
	title.modulate             = Color(0.30, 0.88, 1.00)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchor_and_offset(SIDE_LEFT,   0.0,  20.0)
	title.set_anchor_and_offset(SIDE_TOP,    0.0, 130.0)
	title.set_anchor_and_offset(SIDE_RIGHT,  1.0, -20.0)
	title.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 205.0)
	root.add_child(title)

	var sub := Label.new()
	sub.text                 = "Survive. Level up. Evolve."
	sub.add_theme_font_size_override("font_size", 17)
	sub.modulate             = Color(0.62, 0.62, 0.76)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchor_and_offset(SIDE_LEFT,   0.0,  20.0)
	sub.set_anchor_and_offset(SIDE_TOP,    0.0, 210.0)
	sub.set_anchor_and_offset(SIDE_RIGHT,  1.0, -20.0)
	sub.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 236.0)
	root.add_child(sub)

	# ── Stats strip ──────────────────────────────────────────────────────────────
	var meta := get_node_or_null("/root/MetaManager")
	if meta:
		var coin_lbl := Label.new()
		coin_lbl.text                 = "🪙  " + str(meta.total_coins) + " lifetime coins"
		coin_lbl.add_theme_font_size_override("font_size", 18)
		coin_lbl.modulate             = Color(1.0, 0.88, 0.25)
		coin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		coin_lbl.set_anchor_and_offset(SIDE_LEFT,   0.0,  20.0)
		coin_lbl.set_anchor_and_offset(SIDE_TOP,    0.0, 274.0)
		coin_lbl.set_anchor_and_offset(SIDE_RIGHT,  1.0, -20.0)
		coin_lbl.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 300.0)
		root.add_child(coin_lbl)

		var ach_lbl := Label.new()
		ach_lbl.text                 = "Achievements: %d / 8" % meta.achievements.size()
		ach_lbl.add_theme_font_size_override("font_size", 15)
		ach_lbl.modulate             = Color(0.72, 0.72, 0.72)
		ach_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ach_lbl.set_anchor_and_offset(SIDE_LEFT,   0.0,  20.0)
		ach_lbl.set_anchor_and_offset(SIDE_TOP,    0.0, 305.0)
		ach_lbl.set_anchor_and_offset(SIDE_RIGHT,  1.0, -20.0)
		ach_lbl.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 328.0)
		root.add_child(ach_lbl)

	# ── PLAY button ──────────────────────────────────────────────────────────────
	var play_btn := Button.new()
	play_btn.text                = "▶  PLAY"
	play_btn.add_theme_font_size_override("font_size", 32)
	play_btn.custom_minimum_size = Vector2(240.0, 72.0)
	play_btn.set_anchor_and_offset(SIDE_LEFT,   0.5, -120.0)
	play_btn.set_anchor_and_offset(SIDE_TOP,    0.5, -148.0)
	play_btn.set_anchor_and_offset(SIDE_RIGHT,  0.5,  120.0)
	play_btn.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  -76.0)
	play_btn.pressed.connect(_on_play)
	root.add_child(play_btn)

	# ── META UPGRADES button ──────────────────────────────────────────────────────
	var meta_btn := Button.new()
	meta_btn.text                = "⚡  META UPGRADES"
	meta_btn.add_theme_font_size_override("font_size", 20)
	meta_btn.custom_minimum_size = Vector2(240.0, 54.0)
	meta_btn.set_anchor_and_offset(SIDE_LEFT,   0.5, -120.0)
	meta_btn.set_anchor_and_offset(SIDE_TOP,    0.5,  -58.0)
	meta_btn.set_anchor_and_offset(SIDE_RIGHT,  0.5,  120.0)
	meta_btn.set_anchor_and_offset(SIDE_BOTTOM, 0.5,   -4.0)
	meta_btn.pressed.connect(_on_meta_shop)
	root.add_child(meta_btn)

	# ── Tip ─────────────────────────────────────────────────────────────────────
	var tip := Label.new()
	tip.text                 = "Tip: Reach evolution conditions to unlock\nCrimson Reaper, Death Orbit, or Thunder God"
	tip.add_theme_font_size_override("font_size", 13)
	tip.modulate             = Color(0.55, 0.55, 0.65)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	tip.set_anchor_and_offset(SIDE_LEFT,   0.0,  20.0)
	tip.set_anchor_and_offset(SIDE_TOP,    0.5,  20.0)
	tip.set_anchor_and_offset(SIDE_RIGHT,  1.0, -20.0)
	tip.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  80.0)
	root.add_child(tip)

	# ── Version ──────────────────────────────────────────────────────────────────
	var ver := Label.new()
	ver.text                 = "v0.1"
	ver.add_theme_font_size_override("font_size", 13)
	ver.modulate             = Color(0.42, 0.42, 0.42)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.set_anchor_and_offset(SIDE_LEFT,   1.0, -55.0)
	ver.set_anchor_and_offset(SIDE_TOP,    1.0, -28.0)
	ver.set_anchor_and_offset(SIDE_RIGHT,  1.0,  -6.0)
	ver.set_anchor_and_offset(SIDE_BOTTOM, 1.0,  -6.0)
	root.add_child(ver)

# ── Actions ─────────────────────────────────────────────────────────────────────
func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_meta_shop() -> void:
	var shop := MetaShop.new()
	_ui_layer.add_child(shop)
	shop.shop_closed.connect(shop.queue_free)
