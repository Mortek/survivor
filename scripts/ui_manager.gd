extends CanvasLayer
## HUD – repositions all elements in code so nothing relies on scene-editor placement.

var _last_displayed_second: int = -1

@onready var health_bar:  ProgressBar = $HUD/HealthBar
@onready var xp_bar:      ProgressBar = $HUD/XPBar
@onready var timer_label: Label       = $HUD/TimerLabel
@onready var wave_label:  Label       = $HUD/WaveLabel
@onready var level_label: Label       = $HUD/LevelLabel
@onready var coin_label:  Label       = $HUD/CoinLabel

var kills_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.xp_changed.connect(_on_xp_changed)
	GameManager.level_changed.connect(_on_level_changed)
	GameManager.wave_changed.connect(_on_wave_changed)
	GameManager.coins_changed.connect(_on_coins_changed)
	GameManager.kills_changed.connect(_on_kills_changed)

	if has_node("HUD/KillsLabel"):
		kills_label = $HUD/KillsLabel
	else:
		kills_label = Label.new()
		kills_label.name = "KillsLabel"
		$HUD.add_child(kills_label)

	_layout_hud()

	_on_wave_changed(1)
	_on_level_changed(1)
	_on_coins_changed(0)
	_on_kills_changed(0)
	_on_xp_changed(0, 100)

# ── HUD Layout ────────────────────────────────────────────────────────────────
# All positions are set here so nothing relies on scene-editor placement.
# Layout (px from top):
#   0–24   Health bar (full width)
#  26–43   Wave  (left column)
#  45–62   Level (left column)
#  64–81   Coin  (left column)
#  83–100  Kills (left column)
#  center  Timer (horizontally centered, row 2)
#  bottom  XP bar (full width, last 18px)
#  top-right  Pause btn (handled in game.gd)
#  bottom-right  Dev speed btn (handled in game.gd)
func _layout_hud() -> void:
	# ── Health bar: full-width strip at top ──
	health_bar.set_anchor_and_offset(SIDE_LEFT,   0.0,   0.0)
	health_bar.set_anchor_and_offset(SIDE_TOP,    0.0,   0.0)
	health_bar.set_anchor_and_offset(SIDE_RIGHT,  1.0,   0.0)
	health_bar.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  24.0)
	health_bar.custom_minimum_size = Vector2(0, 24)

	# ── XP bar: full-width strip at bottom ──
	xp_bar.set_anchor_and_offset(SIDE_LEFT,   0.0,   0.0)
	xp_bar.set_anchor_and_offset(SIDE_TOP,    1.0, -18.0)
	xp_bar.set_anchor_and_offset(SIDE_RIGHT,  1.0,   0.0)
	xp_bar.set_anchor_and_offset(SIDE_BOTTOM, 1.0,   0.0)
	xp_bar.custom_minimum_size = Vector2(0, 18)

	# ── Timer: centered horizontally, just below health bar ──
	timer_label.set_anchor_and_offset(SIDE_LEFT,   0.5, -60.0)
	timer_label.set_anchor_and_offset(SIDE_TOP,    0.0,  26.0)
	timer_label.set_anchor_and_offset(SIDE_RIGHT,  0.5,  60.0)
	timer_label.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  46.0)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ── Wave: left column, row 1 ──
	wave_label.set_anchor_and_offset(SIDE_LEFT,   0.0,  4.0)
	wave_label.set_anchor_and_offset(SIDE_TOP,    0.0, 26.0)
	wave_label.set_anchor_and_offset(SIDE_RIGHT,  0.0, 120.0)
	wave_label.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 43.0)

	# ── Level: left column, row 2 ──
	level_label.set_anchor_and_offset(SIDE_LEFT,   0.0,  4.0)
	level_label.set_anchor_and_offset(SIDE_TOP,    0.0, 45.0)
	level_label.set_anchor_and_offset(SIDE_RIGHT,  0.0, 120.0)
	level_label.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 62.0)

	# ── Coin: left column, row 3 ──
	coin_label.set_anchor_and_offset(SIDE_LEFT,   0.0,  4.0)
	coin_label.set_anchor_and_offset(SIDE_TOP,    0.0, 64.0)
	coin_label.set_anchor_and_offset(SIDE_RIGHT,  0.0, 120.0)
	coin_label.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 81.0)

	# ── Kill count: left column, row 4 ──
	if kills_label:
		kills_label.set_anchor_and_offset(SIDE_LEFT,   0.0,   4.0)
		kills_label.set_anchor_and_offset(SIDE_TOP,    0.0,  83.0)
		kills_label.set_anchor_and_offset(SIDE_RIGHT,  0.0, 120.0)
		kills_label.set_anchor_and_offset(SIDE_BOTTOM, 0.0, 100.0)

func _process(_delta: float) -> void:
	var s := int(GameManager.survival_time)
	if s != _last_displayed_second:
		_last_displayed_second = s
		timer_label.text = GameManager.get_time_string()

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
	level_label.text = "Lvl %d" % lvl

func _on_wave_changed(w: int) -> void:
	wave_label.text = "Wave %d" % w

func _on_coins_changed(total: int) -> void:
	coin_label.text = "🪙 " + str(total)

func _on_kills_changed(total: int) -> void:
	if kills_label:
		kills_label.text = "☠ " + str(total)
