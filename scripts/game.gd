extends Node2D
## Game – root of the main scene, wires all systems together.

# ── Node References ───────────────────────────────────────────────────────────
@onready var player:           CharacterBody2D = $Player
@onready var camera:           Camera2D        = $Player/Camera2D
@onready var enemies_node:     Node2D          = $World/Enemies
@onready var coins_node:       Node2D          = $World/Coins
@onready var projectile_pool:  ObjectPool      = $ProjectilePool
@onready var spawner:          Node            = $Spawner
@onready var ui:               CanvasLayer     = $UI
@onready var joystick:         Control         = $UI/VirtualJoystick
@onready var upgrade_menu:     Control         = $UI/UpgradeMenu
@onready var game_over_screen: Control         = $UI/GameOverScreen
@onready var pause_btn:        Button          = $UI/HUD/PauseButton
@onready var go_time_label:    Label           = $UI/GameOverScreen/Panel/VBox/TimeLabel
@onready var go_level_label:   Label           = $UI/GameOverScreen/Panel/VBox/LevelLabel
@onready var restart_btn:      Button          = $UI/GameOverScreen/Panel/VBox/RestartButton

var fx_node: Node2D = null

const COIN_SCENE := preload("res://scenes/coin.tscn")

# ── Dynamic game-over labels ───────────────────────────────────────────────────
var _go_kills_label: Label = null
var _go_wave_label:  Label = null
var _go_coins_label: Label = null

# ── Level-up / boss screen flash ──────────────────────────────────────────────
var _level_flash: ColorRect = null

# ── Dev speed button ──────────────────────────────────────────────────────────
var _speed_btn:   Button = null
var _speed_index: int    = 0
const _SPEEDS := [1, 2, 3, 4, 5]

# ── Audio ─────────────────────────────────────────────────────────────────────
var _audio: Node = null

# ── Wave announcement banner ──────────────────────────────────────────────────
var _wave_banner: PanelContainer = null
var _wave_banner_label: Label    = null

# ── Kill feed ─────────────────────────────────────────────────────────────────
var _kill_feed: VBoxContainer     = null
const KILL_FEED_MAX := 6
const KILL_FEED_DURATION := 3.5

# ── Combo display ─────────────────────────────────────────────────────────────
var _last_combo_shown: int = 0

# ── Curse dialog ──────────────────────────────────────────────────────────────
var _curse_dialog: Control = null

# ── Achievement banner ────────────────────────────────────────────────────────
var _achievement_queue: Array = []
var _achievement_showing: bool = false

# ── Shield indicator ──────────────────────────────────────────────────────────
var _shield_bar: HBoxContainer = null

# ── Pause overlay ─────────────────────────────────────────────────────────────
var _pause_overlay: Control = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_KILL_FEED_DATA = {
		Enemy.Type.BASIC:    ["☠ Basic",     Color(0.90, 0.40, 0.40)],
		Enemy.Type.FAST:     ["☠ Fast",      Color(1.00, 0.90, 0.30)],
		Enemy.Type.TANK:     ["☠ Tank",      Color(0.70, 0.40, 1.00)],
		Enemy.Type.BOSS:     ["💀 BOSS",     Color(1.00, 0.20, 1.00)],
		Enemy.Type.SPLITTER: ["☠ Splitter",  Color(0.30, 1.00, 0.60)],
		Enemy.Type.EXPLODER: ["💥 Exploder", Color(1.00, 0.55, 0.10)],
	}
	GameManager.reset()

	# Apply permanent meta bonuses to stats before first run
	var meta := get_node_or_null("/root/MetaManager")
	if meta:
		meta.apply_to_stats(GameManager.stats)

	# ── Player setup ──
	player.projectile_pool = projectile_pool
	player.camera          = camera

	# ── Spawner setup ──
	spawner.setup(player, enemies_node)
	spawner.enemy_spawned.connect(_on_enemy_spawned)

	# ── Joystick → Player ──
	joystick.direction_changed.connect(player.set_move_direction)

	# ── HUD ──
	ui.connect_player(player)

	# ── Signals ──
	GameManager.game_over_triggered.connect(_on_game_over)
	GameManager.wave_changed.connect(_on_wave_changed)
	GameManager.boss_wave_started.connect(_on_boss_wave)
	GameManager.combo_updated.connect(_on_combo_updated)
	GameManager.achievement_unlocked.connect(_on_achievement_unlocked)
	GameManager.curse_offered.connect(_on_curse_offered)
	player.shield_broken.connect(_on_shield_broken)

	# ── Pause button: top-right, row 2 (below health bar) ──
	pause_btn.custom_minimum_size = Vector2(48, 26)
	pause_btn.set_anchor_and_offset(SIDE_LEFT,   1.0, -54.0)
	pause_btn.set_anchor_and_offset(SIDE_TOP,    0.0,  26.0)
	pause_btn.set_anchor_and_offset(SIDE_RIGHT,  1.0,  -6.0)
	pause_btn.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  52.0)
	pause_btn.pressed.connect(_toggle_pause)

	# ── Restart ──
	restart_btn.pressed.connect(_restart)

	game_over_screen.hide()

	# ── Build dynamic GO labels ──
	_build_extra_go_labels()

	# ── Build screen flash overlay ──
	_level_flash        = ColorRect.new()
	_level_flash.color  = Color(1.0, 1.0, 0.5, 0.0)
	_level_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_flash.z_index      = 20
	ui.add_child(_level_flash)
	GameManager.upgrade_available.connect(_on_upgrade_available_flash)

	# ── Cache autoloads ──
	_audio = get_node_or_null("/root/AudioManager")

	# ── Dev speed button ──
	_create_speed_button()

	# ── FX container ──
	var maybe_fx := get_node_or_null("World/FX")
	if maybe_fx:
		fx_node = maybe_fx
	else:
		fx_node = Node2D.new()
		fx_node.name = "FX"
		$World.add_child(fx_node)

	# ── Wave banner ──
	_build_wave_banner()

	# ── Kill feed ──
	_build_kill_feed()

	# ── Shield indicator ──
	_build_shield_indicator()

	# ── Pause overlay ──
	_build_pause_overlay()

	# ── Lucky Star: offer free upgrade on first frame ──
	if meta and meta.get_upgrade_level("lucky_start") >= 1:
		call_deferred("_lucky_start_offer")

# ── Lucky Star ────────────────────────────────────────────────────────────────
func _lucky_start_offer() -> void:
	GameManager.offer_free_upgrade()

# ── Dev Speed Button ──────────────────────────────────────────────────────────
func _create_speed_button() -> void:
	_speed_btn = Button.new()
	_speed_btn.text = "1x"
	_speed_btn.add_theme_font_size_override("font_size", 13)
	_speed_btn.pressed.connect(_on_speed_pressed)
	$UI/HUD.add_child(_speed_btn)
	call_deferred("_position_speed_btn")

func _position_speed_btn() -> void:
	var vp := get_viewport_rect().size
	_speed_btn.size     = Vector2(46.0, 26.0)
	_speed_btn.position = Vector2(vp.x - 52.0, vp.y - 44.0)

func _on_speed_pressed() -> void:
	_speed_index      = (_speed_index + 1) % _SPEEDS.size()
	Engine.time_scale = float(_SPEEDS[_speed_index])
	_speed_btn.text   = str(_SPEEDS[_speed_index]) + "x"

# ── Extra Game-Over Labels ────────────────────────────────────────────────────
func _build_extra_go_labels() -> void:
	var vbox      := $UI/GameOverScreen/Panel/VBox
	_go_kills_label = _make_go_label()
	_go_wave_label  = _make_go_label()
	_go_coins_label = _make_go_label()
	vbox.add_child(_go_kills_label)
	vbox.add_child(_go_wave_label)
	vbox.add_child(_go_coins_label)
	var btn_idx := restart_btn.get_index()
	vbox.move_child(_go_kills_label,  btn_idx)
	vbox.move_child(_go_wave_label,   btn_idx + 1)
	vbox.move_child(_go_coins_label,  btn_idx + 2)

func _make_go_label() -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	return lbl

# ── Wave Announcement Banner ──────────────────────────────────────────────────
const _WAVE_BANNER_W := 260.0
const _WAVE_BANNER_H := 44.0

func _build_wave_banner() -> void:
	_wave_banner = PanelContainer.new()
	_wave_banner.custom_minimum_size = Vector2(_WAVE_BANNER_W, _WAVE_BANNER_H)
	_wave_banner.modulate.a   = 0.0
	_wave_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_banner.z_index      = 15
	_wave_banner_label = Label.new()
	_wave_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_banner_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_wave_banner_label.add_theme_font_size_override("font_size", 20)
	_wave_banner.add_child(_wave_banner_label)
	ui.add_child(_wave_banner)
	call_deferred("_position_wave_banner")

func _position_wave_banner() -> void:
	var vp := get_viewport_rect().size
	_wave_banner.position = Vector2(
		(vp.x - _WAVE_BANNER_W) * 0.5,
		vp.y * 0.28 - _WAVE_BANNER_H * 0.5
	)

func _show_wave_banner(text: String, color: Color = Color.WHITE) -> void:
	if not _wave_banner:
		return
	_wave_banner_label.text    = text
	_wave_banner_label.modulate = color
	var tw := _wave_banner.create_tween()
	tw.tween_property(_wave_banner, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(_wave_banner, "modulate:a", 0.0, 0.4)

# ── Kill Feed ─────────────────────────────────────────────────────────────────
func _build_kill_feed() -> void:
	_kill_feed = VBoxContainer.new()
	# Right side, starting below the HUD rows (kills reach y=100)
	_kill_feed.set_anchor_and_offset(SIDE_LEFT,   1.0, -192.0)
	_kill_feed.set_anchor_and_offset(SIDE_TOP,    0.0,  104.0)
	_kill_feed.set_anchor_and_offset(SIDE_RIGHT,  1.0,   -6.0)
	_kill_feed.set_anchor_and_offset(SIDE_BOTTOM, 1.0,  -90.0)
	_kill_feed.add_theme_constant_override("separation", 2)
	_kill_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_kill_feed)

func _add_kill_feed_entry(text: String, color: Color) -> void:
	if not _kill_feed:
		return
	# Remove oldest if full
	if _kill_feed.get_child_count() >= KILL_FEED_MAX:
		_kill_feed.get_child(0).queue_free()
	var lbl := Label.new()
	lbl.text                    = text
	lbl.modulate                = color
	lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	_kill_feed.add_child(lbl)
	# Fade out and remove
	var tw := lbl.create_tween()
	tw.tween_interval(KILL_FEED_DURATION - 0.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free)

# ── Shield Indicator ──────────────────────────────────────────────────────────
func _build_shield_indicator() -> void:
	_shield_bar = HBoxContainer.new()
	# Centered horizontally, just below the left-column labels (y=100)
	_shield_bar.set_anchor_and_offset(SIDE_LEFT,   0.5, -60.0)
	_shield_bar.set_anchor_and_offset(SIDE_TOP,    0.0, 104.0)
	_shield_bar.set_anchor_and_offset(SIDE_RIGHT,  0.5,  60.0)
	_shield_bar.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 122.0)
	_shield_bar.add_theme_constant_override("separation", 4)
	_shield_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_shield_bar)
	# Refresh on stats change
	GameManager.stats_changed.connect(_refresh_shield_bar)

func _refresh_shield_bar() -> void:
	if not _shield_bar:
		return
	for c in _shield_bar.get_children():
		c.queue_free()
	var charges := int(GameManager.stats.get("shield_charges", 0))
	for _i in charges:
		var icon := Label.new()
		icon.text                   = "🛡"
		icon.add_theme_font_size_override("font_size", 16)
		icon.mouse_filter           = Control.MOUSE_FILTER_IGNORE
		_shield_bar.add_child(icon)

# ── Achievement Notification ──────────────────────────────────────────────────
func _on_achievement_unlocked(_id: String, title: String) -> void:
	_achievement_queue.append(title)
	if not _achievement_showing:
		_show_next_achievement()
	if _audio:
		_audio.play_any("achievement")

func _show_next_achievement() -> void:
	if _achievement_queue.is_empty():
		_achievement_showing = false
		return
	_achievement_showing = true
	var title := _achievement_queue.pop_front() as String

	var vp     := get_viewport_rect().size
	var bw     := minf(vp.x - 16.0, 320.0)
	var banner := PanelContainer.new()
	banner.custom_minimum_size = Vector2(bw, 50.0)
	banner.modulate.a    = 0.0
	banner.z_index       = 25
	banner.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	# Centered horizontally, just above the XP bar at the bottom
	banner.position = Vector2((vp.x - bw) * 0.5, vp.y - 90.0)

	var lbl := Label.new()
	lbl.text                   = "🏆  " + title
	lbl.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.modulate               = Color(1.0, 0.9, 0.2)
	banner.add_child(lbl)
	ui.add_child(banner)

	var tw := banner.create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.4)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)
	tw.tween_callback(banner.queue_free)
	tw.tween_callback(_show_next_achievement)

# ── Combo Display ─────────────────────────────────────────────────────────────
func _on_combo_updated(count: int) -> void:
	if count < 3:
		_last_combo_shown = 0
		return
	# Only show at milestones: 3, 5, 10, 15...
	var milestone := count >= 3 and (count == 3 or count == 5 or count % 5 == 0)
	if not milestone:
		return
	_last_combo_shown = count
	_spawn_combo_text(count)
	if _audio and count >= 5:
		_audio.play_any("combo")

func _spawn_combo_text(count: int) -> void:
	var lbl := Label.new()
	var col  := Color(1.0, 0.85, 0.1) if count < 10 else Color(1.0, 0.3, 0.1)
	lbl.text                 = "×%d COMBO!" % count
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28 + mini(count, 20))
	lbl.modulate             = col
	lbl.z_index              = 22
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "offset_top",   -60.0, 0.7)
	tw.tween_property(lbl, "modulate:a",    0.0,  0.7)
	tw.tween_callback(lbl.queue_free).set_delay(0.7)

# ── Enemy Events ──────────────────────────────────────────────────────────────
# Kill feed labels/colors keyed by Enemy.Type int value.
# Must be var (not const) — Color() and enum values aren't compile-time literals.
var _KILL_FEED_DATA: Dictionary

func _on_enemy_spawned(enemy: Node) -> void:
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if not enemy.hit_taken.is_connected(_on_enemy_hit_taken):
		enemy.hit_taken.connect(_on_enemy_hit_taken)
	if enemy.enemy_type == Enemy.Type.SPLITTER:
		if not enemy.split_requested.is_connected(_on_split_requested):
			enemy.split_requested.connect(_on_split_requested)

func _on_enemy_died(world_pos: Vector2, xp: int, color: Color, type: int) -> void:
	call_deferred("_spawn_coin", world_pos, xp)
	call_deferred("_spawn_death_particles", world_pos, color)
	if randf() < 0.04:   # 4% chance
		call_deferred("_spawn_magnet_orb", world_pos)
	GameManager.add_kill()
	player.on_kill()

	if type == Enemy.Type.BOSS:
		_boss_death_hitpause()
		if _audio:
			_audio.play_any("boss_die")
	else:
		if _audio:
			if type == Enemy.Type.EXPLODER:
				_audio.play_any("explode")
			else:
				_audio.play("die")

	var entry: Array = _KILL_FEED_DATA.get(type, ["☠ Enemy", Color.WHITE])
	_add_kill_feed_entry(entry[0], entry[1])

func _on_enemy_hit_taken(world_pos: Vector2, amount: float) -> void:
	call_deferred("_spawn_damage_number", world_pos, amount)
	if _audio:
		_audio.play("hit")

func _on_split_requested(world_pos: Vector2) -> void:
	# Spawn 2 small BASIC enemies at the split position
	var wave_mult := GameManager.get_wave_multiplier() * 0.4
	call_deferred("_spawn_split_children", world_pos, wave_mult)

func _spawn_split_children(world_pos: Vector2, wave_mult: float) -> void:
	for off in [Vector2(-28, -10), Vector2(28, 10)]:
		spawner.spawn_at(Enemy.Type.BASIC, world_pos + off, wave_mult, false)

# ── Boss Death Hitpause ───────────────────────────────────────────────────────
func _boss_death_hitpause() -> void:
	Engine.time_scale = 0.04
	_do_flash(Color(1.0, 1.0, 1.0, 0.6), 0.5)
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(0.8)
	await get_tree().create_timer(0.1, true, false, true).timeout   # real-time timer
	Engine.time_scale = float(_SPEEDS[_speed_index])

# ── Shield Broken ─────────────────────────────────────────────────────────────
func _on_shield_broken() -> void:
	_do_flash(Color(0.3, 0.8, 1.0, 0.35), 0.3)
	_refresh_shield_bar()
	if _audio:
		_audio.play_any("shield_break")

# ── Curse Dialog ──────────────────────────────────────────────────────────────
func _on_curse_offered(options: Array) -> void:
	if _curse_dialog:
		_curse_dialog.queue_free()
	_curse_dialog = _build_curse_dialog(options)
	ui.add_child(_curse_dialog)

func _build_curse_dialog(options: Array) -> Control:
	var vp  := get_viewport_rect().size
	var pw  := minf(vp.x - 16.0, 440.0)
	var ph  := minf(float(options.size()) * 96.0 + 160.0, vp.y - 40.0)

	var root := Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.position     = Vector2.ZERO
	root.size         = vp

	var bg := ColorRect.new()
	bg.position     = Vector2.ZERO
	bg.size         = vp
	bg.color        = Color(0.0, 0.0, 0.0, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)

	var panel := PanelContainer.new()
	panel.position = Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5)
	panel.size     = Vector2(pw, ph)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text                 = "⚠  CURSE OFFERED  ⚠"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.modulate             = Color(1.0, 0.4, 0.2)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text               = "Accept a curse for a powerful reward — or skip for free."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.modulate           = Color(0.8, 0.8, 0.8)
	subtitle.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var card_col := VBoxContainer.new()
	card_col.add_theme_constant_override("separation", 8)
	card_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card_col)

	for curse in options:
		card_col.add_child(_build_curse_card(curse, root))

	var skip_btn := Button.new()
	skip_btn.text = "Skip (no reward)"
	skip_btn.add_theme_font_size_override("font_size", 14)
	skip_btn.pressed.connect(func() -> void:
		root.queue_free()
		_curse_dialog = null
		GameManager.decline_curse()
	)
	vbox.add_child(skip_btn)
	return root

func _build_curse_card(curse: Dictionary, dialog_root: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	card.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hbox.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text          = curse["name"]
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.modulate      = Color(1.0, 0.45, 0.1)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text          = curse["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_lbl)

	var reward_lbl := Label.new()
	reward_lbl.text          = "Reward: " + curse["reward"]
	reward_lbl.add_theme_font_size_override("font_size", 12)
	reward_lbl.modulate      = Color(0.3, 1.0, 0.5)
	reward_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(reward_lbl)

	var btn := Button.new()
	btn.text                = "ACCEPT"
	btn.custom_minimum_size = Vector2(80, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func() -> void:
		dialog_root.queue_free()
		_curse_dialog = null
		GameManager.accept_curse(curse)
		if _audio:
			_audio.play_any("curse_accept")
		_do_flash(Color(1.0, 0.3, 0.0, 0.45), 0.8)
	)
	hbox.add_child(btn)
	return card

# ── Wave Events ───────────────────────────────────────────────────────────────
func _on_wave_changed(w: int) -> void:
	if w <= 1:
		return
	var is_boss := (w % 5 == 0)
	var text    := ("💀 BOSS WAVE %d 💀" % w) if is_boss else ("WAVE %d" % w)
	var color   := Color(1.0, 0.25, 0.25) if is_boss else Color(1.0, 0.9, 0.5)
	_show_wave_banner(text, color)

func _on_boss_wave(_wave: int) -> void:
	_do_flash(Color(1.0, 0.1, 0.1, 0.5), 0.6)
	if _audio:
		_audio.play_any("boss_music")

# ── Screen Flashes ────────────────────────────────────────────────────────────
func _on_upgrade_available_flash(_choices) -> void:
	if _audio:
		_audio.play_any("levelup")

func _do_flash(color: Color, duration: float) -> void:
	if not _level_flash:
		return
	_level_flash.size  = get_viewport().get_visible_rect().size
	_level_flash.color = color
	var tw := create_tween()
	tw.tween_property(_level_flash, "color:a", 0.0, duration)

# ── FX Spawning ───────────────────────────────────────────────────────────────
func _spawn_coin(world_pos: Vector2, xp: int) -> void:
	var coin: Node = COIN_SCENE.instantiate()
	coins_node.add_child(coin)
	# Apply curse coin multiplier
	var mult: float = GameManager.stats.get("coin_mult", 1.0)
	coin.global_position = world_pos + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	coin.setup(player, int(xp * mult))

func _spawn_magnet_orb(world_pos: Vector2) -> void:
	# Build a simple Area2D orb that attracts all coins when touched
	var orb       := Area2D.new()
	orb.z_index   = 5
	orb.collision_layer = 0
	orb.collision_mask  = 1   # player layer

	var shape     := CollisionShape2D.new()
	var circle    := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape   = circle
	orb.add_child(shape)

	var lbl       := Label.new()
	lbl.text      = "🧲"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.position  = Vector2(-12, -12)
	orb.add_child(lbl)

	orb.global_position = world_pos
	orb.body_entered.connect(func(body: Node) -> void:
		if not body.is_in_group("player"):
			return
		for coin in coins_node.get_children():
			if coin.has_method("attract_magnet"):
				coin.attract_magnet()
		# Small flash feedback
		_do_flash(Color(0.2, 1.0, 0.5, 0.3), 0.3)
		orb.queue_free()
	)
	coins_node.add_child(orb)

	# Bob gently like a coin
	var tw := orb.create_tween().set_loops()
	tw.tween_property(lbl, "position:y", -16.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(lbl, "position:y", -8.0,  0.5).set_ease(Tween.EASE_IN_OUT)

func _spawn_death_particles(world_pos: Vector2, color: Color) -> void:
	var p := DeathParticles.new()
	_get_fx().add_child(p)
	p.global_position = world_pos
	p.setup(color)

func _spawn_damage_number(world_pos: Vector2, amount: float) -> void:
	var dn := DamageNumber.new()
	_get_fx().add_child(dn)
	dn.global_position = world_pos
	dn.setup(int(amount))

func _get_fx() -> Node2D:
	return fx_node if fx_node else $World

# ── Pause Overlay ─────────────────────────────────────────────────────────────
func _build_pause_overlay() -> void:
	_pause_overlay = Control.new()
	_pause_overlay.process_mode   = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.mouse_filter   = Control.MOUSE_FILTER_STOP
	_pause_overlay.z_index        = 30
	_pause_overlay.visible        = false

	var bg := ColorRect.new()
	bg.color        = Color(0.0, 0.0, 0.0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(bg)

	var lbl := Label.new()
	lbl.name                  = "PausedLabel"
	lbl.text                  = "PAUSED"
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(lbl)

	ui.add_child(_pause_overlay)
	call_deferred("_position_pause_overlay")

func _position_pause_overlay() -> void:
	var vp := get_viewport_rect().size
	_pause_overlay.position         = Vector2.ZERO
	_pause_overlay.size             = vp
	var bg  := _pause_overlay.get_child(0) as ColorRect
	bg.position = Vector2.ZERO
	bg.size     = vp
	var lbl := _pause_overlay.get_node("PausedLabel") as Label
	lbl.position = Vector2.ZERO
	lbl.size     = vp

# ── Pause ─────────────────────────────────────────────────────────────────────
func _toggle_pause() -> void:
	match GameManager.state:
		GameManager.State.PLAYING:
			GameManager.state = GameManager.State.PAUSED
			get_tree().paused = true
			pause_btn.text    = "▶"
			if _pause_overlay:
				_pause_overlay.visible = true
		GameManager.State.PAUSED:
			GameManager.state = GameManager.State.PLAYING
			get_tree().paused = false
			pause_btn.text    = "⏸"
			if _pause_overlay:
				_pause_overlay.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		_toggle_pause()

# ── Game Over ─────────────────────────────────────────────────────────────────
func _on_game_over() -> void:
	go_time_label.text  = "Time: "  + GameManager.get_time_string()
	go_level_label.text = "Level: " + str(GameManager.current_level)
	if _go_kills_label:
		_go_kills_label.text = "Kills: " + str(GameManager.kills)
	if _go_wave_label:
		_go_wave_label.text  = "Wave: " + str(GameManager.wave)
	if _go_coins_label:
		_go_coins_label.text = "Coins earned: " + str(GameManager.coins_this_run)
	# Add meta shop button
	_add_meta_shop_button()
	game_over_screen.show()
	await get_tree().create_timer(0.4).timeout
	get_tree().paused = true

func _add_meta_shop_button() -> void:
	var vbox := $UI/GameOverScreen/Panel/VBox
	# Don't add twice
	if vbox.has_node("MetaShopBtn"):
		return
	var btn := Button.new()
	btn.name = "MetaShopBtn"
	btn.text = "⚡  META UPGRADES"
	btn.add_theme_font_size_override("font_size", 16)
	vbox.add_child(btn)
	vbox.move_child(btn, restart_btn.get_index())
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(func() -> void:
		var shop := MetaShop.new()
		ui.add_child(shop)
	)

# ── Restart ───────────────────────────────────────────────────────────────────
func _restart() -> void:
	Engine.time_scale  = 1.0
	get_tree().paused  = false
	get_tree().reload_current_scene()
