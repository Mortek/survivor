extends CharacterBody2D
## Player – centered on screen, moves via virtual joystick, auto-attacks.

# ── Signals ───────────────────────────────────────────────────────────────────
signal health_changed(current_hp: int, max_hp: int)
signal player_died

# ── Node References ───────────────────────────────────────────────────────────
@onready var sprite:        Sprite2D  = $Sprite2D
@onready var attack_timer:  Timer     = $AttackTimer
@onready var iframes_timer: Timer     = $IFramesTimer

# ── Injected by game.gd ───────────────────────────────────────────────────────
var projectile_pool: ObjectPool = null
var camera:          Camera2D   = null   # must support add_trauma()

# ── Runtime State ─────────────────────────────────────────────────────────────
var current_hp: int    = 0
var is_invincible: bool = false
var move_dir: Vector2  = Vector2.ZERO

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("player")
	current_hp = GameManager.stats["max_health"]
	health_changed.emit(current_hp, GameManager.stats["max_health"])
	# Wire timers (done in code so scene files stay clean)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	iframes_timer.timeout.connect(_on_i_frames_timer_timeout)
	_reset_attack_timer()
	GameManager.stats_changed.connect(_on_stats_changed)
	# Placeholder sprite – replaced when real art is imported
	if not sprite.texture:
		sprite.texture = _solid_tex(32, 32, Color(0.27, 0.47, 1.0))

# ── Movement ──────────────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		velocity = Vector2.ZERO
		return
	# Joystick takes priority; fall back to WASD / arrow keys on desktop
	var final_dir: Vector2 = move_dir if move_dir.length() > 0.1 else _keyboard_dir()
	velocity = final_dir * float(GameManager.stats["speed"])
	move_and_slide()
	if final_dir.length() > 0.1:
		sprite.flip_h = final_dir.x < 0.0

func _keyboard_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    d.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  d.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  d.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): d.x += 1.0
	return d.normalized() if d.length() > 0.0 else Vector2.ZERO

## Called every frame by VirtualJoystick via signal
func set_move_direction(dir: Vector2) -> void:
	move_dir = dir

# ── Combat ────────────────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if is_invincible or GameManager.state != GameManager.State.PLAYING:
		return
	current_hp = maxi(current_hp - amount, 0)
	health_changed.emit(current_hp, GameManager.stats["max_health"])
	_flash(Color(1.0, 0.2, 0.2))
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(0.4)
	is_invincible = true
	iframes_timer.start(0.6)
	if current_hp <= 0:
		player_died.emit()
		GameManager.trigger_game_over()

func heal(amount: int) -> void:
	current_hp = mini(current_hp + amount, GameManager.stats["max_health"])
	health_changed.emit(current_hp, GameManager.stats["max_health"])

## Flash sprite a given color then return to white
func _flash(color: Color) -> void:
	sprite.modulate = color
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE

# ── Auto-Attack ───────────────────────────────────────────────────────────────
func _on_attack_timer_timeout() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_shoot()
	_reset_attack_timer()   # re-read attack_speed in case it changed

func _reset_attack_timer() -> void:
	attack_timer.wait_time = 1.0 / maxf(GameManager.stats["attack_speed"], 0.1)
	attack_timer.start()

func _shoot() -> void:
	if not projectile_pool:
		return
	var targets := _nearest_enemies(GameManager.stats["projectile_count"])
	for target in targets:
		var proj: Node = projectile_pool.get_object()
		if not proj:
			continue
		proj.global_position = global_position
		var dir: Vector2 = (target.global_position - global_position).normalized()
		proj.launch(dir, GameManager.stats["damage"], GameManager.stats["projectile_speed"])

func _nearest_enemies(count: int) -> Array:
	var enemies := get_tree().get_nodes_in_group("enemies")
	enemies.sort_custom(func(a: Node, b: Node) -> bool:
		return global_position.distance_squared_to(a.global_position) \
		     < global_position.distance_squared_to(b.global_position)
	)
	return enemies.slice(0, mini(count, enemies.size()))

# ── Callbacks ─────────────────────────────────────────────────────────────────
func _on_i_frames_timer_timeout() -> void:
	is_invincible = false

func _on_stats_changed() -> void:
	## After an upgrade, clamp HP to new max and refresh UI
	current_hp = mini(current_hp, GameManager.stats["max_health"])
	health_changed.emit(current_hp, GameManager.stats["max_health"])

static func _solid_tex(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
