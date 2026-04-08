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
@export var attack_offset_x_tweak: float = 10.0
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var _sprite_base_position: Vector2
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 1.0
var _dash_direction: float = 1.0
var _dash_input_was_pressed: bool = false
var _roll_time_left: float = 0.0
var _roll_cooldown_left: float = 0.0
var _roll_direction: float = 1.0
var _is_attacking: bool = false
var _attack_step: int = 0
var _queued_attack: bool = false
var _idle_reference_size: Vector2 = Vector2.ZERO

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_sprite_base_position = animated_sprite.position
	animated_sprite.animation_finished.connect(_on_animation_finished)
	for attack_name in ["attack1", "attack2", "attack3"]:
		if animated_sprite.sprite_frames.has_animation(attack_name):
			animated_sprite.sprite_frames.set_animation_loop(attack_name, false)
	if animated_sprite.sprite_frames.has_animation("idle"):
		var idle_tex: Texture2D = animated_sprite.sprite_frames.get_frame_texture("idle", 0)
		if idle_tex != null:
			_idle_reference_size = idle_tex.get_size()

func _update_sprite_offset() -> void:
	if _idle_reference_size == Vector2.ZERO:
		animated_sprite.offset = Vector2.ZERO
		return

	var anim_name: String = String(animated_sprite.animation)
	if not anim_name.begins_with("attack"):
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
	# Keep vertical alignment stable and apply a tiny horizontal nudge for attack frame alignment.
	var x_offset: float = attack_offset_x_tweak
	var y_offset: float = (_idle_reference_size.y - current_size.y) * 0.5
	animated_sprite.offset = Vector2(x_offset, y_offset)

func _stop_attack() -> void:
	_is_attacking = false
	_attack_step = 0
	_queued_attack = false

func _start_attack() -> void:
	if not animated_sprite.sprite_frames.has_animation("attack1"):
		return
	_is_attacking = true
	_attack_step = 1
	_queued_attack = false
	animated_sprite.play("attack1")

func _on_animation_finished() -> void:
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

func _physics_process(delta: float) -> void:
	# Keep the sprite anchored even when animation frames have inconsistent pivots.
	animated_sprite.position = _sprite_base_position

	var direction : Vector2 = Vector2.ZERO
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	var dash_input_pressed := Input.is_action_pressed("dash") or Input.is_key_pressed(KEY_SHIFT)
	var dash_just_pressed := dash_input_pressed and not _dash_input_was_pressed
	_dash_input_was_pressed = dash_input_pressed
	var roll_just_pressed := Input.is_action_just_pressed("roll")
	var attack_just_pressed := Input.is_action_just_pressed("attack")
	_dash_time_left = max(_dash_time_left - delta, 0.0)
	_dash_cooldown_left = max(_dash_cooldown_left - delta, 0.0)
	_roll_time_left = max(_roll_time_left - delta, 0.0)
	_roll_cooldown_left = max(_roll_cooldown_left - delta, 0.0)

	if _is_attacking:
		if not animated_sprite.animation.begins_with("attack"):
			_stop_attack()
		elif not animated_sprite.is_playing():
			_stop_attack()

	if attack_just_pressed:
		if _is_attacking:
			_queued_attack = true
		elif _dash_time_left <= 0.0 and _roll_time_left <= 0.0:
			_start_attack()

	if direction.x != 0.0 and _roll_time_left <= 0.0:
		_set_facing(direction.x < 0.0)

	if dash_just_pressed and _dash_time_left <= 0.0 and _dash_cooldown_left <= 0.0:
		_dash_direction = sign(direction.x) if direction.x != 0.0 else (-1.0 if animated_sprite.flip_h else 1.0)
		_dash_time_left = dash_duration
		_dash_cooldown_left = dash_cooldown

	if roll_just_pressed and is_on_floor() and _dash_time_left <= 0.0 and _roll_time_left <= 0.0 and _roll_cooldown_left <= 0.0:
		_roll_direction = sign(direction.x) if direction.x != 0.0 else (-1.0 if animated_sprite.flip_h else 1.0)
		_roll_time_left = roll_duration
		_roll_cooldown_left = roll_cooldown

	if _dash_time_left > 0.0:
		velocity.x = _dash_direction * dash_speed
		velocity.y = 0.0
	elif _roll_time_left > 0.0:
		velocity.x = _roll_direction * roll_speed
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
	elif _roll_time_left > 0.0:
		if animated_sprite.sprite_frames.has_animation("roll"):
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
