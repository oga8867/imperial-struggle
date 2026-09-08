extends Control

const SpaceNodeScene = preload("res://scripts/board/space_node.gd")

# Actual board image: 5100 x 3300 (aspect 1.545:1)
const VASSAL_MAP_WIDTH := 5100.0
const VASSAL_MAP_HEIGHT := 3300.0

# 자원 대시보드 아래에 원작 비율 그대로 표시한다. 확대·클릭 좌표도 이 크기를 쓴다.
const Layout = preload("res://scripts/ui/session_layout.gd")
const DISPLAY_WIDTH = Layout.BOARD_RECT.size.x
const DISPLAY_HEIGHT = Layout.BOARD_RECT.size.y
const BOARD_OFFSET_X = Layout.BOARD_RECT.position.x
const BOARD_OFFSET_Y = Layout.BOARD_RECT.position.y

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
var navy_box_view: Control
var coords: Dictionary = {}  # space_id -> Vector2 (Vassal pixel coords)

const NODE_SIZE := Vector2(28, 28)

# Pan/Zoom state
var zoom_level: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var is_panning: bool = false
var pan_start_pos: Vector2 = Vector2.ZERO
var pan_start_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	Layout.place(board_clip,Layout.BOARD_RECT)
	Layout.place(hover_label,Rect2(36,292,820,28))
	Layout.place($UILayer/ZoomBar,Rect2(36,816,900,40))
	board_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	_load_board()
	_load_coordinates()
	_create_space_nodes()
	_create_navy_box()
	GameManager.phase_changed.connect(_on_phase_changed)
	if has_node("/root/ActionController"):
		ActionController.action_state_changed.connect(_on_action_state_changed)
		ActionController.ap_changed.connect(_refresh_valid_targets)
	if has_node("/root/EventEffects"):
		EventEffects.pending_choices_changed.connect(func(_c): _refresh_valid_targets())
		EventEffects.effects_resolved.connect(func(): _refresh_valid_targets())
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)
	board_clip.gui_input.connect(_on_board_clip_input)
	zoom_in_btn.pressed.connect(func(): _zoom_at(board_clip.size * 0.5, ZOOM_STEP))
	zoom_out_btn.pressed.connect(func(): _zoom_at(board_clip.size * 0.5, 1.0 / ZOOM_STEP))
	reset_btn.pressed.connect(reset_view)
	reset_btn.text = LocaleManager.tx("전체 지도")
	for region in [Enums.Region.EUROPE, Enums.Region.NORTH_AMERICA, Enums.Region.CARIBBEAN, Enums.Region.INDIA]:
		var button = Button.new()
		button.text = LocaleManager.region(region)
		button.pressed.connect(focus_region.bind(region))
		$UILayer/ZoomBar.add_child(button)


func _on_gui_input(_event: InputEvent) -> void:
	pass

func _create_navy_box() -> void:
	# 원작 해군 상자의 안쪽 좌표. 지도와 같은 부모 아래 두어 확대·이동을
	# 공유한다. 클릭을 무시하여 지도 공간 선택과 드래그를 방해하지 않는다.
	var panel = Panel.new()
	panel.name = "NavyBoxMarkers"
	panel.position = _vassal_to_local(Vector2(1775,1748))
	panel.size = Vector2(100,39)
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07,0.12,0.15,0.92)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel",style)
	board_layer.add_child(panel)
	navy_box_view = preload("res://scripts/ui/navy_box_view.gd").new()
	navy_box_view.compact = true
	navy_box_view.position = Vector2(2,1)
	navy_box_view.size = Vector2(96,36)
	panel.add_child(navy_box_view)


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
	if AIController.is_ai_turn(): return
	# Pending event effect choice takes priority
	if EventEffects.has_pending():
		var ok := EventEffects.resolve_choice(0, space_id)
		if ok:
			_refresh_all_spaces()
		else:
			GameManager.status_message.emit(ActionController.explain_space(space_id).replace("\n"," · "))
		return

	if ActionController.state in [
			ActionController.ActionState.SPENDING_MAJOR,
			ActionController.ActionState.SPENDING_MINOR,ActionController.ActionState.SPENDING_EVENT]:
		var ss: SpaceState = GameManager.state.spaces[space_id]
		if ss.data.space_type==Enums.SpaceType.NAVAL and ActionController.current_action_type()==Enums.ActionType.MILITARY:
			_show_squadron_sources(space_id)
			return
		var remove_conflict = ss.has_conflict_marker and ss.data.space_type in [Enums.SpaceType.MARKET,Enums.SpaceType.POLITICAL] and ActionController.current_action_type()==Enums.ActionType.MILITARY
		if remove_conflict and ActionController.can_shift_space(ss):
			_show_jacobite_choice(space_id)
			return
		var ok = ActionController.remove_conflict_marker(space_id) if remove_conflict else ActionController.attempt_shift(space_id)
		if ok:
			(space_nodes[space_id] as SpaceNode).queue_redraw()
		else:
			GameManager.status_message.emit(ActionController.explain_space(space_id).replace("\n"," · "))


func _show_jacobite_choice(id: String) -> void:
	var popup=PopupPanel.new()
	var box=VBoxContainer.new()
	box.custom_minimum_size=Vector2(580,160)
	popup.add_child(box)
	var ss=GameManager.state.spaces[id]
	var shift=Button.new()
	shift.text=LocaleManager.tx("재커바이트: 깃발 이동 · 군사 %d점") % ActionController.calculate_shift_cost(ss,ss.data.region)
	shift.custom_minimum_size.y=52
	shift.pressed.connect(func():
		ActionController.attempt_shift(id)
		popup.hide()
		_refresh_all_spaces())
	box.add_child(shift)
	var remove=Button.new()
	remove.text=LocaleManager.tx("분쟁 마커만 제거 · 군사 %d점") % (2+int(ss.conflict_marker_extra_cost))
	remove.custom_minimum_size.y=52
	remove.pressed.connect(func():
		ActionController.remove_conflict_marker(id)
		popup.hide()
		_refresh_all_spaces())
	box.add_child(remove)
	var cancel=Button.new()
	cancel.text=LocaleManager.tx("닫기")
	cancel.pressed.connect(popup.hide)
	box.add_child(cancel)
	add_child(popup)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup_centered()

func _refresh_all_spaces() -> void:
	bind_to_state()
	for sid in space_nodes:
		(space_nodes[sid] as SpaceNode).queue_redraw()


func _on_space_hovered(space_id: String, is_hover: bool) -> void:
	if is_hover and space_id in GameData.spaces:
		var sd: SpaceData = GameData.spaces[space_id]
		var name_text := sd.display_name
		if LocaleManager.current_locale == "ko" and sd.name_ko != "":
			name_text = sd.name_ko
		hover_label.text = ActionController.explain_space(space_id)
		space_nodes[space_id].tooltip_text = hover_label.text
		hover_label.visible = true
	else:
		hover_label.visible = false


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
	bind_to_state()
	if GameManager.state == null:
		return
	# During an Event effect, highlight the spaces that satisfy the current choice.
	var event_pending := has_node("/root/EventEffects") and EventEffects.has_pending()
	var spending := ActionController.state in [
			ActionController.ActionState.SPENDING_MAJOR,
			ActionController.ActionState.SPENDING_MINOR,ActionController.ActionState.SPENDING_EVENT]
	for sid in space_nodes:
		var node: SpaceNode = space_nodes[sid]
		if event_pending:
			node.set_valid_target(EventEffects.is_valid_target(sid))
			continue
		if not spending:
			node.set_valid_target(false)
			continue
		if sid in GameManager.state.spaces:
			var ss: SpaceState = GameManager.state.spaces[sid]
			node.set_valid_target(ActionController.can_shift_space(ss))
		else:
			node.set_valid_target(false)


func focus_region(region: int) -> void:
	# 원작 지도의 네 구역 중심. 위치 변환은 클릭 마커와 동일한 좌표계를 사용한다.
	var centers = {Enums.Region.NORTH_AMERICA: Vector2(1220,850), Enums.Region.EUROPE: Vector2(4020,850), Enums.Region.CARIBBEAN: Vector2(1220,2460), Enums.Region.INDIA: Vector2(4020,2460)}
	zoom_level = 1.9
	pan_offset = board_clip.size * 0.5 - _vassal_to_local(centers[region]) * zoom_level
	_clamp_pan()
	_apply_transform()

func _show_squadron_sources(target_id: String) -> void:
	var popup=PopupPanel.new()
	var box=VBoxContainer.new()
	box.custom_minimum_size=Vector2(560,120)
	box.add_theme_constant_override("separation",10)
	popup.add_child(box)
	var label=Label.new()
	label.text=LocaleManager.local_name(GameManager.state.spaces[target_id].data.display_name,GameManager.state.spaces[target_id].data.name_ko)+LocaleManager.tx(" · 이동할 함대의 출발지")
	label.add_theme_font_size_override("font_size",22)
	box.add_child(label)
	var sources=["navy"]
	for ss in GameManager.state.spaces.values():
		if ss.data.space_type==Enums.SpaceType.NAVAL and ss.controlled_by==ActionController.current_side: sources.append(ss.data.id)
	for source in sources:
		var plan=ActionController.squadron_deployment_plan(target_id,source)
		if plan.is_empty(): continue
		var button=Button.new()
		button.text=(LocaleManager.tx("해군 상자") if source=="navy" else LocaleManager.local_name(GameManager.state.spaces[source].data.display_name,GameManager.state.spaces[source].data.name_ko))+LocaleManager.tx(" · 군사 %d점") % plan.cost
		button.custom_minimum_size.y=48
		button.disabled=not ActionController.can_spend_ap(plan.cost,GameManager.state.spaces[target_id],"naval")
		button.pressed.connect(func():
			ActionController.deploy_squadron_to(target_id,source)
			popup.hide()
			_refresh_all_spaces())
		box.add_child(button)
	var cancel=Button.new()
	cancel.text=LocaleManager.tx("닫기")
	cancel.pressed.connect(popup.hide)
	box.add_child(cancel)
	add_child(popup)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup_centered()
