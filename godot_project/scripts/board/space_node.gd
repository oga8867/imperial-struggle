class_name SpaceNode
extends Control

signal clicked(space_id: String)
signal hovered(space_id: String, is_hover: bool)

@export var space_id: String = ""

var space_state: SpaceState = null

const COLOR_BRITAIN := Color("c8423a")
const COLOR_FRANCE := Color("3a5fb0")
const COLOR_HOVER := Color("ffffff", 0.5)
const COLOR_VALID := Color("22c55e")
const COLOR_SELECTED := Color("fbbf24")

const SHAPE_DIAMOND := 0
const SHAPE_CIRCLE := 1
const SHAPE_SQUARE := 2
const SHAPE_HEX := 3

# Texture cache (loaded once per session)
static var _tex_control_br: Texture2D
static var _tex_control_fr: Texture2D
static var _tex_squadron_br: Texture2D
static var _tex_squadron_fr: Texture2D
static var _tex_conflict: Texture2D
static var _tex_fort_damaged: Texture2D
static var _tex_usa: Texture2D
static var _textures_loaded: bool = false

var _is_hover: bool = false
var _is_selected: bool = false
var _is_valid_target: bool = false


static func _load_textures() -> void:
	if _textures_loaded:
		return
	_tex_control_br = _try_load("res://assets/tokens/Markers_Control_BR.png")
	_tex_control_fr = _try_load("res://assets/tokens/Markers_Control_FR.png")
	_tex_squadron_br = _try_load("res://assets/tokens/Squadron_BR.png")
	_tex_squadron_fr = _try_load("res://assets/tokens/Squadron_FR.png")
	_tex_conflict = _try_load("res://assets/tokens/Markers_Conflict.png")
	_tex_fort_damaged = _try_load("res://assets/tokens/Markers_Fort Damaged.png")
	_tex_usa = _try_load("res://assets/tokens/Markers_USA Control.png")
	_textures_loaded = true


static func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _ready() -> void:
	_load_textures()
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


func bind(state: SpaceState) -> void:
	space_state = state
	queue_redraw()


func _on_mouse_entered() -> void:
	_is_hover = true
	hovered.emit(space_id, true)
	queue_redraw()


func _on_mouse_exited() -> void:
	_is_hover = false
	hovered.emit(space_id, false)
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(space_id)
			accept_event()


func set_selected(selected: bool) -> void:
	_is_selected = selected
	queue_redraw()


func set_valid_target(valid: bool) -> void:
	if _is_valid_target != valid:
		_is_valid_target = valid
		queue_redraw()


func _draw() -> void:
	if space_state == null:
		_draw_hover_ring()
		return

	var center := size * 0.5
	var radius := mini(size.x, size.y) * 0.45

	# 1. Valid target glow (largest)
	if _is_valid_target:
		draw_circle(center, radius + 6, Color("22c55e", 0.35))
		draw_arc(center, radius + 4, 0, TAU, 24, COLOR_VALID, 2)

	# 2. Token image (control flag or squadron) — replaces shape fill
	if not space_state.is_empty():
		var token := _get_token_texture()
		if token != null:
			var img_size := Vector2(size.x * 1.0, size.y * 1.0)
			var img_pos := center - img_size * 0.5
			draw_texture_rect(token, Rect2(img_pos, img_size), false)
		else:
			# Texture load failed — fall back to colored shape so flag is still visible
			var fill := COLOR_BRITAIN if space_state.controlled_by == Enums.Side.BRITAIN else COLOR_FRANCE
			_draw_filled_shape(center, radius * 0.85, fill)
	else:
		# Empty: draw faint shape outline so the player sees there's a space
		_draw_shape_outline(center, radius * 0.7)

	# 3. Damaged fort marker overlay
	if space_state.is_fort_damaged and _tex_fort_damaged != null:
		var d_size := Vector2(size.x * 0.6, size.y * 0.6)
		draw_texture_rect(_tex_fort_damaged, Rect2(center - d_size * 0.5, d_size), false)

	# 4. Conflict marker overlay
	if space_state.has_conflict_marker:
		if _tex_conflict != null:
			var c_size := Vector2(size.x * 0.6, size.y * 0.6)
			var c_pos := center - c_size * 0.5 + Vector2(size.x * 0.25, -size.y * 0.25)
			draw_texture_rect(_tex_conflict, Rect2(c_pos, c_size), false)
		else:
			draw_circle(center + Vector2(size.x * 0.25, -size.y * 0.25), size.x * 0.18, Color("ef4444"))

	# 5. USA flag overlay
	if space_state.has_usa_flag and _tex_usa != null:
		var u_size := Vector2(size.x * 0.7, size.y * 0.7)
		draw_texture_rect(_tex_usa, Rect2(center - u_size * 0.5, u_size), false)

	# 6. Hover and selection rings
	if _is_hover:
		draw_arc(center, radius + 2, 0, TAU, 24, COLOR_HOVER, 2)
	if _is_selected:
		draw_arc(center, radius + 4, 0, TAU, 24, COLOR_SELECTED, 3)


func _get_token_texture() -> Texture2D:
	if space_state.controlled_by == Enums.Side.NONE:
		return null
	# Squadron for naval, otherwise control flag
	if space_state.data.space_type == Enums.SpaceType.NAVAL:
		if space_state.controlled_by == Enums.Side.BRITAIN: return _tex_squadron_br
		else: return _tex_squadron_fr
	else:
		if space_state.controlled_by == Enums.Side.BRITAIN: return _tex_control_br
		else: return _tex_control_fr


func _draw_hover_ring() -> void:
	if _is_hover:
		var center := size * 0.5
		draw_arc(center, mini(size.x, size.y) * 0.4, 0, TAU, 24, COLOR_HOVER, 2)


func _draw_shape_outline(center: Vector2, radius: float) -> void:
	var color := Color(1, 1, 1, 0.35)
	_draw_shape(center, radius, color, false, 1.5)


func _draw_filled_shape(center: Vector2, radius: float, color: Color) -> void:
	_draw_shape(center, radius, color, true, 0)


func _draw_shape(center: Vector2, radius: float, color: Color, filled: bool, width: float) -> void:
	var shape := _get_shape()
	var points := PackedVector2Array()
	match shape:
		SHAPE_CIRCLE:
			if filled:
				draw_circle(center, radius, color)
			else:
				draw_arc(center, radius, 0, TAU, 24, color, width)
			return
		SHAPE_DIAMOND:
			points = PackedVector2Array([
				center + Vector2(0, -radius), center + Vector2(radius, 0),
				center + Vector2(0, radius), center + Vector2(-radius, 0),
			])
		SHAPE_SQUARE:
			var hr := radius * 0.85
			points = PackedVector2Array([
				center + Vector2(-hr, -hr), center + Vector2(hr, -hr),
				center + Vector2(hr, hr), center + Vector2(-hr, hr),
			])
		SHAPE_HEX:
			for i in range(6):
				var ang := PI / 6 + i * PI / 3
				points.append(center + Vector2(cos(ang), sin(ang)) * radius)
	if points.size() > 0:
		if filled:
			var colors := PackedColorArray()
			for _i in range(points.size()):
				colors.append(color)
			draw_polygon(points, colors)
		else:
			var closed := points.duplicate()
			closed.append(points[0])
			draw_polyline(closed, color, width)


func _get_shape() -> int:
	if space_state == null or space_state.data == null:
		return SHAPE_CIRCLE
	match space_state.data.space_type:
		Enums.SpaceType.POLITICAL: return SHAPE_DIAMOND
		Enums.SpaceType.MARKET: return SHAPE_CIRCLE
		Enums.SpaceType.TERRITORY: return SHAPE_SQUARE
		Enums.SpaceType.NAVAL: return SHAPE_HEX
		Enums.SpaceType.FORT: return SHAPE_HEX
	return SHAPE_CIRCLE
