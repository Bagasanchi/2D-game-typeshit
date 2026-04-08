extends Node2D

@export var is_alive: bool = true

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	_update_animation()

func set_alive(value: bool) -> void:
	is_alive = value
	_update_animation()

func set_dead() -> void:
	set_alive(false)

func set_alive_state() -> void:
	set_alive(true)

func _update_animation() -> void:
	if animated_sprite == null:
		return

	if is_alive:
		animated_sprite.play("move")
	else:
		animated_sprite.play("dead")