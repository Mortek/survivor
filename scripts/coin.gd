extends Area2D
## XP gem / coin dropped by enemies.
## Sits still, then shoots toward the player when within pickup radius.

@export var xp_value: int = 5

@onready var sprite: Sprite2D = $Sprite2D

const ATTRACT_SPEED := 240.0
const BOB_AMPLITUDE := 3.0
const BOB_SPEED     := 4.0

var _player: Node2D   = null
var _attracted: bool  = false
var _age: float       = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if not sprite.texture:
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 1.0, 0.5))
		sprite.texture = ImageTexture.create_from_image(img)

## Called right after instantiation
func setup(player: Node2D, value: int = 5) -> void:
	_player  = player
	xp_value = value

func _process(delta: float) -> void:
	_age += delta
	if not _player:
		return

	var dist := global_position.distance_to(_player.global_position)

	if _attracted or dist < GameManager.stats["pickup_radius"]:
		_attracted = true
		var dir := (_player.global_position - global_position).normalized()
		global_position += dir * ATTRACT_SPEED * delta
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
