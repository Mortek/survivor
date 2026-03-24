class_name LightningChain
extends Node2D
## LightningChain – auto-fires chain lightning that bounces between nearby enemies.
## Added as a child of the Player node by player.gd when the upgrade is taken.
## Thunder God (level 5) fires 8 chains and adds a final AOE burst.

# ── Level table ───────────────────────────────────────────────────────────────
# [dmg_mult, bounces, cooldown, range]
const LEVEL_TABLE: Array = [
	[1.0, 2, 2.0,  200.0],   # level 1
	[1.4, 3, 1.55, 240.0],   # level 2
	[2.0, 4, 1.15, 270.0],   # level 3
	[3.0, 6, 0.80, 320.0],   # level 4
	[4.5, 8, 0.50, 380.0],   # level 5 – Thunder God evolution
]

const THUNDER_GOD_AOE_RADIUS := 80.0

var _level:    int   = 1
var _timer:    float = 0.0
var _cooldown: float = 2.0
var _dmg_mult: float = 1.0
var _bounces:  int   = 2
var _range:    float = 200.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_timer += delta
	if _timer >= _cooldown:
		_timer = 0.0
		_fire()

## Called from player.gd whenever lightning_level stat changes.
func set_level(lvl: int) -> void:
	_level    = clampi(lvl, 1, LEVEL_TABLE.size())
	var t: Array = LEVEL_TABLE[_level - 1]
	_dmg_mult = float(t[0])
	_bounces  = int(t[1])
	_cooldown = float(t[2])
	_range    = float(t[3])

# ── Firing ────────────────────────────────────────────────────────────────────
func _fire() -> void:
	var parent  := get_parent()
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	# Sort by distance to player
	enemies.sort_custom(func(a: Node, b: Node) -> bool:
		return parent.global_position.distance_squared_to(a.global_position) \
			 < parent.global_position.distance_squared_to(b.global_position)
	)

	var dmg  := int(GameManager.stats["damage"] * _dmg_mult)
	var hit  : Array   = []
	var cur  : Node2D  = enemies[0]

	for _i in _bounces:
		if not is_instance_valid(cur) or cur in hit:
			break
		var from_pos: Vector2
		if hit.is_empty():
			from_pos = parent.global_position
		else:
			from_pos = (hit[-1] as Node2D).global_position
		hit.append(cur)
		cur.take_damage(float(dmg))
		_draw_bolt(from_pos, cur.global_position)

		# Find next nearest unhit enemy within range
		var nxt: Node2D = null
		var best_d := _range * _range
		for e in enemies:
			if e in hit or not is_instance_valid(e):
				continue
			var d := cur.global_position.distance_squared_to(e.global_position)
			if d < best_d:
				best_d = d
				nxt = e
		if not nxt:
			break
		cur = nxt

	# Thunder God evolution: AOE burst at last hit position
	if (_level >= 5 or GameManager.stats.get("thunder_god", false)) and not hit.is_empty():
		var last_pos := (hit[-1] as Node2D).global_position
		_thunder_aoe(last_pos, dmg, hit, enemies)
		_draw_aoe_ring(last_pos)

func _thunder_aoe(pos: Vector2, dmg: int, already_hit: Array, enemies: Array) -> void:
	var aoe_sq := THUNDER_GOD_AOE_RADIUS * THUNDER_GOD_AOE_RADIUS
	for e in enemies:
		if e in already_hit or not is_instance_valid(e):
			continue
		if pos.distance_squared_to((e as Node2D).global_position) <= aoe_sq:
			e.take_damage(float(dmg) * 0.6)

# ── Visuals ───────────────────────────────────────────────────────────────────
func _draw_bolt(from: Vector2, to: Vector2) -> void:
	# Draw multiple layered lines for a glowing effect
	var points: Array[Vector2] = []
	points.append(from)
	for i in range(1, 9):
		var t  := float(i) / 9.0
		var p  := from.lerp(to, t)
		p += Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
		points.append(p)
	points.append(to)

	var glow := _create_line_layer(points,  9, 6.0, Color(0.3,  0.75, 1.0, 0.25))
	var mid  := _create_line_layer(points, 10, 3.0, Color(0.55, 0.9,  1.0, 0.75))
	var core := _create_line_layer(points, 11, 1.2, Color(0.85, 1.0,  1.0, 1.0))

	for line: Line2D in [glow, mid, core]:
		var tw: Tween = line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.28)
		tw.tween_callback(line.queue_free)

func _create_line_layer(points: Array[Vector2], z: int, w: float, col: Color) -> Line2D:
	var line := Line2D.new()
	line.z_index       = z
	line.width         = w
	line.default_color = col
	line.antialiased   = true
	for pt in points:
		line.add_point(pt)
	get_tree().current_scene.add_child(line)
	return line

func _draw_aoe_ring(pos: Vector2) -> void:
	# Draw an expanding ring at the AOE position
	var ring := Node2D.new()
	ring.global_position = pos
	ring.z_index = 9
	get_tree().current_scene.add_child(ring)
	# We'll animate the scale of a drawn circle via a script approach using a timer
	var duration := 0.35
	var sc := get_tree().create_tween()
	sc.tween_method(
		func(progress: float) -> void:
			if is_instance_valid(ring):
				ring.queue_redraw()
				ring.set_meta("progress", progress),
		0.0, 1.0, duration
	)
	sc.tween_callback(ring.queue_free)
	ring.connect("draw", func() -> void:
		var p: float = ring.get_meta("progress", 0.0)
		ring.draw_arc(Vector2.ZERO, THUNDER_GOD_AOE_RADIUS * p,
			0.0, TAU, 32, Color(0.55, 0.88, 1.0, 1.0 - p), 3.0)
	)
	ring.set_meta("progress", 0.0)
