extends Node

# Builds and applies the global Theme. Imperial Struggle dark UI with Meta-style pill buttons.

const COLOR_PRIMARY := Color("3b82f6")          # Brighter blue accent
const COLOR_PRIMARY_DEEP := Color("1d4ed8")
const COLOR_BG_DARK := Color("0f1119")
const COLOR_PANEL_DARK := Color("1c1f2e")
const COLOR_PANEL_RAISED := Color("262a3d")
const COLOR_TEXT := Color("e7eaec")
const COLOR_TEXT_MUTED := Color("9ca3af")
const COLOR_BR := Color("c8423a")
const COLOR_FR := Color("3a5fb0")
const COLOR_GOLD := Color("fbbf24")
const COLOR_BORDER := Color("44495e")

var theme: Theme


func _ready() -> void:
	theme = _build_theme()
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		(tree as SceneTree).root.theme = theme


func _build_theme() -> Theme:
	var t := Theme.new()
	_apply_button(t)
	_apply_panel(t)
	_apply_label(t)
	return t


func _apply_button(t: Theme) -> void:
	# Visible on dark backgrounds: light gray fill + bright border
	var sb_normal := _btn_box(COLOR_PANEL_RAISED, COLOR_BORDER, 1)
	var sb_hover := _btn_box(Color("363a52"), COLOR_GOLD, 2)
	var sb_pressed := _btn_box(Color("181a26"), COLOR_GOLD, 2)
	var sb_disabled := _btn_box(Color("1a1c2a"), Color("44495e"), 1)

	t.set_stylebox("normal", "Button", sb_normal)
	t.set_stylebox("hover", "Button", sb_hover)
	t.set_stylebox("pressed", "Button", sb_pressed)
	t.set_stylebox("disabled", "Button", sb_disabled)
	t.set_stylebox("focus", "Button", _focus_box())

	t.set_color("font_color", "Button", COLOR_TEXT)
	t.set_color("font_hover_color", "Button", COLOR_GOLD)
	t.set_color("font_pressed_color", "Button", COLOR_GOLD)
	t.set_color("font_disabled_color", "Button", Color(COLOR_TEXT_MUTED.r, COLOR_TEXT_MUTED.g, COLOR_TEXT_MUTED.b, 0.5))


func _btn_box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(100)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _focus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.border_color = COLOR_PRIMARY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(100)
	return sb


func _apply_panel(t: Theme) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL_DARK
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	t.set_stylebox("panel", "Panel", sb)


func _apply_label(t: Theme) -> void:
	t.set_color("font_color", "Label", COLOR_TEXT)
