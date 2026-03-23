extends Node
## GameManager – Autoload singleton.
## Single source of truth for game state, player stats, XP, waves, and upgrades.

# ── Signals ───────────────────────────────────────────────────────────────────
signal xp_changed(current: int, to_next: int)
signal level_changed(level: int)
signal wave_changed(wave: int)
signal stats_changed
signal game_over_triggered
signal upgrade_available(choices: Array)
signal coins_changed(total: int)

# ── State ─────────────────────────────────────────────────────────────────────
enum State { PLAYING, PAUSED, LEVEL_UP, GAME_OVER }
var state: State = State.PLAYING

# ── Tracked Values ────────────────────────────────────────────────────────────
var survival_time: float = 0.0
var current_level: int   = 1
var current_xp: int      = 0
var xp_to_next: int      = 100
var wave: int            = 1
var coin_count: int      = 0

# ── Player Stats (all upgrades modify this dict) ──────────────────────────────
var stats: Dictionary = {
	"max_health":       100,
	"speed":            150.0,
	"damage":           10,
	"attack_speed":     1.0,      # attacks per second
	"projectile_count": 1,
	"projectile_speed": 320.0,
	"xp_multiplier":    1.0,
	"pickup_radius":    60.0,
}
var _default_stats: Dictionary

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_default_stats = stats.duplicate(true)

func _process(delta: float) -> void:
	if state == State.PLAYING:
		survival_time += delta

# ── XP & Leveling ─────────────────────────────────────────────────────────────
func add_xp(amount: int) -> void:
	if state != State.PLAYING:
		return
	current_xp += int(amount * stats["xp_multiplier"])
	xp_changed.emit(current_xp, xp_to_next)
	# Handle multi-level in one go
	while current_xp >= xp_to_next:
		_level_up()

func _level_up() -> void:
	current_xp -= xp_to_next
	current_level += 1
	xp_to_next    = int(xp_to_next * 1.35)
	level_changed.emit(current_level)
	state = State.LEVEL_UP
	get_tree().paused = true
	upgrade_available.emit(_pick_upgrades(3))

func _pick_upgrades(n: int) -> Array:
	var pool := _upgrade_pool.duplicate()
	pool.shuffle()
	return pool.slice(0, min(n, pool.size()))

func apply_upgrade(upgrade: Dictionary) -> void:
	upgrade["apply"].call()
	state = State.PLAYING
	get_tree().paused = false
	stats_changed.emit()
	xp_changed.emit(current_xp, xp_to_next)

# ── Wave ──────────────────────────────────────────────────────────────────────
func advance_wave() -> void:
	wave += 1
	wave_changed.emit(wave)

func get_wave_multiplier() -> float:
	## Scales enemy stats: 1.0 at wave 1, +18% per wave
	return 1.0 + (wave - 1) * 0.18

# ── Coins ─────────────────────────────────────────────────────────────────────
func add_coin(amount: int = 1) -> void:
	coin_count += amount
	coins_changed.emit(coin_count)

# ── Game Over / Reset ─────────────────────────────────────────────────────────
func trigger_game_over() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	game_over_triggered.emit()

func reset() -> void:
	state         = State.PLAYING
	survival_time = 0.0
	current_level = 1
	current_xp    = 0
	xp_to_next    = 100
	wave          = 1
	coin_count    = 0
	stats         = _default_stats.duplicate(true)
	get_tree().paused = false

func get_time_string() -> String:
	var m := int(survival_time) / 60
	var s := int(survival_time) % 60
	return "%02d:%02d" % [m, s]

# ── Upgrade Pool ──────────────────────────────────────────────────────────────
var _upgrade_pool: Array = [
	{
		"id":    "damage",
		"name":  "Sharp Shots",
		"desc":  "+15 Damage",
		"apply": func(): stats["damage"] += 15,
	},
	{
		"id":    "speed",
		"name":  "Swift Feet",
		"desc":  "+25 Move Speed",
		"apply": func(): stats["speed"] += 25.0,
	},
	{
		"id":    "atk_speed",
		"name":  "Rapid Fire",
		"desc":  "+0.4 Attacks/sec",
		"apply": func(): stats["attack_speed"] += 0.4,
	},
	{
		"id":    "multishot",
		"name":  "Multishot",
		"desc":  "+1 Projectile",
		"apply": func(): stats["projectile_count"] += 1,
	},
	{
		"id":    "health",
		"name":  "Iron Will",
		"desc":  "+30 Max HP",
		"apply": func(): stats["max_health"] += 30,
	},
	{
		"id":    "proj_speed",
		"name":  "Velocity",
		"desc":  "+60 Bullet Speed",
		"apply": func(): stats["projectile_speed"] += 60.0,
	},
	{
		"id":    "xp_gain",
		"name":  "Scholar",
		"desc":  "+30% XP Gain",
		"apply": func(): stats["xp_multiplier"] += 0.3,
	},
	{
		"id":    "pickup",
		"name":  "Magnet",
		"desc":  "+50 Pickup Radius",
		"apply": func(): stats["pickup_radius"] += 50.0,
	},
]
