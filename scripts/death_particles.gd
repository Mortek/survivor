class_name DeathParticles
extends Node2D
## Burst of coloured squares when an enemy dies. Fully code-generated.

const COUNT    := 10
const DURATION := 0.55

var _rects: Array    = []
var _vels: Array     = []
var _lifetime: float = 0.0

## Call immediately after adding to scene.
func setup(base_color: Color) -> void:
	for i in COUNT:
		var r := ColorRect.new()
		var sz := randf_range(4.0, 9.0)
		r.size     = Vector2(sz, sz)
		r.color    = base_color.lightened(randf_range(0.0, 0.4))
		r.position = Vector2.ZERO
		add_child(r)
		_rects.append(r)
		var angle := (TAU / COUNT) * i + randf_range(-0.35, 0.35)
		var spd   := randf_range(55.0, 155.0)
		_vels.append(Vector2(cos(angle), sin(angle)) * spd)

func _process(delta: float) -> void:
	_lifetime += delta
	for i in _rects.size():
		_rects[i].position += _vels[i] * delta
		_vels[i] *= 0.87          # friction
	modulate.a = 1.0 - (_lifetime / DURATION)
	if _lifetime >= DURATION:
		queue_free()
