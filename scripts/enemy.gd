class_name Enemy
extends CharacterBody2D
## Enemy – seeks the player, takes damage, dies and drops XP.
## Types: BASIC, FAST, TANK, BOSS, SPLITTER, EXPLODER.
## Any enemy can also be marked as an Elite for 3× HP and bonus XP.

# ── Signals ───────────────────────────────────────────────────────────────────
signal died(world_position: Vector2, xp_value: int, color: Color, enemy_type: int)
signal hit_taken(world_position: Vector2, amount: float)
signal split_requested(world_position: Vector2)   # emitted by SPLITTER on death

# ── Types ─────────────────────────────────────────────────────────────────────
enum Type { BASIC, FAST, TANK, BOSS, SPLITTER, EXPLODER }
@export var enemy_type: Type = Type.BASIC

# ── Per-type base config ──────────────────────────────────────────────────────
const CONFIGS: Dictionary = {
	Type.BASIC:    { "hp": 30,  "spd": 80,   "dmg": 10, "xp": 10,  "col": Color(0.90, 0.30, 0.30) },
	Type.FAST:     { "hp": 15,  "spd": 155,  "dmg": 7,  "xp": 15,  "col": Color(1.00, 0.85, 0.20) },
	Type.TANK:     { "hp": 120, "spd": 45,   "dmg": 20, "xp": 30,  "col": Color(0.50, 0.20, 0.90) },
	Type.BOSS:     { "hp": 600, "spd": 55,   "dmg": 28, "xp": 200, "col": Color(0.90, 0.10, 0.90) },
	Type.SPLITTER: { "hp": 45,  "spd": 90,   "dmg": 8,  "xp": 20,  "col": Color(0.20, 0.85, 0.50) },
	Type.EXPLODER: { "hp": 25,  "spd": 120,  "dmg": 35, "xp": 25,  "col": Color(1.00, 0.45, 0.05) },
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
var _dead: bool      = false
var is_elite: bool   = false

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
		sprite.texture = _solid_tex(28)

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
		sprite.modulate = _base_color.lightened(0.5)
		sprite.scale   *= 1.25
	else:
		sprite.modulate = _base_color

	_update_hp_bar()

# ── AI Movement ───────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _dead or not _player or GameManager.state != GameManager.State.PLAYING:
		return
	match enemy_type:
		Type.BOSS:
			_boss_ai(delta)
		Type.EXPLODER:
			_exploder_ai(delta)
		_:
			velocity = (_player.global_position - global_position).normalized() * spd
			move_and_slide()

func _boss_ai(delta: float) -> void:
	var dir := (_player.global_position - global_position).normalized()
	if _charging:
		_charge_elapsed += delta
		velocity = dir * spd * BOSS_CHARGE_SPEED_MULT
		if _charge_elapsed >= BOSS_CHARGE_DURATION:
			_charging = false
			sprite.modulate = _base_color.lightened(0.5) if is_elite else _base_color
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

# ── Combat ────────────────────────────────────────────────────────────────────
func take_damage(amount: float) -> void:
	if _dead:
		return
	current_hp -= amount
	_update_hp_bar()
	_flash_hit()
	hit_taken.emit(global_position, amount)
	if current_hp <= 0.0:
		_die()

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
		sprite.modulate = _base_color.lightened(0.5) if is_elite else _base_color

func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemies")
	died.emit(global_position, xp_value, _base_color, int(enemy_type))
	if enemy_type == Type.SPLITTER:
		split_requested.emit(global_position)
	queue_free()

# ── Contact Damage ────────────────────────────────────────────────────────────
func _on_damage_area_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(dmg)

static func _solid_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)
