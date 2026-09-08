extends Control

const GameSessionScene := preload("res://scenes/game_session.tscn")

@onready var main_menu: Control = $MainMenu
@onready var game_board: Control = $GameBoard

var current_session: Node = null
var resume_btn: Button
@onready var new_game_btn: Button = $MainMenu/CenterContainer/VBox/NewGameBtn
@onready var solo_br_btn: Button = $MainMenu/CenterContainer/VBox/SoloBRBtn
@onready var solo_fr_btn: Button = $MainMenu/CenterContainer/VBox/SoloFRBtn
@onready var load_btn: Button = $MainMenu/CenterContainer/VBox/LoadBtn
@onready var card_list_btn: Button = $MainMenu/CenterContainer/VBox/CardListBtn
@onready var settings_btn: Button = $MainMenu/CenterContainer/VBox/SettingsBtn

const CardBrowserScene := preload("res://scenes/ui/card_browser.tscn")
const CardModalScene := preload("res://scenes/ui/card_modal.tscn")
var _card_browser: Node = null
var _card_modal: Node = null
@onready var quit_btn: Button = $MainMenu/CenterContainer/VBox/QuitBtn
@onready var title_label: Label = $MainMenu/CenterContainer/VBox/Title
@onready var subtitle_label: Label = $MainMenu/CenterContainer/VBox/Subtitle


func _ready() -> void:
	theme = ThemeManager.theme
	new_game_btn.pressed.connect(_on_new_game.bind(Enums.Side.NONE))
	solo_br_btn.pressed.connect(_on_new_game.bind(Enums.Side.FRANCE))  # AI plays France, user plays Britain
	solo_fr_btn.pressed.connect(_on_new_game.bind(Enums.Side.BRITAIN))  # AI plays Britain
	load_btn.pressed.connect(_on_load)
	card_list_btn.pressed.connect(_on_card_list)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

	LocaleManager.locale_changed.connect(_on_locale_changed)
	preload("res://scripts/ui/heritage_menu.gd").decorate(main_menu)
	resume_btn=Button.new()
	resume_btn.text=LocaleManager.tx("진행 중인 게임으로 돌아가기")
	resume_btn.custom_minimum_size=Vector2(580,52)
	resume_btn.pressed.connect(func():
		_show_game_board()
		GameManager.resume_session())
	$MainMenu/CenterContainer/VBox.add_child(resume_btn)
	$MainMenu/CenterContainer/VBox.move_child(resume_btn,5)
	_refresh_texts()
	_apply_theme()
	_show_main_menu()
	LocaleManager.bind_literals(main_menu)


func _on_locale_changed(_new_locale: String) -> void:
	_refresh_texts()


func _refresh_texts() -> void:
	if resume_btn: resume_btn.text = LocaleManager.tx("진행 중인 게임으로 돌아가기")
	title_label.text = LocaleManager.t("game_title")
	subtitle_label.text = "IMPERIAL STRUGGLE"
	new_game_btn.text = LocaleManager.t("menu_hotseat")
	solo_br_btn.text = LocaleManager.t("menu_solo_br")
	solo_fr_btn.text = LocaleManager.t("menu_solo_fr")
	load_btn.text = LocaleManager.t("menu_load_game")
	load_btn.disabled = not "autosave" in SaveLoad.list_saves()
	card_list_btn.text = LocaleManager.t("menu_card_list")
	settings_btn.text = LocaleManager.t("menu_settings")
	quit_btn.text = LocaleManager.t("menu_quit")


func _apply_theme() -> void:
	title_label.add_theme_font_size_override("font_size", 76)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	subtitle_label.add_theme_font_size_override("font_size", 24)
	subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	# Buttons styled by ThemeManager autoload


func _show_main_menu() -> void:
	if resume_btn: resume_btn.visible=current_session!=null
	main_menu.visible = true
	game_board.visible = false
	_refresh_texts()


func _show_game_board() -> void:
	main_menu.visible = false
	game_board.visible = true


func _on_new_game(ai_side: int) -> void:
	if current_session:
		game_board.remove_child(current_session)
		# 새 판의 신호를 보내기 전에 구 판의 수신 연결까지 정리한다.
		current_session.free()
	current_session = GameSessionScene.instantiate()
	game_board.add_child(current_session)
	_show_game_board()

	if ai_side == Enums.Side.NONE:
		AIController.disable()
	else:
		AIController.enable_for(ai_side)

	if current_session.has_signal("menu_requested"):
		current_session.menu_requested.connect(_show_main_menu)
	GameManager.start_new_game()
	if current_session.has_method("bind_to_state"):
		current_session.bind_to_state()


func _on_load() -> void:
	if not SaveLoad.load_game():
		var dialog = AcceptDialog.new()
		dialog.dialog_text = SaveLoad.last_error
		add_child(dialog)
		dialog.popup_centered()
		return
	if current_session:
		game_board.remove_child(current_session)
		current_session.free()
	current_session = GameSessionScene.instantiate()
	game_board.add_child(current_session)
	if current_session.has_signal("menu_requested"):
		current_session.menu_requested.connect(_show_main_menu)
	_show_game_board()
	if current_session.has_method("bind_to_state"):
		current_session.bind_to_state()
	GameManager.resume_session()


func _on_card_list() -> void:
	if _card_modal == null:
		_card_modal = CardModalScene.instantiate()
		add_child(_card_modal)
	if _card_browser == null:
		_card_browser = CardBrowserScene.instantiate()
		add_child(_card_browser)
	_card_browser.show_for_main_menu()


func _on_settings() -> void:
	# Toggle Korean / English
	if LocaleManager.current_locale == "en":
		LocaleManager.set_locale("ko")
	else:
		LocaleManager.set_locale("en")


func _on_quit() -> void:
	get_tree().quit()
