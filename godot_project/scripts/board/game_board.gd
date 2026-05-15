extends Control

const SpaceNodeScene = preload("res://scripts/board/space_node.gd")

# Actual board image: 5100 x 3300 (aspect 1.545:1)
const VASSAL_MAP_WIDTH := 5100.0
const VASSAL_MAP_HEIGHT := 3300.0

# Display preserves aspect — height-bound to 660, so width = 660 * 1.545 = 1020
const DISPLAY_WIDTH := 1020.0
const DISPLAY_HEIGHT := 660.0
const BOARD_OFFSET_X := 20.0
const BOARD_OFFSET_Y := 144.0

const ZOOM_MIN := 1.0
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.15

@onready var board_image: TextureRect = $BoardClip/BoardLayer/BoardImage
@onready var spaces_layer: Control = $BoardClip/BoardLayer/SpacesLayer
@onready var hover_label: Label = $UILayer/HoverLabel
@onready var board_layer: Control = $BoardClip/BoardLayer
@onready var board_clip: Control = $BoardClip
@onready var zoom_label: Label = $UILayer/ZoomBar/ZoomLabel
@onready var zoom_in_btn: Button = $UILayer/ZoomBar/ZoomInBtn
@onready var zoom_out_btn: Button = $UILayer/ZoomBar/ZoomOutBtn
@onready var reset_btn: Button = $UILayer/ZoomBar/ResetBtn

var space_nodes: Dictionary = {}
var coords: Dictionary = {}  # space_id -> Vector2 (Vassal pixel coords)

const NODE_SIZE := Vector2(28, 28)

# Pan/Zoom state
var zoom_level: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var is_panning: bool = false
var pan_start_pos: Vector2 = Vector2.ZERO
var pan_start_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_load_board()
	_load_coordinates()
	_create_space_nodes()
	GameManager.phase_changed.connect(_on_phase_changed)
	if has_node("/root/ActionController"):
		ActionController.action_state_changed.connect(_on_action_state_changed)
		ActionController.ap_changed.connect(_refresh_valid_targets)
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)
	board_clip.gui_input.connect(_on_board_clip_input)
	zoom_in_btn.pressed.connect(func(): _zoom_at(board_clip.size * 0.5, ZOOM_STEP))
	zoom_out_btn.pressed.connect(func(): _zoom_at(board_clip.size * 0.5, 1.0 / ZOOM_STEP))
	reset_btn.pressed.connect(reset_view)


func _on_gui_input(_event: InputEvent) -> void:
	pass


func _on_board_clip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, ZOOM_STEP)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
			accept_event()
		elif mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT]:
			# Left-click on EMPTY board area also pans (space nodes consume their own clicks first)
			if mb.pressed:
				is_panning = true
				pan_start_pos = mb.position
				pan_start_offset = pan_offset
				if mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
					accept_event()
			else:
				is_panning = false
				if mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
					accept_event()
	elif event is InputEventMouseMotion and is_panning:
		var mm := event as InputEventMouseMotion
		pan_offset = pan_start_offset + (mm.position - pan_start_pos)
		_clamp_pan()
		_apply_transform()
		accept_event()


func _zoom_at(local_pos: Vector2, factor: float) -> void:
	var new_zoom = clampf(zoom_level * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, zoom_level):
		return
	# Convert local cursor position to board-space coords (pre-zoom)
	var board_pos = (local_pos - pan_offset) / zoom_level
	zoom_level = new_zoom
	pan_offset = local_pos - board_pos * zoom_level
	_clamp_pan()
	_apply_transform()


func _clamp_pan() -> void:
	# Keep the scaled board within the clip area so it never disappears.
	var scaled_w := DISPLAY_WIDTH * zoom_level
	var scaled_h := DISPLAY_HEIGHT * zoom_level
	var clip_w := board_clip.size.x
	var clip_h := board_clip.size.y
	# At zoom=1 the board fits exactly: pan must be 0.
	# At higher zoom: pan can go from (clip_w - scaled_w) to 0 (board edges align with clip edges)
	var min_x := minf(0.0, clip_w - scaled_w)
	var max_x := maxf(0.0, clip_w - scaled_w)
	var min_y := minf(0.0, clip_h - scaled_h)
	var max_y := maxf(0.0, clip_h - scaled_h)
	# When zoom_level == 1, scaled_w <= clip_w → max_x is positive, allowing centering
	# Actually we want: don't let board's left edge go right of clip's left, etc.
	pan_offset.x = clampf(pan_offset.x, min_x, max_x)
	pan_offset.y = clampf(pan_offset.y, min_y, max_y)


func _apply_transform() -> void:
	board_layer.scale = Vector2(zoom_level, zoom_level)
	board_layer.position = pan_offset
	if zoom_label:
		zoom_label.text = "%d%%" % int(zoom_level * 100)


func reset_view() -> void:
	zoom_level = 1.0
	pan_offset = Vector2.ZERO
	_apply_transform()


func _load_board() -> void:
	var path := "res://assets/board/Imperial Struggle Map_Final-150-Clean.png"
	if ResourceLoader.exists(path):
		board_image.texture = load(path)
	board_image.size = Vector2(DISPLAY_WIDTH, DISPLAY_HEIGHT)
	board_image.position = Vector2.ZERO
	spaces_layer.position = Vector2.ZERO
	spaces_layer.size = board_image.size


func _load_coordinates() -> void:
	var path := "res://data/space_coords.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return
	for entry in json.data:
		coords[entry["id"]] = Vector2(entry["x"], entry["y"])


func _vassal_to_local(p: Vector2) -> Vector2:
	return Vector2(p.x / VASSAL_MAP_WIDTH * DISPLAY_WIDTH,
				   p.y / VASSAL_MAP_HEIGHT * DISPLAY_HEIGHT)


func _create_space_nodes() -> void:
	for space_id in GameData.spaces:
		var sd: SpaceData = GameData.spaces[space_id]
		var node := SpaceNodeScene.new()
		node.space_id = space_id
		node.size = NODE_SIZE
		var v_pos: Vector2 = coords.get(space_id, Vector2(50, 50))
		var local := _vassal_to_local(v_pos)
		node.position = local - NODE_SIZE * 0.5
		node.clicked.connect(_on_space_clicked)
		node.hovered.connect(_on_space_hovered)
		spaces_layer.add_child(node)
		space_nodes[space_id] = node


func bind_to_state() -> void:
	for space_id in space_nodes:
		var node: SpaceNode = space_nodes[space_id]
		if space_id in GameManager.state.spaces:
			node.bind(GameManager.state.spaces[space_id])


func _on_space_clicked(space_id: String) -> void:
	# Pending event effect choice takes priority
	if EventEffects.has_pending():
		var ok := EventEffects.resolve_choice(0, space_id)
		if ok:
			_refresh_all_spaces()
		else:
			print("[Board] Invalid target for event choice: ", space_id)
		return

	if ActionController.state in [
			ActionController.ActionState.SPENDING_MAJOR,
			ActionController.ActionState.SPENDING_MINOR]:
		var ok := ActionController.attempt_shift(space_id)
		if ok:
			(space_nodes[space_id] as SpaceNode).queue_redraw()
		else:
			print("[Board] Cannot shift: ", space_id)


func _refresh_all_spaces() -> void:
	for sid in space_nodes:
		(space_nodes[sid] as SpaceNode).queue_redraw()


func _on_space_hovered(space_id: String, is_hover: bool) -> void:
	if is_hover and space_id in GameData.spaces:
		var sd: SpaceData = GameData.spaces[space_id]
		var name_text := sd.display_name
		if LocaleManager.current_locale == "ko" and "name_ko" in sd:
			name_text = sd.display_name
		hover_label.text = "%s · %s · cost %d" % [name_text, _region_name(sd.region), sd.base_cost]
		hover_label.visible = true
	else:
		hover_label.visible = false


func _region_name(region: Enums.Region) -> String:
	match region:
		Enums.Region.EUROPE: return "Europe"
		Enums.Region.NORTH_AMERICA: return "N. America"
		Enums.Region.CARIBBEAN: return "Caribbean"
		Enums.Region.INDIA: return "India"
	return ""


func _on_phase_changed(_phase: Enums.TurnPhase) -> void:
	for space_id in space_nodes:
		(space_nodes[space_id] as SpaceNode).queue_redraw()


func _on_action_state_changed(_label: String) -> void:
	_refresh_valid_targets()


func highlight_spaces(space_ids: Array) -> void:
	# External hover-highlight (e.g., from log panel)
	for sid in space_nodes:
		var node: SpaceNode = space_nodes[sid]
		node.set_selected(sid in space_ids)


func _refresh_valid_targets() -> void:
	if GameManager.state == null:
		return
	var spending := ActionController.state in [
			ActionController.ActionState.SPENDING_MAJOR,
			ActionController.ActionState.SPENDING_MINOR]
	for sid in space_nodes:
		var node: SpaceNode = space_nodes[sid]
		if not spending:
			node.set_valid_target(false)
			continue
		if sid in GameManager.state.spaces:
			var ss: SpaceState = GameManager.state.spaces[sid]
			node.set_valid_target(ActionController.can_shift_space(ss))
		else:
			node.set_valid_target(false)
