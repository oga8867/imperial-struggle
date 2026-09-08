extends Control

signal war_tile_requested
signal war_tile_upgrade_requested
signal war_tile_view_requested
var body: VBoxContainer

func _ready() -> void:
	# 남은 AP와 종료된 행동을 같은 모델에서 읽어 중복 사용 버튼이 남지 않게 한다.
	$Panel/VBox.hide()
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 14
	scroll.offset_right = -16
	scroll.offset_bottom = -14
	$Panel.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	scroll.add_child(body)
	ActionController.action_state_changed.connect(func(_s): _refresh())
	ActionController.ap_changed.connect(_refresh)
	ActionController.action_round_ended.connect(_refresh)
	GameManager.player_action_required.connect(func(_s,_a): _refresh())
	EventEffects.effects_resolved.connect(_refresh)
	LocaleManager.locale_changed.connect(func(_l): _refresh())
	_refresh()

func _label(text: String, font_size: int = 17) -> void:
	var label = Label.new()
	label.text = LocaleManager.message(text)
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)

func _button(text: String, action: Callable, enabled: bool = true, parent: Node = null) -> Button:
	var button = Button.new()
	button.text = LocaleManager.message(text)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size",18)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not enabled or AIController.is_ai_turn()
	button.pressed.connect(action)
	(parent if parent else body).add_child(button)
	return button

func _pool_button(key: String, title: String, action: Callable, parent: Node) -> void:
	var ac = ActionController
	var selected = ac.pool_key() == key
	var done = key in ac.finished_pools or (key == "minor" and ac.minor_action_used_first_expense)
	var caption = LocaleManager.tx("완료") if done else LocaleManager.tx("남은 %d점") % ac.remaining_for_pool(key)
	if selected and not done: caption += LocaleManager.tx(" · 선택 중")
	# 선택 중인 버튼을 disabled로 만들면 가장 필요한 숫자가 희미해진다.
	# 선택 상태는 테두리·문구로 표시하고, 다시 누르는 동작은 아무 것도 바꾸지 않는다.
	var button = _button(title+"\n"+caption,func():
		if ac.pool_key() != key: action.call(),ac.can_switch_pool(key) and not done,parent)
	button.custom_minimum_size.y = 80
	button.add_theme_font_size_override("font_size",22)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("354b52") if selected else Color("22343d")
	style.border_color = Color("ebc982") if selected else Color("64767b")
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(7)
	button.add_theme_stylebox_override("normal",style)
	button.add_theme_color_override("font_color",Color("f2ecdf"))

func _refresh() -> void:
	if body == null: return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var ac = ActionController
	var tile = ac.current_tile
	if tile == null:
		_label(LocaleManager.tx("이번 행동"),23)
		_label(LocaleManager.tx("투자 타일 1장을 선택하세요.\n주요 행동 · 보조 행동 · 전쟁 준비를 순서대로 진행합니다."))
		return
	_label(LocaleManager.tx("이벤트 선택") if ac.state == ac.ActionState.AWAITING_EVENT else LocaleManager.tx("행동점수 사용"),23)
	if ac.state == ac.ActionState.AWAITING_EVENT:
		_label(LocaleManager.tx("손패에서 이벤트를 선택하세요. 이벤트는 다른 행동보다 먼저 사용합니다."))
		_button(LocaleManager.tx("이벤트 없이 진행"),ac.skip_event)
	else:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		body.add_child(row)
		_pool_button("major",LocaleManager.tx("주요 ")+LocaleManager.action(tile.major_action_type),ac.switch_to_major,row)
		_pool_button("minor",LocaleManager.tx("보조 ")+LocaleManager.action(tile.minor_action_type),ac.switch_to_minor,row)
		if ac.current_action_type() == Enums.ActionType.DIPLOMATIC:
			var draw_button = _button(LocaleManager.tx("이벤트 카드 1장 뽑기 · 외교 3점"),ac.draw_event_card,ac.can_draw_event())
			draw_button.name = "DrawEventButton"
			draw_button.custom_minimum_size.y = 48
			draw_button.tooltip_text = LocaleManager.tx("외교 3점으로 카드 1장을 뽑습니다. 채무·조약점수로 보충할 수 있습니다.\n지역 등 사용처가 제한된 점수는 사용할 수 없습니다. (§5.5.3)")
			var reason = ac.draw_event_block_reason()
			_label(reason if not reason.is_empty() else LocaleManager.tx("뽑은 카드는 손패에 추가됩니다. 다음 행동 라운드부터 사용할 수 있습니다."),16)
		for i in ac.event_grants.size():
			var grant = ac.event_grants[i]
			if grant.amount <= 0 or grant.get("locked",false): continue
			var key = "event_%d" % i
			var event_row = HBoxContainer.new()
			body.add_child(event_row)
			_button(LocaleManager.tx("이벤트 %s %d점") % [LocaleManager.action(grant.type),grant.amount],ac.switch_to_event.bind(i),grant.pool == key and ac.can_switch_pool(key) and ac.pool_key()!=key,event_row)
			var select = OptionButton.new()
			select.add_item(LocaleManager.tx("별도 행동"),0)
			if grant.type == tile.major_action_type: select.add_item(LocaleManager.tx("주요 합산"),1)
			if grant.type == tile.minor_action_type: select.add_item(LocaleManager.tx("보조 합산"),2)
			select.select(select.get_item_index(1 if grant.pool=="major" else (2 if grant.pool=="minor" else 0)))
			select.disabled = not ac.spent_pools.is_empty() or AIController.is_ai_turn()
			select.item_selected.connect(func(idx): ac.assign_event_grant(i,[key,"major","minor"][select.get_item_id(idx)]))
			event_row.add_child(select)
			var note=_restriction_text(grant.restrictions)
			if not note.is_empty(): _label("↳ "+note,14)
		if EventEffects.has_pending():
			_label(LocaleManager.tx("이벤트의 대상 선택을 먼저 완료하세요."))
		else:
			var spend = HBoxContainer.new()
			body.add_child(spend)
			var p = GameManager.state.get_player(ac.current_side)
			var action_name = LocaleManager.action(ac.current_action_type())
			_button(LocaleManager.tx("채무로 %s 점수 보충") % action_name,func(): ac.take_debt_for_ap(1),p.available_debt()>0 or MinistryDecisions.possible_bank_credit(ac.current_side)>0,spend)
			_button(LocaleManager.tx("조약점수 1 → %s 1점") % action_name,func(): ac.spend_treaty_points_for_ap(1),p.treaty_points>0,spend)
			if ac.current_action_type() == Enums.ActionType.MILITARY:
				if GameManager.state.current_turn == 6:
					for type in [Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC]:
						_button(LocaleManager.tx("군사 2점 → %s 1점") % LocaleManager.action(type),ac.convert_turn6_military.bind(type),not ac.conversion_plan().is_empty() and ac.turn6_conversion_type in [Enums.ActionType.NONE,type])
				else:
					_button(LocaleManager.tx("보너스 전쟁 타일 구입 · 군사 2점"),func(): war_tile_requested.emit(),not ac.bonus_purchase_theaters().is_empty())
			if tile.has_military_upgrade:
				_button(LocaleManager.tx("전쟁 준비 · ") + (LocaleManager.tx("조약점수 1") if GameManager.state.current_turn==6 else LocaleManager.tx("기본 전쟁 타일 교체")),func(): war_tile_upgrade_requested.emit(),ac.can_upgrade())
			# 위그노 마커는 원래 내각이 퇴임한 뒤에도 지도에 남아 사용할 수 있다.
			for ss in GameManager.state.spaces.values():
				if ac.can_flip_huguenots(ss.data.id): _button(LocaleManager.local_name(ss.data.display_name,ss.data.name_ko)+LocaleManager.tx(" 위그노 · 시장 비용 −1"),ac.flip_huguenots.bind(ss.data.id))
			if ac.can_undo(): _button(LocaleManager.tx("직전 행동 되돌리기"),ac.undo_last)
			_button(LocaleManager.tx("행동 라운드 종료"),ac.end_action_round,ac.can_end_action_round())
		_label(LocaleManager.tx("행동에서 점수를 쓴 뒤 다른 행동으로 바꾸면 돌아갈 수 없습니다. 보조 행동은 한 번만 지출합니다."),14)
	if not ac.action_started:
		_button(LocaleManager.tx("이 타일을 소비하고 패스 · 부채 2 감소"),func(): GameManager.pass_action_round(ac.current_side))

func _restriction_text(rules: Dictionary) -> String:
	# 숫자가 같아도 카드 AP마다 사용할 수 있는 대상은 다르다 (§5.2.4).
	var parts: Array[String]=[]
	if rules.has("region"): parts.append(LocaleManager.region(rules.region)+LocaleManager.tx(" 전용"))
	if rules.get("non_prestige",false): parts.append(LocaleManager.tx("위신 공간 제외"))
	if rules.get("unflag",false): parts.append(LocaleManager.tx("상대 깃발 제거 전용"))
	if rules.get("flag_adjacent_market",false): parts.append(LocaleManager.tx("내 시장과 인접한 빈 시장에 배치"))
	if rules.has("countries"):
		var names={"spain":LocaleManager.tx("스페인"),"austria":LocaleManager.tx("오스트리아"),"savoy":LocaleManager.tx("사보이"),"sardinia":LocaleManager.tx("사르데냐"),"dutch":LocaleManager.tx("네덜란드")}
		parts.append(" · ".join(rules.countries.map(func(c):return names.get(c,c)))+LocaleManager.tx(" 공간 전용"))
	if rules.has("kinds"):
		var names={"naval":LocaleManager.tx("함대 배치"),"war_tile":LocaleManager.tx("보너스 전쟁 타일"),"construct":LocaleManager.tx("함대 건조"),"shift":LocaleManager.tx("공간 변경")}
		parts.append(" · ".join(rules.kinds.map(func(k):return names.get(k,k)))+LocaleManager.tx(" 전용"))
	return " / ".join(parts)
