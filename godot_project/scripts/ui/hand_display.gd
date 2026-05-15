extends Control

signal card_clicked(card: EventCard)

const CardViewScene := preload("res://scenes/ui/card_view.tscn")

@onready var hbox: HBoxContainer = $Panel/Margin/HBox
@onready var title: Label = $TitleLabel

var current_side: Enums.Side = Enums.Side.FRANCE


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	refresh()


func set_side(side: Enums.Side) -> void:
	current_side = side
	title.text = ("Britain Hand" if side == Enums.Side.BRITAIN else "France Hand")
	refresh()


func refresh() -> void:
	for child in hbox.get_children():
		child.queue_free()
	if GameManager.state == null:
		return
	var player := GameManager.state.get_player(current_side)
	for card in player.hand:
		var view := CardViewScene.instantiate()
		hbox.add_child(view)
		view.custom_minimum_size = Vector2(140, 196)
		view.bind_event(card)
		view.clicked.connect(_on_card_clicked)


func _on_card_clicked(card) -> void:
	if card is EventCard:
		card_clicked.emit(card)


func _on_phase_changed(_phase: Enums.TurnPhase) -> void:
	refresh()
