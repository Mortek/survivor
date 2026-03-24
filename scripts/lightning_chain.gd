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
	# Layered glow lines from wide bloom to tight core
	var points: Array[Vector2] = []
	points.append(from)
	for i in range(1, 13):
		var t  := float(i) / 13.0
		var p  := from.lerp(to, t)
		var jitter := lerpf(22.0, 8.0, t)
		p += Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))
		points.append(p)
	points.append(to)

	var mega    := _create_line_layer(points,  7, 22.0, Color(0.15, 0.3,  1.0, 0.05))
	var bloom   := _create_line_layer(points,  8, 16.0, Color(0.2,  0.5,  1.0, 0.10))
	var glow    := _create_line_layer(points,  9, 10.0, Color(0.3,  0.7,  1.0, 0.25))
	var outer   := _create_line_layer(points, 10,  5.5, Color(0.45, 0.85, 1.0, 0.60))
	var mid     := _create_line_layer(points, 11,  3.0, Color(0.75, 0.95, 1.0, 0.90))
	var core    := _create_line_layer(points, 12,  1.2, Color(1.0,  1.0,  1.0, 1.0))

	for line: Line2D in [mega, bloom, glow, outer, mid, core]:
		var tw: Tween = line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.35)
		tw.tween_callback(line.queue_free)

	# Impact flash at hit position
	_draw_impact_flash(to)

func _draw_impact_flash(pos: Vector2) -> void:
	var flash := Node2D.new()
	flash.global_position = pos
	flash.z_index = 13
	get_tree().current_scene.add_child(flash)
	flash.set_meta("progress", 0.0)
	flash.connect("draw", func() -> void:
		var p: float = flash.get_meta("progress", 0.0)
		var alpha := (1.0 - p) * 0.9
		var r := 8.0 + p * 18.0
		flash.draw_circle(Vector2.ZERO, r * 1.5, Color(0.3, 0.6, 1.0, alpha * 0.12))
		flash.draw_circle(Vector2.ZERO, r, Color(0.5, 0.85, 1.0, alpha * 0.35))
		flash.draw_circle(Vector2.ZERO, r * 0.55, Color(0.8, 0.95, 1.0, alpha * 0.65))
		flash.draw_circle(Vector2.ZERO, r * 0.2, Color(1.0, 1.0, 1.0, alpha))
	)
	var tw := flash.create_tween()
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(flash):
			flash.set_meta("progress", v)
			flash.queue_redraw()
	, 0.0, 1.0, 0.25)
	tw.tween_callback(flash.queue_free)

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
	var ring := Node2D.new()
	ring.global_position = pos
	ring.z_index = 9
	get_tree().current_scene.add_child(ring)
	var duration := 0.4
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
		var alpha := (1.0 - p)
		# Multi-layered expanding ring
		ring.draw_arc(Vector2.ZERO, THUNDER_GOD_AOE_RADIUS * p,
			0.0, TAU, 48, Color(0.3, 0.6, 1.0, alpha * 0.15), 12.0)
		ring.draw_arc(Vector2.ZERO, THUNDER_GOD_AOE_RADIUS * p,
			0.0, TAU, 48, Color(0.55, 0.88, 1.0, alpha * 0.6), 4.0)
		ring.draw_arc(Vector2.ZERO, THUNDER_GOD_AOE_RADIUS * p,
			0.0, TAU, 48, Color(0.9, 1.0, 1.0, alpha), 1.5)
	)
	ring.set_meta("progress", 0.0)
