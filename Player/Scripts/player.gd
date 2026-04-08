class_name Player extends CharacterBody2D

var move_speed : float = 75.0
@export var jump_velocity: float = -220.0
@export var gravity: float = 700.0
@export var dash_speed: float = 260.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.5
@export var roll_speed: float = 170.0
@export var roll_duration: float = 0.45
@export var roll_cooldown: float = 1
@export var roll_startup_frames: int = 2
@export_file("*.tscn") var transformed_player_scene_path: String = ""
@export var default_collision_shape: Shape2D
@export var room_collision_shape: Shape2D
@export_file("*.tscn") var free_move_scene_path: String = ""
@export var attack_offset_x_tweak: float = 10.0
@export var attack_offset_y_tweak: float = 0.0
@export var transform_offset_y_tweak: float = 0.0
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape_node: CollisionShape2D = $CollisionShape2D
var _sprite_base_position: Vector2
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 1.0
var _dash_direction: float = 1.0
var _dash_input_was_pressed: bool = false
var _roll_time_left: float = 0.0
var _roll_cooldown_left: float = 0.0
var _roll_startup_time_left: float = 0.0
var _roll_failsafe_time_left: float = 0.0
var _roll_direction: float = 1.0
var _is_rolling: bool = false
var _is_transforming: bool = false
var _transform_failsafe_time_left: float = 0.0
var _is_attacking: bool = false
var _attack_step: int = 0
var _queued_attack: bool = false
var _idle_reference_size: Vector2 = Vector2.ZERO
var _applied_collision_scene_path: String = ""
var _collision_bottom_y: float = 0.0
var _collision_right_x: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_sprite_base_position = animated_sprite.position
	animated_sprite.animation_finished.connect(_on_animation_finished)
	if collision_shape_node.shape is RectangleShape2D:
		var start_rect: RectangleShape2D = collision_shape_node.shape
		_collision_bottom_y = collision_shape_node.position.y + (start_rect.size.y * 0.5)
		_collision_right_x = collision_shape_node.position.x + (start_rect.size.x * 0.5)
	else:
		_collision_bottom_y = collision_shape_node.position.y
		_collision_right_x = collision_shape_node.position.x
	_apply_scene_collision_shape()
	for attack_name in ["attack1", "attack2", "attack3"]:
		if animated_sprite.sprite_frames.has_animation(attack_name):
			animated_sprite.sprite_frames.set_animation_loop(attack_name, false)
	if animated_sprite.sprite_frames.has_animation("roll"):
		animated_sprite.sprite_frames.set_animation_loop("roll", false)
	if animated_sprite.sprite_frames.has_animation("transform"):
		animated_sprite.sprite_frames.set_animation_loop("transform", false)
	if animated_sprite.sprite_frames.has_animation("idle"):
		var idle_tex: Texture2D = animated_sprite.sprite_frames.get_frame_texture("idle", 0)
		if idle_tex != null:
			_idle_reference_size = idle_tex.get_size()

func _get_roll_startup_time() -> float:
	if roll_startup_frames <= 0 or not animated_sprite.sprite_frames.has_animation("roll"):
		return 0.0

	var frame_count: int = animated_sprite.sprite_frames.get_frame_count("roll")
	if frame_count <= 0:
		return 0.0

	var speed: float = animated_sprite.sprite_frames.get_animation_speed("roll")
	if speed <= 0.0:
		return 0.0

	var startup_frame_count: int = mini(roll_startup_frames, frame_count)
	var startup_time: float = 0.0
	for i in startup_frame_count:
		startup_time += animated_sprite.sprite_frames.get_frame_duration("roll", i)

	return startup_time / speed

func _get_animation_length(animation_name: String) -> float:
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return 0.0

	var frame_count: int = animated_sprite.sprite_frames.get_frame_count(animation_name)
	if frame_count <= 0:
		return 0.0

	var speed: float = animated_sprite.sprite_frames.get_animation_speed(animation_name)
	if speed <= 0.0:
		return 0.0

	var total: float = 0.0
	for i in frame_count:
		total += animated_sprite.sprite_frames.get_frame_duration(animation_name, i)

	return total / speed

func _apply_scene_collision_shape() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return

	var current_scene_path: String = current_scene.scene_file_path
	if current_scene_path == _applied_collision_scene_path:
		return

	var is_room_scene: bool = _is_free_move_scene()
	var target_shape: Shape2D = default_collision_shape
	if is_room_scene and room_collision_shape != null:
		target_shape = room_collision_shape

	if target_shape != null:
		collision_shape_node.shape = target_shape

	_apply_collision_size(9.0 if is_room_scene else 16.0, 5.0 if is_room_scene else 0.0, 2.0 if is_room_scene else 0.0)

	_applied_collision_scene_path = current_scene_path

func _apply_collision_size(target_height: float, extra_left_width: float, extra_right_width: float) -> void:
	if not (collision_shape_node.shape is RectangleShape2D):
		return

	var source_rect: RectangleShape2D = collision_shape_node.shape
	var rect_copy: RectangleShape2D = source_rect.duplicate()
	rect_copy.size.x = source_rect.size.x + extra_left_width + extra_right_width
	rect_copy.size.y = target_height
	collision_shape_node.shape = rect_copy
	collision_shape_node.position.x = (_collision_right_x + extra_right_width) - (rect_copy.size.x * 0.5)
	collision_shape_node.position.y = _collision_bottom_y - (target_height * 0.5)

func _update_sprite_offset() -> void:
	if _idle_reference_size == Vector2.ZERO:
		animated_sprite.offset = Vector2.ZERO
		return

	var anim_name: String = String(animated_sprite.animation)
	var needs_alignment: bool = anim_name.begins_with("attack") or anim_name == "transform"
	if not needs_alignment:
		animated_sprite.offset = Vector2.ZERO
		return

	var frame_count: int = animated_sprite.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		animated_sprite.offset = Vector2.ZERO
		return

	var frame_index: int = clampi(animated_sprite.frame, 0, frame_count - 1)
	var current_tex: Texture2D = animated_sprite.sprite_frames.get_frame_texture(anim_name, frame_index)
	if current_tex == null:
		animated_sprite.offset = Vector2.ZERO
		return

	var current_size: Vector2 = current_tex.get_size()
	# Keep vertical alignment stable for varying frame sizes.
	var x_offset: float = 0.0
	if anim_name.begins_with("attack"):
		# Attack frames need a tiny horizontal nudge for weapon alignment.
		x_offset = attack_offset_x_tweak
		if animated_sprite.flip_h:
			x_offset = -x_offset
	var y_offset: float = (_idle_reference_size.y - current_size.y) * 0.5
	if anim_name.begins_with("attack"):
		y_offset += attack_offset_y_tweak
	elif anim_name == "transform":
		y_offset += transform_offset_y_tweak
	animated_sprite.offset = Vector2(x_offset, y_offset)

func _stop_attack() -> void:
	_is_attacking = false
	_attack_step = 0
	_queued_attack = false

func _perform_transform_swap() -> void:
	if transformed_player_scene_path.is_empty():
		_is_transforming = false
		_transform_failsafe_time_left = 0.0
		return

	var next_scene: PackedScene = load(transformed_player_scene_path) as PackedScene
	if next_scene == null:
		_is_transforming = false
		_transform_failsafe_time_left = 0.0
		return

	var parent: Node = get_parent()
	if parent == null:
		_is_transforming = false
		_transform_failsafe_time_left = 0.0
		return

	var child_index: int = get_index()
	var previous_transform: Transform2D = global_transform
	var previous_velocity: Vector2 = velocity
	var previous_flip_h: bool = animated_sprite.flip_h

	var spawned: Node = next_scene.instantiate()
	if spawned == null:
		_is_transforming = false
		_transform_failsafe_time_left = 0.0
		return

	parent.add_child(spawned)
	parent.move_child(spawned, child_index)

	if spawned is Node2D:
		(spawned as Node2D).global_transform = previous_transform

	if spawned is CharacterBody2D:
		(spawned as CharacterBody2D).velocity = previous_velocity

	if spawned.has_node("AnimatedSprite2D"):
		var spawned_sprite: AnimatedSprite2D = spawned.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if spawned_sprite != null:
			spawned_sprite.flip_h = previous_flip_h

	queue_free()

func _start_transform() -> void:
	if transformed_player_scene_path.is_empty():
		return

	_is_transforming = true
	_roll_time_left = 0.0
	_roll_startup_time_left = 0.0
	_roll_failsafe_time_left = 0.0
	_dash_time_left = 0.0
	_stop_attack()

	if animated_sprite.sprite_frames.has_animation("transform"):
		animated_sprite.play("transform")
		_transform_failsafe_time_left = max(0.05, _get_animation_length("transform") + 0.1)
	else:
		_perform_transform_swap()

func _start_attack() -> void:
	if not animated_sprite.sprite_frames.has_animation("attack1"):
		return
	_is_attacking = true
	_attack_step = 1
	_queued_attack = false
	animated_sprite.play("attack1")

func _on_animation_finished() -> void:
	if animated_sprite.animation == "transform" and _is_transforming:
		_perform_transform_swap()
		return

	if animated_sprite.animation == "roll":
		_is_rolling = false
		_roll_time_left = 0.0
		_roll_startup_time_left = 0.0
		_roll_failsafe_time_left = 0.0
		return

	if not _is_attacking:
		return

	if not animated_sprite.animation.begins_with("attack"):
		return

	var next_step: int = _attack_step + 1
	var next_attack: String = "attack%d" % next_step
	if _queued_attack and next_step <= 3 and animated_sprite.sprite_frames.has_animation(next_attack):
		_attack_step = next_step
		_queued_attack = false
		animated_sprite.play(next_attack)
	else:
		_stop_attack()

func _set_facing(is_left: bool) -> void:
	animated_sprite.flip_h = is_left

func _is_free_move_scene() -> bool:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return false
	var current_scene_path: String = current_scene.scene_file_path
	if not free_move_scene_path.is_empty() and current_scene_path == free_move_scene_path:
		return true
	var current_scene_file: String = current_scene_path.get_file().to_lower()
	return current_scene_file == "room.tscn"

func _get_vertical_input() -> float:
	var up_strength: float = 0.0
	var down_strength: float = 0.0

	if InputMap.has_action("up"):
		up_strength = Input.get_action_strength("up")
	elif InputMap.has_action("ui_up"):
		up_strength = Input.get_action_strength("ui_up")

	if InputMap.has_action("down"):
		down_strength = Input.get_action_strength("down")
	elif InputMap.has_action("ui_down"):
		down_strength = Input.get_action_strength("ui_down")

	if is_zero_approx(up_strength) and Input.is_key_pressed(KEY_W):
		up_strength = 1.0
	if is_zero_approx(down_strength) and Input.is_key_pressed(KEY_S):
		down_strength = 1.0

	return down_strength - up_strength

func _physics_process(delta: float) -> void:
	# Keep the sprite anchored even when animation frames have inconsistent pivots.
	animated_sprite.position = _sprite_base_position
	_apply_scene_collision_shape()

	var direction : Vector2 = Vector2.ZERO
	var is_free_move_scene: bool = _is_free_move_scene()
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	var dash_input_pressed := Input.is_action_pressed("dash") or Input.is_key_pressed(KEY_SHIFT)
	var dash_just_pressed := dash_input_pressed and not _dash_input_was_pressed
	_dash_input_was_pressed = dash_input_pressed
	var roll_just_pressed := Input.is_action_just_pressed("roll")
	var attack_just_pressed := Input.is_action_just_pressed("attack")
	var transform_just_pressed := Input.is_action_just_pressed("transform")
	_dash_time_left = max(_dash_time_left - delta, 0.0)
	_dash_cooldown_left = max(_dash_cooldown_left - delta, 0.0)
	_roll_time_left = max(_roll_time_left - delta, 0.0)
	_roll_startup_time_left = max(_roll_startup_time_left - delta, 0.0)
	_roll_failsafe_time_left = max(_roll_failsafe_time_left - delta, 0.0)
	_transform_failsafe_time_left = max(_transform_failsafe_time_left - delta, 0.0)
	_roll_cooldown_left = max(_roll_cooldown_left - delta, 0.0)

	if _is_rolling and _roll_failsafe_time_left <= 0.0:
		_is_rolling = false
		_roll_time_left = 0.0
		_roll_startup_time_left = 0.0

	if _is_transforming and _transform_failsafe_time_left <= 0.0:
		_perform_transform_swap()
		return

	if transform_just_pressed and not _is_transforming and _dash_time_left <= 0.0 and not _is_rolling:
		_start_transform()

	if _is_transforming:
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += gravity * delta
		else:
			velocity.y = 0.0

		if animated_sprite.sprite_frames.has_animation("transform"):
			if animated_sprite.animation != "transform" or not animated_sprite.is_playing():
				animated_sprite.play("transform")
		else:
			animated_sprite.play("idle")

		_update_sprite_offset()
		move_and_slide()
		return

	if _is_attacking:
		if not animated_sprite.animation.begins_with("attack"):
			_stop_attack()
		elif not animated_sprite.is_playing():
			_stop_attack()

	if attack_just_pressed and not is_free_move_scene:
		if _is_attacking:
			_queued_attack = true
		elif _dash_time_left <= 0.0 and not _is_rolling:
			_start_attack()

	if is_free_move_scene:
		if _is_attacking:
			_stop_attack()

		direction.y = _get_vertical_input()
		if direction.x != 0.0:
			_set_facing(direction.x < 0.0)

		if _is_attacking:
			velocity = Vector2.ZERO
		else:
			velocity = direction.normalized() * move_speed if direction != Vector2.ZERO else Vector2.ZERO

		if _is_attacking:
			pass
		elif direction != Vector2.ZERO:
			animated_sprite.play("run")
		else:
			animated_sprite.play("idle")

		_update_sprite_offset()
		move_and_slide()
		return

	if direction.x != 0.0 and not _is_rolling:
		_set_facing(direction.x < 0.0)

	if dash_just_pressed and _dash_time_left <= 0.0 and _dash_cooldown_left <= 0.0:
		_dash_direction = sign(direction.x) if direction.x != 0.0 else (-1.0 if animated_sprite.flip_h else 1.0)
		_dash_time_left = dash_duration
		_dash_cooldown_left = dash_cooldown

	if roll_just_pressed and is_on_floor() and _dash_time_left <= 0.0 and not _is_rolling and _roll_cooldown_left <= 0.0:
		_roll_direction = sign(direction.x) if direction.x != 0.0 else (-1.0 if animated_sprite.flip_h else 1.0)
		_is_rolling = true
		_roll_time_left = roll_duration
		_roll_startup_time_left = min(_get_roll_startup_time(), _roll_time_left)
		_roll_failsafe_time_left = max(_get_animation_length("roll") + 0.05, roll_duration + 0.05)
		_roll_cooldown_left = roll_cooldown

	if _dash_time_left > 0.0:
		velocity.x = _dash_direction * dash_speed
		velocity.y = 0.0
	elif _is_rolling:
		var roll_can_move: bool = _roll_time_left > 0.0 and _roll_startup_time_left <= 0.0
		velocity.x = _roll_direction * roll_speed if roll_can_move else 0.0
		if not is_on_floor():
			velocity.y += gravity * delta
		else:
			velocity.y = 0.0
	elif _is_attacking:
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += gravity * delta
		else:
			velocity.y = 0.0
	else:
		velocity.x = direction.x * move_speed

		if not is_on_floor():
			velocity.y += gravity * delta
		elif Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

	if _dash_time_left > 0.0:
		if animated_sprite.sprite_frames.has_animation("dash"):
			animated_sprite.play("dash")
		else:
			animated_sprite.play("run")
	elif _is_rolling:
		if animated_sprite.sprite_frames.has_animation("roll"):
			if animated_sprite.animation != "roll" or not animated_sprite.is_playing():
				animated_sprite.play("roll")
		else:
			animated_sprite.play("run")
	elif _is_attacking:
		pass
	elif not is_on_floor():
		if velocity.y < 0.0:
			animated_sprite.play("jump")
		else:
			animated_sprite.play("fall")
	elif direction != Vector2.ZERO:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

	_update_sprite_offset()

	move_and_slide()
