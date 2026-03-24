extends CharacterBody2D
## Player – centered on screen, moves via virtual joystick, auto-attacks.
## Manages secondary weapons (LightningChain) as children.

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
var _lightning:  LightningChain = null

# ── Regen & aura accumulators ─────────────────────────────────────────────────
var _regen_acc: float = 0.0
var _aura_acc:  float = 0.0
const AURA_INTERVAL := 0.8

# ── Dash ──────────────────────────────────────────────────────────────────────
var _dash_cooldown_remaining: float = 0.0
var _dashing:                 bool  = false
var _dash_dir:                Vector2 = Vector2.ZERO
var _dash_elapsed:            float = 0.0
const DASH_DURATION    := 0.18
const DASH_SPEED_MULT  := 3.5
const DASH_COOLDOWN    := 2.5
signal dash_ready(ready: bool)
const AURA_RADIUS   := 100.0
const AURA_DMG_MULT := 0.4   # fraction of player damage

# ── Battle Cry ────────────────────────────────────────────────────────────────
var _battle_cry_timer: float = 0.0
const BATTLE_CRY_DURATION    := 3.0
const BATTLE_CRY_SPEED_BONUS := 30.0

# ── Cached stats (updated on stats_changed to avoid per-frame dict lookups) ───
var _cached_speed:           float = 150.0
var _cached_regen:           float = 0.0
var _cached_synergy_aura:    bool  = false
var _cached_elite_dmg_bonus: float = 0.0

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
		sprite.texture = _warrior_tex(48)
		sprite.modulate = _BASE_COLOR
	# Animated energy aura around the player
	_start_energy_aura()
	GameManager.level_changed.connect(func(_l: int) -> void: Input.vibrate_handheld(60))
	GameManager.level_changed.connect(func(_l: int) -> void: _levelup_ring())

# ── Movement ──────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		velocity = Vector2.ZERO
		return
	var final_dir: Vector2 = move_dir if move_dir.length() > 0.1 else _keyboard_dir()

	# Battle cry timer
	if _battle_cry_timer > 0.0:
		_battle_cry_timer -= delta

	# Dash cooldown
	if _dash_cooldown_remaining > 0.0:
		_dash_cooldown_remaining -= delta
		if _dash_cooldown_remaining <= 0.0:
			dash_ready.emit(true)

	# Dash movement
	if _dashing:
		_dash_elapsed += delta
		velocity = _dash_dir * _cached_speed * DASH_SPEED_MULT
		if _dash_elapsed >= DASH_DURATION:
			_dashing = false
	else:
		var cry_bonus := BATTLE_CRY_SPEED_BONUS if _battle_cry_timer > 0.0 else 0.0
		velocity = final_dir * (_cached_speed + cry_bonus)
	move_and_slide()
	if final_dir.length() > 0.1 and not _dashing:
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

func try_dash() -> void:
	if not GameManager.stats.get("dash_enabled", false):
		return
	if _dash_cooldown_remaining > 0.0:
		return
	var dir: Vector2 = move_dir if move_dir.length() > 0.1 else _keyboard_dir()
	if dir.length() < 0.1:
		return
	_dashing               = true
	_dash_dir              = dir.normalized()
	_dash_elapsed          = 0.0
	_dash_cooldown_remaining = DASH_COOLDOWN
	is_invincible          = true
	iframes_timer.start(DASH_DURATION + 0.05)
	dash_ready.emit(false)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_any("dash")
	Input.vibrate_handheld(40)

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

	# Apply flat armor reduction, then percentage reduction
	var reduced := maxi(amount - int(GameManager.stats.get("armor", 0)), 1)
	var dr: float = GameManager.stats.get("dmg_reduction", 0.0)
	if dr > 0.0:
		reduced = maxi(int(float(reduced) * (1.0 - dr)), 1)
	current_hp = maxi(current_hp - reduced, 0)
	health_changed.emit(current_hp, GameManager.stats["max_health"])
	_flash(Color(1.0, 0.2, 0.2))
	Input.vibrate_handheld(80)
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
	if GameManager.stats.get("battle_cry", false):
		_battle_cry_timer = BATTLE_CRY_DURATION

const _BASE_COLOR := Color(0.35, 0.6, 1.0)

func _flash(color: Color) -> void:
	sprite.modulate = color
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(sprite):
		sprite.modulate = _BASE_COLOR

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
		var dmg: int = int(GameManager.stats["damage"])
		if GameManager.stats.get("berserk_threshold", 0.0) > 0.0:
			if float(current_hp) / float(GameManager.stats["max_health"]) < GameManager.stats["berserk_threshold"]:
				dmg = int(float(dmg) * 1.6)
		if _cached_elite_dmg_bonus > 0.0:
			var t := target as Enemy
			if t and t.is_elite:
				dmg = int(float(dmg) * (1.0 + _cached_elite_dmg_bonus))
		proj.launch(dir, dmg, GameManager.stats["projectile_speed"])

func _nearest_enemies(count: int) -> Array:
	var enemies := get_tree().get_nodes_in_group("enemies")
	enemies.sort_custom(func(a: Node, b: Node) -> bool:
		return global_position.distance_squared_to(a.global_position) \
		     < global_position.distance_squared_to(b.global_position)
	)
	return enemies.slice(0, mini(count, enemies.size()))

# ── Secondary Weapon Management ───────────────────────────────────────────────
func _check_weapons() -> void:
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
	_cached_speed            = float(GameManager.stats["speed"])
	_cached_regen            = float(GameManager.stats.get("regen", 0.0))
	_cached_synergy_aura     = GameManager.stats.get("synergy_aura", false)
	_cached_elite_dmg_bonus  = float(GameManager.stats.get("elite_dmg_bonus", 0.0))

func _on_stats_changed() -> void:
	current_hp = mini(current_hp, GameManager.stats["max_health"])
	health_changed.emit(current_hp, GameManager.stats["max_health"])
	_cache_stats()
	_check_weapons()
	_reset_attack_timer()

func _levelup_ring() -> void:
	var ring := Node2D.new()
	ring.global_position = global_position
	ring.z_index = 4
	get_tree().current_scene.add_child(ring)
	ring.connect("draw", func() -> void:
		var p: float = ring.get_meta("progress", 0.0)
		var alpha := (1.0 - p) * 0.85
		var radius := 18.0 + p * 55.0
		ring.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(1.0, 1.0, 0.55, alpha), 4.0)
	)
	var tw := ring.create_tween()
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(ring):
			ring.set_meta("progress", v)
			ring.queue_redraw()
	, 0.0, 1.0, 0.55)
	tw.tween_callback(ring.queue_free)

var _aura_ring: Node2D = null
func _start_energy_aura() -> void:
	_aura_ring = Node2D.new()
	_aura_ring.z_index = -1
	add_child(_aura_ring)
	_aura_ring.set_meta("phase", 0.0)
	_aura_ring.connect("draw", func() -> void:
		var p: float = _aura_ring.get_meta("phase", 0.0)
		# Outer pulsing halo
		var r1 := 16.0 + sin(p * 3.0) * 3.0
		var a1 := 0.15 + sin(p * 2.0) * 0.05
		_aura_ring.draw_arc(Vector2.ZERO, r1, 0.0, TAU, 24,
			Color(0.4, 0.7, 1.0, a1), 2.0)
		# Inner bright ring
		var r2 := 11.0 + sin(p * 4.5 + 1.0) * 2.0
		_aura_ring.draw_arc(Vector2.ZERO, r2, 0.0, TAU, 20,
			Color(0.6, 0.85, 1.0, a1 + 0.05), 1.5)
	)
	# Animate phase continuously
	var tw := _aura_ring.create_tween()
	tw.set_loops()
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(_aura_ring):
			_aura_ring.set_meta("phase", v)
			_aura_ring.queue_redraw()
	, 0.0, TAU, 2.0)

static func _warrior_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r_body := size * 0.38
	# Pass 0: wide outer energy aura glow
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r_body * 1.05 and d <= r_body * 1.35:
				var glow := 1.0 - (d - r_body * 1.05) / (r_body * 0.30)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, glow * 0.2))
	# Pass 1: armored octagonal torso with layered energy
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var angle := atan2(dy, dx)
			var sector := fmod(absf(angle) + PI / 8.0, PI / 4.0) - PI / 8.0
			var oct_r  := r_body / cos(sector) * cos(PI / 8.0)
			var d := sqrt(dx * dx + dy * dy)
			if d <= oct_r * 0.90:
				var norm_d := d / oct_r
				var intensity := 1.0 - norm_d * 0.4
				# Radial energy streaks
				var streak := absf(sin(angle * 4.0)) * 0.12 * (1.0 - norm_d)
				# Concentric energy rings
				var ring := absf(sin(norm_d * PI * 3.5)) * 0.06
				intensity += streak + ring
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			elif d <= oct_r:
				# Bright armor rim with bevel
				var rim_t := (d - oct_r * 0.90) / (oct_r * 0.10)
				var i := 0.85 + rim_t * 0.15
				img.set_pixel(x, y, Color(i, i, i, 1.0))
			elif d <= oct_r * 1.05:
				var glow := 1.0 - (d - oct_r) / (oct_r * 0.05)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, glow * 0.45))
	# Helmet: larger with crest and visor
	var head_r := size * 0.20
	var head_cy := cy - size * 0.30
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - head_cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= head_r:
				var norm_d := d / head_r
				var intensity := 1.0 - norm_d * 0.15
				# Subtle face plate shading
				var shade := -dy / head_r * 0.08
				intensity += shade
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
			elif d <= head_r + 2.0:
				var fade := 1.0 - (d - head_r) / 2.0
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.4))
	# Helmet crest — taller spike
	for dy in range(-6, 0):
		var py := int(head_cy - head_r) + dy
		var half_w := maxf(1.0 + float(dy + 6) * 0.25, 0.5)
		for ddx in range(int(-half_w), int(half_w) + 1):
			var px := int(cx) + ddx
			if px >= 0 and px < size and py >= 0 and py < size:
				var ci := 1.0 - float(absf(ddx)) / (half_w + 0.001) * 0.2
				img.set_pixel(px, py, Color(ci, ci, ci, 0.95))
	# Visor: glowing eyes
	var visor_y := int(head_cy + 1)
	for side_offset: int in [-3, 3]:
		var eye_x: int = int(cx) + side_offset
		for edy in range(-1, 2):
			for edx in range(-1, 2):
				var px: int = eye_x + edx
				var py: int = visor_y + edy
				if px >= 0 and px < size and py >= 0 and py < size:
					var ed := sqrt(float(edx * edx + edy * edy))
					if ed <= 1.5:
						img.set_pixel(px, py, Color(0.08, 0.08, 0.08, 1.0))
	# Eye glow (bright dots at center of each eye)
	for side_offset: int in [-3, 3]:
		var ex := int(cx) + side_offset
		if ex >= 0 and ex < size and visor_y >= 0 and visor_y < size:
			img.set_pixel(ex, visor_y, Color(0.7, 0.7, 0.7, 1.0))
	# Shoulder pauldrons with spike accents
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		var shoulder_cx := cx + side * (r_body * 0.82)
		var shoulder_cy := cy - size * 0.08
		var shoulder_r := size * 0.13
		for y in size:
			for x in size:
				var dx := float(x) - shoulder_cx
				var dy := float(y) - shoulder_cy
				var d := sqrt(dx * dx + dy * dy)
				if d <= shoulder_r:
					var si := 1.0 - (d / shoulder_r) * 0.20
					img.set_pixel(x, y, Color(si, si, si, 1.0))
				elif d <= shoulder_r + 1.5:
					var fade := 1.0 - (d - shoulder_r) / 1.5
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.3))
		# Double spikes on each shoulder
		for spike_off in [0.0, 3.0]:
			var spike_x := int(shoulder_cx + side * (2.0 + spike_off * 0.3))
			for sy in range(int(shoulder_cy - shoulder_r - 4 + int(spike_off)), int(shoulder_cy - shoulder_r)):
				if spike_x >= 0 and spike_x < size and sy >= 0 and sy < size:
					img.set_pixel(spike_x, sy, Color(1.0, 1.0, 1.0, 0.85))
	# Glowing chest emblem (diamond with energy core)
	var emblem_y := int(cy - 1)
	for dy in range(-4, 5):
		for ddx in range(-4, 5):
			if absf(ddx) + absf(dy) <= 4:
				var px := int(cx) + ddx
				var py := emblem_y + dy
				if px >= 0 and px < size and py >= 0 and py < size:
					var ed := float(absf(ddx) + absf(dy)) / 4.0
					var ei := 1.0 - ed * 0.25
					img.set_pixel(px, py, Color(ei, ei, ei, 1.0))
	# Emblem bright core
	for dy in range(-1, 2):
		for ddx in range(-1, 2):
			var px := int(cx) + ddx
			var py := emblem_y + dy
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, Color(1.0, 1.0, 1.0, 1.0))
	# Energy rune lines on torso (diagonal)
	for ri in 3:
		var ry_start := int(cy - 4 + ri * 5)
		for s in 6:
			var rx := int(cx - 5 + s * 2)
			var ry := ry_start + s
			if rx >= 0 and rx < size and ry >= 0 and ry < size:
				var existing := img.get_pixel(rx, ry)
				if existing.a > 0.5:
					img.set_pixel(rx, ry, Color(minf(existing.r + 0.12, 1.0), minf(existing.g + 0.12, 1.0), minf(existing.b + 0.12, 1.0), 1.0))
	# Sword on the right side with glow
	var sword_x := int(cx + r_body * 0.58)
	var sword_top := int(cy - size * 0.28)
	var sword_bot := int(cy + size * 0.38)
	for sy in range(sword_top, sword_bot + 1):
		if sword_x >= 0 and sword_x < size and sy >= 0 and sy < size:
			# Blade brightness varies along length
			var blade_t := float(sy - sword_top) / float(sword_bot - sword_top)
			var bi := 1.0 - blade_t * 0.15
			img.set_pixel(sword_x, sy, Color(bi, bi, bi, 0.95))
			if sword_x + 1 < size:
				img.set_pixel(sword_x + 1, sy, Color(bi * 0.8, bi * 0.8, bi * 0.8, 0.45))
			# Blade edge glow
			if sword_x - 1 >= 0:
				img.set_pixel(sword_x - 1, sy, Color(1.0, 1.0, 1.0, 0.15))
	# Sword crossguard (wider)
	var guard_y := int(cy - size * 0.04)
	for gx in range(sword_x - 3, sword_x + 4):
		if gx >= 0 and gx < size and guard_y >= 0 and guard_y < size:
			var gd := absf(float(gx - sword_x)) / 3.0
			img.set_pixel(gx, guard_y, Color(1.0 - gd * 0.15, 1.0 - gd * 0.15, 1.0 - gd * 0.15, 0.9))
	# Sword pommel glow
	if sword_x >= 0 and sword_x < size and sword_bot + 1 < size:
		for pdx in range(-1, 2):
			for pdy in range(0, 2):
				var px := sword_x + pdx
				var py := sword_bot + pdy
				if px >= 0 and px < size and py >= 0 and py < size:
					img.set_pixel(px, py, Color(0.9, 0.9, 0.9, 0.7))
	return ImageTexture.create_from_image(img)

static func _solid_tex(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
