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

const _BASE_COLOR := Color(0.4, 0.8, 1.0)

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
		# Shield ring 1 — oval energy shield rotating around ship
		var r1 := 18.0 + sin(p * 2.5) * 2.0
		var a1 := 0.12 + sin(p * 2.0) * 0.04
		_aura_ring.draw_arc(Vector2.ZERO, r1, p * 0.5, p * 0.5 + PI * 1.4, 20,
			Color(0.5, 0.85, 1.0, a1), 1.5)
		# Shield ring 2 — counter-rotating
		var r2 := 15.0 + sin(p * 3.5 + 1.5) * 2.0
		_aura_ring.draw_arc(Vector2.ZERO, r2, -p * 0.7, -p * 0.7 + PI * 1.2, 18,
			Color(0.6, 0.9, 1.0, a1 + 0.03), 1.0)
		# Engine trail — two lines extending behind ship (downward)
		for side: float in [-4.0, 4.0]:
			var trail_a := 0.18 + sin(p * 5.0 + side) * 0.06
			var trail_len := 12.0 + sin(p * 4.0) * 3.0
			_aura_ring.draw_line(
				Vector2(side, 8.0),
				Vector2(side * 0.6, 8.0 + trail_len),
				Color(0.5, 0.9, 1.0, trail_a), 2.0)
			# Outer glow of trail
			_aura_ring.draw_line(
				Vector2(side, 9.0),
				Vector2(side * 0.5, 9.0 + trail_len * 0.7),
				Color(0.4, 0.8, 1.0, trail_a * 0.4), 3.5)
		# Center engine flare
		var flare_a := 0.15 + sin(p * 6.0) * 0.07
		var flare_len := 8.0 + sin(p * 3.0 + 0.5) * 2.0
		_aura_ring.draw_line(Vector2.ZERO + Vector2(0, 10),
			Vector2(0, 10 + flare_len),
			Color(0.7, 0.95, 1.0, flare_a), 1.5)
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
	var s := float(size)
	var cx := (size - 1) * 0.5

	# --- Helper: hull half-width at normalized y (0=top, 1=bottom) ---
	# Returns half-width in pixels for the ship silhouette
	var _hw := func(t: float) -> float:
		if t < 0.05:       # nose point
			return lerpf(0.0, 2.0, t / 0.05)
		elif t < 0.30:     # nose to cockpit
			return lerpf(2.0, 5.0, (t - 0.05) / 0.25)
		elif t < 0.55:     # body section
			return lerpf(5.0, 8.0, (t - 0.30) / 0.25)
		elif t < 0.78:     # wing expansion
			return lerpf(8.0, 20.0, (t - 0.55) / 0.23)
		elif t < 0.88:     # wing to engine contraction
			return lerpf(20.0, 6.0, (t - 0.78) / 0.10)
		else:              # engine taper
			return lerpf(6.0, 3.0, (t - 0.88) / 0.12)

	# --- Pass 0: Outer energy glow halo (faint silhouette glow) ---
	for y in size:
		var t := float(y) / s
		if t < 0.0 or t > 1.0:
			continue
		var hw: float = _hw.call(t)
		for x in size:
			var dx := absf(float(x) - cx)
			# Distance from hull edge
			var dist_from_edge := dx - hw
			if dist_from_edge > 0.0 and dist_from_edge < 5.0:
				var glow := (1.0 - dist_from_edge / 5.0)
				glow *= glow  # quadratic falloff
				var existing := img.get_pixel(x, y)
				if glow * 0.18 > existing.a:
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, glow * 0.18))
	# Vertical glow above nose
	for y in range(0, int(s * 0.05)):
		var dist := float(int(s * 0.05) - y)
		var glow := maxf(0.0, 1.0 - dist / 4.0)
		glow *= glow
		var px := int(cx)
		if px >= 0 and px < size and y >= 0 and y < size:
			img.set_pixel(px, y, Color(1.0, 1.0, 1.0, glow * 0.15))
	# Glow below engines
	for y in range(int(s * 1.0), mini(size, int(s * 1.0) + 5)):
		var dist := float(y) - s
		var glow := maxf(0.0, 1.0 - dist / 5.0)
		for ddx in range(-3, 4):
			var px := int(cx) + ddx
			if px >= 0 and px < size and y >= 0 and y < size:
				var xfade := 1.0 - absf(float(ddx)) / 4.0
				img.set_pixel(px, y, Color(1.0, 1.0, 1.0, glow * xfade * 0.12))

	# --- Pass 1: Main hull fill with metallic shading ---
	for y in size:
		var t := float(y) / s
		if t < 0.0 or t > 1.0:
			continue
		var hw: float = _hw.call(t)
		for x in size:
			var dx := absf(float(x) - cx)
			if dx <= hw:
				# Metallic shading: brighter at center, darker at edges
				var edge_t := dx / maxf(hw, 0.001)
				var base_i := lerpf(0.72, 0.45, edge_t * edge_t)
				# Slight vertical gradient: brighter near nose
				base_i += (1.0 - t) * 0.08
				img.set_pixel(x, y, Color(base_i, base_i, base_i, 1.0))

	# --- Pass 2: Hull edge bevel (bright rim) ---
	for y in size:
		var t := float(y) / s
		if t < 0.0 or t > 1.0:
			continue
		var hw: float = _hw.call(t)
		for x in size:
			var dx := absf(float(x) - cx)
			if dx > hw - 1.5 and dx <= hw:
				var rim_t := (dx - (hw - 1.5)) / 1.5
				var i := lerpf(0.7, 0.92, rim_t)
				img.set_pixel(x, y, Color(i, i, i, 1.0))

	# --- Pass 3: Center spine line (nose to tail) ---
	for y in size:
		var t := float(y) / s
		if t < 0.02 or t > 0.98:
			continue
		var hw: float = _hw.call(t)
		if hw < 1.5:
			continue
		var px := int(cx)
		if px >= 0 and px < size:
			var existing := img.get_pixel(px, y)
			if existing.a > 0.5:
				var spine_i := minf(existing.r + 0.15, 1.0)
				img.set_pixel(px, y, Color(spine_i, spine_i, spine_i, 1.0))

	# --- Pass 4: Panel lines / seams for hull detail ---
	# Horizontal panel lines at key sections
	var panel_rows := [0.20, 0.35, 0.52, 0.70, 0.85]
	for pr in panel_rows:
		var py := int(pr * s)
		if py < 0 or py >= size:
			continue
		var hw: float = _hw.call(pr)
		for x in size:
			var dx := absf(float(x) - cx)
			if dx < hw - 1.0:
				var existing := img.get_pixel(x, py)
				if existing.a > 0.5:
					var di := maxf(existing.r - 0.12, 0.0)
					img.set_pixel(x, py, Color(di, di, di, 1.0))

	# Diagonal panel lines on each side of hull
	for side: float in [-1.0, 1.0]:
		for yi in range(int(s * 0.25), int(s * 0.75)):
			var t := float(yi) / s
			var hw: float = _hw.call(t)
			var line_x := int(cx + side * hw * 0.5 + side * float(yi - int(s * 0.25)) * 0.15)
			if line_x >= 0 and line_x < size and yi >= 0 and yi < size:
				var existing := img.get_pixel(line_x, yi)
				if existing.a > 0.5:
					var di := maxf(existing.r - 0.08, 0.0)
					img.set_pixel(line_x, yi, Color(di, di, di, 1.0))

	# --- Pass 5: Wing energy lines (bright streaks along wings) ---
	for side: float in [-1.0, 1.0]:
		# Main wing leading edge energy line
		for yi in range(int(s * 0.55), int(s * 0.78)):
			var t := float(yi) / s
			var hw: float = _hw.call(t)
			var wing_edge_x := int(cx + side * (hw - 0.5))
			if wing_edge_x >= 0 and wing_edge_x < size and yi >= 0 and yi < size:
				img.set_pixel(wing_edge_x, yi, Color(0.95, 0.95, 0.95, 1.0))
		# Inner wing energy line
		for yi in range(int(s * 0.58), int(s * 0.76)):
			var t := float(yi) / s
			var hw: float = _hw.call(t)
			var inner_x := int(cx + side * hw * 0.6)
			if inner_x >= 0 and inner_x < size and yi >= 0 and yi < size:
				var existing := img.get_pixel(inner_x, yi)
				if existing.a > 0.5:
					var ei := minf(existing.r + 0.2, 1.0)
					img.set_pixel(inner_x, yi, Color(ei, ei, ei, 1.0))
		# Wing surface energy vein (subtle)
		for yi in range(int(s * 0.60), int(s * 0.74)):
			var t := float(yi) / s
			var hw: float = _hw.call(t)
			var vein_x := int(cx + side * hw * 0.35)
			if vein_x >= 0 and vein_x < size and yi >= 0 and yi < size:
				var existing := img.get_pixel(vein_x, yi)
				if existing.a > 0.5:
					var ei := minf(existing.r + 0.10, 1.0)
					img.set_pixel(vein_x, yi, Color(ei, ei, ei, 1.0))

	# --- Pass 6: Wing tip accents (bright spots at outermost wing points) ---
	var wing_tip_y := int(s * 0.76)
	for side: float in [-1.0, 1.0]:
		var hw_tip: float = _hw.call(0.76)
		var tip_x := int(cx + side * hw_tip)
		for ddy in range(-2, 3):
			for ddx in range(-2, 3):
				var px := tip_x + ddx
				var py := wing_tip_y + ddy
				if px >= 0 and px < size and py >= 0 and py < size:
					var dd := sqrt(float(ddx * ddx + ddy * ddy))
					if dd <= 2.5:
						var gi := lerpf(1.0, 0.7, dd / 2.5)
						var ga := lerpf(1.0, 0.4, dd / 2.5)
						img.set_pixel(px, py, Color(gi, gi, gi, ga))

	# --- Pass 7: Cockpit canopy (glowing dome near front) ---
	var cockpit_cy := s * 0.18
	var cockpit_rx := 3.5   # horizontal radius
	var cockpit_ry := 5.0   # vertical radius (elongated)
	# Cockpit dark rim
	for y in size:
		for x in size:
			var dx := (float(x) - cx) / (cockpit_rx + 1.0)
			var dy := (float(y) - cockpit_cy) / (cockpit_ry + 1.0)
			var d := dx * dx + dy * dy
			if d <= 1.0 and d > 0.65:
				var rim_i := lerpf(0.50, 0.35, (d - 0.65) / 0.35)
				img.set_pixel(x, y, Color(rim_i, rim_i, rim_i, 1.0))
	# Cockpit bright interior
	for y in size:
		for x in size:
			var dx := (float(x) - cx) / cockpit_rx
			var dy := (float(y) - cockpit_cy) / cockpit_ry
			var d := dx * dx + dy * dy
			if d <= 1.0:
				# Bright glowing dome, brightest at center
				var ci := lerpf(1.0, 0.65, d)
				# Slight upward highlight
				ci += (1.0 - dy) * 0.05
				ci = clampf(ci, 0.0, 1.0)
				img.set_pixel(x, y, Color(ci, ci, ci, 1.0))

	# --- Pass 8: Engine exhausts (2 side + 1 center at bottom) ---
	var engine_y := s * 0.93
	var engine_positions: Array[float] = [-3.5, 0.0, 3.5]
	var engine_radii: Array[float] = [2.0, 2.5, 2.0]
	for ei in engine_positions.size():
		var ecx := cx + engine_positions[ei]
		var er: float = engine_radii[ei]
		for y in size:
			for x in size:
				var dx := float(x) - ecx
				var dy := float(y) - engine_y
				var d := sqrt(dx * dx + dy * dy)
				if d <= er:
					# Bright white-hot core
					var ni := lerpf(1.0, 0.75, d / er)
					img.set_pixel(x, y, Color(ni, ni, ni, 1.0))
				elif d <= er + 2.0:
					# Exhaust glow falloff
					var glow := 1.0 - (d - er) / 2.0
					glow *= glow
					var existing := img.get_pixel(x, y)
					var new_a := glow * 0.5
					if new_a > existing.a:
						img.set_pixel(x, y, Color(1.0, 1.0, 1.0, new_a))

	# Engine exhaust plume glow below engines
	for ei in engine_positions.size():
		var ecx := cx + engine_positions[ei]
		var er: float = engine_radii[ei]
		for dy_off in range(1, 5):
			var py := int(engine_y) + int(er) + dy_off
			if py >= size:
				break
			var fade := 1.0 - float(dy_off) / 5.0
			var plume_hw := er * fade * 0.8
			for ddx in range(int(-plume_hw) - 1, int(plume_hw) + 2):
				var px := int(ecx) + ddx
				if px >= 0 and px < size and py >= 0 and py < size:
					var xf := 1.0 - absf(float(ddx)) / (plume_hw + 0.001)
					xf = clampf(xf, 0.0, 1.0)
					var pi := fade * xf * 0.6
					var existing := img.get_pixel(px, py)
					if pi > existing.a:
						img.set_pixel(px, py, Color(1.0, 1.0, 1.0, pi))

	# --- Pass 9: Additional hull detail - weapon mounts on wings ---
	for side: float in [-1.0, 1.0]:
		var mount_y := int(s * 0.65)
		var hw_at: float = _hw.call(0.65)
		var mount_x := int(cx + side * hw_at * 0.75)
		for ddy in range(-2, 3):
			for ddx in range(-1, 2):
				var px := mount_x + ddx
				var py := mount_y + ddy
				if px >= 0 and px < size and py >= 0 and py < size:
					var existing := img.get_pixel(px, py)
					if existing.a > 0.5:
						var mi := minf(existing.r + 0.18, 1.0)
						img.set_pixel(px, py, Color(mi, mi, mi, 1.0))

	# --- Pass 10: Nose tip bright accent ---
	var nose_y := int(s * 0.02)
	for ddy in range(0, 3):
		for ddx in range(-1, 2):
			var px := int(cx) + ddx
			var py := nose_y + ddy
			if px >= 0 and px < size and py >= 0 and py < size:
				var dd := sqrt(float(ddx * ddx + ddy * ddy))
				var ni := lerpf(1.0, 0.8, dd / 2.5)
				img.set_pixel(px, py, Color(ni, ni, ni, 1.0))

	# --- Pass 11: Subtle cross-hull energy shimmer ---
	for y in size:
		var t := float(y) / s
		if t < 0.10 or t > 0.90:
			continue
		var hw: float = _hw.call(t)
		for x in size:
			var dx := absf(float(x) - cx)
			if dx < hw - 1.0:
				var existing := img.get_pixel(x, y)
				if existing.a > 0.5:
					# Subtle wave pattern
					var wave := sin(float(x) * 1.2 + float(y) * 0.8) * 0.03
					wave += sin(float(x) * 0.5 - float(y) * 1.5) * 0.02
					var ni := clampf(existing.r + wave, 0.0, 1.0)
					img.set_pixel(x, y, Color(ni, ni, ni, 1.0))

	return ImageTexture.create_from_image(img)

static func _solid_tex(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
