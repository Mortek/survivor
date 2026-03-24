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
## All shapes include inner details, glow edges, and layered depth.
static func _shape_tex(type: int) -> ImageTexture:
	match type:
		Type.BASIC:    return _spiky_circle_tex(28)
		Type.FAST:     return _lightning_bolt_tex(20, 28)
		Type.TANK:     return _armored_hex_tex(36)
		Type.BOSS:     return _star_shape_tex(30, 6)
		Type.SPLITTER: return _split_diamond_tex(28)
		Type.EXPLODER: return _bomb_tex(26)
		Type.SHIELDER: return _shield_hex_tex(30)
		Type.HEALER:      return _cross_plus_tex(30)
		Type.SWARM:       return _swarm_orb_tex(16)
		Type.TELEPORTER:  return _portal_tex(28)
		Type.CHARGER:     return _ram_skull_tex(20, 30)
		_:                return _spiky_circle_tex(28)

## Spiked circle with glowing core — base enemy
static func _spiky_circle_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.58
	var spikes  := 10
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d  := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var spike_angle := fmod(angle + TAU, TAU / float(spikes))
			var t := absf(spike_angle - (TAU / float(spikes)) * 0.5) / (TAU / float(spikes) * 0.5)
			var r_at_angle: float = lerpf(r_outer, r_inner, t * t * 0.5)
			if d <= r_at_angle:
				# Core glow: brighter center
				var intensity := 1.0 - (d / r_at_angle) * 0.4
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			elif d <= r_at_angle + 1.5:
				# Soft outer glow
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.3))
	# Inner eye/core
	var eye_r := r_inner * 0.35
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= eye_r:
				img.set_pixel(x, y, Color(0.4, 0.4, 0.4, 1.0))
	return ImageTexture.create_from_image(img)

## Lightning bolt shape — fast enemy (replaces arrow)
static func _lightning_bolt_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	# Draw a zigzag lightning bolt shape
	var segments: Array[Vector2] = [
		Vector2(cx + 3.0, 0.0),          # top right
		Vector2(cx - 2.0, h * 0.38),     # zag left
		Vector2(cx + 4.0, h * 0.35),     # zig right
		Vector2(cx - 1.0, h * 0.62),     # zag left
		Vector2(cx + 3.0, h * 0.58),     # zig right
		Vector2(cx, float(h - 1)),       # bottom point
	]
	# Fill bolt shape by drawing thick line segments
	for y in h:
		for x in w:
			var px := float(x)
			var py := float(y)
			var on_bolt := false
			for i in range(segments.size() - 1):
				var a := segments[i]
				var b := segments[i + 1]
				if py >= minf(a.y, b.y) - 1.0 and py <= maxf(a.y, b.y) + 1.0:
					var t_seg := clampf((py - a.y) / maxf(b.y - a.y, 0.001), 0.0, 1.0)
					var center_x := a.x + (b.x - a.x) * t_seg
					var bolt_width := 3.5 - (float(i) * 0.25)
					if absf(px - center_x) <= bolt_width:
						on_bolt = true
						break
			if on_bolt:
				# Brighter core
				var ny := float(y) / float(h - 1)
				var dist_from_center := absf(float(x) - cx) / (w * 0.5)
				var intensity := 1.0 - dist_from_center * 0.2
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Add glow around the bolt
	var base := img.duplicate()
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.1:
				# Check neighbors for glow
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
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.2))
	return ImageTexture.create_from_image(img)

## Armored hexagon with inner plates — tank
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
				var inner := hex_r * 0.50
				var plate := hex_r * 0.75
				if d > plate:
					# Outer armor rim
					img.set_pixel(x, y, Color(0.85, 0.85, 0.85, 1.0))
				elif d > inner:
					# Middle plate
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
				elif d > inner * 0.4:
					# Inner ring gap
					img.set_pixel(x, y, Color(0.5, 0.5, 0.5, 1.0))
				else:
					# Core
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
			elif d <= hex_r + 1.5:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.2))
	return ImageTexture.create_from_image(img)

## 6-pointed star with inner glow — boss
static func _star_shape_tex(size: int, points: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx      := (size - 1) * 0.5
	var cy      := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.40
	for y in size:
		for x in size:
			var dx    := float(x) - cx
			var dy    := float(y) - cy
			var d     := sqrt(dx * dx + dy * dy)
			var angle := atan2(dy, dx)
			var sector_angle := TAU / float(points)
			var a_mod := fmod(angle + TAU + sector_angle * 0.5, sector_angle) - sector_angle * 0.5
			var t     := absf(a_mod) / (sector_angle * 0.5)
			var r_star: float = lerpf(r_outer, r_inner, t)
			if d <= r_star:
				var intensity := 1.0 - (d / r_star) * 0.3
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			elif d <= r_star + 2.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.25))
	# Central core circle
	var core_r := r_inner * 0.55
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			if sqrt(dx * dx + dy * dy) <= core_r:
				img.set_pixel(x, y, Color(0.6, 0.6, 0.6, 1.0))
	return ImageTexture.create_from_image(img)

## Bomb with fuse and inner glow — exploder
static func _bomb_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5 + 2.0
	var r  := size * 0.38
	# Main bomb body (circle)
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= r:
				var intensity := 1.0 - (d / r) * 0.25
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			elif d <= r + 1.5:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.3))
	# Fuse on top
	var fuse_x := int(cx + 2)
	for fy in range(0, int(cy - r) + 3):
		if fuse_x >= 0 and fuse_x < size and fy >= 0 and fy < size:
			img.set_pixel(fuse_x, fy, Color.WHITE)
			if fuse_x + 1 < size:
				img.set_pixel(fuse_x + 1, fy, Color(1.0, 1.0, 1.0, 0.5))
	# Spark at top of fuse
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var sx := fuse_x + dx
			var sy := dy + 1
			if sx >= 0 and sx < size and sy >= 0 and sy < size:
				var sd := sqrt(float(dx * dx + dy * dy))
				if sd <= 2.5:
					img.set_pixel(sx, sy, Color(1.0, 1.0, 1.0, 1.0 - sd * 0.3))
	# Inner highlight
	var hl_r := r * 0.3
	var hl_cx := cx - r * 0.2
	var hl_cy := cy - r * 0.2
	for y in size:
		for x in size:
			var dx := float(x) - hl_cx
			var dy := float(y) - hl_cy
			if sqrt(dx * dx + dy * dy) <= hl_r:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.5))
	return ImageTexture.create_from_image(img)

## Split diamond with crack line — splitter
static func _split_diamond_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	for y in size:
		for x in size:
			var nx := absf(float(x) - cx) / (cx + 0.001)
			var ny := absf(float(y) - cy) / (cy + 0.001)
			var d := nx + ny
			if d <= 1.0:
				var intensity := 1.0 - d * 0.3
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			elif d <= 1.12:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.25))
	# Crack line down the middle
	for y in size:
		var crack_x := int(cx + sin(float(y) * 0.6) * 1.5)
		if crack_x >= 0 and crack_x < size:
			var nx := absf(float(crack_x) - cx) / (cx + 0.001)
			var ny := absf(float(y) - cy) / (cy + 0.001)
			if nx + ny <= 0.95:
				img.set_pixel(crack_x, y, Color(0.3, 0.3, 0.3, 1.0))
	return ImageTexture.create_from_image(img)

## Shield hexagon with barrier lines — shielder
static func _shield_hex_tex(size: int) -> ImageTexture:
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
				var intensity := 0.8 + (1.0 - d / hex_r) * 0.2
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
				# Inner barrier ring
				var ring_d := absf(d - hex_r * 0.65)
				if ring_d < 1.5:
					img.set_pixel(x, y, Color(0.5, 0.5, 0.5, 1.0))
			elif d <= hex_r + 2.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.2))
	return ImageTexture.create_from_image(img)

## Medical cross with heart center — healer
static func _cross_plus_tex(size: int) -> ImageTexture:
	var img     := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx      := int((size - 1) / 2)
	var arm_w   := maxi(int(size * 0.26), 3)
	var arm_len := int(size * 0.44)
	# Horizontal arm
	for y in range(cx - arm_w, cx + arm_w + 1):
		for x in range(cx - arm_len, cx + arm_len + 1):
			if x >= 0 and x < size and y >= 0 and y < size:
				var dist := maxf(absf(float(x) - float(cx)), absf(float(y) - float(cx)))
				var intensity := 1.0 - (dist / float(arm_len)) * 0.2
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Vertical arm
	for x in range(cx - arm_w, cx + arm_w + 1):
		for y in range(cx - arm_len, cx + arm_len + 1):
			if x >= 0 and x < size and y >= 0 and y < size:
				var dist := maxf(absf(float(x) - float(cx)), absf(float(y) - float(cx)))
				var intensity := 1.0 - (dist / float(arm_len)) * 0.2
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Glow outline
	var base := img.duplicate()
	for y in size:
		for x in size:
			if img.get_pixel(x, y).a < 0.1:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := x + dx
						var ny := y + dy
						if nx >= 0 and nx < size and ny >= 0 and ny < size:
							if base.get_pixel(nx, ny).a > 0.5:
								img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.25))
	return ImageTexture.create_from_image(img)

## Glowing orb with inner swirl — swarm
static func _swarm_orb_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.5
	var r := size * 0.5 - 0.5
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= r:
				var intensity := 1.0 - (d / r) * 0.5
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			elif d <= r + 1.5:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.3))
	# Inner bright spot
	var spot_r := r * 0.3
	for y in size:
		for x in size:
			var dx := float(x) - (cx - 1.0)
			var dy := float(y) - (cy - 1.0)
			if sqrt(dx * dx + dy * dy) <= spot_r:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.6))
	return ImageTexture.create_from_image(img)

## Portal ring with energy center — teleporter
static func _portal_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx      := (size - 1) * 0.5
	var cy      := (size - 1) * 0.5
	var r_outer := size * 0.5 - 0.5
	var r_inner := r_outer * 0.55
	var dot_r   := r_inner * 0.4
	for y in size:
		for x in size:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d  := sqrt(dx * dx + dy * dy)
			# Outer ring with gradient
			if d <= r_outer and d >= r_inner:
				var ring_t := (d - r_inner) / (r_outer - r_inner)
				var intensity := 0.7 + ring_t * 0.3
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
			elif d <= r_outer + 1.5 and d > r_outer:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.2))
			# Center energy
			elif d <= dot_r:
				var ci := 1.0 - (d / dot_r) * 0.3
				img.set_pixel(x, y, Color(ci, ci, ci, 1.0))
			# Inner ring glow
			elif d < r_inner and d > r_inner - 1.5:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.3))
	return ImageTexture.create_from_image(img)

## Ram skull shape — charger
static func _ram_skull_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	# Body: wide top tapering to point (aggressive wedge)
	for y in h:
		var t      := float(y) / maxf(float(h - 1), 1.0)
		var half_w := (1.0 - t * 0.85) * cx
		for x in w:
			if absf(float(x) - cx) <= half_w:
				var intensity := 1.0 - t * 0.25
				img.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	# Horn bumps on top
	var horn_sides: Array[float] = [-1.0, 1.0]
	for side in horn_sides:
		var horn_cx := cx + side * (cx * 0.5)
		for y in range(0, int(h * 0.25)):
			for x in w:
				var hdx := float(x) - horn_cx
				var hdy := float(y) - 2.0
				if sqrt(hdx * hdx + hdy * hdy) <= 3.5:
					if x >= 0 and x < w:
						img.set_pixel(x, y, Color.WHITE)
	# Eye slits
	var eye_y := int(h * 0.2)
	var eye_sides: Array[float] = [-1.0, 1.0]
	for side in eye_sides:
		var eye_x := int(cx + side * 3.0)
		for dy in range(-1, 2):
			for dx in range(-1, 1):
				var px := eye_x + dx
				var py := eye_y + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, Color(0.3, 0.3, 0.3, 1.0))
	# Glow outline
	var base := img.duplicate()
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.1:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := x + dx
						var ny := y + dy
						if nx >= 0 and nx < w and ny >= 0 and ny < h:
							if base.get_pixel(nx, ny).a > 0.5:
								img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.2))
	return ImageTexture.create_from_image(img)
