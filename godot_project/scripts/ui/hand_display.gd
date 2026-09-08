extends Control

signal card_clicked(card: EventCard)

const CardViewScene := preload("res://scenes/ui/card_view.tscn")

@onready var hbox: HBoxContainer = $Panel/Margin/HBox
@onready var title: Label = $TitleLabel

var current_side: Enums.Side = Enums.Side.FRANCE


func _ready() -> void:
	LocaleManager.locale_changed.connect(func(_l): set_side(current_side))
	# 외교 뽑기로 손패가 3장을 넘을 수 있다. 고정 폭에 카드를 밀어 넣으면
	# 행동 패널을 침범하므로, 자기 손패 영역 안에서 가로로 스크롤한다.
	var margin = hbox.get_parent()
	margin.remove_child(hbox)
	var scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	scroll.add_child(hbox)
	margin.add_theme_constant_override("margin_top",30)
	margin.add_theme_constant_override("margin_bottom",2)
	title.add_theme_font_size_override("font_size",18)
	GameManager.phase_changed.connect(_on_phase_changed)
	ActionController.action_state_changed.connect(func(_s): refresh())
	EventEffects.effects_resolved.connect(refresh)
	refresh()


func set_side(side: Enums.Side) -> void:
	current_side = side
	title.text = LocaleManager.side(side) + LocaleManager.tx(" · 이벤트 카드")
	refresh()


func refresh() -> void:
	for child in hbox.get_children():
		hbox.remove_child(child)
		child.queue_free()
	if GameManager.state == null:
		return
	var player := GameManager.state.get_player(current_side)
	for card in player.hand:
		var view := CardViewScene.instantiate()
		hbox.add_child(view)
		view.custom_minimum_size = Vector2(73, 104)
		view.bind_event(card)
		view.clicked.connect(_on_card_clicked)
		var info = Label.new()
		info.custom_minimum_size = Vector2(172,0)
		info.text = LocaleManager.tx("#%d  %s\n%s\n보너스 · %s") % [card.id,card.disp_title(),LocaleManager.action(card.major_action),card.disp_bonus_condition()]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.max_lines_visible = 4
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.tooltip_text = info.text
		info.add_theme_font_size_override("font_size",16)
		hbox.add_child(info)


func _on_card_clicked(card) -> void:
	if card is EventCard:
		card_clicked.emit(card)


func _on_phase_changed(_phase: Enums.TurnPhase) -> void:
	refresh()
