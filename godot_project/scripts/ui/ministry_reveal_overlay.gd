extends Control

# 공개 여부를 답할 때까지 원래 행동의 입력을 가린다. 공개하지 않으면 효과도
# 사용하지 않는다. 카드의 그림을 열어 보는 것과 공개를 선언하는 것을 구분한다.
var title_label: Label
var body_label: Label
var art: TextureRect
var note: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=70
	mouse_filter=Control.MOUSE_FILTER_STOP
	var shade=ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color(0.02,0.04,0.06,0.88)
	add_child(shade)
	var panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-510
	panel.offset_right=510
	panel.offset_top=-290
	panel.offset_bottom=290
	add_child(panel)
	var margin=MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,28)
	panel.add_child(margin)
	var column=VBoxContainer.new()
	column.add_theme_constant_override("separation",20)
	margin.add_child(column)
	title_label=Label.new()
	title_label.add_theme_font_size_override("font_size",27)
	column.add_child(title_label)
	var row=HBoxContainer.new()
	row.add_theme_constant_override("separation",24)
	row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(row)
	art=TextureRect.new()
	art.custom_minimum_size=Vector2(190,266)
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(art)
	body_label=Label.new()
	body_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size",20)
	row.add_child(body_label)
	note=Label.new()
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var buttons=HBoxContainer.new()
	column.add_child(buttons)
	for entry in [[LocaleManager.tx("공개하고 진행"),true],[LocaleManager.tx("비공개 유지"),false]]:
		var button=Button.new()
		button.text=entry[0]
		button.custom_minimum_size.y=54
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): MinistryDecisions.choose(entry[1]))
		buttons.add_child(button)
	var save=Button.new()
	save.text=LocaleManager.tx("저장")
	save.pressed.connect(func():note.text=LocaleManager.tx("선택 대기 상태를 저장했습니다.") if SaveLoad.save_game() else LocaleManager.tx("저장 실패: ")+SaveLoad.last_error)
	buttons.add_child(save)
	MinistryDecisions.changed.connect(refresh)
	LocaleManager.locale_changed.connect(func(_l): refresh())
	refresh()

func refresh() -> void:
	visible=MinistryDecisions.has_pending()
	if visible and AIController.enabled and MinistryDecisions.pending.side==AIController.ai_side: visible=false
	if not visible: return
	get_parent().move_child(self,get_parent().get_child_count()-1)
	var request=MinistryDecisions.pending
	var card=MinistryEffects._card(request.side,request.ids[0])
	if card==null: return
	title_label.text=LocaleManager.side(request.side)+LocaleManager.tx(" · 내각을 공개하시겠습니까?")
	art.texture=load(card.image) if ResourceLoader.exists(card.image) else null
	var purpose=LocaleManager.tx("앞으로 효과·키워드를 사용할 수 있도록 미리 공개합니다.") if request.command.kind=="reveal" else LocaleManager.tx("이 행동에 내각 효과를 사용하려면 공개해야 합니다.")
	if request.command.kind=="event":
		var event=request.command.card
		purpose=LocaleManager.tx("이벤트 ‘%s’의 보너스에 이 내각을 사용합니다.\n필요 조건: %s") % [event.disp_title(),event.disp_bonus_condition()]
	elif request.command.kind=="manual": purpose=LocaleManager.tx("선택한 능력: ")+LocaleManager.message(MinistryEffects.ability_labels(card)[request.command.index])
	elif request.command.kind=="shift": purpose=LocaleManager.tx("‘%s’ 공간의 행동에 내각 혜택을 적용합니다.") % LocaleManager.local_name(GameManager.state.spaces[request.command.id].data.display_name,GameManager.state.spaces[request.command.id].data.name_ko)
	body_label.text=card.disp_title()+"\n\n"+purpose+"\n\n"+card.disp_abilities()
	note.text=LocaleManager.tx("비공개를 유지하면 이번 행동에 이 내각의 혜택을 적용하지 않습니다.\n공개한 내각은 같은 시대의 내각 단계에서 교체할 수 없습니다. (§3.5)")
