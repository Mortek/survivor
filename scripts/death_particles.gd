class_name DeathParticles
extends Node2D
## Burst of coloured particles on enemy death. Directional when hit direction is given.

const COUNT    := 16
const DURATION := 1.4

var _rects: Array    = []
var _vels: Array     = []
var _lifetime: float = 0.0

## Call immediately after adding to scene.
func setup(base_color: Color, hit_dir: Vector2 = Vector2.ZERO) -> void:
	for i in COUNT:
		var r := ColorRect.new()
		var sz := randf_range(3.0, 9.0)
		r.size     = Vector2(sz, sz)
		r.color    = base_color.lightened(randf_range(0.0, 0.45))
		r.position = Vector2.ZERO
		add_child(r)
		_rects.append(r)
		# Bias particles in bullet travel direction (hit_dir = bullet direction)
		var angle: float
		if hit_dir.length() > 0.1:
			angle = hit_dir.angle() + randf_range(-PI * 0.375, PI * 0.375)
		else:
			angle = (TAU / COUNT) * i + randf_range(-0.4, 0.4)
		var spd := randf_range(80.0, 240.0)
		_vels.append(Vector2(cos(angle), sin(angle)) * spd)

func _process(delta: float) -> void:
	_lifetime += delta
	for i in _rects.size():
		_rects[i].position += _vels[i] * delta
		_vels[i] *= 0.82          # friction — slow down fast
	modulate.a = 1.0 - (_lifetime / DURATION)
	if _lifetime >= DURATION:
		queue_free()
