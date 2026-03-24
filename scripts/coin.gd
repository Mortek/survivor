extends Area2D
## XP gem / coin dropped by enemies.
## Sits still, then shoots toward the player when within pickup radius.

@export var xp_value: int = 5

@onready var sprite: Sprite2D = $Sprite2D

const ATTRACT_SPEED := 240.0
const BOB_AMPLITUDE := 3.0
const BOB_SPEED     := 4.0

var _player: Node2D  = null
var _attracted: bool = false
var _age: float      = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if not sprite.texture:
		# Small circle gem — white so modulate controls color
		var size := 10
		var img  := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		var cx := (size - 1) * 0.5
		var r2 := (size * 0.5 - 0.5) * (size * 0.5 - 0.5)
		for y in size:
			for x in size:
				var dx := x - cx
				var dy := y - cx
				if dx * dx + dy * dy <= r2:
					img.set_pixel(x, y, Color.WHITE)
		sprite.texture = ImageTexture.create_from_image(img)

## Called right after instantiation
func setup(player: Node2D, value: int = 5) -> void:
	_player  = player
	xp_value = value
	# Color gem by value: green=small, cyan/blue=medium, gold=large
	if xp_value <= 10:
		sprite.modulate = Color(0.3, 1.0, 0.5)
	elif xp_value <= 30:
		sprite.modulate = Color(0.3, 0.7, 1.0)
	else:
		sprite.modulate = Color(1.0, 0.85, 0.2)

func _process(delta: float) -> void:
	_age += delta
	if not _player:
		return

	var dir_vec := _player.global_position - global_position
	var dist    := dir_vec.length()

	if _attracted or dist < GameManager.stats["pickup_radius"]:
		if not _attracted:
			_attracted = true
			var tw := sprite.create_tween()
			tw.tween_property(sprite, "scale", Vector2(1.6, 1.6), 0.07)
			tw.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.10)
		var dir := dir_vec / maxf(dist, 1.0)
		var speed_factor: float = lerpf(4.0, 1.0, clampf(dist / float(GameManager.stats["pickup_radius"]), 0.0, 1.0))
		global_position += dir * ATTRACT_SPEED * speed_factor * delta
	else:
		# Gentle bob in place
		sprite.position.y = sin(_age * BOB_SPEED) * BOB_AMPLITUDE

## Called by the magnet orb to instantly pull this coin to the player.
func attract_magnet() -> void:
	_attracted = true

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		GameManager.add_xp(xp_value)
		GameManager.add_coin(1)
		queue_free()
