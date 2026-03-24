class_name DeathParticles
extends Node2D
## Burst of coloured particles on enemy death. Directional splash from bullet impact.

const COUNT    := 20
const DURATION := 1.0

var _rects: Array    = []
var _vels: Array     = []
var _lifetime: float = 0.0

## Call immediately after adding to scene.
func setup(base_color: Color, hit_dir: Vector2 = Vector2.ZERO) -> void:
	for i in COUNT:
		var r := ColorRect.new()
		var sz := randf_range(2.5, 8.0)
		r.size     = Vector2(sz, sz)
		r.pivot_offset = Vector2(sz, sz) * 0.5
		r.rotation = randf() * TAU
		r.color    = base_color.lightened(randf_range(0.0, 0.55))
		r.position = Vector2.ZERO
		add_child(r)
		_rects.append(r)
		var angle: float
		if hit_dir.length() > 0.1:
			angle = hit_dir.angle() + randf_range(-PI * 0.45, PI * 0.45)
		else:
			angle = (TAU / COUNT) * i + randf_range(-0.5, 0.5)
		var spd := randf_range(120.0, 360.0)
		_vels.append(Vector2(cos(angle), sin(angle)) * spd)

func _process(delta: float) -> void:
	_lifetime += delta
	var t := _lifetime / DURATION
	var shrink_vec := Vector2.ONE * maxf(1.0 - t * 0.6, 0.2)
	for i in _rects.size():
		_rects[i].position += _vels[i] * delta
		_vels[i] *= (1.0 - 3.0 * delta)
		_rects[i].scale = shrink_vec
	modulate.a = 1.0 - t * t
	if _lifetime >= DURATION:
		queue_free()
