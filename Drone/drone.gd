extends Node2D

@export var is_alive: bool = true
@export var follow_target_path: NodePath = NodePath("../Player")
@export var follow_speed: float = 165.0
@export var follow_start_distance: float = 34.0
@export var follow_stop_distance: float = 16.0
@export var follow_behind_distance: float = 20.0
@export var follow_vertical_offset: float = 0.0
@export var direction_update_velocity_x_threshold: float = 1.5
@export var turn_reposition_distance: float = 6.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var _follow_target: Node2D
var _is_following: bool = false
var _behind_direction_x: float = 1.0

func _ready() -> void:
	_resolve_follow_target()
	_seed_follow_direction()
	_update_animation()

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	if _follow_target == null or not is_instance_valid(_follow_target):
		_resolve_follow_target()
		if _follow_target == null:
			return
		_seed_follow_direction()

	_update_follow_direction()

	var start_distance: float = maxf(follow_start_distance, follow_stop_distance + 0.01)
	var player_distance: float = global_position.distance_to(_follow_target.global_position)
	var desired_position: Vector2 = _get_desired_follow_position()
	var desired_distance: float = global_position.distance_to(desired_position)
	if _is_following:
		if desired_distance <= turn_reposition_distance:
			_is_following = false
	else:
		if player_distance >= start_distance or desired_distance >= turn_reposition_distance:
			_is_following = true

	if not _is_following:
		return

	var to_target: Vector2 = desired_position - global_position
	var distance: float = to_target.length()
	if distance <= 0.001:
		return

	var move_distance: float = minf(distance, follow_speed * delta)
	if move_distance <= 0.0:
		return

	global_position += to_target / distance * move_distance

	if absf(to_target.x) > 0.01:
		animated_sprite.flip_h = to_target.x < 0.0

func set_alive(value: bool) -> void:
	is_alive = value
	_update_animation()

func set_dead() -> void:
	set_alive(false)

func set_alive_state() -> void:
	set_alive(true)

func _resolve_follow_target() -> void:
	_follow_target = null

	if not follow_target_path.is_empty():
		var target_node: Node = get_node_or_null(follow_target_path)
		if target_node is Node2D:
			_follow_target = target_node as Node2D
			return

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return

	var named_target: Node2D = _find_named_player_target(current_scene)
	if named_target != null:
		_follow_target = named_target
		return

	var discovered_target: Node2D = _find_player_target_in_scene(current_scene)
	if discovered_target != null:
		_follow_target = discovered_target

func _find_named_player_target(root: Node) -> Node2D:
	for target_name in ["Player", "Player1", "player_1"]:
		var candidate: Node = root.get_node_or_null(target_name)
		if candidate is Node2D and _is_player_candidate(candidate):
			return candidate as Node2D

	return null

func _find_player_target_in_scene(root: Node) -> Node2D:
	var body_nodes: Array[Node] = root.find_children("*", "CharacterBody2D", true, false)
	for candidate in body_nodes:
		if candidate is Node2D and _is_player_candidate(candidate):
			return candidate as Node2D

	return null

func _is_player_candidate(node: Node) -> bool:
	if not (node is CharacterBody2D):
		return false

	if node.name == "Player" or node.name == "Player1" or node.name == "player_1":
		return true

	var node_script: Variant = node.get_script()
	if node_script is Script:
		return (node_script as Script).resource_path == "res://Player/Scripts/player.gd"

	return false

func _seed_follow_direction() -> void:
	if _follow_target == null:
		return

	var delta_x: float = _follow_target.global_position.x - global_position.x
	if absf(delta_x) > 1.0:
		_behind_direction_x = signf(delta_x)
		return

	if _follow_target.has_node("AnimatedSprite2D"):
		var target_sprite: AnimatedSprite2D = _follow_target.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if target_sprite != null:
			_behind_direction_x = -1.0 if target_sprite.flip_h else 1.0

func _update_follow_direction() -> void:
	if _follow_target == null:
		return

	if _follow_target is CharacterBody2D:
		var target_velocity_x: float = (_follow_target as CharacterBody2D).velocity.x
		if absf(target_velocity_x) > direction_update_velocity_x_threshold:
			_behind_direction_x = signf(target_velocity_x)
			return

	var facing_direction_x: float = _get_target_facing_direction_x()
	if absf(facing_direction_x) > 0.0:
		_behind_direction_x = facing_direction_x

func _get_target_facing_direction_x() -> float:
	if _follow_target == null or not _follow_target.has_node("AnimatedSprite2D"):
		return 0.0

	var target_sprite: AnimatedSprite2D = _follow_target.get_node("AnimatedSprite2D") as AnimatedSprite2D
	if target_sprite == null:
		return 0.0

	return -1.0 if target_sprite.flip_h else 1.0

func _get_desired_follow_position() -> Vector2:
	if _follow_target == null:
		return global_position

	return _follow_target.global_position + Vector2(-_behind_direction_x * follow_behind_distance, follow_vertical_offset)

func _update_animation() -> void:
	if animated_sprite == null:
		return

	if is_alive:
		animated_sprite.play("move")
	else:
		animated_sprite.play("dead")