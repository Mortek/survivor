extends CharacterBody2D
## Enemy – seeks the player, takes damage, dies and drops XP.
## Three types: BASIC, FAST, TANK – set via enemy_type before calling activate().

# ── Signals ───────────────────────────────────────────────────────────────────
signal died(world_position: Vector2, xp_value: int)

# ── Types ─────────────────────────────────────────────────────────────────────
enum Type { BASIC, FAST, TANK }
@export var enemy_type: Type = Type.BASIC

# ── Per-type base config ──────────────────────────────────────────────────────
const CONFIGS: Dictionary = {
	Type.BASIC: { "hp": 30,  "spd": 80,  "dmg": 10, "xp": 10, "col": Color(0.90, 0.30, 0.30) },
	Type.FAST:  { "hp": 15,  "spd": 155, "dmg": 7,  "xp": 15, "col": Color(1.00, 0.85, 0.20) },
	Type.TANK:  { "hp": 120, "spd": 45,  "dmg": 20, "xp": 30, "col": Color(0.50, 0.20, 0.90) },
}

# ── Node References ───────────────────────────────────────────────────────────
@onready var sprite:       Sprite2D    = $Sprite2D
@onready var hp_bar:       ProgressBar = $HealthBar
@onready var damage_area:  Area2D      = $DamageArea

# ── Runtime State ─────────────────────────────────────────────────────────────
var max_hp:    float = 30.0
var current_hp: float = 30.0
var spd:       float = 80.0
var dmg:       int   = 10
var xp_value:  int   = 10
var _base_color: Color
var _player: Node2D = null
var _dead: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	damage_area.body_entered.connect(_on_damage_area_body_entered)
	_apply_config()
	if not sprite.texture:
		sprite.texture = _solid_tex(28)

func _apply_config() -> void:
	var cfg: Dictionary = CONFIGS[enemy_type]
	max_hp     = cfg["hp"]
	current_hp = max_hp
	spd        = cfg["spd"]
	dmg        = cfg["dmg"]
	xp_value   = cfg["xp"]
	_base_color = cfg["col"]
	sprite.modulate = _base_color
	_update_hp_bar()

## Call after getting from pool, before placing in the world.
func activate(player: Node2D, wave_multiplier: float) -> void:
	_player = player
	_dead   = false
	add_to_group("enemies")
	# Scale stats with wave difficulty
	var cfg: Dictionary = CONFIGS[enemy_type]
	max_hp     = cfg["hp"]  * wave_multiplier
	current_hp = max_hp
	spd        = minf(cfg["spd"] * (1.0 + (wave_multiplier - 1.0) * 0.25), 220.0)
	dmg        = int(cfg["dmg"] * wave_multiplier)
	xp_value   = int(cfg["xp"] * wave_multiplier)
	sprite.modulate = _base_color
	_update_hp_bar()

# ── AI Movement ───────────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if _dead or not _player or GameManager.state != GameManager.State.PLAYING:
		return
	velocity = (_player.global_position - global_position).normalized() * spd
	move_and_slide()

# ── Combat ────────────────────────────────────────────────────────────────────
func take_damage(amount: float) -> void:
	if _dead:
		return
	current_hp -= amount
	_update_hp_bar()
	_flash_hit()
	if current_hp <= 0.0:
		_die()

func _update_hp_bar() -> void:
	if hp_bar:
		hp_bar.value = (current_hp / max_hp) * 100.0

func _flash_hit() -> void:
	sprite.modulate = Color.WHITE
	await get_tree().create_timer(0.06).timeout
	if is_instance_valid(self) and not _dead:
		sprite.modulate = _base_color

func _die() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemies")
	died.emit(global_position, xp_value)
	queue_free()

# ── Contact Damage ────────────────────────────────────────────────────────────
func _on_damage_area_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(dmg)

static func _solid_tex(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)   # modulate handles per-type color
	return ImageTexture.create_from_image(img)
