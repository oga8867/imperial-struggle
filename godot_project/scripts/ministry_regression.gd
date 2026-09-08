extends "res://scripts/card_regression.gd"

# 사용자 피드백 회귀: 비공개 정보의 확인, 공개 선택, 효과 적용, 공개 가능 시점은
# 서로 다른 동작이다. 각 경로를 수치 및 저장 상태로 검사한다.
func _ready() -> void:
	await get_tree().process_frame
	fresh(Enums.Side.BRITAIN,Enums.ActionType.DIPLOMATIC)
	var card=ministry("M-6",Enums.Side.BRITAIN,false)
	var ss=GameManager.state.spaces.ireland_alliance
	ss.controlled_by=Enums.Side.NONE
	var cost=ActionController.calculate_shift_cost(ss,ss.data.region)
	check("내각 소유와 효과 활성은 별개",not MinistryEffects._has(Enums.Side.BRITAIN,"M-6"))
	check("자기 행동 라운드 공개 가능",MinistryDecisions.can_reveal(card,Enums.Side.BRITAIN))
	ActionController.attempt_shift(ss.data.id)
	check("관련 행동 직전 공개 질문",MinistryDecisions.has_pending() and not card.is_revealed and ss.controlled_by==Enums.Side.NONE)
	check("공개 질문 중 AP 지출과 라운드 종료 차단",not ActionController.can_spend_ap(1) and not ActionController.can_end_action_round())
	var ap=ActionController.major_ap_remaining
	MinistryDecisions.choose(false)
	check("비공개 유지하면 할인 없이 원래 행동 실행",not card.is_revealed and ss.controlled_by==Enums.Side.BRITAIN and ActionController.major_ap_remaining==ap-cost)
	ss.controlled_by=Enums.Side.NONE
	ActionController.major_ap_remaining=cost-1
	ActionController.attempt_shift(ss.data.id)
	check("다음 관련 행동에는 다시 선택 가능",MinistryDecisions.has_pending())
	MinistryDecisions.choose(false)
	check("일반 비용 부족하면 비공개 유지 후 행동 거절",ss.controlled_by==Enums.Side.NONE and ActionController.major_ap_remaining==cost-1)
	ActionController.attempt_shift(ss.data.id)
	var payload=SaveLoad._serialize()
	MinistryDecisions.pending.clear()
	check("공개 질문과 원래 명령 저장 복원",SaveLoad._deserialize(JSON.parse_string(JSON.stringify(payload))) and MinistryDecisions.pending.command.id==ss.data.id)
	MinistryDecisions.choose(true)
	card=MinistryEffects._card(Enums.Side.BRITAIN,"M-6")
	ss=GameManager.state.spaces.ireland_alliance
	check("공개 선택하면 할인 적용 후 행동 재개",card.is_revealed and ss.controlled_by==Enums.Side.BRITAIN and ActionController.major_ap_remaining==0)
	check("공개 정보는 실행 취소로 다시 숨기지 않음",not ActionController.can_undo() or card.is_revealed)
	if ActionController.can_undo(): ActionController.undo_last()
	check("행동 취소 후에도 공개 내각 유지",MinistryEffects._card(Enums.Side.BRITAIN,"M-6").is_revealed)
	fresh()
	card=ministry("M-3",Enums.Side.FRANCE,false)
	var before=GameManager.state.vp
	GameManager.state.current_turn_phase=Enums.TurnPhase.SCORING_PHASE
	MinistryEffects.apply_award_bonus(Enums.Region.EUROPE,Enums.Side.FRANCE)
	check("득점 시 비공개 내각 보너스 없음",GameManager.state.vp==before and not card.is_revealed)
	check("득점 중 뒤늦게 공개 거절",not card.reveal())
	GameManager.state.current_turn_phase=Enums.TurnPhase.ACTION_PHASE
	check("득점 전에 자기 라운드에서 미리 공개",card.reveal())
	GameManager.state.current_turn_phase=Enums.TurnPhase.SCORING_PHASE
	MinistryEffects.apply_award_bonus(Enums.Region.EUROPE,Enums.Side.FRANCE)
	check("미리 공개한 내각만 득점",GameManager.state.vp==before+1)
	fresh()
	card=ministry("M-1",Enums.Side.FRANCE,false)
	var th=WarManager.wars.spanish_succession.theaters[1]
	var hidden=WarManager._calculate_bonus_strength(th,Enums.Side.FRANCE)
	GameManager.state.current_phase=Enums.GamePhase.WAR
	check("전쟁 중 새 내각 공개 거절",not card.reveal())
	check("전쟁 계산은 비공개 키워드를 사용하지 않음",WarManager._calculate_bonus_strength(th,Enums.Side.FRANCE)==hidden and not card.is_revealed)
	GameManager.state.current_phase=Enums.GamePhase.PEACE_TURN
	card.reveal()
	GameManager.state.current_phase=Enums.GamePhase.WAR
	check("미리 공개한 전쟁 키워드 전력 +1",WarManager._calculate_bonus_strength(th,Enums.Side.FRANCE)==hidden+1)
	fresh(Enums.Side.BRITAIN)
	card=ministry("M-19",Enums.Side.BRITAIN,false)
	GameManager.state.phasing_player=Enums.Side.FRANCE
	var trp=GameManager.state.britain.treaty_points
	MinistryEffects.on_advantage_exhausted(Enums.Side.FRANCE,Enums.Region.INDIA)
	check("상대 라운드의 비공개 와트는 공개·발동 안 함",not card.is_revealed and GameManager.state.britain.treaty_points==trp and not MinistryDecisions.has_pending())
	check("상대 라운드 직접 공개 거절",not card.reveal())
	fresh(Enums.Side.BRITAIN)
	card=ministry("M-5",Enums.Side.BRITAIN,false)
	ActionController.reset_session()
	var hand_size=GameManager.state.britain.hand.size()
	check("타일 선택 전 공개·Walpole 사용 가능",MinistryDecisions.can_reveal(card,Enums.Side.BRITAIN) and MinistryEffects.can_activate(card,Enums.Side.BRITAIN))
	MinistryEffects.activate_manual(card,Enums.Side.BRITAIN)
	MinistryDecisions.choose(false)
	check("능력 공개 거절은 카드 뽑기·소진 없음",not card.is_revealed and not card.is_ability_exhausted(0) and GameManager.state.britain.hand.size()==hand_size)
	MinistryEffects.activate_manual(card,Enums.Side.BRITAIN)
	MinistryDecisions.choose(true)
	check("공개 승인 뒤 타일 선택 전에 카드 뽑기",card.is_revealed and EventEffects.has_pending() and GameManager.state.britain.hand.size()==hand_size+1)
	resolve_all()
	ActionController.begin_action_round(Enums.Side.BRITAIN,InvestmentTile.create(91,Enums.ActionType.ECONOMIC,4,Enums.ActionType.MILITARY,true,true))
	check("타일 전 능력 사용은 패스 보상으로 초기화되지 않음",ActionController.action_started)
	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	card=ministry("M-1",Enums.Side.FRANCE,false)
	var event=GameData.events.filter(func(c):return c.id==13)[0]
	GameManager.state.france.hand.assign([event])
	ActionController.state=ActionController.ActionState.AWAITING_EVENT
	check("보너스 가능 여부 조회는 내각 비공개 유지",EventEffects.bonus_condition_met(event,Enums.Side.FRANCE,false) and not card.is_revealed)
	ActionController.play_event(event,true)
	check("이벤트 보너스 전에 공개 질문",MinistryDecisions.has_pending() and event in GameManager.state.france.hand)
	MinistryDecisions.choose(false)
	check("보너스 공개 거절은 기본 이벤트만 실행",not card.is_revealed and ActionController.event_played and not EventEffects.current_with_bonus)
	resolve_all()
	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	card=ministry("M-1",Enums.Side.FRANCE,false)
	GameManager.state.france.hand.assign([event])
	ActionController.state=ActionController.ActionState.AWAITING_EVENT
	ActionController.play_event(event,true)
	MinistryDecisions.choose(true)
	check("이벤트 공개 승인 뒤 보너스 적용",card.is_revealed and EventEffects.current_with_bonus)
	resolve_all()
	fresh(Enums.Side.FRANCE)
	card=ministry("M-2",Enums.Side.FRANCE,false)
	GameManager.state.france.current_debt=3
	GameManager.state.current_turn_phase=Enums.TurnPhase.RESOLVE_REMAINING_POWERS
	MinistryEffects.apply_end_of_peace_turn()
	check("턴 끝 비공개 John Law 자동 공개·혜택 없음",not card.is_revealed and GameManager.state.france.current_debt==3)
	fresh(Enums.Side.BRITAIN)
	card=ministry("M-17",Enums.Side.BRITAIN,false)
	ap=ActionController.major_ap_remaining
	ActionController.take_debt_for_ap(1)
	check("Merchant Banks 부채 행동 전에 공개 선택",MinistryDecisions.has_pending() and not card.is_revealed)
	MinistryDecisions.choose(false)
	check("은행 비공개 시 일반 부채로 AP 구매",GameManager.state.britain.current_debt==1 and ActionController.major_ap_remaining==ap+1 and not card.is_revealed)
	ActionController.take_debt_for_ap(1)
	MinistryDecisions.choose(true)
	check("은행 공개 승인 뒤 면제 AP 제공",card.is_revealed and GameManager.state.britain.current_debt==1 and ActionController.ap_for_current()==ap+2)
	fresh()
	card=ministry("M-13",Enums.Side.FRANCE,false)
	trp=GameManager.state.france.treaty_points
	MinistryEffects.on_advantage_exhausted(Enums.Side.FRANCE,Enums.Region.EUROPE)
	check("퐁파두르 효과 시점의 공개 질문",MinistryDecisions.has_pending() and GameManager.state.france.treaty_points==trp)
	MinistryDecisions.choose(false)
	check("퐁파두르 비공개 유지 시 TRP·소진 없음",not card.is_revealed and not card.is_ability_exhausted(0) and GameManager.state.france.treaty_points==trp)
	MinistryEffects.on_advantage_exhausted(Enums.Side.FRANCE,Enums.Region.EUROPE)
	check("처음의 공개 기회를 거절하면 같은 라운드 재발동 없음",not MinistryDecisions.has_pending() and GameManager.state.france.treaty_points==trp)
	MinistryEffects.prepare_round()
	MinistryEffects.on_advantage_exhausted(Enums.Side.FRANCE,Enums.Region.EUROPE)
	MinistryDecisions.choose(true)
	check("퐁파두르 승인 시 1회 지급",card.is_revealed and card.is_ability_exhausted(0) and GameManager.state.france.treaty_points==trp+1)
	MinistryEffects.on_advantage_exhausted(Enums.Side.FRANCE,Enums.Region.EUROPE)
	check("공개 재개로 이점 보상 중복 지급 없음",GameManager.state.france.treaty_points==trp+1)
	fresh(Enums.Side.BRITAIN)
	card=ministry("M-19",Enums.Side.BRITAIN,false)
	GameManager.state.britain.current_debt=GameManager.state.britain.debt_limit
	before=GameManager.state.vp
	GameManager.state.britain.incur_debt(1)
	check("자기 라운드 한도 초과 강제 부채는 Watt 공개 질문",MinistryDecisions.has_pending() and GameManager.state.vp==before)
	MinistryDecisions.choose(false)
	check("Watt 비공개 유지 시 상대 VP",GameManager.state.vp==before+1 and not card.is_revealed)
	print("MINISTRY REGRESSION: %d passed, %d failed" % [passed,failed])
	get_tree().quit(1 if failed else 0)
