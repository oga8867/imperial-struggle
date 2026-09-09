extends Node

# 내각 공개를 기다리는 동안 원래 행동을 데이터로 보관한다. Callable/await를
# 저장하지 않으므로 질문이 열린 상태에서 저장해도 같은 행동으로 재개한다.
signal changed
signal resolved
var pending: Dictionary = {}
var declined: Array = []
var preview: Array = []
var pre_tile_action_used = false

func reset() -> void:
	pending.clear()
	declined.clear()
	preview.clear()
	pre_tile_action_used=false
	changed.emit()

func has_pending() -> bool:
	return not pending.is_empty()

func own_round(side: int) -> bool:
	var st=GameManager.state
	return st!=null and st.current_phase==Enums.GamePhase.PEACE_TURN and st.current_turn_phase==Enums.TurnPhase.ACTION_PHASE and st.phasing_player==side

func can_reveal(card: MinistryCard,side: int) -> bool:
	return own_round(side) and card in GameManager.state.get_player(side).ministry_cards and not card.is_revealed

func active(card: MinistryCard) -> bool:
	return card!=null and (card.is_revealed or card.id in preview)

func offer(side: int,ids: Array,command: Dictionary) -> bool:
	if has_pending(): return true
	var candidates=[]
	for id in ids:
		var card=MinistryEffects._card(side,id)
		if card and can_reveal(card,side) and id not in declined and id not in candidates:
			candidates.append(id)
	if candidates.is_empty(): return false
	# AI도 자신의 라운드에서 공개하는 같은 모델 함수를 사용한다.
	if AIController.enabled and AIController.ai_side==side and not AIController.strategy_mode:
		for id in candidates: MinistryEffects._card(side,id).reveal()
		return false
	pending={"side":side,"ids":candidates,"declined":[],"command":command}
	changed.emit()
	return true

func choose(reveal_card: bool) -> void:
	if not has_pending(): return
	var id=pending.ids[0]
	var card=MinistryEffects._card(pending.side,id)
	if reveal_card and card and can_reveal(card,pending.side): card.reveal()
	else: pending.declined.append(id)
	pending.ids.pop_front()
	# 필요한 키워드를 이미 공개했다면 같은 키워드의 다른 카드까지 묻지 않는다.
	if pending.command.kind=="event":
		var event=pending.command.card
		var player=GameManager.state.get_player(pending.side)
		pending.ids=pending.ids.filter(func(next_id):
			var next=MinistryEffects._card(pending.side,next_id)
			if next==null or next.is_revealed: return false
			if next_id=="M-26": return EventEffects.bonus_condition_met(event,pending.side,true)
			return not (next.has_keyword(event.bonus_condition) and player.has_keyword(event.bonus_condition)))
	if not pending.ids.is_empty():
		changed.emit()
		return
	var command=pending.command
	declined=pending.declined.duplicate()
	pending={}
	changed.emit()
	_resume(command)
	declined.clear()
	EventEffects._finalize_pending()
	ActionController.ap_changed.emit()
	resolved.emit()

func _resume(c: Dictionary) -> void:
	match c.kind:
		"shift": ActionController.attempt_shift(c.id)
		"debt": ActionController.take_debt_for_ap(c.amount)
		"event":
			if not ActionController.play_event(c.card,c.bonus) and not has_pending(): GameManager.status_message.emit("내각을 비공개로 유지하여 이 이벤트는 사용하지 않았습니다.")
		"manual": MinistryEffects.activate_manual(c.card,c.side,c.index)
		"round": MinistryEffects.round_start(c.side)
		"advantage_hook": MinistryEffects.on_advantage_exhausted(c.side,c.region)
		"pompadour": MinistryEffects.apply_pompadour_reward()
		"forced_debt": GameManager.state.get_player(c.side).incur_debt(c.amount)
		"commodity_award": MinistryEffects.commodity_award(c.side,c.commodity)
		"reveal":
			# 미리 공개한 무역 내각은 아직 끝나지 않은 경제 행동에 적용할 수 있다.
			MinistryEffects.apply_trade_bonus(c.side)

func offer_shift(id: String) -> bool:
	var ac=ActionController
	if not own_round(ac.current_side): return false
	if not GameManager.state.spaces.has(id): return false
	var ss=GameManager.state.spaces[id]
	var ids=[]
	if ac.current_action_type()==Enums.ActionType.ECONOMIC and MinistryEffects.trade_advantage_at_start() and ss.data.space_type==Enums.SpaceType.MARKET and ss.controlled_by!=ac.current_side:
		return offer(ac.current_side,["M-24"],{"kind":"shift","id":id})
	if ac.current_action_type()!=Enums.ActionType.DIPLOMATIC: return false
	if ((id.begins_with("ireland") or id.begins_with("scotland")) and ss.controlled_by==Enums.Side.NONE) or (ac.state==ac.ActionState.SPENDING_MINOR and ss.controlled_by==WarManager._opp(ac.current_side) and ss.data.space_type==Enums.SpaceType.POLITICAL and ss.data.region==Enums.Region.EUROPE and MinistryEffects._count_controlled_containing(ac.current_side,"ireland")>0): ids.append("M-6")
	if id.begins_with("sons_of_liberty") or id.begins_with("usa_"): ids.append("M-22")
	# 조회에만 사용할 임시 허용 목록이다. 카드를 공개하거나 비용을 지출하지 않는다.
	preview=ids
	var possible=ac.can_shift_space(ss)
	preview=[]
	return possible and offer(ac.current_side,ids,{"kind":"shift","id":id})

func offer_debt(amount: int) -> bool:
	var ac=ActionController
	var side=ac.current_side
	var ids=[]
	if ac.current_action_type()==Enums.ActionType.ECONOMIC:
		var bank=MinistryEffects._card(side,"M-17")
		if bank and int(bank.exhausted_abilities.get("credit",0))<2: ids.append("M-17")
	if not ac.first_debt_taken_this_ar and GameManager.state.get_player(side).available_debt()>GameManager.state.get_opponent(side).available_debt(): ids.append("M-23")
	return offer(side,ids,{"kind":"debt","amount":amount})

func offer_event(card: EventCard,bonus: bool) -> bool:
	var ac=ActionController
	var ids=[]
	var tile=ac.current_tile
	if not tile.has_event_symbol: ids.append("M-25")
	elif card.major_action not in [Enums.ActionType.NONE,tile.major_action_type]: ids.append("M-8")
	if bonus and EventEffects.bonus_condition_met(card,ac.current_side,false):
		var player=GameManager.state.get_player(ac.current_side)
		if not player.has_keyword(card.bonus_condition):
			# 한 장을 공개하면 나머지 동일 키워드의 공개 요청은 제거한다.
			for minister in player.ministry_cards:
				if minister.has_keyword(card.bonus_condition): ids.append(minister.id)
		ids.append("M-26")
		if card.id==34 and ac.current_side==Enums.Side.FRANCE and not player.has_keyword("Governance"):
			for minister in player.ministry_cards:
				if minister.has_keyword("Governance"): ids.append(minister.id); break
	return offer(ac.current_side,ids,{"kind":"event","card":card,"bonus":bonus})

func possible_bank_credit(side: int) -> int:
	preview=["M-17"]
	var amount=MinistryEffects.bank_credit(side,1)
	preview=[]
	return amount
