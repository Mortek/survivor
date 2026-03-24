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
func _ready() -> void:
	damage_area.body_entered.connect(_on_damage_area_body_entered)
	# Load defaults so the node displays correctly before activate() is called.
	var cfg: Dictionary = CONFIGS[enemy_type]
	_base_color     = cfg["col"]
	sprite.modulate = _base_color
	if not sprite.texture:
		sprite.texture = _shape_tex(enemy_type)

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
			sprite.scale = Vector2(2.5, 2.5)
		Type.SPLITTER:
			sprite.scale = Vector2(1.0, 1.0)
		Type.EXPLODER:
			sprite.scale = Vector2(0.85, 0.85)

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

## Returns a distinct white-on-transparent shape texture for each enemy type.
## Colour is applied separately via sprite.modulate.
static func _shape_tex(type: int) -> ImageTexture:
	match type:
		Type.BASIC:    return _spiky_circle_tex(26)
		Type.FAST:     return _arrowhead_tex(16, 24)
		Type.TANK:     return _armored_hex_tex(34)
		Type.BOSS:     return _star_shape_tex(26, 6)
		Type.SPLITTER: return _triangle_tex(26)
		Type.EXPLODER: return _bomb_tex(22)
		Type.SHIELDER: return _hexagon_tex(28)
		Type.HEALER:      return _cross_plus_tex(28)
		Type.SWARM:       return _teardrop_tex(14)
		Type.TELEPORTER:  return _ring_dot_tex(24, 4)
		Type.CHARGER:     return _wedge_tex(14, 28)
		_:                return _spiky_circle_tex(26)

## Spiked circle — base enemy
static func _spiky_circle_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.62
	var spikes  := 8
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d  := sqrt(dx * dx + dy * dy)
			if d < 0.5:
				img.set_pixel(x, y, Color.WHITE)
				continue
			var angle := atan2(dy, dx)
			# Spike contribution: radius oscillates between inner and outer
			var spike_angle := fmod(angle + TAU, TAU / float(spikes))
			var t := absf(spike_angle - (TAU / float(spikes)) * 0.5) / (TAU / float(spikes) * 0.5)
			var r_at_angle: float = lerpf(r_outer, r_inner, t * t * 0.45)
			if d <= r_at_angle:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## Arrowhead pointing up — fast enemy
static func _arrowhead_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	# Upper triangle (arrowhead)
	var arrow_h := int(h * 0.6)
	for y in arrow_h:
		var t      := float(y) / float(arrow_h)
		var half_w := t * cx
		for x in w:
			if absf(float(x) - cx) <= half_w:
				img.set_pixel(x, y, Color.WHITE)
	# Lower shaft
	var shaft_w := int(w * 0.35)
	var sx := int(cx - shaft_w * 0.5)
	var ex := int(cx + shaft_w * 0.5)
	for y in range(arrow_h, h):
		for x in range(sx, ex + 1):
			if x >= 0 and x < w:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## Armored hexagon (hex with inner ring) — tank
static func _armored_hex_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r  := size * 0.5 - 0.5
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var angle := atan2(dy, dx)
			var hex_r := r * cos(fmod(absf(angle) + PI / 6.0, PI / 3.0) - PI / 6.0)
			var d := sqrt(dx * dx + dy * dy)
			if d <= hex_r:
				# Fill body, but leave inner cutout ring for armor look
				var inner := hex_r * 0.55
				if d > inner * 0.65 or d <= inner * 0.3:
					img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## 6-pointed star — boss
static func _star_shape_tex(size: int, points: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx      := (size - 1) * 0.5
	var cy      := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.42
	for y in size:
		for x in size:
			var dx    := float(x) - cx
			var dy    := float(y) - cy
			var d     := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			# Interpolate radius between inner and outer based on angle
			var sector_angle := TAU / float(points)
			var a_mod := fmod(angle + TAU + sector_angle * 0.5, sector_angle) - sector_angle * 0.5
			var t     := absf(a_mod) / (sector_angle * 0.5)
			var r_star: float = lerpf(r_outer, r_inner, t)
			if d <= r_star:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## Bomb cross with rounded tips — exploder
static func _bomb_tex(size: int) -> ImageTexture:
	var img       := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var half      := size >> 1
	var thickness := maxi(int(size / 4.0), 2)
	var tip_r     := float(thickness) * 0.9
	for y in size:
		for x in size:
			var dx: int = abs(x - half)
			var dy: int = abs(y - half)
			if dx <= thickness or dy <= thickness:
				img.set_pixel(x, y, Color.WHITE)
			# Round tips
			for tip in [[half, 1], [half, size-2], [1, half], [size-2, half]]:
				var tdx := float(x) - float(tip[0])
				var tdy := float(y) - float(tip[1])
				if sqrt(tdx*tdx + tdy*tdy) <= tip_r:
					img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## Medical cross (healer) — wider plus arms
static func _cross_plus_tex(size: int) -> ImageTexture:
	var img     := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx      := int((size - 1) / 2)
	var arm_w   := maxi(int(size * 0.28), 3)
	var arm_len := int(size * 0.42)
	# Horizontal arm
	for y in range(cx - arm_w, cx + arm_w + 1):
		for x in range(cx - arm_len, cx + arm_len + 1):
			if x >= 0 and x < size and y >= 0 and y < size:
				img.set_pixel(x, y, Color.WHITE)
	# Vertical arm
	for x in range(cx - arm_w, cx + arm_w + 1):
		for y in range(cx - arm_len, cx + arm_len + 1):
			if x >= 0 and x < size and y >= 0 and y < size:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## Teardrop pointing down — swarm enemy
static func _teardrop_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	# Upper circle
	var circle_r := size * 0.38
	var circle_cy := size * 0.40
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - circle_cy
			if dx*dx + dy*dy <= circle_r * circle_r:
				img.set_pixel(x, y, Color.WHITE)
	# Lower pointed tail
	var tail_start := int(circle_cy + circle_r * 0.7)
	for y in range(tail_start, size):
		var t      := float(y - tail_start) / maxf(float(size - 1 - tail_start), 1.0)
		var half_w := (1.0 - t) * circle_r * 0.55
		for x in range(int(cx - half_w), int(cx + half_w) + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## Ring with center dot — teleporter
static func _ring_dot_tex(size: int, thickness: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx      := (size - 1) * 0.5
	var cy      := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer - float(thickness)
	var dot_r   := r_inner * 0.28
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d2 := dx * dx + dy * dy
			if d2 <= r_outer * r_outer and d2 >= r_inner * r_inner:
				img.set_pixel(x, y, Color.WHITE)
			elif d2 <= dot_r * dot_r:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

## Aggressive wedge/arrowhead pointing down — charger
static func _wedge_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	# Wide top, narrow bottom (aggressive wedge)
	for y in h:
		var t      := float(y) / maxf(float(h - 1), 1.0)
		var half_w := (1.0 - t * 0.85) * cx
		for x in w:
			if absf(float(x) - cx) <= half_w:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

static func _ring_tex(size: int, thickness: int) -> ImageTexture:
	return _ring_dot_tex(size, thickness)

static func _circle_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r2 := (size * 0.5 - 0.5) * (size * 0.5 - 0.5)
	for y in size:
		for x in size:
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

static func _diamond_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var nx := absf(x - cx) / (cx + 0.001)
			var ny := absf(y - cy) / (cy + 0.001)
			if nx + ny <= 1.0:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

static func _triangle_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in size:
		var t      := float(y) / maxf(size - 1, 1)
		var half_w := t * (size * 0.5)
		var xs     := int(size * 0.5 - half_w)
		var xe     := int(size * 0.5 + half_w)
		for x in range(xs, xe + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

static func _cross_tex(size: int) -> ImageTexture:
	var img       := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var half      := size >> 1
	var thickness := maxi(int(size / 5.0), 2)
	for y in size:
		for x in size:
			if abs(y - half) <= thickness or abs(x - half) <= thickness:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

static func _hexagon_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r  := size * 0.5 - 0.5
	for y in size:
		for x in size:
			var dx := x - cx
			var dy := y - cy
			var angle := atan2(dy, dx)
			var hex_r := r * cos(fmod(absf(angle) + PI / 6.0, PI / 3.0) - PI / 6.0)
			if sqrt(dx * dx + dy * dy) <= hex_r:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

static func _star_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var thick := maxi(int(size / 5.0), 2)
	for y in size:
		for x in size:
			var dx: int = abs(x - int(cx))
			var dy: int = abs(y - int(cy))
			if dx <= thick or dy <= thick:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
