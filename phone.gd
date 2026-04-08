extends Node2D

signal interacted(player)

@onready var interact_area: Area2D = $InteractArea
@onready var press_e_button: Button = $PromptCanvasLayer/PressEButton
@onready var phone_screen_root: Control = $PhoneScreenLayer/PhoneScreenRoot

var _player_in_range: Player = null

func _ready() -> void:
	interact_area.body_entered.connect(_on_interact_area_body_entered)
	interact_area.body_exited.connect(_on_interact_area_body_exited)
	press_e_button.pressed.connect(_on_press_e_button_pressed)
	_set_prompt_visible(false)

func _unhandled_input(event: InputEvent) -> void:
	if phone_screen_root.visible and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		_set_phone_screen_visible(false)
		get_viewport().set_input_as_handled()
		return

	if _player_in_range == null:
		return

	if event.is_action_pressed("interact"):
		_interact_with_phone()
		get_viewport().set_input_as_handled()

func _on_interact_area_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_in_range = body as Player
		_set_prompt_visible(true)

func _on_interact_area_body_exited(body: Node2D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		_set_prompt_visible(false)

func _on_press_e_button_pressed() -> void:
	_interact_with_phone()

func _interact_with_phone() -> void:
	if _player_in_range == null:
		return

	interacted.emit(_player_in_range)
	_set_phone_screen_visible(true)

func _set_prompt_visible(visible_state: bool) -> void:
	press_e_button.visible = visible_state
	press_e_button.disabled = not visible_state

	if visible_state:
		press_e_button.grab_focus()
	elif press_e_button.has_focus():
		press_e_button.release_focus()

func _set_phone_screen_visible(visible_state: bool) -> void:
	phone_screen_root.visible = visible_state