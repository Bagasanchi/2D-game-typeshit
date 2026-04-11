extends Node2D

@export_node_path("AnimationPlayer") var cutscene_player_path: NodePath = NodePath("CutscenePlayer")
@export var cutscene_animation_name: StringName = &"phone_cutscene"
@export var play_cutscene_only_once: bool = true

@onready var _phone: Node = $StaticBody2D3/Node2D

var _cutscene_started: bool = false

func _ready() -> void:
	if _phone == null:
		push_warning("Room cutscene setup missing phone node.")
		return

	if _phone.has_signal("interacted"):
		_phone.connect("interacted", _on_phone_interacted)
	else:
		push_warning("Phone node does not expose an 'interacted' signal.")

func _on_phone_interacted(_player: Node) -> void:
	if play_cutscene_only_once and _cutscene_started:
		return

	var cutscene_player: AnimationPlayer = get_node_or_null(cutscene_player_path) as AnimationPlayer
	if cutscene_player == null:
		push_warning("Cutscene AnimationPlayer was not found at: %s" % [cutscene_player_path])
		return

	if not cutscene_player.has_animation(cutscene_animation_name):
		push_warning("Cutscene animation '%s' was not found." % [cutscene_animation_name])
		return

	_cutscene_started = true
	cutscene_player.play(cutscene_animation_name)
