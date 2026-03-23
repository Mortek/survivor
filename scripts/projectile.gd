extends Area2D
## Projectile – fired by the player.
## Moves linearly, damages the first enemy it hits, then returns to pool.

@onready var sprite:          Sprite2D = $Sprite2D
@onready var lifetime_timer:  Timer    = $LifetimeTimer

var _velocity: Vector2 = Vector2.ZERO
var _damage:   int     = 0
var _hit:      bool    = false   # guard against double-hit

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	lifetime_timer.timeout.connect(_on_lifetime_timeout)
	if not sprite.texture:
		var img := Image.create(14, 6, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 1.0, 1.0))
		sprite.texture = ImageTexture.create_from_image(img)

## Called by player._shoot() to initialize and fire
func launch(direction: Vector2, damage: int, speed: float) -> void:
	_damage   = damage
	_velocity = direction * speed
	_hit      = false
	rotation  = direction.angle()
	lifetime_timer.start(2.8)

func _process(delta: float) -> void:
	position += _velocity * delta

func _on_body_entered(body: Node) -> void:
	if _hit:
		return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		_hit = true
		body.take_damage(float(_damage))
		_return()

func _on_lifetime_timeout() -> void:
	_return()

func _return() -> void:
	_velocity = Vector2.ZERO
	_hit      = false
	lifetime_timer.stop()
	var pool := get_parent()
	if pool and pool.has_method("return_object"):
		pool.return_object(self)
	else:
		queue_free()
