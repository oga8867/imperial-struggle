extends Control

signal view_war_tiles_requested(side: Enums.Side)
const NavyView = preload("res://scripts/ui/navy_box_view.gd")
var navy_view: Control
var title_label: Label
var view_button: Button

func _ready() -> void:
	# 대기 수와 말을 위쪽에, 전쟁 타일 버튼을 아래에 두어 역할을 구분한다.
	title_label = Label.new()
	title_label.position = Vector2(12,8)
	title_label.size = Vector2(272,24)
	title_label.add_theme_font_size_override("font_size",18)
	title_label.add_theme_color_override("font_color",Color("ebc982"))
	add_child(title_label)
	navy_view = NavyView.new()
	navy_view.position = Vector2(12,36)
	navy_view.size = Vector2(272,146)
	add_child(navy_view)
	view_button = Button.new()
	view_button.position = Vector2(12,188)
	view_button.size = Vector2(272,32)
	view_button.pressed.connect(func(): view_war_tiles_requested.emit(GameManager.state.phasing_player))
	add_child(view_button)
	LocaleManager.locale_changed.connect(func(_l): refresh())
	refresh()

func refresh() -> void:
	title_label.text = LocaleManager.tx("해군 상자")
	view_button.text = LocaleManager.tx("내 전쟁 타일 확인")
	navy_view.refresh()
