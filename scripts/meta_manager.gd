extends Node
## Persists player progress across game sessions:
##   – Lifetime coins (total_coins)
##   – Permanent upgrade levels
##   – Achievements unlocked

const SAVE_PATH := "user://meta.dat"

# ── Permanent Upgrades Definition ─────────────────────────────────────────────
const PERMANENT_UPGRADES: Array = [
	# ── Offense ────────────────────────────────────────────────────────────────
	{
		"id":         "start_damage",
		"name":       "Lethal Training",
		"desc":       "+8 Base Damage per level",
		"max_level":  10,
		"base_cost":  80,
		"cost_scale": 70,
	},
	{
		"id":         "start_atk_speed",
		"name":       "Trigger Discipline",
		"desc":       "+0.15 Attack Speed per level",
		"max_level":  8,
		"base_cost":  100,
		"cost_scale": 90,
	},
	{
		"id":         "start_crit",
		"name":       "Sharpshooter",
		"desc":       "+5% Crit Chance per level",
		"max_level":  8,
		"base_cost":  120,
		"cost_scale": 110,
	},
	{
		"id":         "start_multishot",
		"name":       "Arsenal",
		"desc":       "+1 Starting Projectile per level",
		"max_level":  5,
		"base_cost":  200,
		"cost_scale": 180,
	},
	{
		"id":         "start_pierce",
		"name":       "Penetrator",
		"desc":       "+1 Pierce per level",
		"max_level":  4,
		"base_cost":  200,
		"cost_scale": 200,
	},
	# ── Defense ────────────────────────────────────────────────────────────────
	{
		"id":         "start_health",
		"name":       "Iron Constitution",
		"desc":       "+20 Max HP per level",
		"max_level":  10,
		"base_cost":  60,
		"cost_scale": 55,
	},
	{
		"id":         "start_armor",
		"name":       "Iron Plating",
		"desc":       "+2 Armor per level",
		"max_level":  10,
		"base_cost":  80,
		"cost_scale": 70,
	},
	{
		"id":         "start_regen",
		"name":       "Blood Pact",
		"desc":       "+1 HP/sec Regen per level",
		"max_level":  8,
		"base_cost":  80,
		"cost_scale": 70,
	},
	{
		"id":         "start_lifesteal",
		"name":       "Vampiric Touch",
		"desc":       "+3% Lifesteal per level",
		"max_level":  6,
		"base_cost":  150,
		"cost_scale": 130,
	},
	{
		"id":         "start_shields",
		"name":       "Energy Reserve",
		"desc":       "+1 Shield Charge per level",
		"max_level":  3,
		"base_cost":  300,
		"cost_scale": 280,
	},
	{
		"id":         "battle_hardened",
		"name":       "Battle Hardened",
		"desc":       "+3 Armor and +15 Max HP per level",
		"max_level":  6,
		"base_cost":  180,
		"cost_scale": 160,
	},
	# ── Utility ────────────────────────────────────────────────────────────────
	{
		"id":         "start_speed",
		"name":       "Fleet Feet",
		"desc":       "+15 Base Speed per level",
		"max_level":  8,
		"base_cost":  90,
		"cost_scale": 80,
	},
	{
		"id":         "xp_boost",
		"name":       "Scholar's Mark",
		"desc":       "+10% XP gain per level",
		"max_level":  10,
		"base_cost":  70,
		"cost_scale": 60,
	},
	{
		"id":         "coin_bonus",
		"name":       "Fortune Seeker",
		"desc":       "+12% XP & Coin gain per level",
		"max_level":  8,
		"base_cost":  90,
		"cost_scale": 80,
	},
	{
		"id":         "pickup_boost",
		"name":       "Gravity Well",
		"desc":       "+20 Pickup Radius per level",
		"max_level":  8,
		"base_cost":  60,
		"cost_scale": 50,
	},
	{
		"id":         "coin_magnet",
		"name":       "Coin Magnet",
		"desc":       "+25 Pickup Radius + magnet orb chance +0.25% per level",
		"max_level":  5,
		"base_cost":  100,
		"cost_scale": 90,
	},
	{
		"id":         "bounty_hunter",
		"name":       "Bounty Hunter",
		"desc":       "+20% Coin & XP drop value per level",
		"max_level":  6,
		"base_cost":  120,
		"cost_scale": 100,
	},
	# ── Specials (unlock once, very expensive) ─────────────────────────────────
	{
		"id":         "lucky_start",
		"name":       "Lucky Star",
		"desc":       "Start each run with a free upgrade card",
		"max_level":  1,
		"base_cost":  500,
		"cost_scale": 0,
	},
	{
		"id":         "start_dash",
		"name":       "Shadow Step",
		"desc":       "Start each run with the Dash ability unlocked",
		"max_level":  1,
		"base_cost":  700,
		"cost_scale": 0,
	},
	{
		"id":         "start_lightning",
		"name":       "Chain Starter",
		"desc":       "Start each run with Lightning Chain unlocked",
		"max_level":  1,
		"base_cost":  800,
		"cost_scale": 0,
	},
	{
		"id":         "double_curse",
		"name":       "Curse Seeker",
		"desc":       "Curse offers show +1 extra option per level",
		"max_level":  2,
		"base_cost":  500,
		"cost_scale": 450,
	},
	# ── Advanced ────────────────────────────────────────────────────────────────
	{
		"id":         "resilience",
		"name":       "Iron Will",
		"desc":       "−8% damage taken per level",
		"max_level":  5,
		"base_cost":  200,
		"cost_scale": 180,
	},
	{
		"id":         "elite_hunter",
		"name":       "Elite Hunter",
		"desc":       "+15% damage vs elite enemies per level",
		"max_level":  5,
		"base_cost":  180,
		"cost_scale": 160,
	},
	{
		"id":         "lucky_drops",
		"name":       "Lucky Breaks",
		"desc":       "+8% bonus coin drop chance per level",
		"max_level":  5,
		"base_cost":  100,
		"cost_scale": 90,
	},
	{
		"id":         "explosive_start",
		"name":       "Explosive Start",
		"desc":       "Start each run with Chain Reaction unlocked",
		"max_level":  1,
		"base_cost":  600,
		"cost_scale": 0,
	},
	{
		"id":         "wave_veteran",
		"name":       "Wave Veteran",
		"desc":       "+10 Max HP per 5 waves survived (applied at run start based on best wave)",
		"max_level":  5,
		"base_cost":  150,
		"cost_scale": 130,
	},
]

# ── Runtime State ──────────────────────────────────────────────────────────────
var total_coins:         int        = 0
var permanent_upgrades:  Dictionary = {}   # id → level (int)
var achievements:        Dictionary = {}   # id → true
var best_wave:  int   = 0
var best_kills: int   = 0
var best_time:  float = 0.0
var run_history:     Array = []   # Array of {wave, kills, time, coins}
var tutorial_done:   bool  = false
const MAX_RUN_HISTORY := 5

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_load()

# ── Coins ─────────────────────────────────────────────────────────────────────
func add_coins(amount: int) -> void:
	total_coins += amount
	_save()

func spend_coins(amount: int) -> bool:
	if total_coins < amount:
		return false
	total_coins -= amount
	_save()
	return true

# ── Permanent Upgrades ────────────────────────────────────────────────────────
func get_upgrade_level(id: String) -> int:
	return permanent_upgrades.get(id, 0)

func purchase_upgrade(id: String, cost: int) -> bool:
	if not spend_coins(cost):
		return false
	permanent_upgrades[id] = permanent_upgrades.get(id, 0) + 1
	_save()
	return true

func reset_all_upgrades() -> void:
	# Refund all coins spent on upgrades
	var upg_map: Dictionary = {}
	for upg in PERMANENT_UPGRADES:
		upg_map[upg["id"]] = upg
	var refund := 0
	for id in permanent_upgrades:
		var lvl: int = permanent_upgrades[id]
		if lvl <= 0 or not upg_map.has(id):
			continue
		var base: int = int(upg_map[id]["base_cost"])
		var scale: int = int(upg_map[id]["cost_scale"])
		for i in range(lvl):
			refund += base + (i * i) * scale
	total_coins += refund
	permanent_upgrades.clear()
	_save()

## Apply all permanent upgrade bonuses to a stats dict (called at run start).
func apply_to_stats(stats: Dictionary) -> void:
	var lvl: int

	# ── Offense ────────────────────────────────────────────────────────────────
	lvl = get_upgrade_level("start_damage")
	if lvl > 0:
		stats["damage"] += lvl * 8

	lvl = get_upgrade_level("start_atk_speed")
	if lvl > 0:
		stats["attack_speed"] = stats.get("attack_speed", 1.0) + float(lvl) * 0.15

	lvl = get_upgrade_level("start_crit")
	if lvl > 0:
		stats["crit_chance"] = minf(stats.get("crit_chance", 0.0) + float(lvl) * 0.05, 0.80)

	lvl = get_upgrade_level("start_multishot")
	if lvl > 0:
		stats["projectile_count"] = stats.get("projectile_count", 1) + lvl

	lvl = get_upgrade_level("start_pierce")
	if lvl > 0:
		stats["pierce"] = stats.get("pierce", 0) + lvl

	# ── Defense ────────────────────────────────────────────────────────────────
	lvl = get_upgrade_level("start_health")
	if lvl > 0:
		stats["max_health"] += lvl * 20

	lvl = get_upgrade_level("start_armor")
	if lvl > 0:
		stats["armor"] = stats.get("armor", 0) + lvl * 2

	lvl = get_upgrade_level("start_regen")
	if lvl > 0:
		stats["regen"] = stats.get("regen", 0.0) + float(lvl) * 1.0

	lvl = get_upgrade_level("start_lifesteal")
	if lvl > 0:
		stats["lifesteal"] = stats.get("lifesteal", 0.0) + float(lvl) * 0.03

	lvl = get_upgrade_level("start_shields")
	if lvl > 0:
		stats["shield_charges"] = stats.get("shield_charges", 0) + lvl

	lvl = get_upgrade_level("battle_hardened")
	if lvl > 0:
		stats["armor"]      = stats.get("armor", 0) + lvl * 3
		stats["max_health"] += lvl * 15

	# ── Utility ────────────────────────────────────────────────────────────────
	lvl = get_upgrade_level("start_speed")
	if lvl > 0:
		stats["speed"] = stats.get("speed", 150.0) + float(lvl) * 15.0

	lvl = get_upgrade_level("xp_boost")
	if lvl > 0:
		stats["xp_multiplier"] = stats.get("xp_multiplier", 1.0) + float(lvl) * 0.10

	lvl = get_upgrade_level("coin_bonus")
	if lvl > 0:
		stats["xp_multiplier"] = stats.get("xp_multiplier", 1.0) + float(lvl) * 0.12
		stats["coin_mult"]     = stats.get("coin_mult", 1.0) + float(lvl) * 0.12

	lvl = get_upgrade_level("pickup_boost")
	if lvl > 0:
		stats["pickup_radius"] = stats.get("pickup_radius", 60.0) + float(lvl) * 20.0

	lvl = get_upgrade_level("coin_magnet")
	if lvl > 0:
		stats["pickup_radius"]    = stats.get("pickup_radius", 60.0) + float(lvl) * 25.0
		stats["magnet_orb_bonus"] = stats.get("magnet_orb_bonus", 0.0) + float(lvl) * 0.0025

	lvl = get_upgrade_level("bounty_hunter")
	if lvl > 0:
		stats["coin_mult"]     = stats.get("coin_mult", 1.0) + float(lvl) * 0.20
		stats["xp_multiplier"] = stats.get("xp_multiplier", 1.0) + float(lvl) * 0.20

	# ── Advanced ───────────────────────────────────────────────────────────────
	lvl = get_upgrade_level("resilience")
	if lvl > 0:
		stats["dmg_reduction"] = minf(stats.get("dmg_reduction", 0.0) + float(lvl) * 0.08, 0.50)

	lvl = get_upgrade_level("elite_hunter")
	if lvl > 0:
		stats["elite_dmg_bonus"] = stats.get("elite_dmg_bonus", 0.0) + float(lvl) * 0.15

	lvl = get_upgrade_level("lucky_drops")
	if lvl > 0:
		stats["lucky_drop_chance"] = stats.get("lucky_drop_chance", 0.0) + float(lvl) * 0.08

	if get_upgrade_level("explosive_start") >= 1:
		stats["chain_explosion"] = maxf(stats.get("chain_explosion", 0.0), 0.25)

	lvl = get_upgrade_level("wave_veteran")
	if lvl > 0:
		var bonus_waves := mini(int(best_wave / 5.0), 20)
		stats["max_health"] += bonus_waves * lvl * 10

	# ── Specials ───────────────────────────────────────────────────────────────
	if get_upgrade_level("start_dash") >= 1:
		stats["dash_enabled"] = true

	if get_upgrade_level("start_lightning") >= 1:
		stats["lightning_enabled"] = true
		stats["lightning_level"]   = 1


# ── Achievements ──────────────────────────────────────────────────────────────
func add_run_history(wave: int, kills: int, time: float, coins: int) -> void:
	run_history.push_front({"wave": wave, "kills": kills, "time": time, "coins": coins})
	if run_history.size() > MAX_RUN_HISTORY:
		run_history.resize(MAX_RUN_HISTORY)
	_save()

func get_run_history() -> Array:
	return run_history

func update_best_run(wave: int, kills: int, time: float) -> void:
	var changed := false
	if wave > best_wave:
		best_wave = wave
		changed   = true
	if kills > best_kills:
		best_kills = kills
		changed    = true
	if time > best_time:
		best_time = time
		changed   = true
	if changed:
		_save()

func get_best_run_string() -> String:
	if best_wave == 0:
		return "No runs yet"
	return "Best: Wave %d  ·  %d kills  ·  %02d:%02d" % [
		best_wave, best_kills, int(best_time / 60.0), int(best_time) % 60
	]

func unlock_achievement(id: String) -> void:
	if achievements.get(id, false):
		return
	achievements[id] = true
	_save()

func has_achievement(id: String) -> bool:
	return achievements.get(id, false)

# ── Persistence ───────────────────────────────────────────────────────────────
func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_var({
			"coins":         total_coins,
			"upgrades":      permanent_upgrades,
			"achievements":  achievements,
			"best_wave":     best_wave,
			"best_kills":    best_kills,
			"best_time":     best_time,
			"run_history":   run_history,
			"tutorial_done": tutorial_done,
		})

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var data = f.get_var()
	if data is Dictionary:
		total_coins        = data.get("coins",        0)
		permanent_upgrades = data.get("upgrades",     {})
		achievements       = data.get("achievements", {})
		best_wave     = data.get("best_wave",     0)
		best_kills    = data.get("best_kills",    0)
		best_time     = data.get("best_time",     0.0)
		run_history   = data.get("run_history",   [])
		tutorial_done = data.get("tutorial_done", false)
