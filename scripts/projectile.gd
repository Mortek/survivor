extends Area2D
## Projectile – fired by the player.
## Supports: pierce, crit, knockback, slow-on-hit, burn-on-hit.

@onready var sprite:         Sprite2D = $Sprite2D
@onready var lifetime_timer: Timer    = $LifetimeTimer

var _velocity:          Vector2 = Vector2.ZERO
var _damage:            int     = 0
var _pierce_remaining:  int     = 0
var _knockback:         float   = 0.0
var _slow_on_hit:       bool    = false
var _burn_on_hit:       bool    = false
var _crit_chance:       float   = 0.0
var _hit_enemies:       Array   = []  # track per-shot hits for pierce

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	lifetime_timer.timeout.connect(_on_lifetime_timeout)
	if not sprite.texture:
		# Epic glowing projectile with radiant core, layered energy, and blazing glow
		var pw := 20
		var ph := 10
		var img := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		var cx_f := (pw - 1) * 0.5
		var cy_f := (ph - 1) * 0.5
		for py in ph:
			for px in pw:
				var nx := absf(float(px) - cx_f) / (cx_f + 0.001)
				var ny := absf(float(py) - cy_f) / (cy_f + 0.001)
				# Front-weighted elongated ellipse — brighter tip
				var front_bias := 0.25 if float(px) < cx_f else 0.55
				var d  := nx * nx * front_bias + ny * ny
				if d <= 1.0:
					var intensity := 1.0 - d
					var i2 := intensity * intensity
					var i3 := i2 * intensity
					# 4-layer color: white-hot core → cyan → electric blue → blue edge
					var r := lerpf(0.1, 1.0, i3)
					var g := lerpf(0.55, 1.0, i2)
					var b := 1.0
					var a := clampf(i2 + 0.25, 0.0, 1.0)
					img.set_pixel(px, py, Color(r, g, b, a))
				elif d <= 1.35:
					# Inner glow ring
					var glow := (1.35 - d) / 0.35
					img.set_pixel(px, py, Color(0.4, 0.8, 1.0, glow * glow * 0.5))
				elif d <= 2.0:
					# Wide outer bloom halo
					var bloom := (2.0 - d) / 0.65
					img.set_pixel(px, py, Color(0.2, 0.5, 1.0, bloom * bloom * 0.18))
		sprite.texture = ImageTexture.create_from_image(img)
		sprite.scale   = Vector2(1.4, 1.4)

func launch(direction: Vector2, damage: int, speed: float) -> void:
	_damage           = damage
	_velocity         = direction * speed
	_hit_enemies.clear()
	_pierce_remaining = GameManager.stats.get("pierce", 0)
	_knockback        = float(GameManager.stats.get("knockback", 0.0))
	_slow_on_hit      = GameManager.stats.get("slow_on_hit", false)
	_burn_on_hit      = GameManager.stats.get("burn_on_hit", false)
	_crit_chance      = float(GameManager.stats.get("crit_chance", 0.0))
	rotation          = direction.angle()
	lifetime_timer.start(2.8)

func _process(delta: float) -> void:
	position += _velocity * delta

func _on_body_entered(body: Node) -> void:
	if body in _hit_enemies:
		return
	if not (body.is_in_group("enemies") and body.has_method("take_damage")):
		return
	_hit_enemies.append(body)

	var dmg := float(_damage)
	var is_crit := _crit_chance > 0.0 and randf() < _crit_chance
	if is_crit:
		dmg *= 2.0
		GameManager.add_crit()

	body.take_damage(dmg, _velocity.normalized())

	if _knockback > 0.0 and body.has_method("apply_knockback"):
		body.apply_knockback(_velocity.normalized() * _knockback)
	if _slow_on_hit and body.has_method("apply_slow"):
		body.apply_slow(0.4, 2.0)
	if _burn_on_hit and body.has_method("apply_burn"):
		body.apply_burn(3.0, 3.0)

	if _pierce_remaining > 0:
		_pierce_remaining -= 1
	else:
		_return()

func _on_lifetime_timeout() -> void:
	_return()

func _return() -> void:
	_velocity = Vector2.ZERO
	_hit_enemies.clear()
	lifetime_timer.stop()
	var pool := get_parent()
	if pool and pool.has_method("return_object"):
		pool.return_object(self)
	else:
		queue_free()
