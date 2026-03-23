extends CharacterBody2D
## Player – centered on screen, moves via virtual joystick, auto-attacks.
## Manages secondary weapons (MeleeWeapon, Boomerang, LightningChain) as children.

# ── Signals ───────────────────────────────────────────────────────────────────
signal health_changed(current_hp: int, max_hp: int)
signal player_died
signal shield_broken   # emitted when a shield charge absorbs a hit

# ── Node References ───────────────────────────────────────────────────────────
@onready var sprite:        Sprite2D  = $Sprite2D
@onready var attack_timer:  Timer     = $AttackTimer
@onready var iframes_timer: Timer     = $IFramesTimer

# ── Injected by game.gd ───────────────────────────────────────────────────────
var projectile_pool: ObjectPool = null
var camera:          Camera2D   = null

# ── Runtime State ─────────────────────────────────────────────────────────────
var current_hp:    int    = 0
var is_invincible: bool   = false
var move_dir:      Vector2 = Vector2.ZERO

# ── Secondary weapons ─────────────────────────────────────────────────────────
var _melee:      MeleeWeapon   = null
var _boomerangs: Array         = []
var _lightning:  LightningChain = null

# ── Regen & aura accumulators ─────────────────────────────────────────────────
var _regen_acc: float = 0.0
var _aura_acc:  float = 0.0
const AURA_INTERVAL := 0.8
const AURA_RADIUS   := 100.0
const AURA_DMG_MULT := 0.4   # fraction of player damage

# ── Cached stats (updated on stats_changed to avoid per-frame dict lookups) ───
var _cached_speed:       float = 150.0
var _cached_regen:       float = 0.0
var _cached_synergy_aura: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("player")
	current_hp = GameManager.stats["max_health"]
	health_changed.emit(current_hp, GameManager.stats["max_health"])
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	iframes_timer.timeout.connect(_on_i_frames_timer_timeout)
	_reset_attack_timer()
	GameManager.stats_changed.connect(_on_stats_changed)
	_cache_stats()
	if not sprite.texture:
		sprite.texture = _solid_tex(32, 32, Color(0.27, 0.47, 1.0))

# ── Movement ──────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		velocity = Vector2.ZERO
		return
	var final_dir: Vector2 = move_dir if move_dir.length() > 0.1 else _keyboard_dir()
	velocity = final_dir * _cached_speed
	move_and_slide()
	if final_dir.length() > 0.1:
		sprite.flip_h = final_dir.x < 0.0

	if _cached_regen > 0.0:
		_regen_acc += delta
		if _regen_acc >= 1.0:
			_regen_acc -= 1.0
			heal(int(_cached_regen))

	if _cached_synergy_aura:
		_aura_acc += delta
		if _aura_acc >= AURA_INTERVAL:
			_aura_acc -= AURA_INTERVAL
			_pulse_aura()

func _keyboard_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    d.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  d.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  d.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): d.x += 1.0
	return d.normalized() if d.length() > 0.0 else Vector2.ZERO

func set_move_direction(dir: Vector2) -> void:
	move_dir = dir

# ── Combat ────────────────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if is_invincible or GameManager.state != GameManager.State.PLAYING:
		return

	# Shield charges absorb the hit entirely
	var shields := int(GameManager.stats.get("shield_charges", 0))
	if shields > 0:
		GameManager.stats["shield_charges"] = shields - 1
		shield_broken.emit()
		_flash(Color(0.3, 0.8, 1.0))
		if camera and camera.has_method("add_trauma"):
			camera.add_trauma(0.2)
		is_invincible = true
		iframes_timer.start(0.4)
		return

	# Apply flat armor reduction
	var reduced := maxi(amount - int(GameManager.stats.get("armor", 0)), 1)
	current_hp = maxi(current_hp - reduced, 0)
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

func on_kill() -> void:
	var ls := float(GameManager.stats.get("lifesteal", 0.0))
	if ls > 0.0:
		heal(int(ls))

func _flash(color: Color) -> void:
	sprite.modulate = color
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE

# ── Synergy Aura ──────────────────────────────────────────────────────────────
func _pulse_aura() -> void:
	var dmg := float(GameManager.stats["damage"]) * AURA_DMG_MULT
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_squared_to((enemy as Node2D).global_position) <= AURA_RADIUS * AURA_RADIUS:
			enemy.take_damage(dmg)
	# Visual ring flash
	_draw_aura_ring()

func _draw_aura_ring() -> void:
	var ring := Node2D.new()
	ring.global_position = global_position
	ring.z_index = 3
	get_tree().current_scene.add_child(ring)
	var progress := 0.0
	ring.set_meta("progress", progress)
	ring.connect("draw", func() -> void:
		var p: float = ring.get_meta("progress", 0.0)
		var alpha    := (1.0 - p) * 0.7
		ring.draw_arc(Vector2.ZERO, AURA_RADIUS * (0.5 + p * 0.5), 0.0, TAU, 32,
			Color(0.8, 0.4, 1.0, alpha), 3.0)
	)
	var tw := ring.create_tween()
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(ring):
			ring.set_meta("progress", v)
			ring.queue_redraw()
		, 0.0, 1.0, 0.5)
	tw.tween_callback(ring.queue_free)

# ── Auto-Attack ───────────────────────────────────────────────────────────────
func _on_attack_timer_timeout() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_shoot()
	_reset_attack_timer()

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

# ── Secondary Weapon Management ───────────────────────────────────────────────
func _check_weapons() -> void:
	# ── Melee ──────────────────────────────────────────────────────────────────
	if GameManager.stats.get("melee_enabled", false):
		if not _melee:
			_melee = MeleeWeapon.new()
			add_child(_melee)
		var melee_lvl := int(GameManager.stats.get("melee_level", 1))
		if GameManager.stats.get("crimson_reaper", false):
			melee_lvl = 4
		_melee.set_level(melee_lvl)

	# ── Boomerang(s) ───────────────────────────────────────────────────────────
	if GameManager.stats.get("boomerang_enabled", false):
		var target_count := 3 if GameManager.stats.get("death_orbit", false) else 1
		while _boomerangs.size() < target_count:
			var b := Boomerang.new()
			b._angle = (TAU / target_count) * _boomerangs.size()
			add_child(b)
			_boomerangs.append(b)
		var boom_lvl := int(GameManager.stats.get("boomerang_level", 1))
		if GameManager.stats.get("death_orbit", false):
			boom_lvl = 5
		for b in _boomerangs:
			b.set_level(boom_lvl)

	# ── Lightning Chain ─────────────────────────────────────────────────────────
	if GameManager.stats.get("lightning_enabled", false):
		if not _lightning:
			_lightning = LightningChain.new()
			add_child(_lightning)
		var chain_lvl := int(GameManager.stats.get("lightning_level", 1))
		if GameManager.stats.get("thunder_god", false):
			chain_lvl = 5
		_lightning.set_level(chain_lvl)

# ── Callbacks ─────────────────────────────────────────────────────────────────
func _on_i_frames_timer_timeout() -> void:
	is_invincible = false

func _cache_stats() -> void:
	_cached_speed        = float(GameManager.stats["speed"])
	_cached_regen        = float(GameManager.stats.get("regen", 0.0))
	_cached_synergy_aura = GameManager.stats.get("synergy_aura", false)

func _on_stats_changed() -> void:
	current_hp = mini(current_hp, GameManager.stats["max_health"])
	health_changed.emit(current_hp, GameManager.stats["max_health"])
	_cache_stats()
	_check_weapons()
	_reset_attack_timer()

static func _solid_tex(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
