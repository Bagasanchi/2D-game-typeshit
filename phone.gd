extends Node2D

signal interacted(player)

@onready var interact_area: Area2D = $InteractArea
@onready var press_e_button: Button = $PromptCanvasLayer/PressEButton
@onready var phone_screen_root: Control = $PhoneScreenLayer/PhoneScreenRoot
@onready var apps_grid: GridContainer = $PhoneScreenLayer/PhoneScreenRoot/AppsMargin/AppsGrid

const APP_ICONS_DIR := "res://AppIcons"
const MAX_APP_ICONS := 20
const APP_ICON_SIZE := Vector2(56.0, 56.0)

const DIALOGUE_POS_CENTER := 0
const DIALOGUE_POS_ABOVE_VILLAIN := 1

@export var play_cutscene_every_open: bool = false
@export var villain_texture: Texture2D
@export var villain_size: Vector2 = Vector2(44.0, 44.0)
@export var villain_entry_padding: float = 14.0
@export var villain_corner_margin: Vector2 = Vector2(20.0, 22.0)
@export var villain_move_duration: float = 0.2
@export var villain_row_offset: float = 14.0
@export var dialogue_line_duration: float = 1.25
@export var dialogue_auto_time_per_character: float = 0.035
@export var phone_auto_close_delay: float = 1.0
@export_enum("Center", "Above Villain") var dialogue_position_mode: int = DIALOGUE_POS_ABOVE_VILLAIN
@export var dialogue_panel_size: Vector2 = Vector2(260.0, 92.0)
@export var dialogue_screen_margin: Vector2 = Vector2(10.0, 10.0)
@export var dialogue_villain_gap: float = 10.0
@export var villain_dialogue_lines_en: PackedStringArray = PackedStringArray([
	"- heya.",
	"so... funny story.",
	"i hacked your phone.",
	"yeah, yeah, don't bother checking.",
	"your apps are already crying.",
	"instagram? mine.",
	"facebook? mine.",
	"that one game you swore you'd quit? yeah... still yours. i'm not that cruel.",
	"honestly, i expected a challenge.",
	"but your password?",
	"\"123456seven\"",
	"...",
	"anyway.",
	"i've locked your apps.",
	"if you want them back...",
	"you're gonna have to come get them.",
	"inside.",
	"your own.",
	"phone.",
	"hope you like bugs.",
	"and no, not the cute kind.",
	"see you in there :)"
])

var _player_in_range: Player = null
var _app_icon_nodes: Array[Control] = []
var _cutscene_overlay: Control = null
var _villain_actor: Panel = null
var _villain_visual: TextureRect = null
var _villain_fallback_label: Label = null
var _dialogue_panel: PanelContainer = null
var _dialogue_label: Label = null
var _has_played_cutscene: bool = false
var _is_cutscene_running: bool = false
var _cutscene_run_id: int = 0
var _active_cutscene_tween: Tween = null
var _dialogue_advance_queued: bool = false

func _ready() -> void:
	interact_area.body_entered.connect(_on_interact_area_body_entered)
	interact_area.body_exited.connect(_on_interact_area_body_exited)
	press_e_button.pressed.connect(_on_press_e_button_pressed)
	_set_prompt_visible(false)
	_set_phone_screen_visible(false)
	_populate_app_icons()
	_setup_cutscene_nodes()

func _populate_app_icons() -> void:
	_app_icon_nodes.clear()
	for child in apps_grid.get_children():
		child.queue_free()

	var dir := DirAccess.open(APP_ICONS_DIR)
	if dir == null:
		push_warning("Could not open app icons folder: %s" % APP_ICONS_DIR)
		return

	var files := dir.get_files()
	files.sort()

	var added := 0
	for file_name in files:
		if not file_name.to_lower().ends_with(".png"):
			continue

		var texture := load("%s/%s" % [APP_ICONS_DIR, file_name]) as Texture2D
		if texture == null:
			continue

		var icon := TextureRect.new()
		icon.custom_minimum_size = APP_ICON_SIZE
		icon.texture = texture
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		apps_grid.add_child(icon)
		_app_icon_nodes.append(icon)

		added += 1
		if added >= MAX_APP_ICONS:
			break

	if added == 0:
		push_warning("No PNG app icons found in %s" % APP_ICONS_DIR)

func _unhandled_input(event: InputEvent) -> void:
	if phone_screen_root.visible and _is_cutscene_running:
		var wants_dialogue_advance := _is_dialogue_advance_event(event)
		if wants_dialogue_advance and _dialogue_panel != null and _dialogue_panel.visible:
			_dialogue_advance_queued = true

		if wants_dialogue_advance or event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			return

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

	if _should_play_cutscene():
		_start_phone_cutscene()

func _should_play_cutscene() -> bool:
	if _is_cutscene_running:
		return false

	if play_cutscene_every_open:
		return true

	return not _has_played_cutscene

func _setup_cutscene_nodes() -> void:
	_cutscene_overlay = Control.new()
	_cutscene_overlay.name = "CutsceneOverlay"
	_cutscene_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cutscene_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutscene_overlay.visible = false
	phone_screen_root.add_child(_cutscene_overlay)

	_villain_actor = Panel.new()
	_villain_actor.name = "VillainActor"
	_villain_actor.custom_minimum_size = villain_size
	_villain_actor.size = villain_size
	_villain_actor.visible = false
	var villain_style := StyleBoxFlat.new()
	villain_style.bg_color = Color(0.88, 0.2, 0.2, 0.95)
	villain_style.corner_radius_top_left = 6
	villain_style.corner_radius_top_right = 6
	villain_style.corner_radius_bottom_right = 6
	villain_style.corner_radius_bottom_left = 6
	_villain_actor.add_theme_stylebox_override("panel", villain_style)
	_cutscene_overlay.add_child(_villain_actor)

	_villain_visual = TextureRect.new()
	_villain_visual.name = "VillainTexture"
	_villain_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_villain_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_villain_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_villain_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_villain_actor.add_child(_villain_visual)

	_villain_fallback_label = Label.new()
	_villain_fallback_label.name = "VillainFallback"
	_villain_fallback_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_villain_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_villain_fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_villain_fallback_label.text = "V"
	_villain_actor.add_child(_villain_fallback_label)

	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.name = "DialoguePanel"
	_dialogue_panel.anchor_left = 0.06
	_dialogue_panel.anchor_top = 0.72
	_dialogue_panel.anchor_right = 0.94
	_dialogue_panel.anchor_bottom = 0.96
	_dialogue_panel.offset_left = 0.0
	_dialogue_panel.offset_top = 0.0
	_dialogue_panel.offset_right = 0.0
	_dialogue_panel.offset_bottom = 0.0
	_dialogue_panel.visible = false
	var dialogue_style := StyleBoxFlat.new()
	dialogue_style.bg_color = Color(0.0, 0.0, 0.0, 0.78)
	dialogue_style.border_color = Color(0.95, 0.95, 0.95, 0.5)
	dialogue_style.border_width_left = 1
	dialogue_style.border_width_top = 1
	dialogue_style.border_width_right = 1
	dialogue_style.border_width_bottom = 1
	dialogue_style.corner_radius_top_left = 6
	dialogue_style.corner_radius_top_right = 6
	dialogue_style.corner_radius_bottom_right = 6
	dialogue_style.corner_radius_bottom_left = 6
	dialogue_style.content_margin_left = 10
	dialogue_style.content_margin_top = 8
	dialogue_style.content_margin_right = 10
	dialogue_style.content_margin_bottom = 8
	_dialogue_panel.add_theme_stylebox_override("panel", dialogue_style)
	_cutscene_overlay.add_child(_dialogue_panel)

	_dialogue_label = Label.new()
	_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_panel.add_child(_dialogue_label)

	_refresh_villain_visual()

func _refresh_villain_visual() -> void:
	if _villain_visual == null or _villain_fallback_label == null:
		return

	_villain_visual.texture = villain_texture
	var has_texture := villain_texture != null
	_villain_visual.visible = has_texture
	_villain_fallback_label.visible = not has_texture

func _start_phone_cutscene() -> void:
	if _is_cutscene_running:
		return

	_is_cutscene_running = true
	_has_played_cutscene = true
	_cutscene_run_id += 1
	var run_id := _cutscene_run_id

	_prepare_cutscene_open_state()
	await get_tree().process_frame

	if not _is_cutscene_valid(run_id):
		return

	var icons_done := await _run_icon_steal_sequence(run_id)
	if not icons_done:
		return

	var dialogue_done := await _run_dialogue_sequence(run_id)
	if not dialogue_done:
		return

	await get_tree().create_timer(max(0.0, phone_auto_close_delay)).timeout
	if not _is_cutscene_valid(run_id):
		return

	_set_phone_screen_visible(false)

func _prepare_cutscene_open_state() -> void:
	_refresh_villain_visual()

	if _cutscene_overlay != null:
		_cutscene_overlay.visible = true

	if _villain_actor != null:
		_villain_actor.custom_minimum_size = villain_size
		_villain_actor.size = villain_size
		_villain_actor.position = Vector2(
			phone_screen_root.size.x + villain_entry_padding,
			-villain_size.y - villain_entry_padding
		)
		_villain_actor.visible = true

	if _dialogue_panel != null:
		_update_dialogue_panel_layout()
		_dialogue_panel.visible = false

	if _dialogue_label != null:
		_dialogue_label.text = ""

	_set_app_icons_visible(true)
	apps_grid.visible = true

func _run_icon_steal_sequence(run_id: int) -> bool:
	var ordered_icons := _get_icons_in_zigzag_order()
	if ordered_icons.is_empty():
		return await _move_villain_to_corner(run_id)

	var columns := maxi(1, apps_grid.columns)
	for idx in range(ordered_icons.size()):
		var icon := ordered_icons[idx]
		if not is_instance_valid(icon):
			continue
		if not icon.visible:
			continue

		var target := _get_icon_center_in_phone(icon) - (villain_size * 0.5)
		var row_index := idx / columns
		target.y += villain_row_offset if row_index % 2 == 0 else -villain_row_offset

		var moved := await _tween_villain_to(target, villain_move_duration, run_id)
		if not moved:
			return false

		icon.visible = false

	_set_app_icons_visible(false)
	apps_grid.visible = false
	return await _move_villain_to_corner(run_id)

func _run_dialogue_sequence(run_id: int) -> bool:
	if not _is_cutscene_valid(run_id):
		return false

	if _dialogue_panel != null:
		_update_dialogue_panel_layout()
		_dialogue_panel.visible = true

	if _dialogue_label == null:
		return true

	var active_lines := _get_active_dialogue_lines()
	if active_lines.is_empty():
		return true

	for line in active_lines:
		if not _is_cutscene_valid(run_id):
			return false
		if String(line).strip_edges().is_empty():
			continue

		_dialogue_label.text = String(line)
		if not await _wait_for_dialogue_advance(run_id):
			return false

	return _is_cutscene_valid(run_id)

func _get_active_dialogue_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for line in villain_dialogue_lines_en:
		var clean_line := String(line).strip_edges()
		if not clean_line.is_empty():
			lines.append(clean_line)

	return lines

func _wait_for_dialogue_advance(run_id: int) -> bool:
	while _is_cutscene_valid(run_id):
		if _dialogue_advance_queued:
			_dialogue_advance_queued = false
			return true
		await get_tree().process_frame

	_dialogue_advance_queued = false
	return false

func _is_dialogue_advance_event(event: InputEvent) -> bool:
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		return true

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT

	return false

func _update_dialogue_panel_layout() -> void:
	if _dialogue_panel == null:
		return

	var size_limits := phone_screen_root.size - (dialogue_screen_margin * 2.0)
	var panel_size := dialogue_panel_size
	panel_size.x = clampf(panel_size.x, 120.0, maxf(120.0, size_limits.x))
	panel_size.y = clampf(panel_size.y, 56.0, maxf(56.0, size_limits.y))

	_dialogue_panel.anchor_left = 0.0
	_dialogue_panel.anchor_top = 0.0
	_dialogue_panel.anchor_right = 0.0
	_dialogue_panel.anchor_bottom = 0.0
	_dialogue_panel.custom_minimum_size = panel_size
	_dialogue_panel.size = panel_size

	var target_pos := Vector2.ZERO
	if dialogue_position_mode == DIALOGUE_POS_ABOVE_VILLAIN and _villain_actor != null and _villain_actor.visible:
		target_pos = Vector2(
			_villain_actor.position.x + ((_villain_actor.size.x - panel_size.x) * 0.5),
			_villain_actor.position.y - panel_size.y - dialogue_villain_gap
		)
	else:
		target_pos = (phone_screen_root.size - panel_size) * 0.5

	var max_x: float = maxf(dialogue_screen_margin.x, phone_screen_root.size.x - panel_size.x - dialogue_screen_margin.x)
	var max_y: float = maxf(dialogue_screen_margin.y, phone_screen_root.size.y - panel_size.y - dialogue_screen_margin.y)
	target_pos.x = clampf(target_pos.x, dialogue_screen_margin.x, max_x)
	target_pos.y = clampf(target_pos.y, dialogue_screen_margin.y, max_y)
	_dialogue_panel.position = target_pos

func _move_villain_to_corner(run_id: int) -> bool:
	var corner_target := Vector2(
		phone_screen_root.size.x - villain_size.x - villain_corner_margin.x,
		phone_screen_root.size.y - villain_size.y - villain_corner_margin.y
	)
	return await _tween_villain_to(corner_target, villain_move_duration, run_id)

func _tween_villain_to(target_position: Vector2, duration: float, run_id: int) -> bool:
	if not _is_cutscene_valid(run_id):
		return false

	if _active_cutscene_tween != null:
		_active_cutscene_tween.kill()

	_active_cutscene_tween = create_tween()
	_active_cutscene_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_cutscene_tween.tween_property(_villain_actor, "position", target_position, max(0.05, duration))
	await _active_cutscene_tween.finished
	_active_cutscene_tween = null

	return _is_cutscene_valid(run_id)

func _get_icons_in_zigzag_order() -> Array[Control]:
	var ordered: Array[Control] = []
	var icon_count := _app_icon_nodes.size()
	if icon_count == 0:
		return ordered

	var columns := maxi(1, apps_grid.columns)
	var row_count := int(ceil(float(icon_count) / float(columns)))
	for row in range(row_count):
		var row_start := row * columns
		var row_end := mini(row_start + columns, icon_count)
		if row % 2 == 0:
			for idx in range(row_start, row_end):
				ordered.append(_app_icon_nodes[idx])
		else:
			for idx in range(row_end - 1, row_start - 1, -1):
				ordered.append(_app_icon_nodes[idx])

	return ordered

func _get_icon_center_in_phone(icon: Control) -> Vector2:
	var icon_rect := icon.get_global_rect()
	var phone_rect := phone_screen_root.get_global_rect()
	return (icon_rect.position + (icon_rect.size * 0.5)) - phone_rect.position

func _set_app_icons_visible(visible_state: bool) -> void:
	for icon in _app_icon_nodes:
		if is_instance_valid(icon):
			icon.visible = visible_state

func _is_cutscene_valid(run_id: int) -> bool:
	return _is_cutscene_running and run_id == _cutscene_run_id and phone_screen_root.visible

func _cancel_phone_cutscene() -> void:
	_cutscene_run_id += 1
	_is_cutscene_running = false
	_dialogue_advance_queued = false

	if _active_cutscene_tween != null:
		_active_cutscene_tween.kill()
		_active_cutscene_tween = null

	if _cutscene_overlay != null:
		_cutscene_overlay.visible = false

	if _villain_actor != null:
		_villain_actor.visible = false

	if _dialogue_panel != null:
		_dialogue_panel.visible = false

	if _dialogue_label != null:
		_dialogue_label.text = ""

func _set_prompt_visible(visible_state: bool) -> void:
	press_e_button.visible = visible_state
	press_e_button.disabled = not visible_state

	if visible_state:
		press_e_button.grab_focus()
	elif press_e_button.has_focus():
		press_e_button.release_focus()

func _set_phone_screen_visible(visible_state: bool) -> void:
	phone_screen_root.visible = visible_state
	if not visible_state:
		_cancel_phone_cutscene()
