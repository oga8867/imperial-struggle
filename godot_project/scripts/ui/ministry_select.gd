extends Control

signal ministry_selected(side: Enums.Side, cards: Array)

const CardViewScene := preload("res://scenes/ui/card_view.tscn")

@onready var title_label: Label = $Panel/VBox/Title
@onready var grid: GridContainer = $Panel/VBox/Scroll/Grid
@onready var confirm_btn: Button = $Panel/VBox/HBox/ConfirmBtn
@onready var counter_label: Label = $Panel/VBox/HBox/CounterLabel

var current_side: Enums.Side = Enums.Side.NONE
var available_cards: Array[MinistryCard] = []
var selected_cards: Array[MinistryCard] = []
var card_views: Dictionary = {}  # card -> CardView


func _ready() -> void:
	visible = false
	confirm_btn.pressed.connect(_on_confirm)


func show_for_side(side: Enums.Side) -> void:
	current_side = side
	selected_cards.clear()
	if GameManager.state == null:
		return

	available_cards = GameData.get_ministries_for_era(side, GameManager.state.current_era)

	title_label.text = "%s — Select 2 Ministry Cards" % _side_name(side)
	_refresh_grid()
	_refresh_counter()
	visible = true


func _refresh_grid() -> void:
	for child in grid.get_children():
		child.queue_free()
	card_views.clear()
	for card in available_cards:
		var view := CardViewScene.instantiate()
		grid.add_child(view)
		view.custom_minimum_size = Vector2(160, 224)
		view.bind_ministry(card)
		view.clicked.connect(_on_card_clicked)
		card_views[card] = view


func _on_card_clicked(card) -> void:
	if not (card is MinistryCard):
		return
	if card in selected_cards:
		selected_cards.erase(card)
	elif selected_cards.size() < 2:
		selected_cards.append(card)
	_refresh_selection_visuals()
	_refresh_counter()


func _refresh_selection_visuals() -> void:
	for card in card_views:
		var view = card_views[card]
		if view.has_method("set_selected"):
			view.set_selected(card in selected_cards)


func _refresh_counter() -> void:
	counter_label.text = "Selected: %d/2" % selected_cards.size()
	confirm_btn.disabled = selected_cards.size() != 2


func _on_confirm() -> void:
	var player := GameManager.state.get_player(current_side)
	player.ministry_cards.clear()
	for card in selected_cards:
		player.ministry_cards.append(card)
		card.is_in_play = true
		card.is_revealed = false
	visible = false
	ministry_selected.emit(current_side, selected_cards)
	GameManager.complete_ministry_selection(current_side)


func _side_name(side: Enums.Side) -> String:
	match side:
		Enums.Side.BRITAIN: return "Britain"
		Enums.Side.FRANCE: return "France"
	return ""
