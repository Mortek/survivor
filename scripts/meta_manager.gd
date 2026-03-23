extends Node
## Persists player progress (lifetime coins) across game sessions.
## Registered as an Autoload in project.godot.

const SAVE_PATH := "user://meta.dat"

var total_coins: int = 0

func _ready() -> void:
	_load()

## Add coins to the persistent total and save immediately.
func add_coins(amount: int) -> void:
	total_coins += amount
	_save()

## Spend coins. Returns true on success, false if insufficient funds.
func spend_coins(amount: int) -> bool:
	if total_coins < amount:
		return false
	total_coins -= amount
	_save()
	return true

# ── Persistence ────────────────────────────────────────────────────────────────
func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_var({"coins": total_coins})

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var data = f.get_var()
	if data is Dictionary:
		total_coins = data.get("coins", 0)
