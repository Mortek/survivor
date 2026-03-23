class_name Boomerang
extends Area2D
## Orbiting boomerang that damages every enemy it passes through.
## Multiple instances are spawned for the Death Orbit evolution.
## Added as a child of the Player node by player.gd.

const HIT_COOLDOWN := 0.45   # seconds between hits on the same enemy

var _angle:       float = 0.0
var _orbit_speed: float = 2.8    # radians / sec
var _orbit_radius: float = 90.0
var _dmg_mult:    float = 1.2
var _hit_cd:      Dictionary = {}   # enemy → remaining cooldown

func _ready() -> void:
	set_collision_layer(0)
	set_collision_mask(2)   # enemies
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	var coll := CollisionShape2D.new()
	coll.shape = shape
	add_child(coll)

func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_angle += _orbit_speed * delta
	position = Vector2(cos(_angle), sin(_angle)) * _orbit_radius
	rotation  = _angle
	queue_redraw()

	# Tick down hit cooldowns; remove dead/freed enemies immediately
	for enemy in _hit_cd.keys():
		if not is_instance_valid(enemy):
			_hit_cd.erase(enemy)
			continue
		_hit_cd[enemy] -= delta
		if _hit_cd[enemy] <= 0.0:
			_hit_cd.erase(enemy)

	# Damage overlapping enemies
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			if not _hit_cd.has(body):
				body.take_damage(GameManager.stats["damage"] * _dmg_mult)
				_hit_cd[body] = HIT_COOLDOWN

func _draw() -> void:
	draw_rect(Rect2(Vector2(-14.0, -5.0), Vector2(28.0, 10.0)), Color(1.0, 0.55, 0.1))

## Called from player.gd whenever boomerang_level changes.
func set_level(lvl: int) -> void:
	match lvl:
		2:
			_orbit_speed = 4.0
			_dmg_mult    = 1.8
		3:
			_orbit_speed  = 5.5
			_dmg_mult     = 2.5
			_orbit_radius = 115.0
		5:   # Death Orbit evolution
			_orbit_speed  = 7.0
			_dmg_mult     = 4.0
			_orbit_radius = 130.0
