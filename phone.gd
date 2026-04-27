extends Node2D

signal interacted(player)

@onready var interact_area: Area2D = $InteractArea
@onready var press_e_button: Button = $PromptCanvasLayer/PressEButton
@onready var phone_screen_root: Control = $PhoneScreenLayer/PhoneScreenRoot
@onready var apps_margin: Control = $PhoneScreenLayer/PhoneScreenRoot/AppsMargin
@onready var apps_grid: GridContainer = $PhoneScreenLayer/PhoneScreenRoot/AppsMargin/AppsGrid

const APP_ICONS_DIR := "res://AppIcons"
const MAX_APP_ICONS := 20
const APP_ICON_SIZE := Vector2(56.0, 56.0)
const DEFAULT_DIALOGUE_FONT_PATH := "res://Fonts/TTF/dogicapixel.ttf"
const DEFAULT_DIALOGUE_PANEL_SCENE_PATH := "res://UI/dialogue_panel.tscn"
const VILLAIN_SCENE_CANDIDATE_PATHS = [
	"res://Hacker/main_villain.tscn",
	"res://Hacker/hacker.tscn",
	"res://main_villain.tscn",
	"res://hacker.tscn"
]
const VILLAIN_ANIM_IDLE := &"idle"
const VILLAIN_ANIM_WALK := &"walk"

const DIALOGUE_POS_CENTER := 0
const DIALOGUE_POS_ABOVE_VILLAIN := 1
const VILLAIN_ROW_RIGHT_TO_LEFT := -1
const VILLAIN_ROW_LEFT_TO_RIGHT := 1
const CUTSCENE_Z_STOLEN_ICONS := 10
const CUTSCENE_Z_VILLAIN := 20
const CUTSCENE_Z_DIALOGUE := 30

@export var play_cutscene_every_open: bool = false
@export var villain_scene: PackedScene
@export var villain_size: Vector2 = Vector2(44.0, 44.0)
@export var villain_base_frame_size: Vector2 = Vector2(32.0, 32.0)
@export var villain_entry_padding: float = 14.0
@export var villain_corner_margin: Vector2 = Vector2(20.0, 22.0)
@export var villain_move_duration: float = 0.3
@export var villain_row_offset: float = 14.0
@export var stolen_icon_scale: float = 0.52
@export var stolen_icon_spacing: float = 22.0
@export var dialogue_line_duration: float = 1.25
@export var dialogue_auto_time_per_character: float = 0.035
@export var phone_auto_close_delay: float = 1.0
@export var dialogue_panel_scene: PackedScene
@export_enum("Center", "Above Villain") var dialogue_position_mode: int = DIALOGUE_POS_ABOVE_VILLAIN
@export var dialogue_panel_size: Vector2 = Vector2(50.0, 72.0)
@export var dialogue_screen_margin: Vector2 = Vector2(10.0, 10.0)
@export var dialogue_villain_gap: float = 10.0
@export var dialogue_offset: Vector2 = Vector2.ZERO
@export_range(8, 48, 1) var dialogue_font_size: int = 16
@export var dialogue_font: Font
@export var smooth_dialogue_text: bool = true
@export var villain_dialogue_bottom_margin: float = 20.0
@export var villain_dialogue_lines_en: PackedStringArray = PackedStringArray([
	"heya.",
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
var _villain_actor: Control = null
var _villain_scene_instance: Node = null
var _villain_sprite: AnimatedSprite2D = null
var _stolen_icon_train: Array[Control] = []
var _last_villain_row_direction: int = VILLAIN_ROW_RIGHT_TO_LEFT
var _dialogue_panel: Control = null
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
	_resolve_dialogue_font()
	_resolve_dialogue_panel_scene()
	_populate_app_icons()
	_setup_cutscene_nodes()

func _resolve_dialogue_font() -> void:
	if dialogue_font != null:
		return

	if ResourceLoader.exists(DEFAULT_DIALOGUE_FONT_PATH):
		dialogue_font = load(DEFAULT_DIALOGUE_FONT_PATH) as Font
	else:
		push_warning("Dialogue font missing at %s" % DEFAULT_DIALOGUE_FONT_PATH)

func _resolve_dialogue_panel_scene() -> void:
	if dialogue_panel_scene != null:
		return

	if ResourceLoader.exists(DEFAULT_DIALOGUE_PANEL_SCENE_PATH):
		dialogue_panel_scene = load(DEFAULT_DIALOGUE_PANEL_SCENE_PATH) as PackedScene

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
	phone_screen_root.clip_contents = true

	_cutscene_overlay = Control.new()
	_cutscene_overlay.name = "CutsceneOverlay"
	_cutscene_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cutscene_overlay.clip_contents = true
	_cutscene_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutscene_overlay.visible = false
	phone_screen_root.add_child(_cutscene_overlay)

	_villain_actor = Control.new()
	_villain_actor.name = "VillainActor"
	_villain_actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_villain_actor.custom_minimum_size = villain_size
	_villain_actor.size = villain_size
	_villain_actor.visible = false
	_villain_actor.z_index = CUTSCENE_Z_VILLAIN
	_cutscene_overlay.add_child(_villain_actor)
	_ensure_villain_scene_instance()

	var used_dialogue_scene := false
	_dialogue_panel = _instantiate_dialogue_panel_from_scene()
	if _dialogue_panel != null:
		used_dialogue_scene = true
	else:
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
	_dialogue_panel.z_index = CUTSCENE_Z_DIALOGUE
	if not used_dialogue_scene:
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
		dialogue_style.content_margin_left = 8
		dialogue_style.content_margin_top = 6
		dialogue_style.content_margin_right = 8
		dialogue_style.content_margin_bottom = 6
		_dialogue_panel.add_theme_stylebox_override("panel", dialogue_style)
	_cutscene_overlay.add_child(_dialogue_panel)

	_dialogue_label = _find_dialogue_label(_dialogue_panel)
	if _dialogue_label == null:
		if used_dialogue_scene:
			push_warning("Dialogue scene has no Label node. Adding a fallback label named DialogueLabel.")
		_dialogue_label = Label.new()
		_dialogue_label.name = "DialogueLabel"
		_dialogue_panel.add_child(_dialogue_label)
		used_dialogue_scene = false

	if not used_dialogue_scene:
		_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_dialogue_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if smooth_dialogue_text else CanvasItem.TEXTURE_FILTER_NEAREST
		if dialogue_font != null:
			_dialogue_label.add_theme_font_override("font", dialogue_font)
		_dialogue_label.add_theme_font_size_override("font_size", dialogue_font_size)
		_dialogue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_set_villain_animation(VILLAIN_ANIM_IDLE)

func _instantiate_dialogue_panel_from_scene() -> Control:
	if dialogue_panel_scene == null:
		return null

	var instance := dialogue_panel_scene.instantiate()
	if instance is Control:
		return instance as Control

	push_warning("Dialogue panel scene root must inherit Control. Falling back to generated dialogue panel.")
	if instance != null:
		instance.free()
	return null
#test
func _find_dialogue_label(root: Node) -> Label:
	if root == null:
		return null

	if root is Label:
		return root as Label

	for child in root.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var found := _find_dialogue_label(child_node)
		if found != null:
			return found

	return null

func _ensure_villain_scene_instance() -> void:
	if _villain_actor == null or _villain_scene_instance != null:
		return

	var resolved_scene := _resolve_villain_scene()
	if resolved_scene == null:
		push_warning("Could not find villain scene. Expected main_villain or hacker scene.")
		return

	_villain_scene_instance = resolved_scene.instantiate()
	if _villain_scene_instance == null:
		return

	_villain_actor.add_child(_villain_scene_instance)
	_villain_sprite = _find_animated_sprite(_villain_scene_instance)
	if _villain_sprite == null:
		push_warning("Villain scene has no AnimatedSprite2D, so no walk/idle animation can play.")
	else:
		_villain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_sync_villain_scene_transform()

func _resolve_villain_scene() -> PackedScene:
	if villain_scene != null:
		return villain_scene

	for scene_path in VILLAIN_SCENE_CANDIDATE_PATHS:
		if ResourceLoader.exists(scene_path):
			var scene_resource := load(scene_path) as PackedScene
			if scene_resource != null:
				return scene_resource

	return null

func _find_animated_sprite(root: Node) -> AnimatedSprite2D:
	if root is AnimatedSprite2D:
		return root as AnimatedSprite2D

	for child in root.get_children():
		var child_node := child as Node
		if child_node == null:
			continue
		var found := _find_animated_sprite(child_node)
		if found != null:
			return found

	return null

func _sync_villain_scene_transform() -> void:
	if _villain_actor == null or _villain_scene_instance == null:
		return

	if _villain_scene_instance is Node2D:
		var villain_node := _villain_scene_instance as Node2D
		villain_node.position = villain_size * 0.5
		var safe_base := Vector2(maxf(1.0, villain_base_frame_size.x), maxf(1.0, villain_base_frame_size.y))
		villain_node.scale = Vector2(villain_size.x / safe_base.x, villain_size.y / safe_base.y)

func _set_villain_animation(animation_name: StringName) -> void:
	if _villain_sprite == null or _villain_sprite.sprite_frames == null:
		return

	var active_animation := animation_name
	if not _villain_sprite.sprite_frames.has_animation(active_animation):
		active_animation = VILLAIN_ANIM_IDLE

	if not _villain_sprite.sprite_frames.has_animation(active_animation):
		return

	if _villain_sprite.animation != active_animation or not _villain_sprite.is_playing():
		_villain_sprite.play(active_animation)

func _set_villain_facing(horizontal_delta: float) -> void:
	if _villain_sprite == null:
		return

	if absf(horizontal_delta) < 0.01:
		return

	_villain_sprite.flip_h = horizontal_delta < 0.0

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

	var villain_positioned := await _move_villain_to_dialogue_spot(run_id)
	if not villain_positioned:
		return

	var dialogue_done := await _run_dialogue_sequence(run_id)
	if not dialogue_done:
		return

	await get_tree().create_timer(max(0.0, phone_auto_close_delay)).timeout
	if not _is_cutscene_valid(run_id):
		return

	_set_phone_screen_visible(false)

func _prepare_cutscene_open_state() -> void:
	_ensure_villain_scene_instance()
	_clear_stolen_icon_train()
	_last_villain_row_direction = VILLAIN_ROW_RIGHT_TO_LEFT

	if _cutscene_overlay != null:
		_cutscene_overlay.visible = true

	if _villain_actor != null:
		_villain_actor.custom_minimum_size = villain_size
		_villain_actor.size = villain_size
		_sync_villain_scene_transform()
		_villain_actor.position = Vector2(
			phone_screen_root.size.x + villain_entry_padding,
			-villain_size.y - villain_entry_padding
		)
		_villain_actor.visible = true
		_set_villain_animation(VILLAIN_ANIM_IDLE)

	if _dialogue_panel != null:
		_update_dialogue_panel_layout()
		_dialogue_panel.visible = false

	if _dialogue_label != null:
		_dialogue_label.text = ""

	_set_app_icons_visible(true)
	apps_grid.visible = true

func _run_icon_steal_sequence(run_id: int) -> bool:
	var rows := _get_icon_rows()
	if rows.is_empty():
		return true

	for row_index in range(rows.size()):
		if not _is_cutscene_valid(run_id):
			return false

		var row_icons: Array = rows[row_index]
		if row_icons.is_empty():
			continue

		var row_direction := VILLAIN_ROW_RIGHT_TO_LEFT if row_index % 2 == 0 else VILLAIN_ROW_LEFT_TO_RIGHT
		var row_y := _get_row_travel_y(row_icons)
		if row_index == 0:
			row_y = villain_corner_margin.y
		var spawn_pos := _get_row_edge_position(row_y, row_direction)

		_set_villain_and_train_visible(false)
		_villain_actor.position = spawn_pos
		_sync_train_to_villain_immediate(row_direction)
		_set_villain_and_train_visible(true)
		_set_villain_animation(VILLAIN_ANIM_IDLE)

		var ordered_row_icons := _get_row_icons_in_direction(row_icons, row_direction)
		for icon in ordered_row_icons:
			if not is_instance_valid(icon):
				continue
			if not icon.visible:
				continue

			var target := _get_icon_center_in_phone(icon) - (villain_size * 0.5)
			var moved := await _tween_villain_to(target, villain_move_duration, run_id)
			if not moved:
				return false

			_steal_icon_into_train(icon)
			_sync_train_to_villain_immediate(row_direction)

		var exit_pos := _get_row_edge_position(row_y, -row_direction)
		var exited := await _tween_villain_to(exit_pos, villain_move_duration, run_id)
		if not exited:
			return false

		_set_villain_and_train_visible(false)
		_last_villain_row_direction = row_direction

	_set_app_icons_visible(false)
	apps_grid.visible = false
	return _is_cutscene_valid(run_id)

func _get_icon_rows() -> Array:
	var rows: Array = []
	var icon_count := _app_icon_nodes.size()
	if icon_count == 0:
		return rows

	var columns := maxi(1, apps_grid.columns)
	var row_count := int(ceil(float(icon_count) / float(columns)))
	for row in range(row_count):
		var row_icons: Array = []
		var row_start := row * columns
		var row_end := mini(row_start + columns, icon_count)
		for idx in range(row_start, row_end):
			row_icons.append(_app_icon_nodes[idx])
		rows.append(row_icons)

	return rows

func _get_row_icons_in_direction(row_icons: Array, row_direction: int) -> Array:
	var ordered: Array = []
	if row_direction == VILLAIN_ROW_RIGHT_TO_LEFT:
		for idx in range(row_icons.size() - 1, -1, -1):
			ordered.append(row_icons[idx])
		return ordered

	for icon in row_icons:
		ordered.append(icon)
	return ordered

func _get_row_travel_y(row_icons: Array) -> float:
	if row_icons.is_empty():
		return villain_corner_margin.y

	var first_icon := row_icons[0] as Control
	if not is_instance_valid(first_icon):
		return villain_corner_margin.y

	var row_y := _get_icon_center_in_phone(first_icon).y - (villain_size.y * 0.5)
	var max_y := maxf(villain_corner_margin.y, phone_screen_root.size.y - villain_size.y - villain_corner_margin.y)
	return clampf(row_y, villain_corner_margin.y, max_y)

func _get_row_edge_position(row_y: float, row_direction: int) -> Vector2:
	var x := villain_corner_margin.x
	if row_direction == VILLAIN_ROW_RIGHT_TO_LEFT:
		x = phone_screen_root.size.x - villain_size.x - villain_corner_margin.x

	return Vector2(x, row_y)

func _set_villain_and_train_visible(visible_state: bool) -> void:
	if _villain_actor != null:
		_villain_actor.visible = visible_state

	for follower in _stolen_icon_train:
		if is_instance_valid(follower):
			follower.visible = visible_state

func _sync_train_to_villain_immediate(row_direction: int) -> void:
	if _villain_actor == null:
		return

	for idx in range(_stolen_icon_train.size()):
		var follower := _stolen_icon_train[idx]
		if not is_instance_valid(follower):
			continue

		var train_target := _get_train_target_for_index(idx, _villain_actor.position, row_direction, follower.size)
		follower.position = train_target

func _steal_icon_into_train(icon: Control) -> void:
	if _cutscene_overlay == null:
		return

	var icon_texture_rect := icon as TextureRect
	if icon_texture_rect == null or icon_texture_rect.texture == null:
		icon.visible = false
		return

	var follower := TextureRect.new()
	follower.texture = icon_texture_rect.texture
	follower.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	follower.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	follower.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	follower.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var follower_size := APP_ICON_SIZE * stolen_icon_scale
	follower.custom_minimum_size = follower_size
	follower.size = follower_size
	follower.position = _get_icon_center_in_phone(icon) - (follower_size * 0.5)
	follower.z_index = CUTSCENE_Z_STOLEN_ICONS
	_cutscene_overlay.add_child(follower)
	_stolen_icon_train.append(follower)

	icon.visible = false

func _get_train_target_for_index(train_index: int, villain_target: Vector2, row_direction: int, follower_size: Vector2) -> Vector2:
	var behind_sign := -row_direction
	var offset := Vector2(stolen_icon_spacing * float(train_index + 1) * float(behind_sign), 0.0)
	var target := villain_target + offset
	return _clamp_to_phone_bounds(target, follower_size)

func _clamp_to_phone_bounds(target: Vector2, control_size: Vector2) -> Vector2:
	var max_x := maxf(0.0, phone_screen_root.size.x - control_size.x)
	var max_y := maxf(0.0, phone_screen_root.size.y - control_size.y)
	return Vector2(clampf(target.x, 0.0, max_x), clampf(target.y, 0.0, max_y))

func _clear_stolen_icon_train() -> void:
	for follower in _stolen_icon_train:
		if is_instance_valid(follower):
			follower.queue_free()
	_stolen_icon_train.clear()

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

func _get_dialogue_bounds() -> Rect2:
	var fallback := Rect2(Vector2.ZERO, phone_screen_root.size)
	if apps_margin == null:
		return fallback

	var phone_rect := phone_screen_root.get_global_rect()
	var margin_rect := apps_margin.get_global_rect()
	var local_pos := margin_rect.position - phone_rect.position

	var clamped_pos := Vector2(
		clampf(local_pos.x, 0.0, phone_screen_root.size.x),
		clampf(local_pos.y, 0.0, phone_screen_root.size.y)
	)
	var max_size := phone_screen_root.size - clamped_pos
	var clamped_size := Vector2(
		clampf(margin_rect.size.x, 0.0, max_size.x),
		clampf(margin_rect.size.y, 0.0, max_size.y)
	)

	if clamped_size.x < 24.0 or clamped_size.y < 24.0:
		return fallback

	return Rect2(clamped_pos, clamped_size)

func _update_dialogue_panel_layout() -> void:
	if _dialogue_panel == null:
		return

	var dialogue_bounds := _get_dialogue_bounds()
	var size_limits := dialogue_bounds.size - (dialogue_screen_margin * 2.0)
	var panel_size := dialogue_panel_size
	panel_size.x = clampf(panel_size.x, 120.0, maxf(120.0, size_limits.x))
	panel_size.y = clampf(panel_size.y, 44.0, maxf(44.0, size_limits.y))

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
		target_pos = dialogue_bounds.position + ((dialogue_bounds.size - panel_size) * 0.5)

	target_pos += dialogue_offset

	var min_x := dialogue_bounds.position.x + dialogue_screen_margin.x
	var min_y := dialogue_bounds.position.y + dialogue_screen_margin.y
	var max_x: float = maxf(min_x, dialogue_bounds.position.x + dialogue_bounds.size.x - panel_size.x - dialogue_screen_margin.x)
	var max_y: float = maxf(min_y, dialogue_bounds.position.y + dialogue_bounds.size.y - panel_size.y - dialogue_screen_margin.y)
	target_pos.x = clampf(target_pos.x, min_x, max_x)
	target_pos.y = clampf(target_pos.y, min_y, max_y)
	_dialogue_panel.position = target_pos

func _move_villain_to_dialogue_spot(run_id: int) -> bool:
	if _villain_actor == null:
		return true

	_set_villain_and_train_visible(true)
	var target := Vector2(
		(phone_screen_root.size.x - villain_size.x) * 0.5,
		phone_screen_root.size.y - villain_size.y - maxf(0.0, villain_dialogue_bottom_margin)
	)
	var moved := await _tween_villain_to(target, maxf(0.15, villain_move_duration), run_id)
	if not moved:
		return false

	_sync_train_to_villain_immediate(_last_villain_row_direction)
	return _is_cutscene_valid(run_id)

func _tween_villain_to(target_position: Vector2, duration: float, run_id: int) -> bool:
	if not _is_cutscene_valid(run_id):
		return false

	target_position = _clamp_to_phone_bounds(target_position, villain_size)
	var row_direction := _last_villain_row_direction
	if _villain_actor != null:
		var move_delta := target_position - _villain_actor.position
		if absf(move_delta.x) > 0.01:
			row_direction = VILLAIN_ROW_LEFT_TO_RIGHT if move_delta.x > 0.0 else VILLAIN_ROW_RIGHT_TO_LEFT
			_last_villain_row_direction = row_direction

	if _villain_actor != null:
		var move_delta := target_position - _villain_actor.position
		if move_delta.length() > 0.01:
			_set_villain_facing(move_delta.x)
			_set_villain_animation(VILLAIN_ANIM_WALK)

	if _active_cutscene_tween != null:
		_active_cutscene_tween.kill()

	_active_cutscene_tween = create_tween()
	_active_cutscene_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_active_cutscene_tween.tween_property(_villain_actor, "position", target_position, max(0.05, duration))

	for idx in range(_stolen_icon_train.size()):
		var follower := _stolen_icon_train[idx]
		if not is_instance_valid(follower):
			continue
		var follower_target := _get_train_target_for_index(idx, target_position, row_direction, follower.size)
		_active_cutscene_tween.parallel().tween_property(follower, "position", follower_target, max(0.05, duration))

	await _active_cutscene_tween.finished
	_active_cutscene_tween = null
	_set_villain_animation(VILLAIN_ANIM_IDLE)

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
	_set_villain_animation(VILLAIN_ANIM_IDLE)
	_clear_stolen_icon_train()

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
