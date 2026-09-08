extends Control

# Card Browser — used both as in-game discard/played pile viewer and main-menu card list.

signal closed

const CardViewScene := preload("res://scenes/ui/card_view.tscn")

@onready var title_label: Label = $Panel/VBox/Title
@onready var grid: GridContainer = $Panel/VBox/Scroll/Grid
@onready var close_btn: Button = $Panel/VBox/CloseBtn
@onready var tab_all_events: Button = $Panel/VBox/Tabs/AllEvents
@onready var tab_all_min: Button = $Panel/VBox/Tabs/AllMinistries
@onready var tab_played: Button = $Panel/VBox/Tabs/Played
@onready var tab_discard: Button = $Panel/VBox/Tabs/Discard
@onready var card_modal_node: Control = null

var current_mode: String = "all_events"


func _ready() -> void:
	visible = false
	close_btn.pressed.connect(_on_close)
	tab_all_events.pressed.connect(func(): set_mode("all_events"))
	tab_all_min.pressed.connect(func(): set_mode("all_ministries"))
	tab_played.pressed.connect(func(): set_mode("played"))
	tab_discard.pressed.connect(func(): set_mode("discard"))
	LocaleManager.locale_changed.connect(func(_l): _refresh_static_texts())
	_refresh_static_texts()


func _refresh_static_texts() -> void:
	close_btn.text = LocaleManager.t("btn_close")
	tab_all_events.text = LocaleManager.t("cards_all_events")
	tab_all_min.text = LocaleManager.t("cards_all_ministries")
	tab_played.text = LocaleManager.t("cards_played")
	tab_discard.text = LocaleManager.t("cards_discard")
	if visible:
		_refresh()


func show_for_main_menu() -> void:
	visible = true
	# Hide in-game-only tabs
	tab_played.visible = false
	tab_discard.visible = false
	set_mode("all_events")


func show_in_game() -> void:
	visible = true
	tab_played.visible = true
	tab_discard.visible = true
	set_mode("played")


func set_mode(mode: String) -> void:
	current_mode = mode
	_refresh()


func _refresh() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var cards: Array = []
	match current_mode:
		"all_events":
			title_label.text = LocaleManager.tf("cards_title_events", [GameData.events.size()])
			cards = GameData.events
		"all_ministries":
			title_label.text = LocaleManager.tf("cards_title_ministries", [GameData.ministries.size()])
			cards = GameData.ministries
		"played":
			var pile = GameManager.state.event_played_pile if GameManager.state else []
			title_label.text = LocaleManager.tf("cards_title_played", [pile.size()])
			cards = pile
		"discard":
			var pile = GameManager.state.event_discard_pile if GameManager.state else []
			title_label.text = LocaleManager.tf("cards_title_discard", [pile.size()])
			cards = pile

	tab_all_events.disabled = current_mode == "all_events"
	tab_all_min.disabled = current_mode == "all_ministries"
	tab_played.disabled = current_mode == "played"
	tab_discard.disabled = current_mode == "discard"

	for card in cards:
		var view := CardViewScene.instantiate()
		grid.add_child(view)
		view.custom_minimum_size = Vector2(140, 196)
		if card is EventCard:
			view.bind_event(card)
		elif card is MinistryCard:
			view.bind_ministry(card)
		view.clicked.connect(_on_card_clicked)


func _on_card_clicked(card) -> void:
	# Try to find card_modal in tree
	if card_modal_node == null:
		var root = get_tree().get_root()
		card_modal_node = root.find_child("CardModal", true, false)
	if card_modal_node and card_modal_node.has_method("show_card"):
		card_modal_node.show_card(card)


func _on_close() -> void:
	visible = false
	closed.emit()
