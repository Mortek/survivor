class_name Enemy
extends CharacterBody2D
## Enemy – seeks the player, takes damage, dies and drops XP.
## Types: BASIC, FAST, TANK, BOSS, SPLITTER, EXPLODER.
## Any enemy can also be marked as an Elite for 3× HP and bonus XP.

# ── Signals ───────────────────────────────────────────────────────────────────
signal died(world_position: Vector2, xp_value: int, color: Color, enemy_type: int, hit_dir: Vector2)
signal hit_taken(world_position: Vector2, amount: float)
signal split_requested(world_position: Vector2)   # emitted by SPLITTER on death

# ── Types ─────────────────────────────────────────────────────────────────────
enum Type { BASIC, FAST, TANK, BOSS, SPLITTER, EXPLODER, SHIELDER, HEALER, SWARM, TELEPORTER, CHARGER }
@export var enemy_type: Type = Type.BASIC

# ── Per-type base config ──────────────────────────────────────────────────────
const CONFIGS: Dictionary = {
	Type.BASIC:    { "hp": 30,  "spd": 80,   "dmg": 10, "xp": 10,  "col": Color(0.90, 0.30, 0.30) },
	Type.FAST:     { "hp": 15,  "spd": 155,  "dmg": 7,  "xp": 15,  "col": Color(1.00, 0.85, 0.20) },
	Type.TANK:     { "hp": 120, "spd": 45,   "dmg": 20, "xp": 30,  "col": Color(0.50, 0.20, 0.90) },
	Type.BOSS:     { "hp": 600, "spd": 55,   "dmg": 28, "xp": 200, "col": Color(0.90, 0.10, 0.90) },
	Type.SPLITTER: { "hp": 45,  "spd": 90,   "dmg": 8,  "xp": 20,  "col": Color(0.20, 0.85, 0.50) },
	Type.EXPLODER: { "hp": 25,  "spd": 120,  "dmg": 35, "xp": 25,  "col": Color(1.00, 0.45, 0.05) },
	Type.SHIELDER: { "hp": 60,  "spd": 65,   "dmg": 12, "xp": 35,  "col": Color(0.40, 0.60, 1.00) },
	Type.HEALER:   { "hp": 40,  "spd": 50,   "dmg": 8,  "xp": 40,  "col": Color(0.20, 0.90, 0.80) },
	Type.SWARM:       { "hp": 8,   "spd": 175,  "dmg": 5,  "xp": 6,   "col": Color(1.00, 0.60, 0.80) },
	Type.TELEPORTER:  { "hp": 40,  "spd": 55,   "dmg": 14, "xp": 35,  "col": Color(0.10, 0.90, 1.00) },
	Type.CHARGER:     { "hp": 65,  "spd": 60,   "dmg": 22, "xp": 30,  "col": Color(0.80, 0.12, 0.25) },
}

# ── Node References ───────────────────────────────────────────────────────────
@onready var sprite:       Sprite2D    = $Sprite2D
@onready var hp_bar:       ProgressBar = $HealthBar
@onready var damage_area:  Area2D      = $DamageArea

# ── Runtime State ─────────────────────────────────────────────────────────────
var max_hp:     float = 30.0
var current_hp: float = 30.0
var spd:        float = 80.0
var dmg:        int   = 10
var xp_value:   int   = 10
var _base_color: Color
var _player: Node2D  = null
var _dead: bool         = false
var is_elite: bool      = false
var _last_hit_dir: Vector2 = Vector2.ZERO

# ── Status effects ────────────────────────────────────────────────────────────
var _slow_timer:       float = 0.0
var _slow_factor:      float = 1.0
var _burn_timer:       float = 0.0
var _burn_acc:         float = 0.0
var _burn_dmg_per_sec: float = 0.0
var _knockback_vel:    Vector2 = Vector2.ZERO

# ── Shielder-specific ─────────────────────────────────────────────────────────
var _shield_active:    bool  = false

# ── Healer-specific ───────────────────────────────────────────────────────────
var _heal_timer:       float = 0.0
const HEALER_PULSE_INTERVAL := 1.5
const HEALER_PULSE_RADIUS   := 120.0
const HEALER_PULSE_AMOUNT   := 5.0

# ── Teleporter-specific state ─────────────────────────────────────────────────
var _tele_timer:       float = 0.0
var _tele_flashing:    bool  = false
var _tele_flash_timer: float = 0.0
const TELEPORTER_INTERVAL       := 3.5
const TELEPORTER_FLASH_DURATION := 0.28

# ── Charger-specific state ────────────────────────────────────────────────────
var _charger_state: int     = 0   # 0=tracking, 1=warning, 2=charging, 3=cooldown
var _charger_timer: float   = 0.0
var _charger_dir:   Vector2 = Vector2.ZERO
const CHARGER_TRACK_DURATION  := 2.2
const CHARGER_WARN_DURATION   := 0.35
const CHARGER_CHARGE_DURATION := 0.55
const CHARGER_COOLDOWN        := 1.0
const CHARGER_CHARGE_SPEED    := 360.0

# ── Boss-specific state ───────────────────────────────────────────────────────
var _charge_timer:   float = 0.0
var _charging:       bool  = false
var _charge_elapsed: float = 0.0
const BOSS_CHARGE_COOLDOWN  := 3.5
const BOSS_CHARGE_DURATION  := 0.55
const BOSS_CHARGE_SPEED_MULT := 3.8

# ── Exploder-specific state ───────────────────────────────────────────────────
var _exploder_fuse_timer:  float = 0.0
var _exploder_triggered:   bool  = false
const EXPLODER_TRIGGER_DIST  := 45.0
const EXPLODER_AOE_RADIUS    := 90.0
const EXPLODER_FUSE_DURATION := 0.6

# ── Lifecycle ─────────────────────────────────────────────────────────────────
var _glow_tween: Tween = null

func _ready() -> void:
	damage_area.body_entered.connect(_on_damage_area_body_entered)
	# Load defaults so the node displays correctly before activate() is called.
	var cfg: Dictionary = CONFIGS[enemy_type]
	_base_color     = cfg["col"]
	sprite.modulate = _base_color
	if not sprite.texture:
		sprite.texture = _shape_tex(enemy_type)
	# Pulsing brightness animation for all enemies
	_start_glow_pulse()

func _start_glow_pulse() -> void:
	if _glow_tween and _glow_tween.is_running():
		return
	# Subtle brightness pulse — each type gets a different speed
	var speed := 0.8
	match enemy_type:
		Type.FAST:       speed = 0.5
		Type.BOSS:       speed = 1.2
		Type.EXPLODER:   speed = 0.4
		Type.TELEPORTER: speed = 0.6
	_glow_tween = create_tween()
	_glow_tween.set_loops()
	_glow_tween.tween_method(func(v: float) -> void:
		if is_instance_valid(sprite) and not _dead:
			var base := _normal_modulate()
			sprite.modulate = base.lightened(v * 0.15)
	, 0.0, 1.0, speed).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_method(func(v: float) -> void:
		if is_instance_valid(sprite) and not _dead:
			var base := _normal_modulate()
			sprite.modulate = base.lightened(v * 0.15)
	, 1.0, 0.0, speed).set_trans(Tween.TRANS_SINE)

## Call after instantiation, before placing in the world.
func activate(player: Node2D, wave_multiplier: float) -> void:
	_player = player
	_dead   = false
	add_to_group("enemies")

	var cfg: Dictionary = CONFIGS[enemy_type]
	_base_color = cfg["col"]
	max_hp      = cfg["hp"]  * wave_multiplier
	current_hp  = max_hp
	spd         = minf(cfg["spd"] * (1.0 + (wave_multiplier - 1.0) * 0.25), 220.0) \
				  * GameManager.stats.get("enemy_speed_mult", 1.0)
	dmg         = int(cfg["dmg"] * wave_multiplier)
	xp_value    = int(cfg["xp"] * wave_multiplier)

	# Per-type overrides
	match enemy_type:
		Type.BOSS:
			# Boss speed is not wave-scaled; still applies curse mult
			spd          = cfg["spd"] * GameManager.stats.get("enemy_speed_mult", 1.0)
			sprite.scale = Vector2(2.0, 2.0)
		Type.SPLITTER:
			sprite.scale = Vector2(0.85, 0.85)
		Type.EXPLODER:
			sprite.scale = Vector2(0.75, 0.75)

	if is_elite:
		max_hp       *= 3.0
		current_hp    = max_hp
		xp_value     *= 5
		dmg           = int(dmg * 1.5)
		sprite.scale   *= 1.25
	sprite.modulate = _normal_modulate()

	# Per-type setup
	if enemy_type == Type.SHIELDER:
		_shield_active = true
	_slow_timer       = 0.0
	_slow_factor      = 1.0
	_burn_timer       = 0.0
	_burn_acc         = 0.0
	_burn_dmg_per_sec = 0.0
	_knockback_vel    = Vector2.ZERO
	_heal_timer       = 0.0
	_tele_timer       = 0.0
	_tele_flashing    = false
	_tele_flash_timer = 0.0
	_charger_state    = 0
	_charger_timer    = 0.0
	_charger_dir      = Vector2.ZERO

	_update_hp_bar()
	if hp_bar:
		hp_bar.hide()

# ── AI Movement ───────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _dead or not _player or GameManager.state != GameManager.State.PLAYING:
		return

	# Status effect ticks
	_knockback_vel = _knockback_vel.move_toward(Vector2.ZERO, 500.0 * delta)

	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_factor = 1.0

	if _burn_timer > 0.0:
		_burn_timer -= delta
		_burn_acc   += delta
		if _burn_acc >= 1.0:
			_burn_acc -= 1.0
			if not _dead:
				current_hp -= _burn_dmg_per_sec
				_update_hp_bar()
				_flash_hit()
				hit_taken.emit(global_position, _burn_dmg_per_sec)
				if current_hp <= 0.0:
					_die()
					return

	match enemy_type:
		Type.BOSS:
			_boss_ai(delta)
		Type.EXPLODER:
			_exploder_ai(delta)
		Type.HEALER:
			_healer_ai(delta)
		Type.TELEPORTER:
			_teleporter_ai(delta)
		Type.CHARGER:
			_charger_ai(delta)
		_:
			velocity = (_player.global_position - global_position).normalized() * spd * _slow_factor + _knockback_vel
			move_and_slide()

func _boss_ai(delta: float) -> void:
	var dir := (_player.global_position - global_position).normalized()
	if _charging:
		_charge_elapsed += delta
		velocity = dir * spd * BOSS_CHARGE_SPEED_MULT
		if _charge_elapsed >= BOSS_CHARGE_DURATION:
			_charging = false
			sprite.modulate = _normal_modulate()
	else:
		_charge_timer += delta
		velocity = dir * spd
		if _charge_timer >= BOSS_CHARGE_COOLDOWN:
			_charge_timer   = 0.0
			_charge_elapsed = 0.0
			_charging       = true
			sprite.modulate = Color(1.0, 0.15, 0.0)
	move_and_slide()

func _exploder_ai(delta: float) -> void:
	if _exploder_triggered:
		_exploder_fuse_timer += delta
		# Pulse warning flash
		var pulse := sin(_exploder_fuse_timer * 30.0) * 0.5 + 0.5
		sprite.modulate = Color(1.0, pulse * 0.5, 0.0)
		if _exploder_fuse_timer >= EXPLODER_FUSE_DURATION:
			_explode()
		return
	# Move toward player; trigger when in range
	var dist := global_position.distance_to(_player.global_position)
	velocity = (_player.global_position - global_position).normalized() * spd
	move_and_slide()
	if dist <= EXPLODER_TRIGGER_DIST:
		_exploder_triggered = true
		_exploder_fuse_timer = 0.0

func _explode() -> void:
	if _dead:
		return
	# Deal AOE damage to player if in range
	if _player and _player.global_position.distance_to(global_position) <= EXPLODER_AOE_RADIUS:
		if _player.has_method("take_damage"):
			_player.take_damage(dmg)
	_die()

func _healer_ai(delta: float) -> void:
	velocity = (_player.global_position - global_position).normalized() * spd * _slow_factor + _knockback_vel
	move_and_slide()
	_heal_timer += delta
	if _heal_timer >= HEALER_PULSE_INTERVAL:
		_heal_timer = 0.0
		_pulse_heal()

func _teleporter_ai(delta: float) -> void:
	if _tele_flashing:
		_tele_flash_timer += delta
		sprite.modulate.a = 0.25 + absf(sin(_tele_flash_timer * 22.0)) * 0.55
		if _tele_flash_timer >= TELEPORTER_FLASH_DURATION:
			var angle := randf() * TAU
			var dist  := randf_range(65.0, 105.0)
			global_position  = _player.global_position + Vector2(cos(angle), sin(angle)) * dist
			sprite.modulate  = _normal_modulate()
			_tele_flashing   = false
			_tele_timer      = 0.0
		return
	velocity = (_player.global_position - global_position).normalized() * spd * _slow_factor + _knockback_vel
	move_and_slide()
	_tele_timer += delta
	if _tele_timer >= TELEPORTER_INTERVAL:
		_tele_flashing    = true
		_tele_flash_timer = 0.0

func _charger_ai(delta: float) -> void:
	_charger_timer += delta
	match _charger_state:
		0:  # Tracking player
			velocity = (_player.global_position - global_position).normalized() * spd * _slow_factor + _knockback_vel
			move_and_slide()
			if _charger_timer >= CHARGER_TRACK_DURATION:
				_charger_state = 1
				_charger_timer = 0.0
				_charger_dir   = (_player.global_position - global_position).normalized()
				sprite.modulate = Color(1.0, 0.9, 0.1)  # Yellow warning
		1:  # Pre-charge warning pause
			velocity = Vector2.ZERO
			if _charger_timer >= CHARGER_WARN_DURATION:
				_charger_state  = 2
				_charger_timer  = 0.0
				sprite.modulate = _normal_modulate()
		2:  # Charging
			velocity = _charger_dir * CHARGER_CHARGE_SPEED
			move_and_slide()
			if _charger_timer >= CHARGER_CHARGE_DURATION:
				_charger_state = 3
				_charger_timer = 0.0
		3:  # Cooldown
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			move_and_slide()
			if _charger_timer >= CHARGER_COOLDOWN:
				_charger_state = 0
				_charger_timer = 0.0

func _pulse_heal() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy == self:
			continue
		var e := enemy as Enemy
		if e and global_position.distance_squared_to(e.global_position) <= HEALER_PULSE_RADIUS * HEALER_PULSE_RADIUS:
			if e.current_hp < e.max_hp:
				e.current_hp = minf(e.current_hp + HEALER_PULSE_AMOUNT, e.max_hp)
				e._update_hp_bar()

# ── Combat ────────────────────────────────────────────────────────────────────
func _is_on_screen() -> bool:
	var vp         := get_viewport()
	var screen_pos := vp.get_canvas_transform() * global_position
	return Rect2(Vector2.ZERO, vp.get_visible_rect().size).has_point(screen_pos)

func take_damage(amount: float, hit_dir: Vector2 = Vector2.ZERO) -> void:
	if _dead:
		return
	_last_hit_dir = hit_dir
	if not _is_on_screen():
		return
	if hp_bar and not hp_bar.visible:
		hp_bar.show()
	# Shielder absorbs the first hit
	if _shield_active:
		_shield_active = false
		sprite.modulate = Color(0.5, 0.8, 1.0)
		await get_tree().create_timer(0.12).timeout
		if is_instance_valid(self) and not _dead:
			sprite.modulate = _normal_modulate()
		return
	current_hp -= amount
	_update_hp_bar()
	_flash_hit()
	hit_taken.emit(global_position, amount)
	if current_hp <= 0.0:
		_die()

func _normal_modulate() -> Color:
	return _base_color.lightened(0.5) if is_elite else _base_color

func _update_hp_bar() -> void:
	if hp_bar:
		hp_bar.value = (current_hp / max_hp) * 100.0

func _flash_hit() -> void:
	if enemy_type == Type.BOSS and _charging:
		return
	if _exploder_triggered:
		return
	sprite.modulate = Color.WHITE
	await get_tree().create_timer(0.06).timeout
	if is_instance_valid(self) and not _dead:
		sprite.modulate = _normal_modulate()

func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemies")
	# Brief slow-motion punch on death (skip SWARM and BOSS — boss has its own hitpause)
	if enemy_type != Type.SWARM and enemy_type != Type.BOSS:
		Engine.time_scale = 0.35
		get_tree().create_timer(0.06, true, false, true).timeout.connect(
			func() -> void: if Engine.time_scale < 0.9: Engine.time_scale = GameManager.desired_time_scale
		)
	died.emit(global_position, xp_value, _base_color, int(enemy_type), _last_hit_dir)
	if enemy_type == Type.SPLITTER:
		split_requested.emit(global_position)
	queue_free()

func apply_knockback(force: Vector2) -> void:
	_knockback_vel = force

func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = minf(_slow_factor, 1.0 - factor)
	_slow_timer  = maxf(_slow_timer, duration)

func apply_burn(dmg_per_sec: float, duration: float) -> void:
	_burn_dmg_per_sec = maxf(_burn_dmg_per_sec, dmg_per_sec)
	_burn_timer       = maxf(_burn_timer, duration)

# ── Contact Damage ────────────────────────────────────────────────────────────
func _on_damage_area_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(dmg)

## Texture cache — generated once per type, reused for all instances.
static var _tex_cache: Dictionary = {}

## Returns a distinct white-on-transparent shape texture for each enemy type.
## Colour is applied separately via sprite.modulate.
## All shapes include inner details, glow edges, and layered depth.
static func _shape_tex(type: int) -> ImageTexture:
	if type in _tex_cache:
		return _tex_cache[type]
	var tex := _shape_tex_uncached(type)
	_tex_cache[type] = tex
	return tex

static func _shape_tex_uncached(type: int) -> ImageTexture:
	match type:
		Type.BASIC:    return _spiky_circle_tex(36)
		Type.FAST:     return _lightning_bolt_tex(26, 36)
		Type.TANK:     return _armored_hex_tex(44)
		Type.BOSS:     return _star_shape_tex(40, 6)
		Type.SPLITTER: return _split_diamond_tex(36)
		Type.EXPLODER: return _bomb_tex(34)
		Type.SHIELDER: return _shield_hex_tex(38)
		Type.HEALER:      return _cross_plus_tex(38)
		Type.SWARM:       return _swarm_orb_tex(20)
		Type.TELEPORTER:  return _portal_tex(36)
		Type.CHARGER:     return _ram_skull_tex(26, 38)
		_:                return _spiky_circle_tex(36)

## Alien Face — tall oval cranium, almond eyes with glowing irises, vein patterns
static func _spiky_circle_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r := size * 0.5 - 0.5
	# Pass 1: bioluminescent outer glow
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			# Cranium shape: tall oval — wider at top, narrow chin
			var stretch_y := dy * 0.78 + r * 0.08
			var chin_factor := 1.0 + maxf(dy / r, 0.0) * 0.5
			var shape_d := sqrt(dx * dx * chin_factor * chin_factor + stretch_y * stretch_y)
			if shape_d > r and shape_d <= r + 3.5:
				var fade := 1.0 - (shape_d - r) / 3.5
				var angle := atan2(dy, dx)
				var pulse := absf(sin(angle * 5.0)) * 0.1
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * (0.3 + pulse)))
	# Pass 2: cranium body with smooth shading and vein patterns
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var stretch_y := dy * 0.78 + r * 0.08
			var chin_factor := 1.0 + maxf(dy / r, 0.0) * 0.5
			var shape_d := sqrt(dx * dx * chin_factor * chin_factor + stretch_y * stretch_y)
			if shape_d <= r:
				var norm_d := shape_d / r
				# Smooth cranium shading — bright top, darker edges
				var shade := (-dy / r) * 0.1 + (-dx / r) * 0.05
				# Subtle vein patterns on cranium
				var vein1 := absf(sin(dx * 0.9 + dy * 0.4 + 2.0))
				var vein2 := absf(sin(dx * 0.5 - dy * 0.7 + 1.0))
				var vein := 0.0
				if vein1 < 0.08 and dy < cy * 0.3:
					vein = 0.12
				if vein2 < 0.06 and dy < cy * 0.2:
					vein = 0.10
				var intensity := clampf(0.85 - norm_d * 0.25 + shade + vein, 0.0, 1.0)
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Pass 3: two large almond-shaped eyes
	var eye_y := cy - r * 0.08
	var eye_sep := r * 0.32
	var eye_rx := r * 0.22   # horizontal radius of eye
	var eye_ry := r * 0.13   # vertical radius (almond)
	for side: float in [-1.0, 1.0]:
		var ecx := cx + side * eye_sep
		var ecy := eye_y
		for y in size:
			for x in size:
				var ex := (float(x) - ecx) / eye_rx
				var ey := (float(y) - ecy) / eye_ry
				# Almond shape: tilted ellipse
				var tilt := side * 0.3
				var tex_val := ex * cos(tilt) + ey * sin(tilt)
				var tey := -ex * sin(tilt) + ey * cos(tilt)
				var eye_d := sqrt(tex_val * tex_val + tey * tey)
				if eye_d <= 1.0:
					# Dark eye socket
					var socket_i := 0.12 + eye_d * 0.08
					img.set_pixel(x, y, Color(socket_i, socket_i, socket_i, 1.0))
					# Bright iris ring
					if eye_d > 0.3 and eye_d < 0.7:
						var iris_t := (eye_d - 0.3) / 0.4
						var angle := atan2(tey, tex_val)
						var ray := absf(sin(angle * 6.0)) * 0.15
						var ii := 0.7 + sin(iris_t * PI) * 0.3 + ray
						img.set_pixel(x, y, Color(clampf(ii, 0.0, 1.0), clampf(ii, 0.0, 1.0), clampf(ii, 0.0, 1.0), 1.0))
					# Bright pupil center
					elif eye_d <= 0.3:
						var pi_val := 0.6 + (1.0 - eye_d / 0.3) * 0.4
						img.set_pixel(x, y, Color(pi_val, pi_val, pi_val, 1.0))
	# Pass 4: catchlight on each eye
	for side: float in [-1.0, 1.0]:
		var hl_x := cx + side * eye_sep - eye_rx * 0.25
		var hl_y := eye_y - eye_ry * 0.3
		for y in size:
			for x in size:
				var ddx := float(x) - hl_x
				var ddy := float(y) - hl_y
				if sqrt(ddx * ddx + ddy * ddy) <= 1.2:
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.95))
	# Pass 5: small slit mouth
	var mouth_y := cy + r * 0.32
	for x in size:
		var mdx := absf(float(x) - cx)
		if mdx < r * 0.1:
			var mx := int(x)
			var my := int(mouth_y)
			if my >= 0 and my < size:
				var mi := 0.25 + (1.0 - mdx / (r * 0.1)) * 0.15
				img.set_pixel(mx, my, Color(mi, mi, mi, 1.0))
				if my + 1 < size:
					img.set_pixel(mx, my + 1, Color(mi * 0.8, mi * 0.8, mi * 0.8, 1.0))
	return ImageTexture.create_from_image(img)

## Alien Scout Ship / UFO — flying saucer side view, dome, energy ring, underside glow
static func _lightning_bolt_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	var fw := float(w)
	var fh := float(h)
	# Saucer disc center is slightly below middle
	var disc_cy := cy + fh * 0.08
	var disc_rx := fw * 0.48   # horizontal radius of disc
	var disc_ry := fh * 0.14   # vertical radius (flat ellipse)
	# Dome on top
	var dome_cy := disc_cy - disc_ry * 0.6
	var dome_rx := disc_rx * 0.4
	var dome_ry := fh * 0.22
	# Pass 1: underside glow (below disc)
	for y in h:
		for x in w:
			var dx := float(x) - cx
			var dy := float(y) - disc_cy
			if dy > disc_ry * 0.3 and dy < fh * 0.35:
				var glow_w := disc_rx * (1.0 - (dy - disc_ry * 0.3) / (fh * 0.35))
				if absf(dx) < glow_w:
					var norm_x := absf(dx) / glow_w
					var norm_y := (dy - disc_ry * 0.3) / (fh * 0.35 - disc_ry * 0.3)
					var alpha := (1.0 - norm_y) * (1.0 - norm_x * norm_x) * 0.35
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	# Pass 2: main disc body
	for y in h:
		for x in w:
			var dx := float(x) - cx
			var dy := float(y) - disc_cy
			var ed := sqrt((dx / disc_rx) * (dx / disc_rx) + (dy / disc_ry) * (dy / disc_ry))
			if ed <= 1.0:
				var norm_d := ed
				# Beveled disc: bright center ridge, darker edges
				var vert_shade := absf(dy / disc_ry) * 0.2
				var intensity := 0.8 - norm_d * 0.15 - vert_shade
				# Rim highlight at outer edge
				if norm_d > 0.85:
					intensity = 0.9 + (norm_d - 0.85) / 0.15 * 0.1
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 3: energy ring around rim
	for y in h:
		for x in w:
			var dx := float(x) - cx
			var dy := float(y) - disc_cy
			var ed := sqrt((dx / disc_rx) * (dx / disc_rx) + (dy / disc_ry) * (dy / disc_ry))
			if ed > 0.88 and ed <= 1.08:
				var ring_t := absf(ed - 0.98) / 0.1
				var angle := atan2(dy, dx)
				var seg_pulse := absf(sin(angle * 8.0)) * 0.15
				var ri := clampf(1.0 - ring_t * 0.4 + seg_pulse, 0.0, 1.0)
				var existing := img.get_pixel(x, y)
				if ri > existing.r or existing.a < 0.5:
					img.set_pixel(x, y, Color(ri, ri, ri, 1.0))
	# Pass 4: dome with viewport
	for y in h:
		for x in w:
			var dx := float(x) - cx
			var dy := float(y) - dome_cy
			var ed := sqrt((dx / dome_rx) * (dx / dome_rx) + (dy / dome_ry) * (dy / dome_ry))
			# Only draw upper half of dome (above disc)
			if ed <= 1.0 and float(y) < disc_cy - disc_ry * 0.2:
				var norm_d := ed
				# Glass dome shading — bright highlight area
				var shade := (-dy / dome_ry) * 0.15
				var intensity := 0.7 - norm_d * 0.2 + shade
				# Viewport reflection band
				if norm_d > 0.4 and norm_d < 0.7:
					intensity += 0.15
				# Dome edge glow
				if norm_d > 0.85:
					intensity = 0.95
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 5: dome highlight / viewport glint
	var glint_x := cx - dome_rx * 0.25
	var glint_y := dome_cy - dome_ry * 0.4
	for y in h:
		for x in w:
			var ddx := float(x) - glint_x
			var ddy := float(y) - glint_y
			var gd := sqrt(ddx * ddx + ddy * ddy)
			if gd <= 1.8:
				var gi := 1.0 - gd / 1.8 * 0.15
				img.set_pixel(x, y, Color(gi, gi, gi, 1.0))
	# Pass 6: port lights along disc edge
	var num_lights := 6
	for i in num_lights:
		var angle := PI + PI * float(i) / float(num_lights - 1)
		var lx := cx + cos(angle) * disc_rx * 0.75
		var ly := disc_cy + sin(angle) * disc_ry * 0.6
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var px := int(lx) + dx
				var py := int(ly) + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					var ld := sqrt(float(dx * dx + dy * dy))
					if ld <= 1.2:
						img.set_pixel(px, py, Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

## Hex-distance helper used by hex-shaped enemies.
static func _hex_r(angle: float, radius: float) -> float:
	return radius * cos(fmod(absf(angle) + PI / 6.0, PI / 3.0) - PI / 6.0)

## Point-to-segment distance helper for bolt shapes.
static func _pt_seg_dist(px: float, py: float, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := Vector2(px - a.x, py - a.y)
	var t_val := clampf(ap.dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
	var closest := Vector2(a.x + ab.x * t_val, a.y + ab.y * t_val)
	var ddx: float = px - closest.x
	var ddy: float = py - closest.y
	return sqrt(ddx * ddx + ddy * ddy)

## Alien Heavy Beetle — massive chitinous shell, compound eye, mandibles, armored
static func _armored_hex_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r := size * 0.5 - 0.5
	# Pass 1: outer glow halo
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var hex_r := _hex_r(angle, r)
			if d > hex_r and d <= hex_r + 3.5:
				var fade := 1.0 - (d - hex_r) / 3.5
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.25))
	# Pass 2: main shell body with chitinous segments
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var hex_r := _hex_r(angle, r)
			if d > hex_r:
				continue
			var norm_d := d / hex_r
			# Shell segment lines — 3 horizontal bands
			var band_line := 0.0
			var ny := (dy / r + 1.0) * 0.5  # 0 to 1
			if absf(ny - 0.35) < 0.015 or absf(ny - 0.55) < 0.015:
				band_line = -0.3
			# Carapace texture: chitin plates with slight bump mapping
			var chitin := sin(dx * 0.8) * sin(dy * 0.8) * 0.06
			# Overall shading: raised center, darker edges
			var intensity := 0.85 - norm_d * 0.2 + chitin + band_line
			# Thick rim plate
			if norm_d > 0.88:
				intensity = 0.6 + (1.0 - norm_d) / 0.12 * 0.15
			# Center ridge line (spine)
			if absf(dx) < 1.0 and d > r * 0.15 and d < r * 0.85:
				intensity += 0.12
			img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 3: compound eye in upper center
	var eye_cx := cx
	var eye_cy := cy - r * 0.2
	var eye_r := r * 0.22
	for y in size:
		for x in size:
			var edx := float(x) - eye_cx
			var edy := float(y) - eye_cy
			var ed := sqrt(edx * edx + edy * edy)
			if ed <= eye_r:
				var norm_ed := ed / eye_r
				# Compound eye facets — hexagonal pattern
				var facet_scale := 3.5
				var fx := edx * facet_scale / eye_r
				var fy := edy * facet_scale / eye_r
				var fhx := fx - fy * 0.577
				var fhy := fy * 1.155
				var cell_x: float = fhx - floorf(fhx)
				var cell_y: float = fhy - floorf(fhy)
				var cell_d := sqrt((cell_x - 0.5) * (cell_x - 0.5) + (cell_y - 0.5) * (cell_y - 0.5))
				var facet_bright := 0.0
				if cell_d < 0.3:
					facet_bright = 0.3 * (1.0 - cell_d / 0.3)
				var ei := 0.5 + facet_bright + (1.0 - norm_ed) * 0.3
				img.set_pixel(x, y, Color(clampf(ei, 0.0, 1.0), clampf(ei, 0.0, 1.0), clampf(ei, 0.0, 1.0), 1.0))
			elif ed <= eye_r + 1.5:
				# Dark socket ring
				var existing := img.get_pixel(x, y)
				if existing.a > 0.5:
					img.set_pixel(x, y, Color(0.3, 0.3, 0.3, 1.0))
	# Pass 4: mandible hints at bottom
	for side: float in [-1.0, 1.0]:
		var mand_cx := cx + side * r * 0.2
		var mand_cy := cy + r * 0.55
		for s in range(0, 10):
			var st := float(s) / 9.0
			var mx := mand_cx + side * st * r * 0.25
			var my := mand_cy + st * r * 0.25 - st * st * r * 0.1
			var thick := 2.0 - st * 1.2
			for ddy in range(-int(thick) - 1, int(thick) + 2):
				for ddx in range(-int(thick) - 1, int(thick) + 2):
					var px := int(mx) + ddx
					var py := int(my) + ddy
					if px >= 0 and px < size and py >= 0 and py < size:
						var dd := sqrt(float(ddx * ddx + ddy * ddy))
						if dd <= thick:
							var mi := 0.9 - st * 0.3
							var existing := img.get_pixel(px, py)
							if mi > existing.r or existing.a < 0.5:
								img.set_pixel(px, py, Color(clampf(mi, 0.0, 1.0), clampf(mi, 0.0, 1.0), clampf(mi, 0.0, 1.0), 1.0))
	# Pass 5: armor plate rivets at segment corners
	for i in 6:
		var a := i * PI / 3.0
		var rivet_d := r * 0.78
		var rvx := cx + cos(a) * rivet_d
		var rvy := cy + sin(a) * rivet_d
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var px := int(rvx) + dx
				var py := int(rvy) + dy
				if px >= 0 and px < size and py >= 0 and py < size:
					var dd := sqrt(float(dx * dx + dy * dy))
					if dd <= 1.8:
						var ri := 1.0 - dd * 0.15
						img.set_pixel(px, py, Color(ri, ri, ri, 1.0))
	return ImageTexture.create_from_image(img)

## Alien Overlord — tentacle crown, enormous central eye, organic pulsing patterns
static func _star_shape_tex(size: int, points: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.38
	var sector_angle := TAU / float(points)
	# Pass 1: eldritch glow around tentacles
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var a_mod := fmod(angle + TAU + sector_angle * 0.5, sector_angle) - sector_angle * 0.5
			var t := absf(a_mod) / (sector_angle * 0.5)
			var r_star: float = lerpf(r_outer, r_inner, t * t)
			if d > r_star and d <= r_star + 4.0:
				var fade := 1.0 - (d - r_star) / 4.0
				var pulse := absf(sin(angle * 3.0 + d * 0.3)) * 0.12
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * (0.3 + pulse)))
	# Pass 2: tentacle body with organic texture
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var a_mod := fmod(angle + TAU + sector_angle * 0.5, sector_angle) - sector_angle * 0.5
			var t := absf(a_mod) / (sector_angle * 0.5)
			var sharp_t := t * t
			var r_star: float = lerpf(r_outer, r_inner, sharp_t)
			if d <= r_star:
				var norm_d := d / r_star
				# Organic pulsing pattern — veiny texture
				var vein_val := sin(angle * float(points) + d * 0.8) * sin(d * 1.5 - angle * 2.0)
				var vein := 0.0
				if absf(vein_val) < 0.12:
					vein = 0.12 - absf(vein_val)
				# Tentacle sucker dots along each arm
				var sucker := 0.0
				if t < 0.25 and norm_d > 0.45:
					var sucker_pos := fmod(norm_d * 6.0, 1.0)
					if absf(sucker_pos - 0.5) < 0.15:
						sucker = -0.15
				# Base organic intensity
				var intensity := 0.88 - norm_d * 0.25 + vein + sucker
				# Tentacle tip brightening (bioluminescent tips)
				if t < 0.15 and norm_d > 0.75:
					intensity = minf(intensity + 0.25, 1.0)
				# Body core area — slightly darker organic mass
				if d < r_inner * 0.9:
					intensity -= 0.05
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 3: enormous central eye
	var eye_r := r_inner * 0.75
	var pupil_r := eye_r * 0.4
	var iris_r := eye_r * 0.75
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= eye_r:
				var angle := atan2(dy, dx)
				if d <= pupil_r:
					# Dark abyss pupil with faint inner glow
					var pi_val := 0.08 + (1.0 - d / pupil_r) * 0.12
					img.set_pixel(x, y, Color(pi_val, pi_val, pi_val, 1.0))
				elif d <= iris_r:
					# Alien iris — radial fibers with bright ring
					var iris_t := (d - pupil_r) / (iris_r - pupil_r)
					var ray := absf(sin(angle * 12.0)) * 0.2
					var ring_bright := sin(iris_t * PI) * 0.25
					var ii := 0.4 + iris_t * 0.2 + ray + ring_bright
					img.set_pixel(x, y, Color(clampf(ii, 0.0, 1.0), clampf(ii, 0.0, 1.0), clampf(ii, 0.0, 1.0), 1.0))
				else:
					# Outer eye — sclera with blood vessels
					var sclera_t := (d - iris_r) / (eye_r - iris_r)
					var vein_e := absf(sin(angle * 8.0 + d)) * 0.1
					var si := 0.55 + (1.0 - sclera_t) * 0.15 + vein_e
					img.set_pixel(x, y, Color(clampf(si, 0.0, 1.0), clampf(si, 0.0, 1.0), clampf(si, 0.0, 1.0), 1.0))
	# Pass 4: eye catchlight
	var hl_x := cx - eye_r * 0.3
	var hl_y := cy - eye_r * 0.3
	for y in size:
		for x in size:
			var ddx := float(x) - hl_x
			var ddy := float(y) - hl_y
			if sqrt(ddx * ddx + ddy * ddy) <= pupil_r * 0.4:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.92))
	return ImageTexture.create_from_image(img)

## Alien Spore Pod — organic sphere, bio-veins, pressurized glow, spore tendrils
static func _bomb_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r := size * 0.42
	# Pass 1: spore tendril spikes radiating outward
	var num_tendrils := 8
	for i in num_tendrils:
		var angle := float(i) * TAU / float(num_tendrils) + 0.3
		var tendril_len := r * 0.45
		for s in range(0, int(tendril_len)):
			var st := float(s) / tendril_len
			var tx := cx + cos(angle) * (r * 0.85 + st * tendril_len * 0.5)
			var ty := cy + sin(angle) * (r * 0.85 + st * tendril_len * 0.5)
			# Wobble the tendril
			tx += sin(st * 5.0 + angle) * 1.5
			ty += cos(st * 5.0 + angle) * 1.5
			var thick := 2.0 - st * 1.5
			for ddy in range(-int(thick) - 1, int(thick) + 2):
				for ddx in range(-int(thick) - 1, int(thick) + 2):
					var px := int(tx) + ddx
					var py := int(ty) + ddy
					if px >= 0 and px < size and py >= 0 and py < size:
						var dd := sqrt(float(ddx * ddx + ddy * ddy))
						if dd <= thick:
							var ti := (1.0 - st) * 0.7 + 0.2
							var existing := img.get_pixel(px, py)
							if ti > existing.r or existing.a < 0.3:
								img.set_pixel(px, py, Color(clampf(ti, 0.0, 1.0), clampf(ti, 0.0, 1.0), clampf(ti, 0.0, 1.0), clampf(ti + 0.2, 0.0, 1.0)))
	# Pass 2: outer danger glow
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r and d <= r + 3.5:
				var fade := 1.0 - (d - r) / 3.5
				var angle := atan2(dy, dx)
				var pulse := absf(sin(angle * 5.0)) * 0.12
				var existing := img.get_pixel(x, y)
				var alpha := fade * (0.35 + pulse)
				if alpha > existing.a:
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	# Pass 3: main spore body
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= r:
				var norm_d := d / r
				# Spherical shading — pressurized look, very bright center
				var shade := (-dx / r * 0.3 - dy / r * 0.3) * 0.1
				# Bio-vein network radiating from center
				var angle := atan2(dy, dx)
				var vein1 := absf(sin(angle * 5.0 + d * 0.5))
				var vein2 := absf(sin(angle * 3.0 - d * 0.3 + 1.5))
				var vein := 0.0
				if vein1 < 0.08:
					vein = 0.15 * (1.0 - norm_d * 0.5)
				if vein2 < 0.06:
					vein = maxf(vein, 0.12 * (1.0 - norm_d * 0.5))
				# Pressurized glow — very bright center fading outward
				var intensity := 0.55 + (1.0 - norm_d) * 0.45 + shade + vein
				# Surface bumps (spore texture)
				var bump := sin(dx * 1.2) * sin(dy * 1.2) * 0.05
				intensity += bump
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 4: bright energy core (about to burst!)
	var core_r := r * 0.3
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= core_r:
				var ci := 0.85 + (1.0 - d / core_r) * 0.15
				img.set_pixel(x, y, Color(ci, ci, ci, 1.0))
	# Pass 5: specular highlight
	var hl_x := cx - r * 0.22
	var hl_y := cy - r * 0.22
	for y in size:
		for x in size:
			var ddx := float(x) - hl_x
			var ddy := float(y) - hl_y
			var d := sqrt(ddx * ddx + ddy * ddy)
			if d <= r * 0.18:
				var hi := 1.0 - d / (r * 0.18) * 0.15
				img.set_pixel(x, y, Color(hi, hi, hi, 1.0))
	return ImageTexture.create_from_image(img)

## Alien Cell / Amoeba — organic blob, cell membrane, two nuclei, organelles
static func _split_diamond_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	# Pass 1: translucent outer membrane glow
	for y in size:
		for x in size:
			var mx := absf(float(x) - cx) / (cx + 0.001)
			var my := absf(float(y) - cy) / (cy + 0.001)
			var d := mx + my
			if d > 1.0 and d <= 1.25:
				var fade := 1.0 - (d - 1.0) / 0.25
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.3))
	# Pass 2: cell body — translucent organic fill
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var mx := absf(dx) / (cx + 0.001)
			var my := absf(dy) / (cy + 0.001)
			var d := mx + my
			if d <= 1.0:
				# Base translucent cell fill
				var intensity := 0.55 + (1.0 - d) * 0.15
				# Cell membrane — bright ring near edge
				if d > 0.82:
					var mem_t := (d - 0.82) / 0.18
					intensity = 0.75 + sin(mem_t * PI) * 0.2
				# Inner cytoplasm texture — blobby organic look
				var blob := sin(dx * 0.6 + 0.5) * sin(dy * 0.5 + 0.3) * 0.08
				intensity += blob
				# Organelle dots — small darker spots scattered inside
				var org1 := sin(dx * 1.5 + dy * 0.8) * sin(dx * 0.7 - dy * 1.2)
				if absf(org1) < 0.04 and d < 0.7 and d > 0.3:
					intensity -= 0.1
				# Translucent edges
				if d > 0.7 and d <= 0.82:
					var alpha_edge := 0.85 + (0.82 - d) / 0.12 * 0.15
					img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(alpha_edge, 0.0, 1.0)))
				else:
					img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 3: two nuclei (foreshadowing split) — left and right of center
	for side: float in [-1.0, 1.0]:
		var nuc_cx := cx + side * cx * 0.28
		var nuc_cy := cy + side * cy * 0.08
		var nuc_r := cx * 0.22
		for y in size:
			for x in size:
				var ndx := float(x) - nuc_cx
				var ndy := float(y) - nuc_cy
				var nd := sqrt(ndx * ndx + ndy * ndy)
				# Check we are inside cell
				var mx := absf(float(x) - cx) / (cx + 0.001)
				var my := absf(float(y) - cy) / (cy + 0.001)
				if mx + my > 0.9:
					continue
				if nd <= nuc_r:
					var norm_nd := nd / nuc_r
					# Dense nucleus — darker center, bright ring
					var ni := 0.35 + norm_nd * 0.3
					# Chromatin texture inside
					var chrom := absf(sin(ndx * 2.0 + ndy * 1.5)) * 0.1
					ni += chrom
					# Bright nuclear membrane
					if norm_nd > 0.75:
						ni = 0.8 + (norm_nd - 0.75) / 0.25 * 0.15
					img.set_pixel(x, y, Color(clampf(ni, 0.0, 1.0), clampf(ni, 0.0, 1.0), clampf(ni, 0.0, 1.0), 1.0))
	# Pass 4: fission groove — faint line between nuclei hinting at splitting
	for y in size:
		var dy_off := float(y) - cy
		var my_check := absf(dy_off) / (cy + 0.001)
		if my_check > 0.85:
			continue
		for x in size:
			var ddx := absf(float(x) - cx)
			var emx := ddx / (cx + 0.001)
			var emy := absf(float(y) - cy) / (cy + 0.001)
			if emx + emy > 0.9:
				continue
			if ddx < 0.8:
				var existing := img.get_pixel(x, y)
				if existing.a > 0.5:
					var dimmed := clampf(existing.r - 0.12, 0.2, 1.0)
					img.set_pixel(x, y, Color(dimmed, dimmed, dimmed, existing.a))
			elif ddx < 2.0:
				var existing := img.get_pixel(x, y)
				if existing.a > 0.5:
					var brightened := clampf(existing.r + 0.08, 0.0, 1.0)
					img.set_pixel(x, y, Color(brightened, brightened, brightened, existing.a))
	return ImageTexture.create_from_image(img)

## Alien Guardian — creature with hexagonal energy shield bubble, multiple layers
static func _shield_hex_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r := size * 0.5 - 0.5
	# Pass 1: outer force field glow
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var hex_r := _hex_r(angle, r)
			if d > hex_r and d <= hex_r + 4.0:
				var fade := 1.0 - (d - hex_r) / 4.0
				var pulse := absf(sin(angle * 6.0 + d * 0.5)) * 0.15
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * (0.35 + pulse)))
	# Pass 2: outer shield shell with hex energy pattern
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var hex_r := _hex_r(angle, r)
			if d > hex_r:
				continue
			var norm_d := d / hex_r
			# Outer shield layer (hex-patterned energy field)
			if norm_d > 0.6:
				# Hexagonal energy grid on shield surface
				var grid_scale := 4.0
				var gx := dx * grid_scale / r
				var gy := dy * grid_scale / r
				var hx := gx - gy * 0.577
				var hy := gy * 1.155
				var cell_x: float = hx - floorf(hx)
				var cell_y: float = hy - floorf(hy)
				var cell_d := sqrt((cell_x - 0.5) * (cell_x - 0.5) + (cell_y - 0.5) * (cell_y - 0.5))
				var hex_line := 0.0
				if cell_d > 0.32:
					hex_line = 0.2
				# Shield intensity — brighter at rim
				var shield_i := 0.5 + (norm_d - 0.6) / 0.4 * 0.25 + hex_line
				# Concentric energy ring layers
				if absf(norm_d - 0.75) < 0.025:
					shield_i += 0.25
				if absf(norm_d - 0.90) < 0.025:
					shield_i += 0.2
				# Semi-transparent shield
				var alpha := 0.6 + (norm_d - 0.6) / 0.4 * 0.4
				img.set_pixel(x, y, Color(clampf(shield_i, 0.0, 1.0), clampf(shield_i, 0.0, 1.0), clampf(shield_i, 0.0, 1.0), clampf(alpha, 0.0, 1.0)))
			# Inner gap between shield and creature
			elif norm_d > 0.4 and norm_d <= 0.6:
				# Faint energy glow in the gap
				var gap_t := (norm_d - 0.4) / 0.2
				var gap_i := 0.3 + sin(gap_t * PI) * 0.15
				var angle_pulse := absf(sin(angle * 4.0)) * 0.08
				img.set_pixel(x, y, Color(clampf(gap_i + angle_pulse, 0.0, 1.0), clampf(gap_i + angle_pulse, 0.0, 1.0), clampf(gap_i + angle_pulse, 0.0, 1.0), 0.4))
	# Pass 3: inner alien creature body (small, centered)
	var body_r := r * 0.38
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= body_r:
				var norm_d := d / body_r
				var angle := atan2(dy, dx)
				# Alien body — organic with slight elongation
				var stretch := sqrt(dx * dx * 0.8 + dy * dy * 1.2) / body_r
				if stretch > 1.0:
					continue
				# Body texture
				var intensity := 0.75 - stretch * 0.2
				# Organic surface pattern
				var org := sin(dx * 1.5) * sin(dy * 1.5) * 0.06
				intensity += org
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 4: creature eye (centered, bright)
	var eye_r := body_r * 0.35
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= eye_r:
				var norm_d := d / eye_r
				if norm_d < 0.4:
					# Bright pupil
					var ei := 0.9 + (1.0 - norm_d / 0.4) * 0.1
					img.set_pixel(x, y, Color(ei, ei, ei, 1.0))
				else:
					# Dark iris ring
					var ei := 0.25 + (norm_d - 0.4) / 0.6 * 0.2
					img.set_pixel(x, y, Color(ei, ei, ei, 1.0))
	# Pass 5: shield energy struts (6 radial lines)
	for i in 6:
		var strut_angle := i * PI / 3.0 + PI / 6.0
		for s in range(int(r * 0.42), int(r * 0.92)):
			var sx := cx + cos(strut_angle) * float(s)
			var sy := cy + sin(strut_angle) * float(s)
			var isx := int(sx)
			var isy := int(sy)
			if isx >= 0 and isx < size and isy >= 0 and isy < size:
				var existing := img.get_pixel(isx, isy)
				var strut_i := 0.95
				if strut_i > existing.r or existing.a < 0.5:
					img.set_pixel(isx, isy, Color(strut_i, strut_i, strut_i, 1.0))
	return ImageTexture.create_from_image(img)

## Cross shape test helper.
static func _in_cross(px: int, py: int, cx: int, arm_w: int, arm_len: int) -> bool:
	var in_h := py >= cx - arm_w and py <= cx + arm_w and px >= cx - arm_len and px <= cx + arm_len
	var in_v := px >= cx - arm_w and px <= cx + arm_w and py >= cx - arm_len and py <= cx + arm_len
	return in_h or in_v

## Cross edge distance helper.
static func _cross_edge_dist(px: int, py: int, cx: int, arm_w: int, arm_len: int) -> float:
	if not _in_cross(px, py, cx, arm_w, arm_len):
		return -1.0
	var dx_left := float(px - (cx - arm_len))
	var dx_right := float((cx + arm_len) - px)
	var dy_top := float(py - (cx - arm_len))
	var dy_bottom := float((cx + arm_len) - py)
	var dw_left := float(px - (cx - arm_w))
	var dw_right := float((cx + arm_w) - px)
	var dh_top := float(py - (cx - arm_w))
	var dh_bottom := float((cx + arm_w) - py)
	var min_d := 999.0
	if py >= cx - arm_w and py <= cx + arm_w:
		min_d = minf(min_d, minf(dx_left, dx_right))
		min_d = minf(min_d, minf(dh_top, dh_bottom))
	if px >= cx - arm_w and px <= cx + arm_w:
		min_d = minf(min_d, minf(dy_top, dy_bottom))
		min_d = minf(min_d, minf(dw_left, dw_right))
	return maxf(min_d, 0.0)

## Alien Jellyfish — bell dome top, trailing bioluminescent tentacles, ethereal glow
static func _cross_plus_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx: int = int(float(size - 1) * 0.5)
	var fcx := float(cx)
	var arm_w := maxi(int(size * 0.24), 3)
	var arm_len := int(size * 0.44)
	# Pass 1: ethereal aura glow around cross shape
	for y in size:
		for x in size:
			if _in_cross(x, y, cx, arm_w, arm_len):
				continue
			var min_dist := 999.0
			for dy in range(-5, 6):
				for dx in range(-5, 6):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and nx < size and ny >= 0 and ny < size:
						if _in_cross(nx, ny, cx, arm_w, arm_len):
							var dd := sqrt(float(dx * dx + dy * dy))
							min_dist = minf(min_dist, dd)
			if min_dist <= 5.0:
				var fade := 1.0 - min_dist / 5.0
				var angle := atan2(float(y) - fcx, float(x) - fcx)
				var pulse := absf(sin(angle * 3.0)) * 0.1
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * (0.3 + pulse)))
	# Pass 2: fill cross shape with jellyfish texture
	for y in size:
		for x in size:
			if not _in_cross(x, y, cx, arm_w, arm_len):
				continue
			var dx := float(x) - fcx
			var dy := float(y) - fcx
			var dist_from_center := sqrt(dx * dx + dy * dy)
			var norm_dist := dist_from_center / float(arm_len)
			var edge_d: float = _cross_edge_dist(x, y, cx, arm_w, arm_len)
			# Bell dome (upper arm) — brighter, dome-like shading
			var is_upper := y < cx
			var is_lower := y > cx
			var intensity := 0.65
			if is_upper:
				# Dome: bright with spherical highlight
				var dome_t := float(cx - y) / float(arm_len)
				intensity = 0.8 - dome_t * 0.15
				# Dome curvature highlight
				if absf(dx) < float(arm_w) * 0.5 and dome_t > 0.2:
					intensity += 0.1
				# Internal organ glow visible through translucent bell
				var organ := sin(dx * 1.0 + dy * 0.8) * 0.08
				intensity += organ
			elif is_lower:
				# Tentacles (lower arm) — dimmer, wispy
				var tent_t := float(y - cx) / float(arm_len)
				intensity = 0.7 - tent_t * 0.3
				# Bioluminescent dots along tentacles
				var lum := sin(dy * 1.5) * sin(dx * 2.0)
				if absf(lum) < 0.1:
					intensity += 0.2 * (1.0 - tent_t)
			else:
				# Side arms (horizontal) — tentacle-like
				var side_t := absf(dx) / float(arm_len)
				intensity = 0.7 - side_t * 0.25
				# Bioluminescent pulses
				var lum := sin(dx * 1.2) * sin(dy * 1.8)
				if absf(lum) < 0.08:
					intensity += 0.15
			# Edge membrane glow
			if edge_d < 2.0:
				intensity = maxf(intensity, 0.85 + (1.0 - edge_d / 2.0) * 0.15)
			img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 3: inner organs visible in bell area — pulsing bright spots
	var organ_spots: Array[Vector2] = [
		Vector2(fcx - 2.0, fcx - float(arm_len) * 0.35),
		Vector2(fcx + 1.5, fcx - float(arm_len) * 0.25),
		Vector2(fcx, fcx - float(arm_len) * 0.15),
	]
	for spot in organ_spots:
		for dy in range(-2, 3):
			for ddx in range(-2, 3):
				var px := int(spot.x) + ddx
				var py := int(spot.y) + dy
				if px >= 0 and px < size and py >= 0 and py < size:
					if _in_cross(px, py, cx, arm_w, arm_len):
						var od := sqrt(float(ddx * ddx + dy * dy))
						if od <= 2.0:
							var oi := 0.5 + (1.0 - od / 2.0) * 0.3
							var existing := img.get_pixel(px, py)
							if oi < existing.r:
								img.set_pixel(px, py, Color(oi, oi, oi, 1.0))
	# Pass 4: bright central core
	for dy in range(-3, 4):
		for ddx in range(-3, 4):
			var px := cx + ddx
			var py := cx + dy
			if px >= 0 and px < size and py >= 0 and py < size:
				var cd := sqrt(float(ddx * ddx + dy * dy))
				if cd <= 3.0:
					var ci := 0.85 + (1.0 - cd / 3.0) * 0.15
					img.set_pixel(px, py, Color(ci, ci, ci, 1.0))
	return ImageTexture.create_from_image(img)

## Alien Insect — tiny bug with wings, compound eyes, antennae, fast and swarmy
static func _swarm_orb_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r := size * 0.5 - 0.5
	# Pass 1: wings — two translucent oval shapes spread outward
	for side: float in [-1.0, 1.0]:
		var wing_cx := cx + side * r * 0.5
		var wing_cy := cy - r * 0.1
		var wing_rx := r * 0.5
		var wing_ry := r * 0.35
		for y in size:
			for x in size:
				var wx := (float(x) - wing_cx) / wing_rx
				var wy := (float(y) - wing_cy) / wing_ry
				# Tilt wings slightly
				var twx := wx * 0.9 + wy * side * 0.2
				var twy := -wx * side * 0.2 + wy * 0.9
				var wd := sqrt(twx * twx + twy * twy)
				if wd <= 1.0:
					var norm_wd := wd
					# Wing membrane texture — veiny pattern
					var vein := absf(sin(twx * 5.0 + twy * 3.0)) * 0.1
					var wing_i := 0.55 + (1.0 - norm_wd) * 0.2 + vein
					# Wing edge highlight
					if norm_wd > 0.75:
						wing_i += (norm_wd - 0.75) / 0.25 * 0.15
					# Semi-transparent wings
					var alpha := 0.5 + (1.0 - norm_wd) * 0.3
					img.set_pixel(x, y, Color(clampf(wing_i, 0.0, 1.0), clampf(wing_i, 0.0, 1.0), clampf(wing_i, 0.0, 1.0), clampf(alpha, 0.0, 1.0)))
	# Pass 2: oval body (center, opaque)
	var body_rx := r * 0.35
	var body_ry := r * 0.55
	for y in size:
		for x in size:
			var bx := (float(x) - cx) / body_rx
			var by := (float(y) - cy) / body_ry
			var bd := sqrt(bx * bx + by * by)
			if bd <= 1.0:
				var norm_bd := bd
				# Body shading — segmented look
				var seg := absf(sin(by * 4.0)) * 0.08
				var intensity := 0.8 - norm_bd * 0.2 + seg
				# Thorax/abdomen division line
				if absf(by) < 0.06 and absf(bx) < 0.8:
					intensity -= 0.15
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 3: two compound eyes at top of body
	for side: float in [-1.0, 1.0]:
		var eye_cx := cx + side * body_rx * 0.55
		var eye_cy := cy - body_ry * 0.55
		var eye_r := r * 0.18
		for y in size:
			for x in size:
				var edx := float(x) - eye_cx
				var edy := float(y) - eye_cy
				var ed := sqrt(edx * edx + edy * edy)
				if ed <= eye_r:
					var norm_ed := ed / eye_r
					# Bright compound eye
					var ei := 0.85 + (1.0 - norm_ed) * 0.15
					img.set_pixel(x, y, Color(ei, ei, ei, 1.0))
	# Pass 4: antennae — two thin lines from head upward
	for side: float in [-1.0, 1.0]:
		var ant_bx := cx + side * body_rx * 0.3
		var ant_by := cy - body_ry * 0.8
		for s in range(0, 5):
			var st := float(s) / 4.0
			var ax := ant_bx + side * st * r * 0.3
			var ay := ant_by - st * r * 0.35
			var px := int(ax)
			var py := int(ay)
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, Color(0.8, 0.8, 0.8, 1.0))
				# Antenna tip dot
				if s == 4:
					if px + 1 < size:
						img.set_pixel(px + 1, py, Color(0.9, 0.9, 0.9, 1.0))
					if py + 1 < size:
						img.set_pixel(px, py + 1, Color(0.9, 0.9, 0.9, 1.0))
	return ImageTexture.create_from_image(img)

## Alien Phaser — dimensional distortion, spiral warp ring, void center, peering eye
static func _portal_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.45
	var eye_r := r_inner * 0.45
	var pupil_r := eye_r * 0.45
	# Pass 1: reality-distortion outer glow
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r_outer and d <= r_outer + 4.0:
				var fade := 1.0 - (d - r_outer) / 4.0
				var angle := atan2(dy, dx)
				# Warped spiral glow
				var warp := sin(angle * 5.0 + d * 0.8) * 0.2
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * (0.25 + absf(warp))))
	# Pass 2: outer warped-space spiral ring
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			if d >= r_inner and d <= r_outer:
				var ring_t := (d - r_inner) / (r_outer - r_inner)
				# Spiral arm pattern — multiple interleaved spirals
				var spiral1 := sin(angle * 3.0 + d * 0.8)
				var spiral2 := sin(angle * 3.0 + d * 0.8 + PI * 0.667)
				var spiral3 := sin(angle * 3.0 + d * 0.8 + PI * 1.333)
				var best_spiral := maxf(spiral1, maxf(spiral2, spiral3))
				var intensity := 0.5 + ring_t * 0.15 + best_spiral * 0.25
				# Bright rim at outer edge
				if ring_t > 0.85:
					intensity += (ring_t - 0.85) / 0.15 * 0.15
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 3: void between ring and eye — dark with faint tendrils
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d >= eye_r and d < r_inner:
				var angle := atan2(dy, dx)
				# Dark void with dimensional tears
				var tear := absf(sin(angle * 4.0 - d * 2.0))
				var void_i := 0.12 + tear * 0.2
				# Occasional bright streaks (dimensional fractures)
				if tear > 0.92:
					void_i = 0.7
				img.set_pixel(x, y, Color(clampf(void_i, 0.0, 1.0), clampf(void_i, 0.0, 1.0), clampf(void_i, 0.0, 1.0), clampf(void_i + 0.3, 0.0, 1.0)))
	# Pass 4: inner ring glow border
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if absf(d - r_inner) < 1.5:
				var ring_i := 1.0 - absf(d - r_inner) / 1.5 * 0.25
				img.set_pixel(x, y, Color(ring_i, ring_i, ring_i, 1.0))
	# Pass 5: central alien eye peering through dimensions
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= eye_r:
				var angle := atan2(dy, dx)
				if d <= pupil_r:
					# Abyss pupil — nearly black with faint glow
					var pi_val := 0.06 + (1.0 - d / pupil_r) * 0.1
					img.set_pixel(x, y, Color(pi_val, pi_val, pi_val, 1.0))
				else:
					# Alien iris with dimensional shimmer
					var iris_t := (d - pupil_r) / (eye_r - pupil_r)
					var ray := absf(sin(angle * 8.0)) * 0.2
					var shimmer := sin(angle * 3.0 + d * 2.0) * 0.1
					var ii := 0.45 + iris_t * 0.25 + ray + shimmer
					img.set_pixel(x, y, Color(clampf(ii, 0.0, 1.0), clampf(ii, 0.0, 1.0), clampf(ii, 0.0, 1.0), 1.0))
	# Pass 6: catchlight
	var hl_x := cx - eye_r * 0.3
	var hl_y := cy - eye_r * 0.3
	for y in size:
		for x in size:
			var ddx := float(x) - hl_x
			var ddy := float(y) - hl_y
			if sqrt(ddx * ddx + ddy * ddy) <= pupil_r * 0.45:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.9))
	return ImageTexture.create_from_image(img)

## Alien Beast — rhino/bull creature charging forward, massive horn, armored head
static func _ram_skull_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	var fh := float(h - 1)
	# Pass 1: main body — wedge-shaped alien beast, wider at back (bottom), narrow at front (top)
	for y in h:
		var t := float(y) / maxf(fh, 1.0)
		# Shape: narrow horn at top, widening to muscular body
		var half_w := 0.0
		if t < 0.15:
			# Horn — very narrow, tapering to point
			half_w = t / 0.15 * cx * 0.15
		elif t < 0.35:
			# Armored head — expanding
			var head_t := (t - 0.15) / 0.2
			half_w = cx * 0.15 + head_t * cx * 0.55
		else:
			# Muscular body — wide, slightly tapering at rear
			var body_t := (t - 0.35) / 0.65
			half_w = cx * 0.7 + body_t * cx * 0.15 - body_t * body_t * cx * 0.2
		for x in w:
			var dx := absf(float(x) - cx)
			if dx <= half_w and half_w > 0.5:
				var norm_dx := dx / maxf(half_w, 0.001)
				var intensity := 0.0
				if t < 0.15:
					# Horn: bright, ridged
					var ridge := absf(sin(t * 60.0)) * 0.08
					intensity = 1.0 - t / 0.15 * 0.2 + ridge
				elif t < 0.35:
					# Armored head plates — bright with plate lines
					var head_t := (t - 0.15) / 0.2
					intensity = 0.9 - head_t * 0.1
					# Plate segment lines
					if absf(head_t - 0.4) < 0.03 or absf(head_t - 0.7) < 0.03:
						intensity -= 0.2
					# Center ridge
					if dx < half_w * 0.1:
						intensity += 0.1
				else:
					# Muscular body with alien texture
					var body_t := (t - 0.35) / 0.65
					intensity = 0.8 - body_t * 0.15
					# Muscle segment texture
					var muscle := sin(t * 18.0) * sin(dx * 0.5) * 0.06
					intensity += muscle
				# Edge darkening
				if norm_dx > 0.75:
					intensity -= (norm_dx - 0.75) * 0.4
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 2: alien eyes on sides of head
	var eye_y := h * 0.25
	for side: float in [-1.0, 1.0]:
		var eye_cx := cx + side * cx * 0.4
		var eye_cy := eye_y
		for dy in range(-3, 4):
			for ddx in range(-2, 3):
				var px := int(eye_cx) + ddx
				var py := int(eye_cy) + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					var ed := sqrt(float(ddx * ddx) * 1.0 + float(dy * dy) * 0.6)
					if ed <= 2.5:
						# Dark socket
						img.set_pixel(px, py, Color(0.12, 0.12, 0.12, 1.0))
					if ed <= 1.5:
						# Bright glowing eye
						var gi := 0.85 + (1.0 - ed / 1.5) * 0.15
						img.set_pixel(px, py, Color(gi, gi, gi, 1.0))
	# Pass 3: small tusk/horn details on sides of head
	for side: float in [-1.0, 1.0]:
		var tusk_bx := cx + side * cx * 0.55
		var tusk_by := float(int(h * 0.32))
		for s in range(0, 8):
			var st := float(s) / 7.0
			var tx := tusk_bx + side * st * cx * 0.3
			var ty := tusk_by + st * fh * 0.06 - st * st * fh * 0.03
			var thick := 2.0 - st * 1.5
			for ddy in range(-int(thick) - 1, int(thick) + 2):
				for ddx in range(-int(thick) - 1, int(thick) + 2):
					var px := int(tx) + ddx
					var py := int(ty) + ddy
					if px >= 0 and px < w and py >= 0 and py < h:
						var dd := sqrt(float(ddx * ddx + ddy * ddy))
						if dd <= thick:
							var ti := 0.95 - st * 0.25
							var existing := img.get_pixel(px, py)
							if ti > existing.r or existing.a < 0.5:
								img.set_pixel(px, py, Color(clampf(ti, 0.0, 1.0), clampf(ti, 0.0, 1.0), clampf(ti, 0.0, 1.0), 1.0))
	# Pass 4: nostril slits
	var nose_y := int(h * 0.18)
	for side: float in [-1.0, 1.0]:
		var nx := int(cx + side * 1.5)
		if nx >= 0 and nx < w and nose_y >= 0 and nose_y < h:
			img.set_pixel(nx, nose_y, Color(0.25, 0.25, 0.25, 1.0))
			if nose_y + 1 < h:
				img.set_pixel(nx, nose_y + 1, Color(0.25, 0.25, 0.25, 1.0))
	# Pass 5: glow outline around entire shape
	var base := img.duplicate()
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.1:
				var near := false
				for dy in range(-2, 3):
					for ddx in range(-2, 3):
						var nbx := x + ddx
						var nby := y + dy
						if nbx >= 0 and nbx < w and nby >= 0 and nby < h:
							if base.get_pixel(nbx, nby).a > 0.5:
								near = true
								break
					if near:
						break
				if near:
					var dd := 999.0
					for dy in range(-2, 3):
						for ddx in range(-2, 3):
							var nbx := x + ddx
							var nby := y + dy
							if nbx >= 0 and nbx < w and nby >= 0 and nby < h:
								if base.get_pixel(nbx, nby).a > 0.5:
									dd = minf(dd, sqrt(float(ddx * ddx + dy * dy)))
					var alpha := (1.0 - dd / 2.5) * 0.3
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 0.3)))
	return ImageTexture.create_from_image(img)
