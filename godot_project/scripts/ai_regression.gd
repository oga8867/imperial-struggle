extends "res://scripts/card_regression.gd"

const Observation = preload("res://scripts/ai/observation.gd")
const Search = preload("res://scripts/ai/search.gd")
const Commands = preload("res://scripts/ai/commands.gd")
const Codec = preload("res://scripts/models/session_codec.gd")

func _ready() -> void:
	await get_tree().process_frame
	fresh()
	var st=GameManager.state
	st.britain.hand.assign(GameData.events.slice(0,5))
	st.france.hand.assign(GameData.events.slice(5,10))
	st.event_discard_pile.clear()
	GameManager._begin_hand_discard_phase()
	check("먼저 버린 카드 비공개",GameManager.complete_discard(Enums.Side.BRITAIN,st.britain.hand.slice(0,3)) and st.event_discard_pile.is_empty() and GameManager._pending_discards[Enums.Side.BRITAIN].size()==2)
	var saved=SaveLoad._serialize()
	GameManager._pending_discards.clear()
	check("비공개 버림 저장 복원",SaveLoad._deserialize(saved) and GameManager._pending_discards[Enums.Side.BRITAIN].size()==2)
	st=GameManager.state
	check("양쪽 선택 후 동시 공개",GameManager.complete_discard(Enums.Side.FRANCE,st.france.hand.slice(0,3)) and st.event_discard_pile.size()==4 and GameManager._pending_discards.is_empty())
	var old=Codec.new().decode(saved.payload)
	old.GameManager.erase("_pending_discards")
	GameManager._pending_discards={Enums.Side.BRITAIN:[GameData.events[0]]}
	check("기존 v2 저장에 이전 판의 버림이 섞이지 않음",SaveLoad._deserialize(SaveLoad.encode_snapshot(old)) and GameManager._pending_discards.is_empty())
	fresh()
	var before=SaveLoad._serialize().payload
	seed(771)
	var expected_random=randi()
	seed(771)
	var observed=Observation.build(Enums.Side.FRANCE,1234)
	check("관찰 생성은 실제 난수열 불변",randi()==expected_random)
	check("관찰 생성은 실제 모델 불변",SaveLoad._serialize().payload==before)
	var other=GameManager.state.britain
	other.hand.reverse()
	GameManager.state.event_draw_pile.reverse()
	WarManager.basic_war_tiles[Enums.Side.BRITAIN].reverse()
	check("숨긴 순서 변경은 같은 관찰",Observation.build(Enums.Side.FRANCE,1234).payload==observed.payload)
	# 상대 손패와 더미의 실제 구성을 맞바꾸어도 공개 정보가 같으면 같은 관찰이어야 한다.
	if not other.hand.is_empty() and not GameManager.state.event_draw_pile.is_empty():
		var c=other.hand[0]
		other.hand[0]=GameManager.state.event_draw_pile[0]
		GameManager.state.event_draw_pile[0]=c
	check("상대 카드 신원 변경은 같은 관찰",Observation.build(Enums.Side.FRANCE,1234).payload==observed.payload)
	var model=Codec.new().decode(observed.payload)
	check("관찰에 실행 취소·과거 로그 없음",model.ActionController._undo_stack.is_empty() and model.GameLog.entries.is_empty())
	check("관찰의 카드 수 보존",model.GameManager.state.britain.hand.size()==other.hand.size() and model.GameManager.state.event_draw_pile.size()==GameManager.state.event_draw_pile.size())
	var started=Time.get_ticks_msec()
	var result=Search.new().run({"side":Enums.Side.FRANCE,"snapshots":[observed],"budget_ms":2500,"iterations":10})
	print("AI SEARCH ",JSON.stringify(result))
	check("시간 제한 탐색 결과",not result.plan.is_empty() and result.iterations>0 and Time.get_ticks_msec()-started<3300)
	SaveLoad._deserialize(observed)
	var legal=true
	for command in result.plan:
		if not Commands.apply(command,Enums.Side.FRANCE): legal=false; break
	check("탐색 계획은 실제 규칙 경로에서 실행 가능",legal)
	_test_hidden_war_and_ministries()
	_test_action_boundaries()
	_test_immediate_scoring()
	fresh()
	GameManager.state.current_turn=3
	GameManager._deck_phase()
	var empire=Codec.new().decode(Observation.build(Enums.Side.FRANCE,145).payload).GameManager.state
	check("제국 시대 관찰은 이전 시대 카드와 전체 덱 수 유지",empire.event_draw_pile.size()==GameManager.state.event_draw_pile.size() and empire.event_draw_pile.any(func(c):return c.era==Enums.Era.SUCCESSION))
	print("AI REGRESSION: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed==0 else 1)

func _test_hidden_war_and_ministries() -> void:
	fresh()
	var own=Enums.Side.FRANCE
	var enemy=Enums.Side.BRITAIN
	var cards=GameData.get_ministries_for_era(enemy,GameManager.state.current_era)
	GameManager.state.britain.ministry_cards.assign([cards[0]])
	cards[0].is_in_play=true
	var observed=Observation.build(own,8841).payload
	cards[0].is_in_play=false
	cards[1].is_in_play=true
	GameManager.state.britain.ministry_cards.assign([cards[1]])
	check("상대 미공개 내각 신원은 관찰 불변",Observation.build(own,8841).payload==observed)
	var id=WarManager.basic_tile_in_theater.keys()[0]
	var tile=WarManager.basic_tile_in_theater[id][enemy]
	WarManager.basic_tile_in_theater[id][enemy]=WarManager.basic_war_tiles[enemy][0]
	WarManager.basic_war_tiles[enemy][0]=tile
	check("상대 기본 전쟁 타일 신원은 관찰 불변",Observation.build(own,8841).payload==observed)
	GameManager.state.investment_draw_pile.reverse()
	WarManager.basic_war_tiles[own].reverse()
	WarManager.bonus_tile_pool[own].reverse()
	check("내 풀과 투자 더미의 숨은 순서도 관찰 불변",Observation.build(own,8841).payload==observed)
	WarManager.bonus_war_tiles_in_theater[id][enemy].append(WarManager.bonus_tile_pool[enemy].pop_back())
	observed=Observation.build(own,8841).payload
	tile=WarManager.bonus_war_tiles_in_theater[id][enemy][0]
	WarManager.bonus_war_tiles_in_theater[id][enemy][0]=WarManager.bonus_tile_pool[enemy][0]
	WarManager.bonus_tile_pool[enemy][0]=tile
	check("상대 보너스 전쟁 타일 신원은 관찰 불변",Observation.build(own,8841).payload==observed)
	cards[1].is_revealed=true
	check("공개한 내각은 관찰에 반영",Observation.build(own,8841).payload!=observed)

func _test_action_boundaries() -> void:
	fresh()
	var card=ministry("M-3",Enums.Side.FRANCE,false)
	check("수동 능력이 없는 내각 활성화 금지",not MinistryEffects.can_activate(card,Enums.Side.FRANCE,0))
	card=ministry("M-8",Enums.Side.FRANCE,false)
	check("존재하지 않는 능력 번호 금지",not MinistryEffects.can_activate(card,Enums.Side.FRANCE,1))
	var before=SaveLoad._serialize().payload
	check("오래된·잘못된 명령 거부",not Commands.apply({"kind":"shift","id":"missing-space"},Enums.Side.FRANCE) and SaveLoad._serialize().payload==before)
	ActionController.skip_event()
	EventEffects._add_pending("place_conflict_marker_choice",{"side":Enums.Side.FRANCE,"region":Enums.Region.NORTH_AMERICA,"kind":"conflict"})
	EventEffects.current_side=Enums.Side.NONE
	check("카드 밖에서 생긴 선택의 담당 진영",Commands.chooser()==Enums.Side.FRANCE and not Commands.options(Enums.Side.FRANCE).is_empty())
	EventEffects.pending_choices.clear()
	ActionController.current_tile=InvestmentTile.create(99,Enums.ActionType.DIPLOMATIC,4,Enums.ActionType.ECONOMIC,false,false)
	GameManager.state.event_draw_pile.assign(GameData.events.slice(0,1))
	check("전략 후보에 외교 카드 뽑기 포함",Commands.options(Enums.Side.FRANCE).any(func(c):return c.kind=="draw"))
	check("확률 결과에서 실행 계획 중단",Commands.boundary({"kind":"draw"}) and Commands.boundary({"kind":"bonus"}) and Commands.boundary({"kind":"event"}))
	EventEffects.pending_choices.clear()
	ActionController.reset_session()
	var tile_command=Commands.options(Enums.Side.FRANCE).filter(func(c):return c.kind=="tile")[0]
	var from_worker=JSON.parse_string(JSON.stringify(tile_command))
	check("작업 파일의 숫자 타입 왕복 후 투자 명령 실행",Commands.apply(from_worker,Enums.Side.FRANCE) and ActionController.current_tile.id==int(tile_command.id))

func _test_immediate_scoring() -> void:
	fresh()
	var side=Enums.Side.FRANCE
	var st=GameManager.state
	for ss in st.spaces.values(): ss.controlled_by=Enums.Side.NONE; ss.has_conflict_marker=false
	st.spaces.st_domingue.controlled_by=side
	st.france.hand.clear()
	st.france.ministry_cards.clear()
	st.britain.ministry_cards.clear()
	st.vp=27
	st.france.action_rounds_taken=3
	st.britain.action_rounds_taken=4
	st.current_action_round=4
	st.current_global_demand.assign([Enums.Commodity.FUR,Enums.Commodity.SPICE,Enums.Commodity.FISH])
	AwardManager.turn_awards={"europe":{"vp":0,"tp":0,"margin_required":1},"north_america":{"vp":0,"tp":0,"margin_required":1},"caribbean":{"vp":3,"tp":0,"margin_required":2},"india":{"vp":0,"tp":0,"margin_required":1}}
	AdvantageManager.recompute_control()
	ActionController.current_tile.has_military_upgrade=false
	var observation=Observation.build(side,111)
	var result=Search.new().run({"side":side,"snapshots":[observation],"budget_ms":1300})
	check("즉시 승리할 지역 보상을 위한 계획 발견",not result.plan.is_empty() and result.plan[0].kind=="shift")
	SaveLoad._deserialize(observation)
	if not result.plan.is_empty(): Commands.apply(result.plan[0],side)
	ActionController.end_action_round()
	check("선택한 시장의 실제 득점으로 승리",GameManager.state.winner==side)
	fresh()
	st=GameManager.state
	for ss in st.spaces.values(): ss.controlled_by=Enums.Side.NONE; ss.has_conflict_marker=false
	st.spaces.ireland_alliance.controlled_by=side
	AwardManager.turn_awards.europe={"vp":0,"tp":0,"margin_required":1}
	st.vp=29
	st.france.action_rounds_taken=3
	st.britain.action_rounds_taken=4
	st.current_action_round=4
	var card=ministry("M-3",side,false)
	ActionController.major_ap_remaining=0
	ActionController.minor_ap_remaining=0
	ActionController.current_tile.has_military_upgrade=false
	st.france.current_debt=st.france.debt_limit
	st.france.treaty_points=0
	st.france.hand.clear()
	AdvantageManager.recompute_control()
	observation=Observation.build(side,121)
	result=Search.new().run({"side":side,"snapshots":[observation],"budget_ms":1300})
	check("득점 전에 필요한 내각 공개 계획",not result.plan.is_empty() and result.plan[0].kind=="reveal" and result.plan[0].id==card.id)
