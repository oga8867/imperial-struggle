extends Node

# Manages Advantage tiles per rule §8.0:
# - A player gains an Advantage when they control ALL spaces connected to it
# - Loses it when any connected space stops being controlled by them
# - Can use once per turn, max 2/AR, max 1/region, not on same AR taken

signal advantage_gained(adv_id: String, side: Enums.Side)
signal advantage_lost(adv_id: String, side: Enums.Side)

var effect_rules: Dictionary = {}
var discounts: Array = []
var advantages: Dictionary = {}  # id -> Advantage
var _advantages_used_this_round: int = 0
var _regions_used_this_round: Array[Enums.Region] = []
var _connections_data: Dictionary = {}  # id -> {connected_spaces, region, effect, name}

# One-shot market shift-cost discount granted by economic advantages (Wheat/Fur Trade/Rum/Textiles...).
# Consumed by ActionController on the next Market shift by the owning side.
var pending_market_discount: int = 0
var pending_discount_side: int = Enums.Side.NONE

# Categories for each advantage's ACTIVATED effect (rule §8.0 + card text)
const CAT_CONFLICT := "conflict"       # place a Conflict marker in the region
const CAT_MARKET_DISCOUNT := "discount" # reduce next Market shift cost by 1
const CAT_DIPLO_SHIFT := "diplo"        # shift a Political space in the region
const CAT_NAVAL := "naval"              # build a Squadron cheaply (into Navy Box)
const CAT_SCORE := "score"              # immediate scoring benefit

const ADV_CATEGORY := {
	"algonquin_raids_adv": CAT_CONFLICT,
	"iroquois_raids_adv": CAT_CONFLICT,
	"patriot_agitation_adv": CAT_CONFLICT,
	"letters_of_marque_adv": CAT_CONFLICT,
	"pirate_havens_adv": CAT_CONFLICT,
	"power_struggle_adv": CAT_CONFLICT,
	"raids_and_incursions_adv": CAT_CONFLICT,
	"separatist_wars_adv": CAT_CONFLICT,
	"mediterranean_intrigue_adv": CAT_CONFLICT,
	"central_europe_conflict_adv": CAT_CONFLICT,
	"wheat_adv": CAT_MARKET_DISCOUNT,
	"fur_trade_adv": CAT_MARKET_DISCOUNT,
	"rum_adv": CAT_MARKET_DISCOUNT,
	"textiles_adv": CAT_MARKET_DISCOUNT,
	"fruit_adv": CAT_MARKET_DISCOUNT,
	"silk_adv": CAT_MARKET_DISCOUNT,
	"italy_influence_adv": CAT_DIPLO_SHIFT,
	"german_diplomacy_adv": CAT_DIPLO_SHIFT,
	"silesia_negotiations_adv": CAT_DIPLO_SHIFT,
	"baltic_trade_adv": CAT_DIPLO_SHIFT,
	"naval_bastion_adv": CAT_NAVAL,
	"slaving_contracts_adv": CAT_SCORE,
}


func _ready() -> void:
	effect_rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/advantage_rules.json"))
	_load_connections()
	_create_advantages()
	# Listen for state changes to recompute control
	GameManager.action_round_started.connect(func(_s, _r): recompute_control())


func _load_connections() -> void:
	var path := "res://data/advantage_connections.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return
	_connections_data = json.data.get("advantages", {})


func _create_advantages() -> void:
	advantages.clear()
	for adv_id in _connections_data:
		var data: Dictionary = _connections_data[adv_id]
		var adv := Advantage.new()
		adv.id = adv_id
		adv.name = data.get("name", adv_id)
		adv.name_ko = effect_rules.get(adv_id,{}).get("name_ko",adv.name)
		adv.region = _parse_region(data.get("region", "europe"))
		adv.connected_space_ids.clear()
		for sid in data.get("connected_spaces", []):
			adv.connected_space_ids.append(str(sid))
		advantages[adv_id] = adv


func recompute_control() -> void:
	# Per §8.0: A player controls an advantage if they control ALL connected spaces
	# without conflict markers. Once gained, only lost when a connected space's flag
	# is REMOVED (not just conflict-marked).
	if GameManager.state == null:
		return
	for adv_id in advantages:
		var adv: Advantage = advantages[adv_id]
		if adv.connected_space_ids.is_empty():
			continue
		var br_controls := _all_controlled_by(adv, Enums.Side.BRITAIN, true)
		var fr_controls := _all_controlled_by(adv, Enums.Side.FRANCE, true)
		var prev_controller := adv.controlled_by

		# Re-check if held: still hold UNLESS opponent broke the chain (flag actually removed)
		if adv.controlled_by != Enums.Side.NONE:
			var still_holds := _all_controlled_by(adv, adv.controlled_by, false)
			# false = ignore conflict markers; gainer keeps unless flag removed
			if not still_holds:
				adv.controlled_by = Enums.Side.NONE
				advantage_lost.emit(adv_id, prev_controller)

		if adv.controlled_by == Enums.Side.NONE:
			# Check who can now claim it (must control ALL spaces, no conflict markers)
			if br_controls and not fr_controls:
				adv.controlled_by = Enums.Side.BRITAIN
				adv.gained_this_round = true
				advantage_gained.emit(adv_id, Enums.Side.BRITAIN)
				if has_node("/root/GameLog"):
					GameLog.log_entry(Enums.Side.BRITAIN, "advantage", "gained %s" % adv.name)
			elif fr_controls and not br_controls:
				adv.controlled_by = Enums.Side.FRANCE
				adv.gained_this_round = true
				advantage_gained.emit(adv_id, Enums.Side.FRANCE)
				if has_node("/root/GameLog"):
					GameLog.log_entry(Enums.Side.FRANCE, "advantage", "gained %s" % adv.name)


func _all_controlled_by(adv: Advantage, side: Enums.Side, require_no_conflict: bool) -> bool:
	for sid in adv.connected_space_ids:
		if not (sid in GameManager.state.spaces):
			# 연결 데이터가 틀렸다면 빈 조건을 참으로 간주해 이점을 지급하지 않는다.
			return false
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by != side:
			return false
		if require_no_conflict and ss.has_conflict_marker:
			return false
	return true


func reset_round() -> void:
	_advantages_used_this_round = 0
	discounts.clear()
	_regions_used_this_round.clear()
	for adv_id in advantages:
		advantages[adv_id].reset_round()


func reset_exhaustion() -> void:
	for adv_id in advantages:
		advantages[adv_id].reset_exhaustion()


func can_activate(adv_id: String) -> bool:
	if not (adv_id in advantages):
		return false
	var adv: Advantage = advantages[adv_id]
	if adv.controlled_by == Enums.Side.NONE:
		return false
	if has_node("/root/GameManager") and GameManager.state:
		if GameManager.state.phasing_player != adv.controlled_by:
			return false
		if has_node("/root/ActionController"):
			var ac_state = ActionController.state
			if ac_state == ActionController.ActionState.IDLE:
				return false
			if ac_state == ActionController.ActionState.AWAITING_EVENT:
				return false
	if _advantages_used_this_round >= 2:
		return false
	if _regions_used_this_round.has(adv.region):
		return false
	if not _all_controlled_by(adv,adv.controlled_by,true): return false
	if EventEffects.has_pending() or ActionController.upgrade_drawn or ActionController.bonus_drawn: return false
	var rule: Dictionary = effect_rules[adv_id]
	if rule.kind in ["naval","construct"]:
		if ActionController.current_action_type() != Enums.ActionType.MILITARY or not ActionController.can_spend_ap(rule.cost,null,"advantage"): return false
		if rule.kind == "naval" and ActionController.state == ActionController.ActionState.SPENDING_MINOR: return false
		if rule.kind=="construct" and not GameManager.state.get_player(adv.controlled_by).can_build_squadron(): return false
	return adv.can_use(false)


func activate(adv_id: String) -> bool:
	if not can_activate(adv_id):
		return false
	var adv: Advantage = advantages[adv_id]
	ActionController.clear_undo_stack()
	ActionController.action_started = true
	adv.is_exhausted = true
	_advantages_used_this_round += 1
	_regions_used_this_round.append(adv.region)
	_apply_effect(adv)
	EventEffects._finalize_pending()
	# Ministry hooks that trigger when an Advantage is exhausted (M-13 Pompadour, M-19 James Watt)
	if has_node("/root/MinistryEffects"):
		MinistryEffects.on_advantage_exhausted(adv.controlled_by, adv.region)
	return true


func _apply_effect(adv: Advantage) -> void:
	var side = adv.controlled_by
	var rule: Dictionary = effect_rules[adv.id].duplicate(true)
	match rule.kind:
		"conflict":
			rule.side = side
			EventEffects._add_pending("place_conflict_marker_choice",rule)
		"discount":
			rule.side = side
			discounts.append(rule)
		"debt": GameManager.state.get_player(side).reduce_debt(rule.amount)
		"naval":
			if ActionController.spend_ap(rule.cost,null,"advantage"):
				EventEffects._add_pending("advantage_remove_naval",{"side":side})
		"construct":
			var cost = maxi(0,rule.cost-ActionController.event_construct_discount)
			if GameManager.state.get_player(side).can_build_squadron() and ActionController.spend_ap(cost,null,"construct"):
				GameManager.state.get_player(side).squadrons_in_navy_box += 1
	ActionController.ap_changed.emit()

func discounted_cost(side: int, target: SpaceState, type: int, base: int, consume: bool = false) -> int:
	# 모든 이점의 경제·외교 할인은 상대 깃발을 제거하는 한 번의 지출에만 적용된다.
	for rule in discounts.duplicate():
		if rule.side != side or rule.type != type: continue
		if target.controlled_by != WarManager._opp(side) and not rule.get("friendly_allowed",false): continue
		if rule.has("region") and rule.region != target.data.region: continue
		if rule.has("countries") and not rule.countries.any(func(c): return target.data.id.begins_with(c)): continue
		base = rule.fixed if rule.has("fixed") else base-rule.reduction
		if consume: discounts.erase(rule)
	return base


func _auto_place_conflict(region: int, side: int) -> void:
	var opp: int = Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
	# Prefer an enemy-flagged Market/Political in the region with no marker; else any such space
	var best: SpaceState = null
	var fallback: SpaceState = null
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.region != region:
			continue
		if ss.data.space_type != Enums.SpaceType.MARKET and ss.data.space_type != Enums.SpaceType.POLITICAL:
			continue
		if ss.has_conflict_marker:
			continue
		if ss.controlled_by == opp and best == null:
			best = ss
		elif fallback == null:
			fallback = ss
	var target := best if best != null else fallback
	if target != null and target.place_conflict_marker():
		_log(side, "%s에 분쟁마커 배치" % target.data.display_name)


func _auto_diplo_shift(region: int, side: int) -> void:
	var opp: int = Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
	# Prefer flagging an empty Political space; else unflag an enemy one, in the region
	var empty_target: SpaceState = null
	var enemy_target: SpaceState = null
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.region != region:
			continue
		if ss.data.space_type != Enums.SpaceType.POLITICAL:
			continue
		if ss.has_conflict_marker:
			continue
		if ss.is_empty() and empty_target == null:
			empty_target = ss
		elif ss.controlled_by == opp and enemy_target == null:
			enemy_target = ss
	var target := empty_target if empty_target != null else enemy_target
	if target != null and target.shift(side):
		_log(side, "%s 이동" % target.data.display_name)
		recompute_control()


func peek_market_discount(side: int) -> int:
	# Non-clearing lookup for cost preview.
	if pending_market_discount > 0 and pending_discount_side == side:
		return pending_market_discount
	return 0


func consume_market_discount(side: int) -> int:
	# Called by ActionController when a Market shift is resolved. Returns discount, then clears.
	if pending_market_discount > 0 and pending_discount_side == side:
		var d := pending_market_discount
		pending_market_discount = 0
		pending_discount_side = Enums.Side.NONE
		return d
	return 0


func _log(side: int, msg: String) -> void:
	if has_node("/root/GameLog"):
		GameLog.log_entry(side, "advantage", msg)


func _parse_region(s: String) -> Enums.Region:
	match s:
		"europe": return Enums.Region.EUROPE
		"north_america": return Enums.Region.NORTH_AMERICA
		"caribbean": return Enums.Region.CARIBBEAN
		"india": return Enums.Region.INDIA
	return Enums.Region.EUROPE
