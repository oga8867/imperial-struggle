extends Control

signal ministry_selected(side: Enums.Side, cards: Array)
signal card_detail_requested(card: EventCard)

const CardViewScene := preload("res://scenes/ui/card_view.tscn")

@onready var title_label: Label = $Panel/VBox/Title
@onready var grid: GridContainer = $Panel/VBox/Scroll/Grid
@onready var confirm_btn: Button = $Panel/VBox/HBox/ConfirmBtn
@onready var counter_label: Label = $Panel/VBox/HBox/CounterLabel

var current_side: Enums.Side = Enums.Side.NONE
var available_cards: Array[MinistryCard] = []
var selected_cards: Array[MinistryCard] = []
var locked_cards: Array = []
var card_views: Dictionary = {}  # card -> CardView
var hand_box: VBoxContainer


func _ready() -> void:
	visible = false
	$Panel/VBox/Scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_build_hand_preview()
	confirm_btn.pressed.connect(_on_confirm)
	confirm_btn.text = LocaleManager.t("btn_confirm")
	LocaleManager.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_new_locale: String) -> void:
	confirm_btn.text = LocaleManager.t("btn_confirm")
	if visible:
		title_label.text = LocaleManager.tf("ministry_select_header", [LocaleManager.side(current_side)])
		_refresh_grid()
		_refresh_hand()
		_refresh_selection_visuals()
	_refresh_counter()


func show_for_side(side: Enums.Side) -> void:
	current_side = side
	selected_cards.clear()
	if GameManager.state == null:
		return

	available_cards = GameData.get_ministries_for_era(side, GameManager.state.current_era)
	locked_cards.clear()
	if not GameManager.state.is_new_era_turn():
		selected_cards.assign(GameManager.state.get_player(side).ministry_cards)
		locked_cards = selected_cards.filter(func(c): return c.is_revealed)

	title_label.text = LocaleManager.tf("ministry_select_header", [LocaleManager.side(side)])
	_refresh_grid()
	_refresh_hand()
	_refresh_selection_visuals()
	_refresh_counter()
	visible = true


func _refresh_grid() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	card_views.clear()
	grid.columns=2
	for card in available_cards:
		var view=Button.new()
		view.custom_minimum_size=Vector2(394,285)
		view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		view.toggle_mode=true
		grid.add_child(view)
		var margin=MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,14)
		view.add_child(margin)
		var column=VBoxContainer.new()
		column.add_theme_constant_override("separation",12)
		margin.add_child(column)
		var heading=Label.new()
		heading.text=card.disp_title()+(LocaleManager.tx(" · 유지") if card in locked_cards else "")
		heading.add_theme_font_size_override("font_size",20)
		heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		column.add_child(heading)
		var keywords=Label.new()
		var names={"Governance":LocaleManager.tx("통치"),"Mercantilism":LocaleManager.tx("중상주의"),"Style":LocaleManager.tx("양식"),"Scholarship":LocaleManager.tx("학문"),"Finance":LocaleManager.tx("금융")}
		keywords.text=" · ".join(card.keywords.map(func(k):return names.get(k,k)))
		keywords.add_theme_color_override("font_color",ThemeManager.COLOR_GOLD)
		keywords.add_theme_font_size_override("font_size",15)
		column.add_child(keywords)
		var row=HBoxContainer.new()
		row.add_theme_constant_override("separation",14)
		column.add_child(row)
		var picture=TextureRect.new()
		picture.custom_minimum_size=Vector2(86,120)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		if ResourceLoader.exists(card.image): picture.texture=load(card.image)
		row.add_child(picture)
		var description=Label.new()
		description.custom_minimum_size.x=260
		description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		description.text=card.disp_abilities()
		description.add_theme_font_size_override("font_size",16)
		description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		row.add_child(description)
		# Button은 자식 설명의 최소 높이를 자동 전달하지 않는다. 긴 내각 설명이
		# 카드 밖으로 넘치지 않도록 실제 줄바꿈 높이를 Grid에 되돌려 준다.
		margin.minimum_size_changed.connect(func():
			view.custom_minimum_size.y=maxf(285,margin.get_combined_minimum_size().y))
		_ignore_mouse(margin)
		view.pressed.connect(_on_card_clicked.bind(card))
		card_views[card] = view

func _build_hand_preview() -> void:
	# 내각 단계는 손패를 받은 뒤다. 자기 이벤트의 행동 종류와 보너스 키워드를
	# 내각 후보와 나란히 비교할 수 있게 같은 창 안에 손패를 표시한다 (§4.1).
	$Panel.offset_left=-870
	$Panel.offset_right=870
	$Panel.offset_top=-476
	$Panel.offset_bottom=476
	var body=$Panel/VBox
	var scroll=$Panel/VBox/Scroll
	var row=HBoxContainer.new()
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",20)
	body.remove_child(scroll)
	body.add_child(row)
	body.move_child(row,1)
	row.add_child(scroll)
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var panel=PanelContainer.new()
	panel.custom_minimum_size.x=500
	row.add_child(panel)
	var margin=MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	panel.add_child(margin)
	var hand_scroll=ScrollContainer.new()
	hand_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(hand_scroll)
	hand_box=VBoxContainer.new()
	hand_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	hand_box.add_theme_constant_override("separation",16)
	hand_scroll.add_child(hand_box)

func _refresh_hand() -> void:
	for child in hand_box.get_children():
		hand_box.remove_child(child)
		child.queue_free()
	var heading=Label.new()
	heading.text=LocaleManager.side(current_side)+LocaleManager.tx(" · 이번 손패")
	heading.add_theme_font_size_override("font_size",23)
	hand_box.add_child(heading)
	var hint=Label.new()
	hint.text=LocaleManager.tx("카드를 눌러 효과를 확인하고 내각을 고르세요.\n손패 확인은 카드 사용이나 내각 공개가 아닙니다.")
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hand_box.add_child(hint)
	for card in GameManager.state.get_player(current_side).hand:
		var row=HBoxContainer.new()
		row.add_theme_constant_override("separation",14)
		hand_box.add_child(row)
		var view=CardViewScene.instantiate()
		view.custom_minimum_size=Vector2(100,140)
		row.add_child(view)
		view.bind_event(card)
		view.clicked.connect(func(c):card_detail_requested.emit(c))
		var button=Button.new()
		button.text=LocaleManager.tx("#%d %s\n%s\n보너스: %s\n상세 보기") % [card.id,card.disp_title(),LocaleManager.action(card.major_action),card.disp_bonus_condition()]
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func():card_detail_requested.emit(card))
		row.add_child(button)

func _ignore_mouse(node: Control) -> void:
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control: _ignore_mouse(child)


func _on_card_clicked(card) -> void:
	if not (card is MinistryCard):
		return
	if card in locked_cards: return
	if card in selected_cards:
		selected_cards.erase(card)
	elif selected_cards.size() < (3 if _extra_jacobite() else 2):
		selected_cards.append(card)
	_refresh_selection_visuals()
	_refresh_counter()


func _refresh_selection_visuals() -> void:
	for card in card_views:
		var view = card_views[card]
		if view.has_method("set_selected"):
			view.set_selected(card in selected_cards)
		elif view is Button: view.set_pressed_no_signal(card in selected_cards)


func _refresh_counter() -> void:
	counter_label.text = LocaleManager.tx("내각 %d장 선택 · 기본 2장%s") % [selected_cards.size(),LocaleManager.tx(" + 재커바이트 봉기 1장 선택 가능") if _extra_jacobite() else ""]
	confirm_btn.disabled = not (selected_cards.size()==2 or (_extra_jacobite() and selected_cards.size()==3 and selected_cards.any(func(c):return c.id=="M-4")))

func _extra_jacobite() -> bool:
	return current_side==Enums.Side.FRANCE and GameManager.state.jacobite_extra_ministry and not GameManager.state.jacobite_defeated


func _on_confirm() -> void:
	var player := GameManager.state.get_player(current_side)
	player.ministry_cards.clear()
	for card in selected_cards:
		player.ministry_cards.append(card)
		card.is_in_play = true
		if GameManager.state.is_new_era_turn(): card.is_revealed = false
	visible = false
	ministry_selected.emit(current_side, selected_cards)
	GameManager.complete_ministry_selection(current_side)
