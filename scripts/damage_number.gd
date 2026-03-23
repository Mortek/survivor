class_name DamageNumber
extends Node2D
## Floating damage number that rises and fades — spawned on every hit.

const DURATION := 0.75

var _label: Label
var _vel: Vector2
var _lifetime: float = 0.0

func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-20, -12)
	_label.custom_minimum_size = Vector2(40, 0)
	add_child(_label)
	_vel = Vector2(randf_range(-18.0, 18.0), -85.0)

## Call immediately after adding to scene.
func setup(amount: int, crit: bool = false) -> void:
	_label.text = str(amount)
	if crit:
		_label.modulate = Color(1.0, 0.9, 0.1)
		_label.add_theme_font_size_override("font_size", 26)
	else:
		_label.modulate = Color(1.0, 0.35, 0.35)

func _process(delta: float) -> void:
	_lifetime += delta
	position += _vel * delta
	_vel.y += 70.0 * delta          # gravity / deceleration
	modulate.a = 1.0 - (_lifetime / DURATION)
	if _lifetime >= DURATION:
		queue_free()
