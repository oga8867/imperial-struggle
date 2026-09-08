extends Node

var passed=0
var failed=0

func check(label: String,ok: bool) -> void:
	if ok: passed+=1; print("PASS ",label)
	else: failed+=1; push_error("FAIL "+label)

func fresh(side: int=Enums.Side.FRANCE,major: int=Enums.ActionType.ECONOMIC,minor: int=Enums.ActionType.MILITARY) -> void:
	AIController.disable()
	GameManager.start_new_game()
	while not GameManager._ministry_pending_sides.is_empty(): GameManager.complete_ministry_selection(GameManager._ministry_pending_sides[0])
	GameManager.state.phasing_player=side
	ActionController.begin_action_round(side,InvestmentTile.create(99,major,4,minor,true,true))
	ActionController.skip_event()

func ministry(id: String,side: int,revealed: bool=true) -> MinistryCard:
	var card=GameData.ministries.filter(func(c):return c.id==id)[0]
	GameManager.state.get_player(side).ministry_cards.assign([card])
	card.is_in_play=true
	card.is_revealed=revealed
	return card

func resolve_all() -> bool:
	for i in 100:
		if not EventEffects.has_pending(): return true
		var options=EventEffects.choice_options()
		if not options.is_empty():
			if not EventEffects.resolve_option(options[0].id): return false
		else:
			var target=""
			for ss in GameManager.state.spaces.values():
				if EventEffects.is_valid_target(ss.data.id): target=ss.data.id; break
			if target=="" or not EventEffects.resolve_choice(0,target): return false
	return false

func _ready() -> void:
	await get_tree().process_frame
	# 모든 카드의 양 진영 분기에서 선택 상태가 완료 가능한지 확인한다.
	# 개별 효과의 정확성은 아래 별도의 조건·숫자·소유권 검사로 검증한다.
	for card in GameData.events:
		for side in [Enums.Side.BRITAIN,Enums.Side.FRANCE]:
			fresh(side)
			GameManager.state.current_era=card.era
			GameManager.state.current_turn=[1,3,5][card.era]
			EventEffects.apply_event(card,side,true)
			check("이벤트 #%d %s 선택 완료" % [card.id,LocaleManager.side(side)],resolve_all())
	fresh(Enums.Side.BRITAIN)
	var p=GameManager.state.britain
	var before=GameManager.state.vp
	EventEffects.apply_event(GameData.events.filter(func(c):return c.id==25)[0],Enums.Side.BRITAIN,false)
	check("#25 내 함대의 출발지를 사람에게 질문",EventEffects.choice_options().any(func(o):return o.id=="navy"))
	EventEffects.resolve_option("navy")
	check("#25 내 함대 대기와 2 VP",p.squadrons_in_navy_box==1 and p.squadrons_returning.get(2)==1 and GameManager.state.vp==before-2)
	GameManager.state.current_turn=2
	p.reset_for_new_turn()
	check("#25 다음 평화 턴 함대 복귀",p.squadrons_in_navy_box==2 and p.squadrons_returning.is_empty())
	fresh(Enums.Side.BRITAIN)
	EventEffects.apply_event(GameData.events.filter(func(c):return c.id==18)[0],Enums.Side.BRITAIN,false)
	var th=EventEffects.choice_options()[0].id
	before=WarManager._calculate_army_strength(th,Enums.Side.BRITAIN)
	EventEffects.resolve_option(th)
	check("#18 Byng 마커의 지정 전장 +2",WarManager._calculate_army_strength(th,Enums.Side.BRITAIN)==before+2)
	fresh()
	EventEffects.apply_event(GameData.events.filter(func(c):return c.id==12)[0],Enums.Side.FRANCE,false)
	# 아무 피해 대상이 없다면 불가능한 효과는 규칙에 따라 종료한다.
	check("#12 실행 불가능한 전쟁 손실로 정지하지 않음",not EventEffects.has_pending())
	fresh(Enums.Side.BRITAIN,Enums.ActionType.DIPLOMATIC)
	var card=ministry("M-15",Enums.Side.BRITAIN)
	MinistryEffects.activate_manual(card,Enums.Side.BRITAIN,0)
	check("Pitt 추가 DP는 비위신 공간에서 사용",ActionController.ap_for_current(GameManager.state.spaces.ireland_alliance,"shift")==5)
	check("Pitt 추가 DP는 위신 공간에서 제외",ActionController.ap_for_current(GameManager.state.spaces.ireland_prestige,"shift")==4)
	fresh(Enums.Side.BRITAIN,Enums.ActionType.ECONOMIC)
	card=ministry("M-17",Enums.Side.BRITAIN)
	p=GameManager.state.britain
	p.current_debt=p.debt_limit
	check("Merchant Banks는 한도에서도 경제 AP 2 제공",ActionController.take_debt_for_ap(2)==2 and p.current_debt==p.debt_limit)
	ActionController.spend_ap(2)
	check("Merchant Banks 사용 후 세 번째 면제 거절",ActionController.take_debt_for_ap(1)==0 and card.exhausted_abilities.get("credit")==2)
	fresh(Enums.Side.BRITAIN,Enums.ActionType.MILITARY)
	ministry("M-17",Enums.Side.BRITAIN)
	p=GameManager.state.britain
	p.current_debt=p.debt_limit
	check("Merchant Banks는 군사 부채 면제 안 함",ActionController.take_debt_for_ap(1)==0)
	fresh(Enums.Side.BRITAIN)
	ministry("M-19",Enums.Side.BRITAIN)
	p=GameManager.state.britain
	p.current_debt=p.debt_limit
	before=GameManager.state.vp
	p.incur_debt(2)
	check("James Watt 강제 초과 부채 VP 차단",GameManager.state.vp==before)
	fresh(Enums.Side.FRANCE,Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC)
	card=ministry("M-1",Enums.Side.FRANCE)
	GameManager.state.spaces.savoy_alliance.controlled_by=Enums.Side.FRANCE
	MinistryEffects.activate_manual(card,Enums.Side.FRANCE)
	ActionController.switch_to_minor()
	check("Cardinal Ministers가 보조 외교에도 추가 DP",ActionController.ap_for_current()>=3)
	fresh(Enums.Side.FRANCE,Enums.ActionType.MILITARY)
	card=ministry("M-4",Enums.Side.FRANCE)
	MinistryEffects.activate_manual(card,Enums.Side.FRANCE,0)
	check("Jacobite 같은 AR의 두 능력 동시 사용 거절",not MinistryEffects.can_activate(card,Enums.Side.FRANCE,1))
	fresh(Enums.Side.BRITAIN)
	card=ministry("M-5",Enums.Side.BRITAIN)
	MinistryEffects.activate_manual(card,Enums.Side.BRITAIN)
	check("Walpole 버릴 카드 직접 선택",EventEffects.choice_options().size()==4)
	resolve_all()
	check("Walpole 선택 후 손패 3장",GameManager.state.britain.hand.size()==3)
	print("CARD REGRESSION: %d passed, %d failed" % [passed,failed])
	get_tree().quit(1 if failed else 0)
