extends Node

var passed = 0
var failed = 0

func check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)

func fresh() -> void:
	AIController.disable()
	GameManager.start_new_game()
	while not GameManager._ministry_pending_sides.is_empty():
		GameManager.complete_ministry_selection(GameManager._ministry_pending_sides[0])

func begin(major: int, minor: int, points: int = 10) -> void:
	ActionController.begin_action_round(Enums.Side.FRANCE, InvestmentTile.create(99, major, points, minor, false, false))
	GameManager.state.phasing_player = Enums.Side.FRANCE

func _ready() -> void:
	await get_tree().process_frame
	fresh()
	check("투자 타일은 실제 24장", GameData.investment_tile_pool.size() == 24)
	var first_ids = GameManager.state.available_investment_tiles.map(func(t): return t.id)
	GameManager._deal_cards_phase()
	check("다음 턴 투자 타일은 사용 더미와 겹치지 않음", GameManager.state.available_investment_tiles.all(func(t): return t.id not in first_ids))
	check("수요·지역 점수에 쓰는 지역 보상 총 8개", AwardManager.all_awards.size() == 8)
	var awards = AwardManager.turn_awards.values().map(func(a): return a.id)
	AwardManager.assign_awards_for_turn(false)
	check("시대 두 번째 턴은 다른 지역 보상 4개", AwardManager.turn_awards.values().all(func(a): return a.id not in awards))
	check("WSS 제4전장은 재커바이트 반란", WarManager.wars.spanish_succession.theaters[3].id == "jacobite_rebellion_wss")
	check("AWI 전장은 3개", WarManager.wars.american_independence.theaters.size() == 3)
	check("스페인 최대 보상은 격차 4", WarManager.is_maximum_spoils("spain_wss", Enums.Side.FRANCE, 4) and not WarManager.is_maximum_spoils("spain_wss", Enums.Side.FRANCE, 3))
	check("WSS 보너스 전력 총합 20", WarManager.bonus_tile_pool[Enums.Side.BRITAIN].reduce(func(total,t): return total+t.strength,0) == 20)
	var before = GameManager.state.vp
	GameManager.state.france.current_debt = 6
	GameManager.state.france.incur_debt(2)
	check("강제 부채 초과는 상대 VP", GameManager.state.vp == before - 2 and GameManager.state.france.current_debt == 6)
	check("음수 부채 차입 거절", GameManager.state.france.take_debt(-2) == 0 and GameManager.state.france.current_debt == 6)
	begin(Enums.ActionType.DIPLOMATIC, Enums.ActionType.MILITARY)
	ActionController.switch_to_minor()
	check("보조 행동 첫 지출 가능", ActionController.spend_ap(1))
	check("보조 행동 두 번째 지출 거절", not ActionController.spend_ap(1))
	begin(Enums.ActionType.MILITARY, Enums.ActionType.DIPLOMATIC)
	var naval = ""
	var next_naval = ""
	for ss in GameManager.state.spaces.values():
		if ss.data.space_type == Enums.SpaceType.NAVAL:
			if naval == "": naval = ss.data.id
			elif next_naval == "": next_naval = ss.data.id
	check("해군 상자에서 함대 배치", ActionController.deploy_squadron_to(naval))
	check("동일 함대 같은 라운드 재배치 거절", not ActionController.deploy_squadron_to(next_naval, naval))
	begin(Enums.ActionType.MILITARY, Enums.ActionType.DIPLOMATIC)
	check("다음 라운드 함대 이동 가능", ActionController.deploy_squadron_to(next_naval, naval))
	check("함대 이동 후 출발지 비움", GameManager.state.spaces[naval].controlled_by == Enums.Side.NONE and GameManager.state.france.squadrons_on_map == 1)
	before = ActionController.major_ap_remaining
	check("출발 함대 없으면 AP 차감 없음", not ActionController.deploy_squadron_to(naval, "missing") and ActionController.major_ap_remaining == before)
	var no_bonus: EventCard = GameData.events.filter(func(c): return c.id == 12)[0]
	check("보너스 부채 조건 불충족", not EventEffects.bonus_condition_met(no_bonus, Enums.Side.FRANCE))
	GameManager.state.france.ministry_cards.assign([GameData.ministries[0]])
	# 저장의 공유 참조를 검사하기 위한 공개 상태 fixture. 공개 시점은 별도 검사한다.
	GameManager.state.france.ministry_cards[0].is_revealed=true
	EventEffects.pending_choices = [{"type":"place_conflict_marker_choice","params":{"count":1}}]
	var payload = SaveLoad._serialize()
	var expected_ap = ActionController.major_ap_remaining
	var expected_tile = WarManager.basic_tile_in_theater["central_europe_wss"][Enums.Side.FRANCE].strength
	GameManager.state.vp = 999
	ActionController.major_ap_remaining = -9
	EventEffects.pending_choices.clear()
	check("저장 그래프 JSON 왕복", SaveLoad._deserialize(JSON.parse_string(JSON.stringify(payload))))
	check("행동점수와 전쟁 타일 복원", ActionController.major_ap_remaining == expected_ap and WarManager.basic_tile_in_theater["central_europe_wss"][Enums.Side.FRANCE].strength == expected_tile)
	check("이벤트 선택 대기 복원", EventEffects.pending_choices.size() == 1)
	check("공유 내각 카드 참조 복원", GameManager.state.france.ministry_cards[0] in GameData.ministries and GameManager.state.france.ministry_cards[0].is_revealed)
	check("실제 파일 저장", SaveLoad.save_game("regression"))
	check("실제 파일 읽기", SaveLoad.load_game("regression"))
	fresh()
	check("새 게임은 행동·이벤트 초기화", ActionController.state == ActionController.ActionState.IDLE and EventEffects.pending_choices.is_empty())
	_advanced_cases()
	fresh()
	GameManager.state.current_turn = 5
	GameManager._advance_to_next_turn()
	check("5턴 뒤 미국 독립전쟁 필수 진행", GameManager.state.current_phase == Enums.GamePhase.WAR and WarManager.current_war_id == "american_independence")
	print("RULES REGRESSION: %d passed, %d failed" % [passed,failed])
	get_tree().quit(1 if failed else 0)

func _advanced_cases() -> void:
	begin(Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	ActionController.spend_ap(1)
	ActionController.switch_to_minor()
	ActionController.switch_to_major()
	check("지출 후 끝낸 주요 행동으로 복귀 거절",ActionController.state == ActionController.ActionState.SPENDING_MINOR)
	begin(Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	ActionController.grant_event_ap(3,Enums.ActionType.MILITARY)
	ActionController.switch_to_event(0)
	check("투자 타일에 없는 이벤트 행동 종류 사용",ActionController.current_action_type()==Enums.ActionType.MILITARY and ActionController.ap_for_current()==3)
	check("종류가 다른 주요 행동에 이벤트 합산 거절",not ActionController.assign_event_grant(0,"major"))
	begin(Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	ActionController.grant_event_ap(2,Enums.ActionType.ECONOMIC,{"region":Enums.Region.INDIA,"unflag":true})
	ActionController.switch_to_event(0)
	var india = GameManager.state.spaces.midnapore
	var north = GameManager.state.spaces.mass_bay
	check("지역 제한 이벤트 AP: 인도 가능",ActionController.can_spend_ap(2,india,"shift"))
	check("지역 제한 이벤트 AP: 북미 거절",not ActionController.can_spend_ap(1,north,"shift"))
	india.controlled_by=Enums.Side.NONE
	check("깃발 제거용 AP로 빈 공간 차지 거절",not ActionController.can_spend_ap(1,india,"shift"))
	ActionController.take_debt_for_ap(1)
	check("부채로 늘린 이벤트 AP도 제한 유지",ActionController.ap_for_current()==3 and not ActionController.can_spend_ap(1,north,"shift"))
	begin(Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	ActionController.grant_event_ap(2,Enums.ActionType.DIPLOMATIC)
	ActionController.assign_event_grant(0,"minor")
	ActionController.switch_to_minor()
	check("이벤트를 보조 행동에 합산",ActionController.ap_for_current()==4 and ActionController.spend_ap(3))
	check("합산해도 보조 지출 횟수는 하나",not ActionController.spend_ap(1))
	fresh()
	var adv = AdvantageManager.advantages.wheat_adv
	check("원본 지도대로 밀 이점은 체서피크",adv.connected_space_ids == ["chesapeake"] and adv.controlled_by == Enums.Side.BRITAIN)
	check("Hudson Bay에는 York Factory 실선만 존재",GameData.spaces.hudson_bay.connections == ["york_factory"])
	check("인도 내각·정치 공간은 시장 연결의 앵커 아님",GameData.spaces.nizam_la.connections.is_empty())
	check("맵 연결은 양방향",GameData.spaces.values().all(func(s): return s.connections.all(func(c): return s.id in GameData.spaces[c].connections)))
	check("기본 시대에 프러시아 추가 공간 잠금",GameData.spaces.prussia_alliance_b.available_from_era==Enums.Era.EMPIRE)
	begin(Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	var market = GameManager.state.spaces.antigua
	market.controlled_by = Enums.Side.BRITAIN
	market.place_conflict_marker()
	GameManager.state.spaces.antilles_channel_naval.controlled_by=Enums.Side.BRITAIN
	AdvantageManager.discounts=[{"side":Enums.Side.FRANCE,"type":Enums.ActionType.ECONOMIC,"region":Enums.Region.CARIBBEAN,"reduction":1}]
	check("규칙 §8 Rum: 분쟁·보호 시장 할인 후 1 EP",ActionController.calculate_shift_cost(market,Enums.Region.CARIBBEAN)==1)
	EventEffects.pending_choices=[{"type":"place_conflict_marker_in_country","params":{"side":Enums.Side.FRANCE,"country":"spain"}}]
	check("스페인 대상 효과에 러시아 클릭 거절",not EventEffects.resolve_choice(0,"russia_alliance"))
	EventEffects.skip_choice(0)
	check("필수 카드 효과 임의 생략 거절",EventEffects.has_pending())
	EventEffects.pending_choices.clear()
	fresh()
	ActionController.begin_action_round(Enums.Side.FRANCE,InvestmentTile.create(90,Enums.ActionType.MILITARY,5,Enums.ActionType.ECONOMIC,false,true))
	var theater_id = WarManager.get_upcoming_theaters()[0].id
	check("기본 전쟁 타일 업그레이드 시작",ActionController.begin_upgrade(theater_id))
	check("타일 선택 대기 중 라운드 종료 거절",not ActionController.can_end_action_round())
	var saved = SaveLoad._serialize()
	var strength = ActionController.upgrade_drawn.strength
	ActionController.upgrade_drawn = null
	check("업그레이드 선택 대기 저장 복원",SaveLoad._deserialize(saved) and ActionController.upgrade_drawn.strength == strength)
	ActionController.finish_upgrade(false,false)
	check("한 타일의 업그레이드 재사용 거절",not ActionController.begin_upgrade(theater_id))
	begin(Enums.ActionType.MILITARY,Enums.ActionType.ECONOMIC)
	check("보너스 타일: 전장 선택 전에 무작위 뽑기",ActionController.begin_bonus_purchase() and ActionController.bonus_drawn!=null)
	check("배치 전 추가 구입 거절",not ActionController.begin_bonus_purchase())
	check("보너스 타일 배치 후 대기 해제",ActionController.place_bonus_tile(theater_id) and ActionController.bonus_drawn==null)
	GameManager.state.current_turn=6
	begin(Enums.ActionType.MILITARY,Enums.ActionType.ECONOMIC)
	check("6턴 군사 AP 경제 변환",ActionController.convert_turn6_military(Enums.ActionType.ECONOMIC))
	check("6턴 경제와 외교 동시 변환 거절",not ActionController.convert_turn6_military(Enums.ActionType.DIPLOMATIC))
	ActionController.begin_action_round(Enums.Side.FRANCE,InvestmentTile.create(90,Enums.ActionType.MILITARY,5,Enums.ActionType.ECONOMIC,false,true))
	var trp=GameManager.state.france.treaty_points
	check("6턴 업그레이드는 조약점수 1",ActionController.begin_upgrade() and GameManager.state.france.treaty_points==trp+1)
