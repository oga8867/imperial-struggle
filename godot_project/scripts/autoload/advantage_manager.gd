extends Node

# Manages Advantage tiles per rule §8.0:
# - A player gains an Advantage when they control ALL spaces connected to it
# - Loses it when any connected space stops being controlled by them
# - Can use once per turn, max 2/AR, max 1/region, not on same AR taken

signal advantage_gained(adv_id: String, side: Enums.Side)
signal advantage_lost(adv_id: String, side: Enums.Side)

var advantages: Dictionary = {}  # id -> Advantage
var _advantages_used_this_round: int = 0
var _regions_used_this_round: Array[Enums.Region] = []
var _connections_data: Dictionary = {}  # id -> {connected_spaces, region, effect, name}


func _ready() -> void:
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
		adv.name_ko = data.get("name", adv_id)
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
			# Missing space ID — skip silently (data may be incomplete)
			continue
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by != side:
			return false
		if require_no_conflict and ss.has_conflict_marker:
			return false
	return true


func reset_round() -> void:
	_advantages_used_this_round = 0
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
	return adv.can_use(false)


func activate(adv_id: String) -> bool:
	if not can_activate(adv_id):
		return false
	var adv: Advantage = advantages[adv_id]
	adv.is_exhausted = true
	_advantages_used_this_round += 1
	_regions_used_this_round.append(adv.region)
	return true


func _parse_region(s: String) -> Enums.Region:
	match s:
		"europe": return Enums.Region.EUROPE
		"north_america": return Enums.Region.NORTH_AMERICA
		"caribbean": return Enums.Region.CARIBBEAN
		"india": return Enums.Region.INDIA
	return Enums.Region.EUROPE
