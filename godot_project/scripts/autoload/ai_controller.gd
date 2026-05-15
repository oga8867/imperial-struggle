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
	# 1. Decide event play
	if ActionController.state == ActionController.ActionState.AWAITING_EVENT:
		var card := _pick_event_to_play()
		if card != null:
			ActionController.play_event(card, true)
			# Resolve pending choices
			while EventEffects.has_pending():
				if not _resolve_pending():
					EventEffects.skip_choice(0)
		else:
			ActionController.skip_event()

	# 2. Spend Major AP on shifts
	while ActionController.major_ap_remaining > 0 or ActionController.event_ap_remaining > 0:
		var target := _find_best_shift_target(ActionController.current_action_type())
		if target == "":
			break
		var ok := ActionController.attempt_shift(target)
		if not ok:
			break

	# 2b. If military and have AP, buy bonus war tiles
	if ActionController.current_action_type() == Enums.ActionType.MILITARY:
		_try_buy_war_tiles()

	# 3. Switch to Minor and spend
	ActionController.switch_to_minor()
	while ActionController.minor_ap_remaining > 0 and ActionController.state == ActionController.ActionState.SPENDING_MINOR:
		var target := _find_best_shift_target(ActionController.current_action_type())
		if target == "":
			break
		var ok := ActionController.attempt_shift(target)
		if not ok:
			break

	# 4. Military upgrade if available
	if ActionController.current_tile and ActionController.current_tile.has_military_upgrade:
		WarManager.military_upgrade(ai_side, _pick_upgrade_theater())

	# 5. End the round
	ActionController.end_action_round()
	ai_action_taken.emit("AI completed action round")


func _pick_event_to_play() -> EventCard:
	var p := GameManager.state.get_player(ai_side)
	if p.hand.is_empty():
		return null
	# Pick the card whose major_action matches our tile's, or any if none matches
	var tile = ActionController.current_tile
	for card in p.hand:
		if tile.major_action_type == Enums.ActionType.NONE or card.major_action == Enums.ActionType.NONE or card.major_action == tile.major_action_type:
			return card
	return null


func _resolve_pending() -> bool:
	if not EventEffects.has_pending():
		return false
	var choice = EventEffects.pending_choices[0]
	# Find a valid space matching the choice constraints
	for sid in GameManager.state.spaces:
		if EventEffects.resolve_choice(0, sid):
			return true
	return false


func _try_buy_war_tiles() -> void:
	if WarManager.get_upcoming_war_id() == "":
		return
	var theaters = WarManager.get_upcoming_theaters()
	if theaters.is_empty():
		return
	var max_buys := 2
	while max_buys > 0 and ActionController.ap_for_current() >= 2:
		var theater_id = (theaters[randi() % theaters.size()] as TheaterData).id
		if not ActionController.spend_ap(2):
			break
		WarManager.purchase_bonus_war_tile(ai_side, theater_id)
		max_buys -= 1


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
	# Prefer cards with keywords matching upcoming war theaters
	available.sort_custom(func(a, b): return a.keywords.size() > b.keywords.size())
	return [available[0], available[1]]
