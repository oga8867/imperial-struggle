extends Control

# Custom-rendered investment tile per rulebook §3.3.
# Colors match official tile colors (Vassal): Econ=green, Dipl=purple, Mil=cyan.
# Symbols: ✚ Event, ⚑ Military Upgrade.
# Each tile clearly displays Major action+value, Minor action+value, and any symbols.

signal tile_clicked(tile: InvestmentTile)

var bound_tile: InvestmentTile = null
var _hover: bool = false

# Vassal-matched colors
const COLOR_ECON_BG := Color("c8e0a4")     # light green
const COLOR_DIPL_BG := Color("d4b8e8")     # light purple
const COLOR_MIL_BG := Color("a4dde0")      # light cyan
const COLOR_TEXT := Color("0a1317")
const COLOR_EVENT := Color("c8423a")       # red cross for event
const COLOR_UPGRADE := Color("1063e1")     # blue for upgrade


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func bind(tile: InvestmentTile) -> void:
	bound_tile = tile
	if tile == null:
		return
	var maj := _action_full(tile.major_action_type)
	var minor := _action_full(tile.minor_action_type)
	var symbols := []
	if tile.has_event_symbol: symbols.append("Event")
	if tile.has_military_upgrade: symbols.append("Mil Upgrade")
	tooltip_text = "MAJOR: %s %d AP\nMINOR: %s 2 AP%s" % [
		maj, tile.major_action_points, minor,
		"\n" + ", ".join(symbols) if symbols.size() > 0 else ""]
	queue_redraw()


func _draw() -> void:
	if bound_tile == null:
		return
	var rect := Rect2(Vector2.ZERO, size)

	# Background — major action color
	var bg_color := _color_for(bound_tile.major_action_type)
	draw_rect(rect, bg_color, true)
	# Outer border
	draw_rect(rect.grow(-1), Color("3a3d4a"), false, 2)
	# Divider line halfway
	var divider_y := size.y * 0.55
	draw_line(Vector2(6, divider_y), Vector2(size.x - 6, divider_y), Color("3a3d4a", 0.5), 1.5)

	var font := ThemeDB.fallback_font

	# MAJOR ACTION (top half) — large value + action label
	var major_letter := _action_letter(bound_tile.major_action_type)
	var major_value := str(bound_tile.major_action_points)
	# Action symbol (large)
	draw_string(font, Vector2(8, 28), major_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COLOR_TEXT)
	# Value (very large) on right
	draw_string(font, Vector2(size.x - 32, 36), major_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 32,
		Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 1), TextServer.JUSTIFICATION_NONE)

	# MINOR ACTION (bottom half) — smaller
	var minor_letter := _action_letter(bound_tile.minor_action_type)
	# Lighter bg for minor section
	draw_rect(Rect2(Vector2(2, divider_y + 2), Vector2(size.x - 4, size.y - divider_y - 4)),
		Color(bg_color.r * 0.85, bg_color.g * 0.85, bg_color.b * 0.85), true)
	draw_string(font, Vector2(8, divider_y + 22), minor_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_TEXT)
	draw_string(font, Vector2(size.x - 18, divider_y + 25), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT)

	# SYMBOLS (bottom-right region, on minor section)
	var sym_x := 28
	var sym_y := divider_y + 25
	if bound_tile.has_event_symbol:
		# ✚ red cross
		draw_string(font, Vector2(sym_x, sym_y), "✚", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_EVENT)
		sym_x += 18
	if bound_tile.has_military_upgrade:
		# ⚑ flag for upgrade (symbolic for "swap a war tile")
		draw_string(font, Vector2(sym_x, sym_y), "⚑", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_UPGRADE)

	# Hover/selection ring
	if _hover:
		draw_rect(rect, Color("fbbf24"), false, 3)


func _color_for(t: Enums.ActionType) -> Color:
	match t:
		Enums.ActionType.ECONOMIC: return COLOR_ECON_BG
		Enums.ActionType.DIPLOMATIC: return COLOR_DIPL_BG
		Enums.ActionType.MILITARY: return COLOR_MIL_BG
	return Color.WHITE


func _action_letter(t: Enums.ActionType) -> String:
	# Per Vassal labeling — single letter (rule §3.3 uses coins/grenade/quill icons,
	# but Vassal stylizes as letters; we follow that convention.)
	match t:
		Enums.ActionType.ECONOMIC: return "E"
		Enums.ActionType.DIPLOMATIC: return "D"
		Enums.ActionType.MILITARY: return "M"
	return "?"


func _action_full(t: Enums.ActionType) -> String:
	match t:
		Enums.ActionType.ECONOMIC: return "Economic"
		Enums.ActionType.DIPLOMATIC: return "Diplomatic"
		Enums.ActionType.MILITARY: return "Military"
	return ""


func _on_mouse_entered() -> void:
	_hover = true
	z_index = 5
	queue_redraw()


func _on_mouse_exited() -> void:
	_hover = false
	z_index = 0
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tile_clicked.emit(bound_tile)
