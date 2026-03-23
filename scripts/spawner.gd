extends Node
## Spawner – instantiates enemies on a timer, scaling with waves.
## Supports BASIC, FAST, TANK, BOSS, SPLITTER, and EXPLODER types.
## Any enemy has an 8% chance to be Elite (3× HP, bonus XP).

# ── Signals ───────────────────────────────────────────────────────────────────
signal enemy_spawned(enemy: Node)

# ── Config ────────────────────────────────────────────────────────────────────
@export var enemy_scene:           PackedScene
@export var wave_duration:         float = 30.0
@export var base_spawn_interval:   float = 1.5
@export var max_on_screen:         int   = 45

# Enemy type shorthands — must be var, not const (enum values aren't compile-time literals in GDScript)
var ENEMY_TYPE_BASIC    := Enemy.Type.BASIC
var ENEMY_TYPE_FAST     := Enemy.Type.FAST
var ENEMY_TYPE_TANK     := Enemy.Type.TANK
var ENEMY_TYPE_BOSS     := Enemy.Type.BOSS
var ENEMY_TYPE_SPLITTER := Enemy.Type.SPLITTER
var ENEMY_TYPE_EXPLODER := Enemy.Type.EXPLODER

const ELITE_CHANCE := 0.08

# ── State ─────────────────────────────────────────────────────────────────────
var _player:        Node2D  = null
var _container:     Node    = null
var _spawn_timer:   float   = 0.0
var _wave_timer:    float   = 0.0
var _spawn_interval: float

func _ready() -> void:
	_spawn_interval = base_spawn_interval

func setup(player: Node2D, container: Node) -> void:
	_player    = player
	_container = container

# ── Processing ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return

	_spawn_timer += delta
	if _spawn_timer >= _spawn_interval:
		_spawn_timer = 0.0
		_try_spawn()

	_wave_timer += delta
	if _wave_timer >= wave_duration:
		_wave_timer = 0.0
		_next_wave()

func _next_wave() -> void:
	GameManager.advance_wave()
	_spawn_interval = maxf(base_spawn_interval / (1.0 + GameManager.wave * 0.12), 0.30)

	if GameManager.wave % 5 == 0:
		_spawn_boss()
	else:
		# Normal wave burst
		for _i in 6:
			_try_spawn()

	# Offer a curse right after boss waves (wave 6, 11, 16...)
	if GameManager.wave >= 6 and (GameManager.wave - 1) % 5 == 0:
		GameManager.try_offer_curse()

# ── Spawning ──────────────────────────────────────────────────────────────────
func _try_spawn() -> void:
	if not _player or not _container or not enemy_scene:
		return
	if get_tree().get_nodes_in_group("enemies").size() >= max_on_screen:
		return
	var type_int := _pick_type()
	var elite    := randf() < ELITE_CHANCE
	_spawn_enemy(type_int, GameManager.get_wave_multiplier(), elite)

func _spawn_boss() -> void:
	if not _player or not _container or not enemy_scene:
		return
	_spawn_enemy(ENEMY_TYPE_BOSS, GameManager.get_wave_multiplier(), false)

## Public – used by game.gd to spawn SPLITTER children at a given position.
func spawn_at(type_int: int, pos: Vector2, wave_mult: float, elite: bool = false) -> void:
	if not _player or not _container or not enemy_scene:
		return
	_spawn_enemy(type_int, wave_mult, elite, pos)

func _spawn_enemy(type_int: int, wave_mult: float, elite: bool, override_pos: Vector2 = Vector2.INF) -> void:
	var enemy: Node = enemy_scene.instantiate()
	enemy.enemy_type = type_int
	enemy.is_elite   = elite
	_container.add_child(enemy)
	enemy.global_position = override_pos if override_pos != Vector2.INF else _edge_position()
	enemy.activate(_player, wave_mult)
	enemy_spawned.emit(enemy)

func _pick_type() -> int:
	var w := GameManager.wave
	var r := randf()
	if w <= 2:
		# Only basics
		return ENEMY_TYPE_BASIC
	elif w <= 4:
		# Basics and fasts
		if r < 0.72: return ENEMY_TYPE_BASIC
		else:        return ENEMY_TYPE_FAST
	elif w <= 7:
		# Introduce tanks and splitters
		if   r < 0.45: return ENEMY_TYPE_BASIC
		elif r < 0.72: return ENEMY_TYPE_FAST
		elif r < 0.88: return ENEMY_TYPE_TANK
		else:          return ENEMY_TYPE_SPLITTER
	else:
		# All types, exploders appear at wave 8+
		if   r < 0.35: return ENEMY_TYPE_BASIC
		elif r < 0.58: return ENEMY_TYPE_FAST
		elif r < 0.73: return ENEMY_TYPE_TANK
		elif r < 0.87: return ENEMY_TYPE_SPLITTER
		else:          return ENEMY_TYPE_EXPLODER

func _edge_position() -> Vector2:
	var cam     := get_viewport().get_camera_2d()
	var cam_pos := cam.global_position if cam else Vector2.ZERO
	var vp      := get_viewport().get_visible_rect().size
	var hw      := vp.x * 0.5 + 90.0
	var hh      := vp.y * 0.5 + 90.0
	match randi() % 4:
		0: return cam_pos + Vector2(randf_range(-hw, hw), -hh)
		1: return cam_pos + Vector2(randf_range(-hw, hw),  hh)
		2: return cam_pos + Vector2(-hw, randf_range(-hh, hh))
		_: return cam_pos + Vector2( hw, randf_range(-hh, hh))
