class_name ObjectPool
extends Node
## Generic scene-instance object pool.
## Assign `scene` in the Inspector, then call get_object() / return_object().

@export var scene: PackedScene
@export var initial_size: int = 15

var _pool: Array[Node] = []

func _ready() -> void:
	assert(scene != null, "ObjectPool: scene must be assigned in Inspector")
	for i in initial_size:
		_create_instance()

# ── Public API ────────────────────────────────────────────────────────────────
func get_object() -> Node:
	## Returns an inactive object from the pool, expanding if needed.
	for obj in _pool:
		if not obj.visible:
			_activate(obj)
			return obj
	# Pool exhausted – grow
	var obj := _create_instance()
	_activate(obj)
	return obj

func return_object(obj: Node) -> void:
	## Return an object back to the pool (hide + disable processing).
	## Uses set_deferred because this may be called from a physics callback.
	if not is_instance_valid(obj):
		return
	obj.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	obj.hide()

# ── Private ───────────────────────────────────────────────────────────────────
func _create_instance() -> Node:
	var obj := scene.instantiate()
	obj.process_mode = Node.PROCESS_MODE_DISABLED
	obj.hide()
	add_child(obj)
	_pool.append(obj)
	return obj

func _activate(obj: Node) -> void:
	obj.process_mode = Node.PROCESS_MODE_INHERIT
	obj.show()
