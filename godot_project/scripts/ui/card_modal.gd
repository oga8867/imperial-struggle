extends Control

@onready var bg: ColorRect = $BG
@onready var card_image: TextureRect = $Center/CardImage
@onready var title_label: Label = $Center/Info/Title
@onready var desc_label: RichTextLabel = $Center/Info/Description
@onready var close_btn: Button = $Center/Info/CloseBtn
var play_btn: Button
var bonus_toggle: CheckBox
var current_card = null


func _ready() -> void:
	LocaleManager.locale_changed.connect(func(_l):
		if visible and current_card:
			if current_card is EventCard: _show_event(current_card)
			elif current_card is MinistryCard: _show_ministry(current_card))
	visible = false
	bg.gui_input.connect(_on_bg_input)
	close_btn.pressed.connect(_on_close)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 설명 뒤의 지도가 비치면 한글 문장이 지도 지명과 겹쳐 읽기 어렵다.
	var panel=Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-572
	panel.offset_right=572
	panel.offset_top=-332
	panel.offset_bottom=332
	add_child(panel)
	move_child(panel,1)
	title_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	desc_label.fit_content=false
	desc_label.add_theme_font_size_override("normal_font_size",19)
	bonus_toggle=CheckBox.new()
	bonus_toggle.text=LocaleManager.tx("조건을 충족하면 보너스 효과도 사용")
	$Center/Info.add_child(bonus_toggle)
	play_btn=Button.new()
	play_btn.text=LocaleManager.tx("이 이벤트 사용")
	play_btn.custom_minimum_size.y=50
	play_btn.pressed.connect(_play_event)
	$Center/Info.add_child(play_btn)
	$Center/Info.move_child(close_btn,$Center/Info.get_child_count()-1)
	close_btn.text=LocaleManager.tx("닫기")
	close_btn.custom_minimum_size.y=44


func show_card(card) -> void:
	if card == null:
		return
	# 그림의 z 순서와 클릭 수신 순서를 함께 올린다. 사용된 카드/내각 선택 창은
	# 닫지 않고 뒤에 남겨 두므로 상세를 닫으면 같은 목록으로 돌아온다.
	z_index = 80
	get_parent().move_child(self,get_parent().get_child_count()-1)
	visible = true
	current_card=card
	var ac=ActionController
	var can_play=card is EventCard and ac.state==ac.ActionState.AWAITING_EVENT and not AIController.is_ai_turn() and card in GameManager.state.get_player(ac.current_side).hand and ac._can_play_event(card)
	play_btn.visible=can_play
	bonus_toggle.visible=can_play
	bonus_toggle.button_pressed=can_play and EventEffects.bonus_condition_met(card,ac.current_side,false)
	bonus_toggle.disabled=not bonus_toggle.button_pressed
	if card is EventCard:
		_show_event(card)
	elif card is MinistryCard:
		_show_ministry(card)


func _show_event(card: EventCard) -> void:
	var display_title := card.disp_title()
	if LocaleManager.current_locale == "ko" and card.title_ko != "":
		display_title = "%s  /  %s" % [card.title_ko, card.title]
	title_label.text = "#%d  %s" % [card.id, display_title]
	if card.image != "" and ResourceLoader.exists(card.image):
		card_image.texture = load(card.image)
	else:
		card_image.texture = null
	var lines := []
	if card.major_action != Enums.ActionType.NONE:
		lines.append("[i]%s: %s[/i]" % [LocaleManager.t("modal_major_action"), LocaleManager.action(card.major_action)])
	if card.disp_bonus_condition() != "":
		lines.append("[b]%s:[/b] %s" % [LocaleManager.t("modal_bonus_cond"), card.disp_bonus_condition()])
	if card.disp_both_base() != "":
		lines.append("[b]%s:[/b] %s" % [LocaleManager.t("modal_effect"), card.disp_both_base()])
	if card.disp_both_bonus() != "":
		lines.append("[b]%s:[/b] %s" % [LocaleManager.t("modal_bonus_effect"), card.disp_both_bonus()])
	if card.disp_british_base() != "":
		lines.append("[b][color=#c8423a]%s:[/color][/b] %s" % [LocaleManager.t("modal_british"), card.disp_british_base()])
	if card.disp_british_bonus() != "":
		lines.append("[b][color=#c8423a]%s:[/color][/b] %s" % [LocaleManager.t("modal_british_bonus"), card.disp_british_bonus()])
	if card.disp_french_base() != "":
		lines.append("[b][color=#3a5fb0]%s:[/color][/b] %s" % [LocaleManager.t("modal_french"), card.disp_french_base()])
	if card.disp_french_bonus() != "":
		lines.append("[b][color=#3a5fb0]%s:[/color][/b] %s" % [LocaleManager.t("modal_french_bonus"), card.disp_french_bonus()])
	if card.disp_special_note() != "":
		lines.append("[i]" + card.disp_special_note() + "[/i]")
	desc_label.text = "\n\n".join(lines)


func _show_ministry(card: MinistryCard) -> void:
	var display_title := card.title
	if LocaleManager.current_locale == "ko" and card.title_ko != "":
		display_title = "%s  /  %s" % [card.title_ko, card.title]
	title_label.text = "%s  %s" % [card.id, display_title]
	if card.image != "" and ResourceLoader.exists(card.image):
		card_image.texture = load(card.image)
	else:
		card_image.texture = null
	var kw := ", ".join(card.keywords) if card.keywords.size() > 0 else "—"
	var abilities_text := card.abilities
	if LocaleManager.current_locale == "ko" and card.abilities_ko != "":
		abilities_text = card.abilities_ko
	desc_label.text = "[b]%s:[/b] %s\n\n%s" % [LocaleManager.t("modal_keywords"), kw, abilities_text]


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_close()


func _on_close() -> void:
	visible = false

func _play_event() -> void:
	# 창을 먼저 닫아 뒤이어 나타날 카드의 대상 선택창을 가리지 않는다.
	hide()
	if not ActionController.play_event(current_card,bonus_toggle.button_pressed) and not MinistryDecisions.has_pending(): show()
