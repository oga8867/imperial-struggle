extends "res://scripts/card_regression.gd"

# §5.5.3의 결과뿐 아니라 실패 시 점수·더미 보존, 보조 행동 제한,
# 비공개 정보, 저장 후 재개를 검증한다. UI와 AI가 호출하는 공개 메서드를 사용한다.
func _ready() -> void:
	await get_tree().process_frame
	var ac = ActionController
	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	var s = GameManager.state
	var top = s.event_draw_pile.back()
	var deck_size = s.event_draw_pile.size()
	check("외교 카드 뽑기 가능",ac.can_draw_event())
	check("외교 3점 차감하고 더미 맨 위 1장 획득",ac.draw_event_card() and ac.major_ap_remaining==1 and s.france.hand.back()==top and s.event_draw_pile.size()==deck_size-1)
	check("외교 뽑기로 손패 4장을 즉시 버리지 않음",s.france.hand.size()==4)
	check("점수가 부족하면 추가 뽑기 거절",not ac.draw_event_card() and ac.major_ap_remaining==1 and s.france.hand.size()==4)
	check("뽑은 카드를 같은 행동 라운드 이벤트로 사용 불가",not ac.play_event(top))
	check("공개 기록에 뽑은 카드 이름을 노출하지 않음",not GameLog.entries.back().text.contains(top.disp_title()))

	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	ac.take_debt_for_ap(1)
	check("뽑기 전 채무 보충은 실행 취소 가능",ac.can_undo())
	ac.draw_event_card()
	check("새 카드를 보면 이전 실행 취소까지 차단",not ac.can_undo())
	ac.major_ap_remaining=6
	var hand_size=GameManager.state.france.hand.size()
	check("주요 외교 6점으로 두 장 구입 가능",ac.draw_event_card() and ac.draw_event_card() and GameManager.state.france.hand.size()==hand_size+2 and ac.major_ap_remaining==0)

	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	s=GameManager.state
	s.event_discard_pile.append(s.event_draw_pile.pop_back())
	s.event_draw_pile.clear()
	check("빈 더미는 점수 차감 없이 거절",not ac.draw_event_card() and ac.major_ap_remaining==4)
	check("외교 뽑기는 버림 더미를 재혼합하지 않음",s.event_discard_pile.size()==1 and s.event_draw_pile.is_empty())
	fresh()
	check("경제 점수로 이벤트 카드 구매 거절",not ac.draw_event_card())
	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	GameManager.state.phasing_player=Enums.Side.BRITAIN
	check("상대 차례에는 구매 거절",not ac.draw_event_card())
	GameManager.state.phasing_player=Enums.Side.FRANCE
	MinistryDecisions.pending={"command":{"kind":"reveal"}}
	check("내각 공개 선택 중 구매 거절",not ac.draw_event_card())
	MinistryDecisions.pending.clear()
	ac.state=ac.ActionState.AWAITING_EVENT
	check("이벤트 사용 여부 결정 전에 구매 거절",not ac.draw_event_card())
	ac.state=ac.ActionState.SPENDING_MAJOR
	GameManager.state.current_turn_phase=Enums.TurnPhase.SCORING_PHASE
	check("득점 단계에 남아 있는 외교 점수 사용 불가",not ac.draw_event_card())

	fresh(Enums.Side.FRANCE,Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	ac.switch_to_minor()
	check("보조 외교 기본 2점은 구매 비용 부족",not ac.can_draw_event())
	GameManager.state.france.treaty_points=1
	ac.spend_treaty_points_for_ap(1)
	check("조약점수로 보충한 보조 외교 3점 구매",ac.draw_event_card() and ac.minor_action_used_first_expense and GameManager.state.france.treaty_points==0)
	ac.minor_ap_remaining=3
	check("보조 행동은 점수가 남아도 두 번째 지출 불가",not ac.draw_event_card() and ac.remaining_for_pool("minor")==0)

	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	ac.major_ap_remaining=2
	ac.grant_event_ap(3,Enums.ActionType.DIPLOMATIC,{"region":Enums.Region.EUROPE})
	ac.assign_event_grant(0,"major")
	check("지역 제한 합산 점수로 일반 카드 구입 불가",ac.remaining_for_pool("major")==5 and not ac.can_draw_event())
	ac.take_debt_for_ap(1)
	check("일반 외교만 지불하고 제한 점수는 보존",ac.draw_event_card() and ac.major_ap_remaining==0 and ac.event_grants[0].amount==3)
	ac.switch_to_minor()
	check("뽑기 후 다른 행동으로 전환하면 이전 행동 종료",not ac.can_switch_pool("major") and ac.remaining_for_pool("major")==0)
	fresh()
	ac.grant_event_ap(3,Enums.ActionType.DIPLOMATIC)
	ac.switch_to_event(0)
	check("사용처 제한 없는 이벤트 외교로 구매 가능",ac.draw_event_card() and ac.event_grants[0].amount==0)
	for restriction in [{"non_prestige":true},{"countries":["spain"]},{"unflag":true},{"kinds":["shift"]}]:
		fresh()
		ac.grant_event_ap(3,Enums.ActionType.DIPLOMATIC,restriction)
		ac.switch_to_event(0)
		check("제한된 이벤트 외교로 카드 구입 거절 "+str(restriction),not ac.draw_event_card())

	fresh(Enums.Side.FRANCE,Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	ac.switch_to_minor()
	ac.take_debt_for_ap(1)
	ac.draw_event_card()
	var ids=GameManager.state.france.hand.map(func(c): return c.id)
	var deck_ids=GameManager.state.event_draw_pile.map(func(c): return c.id)
	var payload=SaveLoad._serialize()
	check("뽑기 직후 상태 저장 복원",SaveLoad._deserialize(JSON.parse_string(JSON.stringify(payload))))
	check("저장 후 손패·더미 순서 보존",GameManager.state.france.hand.map(func(c): return c.id)==ids and GameManager.state.event_draw_pile.map(func(c): return c.id)==deck_ids)
	check("저장 후 보조 행동 재사용 및 재추첨 차단",ac.minor_action_used_first_expense and not ac.can_draw_event() and not ac.can_undo())

	fresh(Enums.Side.FRANCE,Enums.ActionType.DIPLOMATIC)
	s=GameManager.state
	s.current_era=Enums.Era.REVOLUTION
	var old_card=GameData.events.filter(func(c): return c.era==Enums.Era.SUCCESSION)[0]
	var new_card=GameData.events.filter(func(c): return c.era==Enums.Era.REVOLUTION)[0]
	s.event_draw_pile.assign([new_card,old_card])
	check("혁명 시대 왕위계승 카드 제거 후 대체 카드 획득",ac.draw_event_card() and s.france.hand.back()==new_card and old_card in s.event_played_pile and ac.major_ap_remaining==1)
	s.event_draw_pile.assign([old_card])
	s.event_discard_pile.assign([new_card])
	ac.major_ap_remaining=3
	check("버튼 상태가 더미 속 시대 정보를 누설하지 않음",ac.can_draw_event())
	check("시대 제거로 소진되어도 외교 뽑기는 재혼합하지 않음",ac.draw_event_card() and s.event_draw_pile.is_empty() and s.event_discard_pile.size()==1 and ac.major_ap_remaining==0)

	print("DIPLOMACY REGRESSION: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed==0 else 1)
