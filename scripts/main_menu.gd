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

	# ── Tip ─────────────────────────────────────────────────────────────────────
	var tip := Label.new()
	tip.text                 = "Tip: Reach evolution conditions to unlock\nCrimson Reaper, Death Orbit, or Thunder God"
	tip.add_theme_font_size_override("font_size", 13)
	tip.modulate             = Color(0.55, 0.55, 0.65)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	tip.position             = Vector2(20.0, 600.0)
	tip.size                 = Vector2(VP.x - 40.0, 60.0)
	root.add_child(tip)

	# ── Version ──────────────────────────────────────────────────────────────────
	var ver := Label.new()
	ver.text                 = "v0.1"
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
