extends Control

# Custom-rendered investment tile per rulebook §3.3.
# Colors match official tile colors (Vassal): Econ=green, Dipl=purple, Mil=cyan.
# Symbols: ✚ Event, ⚑ Military Upgrade.
# Each tile clearly displays Major action+value, Minor action+value, and any symbols.

signal tile_clicked(tile: InvestmentTile)

var bound_tile: InvestmentTile = null
var _hover: bool = false

# Vassal-matched colors
const COLOR_ECON_BG := Color("cad5b5")
const COLOR_DIPL_BG := Color("cbbdcf")
const COLOR_MIL_BG := Color("aec9cd")
const COLOR_TEXT := Color("0a1317")
const COLOR_EVENT := Color("c8423a")       # red cross for event
const COLOR_UPGRADE := Color("1063e1")     # blue for upgrade


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	LocaleManager.locale_changed.connect(func(_l): bind(bound_tile))


func bind(tile: InvestmentTile) -> void:
	bound_tile = tile
	if tile == null:
		return
	var maj := LocaleManager.action(tile.major_action_type)
	var minor := LocaleManager.action(tile.minor_action_type)
	var symbols := []
	if tile.has_event_symbol: symbols.append(LocaleManager.t("inv_tile_symbol_event"))
	if tile.has_military_upgrade: symbols.append(LocaleManager.t("inv_tile_symbol_upgrade"))
	tooltip_text = LocaleManager.tf("inv_tile_tooltip", [
		maj, tile.major_action_points, minor,
		"\n" + ", ".join(symbols) if symbols.size() > 0 else ""])
	queue_redraw()


func _draw() -> void:
	if bound_tile == null: return
	var box = StyleBoxFlat.new()
	box.bg_color = _color_for(bound_tile.major_action_type)
	box.border_color = Color("dbbf83") if _hover else Color("516164")
	box.set_border_width_all(3 if _hover else 1)
	box.set_corner_radius_all(6)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var font = get_theme_font("font")
	var major = LocaleManager.action(bound_tile.major_action_type)
	var minor = LocaleManager.action(bound_tile.minor_action_type)
	draw_string(font, Vector2(12,25), LocaleManager.tx("주요 ")+major, HORIZONTAL_ALIGNMENT_LEFT,-1,18,COLOR_TEXT)
	draw_string(font, Vector2(size.x-40,56),str(bound_tile.major_action_points),HORIZONTAL_ALIGNMENT_LEFT,-1,38,COLOR_TEXT)
	draw_line(Vector2(10,64),Vector2(size.x-10,64),Color("718183"),1)
	if LocaleManager.current_locale == "en":
		draw_string(font,Vector2(12,86),LocaleManager.tx("보조 ")+minor,HORIZONTAL_ALIGNMENT_LEFT,-1,16,COLOR_TEXT)
		draw_string(font,Vector2(size.x-21,86),str(bound_tile.minor_action_points),HORIZONTAL_ALIGNMENT_LEFT,-1,17,COLOR_TEXT)
	else:
		draw_string(font,Vector2(12,86),LocaleManager.tx("보조 ")+minor+LocaleManager.tx(" %d점") % bound_tile.minor_action_points,HORIZONTAL_ALIGNMENT_LEFT,-1,17,COLOR_TEXT)
	var symbols = ""
	if bound_tile.has_event_symbol: symbols = LocaleManager.tx("이벤트") if LocaleManager.current_locale == "ko" else "Event"
	if bound_tile.has_military_upgrade: symbols += (" · " if not symbols.is_empty() else "")+LocaleManager.tx("전쟁 준비")
	draw_string(font,Vector2(12,108),symbols,HORIZONTAL_ALIGNMENT_LEFT,-1,13 if LocaleManager.current_locale=="en" else 14,Color("36454a"))


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
