extends Node

# Manages the current player's action round: tracking AP pools and validating space interactions.

signal ap_changed
signal action_state_changed(state_label: String)
signal action_round_ended

enum ActionState {
	IDLE,
	AWAITING_EVENT,
	SPENDING_MAJOR,
	SPENDING_MINOR,
	UPGRADING,
}

var state: ActionState = ActionState.IDLE

var current_side: Enums.Side = Enums.Side.NONE
var current_tile: InvestmentTile = null
var event_played: bool = false

var major_ap_remaining: int = 0
var minor_ap_remaining: int = 0
var event_ap_remaining: int = 0
var event_ap_type: Enums.ActionType = Enums.ActionType.NONE

var regions_used_major: Array[Enums.Region] = []
var regions_used_minor: Array[Enums.Region] = []

var minor_action_used_first_expense: bool = false
var bonus_tiles_bought_this_ar: int = 0

# Undo system: stack of state snapshots taken before each deterministic action
# Random actions (war tile draw, military upgrade) clear the stack
var _undo_stack: Array = []
const MAX_UNDO_DEPTH := 20


func begin_action_round(side: Enums.Side, tile: InvestmentTile) -> void:
	current_side = side
	current_tile = tile
	event_played = false
	major_ap_remaining = tile.major_action_points
	minor_ap_remaining = tile.minor_action_points

	# Ministry bonus AP
	if has_node("/root/MinistryEffects"):
		major_ap_remaining += MinistryEffects.get_extra_major_ap(side, tile.major_action_type)

	event_ap_remaining = 0
	event_ap_type = Enums.ActionType.NONE
	regions_used_major.clear()
	regions_used_minor.clear()
	minor_action_used_first_expense = false
	bonus_tiles_bought_this_ar = 0
	_undo_stack.clear()

	# Per §8.0: reset advantage per-AR counters at start of each AR
	if has_node("/root/AdvantageManager"):
		AdvantageManager.reset_round()

	if tile.has_event_symbol:
		_set_state(ActionState.AWAITING_EVENT)
	else:
		_set_state(ActionState.SPENDING_MAJOR)


func skip_event() -> void:
	if state == ActionState.AWAITING_EVENT:
		_set_state(ActionState.SPENDING_MAJOR)


func play_event(card: EventCard, use_bonus: bool = false) -> bool:
	if state != ActionState.AWAITING_EVENT:
		return false
	if not _can_play_event(card):
		return false

	var player := GameManager.state.get_player(current_side)
	player.hand.erase(card)
	# Per §5.2.5: played event is REMOVED FROM GAME (not in discard pile)
	# Keep it in event_played_pile for UI reference (browse played cards)
	GameManager.state.event_played_pile.append(card)
	event_played = true

	# Apply effects via EventEffects — per-card handlers manage AP grants too
	EventEffects.apply_event(card, current_side, use_bonus)

	if has_node("/root/GameLog"):
		var bonus_str := " (with bonus)" if use_bonus else ""
		GameLog.log_entry(current_side, "event", "played #%d %s%s" % [card.id, card.title, bonus_str])

	_set_state(ActionState.SPENDING_MAJOR)
	return true


func _can_play_event(card: EventCard) -> bool:
	if not current_tile.has_event_symbol:
		return false
	if card.major_action != Enums.ActionType.NONE:
		if current_tile.major_action_type != card.major_action:
			return false
	return true


func switch_to_major() -> void:
	if state in [ActionState.SPENDING_MINOR, ActionState.UPGRADING]:
		_set_state(ActionState.SPENDING_MAJOR)


func switch_to_minor() -> void:
	if state in [ActionState.SPENDING_MAJOR, ActionState.UPGRADING] and minor_ap_remaining > 0:
		_set_state(ActionState.SPENDING_MINOR)


func switch_to_upgrade() -> void:
	if current_tile.has_military_upgrade:
		_set_state(ActionState.UPGRADING)


func current_action_type() -> Enums.ActionType:
	if state == ActionState.SPENDING_MINOR:
		return current_tile.minor_action_type
	return current_tile.major_action_type


func ap_for_current() -> int:
	if state == ActionState.SPENDING_MINOR:
		return minor_ap_remaining
	var total := major_ap_remaining
	if event_ap_type == current_tile.major_action_type:
		total += event_ap_remaining
	return total


func can_spend_ap(amount: int) -> bool:
	return ap_for_current() >= amount


func spend_treaty_points_for_ap(amount: int = 1) -> int:
	# Per §9.0: TRP can be used as wild AP, must match current action type
	if state in [ActionState.IDLE, ActionState.AWAITING_EVENT]:
		return 0
	var player := GameManager.state.get_player(current_side)
	var actually := mini(amount, player.treaty_points)
	if actually <= 0:
		return 0
	player.treaty_points -= actually
	if state == ActionState.SPENDING_MINOR:
		minor_ap_remaining += actually
	else:
		major_ap_remaining += actually
	ap_changed.emit()
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "treaty", "spent %d Treaty Points for AP" % actually)
	return actually


func take_debt_for_ap(amount: int = 1) -> int:
	# Per §6.0: "A player may take Debt during their Action Round to increase their Action Points
	# for any action ... AP of the type matching the Major or Minor action on the player's
	# selected Investment tile, or from AP granted by an Event."
	# Allowed during AWAITING_EVENT too — augments Event AP.
	if state == ActionState.IDLE:
		return 0
	if current_side == Enums.Side.NONE:
		return 0
	var player := GameManager.state.get_player(current_side)
	_push_undo()
	var actually_taken := player.take_debt(amount)
	if actually_taken > 0:
		# Add to current pool (major or minor depending on state)
		if state == ActionState.SPENDING_MINOR:
			minor_ap_remaining += actually_taken
		else:
			# Major or AWAITING_EVENT: add to major pool
			major_ap_remaining += actually_taken
		ap_changed.emit()
		if has_node("/root/GameLog"):
			GameLog.log_entry(current_side, "debt", "took %d Debt for +%d AP" % [actually_taken, actually_taken])
	return actually_taken


func spend_ap(amount: int) -> bool:
	if not can_spend_ap(amount):
		return false
	if state == ActionState.SPENDING_MINOR:
		minor_ap_remaining -= amount
		minor_action_used_first_expense = true
	else:
		# Use event AP first if same type
		if event_ap_type == current_tile.major_action_type and event_ap_remaining > 0:
			var from_event := mini(amount, event_ap_remaining)
			event_ap_remaining -= from_event
			amount -= from_event
		major_ap_remaining -= amount
	ap_changed.emit()
	return true


func calculate_shift_cost(space_state: SpaceState, region_being_used: Enums.Region) -> int:
	if space_state == null:
		return 999
	var cost := space_state.get_effective_cost()
	# Isolated Market → 1 (§5.4.2)
	if space_state.data.space_type == Enums.SpaceType.MARKET:
		if space_state.is_isolated(GameManager.state.spaces):
			cost = 1
	# Protected: only Markets get +1 from protection (rule §5.4.2 Markets only)
	if space_state.data.space_type == Enums.SpaceType.MARKET:
		if _is_market_protected(space_state, _opponent_of(current_side)):
			cost += 1
	# Region switch cost: ONLY for Economic and Diplomatic actions (rule §5.3.4)
	var action_type := current_action_type()
	if action_type in [Enums.ActionType.ECONOMIC, Enums.ActionType.DIPLOMATIC]:
		var regions_used := regions_used_minor if state == ActionState.SPENDING_MINOR else regions_used_major
		if regions_used.size() > 0 and not regions_used.has(region_being_used):
			cost += 1
	# Conflict marker extra
	if space_state.has_conflict_marker and space_state.conflict_marker_extra_cost:
		cost += 1
	# Damaged opposing fort: +1 extra (rule §5.6.4)
	if space_state.data.space_type == Enums.SpaceType.FORT:
		if space_state.controlled_by == _opponent_of(current_side) and space_state.is_fort_damaged:
			cost += 1
	# Friendly damaged Fort repair: -1 (rule §5.6.4)
	if space_state.data.space_type == Enums.SpaceType.FORT:
		if space_state.controlled_by == current_side and space_state.is_fort_damaged:
			cost = maxi(0, cost - 1)
	return maxi(1, cost)


func _is_market_protected(space: SpaceState, by_side: Enums.Side) -> bool:
	# Per §3.2.8: A Protected space is a flagged space connected to a Squadron or undamaged Fort of its own side.
	# The check should be: space's owning side has connected protection
	if space.controlled_by != by_side:
		return false
	for conn_id in space.data.connections:
		if conn_id in GameManager.state.spaces:
			var conn: SpaceState = GameManager.state.spaces[conn_id]
			if conn.controlled_by != by_side:
				continue
			if conn.data.space_type == Enums.SpaceType.NAVAL:
				return true
			if conn.data.space_type == Enums.SpaceType.FORT and not conn.is_fort_damaged:
				return true
	return false


func can_shift_space(space_state: SpaceState) -> bool:
	if state not in [ActionState.SPENDING_MAJOR, ActionState.SPENDING_MINOR]:
		return false
	if space_state == null:
		return false

	var action_type := current_action_type()
	var allowed: bool = false
	match action_type:
		Enums.ActionType.ECONOMIC:
			allowed = space_state.data.space_type == Enums.SpaceType.MARKET
		Enums.ActionType.DIPLOMATIC:
			allowed = space_state.data.space_type == Enums.SpaceType.POLITICAL
		Enums.ActionType.MILITARY:
			allowed = space_state.data.space_type in [Enums.SpaceType.FORT, Enums.SpaceType.NAVAL]
	if not allowed:
		return false

	# Minor action restriction: can't remove opposing flags unless conflict marker present
	if state == ActionState.SPENDING_MINOR:
		if minor_action_used_first_expense:
			return false
		if space_state.controlled_by == _opponent_of(current_side) and not space_state.has_conflict_marker:
			return false

	# Economic: connection requirement
	if action_type == Enums.ActionType.ECONOMIC and space_state.data.space_type == Enums.SpaceType.MARKET:
		if not _market_has_connection(space_state):
			return false

	# Military Fort rules (rule 5.6.3 / 5.6.4)
	if action_type == Enums.ActionType.MILITARY and space_state.data.space_type == Enums.SpaceType.FORT:
		var opp := _opponent_of(current_side)
		if space_state.controlled_by == opp:
			# Cannot capture opposing Fort during peace UNLESS it is damaged
			if not space_state.is_fort_damaged:
				return false
			# Repairing/capturing opposing damaged Fort requires connected Market or Squadron
			if not _fort_capture_has_connection(space_state, current_side):
				return false
		elif space_state.controlled_by == Enums.Side.NONE:
			# Building in empty Fort space: must control connected Market/Naval/Territory
			if not _fort_build_has_connection(space_state, current_side):
				return false

	var cost := calculate_shift_cost(space_state, space_state.data.region)
	if not can_spend_ap(cost):
		return false
	return true


func _fort_build_has_connection(space: SpaceState, side: Enums.Side) -> bool:
	# Rule 5.6.3: must control at least one connected Market, Naval space, or Territory
	for conn_id in space.data.connections:
		if conn_id in GameManager.state.spaces:
			var conn: SpaceState = GameManager.state.spaces[conn_id]
			if conn.controlled_by != side:
				continue
			if conn.data.space_type in [Enums.SpaceType.MARKET, Enums.SpaceType.NAVAL, Enums.SpaceType.TERRITORY]:
				return true
	return false


func _fort_capture_has_connection(space: SpaceState, side: Enums.Side) -> bool:
	# Rule 5.6.4: capturing damaged opposing Fort requires connected Squadron or Market
	for conn_id in space.data.connections:
		if conn_id in GameManager.state.spaces:
			var conn: SpaceState = GameManager.state.spaces[conn_id]
			if conn.controlled_by != side:
				continue
			if conn.data.space_type == Enums.SpaceType.NAVAL:
				return true
			if conn.data.space_type == Enums.SpaceType.MARKET:
				return true
	return false


func construct_squadron() -> bool:
	# §5.6.5: cost 4 MP, place in Navy Box
	if current_action_type() != Enums.ActionType.MILITARY:
		return false
	if not can_spend_ap(4):
		return false
	var player := GameManager.state.get_player(current_side)
	if not player.can_build_squadron():
		return false
	_push_undo()
	if not spend_ap(4):
		return false
	player.squadrons_in_navy_box += 1
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "squadron", "constructed Squadron (-4 MP)")
	return true


func deploy_squadron_to(space_id: String) -> bool:
	# §5.6.6: 1 MP empty, 3 MP from Navy Box vs enemy, 2 MP from map vs enemy
	if not (space_id in GameManager.state.spaces):
		return false
	var ss: SpaceState = GameManager.state.spaces[space_id]
	if ss.data.space_type != Enums.SpaceType.NAVAL:
		return false
	if current_action_type() != Enums.ActionType.MILITARY:
		return false
	_push_undo()
	var player := GameManager.state.get_player(current_side)
	var opp := _opponent_of(current_side)
	var cost := 1
	if ss.controlled_by == opp:
		cost = 3 if player.squadrons_in_navy_box > 0 else 2
		if player.squadrons_on_map == 0 and player.squadrons_in_navy_box == 0:
			return false
	elif ss.controlled_by == current_side:
		return false  # already ours
	# Source: prefer Navy Box if cost matches, else use map
	if not can_spend_ap(cost):
		return false
	if not spend_ap(cost):
		return false
	# Deduct from source
	if ss.controlled_by == opp:
		# Displace opp squadron back to their navy box
		var opp_player := GameManager.state.get_player(opp)
		opp_player.squadrons_on_map -= 1
		opp_player.squadrons_in_navy_box += 1
		# Source: Navy Box (3 MP) preferred
		if cost == 3:
			player.squadrons_in_navy_box -= 1
		else:
			player.squadrons_on_map -= 1
	else:
		# Empty space: 1 MP — use Navy Box first
		if player.squadrons_in_navy_box > 0:
			player.squadrons_in_navy_box -= 1
		elif player.squadrons_on_map > 0:
			# Reposition (rule allows)
			player.squadrons_on_map -= 1
		else:
			return false
	player.squadrons_on_map += 1
	ss.controlled_by = current_side
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "squadron", "deployed to %s (-%d MP)" % [ss.data.display_name, cost])
	return true


func remove_conflict_marker(space_id: String) -> bool:
	# §5.6.2: 2 MP, or 1 MP if protected; +1 if marked
	if not (space_id in GameManager.state.spaces):
		return false
	var ss: SpaceState = GameManager.state.spaces[space_id]
	if not ss.has_conflict_marker:
		return false
	if current_action_type() != Enums.ActionType.MILITARY:
		return false
	_push_undo()
	var cost := 2
	if ss.data.space_type == Enums.SpaceType.MARKET:
		if _is_market_protected(ss, current_side):
			cost = 1
	if ss.conflict_marker_extra_cost:
		cost += 1
	if not can_spend_ap(cost):
		return false
	if not spend_ap(cost):
		return false
	ss.remove_conflict_marker()
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "conflict", "removed Conflict from %s (-%d MP)" % [ss.data.display_name, cost])
	return true


func _snapshot_state() -> Dictionary:
	# Capture the current state for undo (deterministic actions only)
	var snap := {
		"major_ap": major_ap_remaining,
		"minor_ap": minor_ap_remaining,
		"event_ap": event_ap_remaining,
		"event_ap_type": event_ap_type,
		"regions_used_major": regions_used_major.duplicate(),
		"regions_used_minor": regions_used_minor.duplicate(),
		"minor_used_first": minor_action_used_first_expense,
		"bonus_bought": bonus_tiles_bought_this_ar,
		"side_debt": GameManager.state.britain.current_debt if current_side == Enums.Side.BRITAIN else GameManager.state.france.current_debt,
		"side_trp": GameManager.state.britain.treaty_points if current_side == Enums.Side.BRITAIN else GameManager.state.france.treaty_points,
		"vp": GameManager.state.vp,
		"spaces": _snapshot_spaces(),
		"squadrons_navy_br": GameManager.state.britain.squadrons_in_navy_box,
		"squadrons_map_br": GameManager.state.britain.squadrons_on_map,
		"squadrons_navy_fr": GameManager.state.france.squadrons_in_navy_box,
		"squadrons_map_fr": GameManager.state.france.squadrons_on_map,
	}
	return snap


func _snapshot_spaces() -> Dictionary:
	var out := {}
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		out[sid] = {
			"control": ss.controlled_by,
			"conflict": ss.has_conflict_marker,
			"conflict_extra": ss.conflict_marker_extra_cost,
			"damaged": ss.is_fort_damaged,
		}
	return out


func _push_undo() -> void:
	_undo_stack.append(_snapshot_state())
	if _undo_stack.size() > MAX_UNDO_DEPTH:
		_undo_stack.pop_front()


func clear_undo_stack() -> void:
	_undo_stack.clear()


func can_undo() -> bool:
	return _undo_stack.size() > 0


func undo_last() -> bool:
	if _undo_stack.is_empty():
		return false
	var snap = _undo_stack.pop_back()
	major_ap_remaining = snap["major_ap"]
	minor_ap_remaining = snap["minor_ap"]
	event_ap_remaining = snap["event_ap"]
	event_ap_type = snap["event_ap_type"]
	regions_used_major = snap["regions_used_major"]
	regions_used_minor = snap["regions_used_minor"]
	minor_action_used_first_expense = snap["minor_used_first"]
	bonus_tiles_bought_this_ar = snap["bonus_bought"]
	if current_side == Enums.Side.BRITAIN:
		GameManager.state.britain.current_debt = snap["side_debt"]
		GameManager.state.britain.treaty_points = snap["side_trp"]
	else:
		GameManager.state.france.current_debt = snap["side_debt"]
		GameManager.state.france.treaty_points = snap["side_trp"]
	GameManager.state.vp = snap["vp"]
	GameManager.state.britain.squadrons_in_navy_box = snap["squadrons_navy_br"]
	GameManager.state.britain.squadrons_on_map = snap["squadrons_map_br"]
	GameManager.state.france.squadrons_in_navy_box = snap["squadrons_navy_fr"]
	GameManager.state.france.squadrons_on_map = snap["squadrons_map_fr"]
	for sid in snap["spaces"]:
		if sid in GameManager.state.spaces:
			var ss: SpaceState = GameManager.state.spaces[sid]
			var s = snap["spaces"][sid]
			ss.controlled_by = s["control"]
			ss.has_conflict_marker = s["conflict"]
			ss.conflict_marker_extra_cost = s["conflict_extra"]
			ss.is_fort_damaged = s["damaged"]
	GameManager.vp_changed.emit(GameManager.state.vp)
	ap_changed.emit()
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "undo", "undid last action")
	return true


func attempt_shift(space_id: String) -> bool:
	if not (space_id in GameManager.state.spaces):
		return false
	var ss: SpaceState = GameManager.state.spaces[space_id]
	# Naval space → squadron deployment, not flag shift
	if ss.data.space_type == Enums.SpaceType.NAVAL and current_action_type() == Enums.ActionType.MILITARY:
		return deploy_squadron_to(space_id)
	# Fort capture/build/repair via shift (handled by can_shift_space rules)
	if not can_shift_space(ss):
		return false
	_push_undo()  # snapshot BEFORE applying
	var region := ss.data.region
	var cost := calculate_shift_cost(ss, region)
	if not spend_ap(cost):
		return false

	if state == ActionState.SPENDING_MINOR:
		if not regions_used_minor.has(region):
			regions_used_minor.append(region)
	else:
		if not regions_used_major.has(region):
			regions_used_major.append(region)

	var was_empty := ss.is_empty()
	var was_opponent := ss.controlled_by != current_side and not ss.is_empty()

	# Special: opposing damaged Fort capture clears damage
	if (ss.data.space_type == Enums.SpaceType.FORT
			and ss.controlled_by == _opponent_of(current_side)
			and ss.is_fort_damaged):
		ss.is_fort_damaged = false
		ss.controlled_by = current_side
	elif (ss.data.space_type == Enums.SpaceType.FORT
			and ss.controlled_by == current_side
			and ss.is_fort_damaged):
		# Friendly repair: just clear damage, no flag change
		ss.is_fort_damaged = false
	else:
		ss.shift(current_side)

	if has_node("/root/GameLog"):
		var verb := "flagged" if was_empty else ("unflagged" if was_opponent else "shifted")
		GameLog.log_entry(current_side, "shift", "%s [%s] (-%d AP)" % [verb, ss.data.display_name, cost], [space_id])
	# Per §8.0: recompute advantage control after every flag change
	if has_node("/root/AdvantageManager"):
		AdvantageManager.recompute_control()
	return true


func purchase_bonus_war_tile(theater_id: String) -> bool:
	# Per §5.6.1: 2 MP each, max 2 per AR; rule §5.3.2 also allows Minor Mil to buy ONE.
	if current_action_type() != Enums.ActionType.MILITARY:
		return false
	if bonus_tiles_bought_this_ar >= 2:
		return false
	# Minor action allows only ONE expenditure total
	if state == ActionState.SPENDING_MINOR and minor_action_used_first_expense:
		return false
	if not can_spend_ap(2):
		return false
	# Random action: clear undo stack (can't undo random draws)
	clear_undo_stack()
	if not spend_ap(2):
		return false
	if not WarManager.purchase_bonus_war_tile(current_side, theater_id):
		# Refund if WarManager refused
		if state == ActionState.SPENDING_MINOR:
			minor_ap_remaining += 2
		else:
			major_ap_remaining += 2
		ap_changed.emit()
		return false
	bonus_tiles_bought_this_ar += 1
	if has_node("/root/GameLog"):
		var theater_name := theater_id
		if WarManager.current_war_id != "" and WarManager.current_war_id in WarManager.wars:
			for t in WarManager.wars[WarManager.current_war_id].theaters:
				if t.id == theater_id:
					theater_name = t.name; break
		GameLog.log_entry(current_side, "war_tile", "bought Bonus War Tile in %s (-2 MP)" % theater_name)
	return true


func end_action_round() -> void:
	# Carry remaining minor/major AP forward? No - they're lost.
	current_tile = null
	current_side = Enums.Side.NONE
	_set_state(ActionState.IDLE)
	action_round_ended.emit()
	GameManager._end_action_round()


func can_end_action_round() -> bool:
	return state in [ActionState.SPENDING_MAJOR, ActionState.SPENDING_MINOR, ActionState.UPGRADING]


func _set_state(new_state: ActionState) -> void:
	state = new_state
	action_state_changed.emit(_state_label(new_state))


func _state_label(s: ActionState) -> String:
	match s:
		ActionState.IDLE: return "Idle"
		ActionState.AWAITING_EVENT: return "Play Event (or skip)"
		ActionState.SPENDING_MAJOR: return "Spending Major Action"
		ActionState.SPENDING_MINOR: return "Spending Minor Action"
		ActionState.UPGRADING: return "Military Upgrade"
	return ""


func _opponent_of(side: Enums.Side) -> Enums.Side:
	if side == Enums.Side.BRITAIN:
		return Enums.Side.FRANCE
	return Enums.Side.BRITAIN


func _market_has_connection(space: SpaceState) -> bool:
	# Per §5.4.1: shift if connected to controlled Territory/Fort/Naval, OR
	# friendly Market that does NOT contain conflict marker, IS NOT Isolated,
	# AND did not change control during the current AR.
	for conn_id in space.data.connections:
		if conn_id in GameManager.state.spaces:
			var conn: SpaceState = GameManager.state.spaces[conn_id]
			if conn.controlled_by == current_side:
				if conn.data.space_type in [Enums.SpaceType.TERRITORY, Enums.SpaceType.FORT, Enums.SpaceType.NAVAL]:
					return true
				if (conn.data.space_type == Enums.SpaceType.MARKET
						and not conn.has_conflict_marker
						and not _is_market_isolated(conn)):
					return true
	if space.data.connections.is_empty():
		return true
	return false


func _is_market_isolated(market: SpaceState) -> bool:
	# §5.4.1 Market is Isolated if it's flagged but cannot trace a chain of friendly-flagged Markets
	# free of Conflict markers to a controlled Territory/Fort/Naval space.
	if market.controlled_by == Enums.Side.NONE:
		return false  # Empty markets aren't "isolated" in rule sense
	var visited := {}
	return not _can_trace_to_anchor(market, market.controlled_by, visited)


func _can_trace_to_anchor(start: SpaceState, side: Enums.Side, visited: Dictionary) -> bool:
	if start.id in visited:
		return false
	visited[start.id] = true
	for conn_id in start.data.connections:
		if not (conn_id in GameManager.state.spaces):
			continue
		var conn: SpaceState = GameManager.state.spaces[conn_id]
		if conn.controlled_by != side:
			continue
		if conn.data.space_type in [Enums.SpaceType.TERRITORY, Enums.SpaceType.FORT, Enums.SpaceType.NAVAL]:
			return true
		if conn.data.space_type == Enums.SpaceType.MARKET and not conn.has_conflict_marker:
			if _can_trace_to_anchor(conn, side, visited):
				return true
	return false
