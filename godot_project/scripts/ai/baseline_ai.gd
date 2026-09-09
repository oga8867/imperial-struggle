extends Node

# Basic AI for solo play. Plays one side based on heuristics.

signal ai_action_taken(description: String)

var ai_side: Enums.Side = Enums.Side.NONE
var enabled: bool = false


func enable_for(side: Enums.Side) -> void:
	ai_side = side
	enabled = true


func disable() -> void:
	enabled = false


func is_ai_turn() -> bool:
	if not enabled:
		return false
	if GameManager.state == null:
		return false
	return GameManager.state.phasing_player == ai_side


func decide_investment_tile() -> InvestmentTile:
	# AI는 향후 득점·전쟁 키워드를 위해 자기 라운드에 미리 공개하기로 결정한다.
	for card in GameManager.state.get_player(ai_side).ministry_cards.duplicate():
		if MinistryDecisions.can_reveal(card,ai_side): card.reveal()
	# Pick the highest Major action AP tile
	var tiles: Array = GameManager.state.available_investment_tiles
	if tiles.is_empty():
		return null
	var best: InvestmentTile = null
	var best_score := -999
	for t in tiles:
		var score := _score_tile(t)
		if score > best_score:
			best_score = score
			best = t
	return best


func _score_tile(t: InvestmentTile) -> int:
	# Heuristic: prefer high major AP, prefer Economic/Diplomatic over Military early game,
	# strongly prefer event-eligible tiles if hand has good events
	var score := t.major_action_points * 3
	if t.has_event_symbol:
		score += 2
	if t.has_military_upgrade:
		score += 1

	# Prefer non-military in peace turns where opponent has more flags
	var player := GameManager.state.get_player(ai_side)
	var opponent := GameManager.state.get_opponent(ai_side)
	if t.major_action_type == Enums.ActionType.MILITARY:
		if GameManager.state.current_turn >= 5:
			score += 2
	return score


func decide_event_play(card: EventCard) -> bool:
	# Simple: play if base text helps us, skip otherwise
	if card == null:
		return false
	# Prefer playing if we'd otherwise discard it
	return true


func decide_action_round() -> void:
	if MinistryDecisions.has_pending(): return
	if ActionController.current_tile==null: return
	if ActionController.upgrade_drawn:
		_finish_upgrade()
	if ActionController.bonus_drawn:
		var legal=ActionController.bonus_allowed_theaters
		for id in legal:
			if ActionController.place_bonus_tile(id): break
	# 라운드 시작 전용 내각을 이벤트보다 먼저 검토한다.
	if not ActionController.action_started:
		for c in GameManager.state.get_player(ai_side).ministry_cards.duplicate():
			if c.id in ["M-1","M-21"] and MinistryEffects.can_activate(c,ai_side):
				MinistryEffects.activate_manual(c,ai_side)
				while EventEffects.has_pending():
					if not _resolve_pending(): return
	# 1. Decide event play
	if ActionController.state == ActionController.ActionState.AWAITING_EVENT:
		var card := _pick_event_to_play()
		if card != null:
			ActionController.play_event(card, true)
			# Resolve pending choices
			while EventEffects.has_pending():
				if not _resolve_pending(): return
		else:
			ActionController.skip_event()

	while EventEffects.has_pending():
		if not _resolve_pending(): return
	# 이벤트 AP를 주요 행동에 합산하거나 독립 행동으로 먼저 사용한다.
	for i in ActionController.event_grants.size():
		var grant = ActionController.event_grants[i]
		if grant.type == ActionController.current_tile.major_action_type:
			ActionController.assign_event_grant(i,"major")
	for i in ActionController.event_grants.size():
		if ActionController.event_grants[i].pool.begins_with("event_"):
			ActionController.switch_to_event(i)
			_spend_current()
	ActionController.switch_to_major()
	_spend_current()

	# 3. Switch to Minor and spend
	ActionController.switch_to_minor()
	_spend_current()
	# 6턴 군사 변환으로 방금 생긴 별도 AP도 소비한다.
	for i in ActionController.event_grants.size():
		var grant=ActionController.event_grants[i]
		if grant.pool.begins_with("event_") and grant.amount>0 and grant.pool not in ActionController.finished_pools:
			ActionController.switch_to_event(i)
			_spend_current()

	# 4. Military upgrade if available
	if ActionController.current_tile and ActionController.current_tile.has_military_upgrade:
		if ActionController.begin_upgrade(_pick_upgrade_theater()) and ActionController.upgrade_drawn:
			_finish_upgrade()

	# 5. End the round
	ActionController.end_action_round()
	ai_action_taken.emit("AI completed action round")

func _finish_upgrade() -> void:
	var old=WarManager.basic_tile_in_theater[ActionController.upgrade_theater][ai_side]
	var drawn=ActionController.upgrade_drawn
	var swap=drawn.strength>old.strength
	ActionController.finish_upgrade(swap,ActionController.can_remove_upgrade_tile() and (old.strength if swap else drawn.strength)<=0)


func _pick_event_to_play() -> EventCard:
	var p := GameManager.state.get_player(ai_side)
	if p.hand.is_empty():
		return null
	# Pick the card whose major_action matches our tile's, or any if none matches
	var tile = ActionController.current_tile
	var candidates=p.hand.filter(func(c):return ActionController._can_play_event(c))
	candidates.sort_custom(func(a,b):return int(EventEffects.bonus_condition_met(a,ai_side,false))>int(EventEffects.bonus_condition_met(b,ai_side,false)))
	if not candidates.is_empty(): return candidates[0]
	return null


func _resolve_pending() -> bool:
	if not EventEffects.has_pending():
		return false
	var choice = EventEffects.pending_choices[0]
	if choice.params.get("chooser",ai_side) != ai_side: return false
	var options=EventEffects.choice_options()
	if not options.is_empty():
		options.sort_custom(func(a,b):return _choice_score(choice,a)>_choice_score(choice,b))
		return EventEffects.resolve_option(options[0].id)
	# Find a valid space matching the choice constraints
	var targets=[]
	for sid in GameManager.state.spaces:
		if EventEffects.is_valid_target(sid):
			var ss=GameManager.state.spaces[sid]
			var score=_score_target(ss)
			if "conflict" in choice.type: score+=12 if ss.controlled_by==WarManager._opp(ai_side) else (-15 if ss.controlled_by==ai_side else 0)
			if choice.params.get("from","")=="friendly": score=-score
			targets.append({"id":sid,"score":score})
	targets.sort_custom(func(a,b):return a.score>b.score)
	if not targets.is_empty(): return EventEffects.resolve_choice(0,targets[0].id)
	return false

func _choice_score(choice: Dictionary,option: Dictionary) -> int:
	if option.id=="skip":
		if choice.type=="score_commodity" and GameManager._count_commodity_markets(ai_side,choice.params.commodity)<=GameManager._count_commodity_markets(WarManager._opp(ai_side),choice.params.commodity): return 100
		return -100
	if option.has("theater"):
		# 상대 타일의 뒷면을 고를 때 전력을 조회하지 않는다.
		if choice.type in ["remove_bonus","war_loss"]: return 10
		return _theater_priority(option.theater)
	if option.has("commodity"): return GameManager._count_commodity_markets(ai_side,option.commodity)-GameManager._count_commodity_markets(WarManager._opp(ai_side),option.commodity)
	if option.has("card"): return -int(EventEffects.bonus_condition_met(option.card,ai_side,false))*10
	if GameManager.state.spaces.has(option.id): return _score_target(GameManager.state.spaces[option.id])
	return 0

func _theater_priority(id: String) -> int:
	# 비공개 상대 기본/보너스 타일을 읽지 않고 공개 지도 전력과 내 타일만 사용한다.
	var th=WarManager.get_upcoming_theaters().filter(func(t):return t.id==id)[0]
	var own=WarManager._calculate_army_strength(id,ai_side)+WarManager._calculate_bonus_strength(th,ai_side)
	var opposing_map=WarManager._calculate_bonus_strength(th,WarManager._opp(ai_side),true)
	return 20-absi(own-opposing_map-2)*2


func _try_buy_war_tiles() -> void:
	if WarManager.get_upcoming_war_id() == "":
		return
	var theaters = WarManager.get_upcoming_theaters()
	if theaters.is_empty():
		return
	for attempt in 2:
		var legal=ActionController.bonus_purchase_theaters()
		legal.sort_custom(func(a,b):return _theater_priority(a)>_theater_priority(b))
		var bought=false
		for id in legal:
			if ActionController.purchase_bonus_war_tile(id): bought=true; break
		if not bought: break


func _pick_upgrade_theater() -> String:
	var theaters = WarManager.get_upcoming_theaters()
	if theaters.is_empty():
		return ""
	# Pick the theater where our basic tile has lowest strength
	var worst_id := ""
	var worst_str := 999
	for theater in theaters:
		var tile = WarManager.basic_tile_in_theater.get(theater.id, {}).get(ai_side)
		if tile and tile.strength < worst_str:
			worst_str = tile.strength
			worst_id = theater.id
	return worst_id


func _find_best_shift_target(action_type: Enums.ActionType) -> String:
	var opponent: Enums.Side = GameManager.state.get_opponent(ai_side).side
	var allowed_types: Array = []
	match action_type:
		Enums.ActionType.ECONOMIC:
			allowed_types = [Enums.SpaceType.MARKET]
		Enums.ActionType.DIPLOMATIC:
			allowed_types = [Enums.SpaceType.POLITICAL]
		Enums.ActionType.MILITARY:
			allowed_types = [Enums.SpaceType.FORT, Enums.SpaceType.NAVAL]
			if MinistryEffects.active_flags.get("jacobite",false): allowed_types.append(Enums.SpaceType.POLITICAL)

	var candidates: Array = []
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.space_type in allowed_types:
			if ActionController.can_shift_space(ss):
				var score := _score_target(ss)
				candidates.append([sid, score])
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a, b): return a[1] > b[1])
	return candidates[0][0]


func _score_target(ss: SpaceState) -> int:
	var score := 0
	# Prefer empty spaces (cheaper to flag)
	if ss.is_empty():
		score += 5
	# Prefer cheap ones
	score -= ss.data.base_cost
	# Prefer prestige spaces
	if ss.data.is_prestige:
		score += 4
	# Prefer alliance spaces
	if ss.data.is_alliance:
		score += 3
	# Prefer markets matching global demand
	if ss.data.space_type == Enums.SpaceType.MARKET:
		if ss.data.commodity in GameManager.state.current_global_demand:
			score += 3
	# Prefer conflict-marker spaces (cheaper)
	if ss.has_conflict_marker:
		score += 2
	return score


func decide_ministry_selection() -> Array:
	# Pick first 2 available ministry cards
	var available := GameData.get_ministries_for_era(ai_side, GameManager.state.current_era)
	if available.size() <= 2:
		return available.duplicate()
	available.sort_custom(func(a,b):return _ministry_score(a)>_ministry_score(b))
	return [available[0], available[1]]

func _ministry_score(card: MinistryCard) -> int:
	var weights={"M-1":8,"M-2":6,"M-3":7,"M-5":8,"M-6":5,"M-7":7,"M-8":8,"M-11":8,"M-12":8,"M-13":6,"M-14":5,"M-15":9,"M-17":9,"M-18":7,"M-19":9,"M-20":5,"M-22":8,"M-24":7,"M-25":9,"M-26":8}
	var score=weights.get(card.id,3)
	for c in GameManager.state.get_player(ai_side).hand:
		if c.bonus_condition in card.keywords: score+=2
	return score

func _spend_current() -> void:
	var ac=ActionController
	if ac.pool_key() in ac.finished_pools or (ac.state==ac.ActionState.SPENDING_MINOR and ac.minor_action_used_first_expense): return
	for c in GameManager.state.get_player(ai_side).ministry_cards.duplicate():
		if c.id in ["M-5","M-8","M-9","M-11","M-15","M-16","M-20","M-22"] and MinistryEffects.can_activate(c,ai_side):
			MinistryEffects.activate_manual(c,ai_side)
			while EventEffects.has_pending():
				if not _resolve_pending(): return
	for adv in AdvantageManager.advantages.values():
		if not AdvantageManager.can_activate(adv.id): continue
		var rule=AdvantageManager.effect_rules[adv.id]
		if rule.kind=="discount" and rule.type!=ac.current_action_type(): continue
		if rule.kind=="debt" and GameManager.state.get_player(ai_side).current_debt==0: continue
		if AdvantageManager.activate(adv.id):
			while EventEffects.has_pending():
				if not _resolve_pending(): return
	if ac.current_action_type()==Enums.ActionType.MILITARY and GameManager.state.current_turn==6:
		for i in 10:
			if not ac.convert_turn6_military(Enums.ActionType.ECONOMIC): break
		return
	while ActionController.ap_for_current() > 0:
		# 손패가 소진되면 다음 라운드의 이벤트 선택지를 확보한다. UI와 동일한
		# 외교 지출 경로이므로 보조 행동·제한 점수·빈 더미 조건을 우회하지 않는다.
		if GameManager.state.get_player(ai_side).hand.is_empty() and ac.can_draw_event():
			ac.draw_event_card()
			continue
		var target = _find_best_shift_target(ActionController.current_action_type())
		if target == "" or not ActionController.attempt_shift(target): break
	if ac.can_draw_event(): ac.draw_event_card()
	if ActionController.current_action_type() == Enums.ActionType.MILITARY: _try_buy_war_tiles()
