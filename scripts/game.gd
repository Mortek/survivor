extends Node2D
## Game – root of the main scene, wires all systems together.

# ── Node References ───────────────────────────────────────────────────────────
@onready var player:          CharacterBody2D = $Player
@onready var camera:          Camera2D        = $Player/Camera2D
@onready var enemies_node:    Node2D          = $World/Enemies
@onready var coins_node:      Node2D          = $World/Coins
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

# ── Enemy / Coin ──────────────────────────────────────────────────────────────
func _on_enemy_spawned(enemy: Node) -> void:
	## Connect each new enemy's died signal so we can drop coins.
	if not enemy.died.is_connected(_on_enemy_died):
		enemy.died.connect(_on_enemy_died)

func _on_enemy_died(world_pos: Vector2, xp: int) -> void:
	# Defer coin spawn – called from inside a physics callback chain
	call_deferred("_spawn_coin", world_pos, xp)

func _spawn_coin(world_pos: Vector2, xp: int) -> void:
	var coin: Node = COIN_SCENE.instantiate()
	coins_node.add_child(coin)
	coin.global_position = world_pos + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	coin.setup(player, xp)

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
	## Back button / Escape toggles pause
	if event.is_action_pressed("ui_pause"):
		_toggle_pause()

# ── Game Over ─────────────────────────────────────────────────────────────────
func _on_game_over() -> void:
	go_time_label.text  = "Time: " + GameManager.get_time_string()
	go_level_label.text = "Level: " + str(GameManager.current_level)
	game_over_screen.show()
	await get_tree().create_timer(0.4).timeout
	get_tree().paused = true

# ── Restart ───────────────────────────────────────────────────────────────────
func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
