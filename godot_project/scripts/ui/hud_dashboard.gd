extends Control

# 정보의 순서를 고정한다: 자원 → 이번 턴의 보상 → 지도와 행동.
# 숫자만 바뀌는 표시를 매번 새로 만들지 않고 보관해 갱신하므로 마우스 위치와
# 툴팁이 흔들리지 않는다. 글꼴은 ThemeManager의 한국어 지원 글꼴을 상속한다.
const PAPER = Color("f2ecdf")
const MUTED = Color("b8c6c8")
const GOLD = Color("ebc982")
const BRITAIN = Color("eb8576")
const FRANCE = Color("80b9ed")
const RewardIcon = preload("res://scripts/ui/reward_icon.gd")
const COMMODITY_IMAGES = {
	Enums.Commodity.FISH:preload("res://assets/icons/Demand_Fish.png"),
	Enums.Commodity.FUR:preload("res://assets/icons/Demand_Furs.png"),
	Enums.Commodity.SPICE:preload("res://assets/icons/Demand_Spice.png"),
	Enums.Commodity.SUGAR:preload("res://assets/icons/Demand_Sugar.png"),
	Enums.Commodity.TOBACCO:preload("res://assets/icons/Demand_Tobacco.png"),
	Enums.Commodity.COTTON:preload("res://assets/icons/Demand_Cotton.png")}
var players: Dictionary = {}
var demand_cells: Array = []
var award_cells: Array = []
var turn_label: Label
var vp_label: Label
var phase_label: Label
var track: Control

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_player(Enums.Side.BRITAIN, Rect2(24,12,696,120), BRITAIN)
	_build_player(Enums.Side.FRANCE, Rect2(1200,12,696,120), FRANCE)
	var center = _panel(Rect2(736,12,448,120), Color("394b55"))
	turn_label = _label(center,"",18,Rect2(12,7,424,26),MUTED)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vp_label = _label(center,"",34,Rect2(12,30,424,46),GOLD)
	vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label = _label(center,"",16,Rect2(12,83,424,28),PAPER)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	track = Control.new()
	track.position = Vector2(80,78)
	track.size = Vector2(288,4)
	track.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(track)
	track.draw.connect(_draw_track)
	center.tooltip_text = LocaleManager.tx("승점은 영국이 얻으면 내려가고 프랑스가 얻으면 올라갑니다.\n승리 확인 단계: 0 이하 영국 승리 / 30 이상 프랑스 승리. (§4.1.13)")
	_label(self,LocaleManager.tx("세계 수요"),20,Rect2(24,143,170,28),GOLD)
	_label(self,LocaleManager.tx("상품별 시장이 더 많은 진영이 획득"),16,Rect2(200,145,520,26),MUTED)
	_label(self,LocaleManager.tx("지역 보상"),20,Rect2(968,143,185,28),GOLD)
	_label(self,LocaleManager.tx("턴 종료 시 판정 · 기본 보상"),16,Rect2(1160,145,400,26),MUTED)
	# 기본 수요는 3종이지만 카드 효과로 늘어날 수 있다. 모든 상품 칸을
	# 준비하고 현재 개수에 맞춰 폭을 나눈다. 네 번째 수요를 숨기지 않는다.
	for i in 6:
		var panel = _panel(Rect2(24+i*312,178,302,90),Color("4a5a59"))
		var cell = _reward_cell(panel)
		cell.name.position.x = 42
		var commodity_icon = TextureRect.new()
		commodity_icon.position = Vector2(12,5)
		commodity_icon.size = Vector2(24,24)
		commodity_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		commodity_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		commodity_icon.mouse_filter = MOUSE_FILTER_IGNORE
		panel.add_child(commodity_icon)
		cell.commodity_icon = commodity_icon
		demand_cells.append(cell)
	for i in 4:
		var panel = _panel(Rect2(968+i*234,178,224,90),Color("4a5a59"))
		var cell = _reward_cell(panel)
		cell.margin = _label(panel,"",15,Rect2(143,7,75,24),MUTED)
		award_cells.append(cell)
	GameManager.phase_changed.connect(func(_p): refresh())
	GameManager.vp_changed.connect(func(_v): refresh())
	GameManager.action_round_started.connect(func(_s,_r): refresh())
	GameManager.player_action_required.connect(func(_s,_a): refresh())
	ActionController.ap_changed.connect(refresh)
	ActionController.action_state_changed.connect(func(_s): refresh())
	EventEffects.effects_resolved.connect(refresh)
	MinistryDecisions.resolved.connect(refresh)
	LocaleManager.locale_changed.connect(func(_l): refresh())
	refresh()

func _panel(rect: Rect2, accent: Color) -> Panel:
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = MOUSE_FILTER_PASS
	var style = StyleBoxFlat.new()
	style.bg_color = Color("1c2d35")
	style.border_color = accent
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	return panel

func _reward_cell(panel: Panel) -> Dictionary:
	var icons: Array = []
	for i in 2:
		var icon = RewardIcon.new()
		icon.position = Vector2(12,32+i*25)
		icon.size = Vector2(21,21)
		panel.add_child(icon)
		icons.append(icon)
	return {"panel":panel,"icons":icons,
		"name":_label(panel,"",19,Rect2(12,5,116,26),PAPER),
		"reward":_label(panel,"",17,Rect2(40,28,172,54),GOLD)}

func _show_reward(cell: Dictionary, vp: int, treaty: int, debt: int = 0) -> void:
	# 세계 수요와 지역 보상은 같은 아이콘 체계를 사용한다. 채무 +/−와
	# 보상 이름을 텍스트에 남겨, 그림이나 색만으로 뜻을 추측하지 않아도 된다.
	cell.reward.text = _reward_text(vp,treaty,debt)
	cell.reward.size.x = cell.panel.size.x-52
	cell.reward.position.y = 28
	cell.reward.size.y = 54
	cell.reward.autowrap_mode = TextServer.AUTOWRAP_OFF
	var font_size = 19 if LocaleManager.current_locale == "ko" else 17
	var font = cell.reward.get_theme_font("font")
	var lines = cell.reward.text.split("\n")
	while font_size > 12:
		var fits = true
		for line in lines:
			if font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > cell.reward.size.x: fits = false
		if fits: break
		font_size -= 1
	cell.reward.add_theme_font_size_override("font_size",font_size)
	# 라벨의 실제 줄 높이와 아이콘 간격을 맞춘다. 한글·영문 글꼴에서도 동일하다.
	var line_height = font.get_height(font_size)+cell.reward.get_theme_constant("line_spacing")
	cell.icons[0].position.y = 28+(font.get_height(font_size)-21)/2
	cell.icons[1].position.y = cell.icons[0].position.y+line_height
	cell.icons[0].show()
	cell.icons[1].visible = treaty > 0 or debt != 0
	cell.icons[1].kind = 1 if treaty > 0 else 2
	cell.icons[1].queue_redraw()

func _label(parent: Node, text: String, font_size: int, rect: Rect2, color: Color) -> Label:
	var label = Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_player(side: int, rect: Rect2, accent: Color) -> void:
	var panel = _panel(rect,accent)
	_label(panel,LocaleManager.side(side),23,Rect2(16,7,160,30),accent)
	var badge = _label(panel,"",16,Rect2(250,9,428,26),PAPER)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var values: Array = []
	var details: Array = []
	var names = [LocaleManager.tx("채무"), LocaleManager.tx("가용 채무"), LocaleManager.tx("조약점수"), LocaleManager.tx("함대"), LocaleManager.tx("손패")]
	for i in names.size():
		var x = 16+i*136
		_label(panel,names[i],17,Rect2(x,39,128,24),MUTED)
		values.append(_label(panel,"",30,Rect2(x,60,128,38),GOLD if i in [1,2] else PAPER))
		details.append(_label(panel,"",14,Rect2(x,96,128,20),MUTED))
	players[side] = {"panel":panel,"badge":badge,"values":values,"details":details,"accent":accent}

func refresh() -> void:
	var s = GameManager.state
	if s == null or s.britain == null: return
	for side in players:
		var p = s.get_player(side)
		var ui = players[side]
		var active = s.current_turn_phase == Enums.TurnPhase.ACTION_PHASE and s.phasing_player == side
		ui.badge.text = LocaleManager.tx("행동 중 · %d / 4 라운드") % s.current_action_round if active else ""
		var style = ui.panel.get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = Color("273a43") if active else Color("1c2d35")
		var values = [p.current_debt,p.available_debt(),p.treaty_points,p.total_squadrons(),p.hand.size()]
		var details = [LocaleManager.tx("한도 %d") % p.debt_limit,LocaleManager.tx("추가 차입 가능"),LocaleManager.tx("행동점수로 전환"),LocaleManager.tx("대기 %d척") % p.squadrons_in_navy_box,LocaleManager.tx("이벤트 카드")]
		for i in values.size():
			ui.values[i].text = str(values[i])
			ui.details[i].text = details[i]
	turn_label.text = LocaleManager.tx("%d / 6턴   ·   %s") % [s.current_turn,LocaleManager.era(s.current_era)]
	vp_label.text = LocaleManager.tx("승점  %d") % s.vp
	phase_label.text = LocaleManager.tx("영국 ← 0       %s       30 → 프랑스") % (LocaleManager.tx("균형") if s.vp == 15 else (LocaleManager.tx("영국 우세") if s.vp < 15 else LocaleManager.tx("프랑스 우세")))
	turn_label.tooltip_text = LocaleManager.phase(s.current_turn_phase)
	track.queue_redraw()
	var demand_count = maxi(3,s.current_global_demand.size())
	var demand_step = 936.0/demand_count
	for i in demand_cells.size():
		var cell = demand_cells[i]
		cell.panel.visible = i < demand_count
		cell.panel.position.x = 24+i*demand_step
		cell.panel.size.x = demand_step-10
		cell.name.size.x = demand_step-64
		if i >= s.current_global_demand.size():
			cell.name.text = LocaleManager.tx("수요 배정 전")
			cell.reward.text = "—"
			cell.commodity_icon.hide()
			for icon in cell.icons: icon.hide()
			continue
		var commodity = s.current_global_demand[i]
		var reward = GameManager.commodity_reward(commodity)
		cell.name.text = LocaleManager.commodity(commodity)
		cell.commodity_icon.texture = COMMODITY_IMAGES[commodity]
		cell.commodity_icon.show()
		_show_reward(cell,reward[0],reward[2],reward[1])
		cell.panel.tooltip_text = LocaleManager.tx("현재 시장 수: 영국 %d / 프랑스 %d\n시장 수가 같으면 보상이 없습니다. 표시값은 내각 효과 적용 전 기본 보상입니다. (§4.1.12)") % [GameManager._count_commodity_markets(Enums.Side.BRITAIN,commodity),GameManager._count_commodity_markets(Enums.Side.FRANCE,commodity)]
	var regions = [Enums.Region.EUROPE,Enums.Region.NORTH_AMERICA,Enums.Region.CARIBBEAN,Enums.Region.INDIA]
	for i in regions.size():
		var cell = award_cells[i]
		var award = AwardManager.get_award_for_region(regions[i])
		cell.name.text = LocaleManager.region(regions[i])
		var english = LocaleManager.current_locale == "en"
		cell.name.add_theme_font_size_override("font_size",17 if english else 19)
		cell.name.size.x = 138 if english else 116
		cell.margin.position.x = 156 if english else 143
		cell.margin.size.x = 64 if english else 75
		cell.margin.add_theme_font_size_override("font_size",12 if english else 15)
		cell.margin.text = LocaleManager.tx("%d칸 우세") % award.get("margin_required",1)
		if not award.is_empty():
			_show_reward(cell,award.get("vp",0),award.get("tp",0))
		else:
			cell.reward.text = LocaleManager.tx("배정 전")
			for icon in cell.icons: icon.hide()
		cell.panel.tooltip_text = LocaleManager.tx("현재 지배 공간: 영국 %d / 프랑스 %d\n상대보다 표시된 칸 수 이상 많아야 획득합니다.\n내각 보너스와 유럽의 위신 승점은 별도 판정합니다. (§4.1.12)") % [GameManager._count_flags_in_region(Enums.Side.BRITAIN,regions[i]),GameManager._count_flags_in_region(Enums.Side.FRANCE,regions[i])]

func _reward_text(vp: int, treaty: int, debt: int = 0) -> String:
	var parts: Array[String] = [LocaleManager.tx("승점 %d") % vp]
	if treaty > 0: parts.append(LocaleManager.tx("조약점수 %d") % treaty)
	if debt != 0: parts.append(LocaleManager.tx("채무 %+d") % debt)
	if LocaleManager.current_locale == "en":
		# 영문 전체 용어를 유지하면서 두 줄로 배치한다. 한 점에는 단수형을 쓴다.
		if vp == 1: parts[0] = parts[0].trim_suffix("s")
		if treaty == 1: parts[1] = parts[1].trim_suffix("s")
	return "\n".join(parts)

func _draw_track() -> void:
	var s = GameManager.state
	if s == null: return
	track.draw_line(Vector2.ZERO,Vector2(144,0),BRITAIN,3,true)
	track.draw_line(Vector2(144,0),Vector2(288,0),FRANCE,3,true)
	track.draw_circle(Vector2(clampf(s.vp/30.0,0,1)*288,0),5,PAPER)
