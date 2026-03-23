extends Node
## GameManager – Autoload singleton.
## Single source of truth for game state, player stats, XP, waves, upgrades,
## kills, and persistent meta-progression.

# ── Signals ───────────────────────────────────────────────────────────────────
signal xp_changed(current: int, to_next: int)
signal level_changed(level: int)
signal wave_changed(wave: int)
signal stats_changed
signal game_over_triggered
signal upgrade_available(choices: Array)
signal coins_changed(total: int)
signal kills_changed(total: int)
signal boss_wave_started(wave: int)

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
var kills: int           = 0
var coins_this_run: int  = 0   # coins earned in the current run (for end screen)

# ── Player Stats (all upgrades modify this dict) ──────────────────────────────
var stats: Dictionary = {
	"max_health":         100,
	"speed":              150.0,
	"damage":             10,
	"attack_speed":       1.0,       # attacks per second
	"projectile_count":   1,
	"projectile_speed":   320.0,
	"xp_multiplier":      1.0,
	"pickup_radius":      60.0,
	# New stats
	"armor":              0,         # flat damage reduction per hit
	"lifesteal":          0.0,       # HP healed per kill
	"regen":              0.0,       # HP healed per second
	"melee_enabled":      false,
	"melee_level":        1,
	"boomerang_enabled":  false,
	"boomerang_level":    1,
	# Evolution flags
	"crimson_reaper":     false,
	"death_orbit":        false,
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
	# Filter by optional condition, then pick n at random
	var pool := _upgrade_pool.filter(func(u: Dictionary) -> bool:
		return not u.has("condition") or u["condition"].call()
	)
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
	if wave % 5 == 0:
		boss_wave_started.emit(wave)

func get_wave_multiplier() -> float:
	return 1.0 + (wave - 1) * 0.18

# ── Coins & Kills ─────────────────────────────────────────────────────────────
func add_coin(amount: int = 1) -> void:
	coin_count      += amount
	coins_this_run  += amount
	coins_changed.emit(coin_count)

func add_kill() -> void:
	kills += 1
	kills_changed.emit(kills)

# ── Game Over / Reset ─────────────────────────────────────────────────────────
func trigger_game_over() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	# Persist earned coins across runs
	var meta := get_node_or_null("/root/MetaManager")
	if meta:
		meta.add_coins(coins_this_run)
	game_over_triggered.emit()

func reset() -> void:
	state         = State.PLAYING
	survival_time = 0.0
	current_level = 1
	current_xp    = 0
	xp_to_next    = 100
	wave          = 1
	coin_count    = 0
	kills         = 0
	coins_this_run = 0
	stats         = _default_stats.duplicate(true)
	get_tree().paused = false

func get_time_string() -> String:
	var total: int = int(survival_time)
	var m: int = total / 60
	var s: int = total % 60
	return "%02d:%02d" % [m, s]

# ── Upgrade Pool ──────────────────────────────────────────────────────────────
var _upgrade_pool: Array = [
	# ── Core projectile upgrades ───────────────────────────────────────────────
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
	# ── New passive upgrades ───────────────────────────────────────────────────
	{
		"id":    "armor",
		"name":  "Iron Skin",
		"desc":  "+3 Armor\nReduces all damage taken",
		"apply": func(): stats["armor"] += 3,
	},
	{
		"id":    "lifesteal",
		"name":  "Vampirism",
		"desc":  "+5 HP per kill",
		"apply": func(): stats["lifesteal"] += 5.0,
	},
	{
		"id":    "regen",
		"name":  "Regeneration",
		"desc":  "+3 HP/sec",
		"apply": func(): stats["regen"] += 3.0,
	},
	# ── Melee weapon tree ─────────────────────────────────────────────────────
	{
		"id":        "melee_unlock",
		"name":      "Blade Arts",
		"desc":      "UNLOCK: Melee Sweep\nDamages all nearby enemies",
		"condition": func() -> bool: return not stats.get("melee_enabled", false),
		"apply":     func(): stats["melee_enabled"] = true,
	},
	{
		"id":        "melee_lvl2",
		"name":      "Blade Mastery",
		"desc":      "Melee: +50% Damage\nFaster swing",
		"condition": func() -> bool: return stats.get("melee_enabled", false) and stats.get("melee_level", 1) == 1,
		"apply":     func(): stats["melee_level"] = 2,
	},
	{
		"id":        "melee_lvl3",
		"name":      "Blade Mastery II",
		"desc":      "Melee: +100% Damage\nWider range",
		"condition": func() -> bool: return stats.get("melee_level", 1) == 2,
		"apply":     func(): stats["melee_level"] = 3,
	},
	# ── Boomerang weapon tree ─────────────────────────────────────────────────
	{
		"id":        "boomerang_unlock",
		"name":      "Orbital Strike",
		"desc":      "UNLOCK: Orbiting Blade\nSpins around you dealing damage",
		"condition": func() -> bool: return not stats.get("boomerang_enabled", false),
		"apply":     func(): stats["boomerang_enabled"] = true,
	},
	{
		"id":        "boomerang_lvl2",
		"name":      "Orbital Mastery",
		"desc":      "Boomerang: +50% Dmg\nFaster orbit",
		"condition": func() -> bool: return stats.get("boomerang_enabled", false) and stats.get("boomerang_level", 1) == 1,
		"apply":     func(): stats["boomerang_level"] = 2,
	},
	{
		"id":        "boomerang_lvl3",
		"name":      "Orbital Mastery II",
		"desc":      "Boomerang: +100% Dmg\nWider orbit",
		"condition": func() -> bool: return stats.get("boomerang_level", 1) == 2,
		"apply":     func(): stats["boomerang_level"] = 3,
	},
	# ── Evolutions (require two prerequisites each) ───────────────────────────
	# Apply only sets the flag; player._check_weapons() derives the weapon level.
	{
		"id":        "crimson_reaper",
		"name":      "★ Crimson Reaper",
		"desc":      "EVOLUTION\nMelee gains lifesteal\n+150% Melee Damage",
		"condition": func() -> bool: return stats.get("melee_level", 1) >= 3 and stats.get("lifesteal", 0.0) >= 5.0 and not stats.get("crimson_reaper", false),
		"apply":     func(): stats["crimson_reaper"] = true,
	},
	{
		"id":        "death_orbit",
		"name":      "★ Death Orbit",
		"desc":      "EVOLUTION\nTriple boomerang\n+200% Orbital Damage",
		"condition": func() -> bool: return stats.get("boomerang_level", 1) >= 3 and stats.get("projectile_count", 1) >= 3 and not stats.get("death_orbit", false),
		"apply":     func(): stats["death_orbit"] = true,
	},
]
