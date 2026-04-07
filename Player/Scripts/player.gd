class_name Player extends CharacterBody2D

<<<<<<< HEAD
var move_speed : float = 200.0
@export var flip_visual_correction_px: float = 7.0
=======
var move_speed : float = 100.0
>>>>>>> d7c9932785a760ed3cd1b02e3f9f82601d4b2d2f
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var _sprite_base_position: Vector2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_sprite_base_position = animated_sprite.position

func _set_facing(is_left: bool) -> void:
	animated_sprite.flip_h = is_left

func _physics_process(_delta: float) -> void:
	var direction : Vector2 = Vector2.ZERO
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")

	velocity = direction.normalized() * move_speed

	if Input.is_physical_key_pressed(KEY_SPACE):
		animated_sprite.play("jump")
	elif direction != Vector2.ZERO:
		animated_sprite.play("run")
		if direction.x != 0.0:
			_set_facing(direction.x < 0.0)
	else:
		animated_sprite.play("idle")

	move_and_slide()
