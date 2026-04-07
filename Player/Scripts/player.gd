class_name Player extends CharacterBody2D

var move_speed : float = 100.0
@export var jump_velocity: float = -220.0
@export var gravity: float = 700.0
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var _sprite_base_position: Vector2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_sprite_base_position = animated_sprite.position

func _set_facing(is_left: bool) -> void:
	animated_sprite.flip_h = is_left

func _physics_process(delta: float) -> void:
	var direction : Vector2 = Vector2.ZERO
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")

	velocity.x = direction.x * move_speed

	if not is_on_floor():
		velocity.y += gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	if direction.x != 0.0:
		_set_facing(direction.x < 0.0)

	if not is_on_floor():
		if velocity.y < 0.0:
			animated_sprite.play("jump")
		else:
			animated_sprite.play("fall")
	elif direction != Vector2.ZERO:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

	move_and_slide()
