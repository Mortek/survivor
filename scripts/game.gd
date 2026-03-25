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
var _go_best_label:  Label = null

# ── Level-up / boss screen flash ──────────────────────────────────────────────
var _level_flash: ColorRect = null

# ── Dev speed button ──────────────────────────────────────────────────────────
var _speed_btn:   Button = null
var _speed_index: int    = 0
const _SPEEDS := [1, 2, 3, 4, 5, 10, 20]

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

# ── Off-screen enemy indicators ───────────────────────────────────────────────
var _indicator_layer:  Control = null
var _indicator_nodes:  Array   = []   # pre-allocated Node2D pool with triangle draw
var _indicator_timer:  float   = 0.0
const INDICATOR_UPDATE_INTERVAL := 0.20
const INDICATOR_POOL_SIZE       := 8
const CHAIN_EXPLODE_RADIUS      := 80.0

# ── Pause overlay ─────────────────────────────────────────────────────────────
var _pause_overlay: Control = null

# ── Dash button ───────────────────────────────────────────────────────────────
var _dash_btn: Button = null

# ── Settings overlay ──────────────────────────────────────────────────────────
var _settings_overlay: Control = null

# ── Player hit flash tracking ─────────────────────────────────────────────────
var _prev_player_hp: int = 0

# ── Boss HP bar ────────────────────────────────────────────────────────────────
var _boss_hp_container: Control     = null
var _boss_hp_bar:       ProgressBar = null

# ── Wave countdown ─────────────────────────────────────────────────────────────
var _wave_countdown_label: Label = null

# ── Damage numbers toggle ──────────────────────────────────────────────────────
var _damage_numbers_enabled: bool = true

# ── Game-over combo label ──────────────────────────────────────────────────────
var _go_combo_label: Label = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_KILL_FEED_DATA = {
		Enemy.Type.BASIC:    ["☠ Basic",     Color(0.90, 0.40, 0.40)],
		Enemy.Type.FAST:     ["☠ Fast",      Color(1.00, 0.90, 0.30)],
		Enemy.Type.TANK:     ["☠ Tank",      Color(0.70, 0.40, 1.00)],
		Enemy.Type.BOSS:     ["💀 BOSS",     Color(1.00, 0.20, 1.00)],
		Enemy.Type.SPLITTER: ["☠ Splitter",  Color(0.30, 1.00, 0.60)],
		Enemy.Type.EXPLODER: ["💥 Exploder", Color(1.00, 0.55, 0.10)],
		Enemy.Type.SHIELDER: ["🛡 Shielder",  Color(0.40, 0.70, 1.00)],
		Enemy.Type.HEALER:      ["💚 Healer",     Color(0.20, 0.90, 0.80)],
		Enemy.Type.SWARM:       ["☠ Swarm",       Color(1.00, 0.60, 0.80)],
		Enemy.Type.TELEPORTER:  ["⟨⟩ Teleporter", Color(0.20, 0.92, 1.00)],
		Enemy.Type.CHARGER:     ["↯ Charger",      Color(0.90, 0.20, 0.30)],
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
	pause_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_btn.z_index      = 31
	pause_btn.z_as_relative = false
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

	# ── Dash button ──
	_build_dash_button()

	# ── Settings button ──
	_build_settings_button()

	# ── Stats button ──
	_build_stats_button()

	# ── Off-screen indicators ──
	_build_indicator_layer()

	# ── Vignette ──
	_build_vignette()

	# ── Wave countdown ──
	_build_wave_countdown()

	# ── Load damage numbers setting ──
	_damage_numbers_enabled = _load_setting("damage_numbers", 1.0) > 0.5

	# ── Tutorial hints (first run only) ──
	var _meta := get_node_or_null("/root/MetaManager")
	if _meta and not _meta.tutorial_done:
		_meta.tutorial_done = true
		_meta._save()
		_show_tutorial_hints()

	# ── Red flash on player hit ──
	player.health_changed.connect(_on_player_health_changed)
	_prev_player_hp = GameManager.stats["max_health"]

	# ── Animated game background ──
	_build_game_background()

	# ── Lucky Star: offer free upgrade on first frame ──
	if meta and meta.get_upgrade_level("lucky_start") >= 1:
		call_deferred("_lucky_start_offer")

# ── Game Background ───────────────────────────────────────────────────────────
func _build_game_background() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)

	var vp := get_viewport_rect().size
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for _i in 60:
		var star := ColorRect.new()
		var sz   := rng.randf_range(1.0, 3.0)
		star.size     = Vector2(sz, sz)
		star.position = Vector2(rng.randf_range(0.0, vp.x), rng.randf_range(0.0, vp.y))
		star.color    = Color(1.0, 1.0, 1.0, rng.randf_range(0.1, 0.6))
		bg_layer.add_child(star)
		# Pulse animation with random phase
		var tw := star.create_tween().set_loops()
		var phase := rng.randf_range(0.0, 3.0)
		tw.tween_interval(phase)
		tw.tween_property(star, "modulate:a", 1.0, rng.randf_range(0.8, 2.0)).set_trans(Tween.TRANS_SINE)
		tw.tween_property(star, "modulate:a", 0.2, rng.randf_range(0.8, 2.0)).set_trans(Tween.TRANS_SINE)

# ── Lucky Star ────────────────────────────────────────────────────────────────
func _lucky_start_offer() -> void:
	GameManager.offer_free_upgrade()

# ── Dev Speed Button ──────────────────────────────────────────────────────────
func _create_speed_button() -> void:
	_speed_btn = Button.new()
	_speed_btn.text = "1x"
	_speed_btn.add_theme_font_size_override("font_size", 13)
	_speed_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_speed_btn.z_index      = 31
	_speed_btn.z_as_relative = false
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
	GameManager.desired_time_scale = Engine.time_scale
	_speed_btn.text   = str(_SPEEDS[_speed_index]) + "x"

# ── Extra Game-Over Labels ────────────────────────────────────────────────────
func _build_extra_go_labels() -> void:
	var vbox      := $UI/GameOverScreen/Panel/VBox
	_go_kills_label = _make_go_label()
	_go_wave_label  = _make_go_label()
	_go_coins_label = _make_go_label()
	_go_combo_label = _make_go_label()
	_go_combo_label.modulate = Color(1.0, 0.85, 0.2)
	_go_best_label  = _make_go_label()
	_go_best_label.add_theme_font_size_override("font_size", 14)
	_go_best_label.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(_go_kills_label)
	vbox.add_child(_go_wave_label)
	vbox.add_child(_go_coins_label)
	vbox.add_child(_go_combo_label)
	vbox.add_child(_go_best_label)
	var btn_idx := restart_btn.get_index()
	vbox.move_child(_go_kills_label,  btn_idx)
	vbox.move_child(_go_wave_label,   btn_idx + 1)
	vbox.move_child(_go_coins_label,  btn_idx + 2)
	vbox.move_child(_go_combo_label,  btn_idx + 3)
	vbox.move_child(_go_best_label,   btn_idx + 4)

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

# ── Vignette ──────────────────────────────────────────────────────────────────
func _build_vignette() -> void:
	var sz  := Vector2i(64, 64)
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	for y in sz.y:
		for x in sz.x:
			var nx    := float(x) / (sz.x - 1) * 2.0 - 1.0
			var ny    := float(y) / (sz.y - 1) * 2.0 - 1.0
			var d     := maxf(absf(nx), absf(ny))
			var alpha := clampf((d - 0.55) / 0.45, 0.0, 1.0) * 0.48
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	var vignette := TextureRect.new()
	vignette.texture      = ImageTexture.create_from_image(img)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.z_index      = 10
	ui.add_child(vignette)

# ── Wave Countdown ─────────────────────────────────────────────────────────────
func _build_wave_countdown() -> void:
	_wave_countdown_label = Label.new()
	_wave_countdown_label.add_theme_font_size_override("font_size", 12)
	_wave_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_countdown_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_wave_countdown_label.modulate             = Color(1.0, 1.0, 0.8, 0.7)
	_wave_countdown_label.z_index              = 11
	_wave_countdown_label.set_anchor_and_offset(SIDE_LEFT,   0.5, -55.0)
	_wave_countdown_label.set_anchor_and_offset(SIDE_TOP,    0.0,  50.0)
	_wave_countdown_label.set_anchor_and_offset(SIDE_RIGHT,  0.5,  55.0)
	_wave_countdown_label.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  66.0)
	ui.add_child(_wave_countdown_label)

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
	var col := Color(1.0, 0.85, 0.1) if count < 10 else Color(1.0, 0.3, 0.1)
	_add_kill_feed_entry("×%d COMBO!" % count, col)
	if _audio and count >= 5:
		_audio.play_any("combo")

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
	if enemy.enemy_type == Enemy.Type.BOSS:
		_play_boss_intro(enemy)
		_create_boss_hp_bar(enemy)

func _on_enemy_died(world_pos: Vector2, xp: int, color: Color, type: int, hit_dir: Vector2 = Vector2.ZERO) -> void:
	call_deferred("_spawn_coin", world_pos, xp)
	# Use the actual hit direction from the killing projectile
	var splash_dir := hit_dir if hit_dir.length() > 0.1 else (world_pos - player.global_position).normalized()
	call_deferred("_spawn_death_particles", world_pos, color, splash_dir)
	# Bonus coin drop chance (Lucky Breaks meta upgrade)
	var extra_drop: float = GameManager.stats.get("lucky_drop_chance", 0.0)
	if randf() < 0.01 + extra_drop + GameManager.stats.get("magnet_orb_bonus", 0.0):
		call_deferred("_spawn_magnet_orb", world_pos)
	GameManager.add_kill()
	player.on_kill()
	# Chain Reaction: explode nearby enemies on kill
	var chain_chance: float = GameManager.stats.get("chain_explosion", 0.0)
	if chain_chance > 0.0 and randf() < chain_chance:
		var explosion_dmg := float(GameManager.stats.get("damage", 10)) * 0.5
		call_deferred("_chain_explode", world_pos, explosion_dmg)

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
		var hit_pick: String = (["hit", "hit2", "hit3"] as Array[String])[randi() % 3]
		var pitch := 1.0 + clampf(float(GameManager.combo_count) * 0.035, 0.0, 0.45)
		_audio.play_pitched(hit_pick, pitch)

func _on_split_requested(world_pos: Vector2) -> void:
	# Spawn 2 small BASIC enemies at the split position
	var wave_mult := GameManager.get_wave_multiplier() * 0.4
	call_deferred("_spawn_split_children", world_pos, wave_mult)

func _spawn_split_children(world_pos: Vector2, wave_mult: float) -> void:
	for off in [Vector2(-28, -10), Vector2(28, 10)]:
		spawner.spawn_at(Enemy.Type.BASIC, world_pos + off, wave_mult, false)

# ── Boss HP Bar ───────────────────────────────────────────────────────────────
func _create_boss_hp_bar(boss: Node) -> void:
	if _boss_hp_container:
		_boss_hp_container.queue_free()
	_boss_hp_container = Control.new()
	_boss_hp_container.z_index      = 15
	_boss_hp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centered narrow bar above the XP bar
	_boss_hp_container.set_anchor_and_offset(SIDE_LEFT,   0.15, 0.0)
	_boss_hp_container.set_anchor_and_offset(SIDE_TOP,    1.0, -44.0)
	_boss_hp_container.set_anchor_and_offset(SIDE_RIGHT,  0.85, 0.0)
	_boss_hp_container.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -22.0)
	_boss_hp_container.modulate.a = 0.0

	_boss_hp_bar = ProgressBar.new()
	_boss_hp_bar.max_value       = 100
	_boss_hp_bar.value           = 100
	_boss_hp_bar.show_percentage = false
	_boss_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.1, 0.15)
	fill.set_corner_radius_all(4)
	_boss_hp_bar.add_theme_stylebox_override("fill", fill)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.05, 0.05, 0.8)
	bg_style.set_corner_radius_all(4)
	_boss_hp_bar.add_theme_stylebox_override("background", bg_style)
	_boss_hp_container.add_child(_boss_hp_bar)

	var lbl := Label.new()
	lbl.text                 = "BOSS"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	lbl.modulate             = Color(1.0, 0.9, 0.9)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boss_hp_container.add_child(lbl)

	ui.add_child(_boss_hp_container)
	# Fade in smoothly
	var tw_in := _boss_hp_container.create_tween()
	tw_in.tween_property(_boss_hp_container, "modulate:a", 1.0, 0.4)

	var e := boss as Enemy
	if e:
		e.hit_taken.connect(func(_pos: Vector2, _amt: float) -> void:
			if is_instance_valid(e) and is_instance_valid(_boss_hp_bar):
				_boss_hp_bar.value = (e.current_hp / e.max_hp) * 100.0
		)
		e.died.connect(func(_pos, _xp, _col, _type, _hdir) -> void:
			if is_instance_valid(_boss_hp_container):
				var tw := _boss_hp_container.create_tween()
				tw.tween_property(_boss_hp_container, "modulate:a", 0.0, 0.5)
				tw.tween_callback(_boss_hp_container.queue_free)
			_boss_hp_container = null
			_boss_hp_bar       = null
		)

# ── Boss Death Hitpause ───────────────────────────────────────────────────────
func _boss_death_hitpause() -> void:
	Engine.time_scale = 0.15
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(0.8)
	await get_tree().create_timer(0.25, true, false, true).timeout   # real-time timer
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
	_styled_panel(panel, 18)
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
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.14, 0.14, 0.22, 0.9)
	card_style.set_corner_radius_all(10)
	card_style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", card_style)

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
	_boss_edge_warning()
	if _audio:
		_audio.play_any("boss_music")

func _boss_edge_warning() -> void:
	var vp := get_viewport_rect().size
	var mid_y := vp.y * 0.40

	# ── Cinematic dark overlay ──
	var overlay := ColorRect.new()
	overlay.position      = Vector2.ZERO
	overlay.size          = vp
	overlay.color         = Color(0.0, 0.0, 0.0, 0.0)
	overlay.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	overlay.z_index       = 21
	ui.add_child(overlay)
	var tw_ov := overlay.create_tween()
	tw_ov.tween_property(overlay, "color:a", 0.35, 0.2).set_trans(Tween.TRANS_QUAD)
	tw_ov.tween_interval(1.2)
	tw_ov.tween_property(overlay, "color:a", 0.0, 0.4)
	tw_ov.tween_callback(overlay.queue_free)

	# ── Cinematic letterbox bars (top + bottom) ──
	var bar_h := 32.0
	for y_pos in [0.0, vp.y - bar_h]:
		var bar := ColorRect.new()
		bar.position      = Vector2(0, y_pos)
		bar.size          = Vector2(vp.x, bar_h)
		bar.color         = Color(0.0, 0.0, 0.0, 0.0)
		bar.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		bar.z_index       = 22
		ui.add_child(bar)
		var tw := bar.create_tween()
		tw.tween_property(bar, "color:a", 0.9, 0.18).set_trans(Tween.TRANS_QUAD)
		tw.tween_interval(1.2)
		tw.tween_property(bar, "color:a", 0.0, 0.35)
		tw.tween_callback(bar.queue_free)

	# ── Red accent lines sweep from edges to center ──
	var line_h := 2.0
	# Left half sweeps in from off-screen left
	var line_l := ColorRect.new()
	line_l.position      = Vector2(-vp.x * 0.5, mid_y - line_h * 0.5)
	line_l.size          = Vector2(vp.x * 0.5, line_h)
	line_l.color         = Color(1.0, 0.12, 0.22, 0.9)
	line_l.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	line_l.z_index       = 23
	ui.add_child(line_l)
	var tw_ll := line_l.create_tween()
	tw_ll.tween_property(line_l, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw_ll.tween_interval(1.0)
	tw_ll.tween_property(line_l, "color:a", 0.0, 0.35)
	tw_ll.tween_callback(line_l.queue_free)
	# Right half sweeps in from off-screen right
	var line_r := ColorRect.new()
	line_r.position      = Vector2(vp.x, mid_y - line_h * 0.5)
	line_r.size          = Vector2(vp.x * 0.5, line_h)
	line_r.color         = Color(1.0, 0.12, 0.22, 0.9)
	line_r.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	line_r.z_index       = 23
	ui.add_child(line_r)
	var tw_lr := line_r.create_tween()
	tw_lr.tween_property(line_r, "position:x", vp.x * 0.5, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw_lr.tween_interval(1.0)
	tw_lr.tween_property(line_r, "color:a", 0.0, 0.35)
	tw_lr.tween_callback(line_r.queue_free)

	# ── "BOSS INCOMING" label — centered with proper pivot ──
	var warn_lbl := Label.new()
	warn_lbl.text                 = "⚠  BOSS INCOMING  ⚠"
	warn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	warn_lbl.add_theme_font_size_override("font_size", 22)
	warn_lbl.modulate             = Color(1.0, 0.15, 0.25, 0.0)
	warn_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	warn_lbl.z_index              = 24
	var lbl_w := 300.0
	var lbl_h := 36.0
	warn_lbl.size                 = Vector2(lbl_w, lbl_h)
	warn_lbl.position             = Vector2((vp.x - lbl_w) * 0.5, mid_y - lbl_h * 0.5)
	warn_lbl.pivot_offset         = Vector2(lbl_w * 0.5, lbl_h * 0.5)
	warn_lbl.scale                = Vector2(1.6, 1.6)
	ui.add_child(warn_lbl)
	var tw_lbl := warn_lbl.create_tween()
	tw_lbl.set_parallel(true)
	tw_lbl.tween_property(warn_lbl, "modulate:a", 1.0, 0.18)
	tw_lbl.tween_property(warn_lbl, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_lbl.set_parallel(false)
	tw_lbl.tween_interval(0.8)
	tw_lbl.tween_property(warn_lbl, "modulate:a", 0.0, 0.4)
	tw_lbl.tween_callback(warn_lbl.queue_free)

# ── Screen Flashes ────────────────────────────────────────────────────────────
func _on_upgrade_available_flash(_choices) -> void:
	if _audio:
		_audio.play_any("levelup")

func _do_flash(_color: Color, _duration: float) -> void:
	return

# ── FX Spawning ───────────────────────────────────────────────────────────────
func _chain_explode(pos: Vector2, dmg: float) -> void:
	var r2 := CHAIN_EXPLODE_RADIUS * CHAIN_EXPLODE_RADIUS
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if (enemy as Node2D).global_position.distance_squared_to(pos) <= r2:
			enemy.take_damage(dmg)
	_do_flash(Color(1.0, 0.65, 0.1, 0.20), 0.15)

func _spawn_coin(world_pos: Vector2, xp: int) -> void:
	var coin: Node = COIN_SCENE.instantiate()
	coins_node.add_child(coin)
	# Apply curse coin multiplier
	var mult: float = GameManager.stats.get("coin_mult", 1.0)
	coin.global_position = world_pos + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	coin.setup(player, int(xp * mult))

func _spawn_magnet_orb(world_pos: Vector2) -> void:
	var orb := Area2D.new()
	orb.z_index         = 5
	orb.collision_layer = 0
	orb.collision_mask  = 1

	var shape  := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 20.0
	shape.shape   = circle
	orb.add_child(shape)

	# Glowing orb visual using Node2D draw
	var visual    := Node2D.new()
	var orb_color := Color(0.2, 1.0, 0.65)
	visual.connect("draw", func() -> void:
		visual.draw_circle(Vector2.ZERO, 24.0, Color(orb_color.r, orb_color.g, orb_color.b, 0.12))
		visual.draw_circle(Vector2.ZERO, 18.0, Color(orb_color.r, orb_color.g, orb_color.b, 0.22))
		visual.draw_circle(Vector2.ZERO, 12.0, Color(orb_color.r, orb_color.g, orb_color.b, 0.55))
		visual.draw_circle(Vector2.ZERO,  7.0, Color(orb_color.r, orb_color.g, orb_color.b, 0.90))
		visual.draw_circle(Vector2.ZERO,  3.5, Color(1.0, 1.0, 1.0, 0.95))
	)
	orb.add_child(visual)

	# Pulsate scale
	var tw_pulse := visual.create_tween().set_loops()
	tw_pulse.tween_property(visual, "scale", Vector2(1.35, 1.35), 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_pulse.tween_property(visual, "scale", Vector2(0.80, 0.80), 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Pulsate alpha glow
	var tw_alpha := visual.create_tween().set_loops()
	tw_alpha.tween_property(visual, "modulate:a", 1.0, 0.38).set_trans(Tween.TRANS_SINE)
	tw_alpha.tween_property(visual, "modulate:a", 0.5, 0.38).set_trans(Tween.TRANS_SINE)

	# Periodic particle emission
	var particle_timer := Timer.new()
	particle_timer.wait_time = 0.12
	particle_timer.timeout.connect(func() -> void:
		if is_instance_valid(orb):
			_emit_magnet_particle(orb.global_position, orb_color)
	)
	orb.add_child(particle_timer)

	orb.global_position = world_pos
	coins_node.add_child(orb)
	visual.queue_redraw()
	particle_timer.start()

	orb.body_entered.connect(func(body: Node) -> void:
		if not body.is_in_group("player"):
			return
		_do_flash(Color(0.2, 1.0, 0.5, 0.3), 0.3)
		if _audio:
			_audio.play_any("coin_attract")
		orb.queue_free()
		# Pull ALL XP orbs on the entire level toward the player
		for coin in coins_node.get_children():
			if coin.has_method("attract_magnet"):
				coin.attract_magnet()
		# Zoom out camera gently
		if camera:
			var tw_zoom := camera.create_tween()
			tw_zoom.tween_property(camera, "zoom", Vector2(0.55, 0.55), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_wait_for_coins_then_zoom_in()
	)

func _wait_for_coins_then_zoom_in() -> void:
	# Small delay before checking, let coins start moving
	await get_tree().create_timer(0.15).timeout
	var elapsed := 0.0
	while elapsed < 4.0 and coins_node.get_child_count() > 0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	# Smooth zoom back in
	if camera and is_instance_valid(camera):
		var tw_in := camera.create_tween()
		tw_in.tween_property(camera, "zoom", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _emit_magnet_particle(world_pos: Vector2, color: Color) -> void:
	var p := ColorRect.new()
	p.size  = Vector2(4.0, 4.0)
	p.color = color
	_get_fx().add_child(p)
	p.global_position = world_pos + Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	var end_pos := p.global_position + dir * randf_range(18.0, 38.0)
	var tw := p.create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "global_position", end_pos, 0.55)
	tw.tween_property(p, "modulate:a", 0.0, 0.55)
	tw.tween_callback(p.queue_free).set_delay(0.55)

func _spawn_death_particles(world_pos: Vector2, color: Color, hit_dir: Vector2 = Vector2.ZERO) -> void:
	var p := DeathParticles.new()
	_get_fx().add_child(p)
	p.global_position = world_pos
	p.setup(color, hit_dir)

func _spawn_damage_number(world_pos: Vector2, amount: float) -> void:
	if not _damage_numbers_enabled:
		return
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
	_pause_overlay.mouse_filter   = Control.MOUSE_FILTER_IGNORE
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

# ── Stats Button & Popup ───────────────────────────────────────────────────────
var _stats_popup: Control = null
var _stats_owns_pause: bool = false
var _stats_btn: Button = null
var _settings_btn_ref: Button = null

func _build_stats_button() -> void:
	var btn := Button.new()
	btn.text = "📊"
	btn.add_theme_font_size_override("font_size", 20)
	btn.custom_minimum_size = Vector2(48, 26)
	btn.process_mode   = Node.PROCESS_MODE_ALWAYS
	btn.z_index        = 35
	btn.z_as_relative  = false
	btn.pressed.connect(_open_stats_popup)
	_stats_btn = btn
	$UI/HUD.add_child(btn)
	call_deferred("_position_stats_btn", btn)

func _position_stats_btn(btn: Button) -> void:
	var vp := get_viewport_rect().size
	btn.position = Vector2(vp.x - 162.0, 26.0)

func _close_stats_popup() -> void:
	if _stats_popup:
		_stats_popup.queue_free()
		_stats_popup = null
	if _stats_owns_pause:
		_stats_owns_pause = false
		GameManager.state = GameManager.State.PLAYING
		get_tree().paused = false

func _open_stats_popup() -> void:
	if _stats_popup:
		_close_stats_popup()
		return
	# Don't allow opening stats if paused by the pause button (not by this popup)
	if GameManager.state == GameManager.State.PAUSED:
		return
	_stats_owns_pause = true
	GameManager.state = GameManager.State.PAUSED
	get_tree().paused = true
	_stats_popup = _build_stats_popup()
	ui.add_child(_stats_popup)

func _build_stats_popup() -> Control:
	var vp  := get_viewport_rect().size
	var pw  := minf(vp.x - 24.0, 300.0)
	var ph  := minf(vp.y * 0.72, 460.0)

	var root := Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.z_index      = 29
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color        = Color(0, 0, 0, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_stats_popup()
	)
	root.add_child(bg)

	var panel := PanelContainer.new()
	_styled_panel(panel, 16)
	panel.position = Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5)
	panel.size     = Vector2(pw, ph)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)

	# X close button — top-right of panel
	var close_x := Button.new()
	close_x.text = "✕"
	close_x.process_mode = Node.PROCESS_MODE_ALWAYS
	close_x.add_theme_font_size_override("font_size", 16)
	close_x.custom_minimum_size = Vector2(30, 28)
	close_x.z_index = 30
	close_x.position = Vector2(panel.position.x + pw - 38.0, panel.position.y + 4.0)
	close_x.pressed.connect(_close_stats_popup)
	root.add_child(close_x)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text                 = "STATS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vbox.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	var s := GameManager.stats
	var categories: Array = [
		["⚔  OFFENSE", [
			["DMG",         "%d" % s.get("damage", 0)],
			["Crit Chance", "%d%%" % int(s.get("crit_chance", 0.0) * 100.0)],
			["Crit DMG",    "2.0×"],
			["ATK Speed",   "%.2f×" % s.get("attack_speed", 1.0)],
			["Projectiles", "%d" % s.get("projectile_count", 1)],
			["Pierce",      "%d" % s.get("pierce", 0)],
			["Area",        "%.0f%%" % (s.get("area_mult", 1.0) * 100.0)],
			["Knockback",   "%.0f" % s.get("knockback", 0.0)],
		]],
		["🛡  DEFENSE", [
			["Max HP",       "%d" % s.get("max_health", 100)],
			["Armor",        "%d" % s.get("armor", 0)],
			["Dmg Reduction","%d%%" % int(s.get("dmg_reduction", 0.0) * 100.0)],
			["Lifesteal",    "%d HP/kill" % int(s.get("lifesteal", 0.0))],
			["Regen",        "%.1f/s" % s.get("regen", 0.0)],
			["Shield",       "%d charges" % s.get("shield_charges", 0)],
		]],
		["✦  UTILITY", [
			["Speed",         "%.0f" % s.get("speed", 150.0)],
			["XP Gain",       "%.0f%%" % (s.get("xp_multiplier", 1.0) * 100.0)],
			["Pickup Range",  "%.0f" % s.get("pickup_radius", 60.0)],
			["Slow on Hit",   "Yes" if s.get("slow_on_hit", false) else "No"],
			["Burn on Hit",   "Yes" if s.get("burn_on_hit", false) else "No"],
			["Dash",          "Yes" if s.get("dash_enabled", false) else "No"],
		]],
	]

	for cat in categories:
		var header := Label.new()
		header.text          = cat[0]
		header.add_theme_font_size_override("font_size", 14)
		header.modulate      = Color(1.0, 0.85, 0.3)
		inner.add_child(header)

		inner.add_child(HSeparator.new())

		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 4)
		inner.add_child(grid)

		for row in cat[1]:
			var key_lbl := Label.new()
			key_lbl.text                  = row[0]
			key_lbl.add_theme_font_size_override("font_size", 13)
			key_lbl.modulate              = Color(0.75, 0.75, 0.75)
			key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(key_lbl)
			var val_lbl := Label.new()
			val_lbl.text                 = row[1]
			val_lbl.add_theme_font_size_override("font_size", 13)
			val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(val_lbl)

	return root

# ── Player Hit Flash ──────────────────────────────────────────────────────────
func _on_player_health_changed(current: int, _max: int) -> void:
	if current < _prev_player_hp and current > 0:
		_do_flash(Color(1.0, 0.1, 0.1, 0.35), 0.25)
	_prev_player_hp = current

# ── Dash Button ───────────────────────────────────────────────────────────────
func _build_dash_button() -> void:
	_dash_btn = Button.new()
	_dash_btn.text    = "DASH"
	_dash_btn.add_theme_font_size_override("font_size", 18)
	_dash_btn.visible = GameManager.stats.get("dash_enabled", false)
	_dash_btn.pressed.connect(func() -> void: player.try_dash())
	player.dash_ready.connect(func(is_ready: bool) -> void:
		_dash_btn.disabled = not is_ready
	)
	GameManager.stats_changed.connect(func() -> void:
		_dash_btn.visible = GameManager.stats.get("dash_enabled", false)
	)
	$UI/HUD.add_child(_dash_btn)
	call_deferred("_position_dash_btn")

func _position_dash_btn() -> void:
	if not _dash_btn:
		return
	var vp := get_viewport_rect().size
	_dash_btn.custom_minimum_size = Vector2(80, 50)
	_dash_btn.position = Vector2(vp.x * 0.5 - 40.0, vp.y - 100.0)

# ── Settings Button ───────────────────────────────────────────────────────────
func _build_settings_button() -> void:
	var btn := Button.new()
	btn.text = "⚙"
	btn.add_theme_font_size_override("font_size", 20)
	btn.custom_minimum_size = Vector2(48, 26)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.z_index      = 31
	btn.z_as_relative = false
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.7, 0.9, 1.0, 1.0))
	btn.pressed.connect(_open_settings)
	_settings_btn_ref = btn
	$UI/HUD.add_child(btn)
	call_deferred("_position_settings_btn", btn)

func _position_settings_btn(btn: Button) -> void:
	var vp := get_viewport_rect().size
	btn.position = Vector2(vp.x - 108.0, 26.0)

func _open_settings() -> void:
	if _settings_overlay:
		return
	if GameManager.state == GameManager.State.PLAYING:
		GameManager.state = GameManager.State.PAUSED
		get_tree().paused = true
	_settings_overlay = _build_settings_overlay()
	ui.add_child(_settings_overlay)

func _build_settings_overlay() -> Control:
	var vp  := get_viewport_rect().size
	var root := Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.position     = Vector2.ZERO
	root.size         = vp

	var bg := ColorRect.new()
	bg.color        = Color(0, 0, 0, 0.75)
	bg.position     = Vector2.ZERO
	bg.size         = vp
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var pw := minf(vp.x - 16.0, 380.0)
	var ph := 210.0
	var panel := PanelContainer.new()
	_styled_panel(panel, 16)
	panel.position = Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5)
	panel.size     = Vector2(pw, ph)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title row with close X in the top-right
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	var title := Label.new()
	title.text                 = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title_row.add_child(title)

	var close_x := Button.new()
	close_x.text = "✕"
	close_x.process_mode = Node.PROCESS_MODE_ALWAYS
	close_x.add_theme_font_size_override("font_size", 16)
	close_x.custom_minimum_size = Vector2(30, 28)
	close_x.pressed.connect(func() -> void:
		root.queue_free()
		_settings_overlay = null
		if GameManager.state == GameManager.State.PAUSED:
			GameManager.state = GameManager.State.PLAYING
			get_tree().paused = false
	)
	title_row.add_child(close_x)

	# Master volume
	vbox.add_child(_make_volume_row("Volume", func(v: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(v))
		_save_setting("volume", v)
	, _load_setting("volume", 0.8)))

	# Vibration toggle
	var vib_row := HBoxContainer.new()
	var vib_lbl := Label.new()
	vib_lbl.text                  = "Vibration"
	vib_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vib_lbl.add_theme_font_size_override("font_size", 15)
	vib_row.add_child(vib_lbl)
	var vib_toggle := CheckButton.new()
	vib_toggle.button_pressed = _load_setting("vibration", 1.0) > 0.5
	vib_toggle.toggled.connect(func(on: bool) -> void:
		_save_setting("vibration", 1.0 if on else 0.0)
	)
	vib_row.add_child(vib_toggle)
	vbox.add_child(vib_row)

	# Damage numbers toggle
	var dmg_row := HBoxContainer.new()
	var dmg_lbl := Label.new()
	dmg_lbl.text                  = "Damage Numbers"
	dmg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dmg_lbl.add_theme_font_size_override("font_size", 15)
	dmg_row.add_child(dmg_lbl)
	var dmg_toggle := CheckButton.new()
	dmg_toggle.button_pressed = _load_setting("damage_numbers", 1.0) > 0.5
	dmg_toggle.toggled.connect(func(on: bool) -> void:
		_damage_numbers_enabled = on
		_save_setting("damage_numbers", 1.0 if on else 0.0)
	)
	dmg_row.add_child(dmg_toggle)
	vbox.add_child(dmg_row)

	vbox.add_child(HSeparator.new())

	var menu_btn := Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.add_theme_font_size_override("font_size", 16)
	menu_btn.pressed.connect(func() -> void:
		_show_quit_confirm(ui)
	)
	vbox.add_child(menu_btn)

	# Apply saved volume on open
	var saved_vol := _load_setting("volume", 0.8)
	AudioServer.set_bus_volume_db(0, linear_to_db(saved_vol))

	return root

func _show_quit_confirm(settings_root: Node) -> void:
	var vp    := get_viewport_rect().size
	var cw    := minf(vp.x - 40.0, 300.0)

	# Full-screen opaque overlay to block the settings behind
	var overlay := Control.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.z_index      = 40
	overlay.z_as_relative = false
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color        = Color(0.0, 0.0, 0.0, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var confirm := PanelContainer.new()
	confirm.position = Vector2((vp.x - cw) * 0.5, vp.y * 0.35)
	confirm.size     = Vector2(cw, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.18, 1.0)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(20)
	confirm.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(confirm)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	confirm.add_child(vbox)

	var lbl := Label.new()
	lbl.text                 = "Quit to main menu?\nYour run will be lost."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)

	var yes_btn := Button.new()
	yes_btn.text = "Yes, quit"
	yes_btn.add_theme_font_size_override("font_size", 15)
	yes_btn.pressed.connect(func() -> void:
		Engine.time_scale = 1.0
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.add_theme_font_size_override("font_size", 15)
	no_btn.pressed.connect(overlay.queue_free)
	row.add_child(no_btn)

	settings_root.add_child(overlay)

func _make_volume_row(label_text: String, on_change: Callable, initial: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text                  = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 15)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value            = 0.0
	slider.max_value            = 1.0
	slider.step                 = 0.05
	slider.value                = initial
	slider.custom_minimum_size  = Vector2(120, 0)
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row

static func _styled_panel(panel: PanelContainer, padding: int = 16) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.16, 0.95)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(padding)
	style.border_color = Color(0.3, 0.35, 0.5, 0.3)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

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

# ── Per-Frame Updates ─────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_indicator_timer += delta
	if _indicator_timer >= INDICATOR_UPDATE_INTERVAL:
		_indicator_timer = 0.0
		_update_edge_indicators()
	# Wave countdown
	if _wave_countdown_label and spawner:
		var remaining: float = spawner.get_wave_time_remaining()
		_wave_countdown_label.text = "next wave: %ds" % maxi(int(ceil(remaining)), 0)

# ── Off-Screen Enemy Indicators ───────────────────────────────────────────────
func _build_indicator_layer() -> void:
	_indicator_layer = Control.new()
	_indicator_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_indicator_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator_layer.z_index      = 12
	ui.add_child(_indicator_layer)
	for _i in INDICATOR_POOL_SIZE:
		var arrow := _create_indicator_arrow()
		_indicator_layer.add_child(arrow)
		_indicator_nodes.append(arrow)
		# Subtle alpha pulse
		var tw := arrow.create_tween()
		tw.set_loops()
		tw.tween_property(arrow, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(arrow, "modulate:a", 0.55, 0.5).set_trans(Tween.TRANS_SINE)

func _create_indicator_arrow() -> Node2D:
	# Triangle arrow pointing right (rotated to face enemy direction)
	var arrow := Node2D.new()
	arrow.visible = false
	arrow.set_meta("ind_color", Color.WHITE)
	arrow.set_meta("ind_boss", false)
	arrow.connect("draw", func() -> void:
		var col: Color = arrow.get_meta("ind_color", Color.WHITE)
		var is_boss: bool = arrow.get_meta("ind_boss", false)
		var pts := PackedVector2Array([
			Vector2(5, 0),    # tip
			Vector2(-3, -4),  # top-left
			Vector2(-3, 4),   # bottom-left
		])
		arrow.draw_colored_polygon(pts, col)
		# Glow outline
		arrow.draw_polyline(PackedVector2Array([pts[1], pts[0], pts[2]]),
			Color(col.r, col.g, col.b, 0.3), 2.0, true)
		if is_boss:
			# Outer glow ring for boss
			arrow.draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 16,
				Color(col.r, col.g, col.b, 0.4), 1.5)
	)
	return arrow

func _update_edge_indicators() -> void:
	if not _indicator_layer:
		return
	for node in _indicator_nodes:
		node.visible = false
	var canvas_xform := get_viewport().get_canvas_transform()
	var vp           := get_viewport_rect().size
	const MARGIN     := 18.0
	var slot := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if slot >= _indicator_nodes.size():
			break
		if not is_instance_valid(enemy):
			continue
		var e := enemy as Enemy
		if not e:
			continue
		var screen_pos := canvas_xform * e.global_position
		if Rect2(Vector2.ZERO, vp).grow(-MARGIN * 2.0).has_point(screen_pos):
			continue
		var center := vp * 0.5
		var dir    := screen_pos - center
		if dir.length() < 0.01:
			continue
		var sx       := (vp.x * 0.5 - MARGIN) / maxf(absf(dir.x), 0.01)
		var sy       := (vp.y * 0.5 - MARGIN) / maxf(absf(dir.y), 0.01)
		var edge_pos := center + dir * minf(sx, sy)
		var col: Color
		var is_boss := e.enemy_type == Enemy.Type.BOSS
		if is_boss:
			col = Color(1.0, 0.2, 1.0)
		elif e.is_elite:
			col = Color(1.0, 0.75, 0.2)
		else:
			col = Color(1.0, 0.4, 0.4)
		var arrow := _indicator_nodes[slot] as Node2D
		arrow.set_meta("ind_color", col)
		arrow.set_meta("ind_boss", is_boss)
		arrow.position = edge_pos
		arrow.rotation = dir.angle()
		arrow.scale = Vector2(2.5, 2.5) if is_boss else Vector2(1.0, 1.0)
		arrow.visible  = true
		arrow.queue_redraw()
		slot += 1

# ── Tutorial Hints ────────────────────────────────────────────────────────────
func _show_tutorial_hints() -> void:
	var vp   := get_viewport_rect().size
	var tips := [
		"Use the joystick (left half) to move",
		"Your weapon fires automatically",
		"Collect gems to gain XP and level up",
		"Choose upgrades each level to get stronger!",
	]
	for i in tips.size():
		var lbl := Label.new()
		lbl.text                 = tips[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.modulate             = Color(1.0, 1.0, 0.85, 0.0)
		lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		lbl.size                 = Vector2(vp.x - 40.0, 24.0)
		lbl.position             = Vector2(20.0, vp.y * 0.52 + float(i) * 30.0)
		ui.add_child(lbl)
		var tw := lbl.create_tween()
		tw.tween_property(lbl, "modulate:a", 0.9, 0.4).set_delay(float(i) * 0.5)
		tw.tween_interval(3.5)
		tw.tween_property(lbl, "modulate:a", 0.0, 0.8)
		tw.tween_callback(lbl.queue_free)

# ── Focus Lost Auto-Pause ─────────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if GameManager.state == GameManager.State.PLAYING:
			_toggle_pause()

# ── Boss Intro Animation ──────────────────────────────────────────────────────
func _play_boss_intro(boss: Node) -> void:
	# Scale-in: boss starts tiny, grows to normal size with overshoot
	var sprite := boss.get_node_or_null("Sprite2D") as Node2D
	if sprite:
		sprite.scale = Vector2(0.05, 0.05)
		sprite.modulate.a = 0.0
		var tw := boss.create_tween()
		tw.set_parallel(true)
		tw.tween_property(sprite, "scale", Vector2(2.0, 2.0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(sprite, "modulate:a", 1.0, 0.3)
	# Strong screen shake
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(0.6)
	# Brief white flash instead of red fill
	_do_flash(Color(1.0, 1.0, 1.0, 0.35), 0.25)
	if _audio:
		_audio.play_any("boss_intro")

# ── Pause ─────────────────────────────────────────────────────────────────────
func _toggle_pause() -> void:
	match GameManager.state:
		GameManager.State.PLAYING:
			GameManager.state = GameManager.State.PAUSED
			get_tree().paused = true
			pause_btn.text    = "▶"
			if _pause_overlay:
				_pause_overlay.visible = true
			if _stats_btn:
				_stats_btn.disabled = true
				_stats_btn.modulate = Color(0.5, 0.5, 0.5, 0.6)
		GameManager.State.PAUSED:
			GameManager.state = GameManager.State.PLAYING
			get_tree().paused = false
			pause_btn.text    = "⏸"
			if _pause_overlay:
				_pause_overlay.visible = false
			if _stats_btn:
				_stats_btn.disabled = false
				_stats_btn.modulate = Color.WHITE

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
		_go_coins_label.text = "Coins earned: " + _fmt(GameManager.coins_this_run)
	if _go_combo_label:
		_go_combo_label.text = "Best combo: ×%d" % GameManager.max_combo
	var meta := get_node_or_null("/root/MetaManager")
	if meta:
		meta.update_best_run(GameManager.wave, GameManager.kills, GameManager.survival_time)
		meta.add_run_history(GameManager.wave, GameManager.kills, GameManager.survival_time, GameManager.coins_this_run)
	if _go_best_label:
		var meta2 := get_node_or_null("/root/MetaManager")
		_go_best_label.text = meta2.get_best_run_string() if meta2 else ""
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
	btn.text = "⚡  UPGRADES"
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
