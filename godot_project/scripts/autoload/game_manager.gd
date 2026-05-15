extends Node

signal phase_changed(phase: Enums.TurnPhase)
signal action_round_started(side: Enums.Side, round_num: int)
signal game_over(winner: Enums.Side)
signal vp_changed(new_vp: int)
signal player_action_required(side: Enums.Side, action_type: String)
signal status_message(text: String)

var state: GameState

# Pending sets for phases that need user input
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
	state = GameState.new()
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
		GameLog.log_separator("=== TURN %d (%s) ===" % [turn, _era_name(state.current_era)])

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

	# Ministry phase may pause for user input
	_begin_ministry_phase()


func _begin_ministry_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.MINISTRY_PHASE
	phase_changed.emit(Enums.TurnPhase.MINISTRY_PHASE)

	if state.is_new_era_turn():
		_ministry_pending_sides = [Enums.Side.BRITAIN, Enums.Side.FRANCE]
		_request_next_ministry_selection()
	else:
		_continue_after_ministry()


func _request_next_ministry_selection() -> void:
	if _ministry_pending_sides.is_empty():
		_continue_after_ministry()
		return
	var side: Enums.Side = _ministry_pending_sides[0]
	if has_node("/root/AIController") and AIController.enabled and AIController.ai_side == side:
		var picks: Array = AIController.decide_ministry_selection()
		var p := state.get_player(side)
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
	if state.is_new_era_turn():
		AwardManager.assign_awards_for_era_start()


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

	var pool := GameData.investment_tile_pool.duplicate()
	pool.shuffle()
	state.available_investment_tiles.clear()
	for i in range(mini(9, pool.size())):
		state.available_investment_tiles.append(pool[i])

	# Reshuffle discard into draw pile if needed
	if state.event_draw_pile.size() < 6 and state.event_discard_pile.size() > 0:
		state.event_draw_pile.append_array(state.event_discard_pile)
		state.event_discard_pile.clear()
		state.event_draw_pile.shuffle()

	for _i in range(3):
		if state.event_draw_pile.size() > 0:
			state.britain.hand.append(state.event_draw_pile.pop_back())
		if state.event_draw_pile.size() > 0:
			state.france.hand.append(state.event_draw_pile.pop_back())

	# Discard down to 3
	_discard_down_to_three(state.britain)
	_discard_down_to_three(state.france)


func _discard_down_to_three(player: PlayerState) -> void:
	while player.hand.size() > 3:
		# Auto-discard from front (could be replaced with player choice UI later)
		var card = player.hand.pop_front()
		state.event_discard_pile.append(card)


# Old _ministry_phase replaced by _begin_ministry_phase / complete_ministry_selection


func _initiative_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.INITIATIVE_PHASE
	phase_changed.emit(Enums.TurnPhase.INITIATIVE_PHASE)
	state.initiative = state.determine_initiative()
	# Auto-decision: initiative holder picks themselves to go first (common heuristic)
	state.first_player = state.initiative
	status_message.emit("%s holds Initiative — going first." % ("Britain" if state.initiative == Enums.Side.BRITAIN else "France"))


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
	action_round_started.emit(state.phasing_player, rnd)
	player_action_required.emit(state.phasing_player, "select_investment_tile")


func _opponent(side: Enums.Side) -> Enums.Side:
	return Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN


func _era_name(era: Enums.Era) -> String:
	match era:
		Enums.Era.SUCCESSION: return "Succession Era"
		Enums.Era.EMPIRE: return "Empire Era"
		Enums.Era.REVOLUTION: return "Revolution Era"
	return ""


func _check_post_war_sweep(results: Array) -> Enums.Side:
	# Per §2.5 #2: same player won every theater of the war by max margin
	if results.is_empty():
		return Enums.Side.NONE
	var first_winner = results[0].get("winner", Enums.Side.NONE)
	if first_winner == Enums.Side.NONE:
		return Enums.Side.NONE
	# Find the max possible margin from spoils tables
	for r in results:
		if r.get("winner") != first_winner:
			return Enums.Side.NONE
		# Check if margin is at "max" — typically 5+ in our spoils tables
		if r.get("margin", 0) < 5:
			return Enums.Side.NONE
	return first_winner


func select_investment_tile(side: Enums.Side, tile: InvestmentTile) -> void:
	var player := state.get_player(side)
	player.selected_investment_tile = tile
	state.available_investment_tiles.erase(tile)
	player.tiles_taken_this_turn.append(tile)
	ActionController.begin_action_round(side, tile)
	if has_node("/root/GameLog"):
		var maj_name: String = ["?", "Econ", "Dipl", "Mil"][tile.major_action_type]
		var min_name: String = ["?", "Econ", "Dipl", "Mil"][tile.minor_action_type]
		var symbols: Array[String] = []
		if tile.has_event_symbol: symbols.append("Event")
		if tile.has_military_upgrade: symbols.append("Upgrade")
		var sym_str := " + " + ", ".join(symbols) if symbols.size() > 0 else ""
		GameLog.log_entry(side, "tile", "took tile: Major %s/%d, Minor %s/2%s" % [
			maj_name, tile.major_action_points, min_name, sym_str])
	player_action_required.emit(side, "play_actions")


func pass_action_round(side: Enums.Side) -> void:
	var player := state.get_player(side)
	player.reduce_debt(2)
	_end_action_round()


func _end_action_round() -> void:
	var current_side := state.phasing_player
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
	var br_prestige := 0
	var fr_prestige := 0
	for space_id in state.spaces:
		var ss: SpaceState = state.spaces[space_id]
		if ss.data.is_prestige and ss.data.region == Enums.Region.EUROPE:
			if not ss.has_conflict_marker:
				if ss.controlled_by == Enums.Side.BRITAIN:
					br_prestige += 1
				elif ss.controlled_by == Enums.Side.FRANCE:
					fr_prestige += 1
	if fr_prestige > br_prestige:
		state.score_vp(Enums.Side.FRANCE, 2)
	elif br_prestige > fr_prestige:
		state.score_vp(Enums.Side.BRITAIN, 2)


func _score_global_demand() -> void:
	_score_global_demand_with_winner()


func _score_global_demand_with_winner() -> Enums.Side:
	var winners: Array[Enums.Side] = []
	for commodity in state.current_global_demand:
		var br_markets := _count_commodity_markets(Enums.Side.BRITAIN, commodity)
		var fr_markets := _count_commodity_markets(Enums.Side.FRANCE, commodity)
		if fr_markets > br_markets:
			state.score_vp(Enums.Side.FRANCE, 1)
			winners.append(Enums.Side.FRANCE)
		elif br_markets > fr_markets:
			state.score_vp(Enums.Side.BRITAIN, 1)
			winners.append(Enums.Side.BRITAIN)
		else:
			winners.append(Enums.Side.NONE)
	if winners.size() == 0: return Enums.Side.NONE
	var first := winners[0]
	if first == Enums.Side.NONE: return Enums.Side.NONE
	for w in winners:
		if w != first: return Enums.Side.NONE
	return first


func _victory_check_phase() -> void:
	state.current_turn_phase = Enums.TurnPhase.VICTORY_CHECK
	phase_changed.emit(Enums.TurnPhase.VICTORY_CHECK)
	# Per §2.5: check auto-victory by sweep first
	if _swept_awards_winner != Enums.Side.NONE and _swept_awards_winner == _swept_demand_winner:
		state.current_phase = Enums.GamePhase.GAME_OVER
		game_over.emit(_swept_awards_winner)
		return
	# Then VP-based auto-victory
	var winner := state.check_auto_victory()
	if winner != Enums.Side.NONE:
		state.current_phase = Enums.GamePhase.GAME_OVER
		game_over.emit(winner)
		return

	if state.current_turn == 6:
		_final_scoring()
	else:
		_advance_to_next_turn()


func _final_scoring() -> void:
	state.current_turn_phase = Enums.TurnPhase.FINAL_SCORING
	phase_changed.emit(Enums.TurnPhase.FINAL_SCORING)

	# Per §11.0: Prestige (2 VP) — more total Prestige spaces, including USA Political spaces if any USA flags
	var br_prestige := 0
	var fr_prestige := 0
	for sid in state.spaces:
		var ss: SpaceState = state.spaces[sid]
		if ss.data.is_prestige and not ss.has_conflict_marker:
			if ss.controlled_by == Enums.Side.BRITAIN: br_prestige += 1
			elif ss.controlled_by == Enums.Side.FRANCE: fr_prestige += 1
	# USA spaces count as French if any USA flags (§11.0)
	var has_usa := false
	for sid in state.spaces:
		if (state.spaces[sid] as SpaceState).has_usa_flag:
			has_usa = true; break
	if has_usa:
		# Add USA prestige spaces if they exist
		for sid in state.spaces:
			var ss = state.spaces[sid]
			if "usa" in sid.to_lower() and ss.data.is_prestige:
				fr_prestige += 1
	if fr_prestige > br_prestige:
		state.score_vp(Enums.Side.FRANCE, 2)
	elif br_prestige > fr_prestige:
		state.score_vp(Enums.Side.BRITAIN, 2)

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
		if ss.controlled_by != orig and ss.controlled_by != Enums.Side.NONE:
			state.score_vp(ss.controlled_by, 2)

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
	game_over.emit(winner)


func _advance_to_next_turn() -> void:
	state.current_turn += 1
	if state.current_turn in [2, 3, 4, 5]:
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
	var results: Array = WarManager.resolve_full_war()
	# §2.5 #2: post-war max-margin sweep auto-victory
	var sweep_winner := _check_post_war_sweep(results)
	if sweep_winner != Enums.Side.NONE:
		state.current_phase = Enums.GamePhase.GAME_OVER
		game_over.emit(sweep_winner)
		return
	# VP-based auto-victory
	var winner := state.check_auto_victory()
	if winner != Enums.Side.NONE:
		state.current_phase = Enums.GamePhase.GAME_OVER
		game_over.emit(winner)
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
