class_name Player extends CharacterBody2D

var move_speed : float = 100.0
@export var jump_velocity: float = -220.0
@export var gravity: float = 700.0
@export var dash_speed: float = 260.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.35
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var _sprite_base_position: Vector2
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_direction: float = 1.0
var _dash_input_was_pressed: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_sprite_base_position = animated_sprite.position

func _set_facing(is_left: bool) -> void:
	animated_sprite.flip_h = is_left

func _physics_process(delta: float) -> void:
	var direction : Vector2 = Vector2.ZERO
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	var dash_input_pressed := Input.is_action_pressed("dash") or Input.is_key_pressed(KEY_SHIFT)
	var dash_just_pressed := dash_input_pressed and not _dash_input_was_pressed
	_dash_input_was_pressed = dash_input_pressed
	_dash_time_left = max(_dash_time_left - delta, 0.0)
	_dash_cooldown_left = max(_dash_cooldown_left - delta, 0.0)

	if direction.x != 0.0:
		_set_facing(direction.x < 0.0)

	if dash_just_pressed and _dash_time_left <= 0.0 and _dash_cooldown_left <= 0.0:
		_dash_direction = sign(direction.x) if direction.x != 0.0 else (-1.0 if animated_sprite.flip_h else 1.0)
		_dash_time_left = dash_duration
		_dash_cooldown_left = dash_cooldown

	if _dash_time_left > 0.0:
		velocity.x = _dash_direction * dash_speed
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
	elif not is_on_floor():
		if velocity.y < 0.0:
			animated_sprite.play("jump")
		else:
			animated_sprite.play("fall")
	elif direction != Vector2.ZERO:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

	move_and_slide()
