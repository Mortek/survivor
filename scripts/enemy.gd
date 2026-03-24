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
			func() -> void: if Engine.time_scale < 0.9: Engine.time_scale = 1.0
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

## Menacing eye with radiating spikes and pulsing inner glow — base enemy
static func _spiky_circle_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.52
	var spikes := 12
	# Pass 1: outer glow halo
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r_outer and d <= r_outer + 3.0:
				var fade := 1.0 - (d - r_outer) / 3.0
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.25))
	# Pass 2: spiky body with layered intensity
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var spike_angle := fmod(angle + TAU, TAU / float(spikes))
			var t := absf(spike_angle - (TAU / float(spikes)) * 0.5) / (TAU / float(spikes) * 0.5)
			# Sharp spike falloff
			var spike_t := t * t * t * 0.55
			var r_at_angle: float = lerpf(r_outer, r_inner, spike_t)
			if d <= r_at_angle:
				var norm_d := d / r_at_angle
				# Radial gradient with ring bands
				var ring := absf(sin(norm_d * PI * 3.0)) * 0.12
				var intensity := 1.0 - norm_d * 0.35 + ring
				# Spike tip brightening
				if t < 0.3 and norm_d > 0.7:
					intensity = minf(intensity + 0.15, 1.0)
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			elif d <= r_at_angle + 1.5:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.35))
	# Pass 3: menacing eye — iris ring + dark pupil + bright catchlight
	var eye_r := r_inner * 0.45
	var pupil_r := eye_r * 0.45
	var iris_inner := pupil_r * 1.4
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= eye_r:
				if d <= pupil_r:
					# Dark pupil
					img.set_pixel(x, y, Color(0.15, 0.15, 0.15, 1.0))
				elif d <= iris_inner:
					# Iris bright ring
					var iris_t := (d - pupil_r) / (iris_inner - pupil_r)
					var i := 0.3 + iris_t * 0.5
					img.set_pixel(x, y, Color(i, i, i, 1.0))
				else:
					# Outer iris — radial streaks
					var angle := atan2(dy, dx)
					var streak := absf(sin(angle * 8.0)) * 0.2
					var i := 0.55 + streak
					img.set_pixel(x, y, Color(i, i, i, 1.0))
	# Catchlight highlight
	var hl_x := cx - eye_r * 0.3
	var hl_y := cy - eye_r * 0.3
	for y in size:
		for x in size:
			var dx := float(x) - hl_x
			var dy := float(y) - hl_y
			var d := sqrt(dx * dx + dy * dy)
			if d <= pupil_r * 0.45:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.9))
	return ImageTexture.create_from_image(img)

## Jagged lightning bolt with crackling energy and glowing edges — fast enemy
static func _lightning_bolt_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	# Main bolt: sharper zigzag with more segments
	var segments: Array[Vector2] = [
		Vector2(cx + 4.0, 0.0),
		Vector2(cx - 4.0, h * 0.18),
		Vector2(cx + 2.0, h * 0.22),
		Vector2(cx - 3.0, h * 0.40),
		Vector2(cx + 5.0, h * 0.36),
		Vector2(cx - 2.0, h * 0.58),
		Vector2(cx + 3.0, h * 0.55),
		Vector2(cx - 1.0, h * 0.75),
		Vector2(cx + 2.0, h * 0.72),
		Vector2(cx, float(h - 1)),
	]
	# Branch bolts for crackling effect
	var branches: Array[Array] = []
	branches.append([Vector2(cx - 4.0, h * 0.18), Vector2(cx - 7.0, h * 0.28)])
	branches.append([Vector2(cx + 5.0, h * 0.36), Vector2(cx + 8.0, h * 0.44)])
	branches.append([Vector2(cx - 2.0, h * 0.58), Vector2(cx - 6.0, h * 0.66)])
	# Draw all pixels
	for y in h:
		for x in w:
			var px := float(x)
			var py := float(y)
			var min_dist := 999.0
			# Main bolt segments
			for i in range(segments.size() - 1):
				var dd := _pt_seg_dist(px, py, segments[i], segments[i + 1])
				min_dist = minf(min_dist, dd)
			# Branch segments (thinner)
			var branch_dist := 999.0
			for br: Array in branches:
				var dd := _pt_seg_dist(px, py, br[0] as Vector2, br[1] as Vector2)
				branch_dist = minf(branch_dist, dd)
			# Main bolt core (width 3.5)
			if min_dist <= 3.5:
				var core_t := min_dist / 3.5
				var intensity := 1.0 - core_t * 0.3
				# Bright white-hot center line
				if min_dist <= 1.0:
					intensity = 1.0
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			# Main bolt electric edge glow
			elif min_dist <= 6.0:
				var glow_t := (min_dist - 3.5) / 2.5
				var alpha := (1.0 - glow_t) * 0.4
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
			# Branch bolts (thinner)
			if branch_dist <= 2.0:
				var bt := branch_dist / 2.0
				var bi := 0.85 - bt * 0.25
				var existing := img.get_pixel(x, y)
				if existing.a < 0.5:
					img.set_pixel(x, y, Color(bi, bi, bi, 1.0))
			elif branch_dist <= 4.0 and img.get_pixel(x, y).a < 0.1:
				var gt := (branch_dist - 2.0) / 2.0
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, (1.0 - gt) * 0.2))
	# Spark dots at tips and junctions
	var spark_points: Array[Vector2] = [segments[0], segments[segments.size() - 1]]
	for br: Array in branches:
		spark_points.append(br[1] as Vector2)
	for sp in spark_points:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var sx := int(sp.x) + dx
				var sy := int(sp.y) + dy
				if sx >= 0 and sx < w and sy >= 0 and sy < h:
					var sd := sqrt(float(dx * dx + dy * dy))
					if sd <= 3.0:
						var sa := (1.0 - sd / 3.0) * 0.7
						var existing := img.get_pixel(sx, sy)
						if sa > existing.a:
							img.set_pixel(sx, sy, Color(1.0, 1.0, 1.0, sa))
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

## Heavy armored hexagon with plates, rivets, and reinforcement — tank
static func _armored_hex_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r := size * 0.5 - 0.5
	# Pass 1: outer glow
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var hex_r := _hex_r(angle, r)
			if d > hex_r and d <= hex_r + 3.0:
				var fade := 1.0 - (d - hex_r) / 3.0
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.25))
	# Pass 2: main hex body with layered armor
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var hex_r := _hex_r(angle, r)
			if d > hex_r:
				continue
			var outer_rim := hex_r * 0.88
			var mid_plate := hex_r * 0.72
			var inner_ring := hex_r * 0.50
			var core_r := hex_r * 0.28
			# Plate seam lines (6 radial lines from center to edge)
			var seam_angle := fmod(angle + TAU, PI / 3.0)
			var seam_dist := absf(seam_angle - PI / 6.0) * d
			var on_seam := seam_dist < 0.8 and d > core_r and d < outer_rim
			if on_seam:
				img.set_pixel(x, y, Color(0.35, 0.35, 0.35, 1.0))
			elif d > outer_rim:
				# Heavy outer rim — beveled look
				var rim_t := (d - outer_rim) / (hex_r - outer_rim)
				var i := 0.65 + (1.0 - rim_t) * 0.2
				img.set_pixel(x, y, Color(i, i, i, 1.0))
			elif d > mid_plate:
				# Middle armor plate with subtle bevel
				var plate_t := (d - mid_plate) / (outer_rim - mid_plate)
				var i := 0.9 + plate_t * 0.1
				img.set_pixel(x, y, Color(i, i, i, 1.0))
			elif d > inner_ring:
				# Inner reinforcement ring groove
				var ring_t := (d - inner_ring) / (mid_plate - inner_ring)
				var groove := absf(sin(ring_t * PI * 2.0)) * 0.15
				var i := 0.75 + groove
				img.set_pixel(x, y, Color(i, i, i, 1.0))
			elif d > core_r:
				# Inner plate
				var i := 0.6 + (1.0 - d / inner_ring) * 0.2
				img.set_pixel(x, y, Color(i, i, i, 1.0))
			else:
				# Bright core
				var core_t := d / core_r
				var i := 1.0 - core_t * 0.15
				img.set_pixel(x, y, Color(i, i, i, 1.0))
	# Pass 3: rivet dots at each hex corner on the outer rim
	for i in 6:
		var a := i * PI / 3.0
		var rivet_d := r * 0.82
		var rx := cx + cos(a) * rivet_d
		var ry := cy + sin(a) * rivet_d
		for y in size:
			for x in size:
				var ddx := float(x) - rx
				var ddy := float(y) - ry
				var dd := sqrt(ddx * ddx + ddy * ddy)
				if dd <= 2.0:
					var ri := 1.0 - dd * 0.2
					img.set_pixel(x, y, Color(ri, ri, ri, 1.0))
				elif dd <= 3.0:
					var existing := img.get_pixel(x, y)
					if existing.a > 0.5:
						img.set_pixel(x, y, Color(0.5, 0.5, 0.5, 1.0))
	return ImageTexture.create_from_image(img)

## Crown-like menacing star with inner energy pattern — boss
static func _star_shape_tex(size: int, points: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.35
	var sector_angle := TAU / float(points)
	# Pass 1: wide outer glow halo
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var a_mod := fmod(angle + TAU + sector_angle * 0.5, sector_angle) - sector_angle * 0.5
			var t := absf(a_mod) / (sector_angle * 0.5)
			var r_star: float = lerpf(r_outer, r_inner, t)
			if d > r_star and d <= r_star + 3.5:
				var fade := 1.0 - (d - r_star) / 3.5
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.3))
	# Pass 2: star body with sharp points and crown-like serrations
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var a_mod := fmod(angle + TAU + sector_angle * 0.5, sector_angle) - sector_angle * 0.5
			var t := absf(a_mod) / (sector_angle * 0.5)
			# Sharper point falloff for more menacing look
			var sharp_t := t * t
			var r_star: float = lerpf(r_outer, r_inner, sharp_t)
			if d <= r_star:
				var norm_d := d / r_star
				# Inner energy: concentric rings rotating pattern
				var ring_pattern := absf(sin(d * 1.2 + angle * 2.0)) * 0.12
				# Radial energy beams from center
				var beam := absf(sin(angle * float(points) * 0.5)) * 0.08 * (1.0 - norm_d)
				var intensity := 1.0 - norm_d * 0.3 + ring_pattern + beam
				# Bright edge highlight on star tips
				if t < 0.2 and norm_d > 0.65:
					intensity = minf(intensity + 0.2, 1.0)
				intensity = clampf(intensity, 0.0, 1.0)
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Pass 3: crown-like notch markers between each star point
	for i in points:
		var notch_angle := sector_angle * float(i)
		var notch_d := r_inner * 1.1
		var nx_pos := cx + cos(notch_angle) * notch_d
		var ny_pos := cy + sin(notch_angle) * notch_d
		for y in size:
			for x in size:
				var ddx := float(x) - nx_pos
				var ddy := float(y) - ny_pos
				var dd := sqrt(ddx * ddx + ddy * ddy)
				if dd <= 2.0:
					var ni := 0.4 + (1.0 - dd / 2.0) * 0.3
					img.set_pixel(x, y, Color(ni, ni, ni, 1.0))
	# Pass 4: central energy core — bright orb with dark ring
	var core_r := r_inner * 0.55
	var dark_ring_inner := core_r * 0.55
	var dark_ring_outer := core_r * 0.75
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= core_r:
				if d >= dark_ring_inner and d <= dark_ring_outer:
					# Dark energy ring
					img.set_pixel(x, y, Color(0.3, 0.3, 0.3, 1.0))
				elif d < dark_ring_inner:
					# Blazing bright center
					var ci := 1.0 - (d / dark_ring_inner) * 0.15
					img.set_pixel(x, y, Color(ci, ci, ci, 1.0))
				else:
					var ci := 0.55 + (1.0 - (d - dark_ring_outer) / (core_r - dark_ring_outer)) * 0.3
					img.set_pixel(x, y, Color(ci, ci, ci, 1.0))
	return ImageTexture.create_from_image(img)

## Detailed bomb with wick sparks, danger markings, and inner glow — exploder
static func _bomb_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5 + 2.0
	var r := size * 0.38
	# Pass 1: danger glow halo
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r and d <= r + 4.0:
				var fade := 1.0 - (d - r) / 4.0
				# Pulsating danger glow with angular variation
				var angle := atan2(dy, dx)
				var danger_pulse := absf(sin(angle * 4.0)) * 0.1
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, (fade * 0.3) + danger_pulse * fade))
	# Pass 2: bomb body with shading and danger band
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= r:
				var norm_d := d / r
				var angle := atan2(dy, dx)
				# Spherical shading: bright upper-left, dark lower-right
				var shade_dx := dx / r
				var shade_dy := dy / r
				var shade := (-shade_dx * 0.3 - shade_dy * 0.3) * 0.15
				# Danger stripe band around equator
				var band := 0.0
				if absf(norm_d - 0.65) < 0.08:
					# Chevron pattern in the band
					var chevron := fmod(angle + TAU, PI * 0.5) / (PI * 0.5)
					band = -0.25 if chevron < 0.5 else 0.0
				var intensity := clampf(0.85 - norm_d * 0.2 + shade + band, 0.0, 1.0)
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Pass 3: top cap / nozzle
	var nozzle_cx := cx + 1.0
	var nozzle_cy := cy - r + 1.0
	for y in size:
		for x in size:
			var dx := float(x) - nozzle_cx
			var dy := float(y) - nozzle_cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= 3.0:
				var ni := 0.7 + (1.0 - d / 3.0) * 0.3
				img.set_pixel(x, y, Color(ni, ni, ni, 1.0))
	# Pass 4: fuse — curved wick
	var fuse_base_x := nozzle_cx + 1.0
	var fuse_base_y := nozzle_cy - 1.0
	for fy in range(0, int(fuse_base_y) + 1):
		var t := float(fy) / maxf(fuse_base_y, 1.0)
		var fwick_x := fuse_base_x + sin(t * 3.0) * 2.5
		var fwick_y := float(fy)
		for dx in range(-1, 2):
			var px := int(fwick_x) + dx
			if px >= 0 and px < size and int(fwick_y) >= 0 and int(fwick_y) < size:
				var dist := absf(float(px) - fwick_x)
				var wi := 1.0 - dist * 0.3
				img.set_pixel(px, int(fwick_y), Color(wi, wi, wi, 1.0))
	# Pass 5: big spark burst at fuse tip
	var spark_cx := fuse_base_x + sin(0.0) * 2.5
	var spark_cy := 0.0
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var sx := int(spark_cx) + dx
			var sy := int(spark_cy) + dy
			if sx >= 0 and sx < size and sy >= 0 and sy < size:
				var sd := sqrt(float(dx * dx + dy * dy))
				if sd <= 4.0:
					# Star-shaped spark
					var sa := atan2(float(dy), float(dx))
					var star_mod := absf(sin(sa * 3.0)) * 0.4
					var spark_i := (1.0 - sd / 4.0) * (0.8 + star_mod)
					if spark_i > img.get_pixel(sx, sy).a:
						img.set_pixel(sx, sy, Color(1.0, 1.0, 1.0, clampf(spark_i, 0.0, 1.0)))
	# Pass 6: specular highlight
	var hl_r := r * 0.25
	var hl_cx := cx - r * 0.25
	var hl_cy := cy - r * 0.25
	for y in size:
		for x in size:
			var dx := float(x) - hl_cx
			var dy := float(y) - hl_cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= hl_r:
				var hi := 1.0 - (d / hl_r) * 0.3
				img.set_pixel(x, y, Color(hi, hi, hi, 1.0))
	# Pass 7: inner core glow at center (danger!)
	var glow_r := r * 0.2
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= glow_r:
				var gi := 0.65 + (1.0 - d / glow_r) * 0.35
				img.set_pixel(x, y, Color(gi, gi, gi, 1.0))
	return ImageTexture.create_from_image(img)

## Fractured crystal with glowing crack energy and facets — splitter
static func _split_diamond_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	# Pass 1: outer crystal glow
	for y in size:
		for x in size:
			var mx := absf(float(x) - cx) / (cx + 0.001)
			var my := absf(float(y) - cy) / (cy + 0.001)
			var d := mx + my
			if d > 1.0 and d <= 1.2:
				var fade := 1.0 - (d - 1.0) / 0.2
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.35))
	# Pass 2: crystal body with faceted shading
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var mx := absf(dx) / (cx + 0.001)
			var my := absf(dy) / (cy + 0.001)
			var d := mx + my
			if d <= 1.0:
				# Which quadrant for facet shading
				var facet_shade := 0.0
				if dx >= 0.0 and dy < 0.0:
					facet_shade = 0.1  # top-right: brightest
				elif dx < 0.0 and dy < 0.0:
					facet_shade = 0.05  # top-left
				elif dx < 0.0 and dy >= 0.0:
					facet_shade = -0.05  # bottom-left
				else:
					facet_shade = -0.1  # bottom-right: darkest
				# Edge brightening
				var edge_glow := 0.0
				if d > 0.8:
					edge_glow = (d - 0.8) / 0.2 * 0.15
				# Inner refraction lines
				var refract := absf(sin(dx * 0.8 + dy * 0.6)) * 0.08
				var intensity := clampf(0.85 - d * 0.2 + facet_shade + edge_glow + refract, 0.0, 1.0)
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Pass 3: diagonal facet lines (crystal edges)
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var mx := absf(dx) / (cx + 0.001)
			var my := absf(dy) / (cy + 0.001)
			var d := mx + my
			if d > 1.0:
				continue
			# Horizontal facet seam
			if absf(dy) < 1.0 and d < 0.9:
				img.set_pixel(x, y, Color(0.55, 0.55, 0.55, 1.0))
			# Vertical facet seam (this will become the crack zone)
			# Diagonal facet lines from corners to center
			var diag_dist := absf(absf(dx) - absf(dy))
			if diag_dist < 0.8 and d > 0.15 and d < 0.85:
				var existing := img.get_pixel(x, y)
				var dimmed := clampf(existing.r - 0.15, 0.3, 1.0)
				img.set_pixel(x, y, Color(dimmed, dimmed, dimmed, 1.0))
	# Pass 4: main crack — jagged line down the center with energy glow
	for y in size:
		var t := float(y) / float(size - 1)
		var crack_offset := sin(t * 8.0) * 2.0 + sin(t * 13.0) * 1.0
		var crack_center := cx + crack_offset
		var mx_at := absf(crack_offset) / (cx + 0.001)
		var my_at := absf(float(y) - cy) / (cy + 0.001)
		if mx_at + my_at > 0.95:
			continue
		for x in size:
			var dist_to_crack := absf(float(x) - crack_center)
			var mx := absf(float(x) - cx) / (cx + 0.001)
			var my := absf(float(y) - cy) / (cy + 0.001)
			if mx + my > 1.0:
				continue
			if dist_to_crack < 0.8:
				# Dark crack core
				img.set_pixel(x, y, Color(0.15, 0.15, 0.15, 1.0))
			elif dist_to_crack < 2.5:
				# Bright energy glow along crack edges
				var glow_t := (dist_to_crack - 0.8) / 1.7
				var gi := 1.0 - glow_t * 0.3
				img.set_pixel(x, y, Color(gi, gi, gi, 1.0))
	# Pass 5: secondary cracks branching off
	var branch_cracks: Array[Array] = []
	branch_cracks.append([Vector2(cx, cy - cy * 0.3), Vector2(cx + cx * 0.5, cy - cy * 0.6)])
	branch_cracks.append([Vector2(cx, cy + cy * 0.2), Vector2(cx - cx * 0.4, cy + cy * 0.5)])
	for crack: Array in branch_cracks:
		var ca := crack[0] as Vector2
		var cb := crack[1] as Vector2
		var steps := int(ca.distance_to(cb))
		for s in steps:
			var st := float(s) / maxf(float(steps - 1), 1.0)
			var px := ca.x + (cb.x - ca.x) * st
			var py := ca.y + (cb.y - ca.y) * st
			var ix := int(px)
			var iy := int(py)
			if ix >= 0 and ix < size and iy >= 0 and iy < size:
				var mx := absf(float(ix) - cx) / (cx + 0.001)
				var my := absf(float(iy) - cy) / (cy + 0.001)
				if mx + my <= 0.92:
					img.set_pixel(ix, iy, Color(0.2, 0.2, 0.2, 1.0))
					# Tiny glow beside branch cracks
					for ddx in range(-1, 2):
						var nx := ix + ddx
						if nx >= 0 and nx < size:
							var emx := absf(float(nx) - cx) / (cx + 0.001)
							if emx + my <= 0.92 and img.get_pixel(nx, iy).r > 0.5:
								img.set_pixel(nx, iy, Color(0.95, 0.95, 0.95, 1.0))
	return ImageTexture.create_from_image(img)

## Layered shield hex with energy barriers and hex pattern — shielder
static func _shield_hex_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r := size * 0.5 - 0.5
	# Pass 1: outer energy barrier glow (shifted outward)
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var hex_r := _hex_r(angle, r)
			if d > hex_r and d <= hex_r + 4.0:
				var fade := 1.0 - (d - hex_r) / 4.0
				# Pulsating barrier effect
				var pulse := absf(sin(angle * 6.0)) * 0.15
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * (0.3 + pulse)))
	# Pass 2: main hex body with layered shields
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
			# Outer shield rim
			if norm_d > 0.88:
				var rim_t := (norm_d - 0.88) / 0.12
				var i := 0.7 + rim_t * 0.3
				img.set_pixel(x, y, Color(i, i, i, 1.0))
			# Energy barrier ring 1
			elif absf(norm_d - 0.78) < 0.03:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
			# Shield plate
			elif norm_d > 0.55:
				var plate_t := (norm_d - 0.55) / 0.23
				var i := 0.75 + plate_t * 0.15
				img.set_pixel(x, y, Color(i, i, i, 1.0))
			# Energy barrier ring 2
			elif absf(norm_d - 0.48) < 0.03:
				img.set_pixel(x, y, Color(0.95, 0.95, 0.95, 1.0))
			# Inner hex fill with small hex tiling pattern
			elif norm_d > 0.15:
				# Tiny hex grid pattern inside
				var grid_scale := 5.0
				var gx := dx * grid_scale / r
				var gy := dy * grid_scale / r
				# Approximate hex grid distance
				var hx := gx - gy * 0.577
				var hy := gy * 1.155
				var cell_x: float = hx - floorf(hx)
				var cell_y: float = hy - floorf(hy)
				var cell_center_d := sqrt((cell_x - 0.5) * (cell_x - 0.5) + (cell_y - 0.5) * (cell_y - 0.5))
				var hex_pattern := 0.0
				if cell_center_d > 0.35:
					hex_pattern = -0.12
				var i := clampf(0.7 + (0.55 - norm_d) * 0.3 + hex_pattern, 0.0, 1.0)
				img.set_pixel(x, y, Color(i, i, i, 1.0))
			else:
				# Core — bright center
				var ci := 0.9 + (1.0 - norm_d / 0.15) * 0.1
				img.set_pixel(x, y, Color(ci, ci, ci, 1.0))
	# Pass 3: radial shield struts (6 lines from center to edge)
	for i in 6:
		var strut_angle := i * PI / 3.0 + PI / 6.0
		for s in range(int(r * 0.2), int(r * 0.88)):
			var sx := cx + cos(strut_angle) * float(s)
			var sy := cy + sin(strut_angle) * float(s)
			var ix := int(sx)
			var iy := int(sy)
			if ix >= 0 and ix < size and iy >= 0 and iy < size:
				var existing := img.get_pixel(ix, iy)
				if existing.a > 0.5:
					var dimmed := clampf(existing.r - 0.2, 0.35, 0.9)
					img.set_pixel(ix, iy, Color(dimmed, dimmed, dimmed, 1.0))
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

## Glowing medical cross with pulsing aura and heart center — healer
static func _cross_plus_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx: int = int(float(size - 1) * 0.5)
	var fcx := float(cx)
	var arm_w := maxi(int(size * 0.24), 3)
	var arm_len := int(size * 0.44)
	# Pass 1: outer aura glow
	for y in size:
		for x in size:
			if _in_cross(x, y, cx, arm_w, arm_len):
				continue
			# Find minimum distance to cross border
			var min_dist := 999.0
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and nx < size and ny >= 0 and ny < size:
						if _in_cross(nx, ny, cx, arm_w, arm_len):
							var dd := sqrt(float(dx * dx + dy * dy))
							min_dist = minf(min_dist, dd)
			if min_dist <= 4.0:
				var fade := 1.0 - min_dist / 4.0
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.35))
	# Pass 2: cross body with gradient and inner glow pattern
	for y in size:
		for x in size:
			if not _in_cross(x, y, cx, arm_w, arm_len):
				continue
			var edge_d: float = _cross_edge_dist(x, y, cx, arm_w, arm_len)
			var dist_from_center := sqrt((float(x) - fcx) * (float(x) - fcx) + (float(y) - fcx) * (float(y) - fcx))
			var norm_dist := dist_from_center / float(arm_len)
			# Bright edges, slightly dimmer interior with pulse pattern
			var edge_bright := 0.0
			if edge_d < 2.0:
				edge_bright = (1.0 - edge_d / 2.0) * 0.15
			var intensity := clampf(0.85 - norm_dist * 0.15 + edge_bright, 0.0, 1.0)
			img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Pass 3: inner bevel — darker outline 1px inside the cross
	for y in size:
		for x in size:
			if not _in_cross(x, y, cx, arm_w, arm_len):
				continue
			var edge_d: float = _cross_edge_dist(x, y, cx, arm_w, arm_len)
			if edge_d >= 0.0 and edge_d < 1.5:
				var existing := img.get_pixel(x, y)
				var beveled := clampf(existing.r + 0.1, 0.0, 1.0)
				img.set_pixel(x, y, Color(beveled, beveled, beveled, 1.0))
	# Pass 4: heart shape at center
	var heart_size := float(arm_w) * 0.7
	for y in size:
		for x in size:
			var hx := (float(x) - fcx) / heart_size
			var hy := (float(y) - fcx) / heart_size - 0.1
			# Heart equation: (x^2 + y^2 - 1)^3 - x^2 * y^3 <= 0
			var hx2 := hx * hx
			var hy2 := hy * hy
			var val := (hx2 + hy2 - 1.0)
			val = val * val * val - hx2 * hy * hy2
			if val <= 0.0:
				# Dark heart with bright center
				var heart_d := sqrt(hx2 + hy2)
				var hi := 0.35 + (1.0 - heart_d) * 0.25
				img.set_pixel(x, y, Color(hi, hi, hi, 1.0))
			elif val <= 0.15:
				# Heart glow border
				var existing := img.get_pixel(x, y)
				if existing.a > 0.5:
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

## Buzzing energy orb with swirl patterns and glowing nucleus — swarm
static func _swarm_orb_tex(size: int) -> ImageTexture:
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
			if d > r and d <= r + 3.0:
				var fade := 1.0 - (d - r) / 3.0
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * 0.3))
	# Pass 2: orb body with swirl energy pattern
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r:
				continue
			var norm_d := d / r
			var angle := atan2(dy, dx)
			# Spiral swirl pattern: angle + distance creates spiral arms
			var spiral := sin(angle * 3.0 + norm_d * 8.0) * 0.12
			# Radial falloff — bright center, dimmer edges
			var base_i := 1.0 - norm_d * 0.45
			# Buzzing/stipple energy near edge
			var buzz := 0.0
			if norm_d > 0.6:
				var buzz_angle := angle * 7.0 + d * 2.0
				buzz = sin(buzz_angle) * 0.1 * ((norm_d - 0.6) / 0.4)
			var intensity := clampf(base_i + spiral + buzz, 0.0, 1.0)
			img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Pass 3: bright nucleus core
	var nucleus_r := r * 0.3
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= nucleus_r:
				var ni := 1.0 - (d / nucleus_r) * 0.1
				img.set_pixel(x, y, Color(ni, ni, ni, 1.0))
			elif d <= nucleus_r + 1.5 and d > nucleus_r:
				# Ring around nucleus
				var existing := img.get_pixel(x, y)
				if existing.a > 0.5:
					var dimmed := clampf(existing.r - 0.2, 0.3, 1.0)
					img.set_pixel(x, y, Color(dimmed, dimmed, dimmed, 1.0))
	# Pass 4: specular highlight off-center
	var hl_r := r * 0.2
	var hl_cx := cx - r * 0.2
	var hl_cy := cy - r * 0.25
	for y in size:
		for x in size:
			var dx := float(x) - hl_cx
			var dy := float(y) - hl_cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= hl_r:
				var hi := 0.9 + (1.0 - d / hl_r) * 0.1
				img.set_pixel(x, y, Color(hi, hi, hi, 1.0))
	return ImageTexture.create_from_image(img)

## Spinning portal with energy vortex, concentric rings, and center eye — teleporter
static func _portal_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.50
	var eye_r := r_inner * 0.35
	var pupil_r := eye_r * 0.45
	# Pass 1: outer glow halo
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r_outer and d <= r_outer + 4.0:
				var fade := 1.0 - (d - r_outer) / 4.0
				var angle := atan2(dy, dx)
				var swirl := absf(sin(angle * 4.0 + d * 0.5)) * 0.15
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, fade * (0.25 + swirl)))
	# Pass 2: outer ring with spinning energy segments
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			if d >= r_inner and d <= r_outer:
				var ring_t := (d - r_inner) / (r_outer - r_inner)
				# Spinning segment pattern: alternating bright/dim
				var seg := sin(angle * 8.0 + ring_t * 4.0)
				var base_i := 0.65 + ring_t * 0.2
				var seg_mod := seg * 0.15
				var intensity := clampf(base_i + seg_mod, 0.0, 1.0)
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Pass 3: concentric energy rings in the void between outer ring and eye
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d >= eye_r and d < r_inner:
				var angle := atan2(dy, dx)
				# Vortex spiral — twisting lines
				var vortex := sin(angle * 3.0 - d * 1.5) * 0.5 + 0.5
				# Concentric rings
				var ring := absf(sin(d * 2.5))
				var combined := vortex * 0.4 + ring * 0.3
				if combined > 0.35:
					var intensity := clampf(combined + 0.3, 0.0, 1.0)
					img.set_pixel(x, y, Color(intensity, intensity, intensity, intensity))
				else:
					# Faint void fill
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.08))
	# Pass 4: inner ring glow border
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if absf(d - r_inner) < 1.5:
				var ring_i := 1.0 - absf(d - r_inner) / 1.5 * 0.3
				img.set_pixel(x, y, Color(ring_i, ring_i, ring_i, 1.0))
	# Pass 5: center eye — iris + dark pupil + catchlight
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= eye_r:
				if d <= pupil_r:
					# Dark pupil
					img.set_pixel(x, y, Color(0.1, 0.1, 0.1, 1.0))
				else:
					# Iris with radial detail
					var iris_t := (d - pupil_r) / (eye_r - pupil_r)
					var angle := atan2(dy, dx)
					var iris_ray := absf(sin(angle * 6.0)) * 0.15
					var i := 0.5 + iris_t * 0.3 + iris_ray
					img.set_pixel(x, y, Color(i, i, i, 1.0))
	# Catchlight
	var hl_x := cx - eye_r * 0.25
	var hl_y := cy - eye_r * 0.25
	for y in size:
		for x in size:
			var dx := float(x) - hl_x
			var dy := float(y) - hl_y
			if sqrt(dx * dx + dy * dy) <= pupil_r * 0.5:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.85))
	return ImageTexture.create_from_image(img)

## Fierce ram skull with horns, glowing eyes, and armored forehead — charger
static func _ram_skull_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	var fh := float(h - 1)
	# Pass 1: main skull wedge body with armored plating
	for y in h:
		var t := float(y) / maxf(fh, 1.0)
		var half_w := (1.0 - t * 0.82) * cx
		for x in w:
			var dx := absf(float(x) - cx)
			if dx <= half_w:
				var norm_dx := dx / maxf(half_w, 0.001)
				# Armored forehead: brighter top section with plate lines
				var intensity := 0.0
				if t < 0.35:
					# Forehead plate — bright with horizontal grooves
					var groove := absf(sin(t * 30.0)) * 0.08
					intensity = 0.95 - t * 0.3 + groove
					# Center ridge (raised brow ridge)
					if dx < half_w * 0.15:
						intensity += 0.1
				elif t < 0.5:
					# Brow area — slightly darker
					intensity = 0.7 - norm_dx * 0.1
				else:
					# Lower jaw — taper with shading
					intensity = 0.85 - t * 0.3 - norm_dx * 0.1
				# Edge darkening for depth
				if norm_dx > 0.8:
					intensity -= (norm_dx - 0.8) * 0.3
				img.set_pixel(x, y, Color(clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), clampf(intensity, 0.0, 1.0), 1.0))
	# Pass 2: horns — curved arcs extending up and outward
	var horn_sides: Array[float] = [-1.0, 1.0]
	for side in horn_sides:
		var horn_base_x := cx + side * (cx * 0.45)
		var horn_base_y := h * 0.08
		# Draw horn as a curved thick line sweeping outward and up
		for s in range(0, 20):
			var st := float(s) / 19.0
			# Curve: starts at base, sweeps outward and slightly up then curls
			var horn_x := horn_base_x + side * st * cx * 0.65
			var horn_y := horn_base_y - st * h * 0.12 + st * st * h * 0.15
			var horn_thick := 3.0 - st * 2.0  # Tapers to point
			for dy in range(-int(horn_thick) - 1, int(horn_thick) + 2):
				for dx in range(-int(horn_thick) - 1, int(horn_thick) + 2):
					var px := int(horn_x) + dx
					var py := int(horn_y) + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						var dd := sqrt(float(dx * dx + dy * dy))
						if dd <= horn_thick:
							var hi := 1.0 - st * 0.3 - (dd / horn_thick) * 0.15
							var existing := img.get_pixel(px, py)
							if hi > existing.r or existing.a < 0.5:
								img.set_pixel(px, py, Color(clampf(hi, 0.0, 1.0), clampf(hi, 0.0, 1.0), clampf(hi, 0.0, 1.0), 1.0))
	# Pass 3: glowing eyes — bright with dark surround
	var eye_y := int(h * 0.22)
	for side in horn_sides:
		var eye_cx := cx + side * 3.0
		var eye_cy := float(eye_y)
		# Dark eye socket
		for dy in range(-3, 4):
			for dx in range(-2, 3):
				var px := int(eye_cx) + dx
				var py := int(eye_cy) + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					var dd := sqrt(float(dx * dx) * 1.2 + float(dy * dy) * 0.7)
					if dd <= 3.0:
						img.set_pixel(px, py, Color(0.15, 0.15, 0.15, 1.0))
		# Bright glowing eye core (slit-shaped)
		for dy in range(-2, 3):
			for dx in range(-1, 2):
				var px := int(eye_cx) + dx
				var py := int(eye_cy) + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					var slit_d := absf(float(dx)) * 1.5 + absf(float(dy)) * 0.6
					if slit_d <= 2.0:
						var gi := 1.0 - slit_d * 0.15
						img.set_pixel(px, py, Color(gi, gi, gi, 1.0))
		# Eye glow bleed
		for dy in range(-4, 5):
			for dx in range(-3, 4):
				var px := int(eye_cx) + dx
				var py := int(eye_cy) + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					var dd := sqrt(float(dx * dx + dy * dy))
					if dd <= 4.5 and dd > 3.0:
						var existing := img.get_pixel(px, py)
						if existing.a > 0.5 and existing.r > 0.3:
							var glow_i := existing.r + (1.0 - (dd - 3.0) / 1.5) * 0.15
							img.set_pixel(px, py, Color(clampf(glow_i, 0.0, 1.0), clampf(glow_i, 0.0, 1.0), clampf(glow_i, 0.0, 1.0), 1.0))
	# Pass 4: nose slit / nostril marks
	var nose_y := int(h * 0.42)
	for side in horn_sides:
		var nose_x := int(cx + side * 1.5)
		for dy in range(-1, 2):
			var py := nose_y + dy
			if nose_x >= 0 and nose_x < w and py >= 0 and py < h:
				img.set_pixel(nose_x, py, Color(0.3, 0.3, 0.3, 1.0))
	# Pass 5: jaw line / teeth marks at the bottom taper
	var jaw_y_start := int(h * 0.65)
	for y in range(jaw_y_start, h):
		var t := float(y) / maxf(fh, 1.0)
		var half_w := (1.0 - t * 0.82) * cx
		# Serrated jaw edge
		var tooth_x := int(cx - half_w + 0.5)
		var tooth_x2 := int(cx + half_w - 0.5)
		if tooth_x >= 0 and tooth_x < w and y >= 0 and y < h:
			if int(y) % 3 == 0:
				img.set_pixel(tooth_x, y, Color(1.0, 1.0, 1.0, 1.0))
		if tooth_x2 >= 0 and tooth_x2 < w and y >= 0 and y < h:
			if int(y) % 3 == 0:
				img.set_pixel(tooth_x2, y, Color(1.0, 1.0, 1.0, 1.0))
	# Pass 6: glow outline around entire shape
	var base := img.duplicate()
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.1:
				var near := false
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var nx := x + dx
						var ny := y + dy
						if nx >= 0 and nx < w and ny >= 0 and ny < h:
							if base.get_pixel(nx, ny).a > 0.5:
								near = true
								break
					if near:
						break
				if near:
					var dd := 999.0
					for dy in range(-2, 3):
						for dx in range(-2, 3):
							var nx := x + dx
							var ny := y + dy
							if nx >= 0 and nx < w and ny >= 0 and ny < h:
								if base.get_pixel(nx, ny).a > 0.5:
									dd = minf(dd, sqrt(float(dx * dx + dy * dy)))
					var alpha := (1.0 - dd / 2.5) * 0.3
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 0.3)))
	return ImageTexture.create_from_image(img)
