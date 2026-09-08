extends Node

# 카드를 얻었다는 알림과 공개 로그를 분리한다. UI는 자기 카드만 상세로 연다.
signal event_card_drawn(side: Enums.Side, card: EventCard)

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
	SPENDING_EVENT,
}

var state: ActionState = ActionState.IDLE

var current_side: Enums.Side = Enums.Side.NONE
var current_tile: InvestmentTile = null
# 각 이벤트 AP 묶음은 출처·사용 제한을 유지한다 (§5.2.3-4).
var event_grants: Array = []
var active_event_index = -1
var finished_pools: Array[String] = []
var spent_pools: Array[String] = []
var regions_by_type: Dictionary = {}
var regions_by_pool: Dictionary = {}
var upgrade_drawn: WarTile = null
var upgrade_theater = ""
var bonus_drawn: WarTile = null
var bonus_allowed_theaters: Array[String] = []
var turn6_conversion_type = Enums.ActionType.NONE
var event_construct_discount = 0
var event_diplomatic_discount = false
var event_played: bool = false
var action_started: bool = false
var upgrade_used: bool = false
var changed_markets: Array[String] = []
var deployed_squadrons: Array[String] = []
var round_start_control: Dictionary = {}
var round_start_isolated: Dictionary = {}

var major_ap_remaining: int = 0
var minor_ap_remaining: int = 0
var event_ap_remaining: int = 0
var event_ap_type: Enums.ActionType = Enums.ActionType.NONE

var regions_used_major: Array[Enums.Region] = []
var regions_used_minor: Array[Enums.Region] = []

var minor_action_used_first_expense: bool = false
var bonus_tiles_bought_this_ar: int = 0
var first_debt_taken_this_ar: bool = false

# Undo system: stack of state snapshots taken before each deterministic action
# Random actions (war tile draw, military upgrade) clear the stack
var _undo_stack: Array = []
const MAX_UNDO_DEPTH := 20


func begin_action_round(side: Enums.Side, tile: InvestmentTile) -> void:
	current_side = side
	current_tile = tile
	event_played = false
	EventEffects.current_card=null
	action_started = MinistryDecisions.pre_tile_action_used
	upgrade_used = false
	event_grants.clear()
	active_event_index = -1
	finished_pools.clear()
	spent_pools.clear()
	regions_by_type.clear()
	regions_by_pool.clear()
	upgrade_drawn = null
	bonus_drawn = null
	bonus_allowed_theaters.clear()
	turn6_conversion_type = Enums.ActionType.NONE
	event_construct_discount = 0
	event_diplomatic_discount = false
	changed_markets.clear()
	deployed_squadrons.clear()
	round_start_control.clear()
	round_start_isolated.clear()
	for sid in GameManager.state.spaces:
		var space: SpaceState = GameManager.state.spaces[sid]
		round_start_control[sid] = space.controlled_by
		if space.data.space_type == Enums.SpaceType.MARKET:
			round_start_isolated[sid] = space.is_isolated(GameManager.state.spaces)
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
	first_debt_taken_this_ar = false
	_undo_stack.clear()

	# Per §8.0: reset advantage per-AR counters at start of each AR
	if has_node("/root/AdvantageManager"):
		AdvantageManager.reset_round()

	MinistryEffects.round_start(side)
	var condorcet = MinistryEffects._card(side,"M-25")
	if tile.has_event_symbol or (condorcet and not condorcet.is_ability_exhausted(0)):
		_set_state(ActionState.AWAITING_EVENT)
	else:
		_set_state(ActionState.SPENDING_MAJOR)


func skip_event() -> void:
	if state == ActionState.AWAITING_EVENT:
		_set_state(ActionState.SPENDING_MAJOR)


func play_event(card: EventCard, use_bonus: bool = false) -> bool:
	if MinistryDecisions.has_pending(): return false
	if state != ActionState.AWAITING_EVENT:
		return false
	if not _can_play_event(card):
		return false
	if MinistryDecisions.offer_event(card,use_bonus): return false

	var player := GameManager.state.get_player(current_side)
	if card not in player.hand:
		return false
	if not current_tile.has_event_symbol or card.major_action not in [Enums.ActionType.NONE,current_tile.major_action_type]:
		if not MinistryEffects.event_exception(current_side,card,current_tile,true): return false
	player.hand.erase(card)
	action_started = true
	# Per §5.2.5: played event is REMOVED FROM GAME (not in discard pile)
	# Keep it in event_played_pile for UI reference (browse played cards)
	GameManager.state.event_played_pile.append(card)
	event_played = true

	# Apply effects via EventEffects — per-card handlers manage AP grants too
	var bonus_eligible = use_bonus and EventEffects.bonus_condition_met(card, current_side)
	EventEffects.apply_event(card, current_side, bonus_eligible)
	if bonus_eligible: MinistryEffects.bonus_received(current_side)

	if has_node("/root/GameLog"):
		var bonus_str := " (보너스 적용)" if bonus_eligible else ""
		GameLog.log_entry(current_side, "event", "#%d %s 사용%s" % [card.id, card.disp_title(), bonus_str])

	_set_state(ActionState.SPENDING_MAJOR)
	return true


func _can_play_event(card: EventCard) -> bool:
	if card==null or current_tile==null: return false
	if current_tile.has_event_symbol and card.major_action in [Enums.ActionType.NONE,current_tile.major_action_type]: return true
	return MinistryEffects.event_exception(current_side,card,current_tile)


func pool_key() -> String:
	if state == ActionState.SPENDING_MINOR: return "minor"
	if state == ActionState.SPENDING_EVENT: return "event_%d" % active_event_index
	return "major"

func can_switch_pool(key: String) -> bool:
	if MinistryDecisions.has_pending(): return false
	return current_tile != null and key not in finished_pools and not EventEffects.has_pending() and upgrade_drawn == null and bonus_drawn == null and state not in [ActionState.IDLE,ActionState.AWAITING_EVENT]

func _leave_pool(next_key: String) -> void:
	# 먼저 고른 것만으로는 행동이 시작되지 않는다. 실제 지출 후 전환하면 잔여 AP는 소멸한다.
	var previous = pool_key()
	if previous != next_key and previous in spent_pools:
		finished_pools.append(previous)
	clear_undo_stack()

func switch_to_major() -> void:
	if can_switch_pool("major"):
		_leave_pool("major")
		_set_state(ActionState.SPENDING_MAJOR)

func switch_to_minor() -> void:
	if can_switch_pool("minor"):
		_leave_pool("minor")
		_set_state(ActionState.SPENDING_MINOR)

func switch_to_event(index: int) -> void:
	if index < 0 or index >= event_grants.size(): return
	var key = "event_%d" % index
	if event_grants[index].pool != key or not can_switch_pool(key): return
	_leave_pool(key)
	active_event_index = index
	_set_state(ActionState.SPENDING_EVENT)

func switch_to_upgrade() -> void:
	if can_upgrade():
		_leave_pool("upgrade")
		_set_state(ActionState.UPGRADING)

func current_action_type() -> Enums.ActionType:
	if current_tile == null: return Enums.ActionType.NONE
	if state == ActionState.SPENDING_MINOR: return current_tile.minor_action_type
	if state == ActionState.SPENDING_EVENT and active_event_index >= 0: return event_grants[active_event_index].type
	return current_tile.major_action_type

func grant_event_ap(amount: int, ap_type: int, restrictions: Dictionary = {}) -> void:
	if amount <= 0: return
	for grant in event_grants:
		if grant.type == ap_type and grant.restrictions == restrictions and not grant.get("locked",false) and grant.pool not in spent_pools and grant.pool not in finished_pools:
			grant.amount += amount
			_sync_event_total()
			return
	var i = event_grants.size()
	event_grants.append({"amount":amount,"type":ap_type,"restrictions":restrictions,"pool":"event_%d" % i})
	_sync_event_total()

func assign_event_grant(index: int, destination: String) -> bool:
	if index < 0 or index >= event_grants.size() or not spent_pools.is_empty(): return false
	if event_grants[index].get("locked",false): return false
	var grant = event_grants[index]
	if destination == "major" and grant.type != current_tile.major_action_type: return false
	if destination == "minor" and grant.type != current_tile.minor_action_type: return false
	if destination not in ["major","minor","event_%d" % index]: return false
	grant.pool = destination
	ap_changed.emit()
	return true

func _sync_event_total() -> void:
	event_ap_remaining = 0
	event_ap_type = Enums.ActionType.NONE
	for grant in event_grants:
		event_ap_remaining += grant.amount
		if event_ap_type == Enums.ActionType.NONE: event_ap_type = grant.type

func ap_for_current(target: SpaceState = null, kind: String = "") -> int:
	if pool_key() in finished_pools: return 0
	var total = minor_ap_remaining if state == ActionState.SPENDING_MINOR else (0 if state == ActionState.SPENDING_EVENT else major_ap_remaining)
	for grant in event_grants:
		if grant.pool == pool_key() and _grant_allows(grant,target,kind): total += grant.amount
	return total

func _grant_allows(grant: Dictionary, target: SpaceState, kind: String) -> bool:
	var rules: Dictionary = grant.restrictions
	if rules.is_empty() or kind == "": return true
	if rules.has("kinds") and kind not in rules.kinds: return false
	if rules.keys().all(func(k): return k=="kinds"): return true
	if target == null: return false
	if rules.get("non_prestige",false) and target.data.is_prestige: return false
	if rules.has("region") and target.data.region != rules.region: return false
	if rules.has("countries") and not rules.countries.any(func(c): return target.data.id.begins_with(c)): return false
	if rules.get("unflag",false) and target.controlled_by != _opponent_of(current_side): return false
	if rules.get("flag_adjacent_market",false):
		if target.controlled_by != Enums.Side.NONE: return false
		var found = false
		for sid in target.data.connections:
			var other = GameManager.state.spaces.get(sid)
			if other and other.data.space_type == Enums.SpaceType.MARKET and other.controlled_by == current_side: found = true
		if not found: return false
	return true

func can_spend_ap(amount: int, target: SpaceState = null, kind: String = "") -> bool:
	if MinistryDecisions.has_pending(): return false
	if amount < 0 or state not in [ActionState.SPENDING_MAJOR,ActionState.SPENDING_MINOR,ActionState.SPENDING_EVENT]: return false
	if EventEffects.has_pending() or upgrade_drawn != null or bonus_drawn != null: return false
	if state == ActionState.SPENDING_MINOR and minor_action_used_first_expense: return false
	if pool_key() in MinistryEffects.active_flags.get("burke_europe",[]) and target!=null and target.data.region!=Enums.Region.EUROPE: return false
	return current_tile != null and ap_for_current(target,kind) >= amount

func reset_session() -> void:
	current_side = Enums.Side.NONE
	current_tile = null
	major_ap_remaining = 0
	minor_ap_remaining = 0
	event_ap_remaining = 0
	event_ap_type = Enums.ActionType.NONE
	event_played = false
	action_started = false
	event_grants.clear()
	finished_pools.clear()
	spent_pools.clear()
	upgrade_drawn=null
	bonus_drawn=null
	bonus_allowed_theaters.clear()
	upgrade_used=false
	_undo_stack.clear()
	_set_state(ActionState.IDLE)


func spend_treaty_points_for_ap(amount: int = 1) -> int:
	if MinistryDecisions.has_pending(): return 0
	if pool_key() in finished_pools or EventEffects.has_pending() or upgrade_drawn or bonus_drawn: return 0
	if state==ActionState.SPENDING_MINOR and minor_action_used_first_expense: return 0
	# Per §9.0: TRP can be used as wild AP, must match current action type
	if state not in [ActionState.SPENDING_MAJOR,ActionState.SPENDING_MINOR,ActionState.SPENDING_EVENT]:
		return 0
	var player := GameManager.state.get_player(current_side)
	var actually := mini(amount, player.treaty_points)
	if actually <= 0:
		return 0
	_push_undo()
	action_started=true
	player.treaty_points -= actually
	if state == ActionState.SPENDING_MINOR:
		minor_ap_remaining += actually
	elif state == ActionState.SPENDING_EVENT:
		event_grants[active_event_index].amount += actually
		_sync_event_total()
	else:
		major_ap_remaining += actually
	ap_changed.emit()
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "treaty", "조약점수 %d → 행동점수" % actually)
	return actually


func take_debt_for_ap(amount: int = 1) -> int:
	if amount<=0 or pool_key() in finished_pools or EventEffects.has_pending() or upgrade_drawn or bonus_drawn: return 0
	if state==ActionState.SPENDING_MINOR and minor_action_used_first_expense: return 0
	# Per §6.0: "A player may take Debt during their Action Round to increase their Action Points
	# for any action ... AP of the type matching the Major or Minor action on the player's
	# selected Investment tile, or from AP granted by an Event."
	# Allowed during AWAITING_EVENT too — augments Event AP.
	if state not in [ActionState.SPENDING_MAJOR,ActionState.SPENDING_MINOR,ActionState.SPENDING_EVENT]:
		return 0
	if current_side == Enums.Side.NONE:
		return 0
	if MinistryDecisions.offer_debt(amount): return 0
	var player := GameManager.state.get_player(current_side)
	_push_undo()
	var first_debt_bonus = MinistryEffects.get_first_debt_bonus(current_side) if not first_debt_taken_this_ar else 0
	var credit = MinistryEffects.bank_credit(current_side,amount)
	var actually_taken = player.take_debt(amount-credit)
	if credit>0:
		var rules: Dictionary = event_grants[active_event_index].restrictions if state==ActionState.SPENDING_EVENT else {}
		event_grants.append({"amount":credit,"type":Enums.ActionType.ECONOMIC,"restrictions":rules,"pool":pool_key(),"bank":true,"locked":true})
		_sync_event_total()
		action_started=true
		ap_changed.emit()
	if actually_taken > 0:
		action_started=true
		var ap_gain: int = actually_taken
		# M-23 Turgot: first Debt each AR is worth +1 AP (if more Available Debt than opponent)
		if not first_debt_taken_this_ar and has_node("/root/MinistryEffects"):
			ap_gain += first_debt_bonus
		first_debt_taken_this_ar = true
		# M-17 Merchant Banks hook (may grant TRP)
		if has_node("/root/MinistryEffects"):
			MinistryEffects.on_debt_taken(current_side, actually_taken)
		# Add to current pool (major or minor depending on state)
		if state == ActionState.SPENDING_MINOR:
			minor_ap_remaining += ap_gain
		elif state == ActionState.SPENDING_EVENT:
			event_grants[active_event_index].amount += ap_gain
			_sync_event_total()
		else:
			# Major or AWAITING_EVENT: add to major pool
			major_ap_remaining += ap_gain
		ap_changed.emit()
		if has_node("/root/GameLog"):
			GameLog.log_entry(current_side, "debt", "부채 %d 증가 → 행동점수 +%d" % [actually_taken, ap_gain])
	return actually_taken+credit


func spend_ap(amount: int, target: SpaceState = null, kind: String = "") -> bool:
	if not can_spend_ap(amount,target,kind): return false
	action_started = true
	if pool_key() not in spent_pools: spent_pools.append(pool_key())
	for grant in event_grants:
		if grant.pool == pool_key() and _grant_allows(grant,target,kind):
			var paid = mini(amount,grant.amount)
			if paid>0 and grant.get("bank",false): MinistryEffects.bank_credit_spent(current_side,paid)
			grant.amount -= paid
			amount -= paid
	if state == ActionState.SPENDING_MINOR:
		minor_ap_remaining -= amount
		minor_action_used_first_expense = true
	elif state == ActionState.SPENDING_MAJOR: major_ap_remaining -= amount
	_sync_event_total()
	ap_changed.emit()
	return true

func calculate_shift_cost(space_state: SpaceState, region_being_used: Enums.Region) -> int:
	if space_state == null or current_tile == null:
		return 999
	var cost = space_state.get_effective_cost()
	var is_market = space_state.data.space_type == Enums.SpaceType.MARKET
	if is_market and round_start_isolated.get(space_state.data.id, false):
		cost = 1
	# §5.4.2: 할인 후 최소 1을 적용하고, 보호·지역 전환에 따른 추가 비용을 붙인다.
	if is_market:
		cost = AdvantageManager.discounted_cost(current_side,space_state,current_action_type(),cost)
	if not is_market: cost = AdvantageManager.discounted_cost(current_side,space_state,current_action_type(),cost)
	if event_diplomatic_discount and space_state.controlled_by == Enums.Side.FRANCE and (space_state.data.id.begins_with("spain") or space_state.data.id.begins_with("austria")): cost -= 1
	cost -= MinistryEffects.passive_shift_discount(current_side, space_state.data.id, current_action_type())
	# 비용 증감 모두 적용한 뒤 최종 최소값 1 (§8.0 Rum 예시).
	if is_market and _is_market_protected(space_state, space_state.controlled_by):
		cost += 1
	if current_action_type() in [Enums.ActionType.ECONOMIC, Enums.ActionType.DIPLOMATIC] or space_state.data.space_type==Enums.SpaceType.POLITICAL:
		var regions = regions_by_type.get(current_action_type(), [])
		if not regions.is_empty() and region_being_used not in regions:
			cost += 1
	# +1 Conflict 마커는 군사적 제거 비용만 올린다. 경제·외교 shift는 보통 마커와 동일하다 (§3.8.1).
	if space_state.data.space_type == Enums.SpaceType.FORT and space_state.is_fort_damaged:
		cost += -1 if space_state.controlled_by == current_side else 1
	return maxi(1, cost)


func _is_market_protected(space: SpaceState, by_side: Enums.Side) -> bool:
	# Per §3.2.8: A Protected space is a flagged space connected to a Squadron or undamaged Fort of its own side.
	# The check should be: space's owning side has connected protection
	if by_side == Enums.Side.NONE or space.controlled_by != by_side:
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
	if state not in [ActionState.SPENDING_MAJOR, ActionState.SPENDING_MINOR, ActionState.SPENDING_EVENT]:
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
			if MinistryEffects.active_flags.get("jacobite",false) and ["ireland","scotland"].any(func(c):return space_state.data.id.begins_with(c)): allowed=true
	if not allowed:
		return false
	if space_state.has_usa_flag:
		return false
	if space_state.data.available_from_era > GameManager.state.current_era:
		return false
	if space_state.controlled_by == current_side and not (space_state.data.space_type == Enums.SpaceType.FORT and space_state.is_fort_damaged):
		return false

	# Minor action restriction: can't remove opposing flags unless conflict marker present
	if state == ActionState.SPENDING_MINOR:
		if minor_action_used_first_expense:
			return false
		if space_state.controlled_by == _opponent_of(current_side) and not space_state.has_conflict_marker and not MinistryEffects.minor_can_unflag(current_side,space_state):
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

	if space_state.data.id.begins_with("usa_"):
		if GameManager.state.current_turn != 6 or not GameManager.state.spaces.values().any(func(s): return s.has_usa_flag):
			return false
	if space_state.data.space_type == Enums.SpaceType.NAVAL:
		var plan = squadron_deployment_plan(space_state.data.id)
		return not plan.is_empty() and can_spend_ap(plan.cost,space_state,"naval")
	var cost := calculate_shift_cost(space_state, space_state.data.region)
	if not can_spend_ap(cost,space_state,"shift"):
		return false
	return true


func _fort_build_has_connection(space: SpaceState, side: Enums.Side) -> bool:
	# Rule 5.6.3: must control at least one connected Market, Naval space, or Territory
	for conn_id in space.data.connections:
		if conn_id in GameManager.state.spaces:
			var conn: SpaceState = GameManager.state.spaces[conn_id]
			if conn.controlled_by != side or round_start_control.get(conn_id,Enums.Side.NONE) != side:
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
	if current_tile == null or current_action_type() != Enums.ActionType.MILITARY:
		return false
	var cost = maxi(0,4-event_construct_discount)
	if not can_spend_ap(cost,null,"construct"):
		return false
	var player := GameManager.state.get_player(current_side)
	if not player.can_build_squadron():
		return false
	_push_undo()
	if not spend_ap(cost,null,"construct"):
		return false
	player.squadrons_in_navy_box += 1
	ap_changed.emit()
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "squadron", "함대 1척 건조 (군사 %d점 사용)" % cost)
	return true


func deploy_squadron_to(space_id: String, source_id: String = "") -> bool:
	var plan = squadron_deployment_plan(space_id, source_id)
	if plan.is_empty() or not can_spend_ap(plan.cost,GameManager.state.spaces[space_id],"naval"):
		return false
	_push_undo()
	if not spend_ap(plan.cost,GameManager.state.spaces[space_id],"naval"):
		return false
	var player = GameManager.state.get_player(current_side)
	var target: SpaceState = GameManager.state.spaces[space_id]
	var opponent = GameManager.state.get_opponent(current_side)
	if target.controlled_by == opponent.side:
		opponent.squadrons_in_navy_box += 1
	if plan.source == "navy":
		player.squadrons_in_navy_box -= 1
	else:
		GameManager.state.spaces[plan.source].controlled_by = Enums.Side.NONE
	target.controlled_by = current_side
	deployed_squadrons.append(space_id)
	_recount_squadrons()
	AdvantageManager.recompute_control()
	ap_changed.emit()
	GameLog.log_entry(current_side, "squadron", "%s 배치 (군사 %d점 사용)" % [target.data.name_ko,plan.cost], [space_id])
	return true

func squadron_deployment_plan(space_id: String, source_id: String = "") -> Dictionary:
	if current_tile == null or current_action_type() != Enums.ActionType.MILITARY:
		return {}
	if not space_id in GameManager.state.spaces:
		return {}
	var target: SpaceState = GameManager.state.spaces[space_id]
	if target.data.space_type != Enums.SpaceType.NAVAL or target.controlled_by == current_side:
		return {}
	if state == ActionState.SPENDING_MINOR and target.controlled_by != Enums.Side.NONE:
		return {}
	var player = GameManager.state.get_player(current_side)
	var source = source_id
	if source == "":
		if player.squadrons_in_navy_box > 0:
			source = "navy"
		else:
			for sid in GameManager.state.spaces:
				var ss = GameManager.state.spaces[sid]
				if ss.data.space_type == Enums.SpaceType.NAVAL and ss.controlled_by == current_side and sid not in deployed_squadrons:
					source = sid
					break
	if source == "navy":
		if player.squadrons_in_navy_box <= 0:
			return {}
	elif source in GameManager.state.spaces:
		var ss = GameManager.state.spaces[source]
		if ss.data.space_type != Enums.SpaceType.NAVAL or ss.controlled_by != current_side or source in deployed_squadrons:
			return {}
	else:
		return {}
	var cost = 1 if target.controlled_by == Enums.Side.NONE else (3 if source == "navy" else 2)
	return {"cost": cost, "source": source}

func _recount_squadrons() -> void:
	GameManager.state.britain.squadrons_on_map = 0
	GameManager.state.france.squadrons_on_map = 0
	for ss in GameManager.state.spaces.values():
		if ss.data.space_type == Enums.SpaceType.NAVAL and ss.controlled_by != Enums.Side.NONE:
			GameManager.state.get_player(ss.controlled_by).squadrons_on_map += 1


func remove_conflict_marker(space_id: String) -> bool:
	# §5.6.2: 2 MP, or 1 MP if protected; +1 if marked
	if not (space_id in GameManager.state.spaces):
		return false
	var ss: SpaceState = GameManager.state.spaces[space_id]
	if not ss.has_conflict_marker:
		return false
	if current_action_type() != Enums.ActionType.MILITARY:
		return false
	var cost := 2
	if ss.data.space_type == Enums.SpaceType.MARKET:
		if _is_market_protected(ss, current_side):
			cost = 1
	if ss.conflict_marker_extra_cost:
		cost += 1
	if not can_spend_ap(cost,ss,"conflict"):
		return false
	_push_undo()
	if not spend_ap(cost,ss,"conflict"):
		return false
	ss.remove_conflict_marker()
	AdvantageManager.recompute_control()
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "conflict", "%s 분쟁 제거 (군사 %d점 사용)" % [ss.data.name_ko, cost])
	return true


func _snapshot_state() -> Dictionary:
	# Capture the current state for undo (deterministic actions only)
	var snap := {
		"session": SaveLoad._serialize(),
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
	var previous = _undo_stack
	_undo_stack = []
	var snapshot = _snapshot_state()
	_undo_stack = previous
	_undo_stack.append(snapshot)
	if _undo_stack.size() > MAX_UNDO_DEPTH:
		_undo_stack.pop_front()


func clear_undo_stack() -> void:
	_undo_stack.clear()


func can_undo() -> bool:
	return _undo_stack.size() > 0


func undo_last() -> bool:
	if _undo_stack.is_empty(): return false
	var snapshot = _undo_stack.pop_back()
	var previous = _undo_stack
	if not SaveLoad._deserialize(snapshot.session): return false
	_undo_stack = previous
	GameManager.vp_changed.emit(GameManager.state.vp)
	_set_state(state)
	ap_changed.emit()
	return true


func attempt_shift(space_id: String) -> bool:
	if MinistryDecisions.has_pending(): return false
	if MinistryDecisions.offer_shift(space_id): return false
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
	if not spend_ap(cost,ss,"shift"):
		return false
	MinistryEffects.reveal_shift_benefit(current_side,ss,state==ActionState.SPENDING_MINOR)
	if not regions_by_type.has(current_action_type()): regions_by_type[current_action_type()] = []
	if region not in regions_by_type[current_action_type()]: regions_by_type[current_action_type()].append(region)
	if not regions_by_pool.has(pool_key()): regions_by_pool[pool_key()]=[]
	if region not in regions_by_pool[pool_key()]: regions_by_pool[pool_key()].append(region)

	if state == ActionState.SPENDING_MINOR:
		if not regions_used_minor.has(region):
			regions_used_minor.append(region)
	else:
		if not regions_used_major.has(region):
			regions_used_major.append(region)

	if ss.data.space_type == Enums.SpaceType.MARKET and not ss.data.id in changed_markets:
		changed_markets.append(ss.data.id)
	AdvantageManager.discounted_cost(current_side,ss,current_action_type(),0,true)
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

	# Consume one-shot Advantage market discount on a Market shift (rule §8.0)
	if ss.data.space_type == Enums.SpaceType.MARKET and has_node("/root/AdvantageManager"):
		AdvantageManager.consume_market_discount(current_side)

	if has_node("/root/GameLog"):
		var verb := "깃발 배치" if was_empty else ("깃발 제거" if was_opponent else "공간 변경")
		GameLog.log_entry(current_side, "shift", "%s [%s] (%s %d점 사용)" % [verb, ss.data.display_name, LocaleManager.action(current_action_type()), cost], [space_id])
	# Per §8.0: recompute advantage control after every flag change
	if has_node("/root/AdvantageManager"):
		AdvantageManager.recompute_control()
	# 점수 지출 직후의 신호와 별도로, 깃발 변경까지 반영된 표시를 갱신한다.
	ap_changed.emit()
	return true


func purchase_bonus_war_tile(theater_id: String) -> bool:
	# AI 편의 경로도 같은 검증과 소비를 사용한다.
	if not theater_id in WarManager.bonus_war_tiles_in_theater: return false
	if WarManager.bonus_war_tiles_in_theater[theater_id][current_side].size() >= 2: return false
	return begin_bonus_purchase() and place_bonus_tile(theater_id)

func begin_bonus_purchase() -> bool:
	if GameManager.state.current_turn == 6 or current_action_type() != Enums.ActionType.MILITARY: return false
	if bonus_tiles_bought_this_ar >= 2 or bonus_drawn != null: return false
	if WarManager.bonus_tile_pool.get(current_side,[]).is_empty(): return false
	if not WarManager.bonus_war_tiles_in_theater.values().any(func(t): return t[current_side].size()<2): return false
	bonus_allowed_theaters=bonus_purchase_theaters()
	if bonus_allowed_theaters.is_empty(): return false
	clear_undo_stack()
	action_started=true
	WarManager.bonus_tile_pool[current_side].shuffle()
	bonus_drawn = WarManager.bonus_tile_pool[current_side].pop_back()
	ap_changed.emit()
	return true

func remaining_for_pool(key: String) -> int:
	# 합산한 이벤트·내각 점수를 포함한 표시용 총량이다. 실제 지출 시에는
	# can_spend_ap가 대상과 용도를 다시 검사하므로 제한 점수가 만능 점수가 되지 않는다.
	if key in finished_pools: return 0
	if key == "minor" and minor_action_used_first_expense: return 0
	var total = major_ap_remaining if key == "major" else (minor_ap_remaining if key == "minor" else 0)
	for grant in event_grants:
		if grant.pool == key: total += grant.amount
	return total

func draw_event_block_reason() -> String:
	# UI와 AI가 같은 검증을 사용한다. 더미의 내용은 검사하지 않고 장수만 본다.
	# 혁명 시대의 왕위계승 카드는 실제로 뽑을 때 제거해야 비공개 정보를 누설하지 않는다.
	var s = GameManager.state
	if s == null or s.current_phase != Enums.GamePhase.PEACE_TURN or s.current_turn_phase != Enums.TurnPhase.ACTION_PHASE:
		return "자기 행동 라운드에 사용할 수 있습니다."
	if s.phasing_player != current_side: return "자기 차례에 사용할 수 있습니다."
	if current_action_type() != Enums.ActionType.DIPLOMATIC: return "외교 행동을 선택하세요."
	if s.event_draw_pile.is_empty(): return "뽑기 더미에 카드가 없습니다."
	if state == ActionState.SPENDING_MINOR and minor_action_used_first_expense:
		return "보조 행동은 한 번만 지출할 수 있습니다."
	if MinistryDecisions.has_pending() or EventEffects.has_pending() or upgrade_drawn or bonus_drawn or state == ActionState.AWAITING_EVENT:
		return "진행 중인 선택을 먼저 완료하세요."
	if not can_spend_ap(3, null, "draw_event"):
		return "카드 뽑기에 쓸 수 있는 외교 3점이 필요합니다."
	return ""

func can_draw_event() -> bool:
	return draw_event_block_reason().is_empty()

func draw_event_card() -> bool:
	# §5.5.3: 외교 3점 → 카드 1장. 카드 분배 단계와 달리 버림 더미를 재혼합하지 않는다.
	# 지역·국가·깃발 제거 전용 점수는 target=null, kind=draw_event를 통과하지 못한다.
	if not can_draw_event() or not spend_ap(3, null, "draw_event"): return false
	var card = GameManager._draw_event(false)
	if card != null: GameManager.state.get_player(current_side).hand.append(card)
	# 직전 채무 증가까지 되돌리면 이미 본 카드가 다시 더미에 들어간다. 정보가
	# 공개되는 경계에서 과거 실행 취소를 끊고, 이후의 일반 행동은 다시 취소할 수 있다.
	_undo_stack.clear()
	GameLog.log_entry(current_side, "draw_event", "외교 3점으로 이벤트 카드 1장 뽑기" if card else "외교 3점 사용 · 시대에 맞지 않는 카드를 제거한 뒤 더미 소진")
	ap_changed.emit()
	event_card_drawn.emit(current_side, card)
	return true

func _theater_payment_target(theater_id: String) -> SpaceState:
	# 지리 제한이 있는 MP는 배치할 전장의 지역으로 검증한다.
	var data=SpaceData.new()
	data.region=WarManager.wars[WarManager.current_war_id].theaters.filter(func(t): return t.id==theater_id)[0].region
	return SpaceState.new(data)

func bonus_purchase_theaters() -> Array[String]:
	var result: Array[String]=[]
	if GameManager.state.current_turn==6 or bonus_tiles_bought_this_ar>=2 or current_action_type()!=Enums.ActionType.MILITARY: return result
	for th in WarManager.get_upcoming_theaters():
		if can_spend_ap(2,_theater_payment_target(th.id),"war_tile"): result.append(th.id)
	return result

func place_bonus_tile(theater_id: String, relocate_index: int = -1, relocate_to: String = "") -> bool:
	if bonus_drawn == null or not theater_id in WarManager.bonus_war_tiles_in_theater: return false
	if theater_id not in bonus_allowed_theaters: return false
	var target: Array = WarManager.bonus_war_tiles_in_theater[theater_id][current_side]
	if target.size() >= 2:
		if relocate_to == theater_id or not relocate_to in WarManager.bonus_war_tiles_in_theater or relocate_index not in [0,1]: return false
		var destination: Array = WarManager.bonus_war_tiles_in_theater[relocate_to][current_side]
		if destination.size() >= 2: return false
	# 뽑기 이후 다른 행동을 막아 두었으므로 자원은 그대로다. 배치 지역을 고른
	# 순간 해당 지역에 쓸 수 있는 MP만 차감한다. 뽑은 타일은 취소할 수 없다.
	var drawn=bonus_drawn
	bonus_drawn = null
	if not spend_ap(2,_theater_payment_target(theater_id),"war_tile"):
		bonus_drawn=drawn
		return false
	if target.size()>=2: WarManager.bonus_war_tiles_in_theater[relocate_to][current_side].append(target.pop_at(relocate_index))
	target.append(drawn)
	bonus_tiles_bought_this_ar+=1
	bonus_allowed_theaters.clear()
	ap_changed.emit()
	return true


func can_flip_huguenots(id: String) -> bool:
	if current_tile==null or not GameManager.state.spaces.has(id) or EventEffects.has_pending() or bonus_drawn or upgrade_drawn: return false
	var ss=GameManager.state.spaces[id]
	return state in [ActionState.SPENDING_MAJOR,ActionState.SPENDING_MINOR,ActionState.SPENDING_EVENT] and ss.controlled_by==current_side and ss.has_huguenots and not ss.huguenots_exhausted

func flip_huguenots(id: String) -> bool:
	if not can_flip_huguenots(id): return false
	_push_undo()
	action_started=true
	var ss=GameManager.state.spaces[id]
	ss.huguenots_exhausted=true
	AdvantageManager.discounts.append({"side":current_side,"type":Enums.ActionType.ECONOMIC,"region":ss.data.region,"reduction":1,"friendly_allowed":true})
	ap_changed.emit()
	return true

func end_action_round() -> void:
	if not can_end_action_round():
		return
	# 사용하지 않은 AP는 라운드 종료와 함께 소멸한다.
	current_tile = null
	current_side = Enums.Side.NONE
	_set_state(ActionState.IDLE)
	action_round_ended.emit()
	GameManager._end_action_round()


func can_end_action_round() -> bool:
	if MinistryDecisions.has_pending(): return false
	return not EventEffects.has_pending() and upgrade_drawn == null and bonus_drawn == null and state in [ActionState.SPENDING_MAJOR, ActionState.SPENDING_MINOR, ActionState.SPENDING_EVENT, ActionState.UPGRADING]


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
						and conn.data.id not in changed_markets
						and not round_start_isolated.get(conn.data.id, false)):
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
	if start.data.id in visited:
		return false
	visited[start.data.id] = true
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

# 업그레이드에서 뽑은 타일은 UI가 아니라 저장되는 모델이 보유한다.
func can_upgrade() -> bool:
	return current_tile != null and current_tile.has_military_upgrade and not upgrade_used and can_switch_pool("upgrade")

func begin_upgrade(theater_id: String = "") -> bool:
	if not can_upgrade(): return false
	if GameManager.state.current_turn == 6:
		upgrade_used = true
		action_started = true
		GameManager.state.get_player(current_side).add_treaty_points(1)
		ap_changed.emit()
		return true
	if not theater_id in WarManager.basic_tile_in_theater or WarManager.basic_war_tiles[current_side].is_empty(): return false
	switch_to_upgrade()
	upgrade_used = true
	action_started = true
	upgrade_theater = theater_id
	WarManager.basic_war_tiles[current_side].shuffle()
	upgrade_drawn = WarManager.basic_war_tiles[current_side].pop_back()
	return true

func can_remove_upgrade_tile() -> bool:
	var total = WarManager.basic_war_tiles[current_side].size() + (1 if upgrade_drawn else 0)
	for th in WarManager.basic_tile_in_theater.values():
		if th.get(current_side) != null: total += 1
	return total > 4

func finish_upgrade(swap: bool, remove: bool) -> bool:
	if upgrade_drawn == null or (remove and not can_remove_upgrade_tile()): return false
	var discarded = upgrade_drawn
	if swap:
		discarded = WarManager.basic_tile_in_theater[upgrade_theater][current_side]
		WarManager.basic_tile_in_theater[upgrade_theater][current_side] = upgrade_drawn
	if not remove: WarManager.basic_war_tiles[current_side].append(discarded)
	upgrade_drawn = null
	upgrade_theater = ""
	if can_switch_pool("major"): switch_to_major()
	elif can_switch_pool("minor"): switch_to_minor()
	ap_changed.emit()
	return true

func convert_turn6_military(to_type: int) -> bool:
	if GameManager.state.current_turn != 6 or current_action_type() != Enums.ActionType.MILITARY: return false
	if to_type not in [Enums.ActionType.ECONOMIC,Enums.ActionType.DIPLOMATIC]: return false
	if turn6_conversion_type not in [Enums.ActionType.NONE,to_type]: return false
	var plan=conversion_plan()
	if plan.is_empty() or not spend_ap(2,plan.target,"conversion"): return false
	turn6_conversion_type = to_type
	# 전환 AP는 원래 행동과 별개의 주요 행동이다 (§5.6.1).
	# 이벤트 MP에 지리 제한이 있었다면 전환으로 제한을 우회하지 않는다 (§5.2.4).
	grant_event_ap(1,to_type,{} if plan.region<0 else {"region":plan.region})
	return true

func conversion_plan() -> Dictionary:
	if GameManager.state.current_turn!=6 or current_action_type()!=Enums.ActionType.MILITARY: return {}
	if can_spend_ap(2,null,"conversion"): return {"target":null,"region":-1}
	for region in [Enums.Region.EUROPE,Enums.Region.NORTH_AMERICA,Enums.Region.CARIBBEAN,Enums.Region.INDIA]:
		var data=SpaceData.new()
		data.region=region
		var target=SpaceState.new(data)
		if can_spend_ap(2,target,"conversion"): return {"target":target,"region":region}
	return {}

func explain_space(space_id: String) -> String:
	if not space_id in GameManager.state.spaces: return LocaleManager.tx("알 수 없는 공간입니다.")
	var ss: SpaceState = GameManager.state.spaces[space_id]
	var heading = LocaleManager.local_name(ss.data.display_name,ss.data.name_ko) + " · " + LocaleManager.region(ss.data.region)
	if EventEffects.has_pending():
		return heading + (LocaleManager.tx("\n이벤트 효과 대상으로 선택할 수 있습니다. (§5.2)") if EventEffects.is_valid_target(space_id) else LocaleManager.tx("\n현재 이벤트의 대상 조건에 맞지 않습니다. (§5.2)"))
	if current_tile == null: return heading+LocaleManager.tx("\n투자 타일을 먼저 선택하세요. (§5.1)")
	if ss.has_usa_flag: return heading+LocaleManager.tx("\n미국 깃발은 영구적이며 차지하거나 제거할 수 없습니다. (§10)")
	if ss.data.available_from_era > GameManager.state.current_era: return heading+LocaleManager.tx("\n이 공간은 다음 시대부터 사용할 수 있습니다. (§3.2)")
	if state == ActionState.AWAITING_EVENT: return heading+LocaleManager.tx("\n이벤트를 사용하거나 건너뛴 뒤 행동하세요. (§5.2)")
	if ss.has_conflict_marker and current_action_type()==Enums.ActionType.MILITARY and ss.data.space_type in [Enums.SpaceType.MARKET,Enums.SpaceType.POLITICAL]:
		var cost = (1 if _is_market_protected(ss,current_side) else 2)+(1 if ss.conflict_marker_extra_cost else 0)
		return heading+LocaleManager.tx("\n분쟁 제거: 군사 %d점 · %s (§5.6.2)") % [cost,LocaleManager.tx("사용 가능") if can_spend_ap(cost,ss,"conflict") else LocaleManager.tx("사용할 행동점수가 부족하거나 다른 선택이 대기 중입니다")]
	if can_shift_space(ss):
		var cost = squadron_deployment_plan(space_id).cost if ss.data.space_type==Enums.SpaceType.NAVAL else calculate_shift_cost(ss,ss.data.region)
		return heading+LocaleManager.tx("\n필요 비용 %s %d점 · 사용 가능한 점수 %d점\n%s") % [LocaleManager.action(current_action_type()),cost,ap_for_current(ss,"shift"),LocaleManager.tx("함대 출발지를 선택합니다. (§5.6.6)") if ss.data.space_type==Enums.SpaceType.NAVAL else LocaleManager.tx("기본 비용에 분쟁·고립·보호·지역 변경·할인을 반영했습니다. (§5.3–5.6)")]
	if state==ActionState.SPENDING_MINOR and minor_action_used_first_expense: return heading+LocaleManager.tx("\n보조 행동은 한 번만 지출할 수 있습니다. (§5.3.2)")
	if ss.controlled_by==current_side and not ss.is_fort_damaged: return heading+LocaleManager.tx("\n이미 내 진영이 지배하는 공간입니다.")
	if state==ActionState.SPENDING_MINOR and ss.controlled_by==_opponent_of(current_side) and not ss.has_conflict_marker: return heading+LocaleManager.tx("\n보조 행동으로 상대 깃발을 제거할 수 없습니다. (§5.3.2)")
	if current_action_type()==Enums.ActionType.ECONOMIC and ss.data.space_type==Enums.SpaceType.MARKET and not _market_has_connection(ss): return heading+LocaleManager.tx("\n지배 중인 영토·요새·함대 또는 이번 라운드에 바뀌지 않은 비고립 시장과 연결되어야 합니다. (§5.4.1)")
	if ss.data.space_type==Enums.SpaceType.FORT and ss.controlled_by==_opponent_of(current_side) and not ss.is_fort_damaged: return heading+LocaleManager.tx("\n온전한 상대 요새는 평화 턴에 차지할 수 없습니다. (§5.6.3)")
	if ss.data.space_type==Enums.SpaceType.FORT and ss.controlled_by==Enums.Side.NONE and not _fort_build_has_connection(ss,current_side): return heading+LocaleManager.tx("\n라운드 시작부터 지배하던 연결 시장·함대·영토가 필요합니다. (§5.6.3)")
	return heading+LocaleManager.tx("\n현재 행동 종류·행동점수 사용 제한·남은 점수 조건을 만족하지 않습니다. (§5.2–5.6)")
