extends Node
## Persists player progress across game sessions:
##   – Lifetime coins (total_coins)
##   – Permanent upgrade levels
##   – Achievements unlocked

const SAVE_PATH := "user://meta.dat"

# ── Permanent Upgrades Definition ─────────────────────────────────────────────
const PERMANENT_UPGRADES: Array = [
	{
		"id":         "start_health",
		"name":       "Iron Constitution",
		"desc":       "+20 Max HP at run start per level",
		"max_level":  5,
		"base_cost":  15,
		"cost_scale": 10,
	},
	{
		"id":         "start_damage",
		"name":       "Lethal Training",
		"desc":       "+8 Base Damage per level",
		"max_level":  5,
		"base_cost":  20,
		"cost_scale": 15,
	},
	{
		"id":         "start_speed",
		"name":       "Fleet Feet",
		"desc":       "+15 Base Speed per level",
		"max_level":  3,
		"base_cost":  25,
		"cost_scale": 20,
	},
	{
		"id":         "coin_bonus",
		"name":       "Fortune Seeker",
		"desc":       "+15% XP & Coin gain per level",
		"max_level":  4,
		"base_cost":  30,
		"cost_scale": 25,
	},
	{
		"id":         "start_regen",
		"name":       "Blood Pact",
		"desc":       "+1 HP/sec regen per level",
		"max_level":  3,
		"base_cost":  20,
		"cost_scale": 15,
	},
	{
		"id":         "lucky_start",
		"name":       "Lucky Star",
		"desc":       "Start each run with a free upgrade card",
		"max_level":  1,
		"base_cost":  50,
		"cost_scale": 0,
	},
]

# ── Runtime State ──────────────────────────────────────────────────────────────
var total_coins:         int        = 0
var permanent_upgrades:  Dictionary = {}   # id → level (int)
var achievements:        Dictionary = {}   # id → true

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

## Apply all permanent upgrade bonuses to a stats dict (called at run start).
func apply_to_stats(stats: Dictionary) -> void:
	var lvl: int

	lvl = get_upgrade_level("start_health")
	if lvl > 0:
		stats["max_health"] += lvl * 20

	lvl = get_upgrade_level("start_damage")
	if lvl > 0:
		stats["damage"] += lvl * 8

	lvl = get_upgrade_level("start_speed")
	if lvl > 0:
		stats["speed"] += float(lvl) * 15.0

	lvl = get_upgrade_level("coin_bonus")
	if lvl > 0:
		stats["xp_multiplier"] += float(lvl) * 0.15

	lvl = get_upgrade_level("start_regen")
	if lvl > 0:
		stats["regen"] += float(lvl) * 1.0

# ── Achievements ──────────────────────────────────────────────────────────────
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
			"coins":        total_coins,
			"upgrades":     permanent_upgrades,
			"achievements": achievements,
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
