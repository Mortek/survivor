class_name MeleeWeapon
extends Area2D
## Melee sweep – damages all enemies in a circle around the player periodically.
## Added as a child of the Player node by player.gd when the upgrade is taken.

var _cooldown: float  = 1.2
var _timer: float     = 0.0
var _radius: float    = 80.0
var _dmg_mult: float  = 1.5
var _is_crimson: bool = false   # Crimson Reaper evolution flag
var _coll_shape: CircleShape2D = null

func _ready() -> void:
	set_collision_layer(0)
	set_collision_mask(2)          # enemies layer
	_coll_shape = CircleShape2D.new()
	_coll_shape.radius = _radius
	var coll := CollisionShape2D.new()
	coll.shape = _coll_shape
	add_child(coll)

func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_timer += delta
	queue_redraw()
	if _timer >= _cooldown:
		_timer = 0.0
		_sweep()

func _draw() -> void:
	var pulse := 0.07 + 0.10 * sin((_timer / _cooldown) * TAU)
	var color := Color(0.95, 0.3, 0.3, pulse) if _is_crimson else Color(1.0, 0.85, 0.2, pulse)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 36, color, 2.5)

func _sweep() -> void:
	var player := get_parent()
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			var dmg := float(GameManager.stats["damage"]) * _dmg_mult
			body.take_damage(dmg)
			# Crimson Reaper: heal player on each hit
			if _is_crimson and player and player.has_method("heal"):
				player.heal(int(dmg * 0.12))

## Called from player.gd whenever melee_level stat changes.
func set_level(lvl: int) -> void:
	match lvl:
		2:
			_dmg_mult = 2.2
			_cooldown = 0.95
		3:
			_dmg_mult = 3.0
			_cooldown = 0.75
			_radius   = 105.0
			if _coll_shape:
				_coll_shape.radius = _radius
		4:   # Crimson Reaper evolution
			_is_crimson = true
			_dmg_mult   = 5.0
			_cooldown   = 0.60
			_radius     = 130.0
			if _coll_shape:
				_coll_shape.radius = _radius
