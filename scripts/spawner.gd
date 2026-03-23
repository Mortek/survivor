extends Node
## Spawner – instantiates enemies on a timer, scaling with waves.
## Waves advance every `wave_duration` seconds; each wave increases spawn rate + difficulty.

# ── Signals ───────────────────────────────────────────────────────────────────
signal enemy_spawned(enemy: Node)   # game.gd connects per-enemy signals here

# ── Config ────────────────────────────────────────────────────────────────────
@export var enemy_scene: PackedScene
@export var wave_duration: float       = 22.0
@export var base_spawn_interval: float = 1.5
@export var max_on_screen: int         = 45

# ── State ─────────────────────────────────────────────────────────────────────
var _player: Node2D  = null
var _container: Node = null
var _spawn_timer: float = 0.0
var _wave_timer:  float = 0.0
var _spawn_interval: float

func _ready() -> void:
	_spawn_interval = base_spawn_interval

## Call from game.gd after scene is ready
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
	# Increase spawn frequency, minimum 0.3s between spawns
	_spawn_interval = maxf(base_spawn_interval / (1.0 + GameManager.wave * 0.12), 0.30)
	# Burst spawn to feel the wave pressure
	for _i in 6:
		_try_spawn()

# ── Spawning ──────────────────────────────────────────────────────────────────
func _try_spawn() -> void:
	if not _player or not _container or not enemy_scene:
		return
	if get_tree().get_nodes_in_group("enemies").size() >= max_on_screen:
		return

	var enemy: Node = enemy_scene.instantiate()
	# Set type BEFORE add_child so _ready() → _apply_config() uses the correct type
	enemy.enemy_type = _pick_type()
	_container.add_child(enemy)
	enemy.global_position = _edge_position()
	enemy.activate(_player, GameManager.get_wave_multiplier())
	# Emit so game.gd can connect the enemy's died signal for coin drops
	enemy_spawned.emit(enemy)

func _pick_type() -> int:
	var w := GameManager.wave
	var r := randf()
	if w <= 2:
		return 0                                   # BASIC only
	elif w <= 5:
		return 0 if r < 0.72 else 1               # mostly BASIC, some FAST
	else:
		if   r < 0.48: return 0                   # BASIC
		elif r < 0.78: return 1                   # FAST
		else:          return 2                   # TANK

func _edge_position() -> Vector2:
	## Spawn just outside the current viewport edges.
	var cam := get_viewport().get_camera_2d()
	var cam_pos := cam.global_position if cam else Vector2.ZERO
	var vp     := get_viewport().get_visible_rect().size
	var hw     := vp.x * 0.5 + 90.0
	var hh     := vp.y * 0.5 + 90.0

	match randi() % 4:
		0: return cam_pos + Vector2(randf_range(-hw, hw), -hh)   # top
		1: return cam_pos + Vector2(randf_range(-hw, hw),  hh)   # bottom
		2: return cam_pos + Vector2(-hw, randf_range(-hh, hh))   # left
		_: return cam_pos + Vector2( hw, randf_range(-hh, hh))   # right
