extends Node

signal phase_changed(phase: Enums.TurnPhase)
signal action_round_started(side: Enums.Side, round_num: int)
signal game_over(winner: Enums.Side)
signal vp_changed(new_vp: int)
signal player_action_required(side: Enums.Side, action_type: String)
signal status_message(text: String)

var state: GameState

# Pending sets for phases that need user input
var _discard_pending_sides: Array = []
# §4.1.6: 양쪽이 선택을 마칠 때까지 버린 카드도 비공개 정보다.
# 손패에서는 즉시 빼되 공개 버림 더미에는 마지막 선택 뒤 한꺼번에 옮긴다.
var _pending_discards: Dictionary = {}
var _ministry_pending_sides: Array = []
var _initiative_first_player_pending: bool = false

# Sweep tracking (§2.5)
var _swept_awards_winner: Enums.Side = Enums.Side.NONE
var _swept_demand_winner: Enums.Side = Enums.Side.NONE

# Initial setup tracking for Final Scoring (§11.0)
var _initial_territories: Dictionary = {}  # space_id -> initial controller


func _ready() -> void:
	state = GameState.new()


func start_new_game() -> void:
	AIController.cancel()
	state = GameState.new()
	GameLog.clear()
	MinistryDecisions.reset()
	# Autoload는 장면을 바꿔도 살아 있으므로 새 게임마다 이전 판의 상태를 지운다.
	_discard_pending_sides.clear()
	_pending_discards.clear()
	_ministry_pending_sides.clear()
	_initiative_first_player_pending = false
	_swept_awards_winner = Enums.Side.NONE
	_swept_demand_winner = Enums.Side.NONE
	ActionController.reset_session()
	EventEffects.pending_choices.clear()
	EventEffects.current_card = null
	AdvantageManager._create_advantages()
	AdvantageManager.reset_round()
	MinistryEffects.watt_active_for_britain = false
	for card in GameData.ministries:
		card.is_revealed = false
		card.is_in_play = false
		card.reset_exhaustion()
	WarFlow.reset()
	WarManager._create_basic_tiles()
	WarManager._create_bonus_pool()
	state.investment_draw_pile.assign(GameData.investment_tile_pool)
	state.investment_draw_pile.shuffle()
	state.vp = 15
	state.current_turn = 1
	state.current_era = Enums.Era.SUCCESSION
	state.current_phase = Enums.GamePhase.PEACE_TURN
	state.initiative = Enums.Side.FRANCE
	state.first_player = Enums.Side.FRANCE

	# Per playbook: starting Debt Limit = 6 (not 4)
	state.britain.debt_limit = 6
	state.france.debt_limit = 6
	# Britain starts with 2 squadrons in Navy Box, France with 1
	state.britain.squadrons_in_navy_box = 2
	state.france.squadrons_in_navy_box = 1

	_init_spaces()
	_setup_initial_flags()
	_record_initial_territories()
	_deal_initial_cards()
	_setup_initial_war()

	start_peace_turn()


func _init_spaces() -> void:
	# Re-init spaces — clear any starting_control from data, set explicitly below
	for space_id in GameData.spaces:
		var sd: SpaceData = GameData.spaces[space_id]
		var ss := SpaceState.new(sd)
		ss.controlled_by = Enums.Side.NONE  # override data-driven starting_control
		state.spaces[space_id] = ss


func _record_initial_territories() -> void:
	# Save who controls each Territory at game start (for §11.0 final scoring)
	_initial_territories.clear()
	for sid in state.spaces:
		var ss: SpaceState = state.spaces[sid]
		if ss.data.space_type == Enums.SpaceType.TERRITORY and ss.controlled_by != Enums.Side.NONE:
			_initial_territories[sid] = ss.controlled_by


func _setup_initial_flags() -> void:
	# Per Imperial Struggle 2nd Printing Playbook (page 2, Setup section)
	var britain_flags := [
		# Europe
		"austria_alliance",          # Austria Alliance 2
		"dutch_republic_prestige",   # Dutch Republic Prestige 3
		"german_states_saxony_alliance_b",  # German States Alliance 3
		# North America
		"mass_bay",
		"northern_colonies",
		"hudson_valley",
		"chesapeake",
		# Caribbean (incl. southern colonies)
		"carolinas",
		"georgia",
		"jamaica",
		"barbados",
		"st_lucia",
		# India
		"madras",
		"kanchipuram",
		"calcutta",
		"midnapore",
	]
	var france_flags := [
		# Europe
		"spain_alliance",            # Spain Alliance 3
		"austria_prestige_b",        # Austria second Prestige 3
		"bavaria_alliance",          # Bavaria
		"ireland_alliance",          # Ireland Alliance 2
		# North America
		"quebec_and_montreal",
		"acadia",
		"cataraqui",
		"algonquin_la",
		# Caribbean
		"louisiana",
		"st_domingue",
		"guadeloupe",
		"port_de_paix",
		"martinique",
		# India
		"chandernagore",
		"pondicherry",
		"karaikal",
		"plassey",
	]
	var missing_br: Array = []
	var missing_fr: Array = []
	for sid in britain_flags:
		if sid in state.spaces:
			state.spaces[sid].controlled_by = Enums.Side.BRITAIN
		else:
			missing_br.append(sid)
	for sid in france_flags:
		if sid in state.spaces:
			state.spaces[sid].controlled_by = Enums.Side.FRANCE
		else:
			missing_fr.append(sid)
	if missing_br.size() > 0:
		push_warning("Missing BR setup spaces: " + str(missing_br))
	if missing_fr.size() > 0:
		push_warning("Missing FR setup spaces: " + str(missing_fr))


func _deal_initial_cards() -> void:
	# Build initial deck. Hand-dealing happens in _deal_cards_phase (3 each, discard down to 3).
	var succession_events := GameData.get_events_for_era(Enums.Era.SUCCESSION)
	succession_events.shuffle()
	state.event_draw_pile = succession_events.duplicate()


func _setup_initial_war() -> void:
	# Per playbook: pre-place WSS war tiles + France starts with 1 Bonus tile in Central Europe WSS.
	# Also: Britain starts with Wheat advantage, France with Algonquin Raids.
	if has_node("/root/WarManager"):
		WarManager.setup_war("spanish_succession")
		WarManager.purchase_bonus_war_tile(Enums.Side.FRANCE, "central_europe_wss")
	if has_node("/root/AdvantageManager"):
		# Mark starting advantages as controlled
		for adv_id in AdvantageManager.advantages:
			var adv: Advantage = AdvantageManager.advantages[adv_id]
			if "wheat" in adv_id.to_lower():
				adv.controlled_by = Enums.Side.BRITAIN
			elif "algonquin" in adv_id.to_lower() and "raid" in adv_id.to_lower():
				adv.controlled_by = Enums.Side.FRANCE


func start_peace_turn() -> void:
	state.current_phase = Enums.GamePhase.PEACE_TURN
	var turn := state.current_turn
	if has_node("/root/GameLog"):
		GameLog.log_separator("%d턴 · %s" % [turn, LocaleManager.era(state.current_era)])

	# Per playbook: Deck Phase and Debt Limit Phase only apply on new era turns (3, 5)
	# Turn 1 also skips them.
	if state.is_new_era_turn() and turn != 1:
		_deck_phase()
		if turn >= 3:
			_debt_limit_increase_phase()

	_award_phase()
	_global_demand_phase()
	# Reset Phase: skip on turn 1 (no exhausted markers exist yet)
	if turn != 1:
		_reset_phase()
	_deal_cards_phase()

	# 카드를 버리는 선택을 끝낸 뒤 내각 선택으로 넘어간다 (§4.1.6).
	_begin_hand_discard_phase()


func _begin_ministry_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.MINISTRY_PHASE
	phase_changed.emit(Enums.TurnPhase.MINISTRY_PHASE)
	# §4.1.7: 시대 두 번째 턴에도 미공개 내각은 바꿀 수 있다.
	_ministry_pending_sides = [Enums.Side.BRITAIN, Enums.Side.FRANCE]
	_request_next_ministry_selection()


func _request_next_ministry_selection() -> void:
	if _ministry_pending_sides.is_empty():
		_continue_after_ministry()
		return
	var side: Enums.Side = _ministry_pending_sides[0]
	if has_node("/root/AIController") and AIController.enabled and AIController.ai_side == side:
		var p := state.get_player(side)
		var locked: Array = []
		if not state.is_new_era_turn():
			locked = p.ministry_cards.filter(func(c): return c.is_revealed)
		var picks: Array = locked.duplicate()
		for card in AIController.decide_ministry_selection():
			if picks.size() < 2 and card not in picks: picks.append(card)
		if side==Enums.Side.FRANCE and state.jacobite_extra_ministry and not state.jacobite_defeated:
			for card in GameData.ministries:
				if card.id=="M-4" and card not in picks: picks.append(card)
		p.ministry_cards.clear()
		for c in picks:
			if c is MinistryCard:
				p.ministry_cards.append(c)
				c.is_in_play = true
		_ministry_pending_sides.pop_front()
		_request_next_ministry_selection()
	else:
		player_action_required.emit(side, "select_ministry")


func complete_ministry_selection(side: Enums.Side) -> void:
	if side in _ministry_pending_sides:
		_ministry_pending_sides.erase(side)
	_request_next_ministry_selection()


func _continue_after_ministry() -> void:
	if state.current_turn > 1:
		_initiative_phase()
	else:
		_start_action_phase()


func _deck_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.DECK_PHASE
	phase_changed.emit(Enums.TurnPhase.DECK_PHASE)

	if state.current_turn == 3:
		state.current_era = Enums.Era.EMPIRE
		var empire_events := GameData.get_events_for_era(Enums.Era.EMPIRE)
		empire_events.shuffle()
		state.event_draw_pile.append_array(empire_events)
		state.event_draw_pile.shuffle()
	elif state.current_turn == 5:
		state.current_era = Enums.Era.REVOLUTION
		# §4.1.1: 혁명 시대 시작 시 손에 남아 있는 왕위계승 시대 카드를 제거한다.
		for player in [state.britain, state.france]:
			for card in player.hand.duplicate():
				if card.era == Enums.Era.SUCCESSION:
					player.hand.erase(card)
					state.event_played_pile.append(card)
		var rev_events := GameData.get_events_for_era(Enums.Era.REVOLUTION)
		rev_events.shuffle()
		state.event_draw_pile.append_array(rev_events)
		state.event_draw_pile.shuffle()


func _debt_limit_increase_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.DEBT_LIMIT_INCREASE
	phase_changed.emit(Enums.TurnPhase.DEBT_LIMIT_INCREASE)
	state.britain.debt_limit += 4
	state.france.debt_limit += 4


func _award_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.AWARD_PHASE
	phase_changed.emit(Enums.TurnPhase.AWARD_PHASE)
	AwardManager.assign_awards_for_turn(state.is_new_era_turn())


func _global_demand_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.GLOBAL_DEMAND_PHASE
	phase_changed.emit(Enums.TurnPhase.GLOBAL_DEMAND_PHASE)
	var all_commodities: Array[Enums.Commodity] = [
		Enums.Commodity.FISH, Enums.Commodity.FUR, Enums.Commodity.SPICE,
		Enums.Commodity.SUGAR, Enums.Commodity.TOBACCO, Enums.Commodity.COTTON,
	]
	var shuffled := all_commodities.duplicate()
	shuffled.shuffle()
	state.current_global_demand.clear()
	for i in range(3):
		state.current_global_demand.append(shuffled[i])


func _reset_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.RESET_PHASE
	phase_changed.emit(Enums.TurnPhase.RESET_PHASE)
	state.britain.reset_for_new_turn()
	state.france.reset_for_new_turn()
	if has_node("/root/MinistryEffects"):
		MinistryEffects.reset_exhaustion_for_turn()
	if has_node("/root/AdvantageManager"):
		AdvantageManager.reset_exhaustion()


func _deal_cards_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.DEAL_CARDS_PHASE
	phase_changed.emit(Enums.TurnPhase.DEAL_CARDS_PHASE)
	# §4.1.5-6: 고르지 않은 한 장까지 사용 더미로 보낸 뒤, 뽑기 더미가 소진될 때만 재혼합한다.
	state.investment_used_pile.append_array(state.investment_dealt_this_turn)
	state.investment_dealt_this_turn.clear()
	state.available_investment_tiles.clear()
	for i in range(9):
		if state.investment_draw_pile.is_empty():
			state.investment_draw_pile.assign(state.investment_used_pile)
			state.investment_used_pile.clear()
			state.investment_draw_pile.shuffle()
		var tile = state.investment_draw_pile.pop_back()
		state.available_investment_tiles.append(tile)
		state.investment_dealt_this_turn.append(tile)
	for i in range(3):
		for player in [state.britain, state.france]:
			var card = _draw_event()
			if card != null:
				player.hand.append(card)
	_discard_down_to_three(state.britain)
	_discard_down_to_three(state.france)

func _draw_event(allow_recycle: bool = true) -> EventCard:
	# 재순환 가능한 버림 더미와 이미 사용하여 게임에서 제거된 카드를 분리한다.
	while true:
		if state.event_draw_pile.is_empty():
			if not allow_recycle or state.event_discard_pile.is_empty():
				return null
			state.event_draw_pile.assign(state.event_discard_pile)
			state.event_discard_pile.clear()
			state.event_draw_pile.shuffle()
		var card: EventCard = state.event_draw_pile.pop_back()
		if state.current_era == Enums.Era.REVOLUTION and card.era == Enums.Era.SUCCESSION:
			state.event_played_pile.append(card)
			continue
		return card
	return null


func _discard_down_to_three(_player: PlayerState) -> void:
	# 실제 선택은 _begin_hand_discard_phase에서 양 진영의 손패를 받은 뒤 처리한다.
	pass

func _begin_hand_discard_phase() -> void:
	_discard_pending_sides.clear()
	_pending_discards.clear()
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		if state.get_player(side).hand.size() > 3: _discard_pending_sides.append(side)
	_request_next_discard()

func _request_next_discard() -> void:
	if _discard_pending_sides.is_empty():
		for discarded in _pending_discards.values():
			state.event_discard_pile.append_array(discarded)
		_pending_discards.clear()
		_begin_ministry_phase()
		return
	var side = _discard_pending_sides[0]
	if AIController.enabled and AIController.ai_side == side:
		complete_discard(side, AIController.decide_discard())
	else:
		player_action_required.emit(side, "discard_events")

func complete_discard(side: Enums.Side, keep: Array) -> bool:
	if _discard_pending_sides.is_empty() or _discard_pending_sides[0] != side or keep.size() != 3: return false
	var hand = state.get_player(side).hand
	var ids = {}
	for card in keep:
		if not card in hand or ids.has(card.id): return false
		ids[card.id] = true
	for card in hand.duplicate():
		if not card in keep:
			hand.erase(card)
			if not _pending_discards.has(side): _pending_discards[side] = []
			_pending_discards[side].append(card)
	_discard_pending_sides.pop_front()
	_request_next_discard()
	return true


func _initiative_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.INITIATIVE_PHASE
	phase_changed.emit(Enums.TurnPhase.INITIATIVE_PHASE)
	state.initiative = state.determine_initiative()
	_initiative_first_player_pending = true
	if AIController.enabled and AIController.ai_side == state.initiative:
		choose_first_player(state.initiative)
	else:
		player_action_required.emit(state.initiative, "choose_first_player")

func choose_first_player(side: Enums.Side) -> void:
	if not _initiative_first_player_pending or side not in [Enums.Side.BRITAIN, Enums.Side.FRANCE]: return
	state.first_player = side
	_initiative_first_player_pending = false
	_start_action_phase()

func resume_session() -> void:
	phase_changed.emit(state.current_turn_phase)
	vp_changed.emit(state.vp)
	if state.current_phase == Enums.GamePhase.GAME_OVER:
		game_over.emit(state.winner)
		return
	if state.current_phase == Enums.GamePhase.WAR:
		WarManager.begin_war(WarManager.current_war_id)
	elif not _discard_pending_sides.is_empty():
		_request_next_discard()
	elif not _ministry_pending_sides.is_empty():
		_request_next_ministry_selection()
	elif _initiative_first_player_pending:
		player_action_required.emit(state.initiative, "choose_first_player")
	elif state.current_turn_phase == Enums.TurnPhase.ACTION_PHASE:
		var action = "select_investment_tile" if ActionController.current_tile == null else "play_actions"
		player_action_required.emit(state.phasing_player, action)
		ActionController.ap_changed.emit()
		if EventEffects.has_pending(): EventEffects.pending_choices_changed.emit(EventEffects.pending_choices)


func _start_action_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.ACTION_PHASE
	phase_changed.emit(Enums.TurnPhase.ACTION_PHASE)
	state.britain.action_rounds_taken = 0
	state.france.action_rounds_taken = 0
	state.phasing_player = state.first_player
	state.current_action_round = 1
	_start_action_round()


func _start_action_round() -> void:
	# End if both players have completed 4 rounds
	if state.britain.action_rounds_taken >= 4 and state.france.action_rounds_taken >= 4:
		_end_action_phase()
		return
	# Force opponent if current player already done 4
	if state.get_player(state.phasing_player).action_rounds_taken >= 4:
		state.phasing_player = _opponent(state.phasing_player)
	# Round number = the about-to-play player's count + 1
	var rnd := state.get_player(state.phasing_player).action_rounds_taken + 1
	state.current_action_round = rnd
	MinistryDecisions.pre_tile_action_used=false
	MinistryEffects.prepare_round()
	action_round_started.emit(state.phasing_player, rnd)
	player_action_required.emit(state.phasing_player, "select_investment_tile")
	if state.current_turn==4 and rnd==1 and state.war_carryover_draws.get(state.phasing_player,0)>0:
		EventEffects._add_pending("draw_bonus",{"side":state.phasing_player,"count":state.war_carryover_draws[state.phasing_player]})
		state.war_carryover_draws[state.phasing_player]=0
		EventEffects._finalize_pending()


func _opponent(side: Enums.Side) -> Enums.Side:
	return Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN


func _era_name(era: Enums.Era) -> String:
	match era:
		Enums.Era.SUCCESSION: return "Succession Era"
		Enums.Era.EMPIRE: return "Empire Era"
		Enums.Era.REVOLUTION: return "Revolution Era"
	return ""


func _check_post_war_sweep(results: Array) -> Enums.Side:
	if results.is_empty() or not WarManager.current_war_id in WarManager.wars: return Enums.Side.NONE
	if results.size() != WarManager.wars[WarManager.current_war_id].theaters.size(): return Enums.Side.NONE
	var winner = results[0].get("winner", Enums.Side.NONE)
	for result in results:
		if result.get("winner") != winner or not WarManager.is_maximum_spoils(result.get("theater_id", ""), winner, result.get("margin", 0)):
			return Enums.Side.NONE
	return winner


func select_investment_tile(side: Enums.Side, tile: InvestmentTile) -> void:
	if MinistryDecisions.has_pending(): return
	if EventEffects.has_pending(): return
	if state.current_phase != Enums.GamePhase.PEACE_TURN or state.current_turn_phase != Enums.TurnPhase.ACTION_PHASE:
		return
	if side != state.phasing_player or ActionController.state != ActionController.ActionState.IDLE or tile not in state.available_investment_tiles:
		return
	var player := state.get_player(side)
	player.selected_investment_tile = tile
	state.available_investment_tiles.erase(tile)
	player.tiles_taken_this_turn.append(tile)
	ActionController.begin_action_round(side, tile)
	if has_node("/root/GameLog"):
		var maj_name: String = LocaleManager.action(tile.major_action_type)
		var min_name: String = LocaleManager.action(tile.minor_action_type)
		var symbols: Array[String] = []
		if tile.has_event_symbol: symbols.append("이벤트")
		if tile.has_military_upgrade: symbols.append("전쟁 준비")
		var sym_str := " + " + ", ".join(symbols) if symbols.size() > 0 else ""
		GameLog.log_entry(side, "tile", "투자 선택: 주요 %s %d · 보조 %s 2%s" % [
			maj_name, tile.major_action_points, min_name, sym_str])
	player_action_required.emit(side, "play_actions")


func pass_action_round(side: Enums.Side) -> void:
	if MinistryDecisions.has_pending(): return
	if side != state.phasing_player or state.current_turn_phase != Enums.TurnPhase.ACTION_PHASE or state.current_phase != Enums.GamePhase.PEACE_TURN:
		return
	# §6.0: 선택 타일의 어느 요소도 쓰지 않았을 때만 패스 보상을 받는다.
	if ActionController.action_started or EventEffects.has_pending():
		return
	if ActionController.current_tile == null:
		if state.available_investment_tiles.is_empty():
			return
		# UI는 타일 선택 뒤 패스를 권장한다. 레거시 호출에서도 한 장은 반드시 소비한다.
		var tile = state.available_investment_tiles.pop_back()
		state.get_player(side).tiles_taken_this_turn.append(tile)
	state.get_player(side).reduce_debt(2)
	ActionController.reset_session()
	_end_action_round()


func _end_action_round() -> void:
	var current_side := state.phasing_player
	ActionController.reset_session()
	state.get_player(current_side).action_rounds_taken += 1
	state.phasing_player = _opponent(current_side)
	_start_action_round()


func _end_action_phase() -> void:
	_reduce_treaty_points_phase()
	_resolve_remaining_powers()
	_scoring_phase()
	_victory_check_phase()


func _reduce_treaty_points_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.REDUCE_TREATY_POINTS
	phase_changed.emit(Enums.TurnPhase.REDUCE_TREATY_POINTS)
	state.britain.reduce_excess_treaty_points()
	state.france.reduce_excess_treaty_points()


func _resolve_remaining_powers() -> void:
	state.current_turn_phase = Enums.TurnPhase.RESOLVE_REMAINING_POWERS
	phase_changed.emit(Enums.TurnPhase.RESOLVE_REMAINING_POWERS)
	if has_node("/root/MinistryEffects"):
		MinistryEffects.apply_end_of_peace_turn()


func _scoring_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.SCORING_PHASE
	phase_changed.emit(Enums.TurnPhase.SCORING_PHASE)
	# Track sweep info for §2.5 auto-victory check
	_swept_awards_winner = _score_regional_awards_with_winner()
	_score_prestige()
	_swept_demand_winner = _score_global_demand_with_winner()
	if has_node("/root/MinistryEffects"):
		MinistryEffects.apply_scoring_bonuses()
	vp_changed.emit(state.vp)


func _score_regional_awards() -> void:
	_score_regional_awards_with_winner()


func _score_regional_awards_with_winner() -> Enums.Side:
	# Returns the sole winner of all 4 regional awards if any (for §2.5 sweep), else NONE
	var winners: Array[Enums.Side] = []
	for region in [Enums.Region.EUROPE, Enums.Region.NORTH_AMERICA,
			Enums.Region.CARIBBEAN, Enums.Region.INDIA]:
		var br_count := _count_flags_in_region(Enums.Side.BRITAIN, region)
		var fr_count := _count_flags_in_region(Enums.Side.FRANCE, region)
		var winner = AwardManager.score_region(region, br_count, fr_count)
		winners.append(winner)
	# Check if all 4 won by one side
	var first := winners[0]
	if first == Enums.Side.NONE: return Enums.Side.NONE
	for w in winners:
		if w != first: return Enums.Side.NONE
	return first


func _score_prestige() -> void:
	var counts = {Enums.Side.BRITAIN: 0, Enums.Side.FRANCE: 0}
	var usa_open = state.current_turn == 6 and state.spaces.values().any(func(s): return s.has_usa_flag)
	for ss in state.spaces.values():
		var usa_space = ss.data.id.begins_with("usa_")
		var eligible = ss.data.region == Enums.Region.EUROPE or (usa_open and usa_space)
		if ss.data.is_prestige and eligible and not ss.has_conflict_marker and ss.controlled_by != Enums.Side.NONE:
			counts[ss.controlled_by] += 1
	if counts[Enums.Side.FRANCE] > counts[Enums.Side.BRITAIN]:
		state.score_vp(Enums.Side.FRANCE, 2)
	elif counts[Enums.Side.BRITAIN] > counts[Enums.Side.FRANCE]:
		state.score_vp(Enums.Side.BRITAIN, 2)


func _score_global_demand() -> void:
	_score_global_demand_with_winner()


func _score_global_demand_with_winner() -> Enums.Side:
	var winners: Array = []
	for commodity in [Enums.Commodity.FUR,Enums.Commodity.SPICE,Enums.Commodity.FISH,Enums.Commodity.TOBACCO,Enums.Commodity.SUGAR,Enums.Commodity.COTTON]:
		if commodity in state.current_global_demand: winners.append(score_commodity(commodity))
	# §4.1.13은 '모든 수요 보상'을 요구한다. 이벤트로 4종이 됐다면 4종 모두 필요하다.
	if winners.size() < 3 or winners[0] == Enums.Side.NONE: return Enums.Side.NONE
	return winners[0] if winners.all(func(w): return w == winners[0]) else Enums.Side.NONE


func commodity_reward(commodity: int) -> Array:
	# 화면의 세계 수요와 실제 득점이 같은 표를 읽는다. 반환 순서는
	# [승점, 채무 변화, 조약점수]이며 양수 채무는 이득이 아닌 강제 차입이다.
	# Calico Acts도 같은 수요 보상표를 사용한다. 특정 카드에 VP를 하드코딩하면
	# 시대별 부채·조약 보상과 내각 효과가 빠지므로 공통 판정 함수를 호출한다.
	# 보드의 수요 표 위에서 아래 순서. 부채 보상·벌점도 시대별로 달라진다 (§4.1.12).
	var order = [Enums.Commodity.FUR, Enums.Commodity.SPICE, Enums.Commodity.FISH, Enums.Commodity.TOBACCO, Enums.Commodity.SUGAR, Enums.Commodity.COTTON]
	# 각 항목은 [VP, 부채 변화, 조약 점수]. 양수 부채는 강제 차입이다.
	var rewards = [
		[[2,0,1],[1,-1,0],[2,1,0],[3,1,0],[2,0,0],[2,0,1]],
		[[2,0,1],[2,-1,0],[2,0,0],[2,1,0],[3,0,1],[2,0,1]],
		[[1,0,0],[3,-1,0],[2,0,0],[1,1,0],[3,0,0],[3,0,0]]]
	var index = order.find(commodity)
	return rewards[state.current_era][index].duplicate() if index >= 0 else []

func score_commodity(commodity: int) -> Enums.Side:
	var reward = commodity_reward(commodity)
	if reward.is_empty(): return Enums.Side.NONE
	var br = _count_commodity_markets(Enums.Side.BRITAIN, commodity)
	var fr = _count_commodity_markets(Enums.Side.FRANCE, commodity)
	var side = Enums.Side.NONE if br == fr else (Enums.Side.BRITAIN if br > fr else Enums.Side.FRANCE)
	if side == Enums.Side.NONE: return side
	state.score_vp(side, reward[0])
	var player = state.get_player(side)
	if reward[1] < 0: player.reduce_debt(-reward[1])
	elif reward[1] > 0: player.incur_debt(reward[1])
	player.add_treaty_points(reward[2])
	MinistryEffects.commodity_award(side,commodity)
	return side


func _victory_check_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.VICTORY_CHECK
	phase_changed.emit(Enums.TurnPhase.VICTORY_CHECK)
	# Per §2.5: check auto-victory by sweep first
	if _swept_awards_winner != Enums.Side.NONE and _swept_awards_winner == _swept_demand_winner:
		state.current_phase = Enums.GamePhase.GAME_OVER
		_declare_victory(_swept_awards_winner,"한 턴의 지역 보상과 세계 수요 독점")
		return
	# Then VP-based auto-victory
	var winner := state.check_auto_victory()
	if winner != Enums.Side.NONE:
		state.current_phase = Enums.GamePhase.GAME_OVER
		_declare_victory(winner,"승점 트랙의 자동 승리 조건 달성")
		return

	if state.current_turn == 6:
		_final_scoring()
	else:
		_advance_to_next_turn()


func _final_scoring() -> void:
	state.current_turn_phase = Enums.TurnPhase.FINAL_SCORING
	phase_changed.emit(Enums.TurnPhase.FINAL_SCORING)

	_score_prestige()

	# Available Debt: 1 VP per 2 difference, max 4 VP
	var br_debt_avail := state.britain.available_debt()
	var fr_debt_avail := state.france.available_debt()
	if br_debt_avail > fr_debt_avail:
		var diff := br_debt_avail - fr_debt_avail
		state.score_vp(Enums.Side.BRITAIN, mini(diff / 2, 4))
	elif fr_debt_avail > br_debt_avail:
		var diff := fr_debt_avail - br_debt_avail
		state.score_vp(Enums.Side.FRANCE, mini(diff / 2, 4))

	# Each commodity controlled (more markets than opp): 1 VP
	for commodity in [Enums.Commodity.FISH, Enums.Commodity.FUR, Enums.Commodity.SPICE,
			Enums.Commodity.SUGAR, Enums.Commodity.TOBACCO, Enums.Commodity.COTTON]:
		var br_c := _count_commodity_markets(Enums.Side.BRITAIN, commodity)
		var fr_c := _count_commodity_markets(Enums.Side.FRANCE, commodity)
		if br_c > fr_c:
			state.score_vp(Enums.Side.BRITAIN, 1)
		elif fr_c > br_c:
			state.score_vp(Enums.Side.FRANCE, 1)

	# Each friendly flag in opponent's starting Territory: 2 VP
	for sid in _initial_territories:
		var orig: Enums.Side = _initial_territories[sid]
		if not (sid in state.spaces): continue
		var ss = state.spaces[sid]
		var final_side = Enums.Side.FRANCE if ss.has_usa_flag else ss.controlled_by
		if final_side != orig and final_side != Enums.Side.NONE:
			state.score_vp(final_side, 2)

	vp_changed.emit(state.vp)

	var winner: Enums.Side
	if state.vp >= 16:
		winner = Enums.Side.FRANCE
	elif state.vp <= 14:
		winner = Enums.Side.BRITAIN
	elif br_debt_avail > fr_debt_avail:
		winner = Enums.Side.BRITAIN
	elif fr_debt_avail > br_debt_avail:
		winner = Enums.Side.FRANCE
	else:
		winner = Enums.Side.BRITAIN

	state.current_phase = Enums.GamePhase.GAME_OVER
	_declare_victory(winner,"6턴 종료 · 최종 득점")


func _advance_to_next_turn() -> void:
	state.current_turn += 1
	# 전쟁은 방금 끝난 평화 턴 2·3·4·5 뒤에 온다. 다음 턴 번호로 검사하면 AWI를 놓친다.
	if state.current_turn - 1 in [2, 3, 4, 5]:
		_check_war_before_next_turn()
	else:
		start_peace_turn()


func _check_war_before_next_turn() -> void:
	# Wars happen after turns 2, 3, 4, 5 (between peace turns)
	var prev := state.current_turn - 1
	if prev in [2, 3, 4, 5]:
		state.current_phase = Enums.GamePhase.WAR
		# The war for this period was already SET UP at the end of the previous turn's
		# war (or at game start for WSS). Now actually BEGIN the war (show UI).
		var war_id := WarManager.get_war_for_after_turn(prev)
		if war_id != "" and WarManager.current_war_id == war_id:
			WarManager.begin_war(war_id)
		elif war_id != "":
			# Setup was missed — set it up then begin
			WarManager.setup_war(war_id)
			WarManager.begin_war(war_id)
	else:
		start_peace_turn()


func resolve_war_and_continue() -> void:
	if WarFlow.active: return
	var results: Array = WarManager.resolve_full_war()
	# §2.5 #2: post-war max-margin sweep auto-victory
	var sweep_winner := _check_post_war_sweep(results)
	if sweep_winner != Enums.Side.NONE:
		state.current_phase = Enums.GamePhase.GAME_OVER
		_declare_victory(sweep_winner,"모든 전장에서 최대 전리품으로 승리")
		return
	# VP-based auto-victory
	var winner := state.check_auto_victory()
	if winner != Enums.Side.NONE:
		state.current_phase = Enums.GamePhase.GAME_OVER
		_declare_victory(winner,"전쟁 후 승점 자동 승리 조건 달성")
		return

	# Per rule 7.6 War Layout Phase: setup the NEXT war's basic tiles (silent)
	# Skip if this was the last war (American War of Independence after turn 5)
	var next_war := WarManager.get_war_for_after_turn(state.current_turn)
	if next_war != "":
		WarManager.setup_war(next_war)

	if state.current_turn > 6:
		_final_scoring()
	else:
		start_peace_turn()


func _declare_victory(winner: int,reason: String) -> void:
	state.winner=winner
	state.victory_reason=reason
	state.current_phase=Enums.GamePhase.GAME_OVER
	ActionController.reset_session()
	game_over.emit(winner)


func _count_flags_in_region(side: Enums.Side, region: Enums.Region) -> int:
	var count := 0
	for space_id in state.spaces:
		var ss: SpaceState = state.spaces[space_id]
		if ss.data.region == region and ss.controlled_by == side:
			if not ss.has_conflict_marker:
				count += 1
	return count


func _count_commodity_markets(side: Enums.Side, commodity: Enums.Commodity) -> int:
	var count := 0
	for space_id in state.spaces:
		var ss: SpaceState = state.spaces[space_id]
		if ss.data.space_type == Enums.SpaceType.MARKET and ss.data.commodity == commodity:
			if ss.controlled_by == side and not ss.has_conflict_marker:
				count += 1
	return count
