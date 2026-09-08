extends Node

# Builds and applies the global Theme. Imperial Struggle dark UI with Meta-style pill buttons.

const COLOR_PRIMARY := Color("bca475")          # Brighter blue accent
const COLOR_PRIMARY_DEEP := Color("90774f")
const COLOR_BG_DARK := Color("101a20")
const COLOR_PANEL_DARK := Color("16252b")
const COLOR_PANEL_RAISED := Color("223339")
const COLOR_TEXT := Color("eee7d7")
const COLOR_TEXT_MUTED := Color("a8b4b1")
const COLOR_BR := Color("c8423a")
const COLOR_FR := Color("3a5fb0")
const COLOR_GOLD := Color("d5b778")
const COLOR_BORDER := Color("415354")

var theme: Theme


func _ready() -> void:
	theme = _build_theme()
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		(tree as SceneTree).root.theme = theme


func _build_theme() -> Theme:
	var t := Theme.new()
	# 한국어 지원 글꼴을 우선 요청한다. 실제 글리프 검사는 회귀 검증에서도 확인한다.
	var korean = SystemFont.new()
	korean.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Noto Sans KR", "Noto Sans CJK KR"])
	t.default_font = korean
	t.default_font_size = 16
	for character in "제국의투쟁영국프랑스외교군사경제":
		if not korean.has_char(character.unicode_at(0)):
			push_error("한국어 글리프가 없는 글꼴: " + character)
	_apply_button(t)
	_apply_panel(t)
	_apply_label(t)
	return t


func _apply_button(t: Theme) -> void:
	# Visible on dark backgrounds: light gray fill + bright border
	var sb_normal := _btn_box(COLOR_PANEL_RAISED, COLOR_BORDER, 1)
	var sb_hover := _btn_box(Color("304347"), COLOR_GOLD, 2)
	var sb_pressed := _btn_box(Color("192a30"), COLOR_GOLD, 2)
	var sb_disabled := _btn_box(Color("17252b"), Color("415354"), 1)

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
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _focus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.border_color = COLOR_PRIMARY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb


func _apply_panel(t: Theme) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL_DARK
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	t.set_stylebox("panel", "Panel", sb)
	t.set_stylebox("panel", "PanelContainer", sb)
	t.set_stylebox("panel", "PopupPanel", sb)


func _apply_label(t: Theme) -> void:
	t.set_color("font_color", "Label", COLOR_TEXT)
