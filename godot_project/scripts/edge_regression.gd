extends "res://scripts/card_regression.gd"

# 숫자 결과와 불법 경로를 함께 검사한다. 단순히 버튼이 눌리는지만 확인하면
# 규칙 오류가 있어도 완주 검사를 통과할 수 있기 때문이다.
func _ready() -> void:
	await get_tree().process_frame
	fresh()
	var s=GameManager.state.spaces
	check("실선: Puerto Principe–Puerto Rico", "puerto_rico" in s.puerto_principe.data.connections and "port_de_paix" not in s.puerto_rico.data.connections)
	check("Halifax는 북부 식민지",s.halifax_fort.data.sub_region==Enums.SubRegion.NORTHERN_COLONIES)
	check("Acadia 정복선은 Louisbourg",s.acadia.data.conquest_line_connections==["louisbourg_fort"])
	check("Gibraltar와 Carolinas에는 정복선 없음",s.gibraltar.data.conquest_line_connections.is_empty() and s.carolinas.data.conquest_line_connections.is_empty())
	check("Madras는 Arcot 또는 Vandavasi 정복선",s.madras.data.conquest_line_connections.size()==2 and "arcot_fort" in s.madras.data.conquest_line_connections)
	check("면화 영토는 Hooghly 해군 정복선",s.calcutta.data.conquest_line_connections==["hooghly_river_naval"])
	WarManager.setup_war("seven_years")
	WarFlow.index=3
	for i in WarManager.wars.seven_years.theaters.size():
		if WarManager.wars.seven_years.theaters[i].region==Enums.Region.INDIA: WarFlow.index=i
	s.arcot_fort.controlled_by=Enums.Side.NONE
	s.vandavasi_fort.controlled_by=Enums.Side.NONE
	check("Madras 정복선 없이 CP 지출 거절",not WarFlow.conquest_options(Enums.Side.FRANCE,3).any(func(o):return o.id=="madras"))
	s.arcot_fort.controlled_by=Enums.Side.FRANCE
	check("Arcot 지배 후 Madras 정복 허용",WarFlow.conquest_options(Enums.Side.FRANCE,3).any(func(o):return o.id=="madras"))
	# Vatican 기본 효과가 마지막 상대 깃발을 제거한 뒤에 보너스 효과를 판정한다.
	fresh()
	s=GameManager.state.spaces
	for ss in s.values():
		if ss.data.id.begins_with("spain") or ss.data.id.begins_with("austria"): ss.controlled_by=Enums.Side.NONE
	s.spain_alliance.controlled_by=Enums.Side.BRITAIN
	var before=GameManager.state.vp
	EventEffects.apply_event(GameData.events.filter(func(c):return c.id==10)[0],Enums.Side.FRANCE,true)
	check("Vatican 공간 선택 전에는 득점 없음",GameManager.state.vp==before)
	EventEffects.resolve_choice(0,"spain_alliance")
	check("Vatican 기본 효과 후 보너스 +2",GameManager.state.vp==before+2 and not EventEffects.has_pending())
	fresh(Enums.Side.BRITAIN)
	for ss in GameManager.state.spaces.values():
		if ss.data.commodity==Enums.Commodity.COTTON: ss.controlled_by=Enums.Side.BRITAIN
	before=GameManager.state.vp
	var tp=GameManager.state.britain.treaty_points
	EventEffects.apply_event(GameData.events.filter(func(c):return c.id==11)[0],Enums.Side.BRITAIN,true)
	check("Calico 수요 득점은 선택 사항",EventEffects.choice_options().any(func(o):return o.id=="skip") and GameManager.state.vp==before)
	EventEffects.resolve_option("score")
	check("Calico 계승 시대 보상 2 VP +1 TRP",GameManager.state.vp==before-2 and GameManager.state.britain.treaty_points==tp+1)
	fresh()
	ministry("M-12",Enums.Side.FRANCE)
	for ss in GameManager.state.spaces.values():
		if ss.data.commodity==Enums.Commodity.COTTON: ss.controlled_by=Enums.Side.FRANCE
	tp=GameManager.state.france.treaty_points
	GameManager.score_commodity(Enums.Commodity.COTTON)
	check("Dupleix는 면화 수요에도 추가 TRP",GameManager.state.france.treaty_points==tp+2)
	fresh(Enums.Side.FRANCE,Enums.ActionType.MILITARY)
	ActionController.major_ap_remaining=0
	ActionController.grant_event_ap(2,Enums.ActionType.MILITARY,{"region":Enums.Region.NORTH_AMERICA})
	ActionController.switch_to_event(0)
	check("북미 제한 MP로 보너스 타일 뽑기",ActionController.begin_bonus_purchase())
	check("북미 MP로 유럽 전장 배치 거절",not ActionController.place_bonus_tile("central_europe_wss"))
	check("뽑은 뒤 부채 조작 거절",ActionController.take_debt_for_ap(1)==0)
	check("북미 MP로 Queen Anne 전장 배치",ActionController.place_bonus_tile("queen_annes_war") and ActionController.event_grants[0].amount==0)
	fresh(Enums.Side.BRITAIN,Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	var card=ministry("M-6",Enums.Side.BRITAIN,false)
	GameManager.state.spaces.ireland_alliance.controlled_by=Enums.Side.BRITAIN
	GameManager.state.spaces.savoy_alliance.controlled_by=Enums.Side.FRANCE
	ActionController.switch_to_minor()
	ActionController.minor_ap_remaining=10
	check("Swift 비공개 효과는 미리 적용되지 않음",not ActionController.can_shift_space(GameManager.state.spaces.savoy_alliance) and not card.is_revealed)
	ActionController.attempt_shift("savoy_alliance")
	MinistryDecisions.choose(true)
	check("Swift 공개 선택 후 실제 보조 제거",card.is_revealed and GameManager.state.spaces.savoy_alliance.controlled_by==Enums.Side.NONE)
	fresh()
	GameManager.state.spaces.ireland_alliance.controlled_by=Enums.Side.FRANCE
	GameManager.state.spaces.ireland_alliance.place_conflict_marker()
	check("분쟁은 내각 조건에서 제외",MinistryEffects._count_controlled_containing(Enums.Side.FRANCE,"ireland")==0)
	check("분쟁은 이벤트 조건에서 제외",EventEffects._count_flags_in(["ireland"],Enums.Side.FRANCE)==0)
	# CP를 소비하고 상대에게 양도 거부를 묻는 중 저장해도 동일한 선택이 복원된다.
	fresh()
	WarFlow.index=1 # Spain WSS, Gibraltar 포함
	GameManager.state.spaces.gibraltar.controlled_by=Enums.Side.BRITAIN
	GameManager.state.spaces.minorca.controlled_by=Enums.Side.BRITAIN
	WarFlow.automatic=false
	WarFlow._execute({"kind":"cp","side":Enums.Side.FRANCE,"amount":1})
	var option=WarFlow.choice.options.filter(func(o):return o.id=="gibraltar")[0]
	WarFlow._apply_choice(option)
	check("정복 대상의 소유자에게 양도 거부 질문",WarFlow.choice.kind=="refusal" and WarFlow.choice.side==Enums.Side.BRITAIN)
	var payload=SaveLoad._serialize()
	WarFlow.choice.clear()
	check("양도 거부 대기 저장 복원",SaveLoad._deserialize(JSON.parse_string(JSON.stringify(payload))) and WarFlow.choice.kind=="refusal")
	before=GameManager.state.vp
	WarFlow._apply_choice(WarFlow.choice.options[1])
	check("첫 거부 3 VP + 영토 보존",GameManager.state.vp==before+3 and GameManager.state.spaces.gibraltar.controlled_by==Enums.Side.BRITAIN)
	check("거부한 영토는 같은 전쟁 재정복 불가",not WarFlow.conquest_options(Enums.Side.FRANCE,5).any(func(o):return o.id=="gibraltar"))
	# 다음 전장으로 가지 않고 개별 선택의 정확성만 관찰한다.
	WarFlow._execute({"kind":"cp","side":Enums.Side.FRANCE,"amount":1})
	WarFlow._apply_choice(WarFlow.choice.options.filter(func(o):return o.id=="minorca")[0])
	before=GameManager.state.vp
	WarFlow._apply_choice(WarFlow.choice.options[1])
	check("두 번째 거부는 5 VP",GameManager.state.vp==before+5 and WarManager.territory_refusals[Enums.Side.BRITAIN]==2)
	fresh()
	for ss in GameManager.state.spaces.values():
		if ss.data.region==Enums.Region.INDIA: ss.controlled_by=Enums.Side.NONE
	GameManager.state.spaces.arcot_fort.controlled_by=Enums.Side.FRANCE
	GameManager.state.spaces.arcot_fort.is_fort_damaged=true
	before=GameManager.state.vp
	EventEffects.apply_event(GameData.events.filter(func(c):return c.id==38)[0],Enums.Side.FRANCE,false)
	check("East Asia Piracy는 손상된 요새도 보유 수에 포함",GameManager.state.vp==before+3)
	fresh()
	var huguenot=GameManager.state.spaces.louisiana
	huguenot.has_huguenots=true
	check("위그노 내각 퇴임 후에도 마커 사용",ActionController.flip_huguenots("louisiana") and huguenot.huguenots_exhausted)
	check("위그노 회복 전 두 번째 사용 거절",not ActionController.flip_huguenots("louisiana"))
	fresh(Enums.Side.BRITAIN,Enums.ActionType.DIPLOMATIC)
	card=ministry("M-22",Enums.Side.BRITAIN)
	GameManager.state.spaces.ireland_alliance.controlled_by=Enums.Side.BRITAIN
	MinistryEffects.activate_manual(card,Enums.Side.BRITAIN)
	check("Burke 유럽 행동은 인도에 사용 불가",not ActionController.can_spend_ap(1,GameManager.state.spaces.nizam_la,"shift"))
	ActionController.grant_event_ap(2,Enums.ActionType.DIPLOMATIC)
	ActionController.switch_to_event(1)
	check("Burke는 별도 이벤트 주요 행동에도 사용 가능",MinistryEffects.can_activate(card,Enums.Side.BRITAIN))
	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC,Enums.ActionType.MILITARY)
	GameManager.state.spaces.asiento.controlled_by=Enums.Side.FRANCE
	AdvantageManager.recompute_control()
	EventEffects._add_pending("advantage_choice",{"side":Enums.Side.FRANCE,"mode":"activate","regions":[Enums.Region.CARIBBEAN]})
	EventEffects._finalize_pending()
	check("이벤트로 비용 있는 이점 선택",EventEffects.resolve_option("slaving_contracts_adv"))
	var navy=GameManager.state.france.squadrons_in_navy_box
	check("이점의 군사 비용 출처 선택",not EventEffects.choice_options().is_empty())
	EventEffects.resolve_option(EventEffects.choice_options()[0].id)
	check("이벤트 이점: 보조 MP 소비 + 함대 건조",GameManager.state.france.squadrons_in_navy_box==navy+1 and ActionController.minor_action_used_first_expense and ActionController.minor_ap_remaining==0)
	fresh()
	card=ministry("M-1",Enums.Side.FRANCE,false)
	var th=WarManager.wars.spanish_succession.theaters[1]
	check("모든 전력 조회는 비공개 내각 제외",WarManager._calculate_bonus_strength(th,Enums.Side.FRANCE)==WarManager._calculate_bonus_strength(th,Enums.Side.FRANCE,true) and not card.is_revealed)
	# 지리·용도 제한이 붙은 AP를 변환해서 무제한 AP로 세탁할 수 없어야 한다.
	fresh(Enums.Side.FRANCE,Enums.ActionType.MILITARY)
	GameManager.state.current_turn=6
	ActionController.major_ap_remaining=0
	ActionController.grant_event_ap(2,Enums.ActionType.MILITARY,{"region":Enums.Region.NORTH_AMERICA})
	ActionController.switch_to_event(0)
	check("6턴 지역 제한 군사 AP 변환",ActionController.convert_turn6_military(Enums.ActionType.ECONOMIC))
	ActionController.switch_to_event(1)
	check("변환 뒤에도 북미 제한 보존",not ActionController.can_spend_ap(1,GameManager.state.spaces.calcutta,"shift"))
	fresh(Enums.Side.FRANCE,Enums.ActionType.MILITARY)
	GameManager.state.current_turn=6
	ActionController.major_ap_remaining=0
	ActionController.grant_event_ap(2,Enums.ActionType.MILITARY,{"kinds":["war_tile"]})
	ActionController.switch_to_event(0)
	check("전쟁 타일 전용 MP는 일반 AP로 변환 불가",not ActionController.convert_turn6_military(Enums.ActionType.ECONOMIC))
	fresh()
	GameManager.state.current_global_demand.assign([Enums.Commodity.FUR,Enums.Commodity.SPICE,Enums.Commodity.FISH,Enums.Commodity.COTTON])
	for ss in GameManager.state.spaces.values():
		if ss.data.space_type==Enums.SpaceType.MARKET: ss.controlled_by=Enums.Side.FRANCE
	check("이벤트로 수요가 4종이면 4종 독점 인정",GameManager._score_global_demand_with_winner()==Enums.Side.FRANCE)
	for ss in GameManager.state.spaces.values():
		if ss.data.commodity==Enums.Commodity.COTTON: ss.controlled_by=Enums.Side.BRITAIN
	check("4종 중 3종 승리만으로는 독점 아님",GameManager._score_global_demand_with_winner()==Enums.Side.NONE)
	GameLog.log_system("저장할 기록")
	payload=SaveLoad._serialize()
	GameLog.clear()
	check("행동 기록도 저장 복원",SaveLoad._deserialize(JSON.parse_string(JSON.stringify(payload))) and GameLog.entries[-1].text=="저장할 기록")
	GameManager.start_new_game()
	check("새 게임은 이전 행동 기록 초기화",not GameLog.entries.any(func(e):return e.text=="저장할 기록"))
	print("EDGE REGRESSION: %d passed, %d failed" % [passed,failed])
	get_tree().quit(1 if failed else 0)
