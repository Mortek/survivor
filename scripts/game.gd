extends Node2D
## Game – root of the main scene, wires all systems together.

# ── Node References ───────────────────────────────────────────────────────────
@onready var player:          CharacterBody2D = $Player
@onready var camera:          Camera2D        = $Player/Camera2D
@onready var enemies_node:    Node2D          = $World/Enemies
@onready var coins_node:      Node2D          = $World/Coins
# FX node for damage numbers + particles — created at runtime if absent from scene
var fx_node: Node2D = null
@onready var projectile_pool: ObjectPool      = $ProjectilePool
@onready var spawner:         Node            = $Spawner
@onready var ui:              CanvasLayer     = $UI
@onready var joystick:        Control         = $UI/VirtualJoystick
@onready var upgrade_menu:    Control         = $UI/UpgradeMenu
@onready var game_over_screen: Control        = $UI/GameOverScreen
@onready var pause_btn:       Button          = $UI/HUD/PauseButton
@onready var go_time_label:   Label           = $UI/GameOverScreen/Panel/VBox/TimeLabel
@onready var go_level_label:  Label           = $UI/GameOverScreen/Panel/VBox/LevelLabel
@onready var restart_btn:     Button          = $UI/GameOverScreen/Panel/VBox/RestartButton

const COIN_SCENE := preload("res://scenes/coin.tscn")

# ── Dynamic game-over labels (created at runtime) ─────────────────────────────
var _go_kills_label:  Label = null
var _go_wave_label:   Label = null
var _go_coins_label:  Label = null

# ── Level-up screen flash ─────────────────────────────────────────────────────
var _level_flash: ColorRect = null

# ── Dev speed button ──────────────────────────────────────────────────────────
var _speed_btn:   Button = null
var _speed_index: int    = 0
const _SPEEDS := [1, 2, 3, 4, 5]

# ── Cached autoload references ────────────────────────────────────────────────
var _audio: Node = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	GameManager.reset()

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

	# ── Game over ──
	GameManager.game_over_triggered.connect(_on_game_over)

	# ── Pause button ──
	pause_btn.pressed.connect(_toggle_pause)

	# ── Restart ──
	restart_btn.pressed.connect(_restart)

	game_over_screen.hide()

	# ── Dynamic game-over labels ──
	_build_extra_go_labels()

	# ── Level-up screen flash ──
	_level_flash = ColorRect.new()
	_level_flash.color        = Color(1.0, 1.0, 0.5, 0.0)
	_level_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_flash.z_index      = 20
	ui.add_child(_level_flash)
	GameManager.upgrade_available.connect(_on_upgrade_available_flash)
	GameManager.boss_wave_started.connect(_on_boss_wave_flash)

	# ── Cache autoloads ──
	_audio = get_node_or_null("/root/AudioManager")

	# ── Dev speed button ──
	_create_speed_button()

	# ── FX container (damage numbers + particles) ──
	# Use World/FX if it exists, otherwise use a new Node2D added to World.
	var maybe_fx := get_node_or_null("World/FX")
	if maybe_fx:
		fx_node = maybe_fx
	else:
		fx_node = Node2D.new()
		fx_node.name = "FX"
		$World.add_child(fx_node)

# ── Dev speed button ──────────────────────────────────────────────────────────
func _create_speed_button() -> void:
	_speed_btn = Button.new()
	_speed_btn.text = "1x"
	_speed_btn.add_theme_font_size_override("font_size", 14)
	# Anchor to bottom-right, small button above the XP bar
	_speed_btn.set_anchor_and_offset(SIDE_LEFT,   1.0, -60.0)
	_speed_btn.set_anchor_and_offset(SIDE_TOP,    1.0, -50.0)
	_speed_btn.set_anchor_and_offset(SIDE_RIGHT,  1.0, -10.0)
	_speed_btn.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -16.0)
	_speed_btn.pressed.connect(_on_speed_pressed)
	$UI/HUD.add_child(_speed_btn)

func _on_speed_pressed() -> void:
	_speed_index = (_speed_index + 1) % _SPEEDS.size()
	Engine.time_scale = float(_SPEEDS[_speed_index])
	_speed_btn.text   = str(_SPEEDS[_speed_index]) + "x"

func _build_extra_go_labels() -> void:
	var vbox := $UI/GameOverScreen/Panel/VBox
	# Insert before the restart button (last child)
	_go_kills_label = _make_go_label()
	_go_wave_label  = _make_go_label()
	_go_coins_label = _make_go_label()
	vbox.add_child(_go_kills_label)
	vbox.add_child(_go_wave_label)
	vbox.add_child(_go_coins_label)
	# Move them before the restart button
	var btn_idx := restart_btn.get_index()
	vbox.move_child(_go_kills_label,  btn_idx)
	vbox.move_child(_go_wave_label,   btn_idx + 1)
	vbox.move_child(_go_coins_label,  btn_idx + 2)

func _make_go_label() -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	return lbl

# ── Enemy / Coin / FX ─────────────────────────────────────────────────────────
func _on_enemy_spawned(enemy: Node) -> void:
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)
	if not enemy.hit_taken.is_connected(_on_enemy_hit_taken):
		enemy.hit_taken.connect(_on_enemy_hit_taken)

func _on_enemy_died(world_pos: Vector2, xp: int, color: Color) -> void:
	call_deferred("_spawn_coin", world_pos, xp)
	call_deferred("_spawn_death_particles", world_pos, color)
	GameManager.add_kill()
	player.on_kill()
	if _audio:
		if color.g < 0.3:   # purple / boss hue
			_audio.play_any("boss_die")
		else:
			_audio.play("die")

func _on_enemy_hit_taken(world_pos: Vector2, amount: float) -> void:
	call_deferred("_spawn_damage_number", world_pos, amount)
	if _audio:
		_audio.play("hit")

func _spawn_coin(world_pos: Vector2, xp: int) -> void:
	var coin: Node = COIN_SCENE.instantiate()
	coins_node.add_child(coin)
	coin.global_position = world_pos + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	coin.setup(player, xp)

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

# ── Screen Flashes ────────────────────────────────────────────────────────────
func _on_upgrade_available_flash(_choices) -> void:
	if _audio:
		_audio.play_any("levelup")

func _on_boss_wave_flash(_wave: int) -> void:
	_do_flash(Color(1.0, 0.1, 0.1, 0.5), 0.6)

func _do_flash(color: Color, duration: float) -> void:
	if not _level_flash:
		return
	_level_flash.size   = get_viewport().get_visible_rect().size
	_level_flash.color  = color
	var tween := create_tween()
	tween.tween_property(_level_flash, "color:a", 0.0, duration)

# ── Pause ─────────────────────────────────────────────────────────────────────
func _toggle_pause() -> void:
	match GameManager.state:
		GameManager.State.PLAYING:
			GameManager.state = GameManager.State.PAUSED
			get_tree().paused = true
			pause_btn.text    = "▶"
		GameManager.State.PAUSED:
			GameManager.state = GameManager.State.PLAYING
			get_tree().paused = false
			pause_btn.text    = "⏸"

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
		_go_wave_label.text  = "Wave: "  + str(GameManager.wave)
	if _go_coins_label:
		_go_coins_label.text = "Coins earned: " + str(GameManager.coins_this_run)
	game_over_screen.show()
	await get_tree().create_timer(0.4).timeout
	get_tree().paused = true

# ── Restart ───────────────────────────────────────────────────────────────────
func _restart() -> void:
	Engine.time_scale  = 1.0
	get_tree().paused  = false
	get_tree().reload_current_scene()
