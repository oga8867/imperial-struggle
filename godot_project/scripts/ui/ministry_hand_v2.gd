extends Control

@onready var hbox: HBoxContainer = $Panel/Margin/VBox/HBox
@onready var title: Label = $Panel/Margin/VBox/Title
var viewer_side: int = Enums.Side.NONE

func set_view_side(side: int) -> void:
	viewer_side=side
	refresh()

func _ready() -> void:
	LocaleManager.locale_changed.connect(func(_l): refresh())
	title.add_theme_font_size_override("font_size",17)
	GameManager.phase_changed.connect(func(_p): refresh())
	GameManager.action_round_started.connect(func(_s,_r): refresh())
	ActionController.ap_changed.connect(refresh)
	ActionController.action_state_changed.connect(func(_l): refresh())
	EventEffects.effects_resolved.connect(refresh)
	MinistryDecisions.changed.connect(refresh)
	refresh()

func refresh() -> void:
	for child in hbox.get_children():
		hbox.remove_child(child)
		child.queue_free()
	if GameManager.state==null: return
	var side=GameManager.state.phasing_player
	if viewer_side!=Enums.Side.NONE: side=viewer_side
	if AIController.enabled: side=WarManager._opp(AIController.ai_side)
	title.text=LocaleManager.side(side)+LocaleManager.tx(" · 내각")
	var cards=GameManager.state.get_player(side).ministry_cards
	for card in cards:
		var column=VBoxContainer.new()
		column.custom_minimum_size.x=100 if cards.size()==3 else 158
		column.add_theme_constant_override("separation",2)
		hbox.add_child(column)
		var image=TextureButton.new()
		image.custom_minimum_size=Vector2(column.custom_minimum_size.x,36)
		image.ignore_texture_size=true
		image.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists(card.image): image.texture_normal=load(card.image)
		image.tooltip_text=card.disp_title()+"\n"+card.disp_abilities()
		image.pressed.connect(func(): _show_card(card))
		column.add_child(image)
		var label=Label.new()
		label.text=card.disp_title()
		label.add_theme_font_size_override("font_size",13)
		label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(label)
		var reveal=Button.new()
		reveal.text=LocaleManager.tx("공개됨") if card.is_revealed else LocaleManager.tx("비공개 · 공개 선택")
		reveal.add_theme_font_size_override("font_size",13)
		reveal.custom_minimum_size.y=24
		reveal.disabled=not MinistryDecisions.can_reveal(card,side) or AIController.is_ai_turn() or MinistryDecisions.has_pending()
		reveal.tooltip_text=LocaleManager.tx("자기 행동 라운드에는 타일 선택 전에도 공개할 수 있습니다. (§3.5, §5.0)")
		reveal.pressed.connect(func():MinistryDecisions.offer(side,[card.id],{"kind":"reveal","side":side}))
		column.add_child(reveal)
		var button=Button.new()
		button.text=LocaleManager.tx("능력 사용")
		button.add_theme_font_size_override("font_size",12)
		button.custom_minimum_size.y=26
		button.visible=not MinistryEffects.ability_labels(card).is_empty()
		button.disabled=not MinistryDecisions.own_round(side) or AIController.is_ai_turn() or MinistryDecisions.has_pending()
		button.pressed.connect(func(): _show_abilities(card,side))
		column.add_child(button)
		# 좁은 손패 띠에서 글자를 키우되 아래 안내 막대로 넘치지 않게
		# 버튼 안쪽 여백만 줄인다. 클릭 영역과 글자 크기는 유지한다.
		for control in [reveal,button]:
			for state_name in ["normal","hover","pressed","disabled"]:
				var style = control.get_theme_stylebox(state_name).duplicate()
				style.content_margin_top = 4
				style.content_margin_bottom = 4
				control.add_theme_stylebox_override(state_name,style)

func _show_card(card: MinistryCard) -> void:
	# 자신의 카드 확인은 공개 선언이 아니다. 실제 능력·키워드 사용 때 공개한다.
	var modal=get_tree().root.find_child("CardModal",true,false)
	if modal: modal.show_card(card)

func _show_abilities(card: MinistryCard,side: int) -> void:
	var popup=PopupPanel.new()
	var box=VBoxContainer.new()
	box.custom_minimum_size=Vector2(580,100)
	box.add_theme_constant_override("separation",12)
	popup.add_child(box)
	var labels=MinistryEffects.ability_labels(card)
	for i in labels.size():
		var button=Button.new()
		button.text=LocaleManager.message(labels[i])
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y=52
		button.disabled=not MinistryEffects.can_activate(card,side,i)
		button.pressed.connect(func():
			popup.hide()
			MinistryEffects.activate_manual(card,side,i)
			refresh())
		box.add_child(button)
	var close=Button.new()
	close.text=LocaleManager.tx("닫기")
	close.pressed.connect(popup.hide)
	box.add_child(close)
	add_child(popup)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup_centered()
