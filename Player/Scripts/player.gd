class_name Player extends CharacterBody2D

var move_speed : float = 100.0
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
	direction.y = Input.get_action_strength("down") - Input.get_action_strength("up")

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
