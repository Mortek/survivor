extends CanvasLayer
## HUD – health bar, XP bar, timer, wave, level, and coin counter.
## Connects to GameManager signals on _ready; call connect_player() from game.gd.

@onready var health_bar:   ProgressBar = $HUD/HealthBar
@onready var xp_bar:       ProgressBar = $HUD/XPBar
@onready var timer_label:  Label       = $HUD/TimerLabel
@onready var wave_label:   Label       = $HUD/WaveLabel
@onready var level_label:  Label       = $HUD/LevelLabel
@onready var coin_label:   Label       = $HUD/CoinLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.xp_changed.connect(_on_xp_changed)
	GameManager.level_changed.connect(_on_level_changed)
	GameManager.wave_changed.connect(_on_wave_changed)
	GameManager.coins_changed.connect(_on_coins_changed)
	# Initialise display
	_on_wave_changed(1)
	_on_level_changed(1)
	_on_coins_changed(0)
	_on_xp_changed(0, 100)

func _process(_delta: float) -> void:
	timer_label.text = GameManager.get_time_string()

## Called by game.gd once the player node is ready
func connect_player(player: Node) -> void:
	player.health_changed.connect(_on_health_changed)
	_on_health_changed(player.current_hp, GameManager.stats["max_health"])

# ── Signal Handlers ───────────────────────────────────────────────────────────
func _on_health_changed(hp: int, max_hp: int) -> void:
	health_bar.max_value = max_hp
	health_bar.value     = hp

func _on_xp_changed(xp: int, to_next: int) -> void:
	xp_bar.max_value = to_next
	xp_bar.value     = xp

func _on_level_changed(lvl: int) -> void:
	level_label.text = "Lv %d" % lvl

func _on_wave_changed(w: int) -> void:
	wave_label.text = "Wave %d" % w

func _on_coins_changed(total: int) -> void:
	coin_label.text = str(total)
