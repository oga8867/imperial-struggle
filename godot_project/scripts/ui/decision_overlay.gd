extends Control

# 규칙상 사람의 선택이 필요한 단계만 표시하는 공통 창.
# 선택은 이 창에만 저장하지 않고 GameManager에 제출하므로 저장·재개도 같은 경로로 동작한다.
var side: int = Enums.Side.NONE
var action: String = ""
var selected: Array = []
var confirm: Button
var count_label: Label
var grid: GridContainer

func _ready() -> void:
	LocaleManager.locale_changed.connect(func(_l):
		if not visible: return
		# 언어만 바꾸면서 확정 전 선택을 지우지 않는다.
		var kept = selected.duplicate()
		show_decision(side,action)
		selected.assign(kept)
		if action == "discard_events":
			for i in grid.get_child_count():
				grid.get_child(i).set_pressed_no_signal(GameManager.state.get_player(side).hand[i] in selected)
		_refresh())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color(0.02,0.04,0.05,0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(1040,560)
	center.add_child(panel)
	var margin = MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,32)
	panel.add_child(margin)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",24)
	margin.add_child(body)
	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size",26)
	body.add_child(count_label)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",16)
	body.add_child(grid)
	confirm = Button.new()
	confirm.text = LocaleManager.tx("선택 확정")
	confirm.custom_minimum_size.y = 48
	confirm.pressed.connect(_submit)
	body.add_child(confirm)
	hide()

func show_decision(player_side: int, kind: String) -> void:
	side = player_side
	action = kind
	selected.clear()
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	if action == "discard_events":
		for card in GameManager.state.get_player(side).hand:
			var button = Button.new()
			button.custom_minimum_size = Vector2(310,140)
			button.text = LocaleManager.tx("#%d  %s\n%s\n보너스: %s") % [card.id,card.disp_title(),LocaleManager.action(card.major_action),card.disp_bonus_condition()]
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.toggle_mode = true
			button.tooltip_text = card.disp_both_base() if card.is_symmetric() else (card.disp_french_base() if side == Enums.Side.FRANCE else card.disp_british_base())
			button.toggled.connect(func(on):
				if on: selected.append(card)
				else: selected.erase(card)
				_refresh())
			grid.add_child(button)
	else:
		for first in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
			var button = Button.new()
			button.text = LocaleManager.side(first) + LocaleManager.tx(" 먼저 진행")
			button.custom_minimum_size = Vector2(440,180)
			button.pressed.connect(func():
				selected = [first]
				_submit())
			grid.add_child(button)
	_refresh()
	show()

func _refresh() -> void:
	confirm.visible = action == "discard_events"
	confirm.disabled = selected.size() != 3
	count_label.text = LocaleManager.tx("%s · 남길 이벤트 3장을 선택하세요 (%d/3)") % [LocaleManager.side(side),selected.size()] if action == "discard_events" else LocaleManager.tx("%s · 주도권: 이번 턴의 선공을 선택하세요") % LocaleManager.side(side)

func _submit() -> void:
	hide()
	if action == "discard_events":
		if not GameManager.complete_discard(side, selected): show()
	elif not selected.is_empty():
		GameManager.choose_first_player(selected[0])
