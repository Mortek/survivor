extends Node
## GameManager – Autoload singleton.
## Single source of truth for game state, player stats, XP, waves, upgrades,
## kills, combos, achievements, and curses.

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
signal combo_updated(count: int)
signal achievement_unlocked(id: String, title: String)
signal curse_offered(options: Array)

# ── State ─────────────────────────────────────────────────────────────────────
enum State { PLAYING, PAUSED, LEVEL_UP, GAME_OVER, CURSE_OFFER }
var state: State = State.PLAYING

# ── Tracked Values ────────────────────────────────────────────────────────────
var survival_time:  float = 0.0
var current_level:  int   = 1
var current_xp:     int   = 0
var xp_to_next:     int   = 100
var wave:           int   = 1
var coin_count:     int   = 0
var kills:          int   = 0
var coins_this_run: int   = 0
var combo_count:    int   = 0
var _combo_timer:   float = 0.0
const COMBO_WINDOW          := 2.5
var _active_curses:  Array  = []
var _achieved:       Dictionary = {}
var total_crits: int = 0
var _corruption_counter: int = 0

# ── Daily Challenge ───────────────────────────────────────────────────────────
var daily_challenge_active: bool   = false
var daily_challenge_curse:  String = ""

# ── Player Stats ──────────────────────────────────────────────────────────────
var stats: Dictionary = {
	"max_health":         100,
	"speed":              150.0,
	"damage":             10,
	"attack_speed":       1.0,
	"projectile_count":   1,
	"projectile_speed":   320.0,
	"xp_multiplier":      1.0,
	"pickup_radius":      60.0,
	"armor":              0,
	"lifesteal":          0.0,
	"regen":              0.0,
	# Melee
	"melee_enabled":      false,
	"melee_level":        1,
	# Boomerang
	"boomerang_enabled":  false,
	"boomerang_level":    1,
	# Lightning Chain
	"lightning_enabled":  false,
	"lightning_level":    1,
	# Passive
	"shield_charges":     0,
	"synergy_aura":       false,
	"enemy_speed_mult":   1.0,
	# Evolution flags
	"crimson_reaper":     false,
	"death_orbit":        false,
	"thunder_god":        false,
	# New mechanics
	"pierce":             0,
	"area_mult":          1.0,
	"knockback":          0.0,
	"crit_chance":        0.0,
	"slow_on_hit":        false,
	"burn_on_hit":        false,
	"berserk_threshold":  0.0,
	"dash_enabled":       false,
	"wave_speed_mult":    1.0,
	"corruption_active":  false,
}
var _default_stats: Dictionary

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_default_stats = stats.duplicate(true)

func _process(delta: float) -> void:
	if state == State.PLAYING:
		survival_time += delta
		# Check time-based achievements every second
		if int(survival_time) != int(survival_time - delta):
			_check_achievements()
		# Combo decay
		if combo_count > 0:
			_combo_timer += delta
			if _combo_timer > COMBO_WINDOW:
				combo_count  = 0
				_combo_timer = 0.0
				combo_updated.emit(0)

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
	xp_to_next    = int(xp_to_next * 1.28)
	level_changed.emit(current_level)
	_check_achievements()
	state = State.LEVEL_UP
	get_tree().paused = true
	upgrade_available.emit(_pick_upgrades(3))

## Offer a free upgrade card without incrementing the level (used by Lucky Star).
func offer_free_upgrade() -> void:
	state = State.LEVEL_UP
	get_tree().paused = true
	upgrade_available.emit(_pick_upgrades(3))

func _pick_upgrades(n: int) -> Array:
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
	_check_achievements()

# ── Wave ──────────────────────────────────────────────────────────────────────
func advance_wave() -> void:
	wave += 1
	wave_changed.emit(wave)
	if wave % 5 == 0:
		boss_wave_started.emit(wave)
	_check_achievements()

func get_wave_multiplier() -> float:
	return 1.0 + (wave - 1) * 0.14

# ── Coins & Kills ─────────────────────────────────────────────────────────────
func add_coin(amount: int = 1) -> void:
	coin_count     += amount
	coins_this_run += amount
	coins_changed.emit(coin_count)

func add_kill() -> void:
	kills += 1
	kills_changed.emit(kills)
	# Combo
	combo_count  += 1
	_combo_timer  = 0.0
	combo_updated.emit(combo_count)
	_check_achievements()
	# Corruption: every 5th kill deals 8 damage to player
	if stats.get("corruption_active", false):
		_corruption_counter += 1
		if _corruption_counter >= 5:
			_corruption_counter = 0
			var _player := get_tree().get_first_node_in_group("player")
			if _player and _player.has_method("take_damage"):
				_player.take_damage(8)

func add_crit() -> void:
	total_crits += 1
	_check_achievements()

# ── Curse System ──────────────────────────────────────────────────────────────
## Called by spawner at certain waves. Picks 2 random curses and offers them.
func try_offer_curse() -> void:
	var pool := _curse_pool.duplicate()
	# Filter out already-active curses
	pool = pool.filter(func(c: Dictionary) -> bool: return not (c["id"] in _active_curses))
	if pool.is_empty():
		return
	pool.shuffle()
	var extra := 0
	var meta := get_node_or_null("/root/MetaManager")
	if meta:
		extra = meta.get_upgrade_level("double_curse")
	var options := pool.slice(0, min(2 + extra, pool.size()))
	state = State.CURSE_OFFER
	get_tree().paused = true
	curse_offered.emit(options)

func accept_curse(curse: Dictionary) -> void:
	_active_curses.append(curse["id"])
	curse["apply"].call()
	state = State.PLAYING
	get_tree().paused = false
	stats_changed.emit()

func decline_curse() -> void:
	state = State.PLAYING
	get_tree().paused = false

# ── Achievement System ────────────────────────────────────────────────────────
func _check_achievements() -> void:
	_try_achieve("first_blood", "First Blood!",    kills >= 1)
	_try_achieve("century",     "Century Kill",    kills >= 100)
	_try_achieve("wave_rider",  "Wave Rider",      wave  >= 5)
	_try_achieve("survivor",    "10 Min Survivor", survival_time >= 600.0)
	_try_achieve("level10",     "Unstoppable",     current_level >= 10)
	_try_achieve("combo10",     "Combo King!",     combo_count >= 10)
	_try_achieve("evolution",   "Evolved!",
		stats.get("crimson_reaper", false) or
		stats.get("death_orbit",    false) or
		stats.get("thunder_god",    false)
	)
	_try_achieve("triple_tree", "Triple Threat",
		stats.get("melee_enabled", false) and
		stats.get("boomerang_enabled", false) and
		stats.get("lightning_enabled", false)
	)
	_try_achieve("wave10",      "Wave Veteran",  wave >= 10)
	_try_achieve("big_combo",   "On Fire!",      combo_count >= 20)
	_try_achieve("curse_lover", "Cursed Soul",   _active_curses.size() >= 3)

func _try_achieve(id: String, title: String, condition: bool) -> void:
	if condition and not _achieved.has(id):
		_achieved[id] = true
		var meta := get_node_or_null("/root/MetaManager")
		if meta and not meta.has_achievement(id):
			meta.unlock_achievement(id)
			achievement_unlocked.emit(id, title)

# ── Game Over / Reset ─────────────────────────────────────────────────────────
func trigger_game_over() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	var meta := get_node_or_null("/root/MetaManager")
	if meta:
		meta.add_coins(coins_this_run)
	game_over_triggered.emit()

func reset() -> void:
	state          = State.PLAYING
	survival_time  = 0.0
	current_level  = 1
	current_xp     = 0
	xp_to_next     = 100
	wave           = 1
	coin_count     = 0
	kills          = 0
	coins_this_run = 0
	combo_count         = 0
	total_crits         = 0
	_corruption_counter = 0
	_combo_timer   = 0.0
	_active_curses = []
	stats          = _default_stats.duplicate(true)
	get_tree().paused = false

func get_time_string() -> String:
	var total: int = int(survival_time)
	var m: int = int(total / 60.0)
	var s: int = total % 60
	return "%02d:%02d" % [m, s]

# ── Curse Pool ────────────────────────────────────────────────────────────────
var _curse_pool: Array = [
	{
		"id":     "glass_cannon",
		"name":   "Glass Cannon",
		"desc":   "Max HP halved\n+60% Damage",
		"reward": "+60% DMG",
		"apply":  func() -> void:
			stats["max_health"] = int(stats["max_health"] * 0.5)
			stats["damage"]     = int(stats["damage"] * 1.6),
	},
	{
		"id":     "blood_price",
		"name":   "Blood Price",
		"desc":   "Enemies 25% faster\n2× XP gain",
		"reward": "2× XP",
		"apply":  func() -> void:
			stats["enemy_speed_mult"] = stats.get("enemy_speed_mult", 1.0) + 0.25
			stats["xp_multiplier"]   *= 2.0,
	},
	{
		"id":     "berserker",
		"name":   "Berserker Pact",
		"desc":   "−5 Armor\n+40% Attack Speed",
		"reward": "+40% ATK SPD",
		"apply":  func() -> void:
			stats["armor"]        -= 5
			stats["attack_speed"] *= 1.4,
	},
	{
		"id":     "chaos_form",
		"name":   "Chaos Form",
		"desc":   "−0.5 Attack Speed\n+3 Projectiles",
		"reward": "+3 Bullets",
		"apply":  func() -> void:
			stats["attack_speed"]      = maxf(stats["attack_speed"] - 0.5, 0.2)
			stats["projectile_count"] += 3,
	},
	{
		"id":     "iron_burden",
		"name":   "Iron Burden",
		"desc":   "Speed −40\n+8 Armor",
		"reward": "+8 Armor",
		"apply":  func() -> void:
			stats["speed"] = maxf(stats["speed"] - 40.0, 60.0)
			stats["armor"] += 8,
	},
	{
		"id":     "cursed_xp",
		"name":   "Cursed Knowledge",
		"desc":   "−30% XP gain\n+2× Coin drops",
		"reward": "+2× Coins",
		"apply":  func() -> void:
			stats["xp_multiplier"] *= 0.7
			# coin bonus tracked via separate stat
			stats["coin_mult"] = stats.get("coin_mult", 1.0) * 2.0,
	},
	{
		"id":     "giant_form",
		"name":   "Giant Form",
		"desc":   "+80 Max HP\n−40 Speed",
		"reward": "+80 HP",
		"apply":  func() -> void:
			stats["max_health"] += 80
			stats["speed"]       = maxf(stats.get("speed", 150.0) - 40.0, 60.0),
	},
	{
		"id":     "time_warp",
		"name":   "Time Warp",
		"desc":   "Waves 40% shorter\n+80% XP",
		"reward": "+80% XP",
		"apply":  func() -> void:
			stats["xp_multiplier"]  = stats.get("xp_multiplier", 1.0) * 1.8
			stats["wave_speed_mult"] = stats.get("wave_speed_mult", 1.0) * 0.6,
	},
	{
		"id":     "wraith_pact",
		"name":   "Wraith Pact",
		"desc":   "−5 Armor\n+25% Crit Chance",
		"reward": "+25% Crit",
		"apply":  func() -> void:
			stats["armor"]       -= 5
			stats["crit_chance"] = minf(stats.get("crit_chance", 0.0) + 0.25, 0.80),
	},
	{
		"id":     "corruption",
		"name":   "Corruption",
		"desc":   "+4 Projectiles\nEvery 5th kill hurts you",
		"reward": "+4 Bullets",
		"apply":  func() -> void:
			stats["projectile_count"]  += 4
			stats["corruption_active"]  = true,
	},
]

# ── Upgrade Pool ──────────────────────────────────────────────────────────────
var _upgrade_pool: Array = [
	# ── Core projectile ────────────────────────────────────────────────────────
	{
		"id":    "damage",
		"name":  "Sharp Shots",
		"desc":  "+15 Damage",
		"apply": func() -> void: stats["damage"] += 15,
	},
	{
		"id":    "speed",
		"name":  "Swift Feet",
		"desc":  "+25 Move Speed",
		"apply": func() -> void: stats["speed"] += 25.0,
	},
	{
		"id":    "atk_speed",
		"name":  "Rapid Fire",
		"desc":  "+0.4 Attacks/sec",
		"apply": func() -> void: stats["attack_speed"] += 0.4,
	},
	{
		"id":    "multishot",
		"name":  "Multishot",
		"desc":  "+1 Projectile",
		"apply": func() -> void: stats["projectile_count"] += 1,
	},
	{
		"id":    "health",
		"name":  "Iron Will",
		"desc":  "+30 Max HP",
		"apply": func() -> void: stats["max_health"] += 30,
	},
	{
		"id":    "proj_speed",
		"name":  "Velocity",
		"desc":  "+60 Bullet Speed",
		"apply": func() -> void: stats["projectile_speed"] += 60.0,
	},
	{
		"id":    "xp_gain",
		"name":  "Scholar",
		"desc":  "+30% XP Gain",
		"apply": func() -> void: stats["xp_multiplier"] += 0.3,
	},
	{
		"id":    "pickup",
		"name":  "Magnet",
		"desc":  "+50 Pickup Radius",
		"apply": func() -> void: stats["pickup_radius"] += 50.0,
	},
	# ── Passive ────────────────────────────────────────────────────────────────
	{
		"id":    "armor",
		"name":  "Iron Skin",
		"desc":  "+3 Armor",
		"apply": func() -> void: stats["armor"] += 3,
	},
	{
		"id":    "lifesteal",
		"name":  "Vampirism",
		"desc":  "+5 HP per kill",
		"apply": func() -> void: stats["lifesteal"] += 5.0,
	},
	{
		"id":    "regen",
		"name":  "Regeneration",
		"desc":  "+3 HP/sec",
		"apply": func() -> void: stats["regen"] += 3.0,
	},
	{
		"id":        "shield",
		"name":      "Energy Shield",
		"desc":      "+1 Shield Charge\nAbsorbs one hit",
		"apply":     func() -> void: stats["shield_charges"] += 1,
	},
	# ── Melee tree ─────────────────────────────────────────────────────────────
	{
		"id":        "melee_unlock",
		"name":      "Blade Arts",
		"desc":      "UNLOCK: Melee Sweep\nDamages all nearby enemies",
		"condition": func() -> bool: return not stats.get("melee_enabled", false),
		"apply":     func() -> void: stats["melee_enabled"] = true,
	},
	{
		"id":        "melee_lvl2",
		"name":      "Blade Mastery",
		"desc":      "Melee: +50% Damage\nFaster swing",
		"condition": func() -> bool: return stats.get("melee_enabled", false) and stats.get("melee_level", 1) == 1,
		"apply":     func() -> void: stats["melee_level"] = 2,
	},
	{
		"id":        "melee_lvl3",
		"name":      "Blade Mastery II",
		"desc":      "Melee: +100% Damage\nWider range",
		"condition": func() -> bool: return stats.get("melee_level", 1) == 2,
		"apply":     func() -> void: stats["melee_level"] = 3,
	},
	# ── Boomerang tree ─────────────────────────────────────────────────────────
	{
		"id":        "boomerang_unlock",
		"name":      "Orbital Strike",
		"desc":      "UNLOCK: Orbiting Blade\nSpins around you dealing damage",
		"condition": func() -> bool: return not stats.get("boomerang_enabled", false),
		"apply":     func() -> void: stats["boomerang_enabled"] = true,
	},
	{
		"id":        "boomerang_lvl2",
		"name":      "Orbital Mastery",
		"desc":      "Boomerang: +50% Dmg\nFaster orbit",
		"condition": func() -> bool: return stats.get("boomerang_enabled", false) and stats.get("boomerang_level", 1) == 1,
		"apply":     func() -> void: stats["boomerang_level"] = 2,
	},
	{
		"id":        "boomerang_lvl3",
		"name":      "Orbital Mastery II",
		"desc":      "Boomerang: +100% Dmg\nWider orbit",
		"condition": func() -> bool: return stats.get("boomerang_level", 1) == 2,
		"apply":     func() -> void: stats["boomerang_level"] = 3,
	},
	# ── Lightning Chain tree ───────────────────────────────────────────────────
	{
		"id":        "lightning_unlock",
		"name":      "Static Field",
		"desc":      "UNLOCK: Lightning Chain\nBounces between enemies",
		"condition": func() -> bool: return not stats.get("lightning_enabled", false),
		"apply":     func() -> void: stats["lightning_enabled"] = true,
	},
	{
		"id":        "lightning_lvl2",
		"name":      "Chain Lightning",
		"desc":      "Lightning: +40% Dmg\n+1 Bounce",
		"condition": func() -> bool: return stats.get("lightning_enabled", false) and stats.get("lightning_level", 1) == 1,
		"apply":     func() -> void: stats["lightning_level"] = 2,
	},
	{
		"id":        "lightning_lvl3",
		"name":      "Storm Bringer",
		"desc":      "Lightning: +100% Dmg\n+2 Bounces  Faster",
		"condition": func() -> bool: return stats.get("lightning_level", 1) == 2,
		"apply":     func() -> void: stats["lightning_level"] = 3,
	},
	{
		"id":        "lightning_lvl4",
		"name":      "Overcharge",
		"desc":      "Lightning: +200% Dmg\n+3 Bounces  Faster",
		"condition": func() -> bool: return stats.get("lightning_level", 1) == 3,
		"apply":     func() -> void: stats["lightning_level"] = 4,
	},
	# ── Evolutions ─────────────────────────────────────────────────────────────
	{
		"id":        "crimson_reaper",
		"name":      "★ Crimson Reaper",
		"desc":      "EVOLUTION\nMelee gains lifesteal\n+150% Melee Damage",
		"condition": func() -> bool:
			return stats.get("melee_level", 1) >= 3 and stats.get("lifesteal", 0.0) >= 5.0 and not stats.get("crimson_reaper", false),
		"apply":     func() -> void: stats["crimson_reaper"] = true,
	},
	{
		"id":        "death_orbit",
		"name":      "★ Death Orbit",
		"desc":      "EVOLUTION\nTriple boomerang\n+200% Orbital Damage",
		"condition": func() -> bool:
			return stats.get("boomerang_level", 1) >= 3 and stats.get("projectile_count", 1) >= 3 and not stats.get("death_orbit", false),
		"apply":     func() -> void: stats["death_orbit"] = true,
	},
	{
		"id":        "thunder_god",
		"name":      "★ Thunder God",
		"desc":      "EVOLUTION\nLightning adds AOE burst\n+150% Chain Damage",
		"condition": func() -> bool:
			return stats.get("lightning_level", 1) >= 4 and stats.get("armor", 0) >= 6 and not stats.get("thunder_god", false),
		"apply":     func() -> void: stats["thunder_god"] = true,
	},
	{
		"id":        "synergy_aura",
		"name":      "★ Harmonic Resonance",
		"desc":      "SYNERGY\nMelee + Boomerang mastered\nPassive damage aura",
		"condition": func() -> bool:
			return stats.get("melee_level", 1) >= 3 and stats.get("boomerang_level", 1) >= 3 and not stats.get("synergy_aura", false),
		"apply":     func() -> void: stats["synergy_aura"] = true,
	},
	# ── New mechanics ───────────────────────────────────────────────────────────
	{
		"id":    "pierce",
		"name":  "Piercing Shot",
		"desc":  "+1 Pierce\nBullets pass through enemies",
		"apply": func() -> void: stats["pierce"] += 1,
	},
	{
		"id":    "area_boost",
		"name":  "Wide Sweep",
		"desc":  "+30% Melee & Aura area",
		"apply": func() -> void: stats["area_mult"] = stats.get("area_mult", 1.0) * 1.3,
	},
	{
		"id":        "repulsion",
		"name":      "Repulsion",
		"desc":      "Hits knock enemies back",
		"condition": func() -> bool: return stats.get("knockback", 0.0) == 0.0,
		"apply":     func() -> void: stats["knockback"] = 180.0,
	},
	{
		"id":    "crit_chance",
		"name":  "Eagle Eye",
		"desc":  "+15% Crit Chance\n2× damage on crit",
		"apply": func() -> void: stats["crit_chance"] = minf(stats.get("crit_chance", 0.0) + 0.15, 0.80),
	},
	{
		"id":        "frost_touch",
		"name":      "Frost Touch",
		"desc":      "Hits slow enemies 40%\nfor 2 seconds",
		"condition": func() -> bool: return not stats.get("slow_on_hit", false),
		"apply":     func() -> void: stats["slow_on_hit"] = true,
	},
	{
		"id":        "fire_starter",
		"name":      "Fire Starter",
		"desc":      "Hits apply Burn\n3 dmg/sec for 3 sec",
		"condition": func() -> bool: return not stats.get("burn_on_hit", false),
		"apply":     func() -> void: stats["burn_on_hit"] = true,
	},
	{
		"id":        "berserk",
		"name":      "Berserk Mode",
		"desc":      "Below 30% HP: +60% Dmg",
		"condition": func() -> bool: return stats.get("berserk_threshold", 0.0) == 0.0,
		"apply":     func() -> void: stats["berserk_threshold"] = 0.30,
	},
	{
		"id":        "phase_dash",
		"name":      "Phase Dash",
		"desc":      "UNLOCK: Dash ability\nDash button appears in HUD",
		"condition": func() -> bool: return not stats.get("dash_enabled", false),
		"apply":     func() -> void: stats["dash_enabled"] = true,
	},
	{
		"id":    "storm_shot",
		"name":  "Storm Shot",
		"desc":  "+3 Projectiles\n−50 Bullet Speed",
		"apply": func() -> void:
			stats["projectile_count"] += 3
			stats["projectile_speed"]  = maxf(stats.get("projectile_speed", 320.0) - 50.0, 100.0),
	},
	{
		"id":    "double_edge",
		"name":  "Double-Edged",
		"desc":  "−20 Max HP\n+25 Damage",
		"apply": func() -> void:
			stats["max_health"] = maxi(stats.get("max_health", 100) - 20, 20)
			stats["damage"]     += 25,
	},
]
