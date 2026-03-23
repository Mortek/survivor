extends Camera2D
## Camera with trauma-based screen shake.
## Call add_trauma(0.0-1.0) to trigger. Higher = stronger shake.

var trauma: float       = 0.0   # current shake intensity
var trauma_decay: float = 1.5   # how fast trauma fades per second
var max_offset: Vector2 = Vector2(14.0, 14.0)
var max_roll: float     = 0.06  # radians

func _process(delta: float) -> void:
	if trauma <= 0.0:
		offset   = Vector2.ZERO
		rotation = 0.0
		return

	trauma = maxf(trauma - trauma_decay * delta, 0.0)
	var shake := trauma * trauma   # square for smoother feel
	offset   = Vector2(
		max_offset.x * randf_range(-1.0, 1.0) * shake,
		max_offset.y * randf_range(-1.0, 1.0) * shake
	)
	rotation = max_roll * randf_range(-1.0, 1.0) * shake

func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)
