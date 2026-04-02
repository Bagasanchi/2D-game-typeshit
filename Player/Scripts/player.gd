class_name Player extends CharacterBody2D

var move_speed : float = 100.0
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _physics_process(delta: float) -> void:
	var direction : Vector2 = Vector2.ZERO
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	direction.y = Input.get_action_strength("down") - Input.get_action_strength("up")

	velocity = direction.normalized() * move_speed

	if direction != Vector2.ZERO:
		animated_sprite.play("walk")
		if direction.x != 0.0:
			animated_sprite.flip_h = direction.x < 0.0
	else:
		animated_sprite.play("idle")

	move_and_slide()
