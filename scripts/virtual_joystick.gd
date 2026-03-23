extends Control
## Virtual joystick – follow-touch style (base appears where you press).
## Emits direction_changed every frame the thumb is dragged.

signal direction_changed(direction: Vector2)

@export var joystick_radius: float = 65.0
@export var deadzone_ratio:  float = 0.12   # fraction of radius

@onready var base:  ColorRect = $Base
@onready var thumb: ColorRect = $Thumb

var _touch_index: int      = -1
var _base_center: Vector2  = Vector2.ZERO
var _direction:   Vector2  = Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # work even when game paused
	base.hide()
	thumb.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Claim only if no current touch and press is in left 60% of screen
		if _touch_index == -1 and event.position.x < get_viewport_rect().size.x * 0.60:
			_touch_index  = event.index
			_base_center  = event.position
			# Centre the ColorRects on the touch point
			base.position  = _base_center - base.size  * 0.5
			thumb.position = _base_center - thumb.size * 0.5
			base.show()
			thumb.show()
	else:
		if event.index == _touch_index:
			_release()

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _touch_index:
		return
	var offset  := event.position - _base_center
	var clamped := offset.limit_length(joystick_radius)
	thumb.position = _base_center + clamped - thumb.size * 0.5
	var deadzone := joystick_radius * deadzone_ratio
	_direction = offset.normalized() if offset.length() > deadzone else Vector2.ZERO
	direction_changed.emit(_direction)

func _release() -> void:
	_touch_index = -1
	_direction   = Vector2.ZERO
	base.hide()
	thumb.hide()
	direction_changed.emit(Vector2.ZERO)

func get_direction() -> Vector2:
	return _direction
