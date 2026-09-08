extends Control

# 손패를 넘겨 주는 가림 화면과 게임 종료 결과는 화면 최상단에서 처리한다.
# 규칙 데이터는 보관하지 않는다. 저장된 모델로 언제든 다시 만들 수 있다.
var heading: Label
var detail: Label
var body: VBoxContainer
var actions: HBoxContainer
var _refresh_view: Callable

func _ready() -> void:
	LocaleManager.locale_changed.connect(func(_l):
		if visible and _refresh_view.is_valid(): _refresh_view.call())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=100
	var shade=ColorRect.new()
	shade.color=Color("101a20")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	body=VBoxContainer.new()
	body.custom_minimum_size.x=900
	body.add_theme_constant_override("separation",28)
	center.add_child(body)
	var eyebrow=Label.new()
	eyebrow.text="IMPERIAL STRUGGLE"
	eyebrow.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color",ThemeManager.COLOR_GOLD)
	eyebrow.add_theme_font_size_override("font_size",22)
	body.add_child(eyebrow)
	heading=Label.new()
	heading.add_theme_font_size_override("font_size",60)
	heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(heading)
	detail=Label.new()
	detail.add_theme_font_size_override("font_size",23)
	detail.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)
	actions=HBoxContainer.new()
	actions.alignment=BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation",18)
	body.add_child(actions)
	hide()

func _clear_actions() -> void:
	for c in actions.get_children():
		actions.remove_child(c)
		c.queue_free()

func _button(label: String,callback: Callable) -> void:
	var button=Button.new()
	button.text=label
	button.custom_minimum_size=Vector2(320,64)
	button.pressed.connect(callback)
	actions.add_child(button)

func handoff(side: int,ready: Callable) -> void:
	_refresh_view = handoff.bind(side,ready)
	_clear_actions()
	heading.text=LocaleManager.side(side)+LocaleManager.tx(" 차례입니다")
	detail.text=LocaleManager.tx("다음 플레이어에게 화면을 넘겨 주세요.\n준비가 되면 자신의 손패와 내각을 확인할 수 있습니다.")
	_button(LocaleManager.tx("준비 완료 · 내 카드 확인"),func():
		hide()
		ready.call())
	show()

func victory(winner: int,review: Callable,menu: Callable) -> void:
	_refresh_view = victory.bind(winner,review,menu)
	_clear_actions()
	heading.text=LocaleManager.side(winner)+LocaleManager.tx("의 승리")
	var s=GameManager.state
	detail.text=LocaleManager.tx("%s\n\n최종 승점 %d  ·  %d턴\n영국의 부채 %d/%d  |  프랑스의 부채 %d/%d") % [LocaleManager.message(s.victory_reason),s.vp,s.current_turn,s.britain.current_debt,s.britain.debt_limit,s.france.current_debt,s.france.debt_limit]
	_button(LocaleManager.tx("마지막 지도 살펴보기"),func():
		hide()
		review.call())
	_button(LocaleManager.tx("제목 화면"),menu)
	show()
