class_name SpaceState
extends RefCounted

var data: SpaceData
var controlled_by: Enums.Side = Enums.Side.NONE
var has_conflict_marker: bool = false
var conflict_marker_extra_cost: bool = false
var is_fort_damaged: bool = false
var has_usa_flag: bool = false
var huguenots_exhausted: bool = false
var has_huguenots: bool = false  # M-9 New World Huguenots marker (+1 conquest cost)
var is_available: bool = true


func _init(p_data: SpaceData = null) -> void:
	if p_data:
		data = p_data
		controlled_by = p_data.starting_control


func is_empty() -> bool:
	return controlled_by == Enums.Side.NONE


func is_controlled_by(side: Enums.Side) -> bool:
	return controlled_by == side


func flag(side: Enums.Side) -> bool:
	if has_usa_flag or not is_available: return false
	if is_empty():
		controlled_by = side
		remove_conflict_marker()
		return true
	return false


func unflag(side: Enums.Side) -> bool:
	if controlled_by == side:
		return false
	if controlled_by != Enums.Side.NONE and controlled_by != side:
		controlled_by = Enums.Side.NONE
		remove_conflict_marker()
		return true
	return false


func shift(side: Enums.Side) -> bool:
	if is_empty():
		return flag(side)
	elif controlled_by != side:
		return unflag(side)
	return false


func take_control(side: Enums.Side) -> bool:
	if has_usa_flag or not is_available: return false
	controlled_by = side
	if side==Enums.Side.BRITAIN: has_huguenots=false
	remove_conflict_marker()
	return true


func place_conflict_marker(extra_cost: bool = false) -> bool:
	if has_usa_flag or not is_available: return false
	if has_conflict_marker:
		return false
	if data.space_type == Enums.SpaceType.TERRITORY:
		return false
	if data.space_type == Enums.SpaceType.NAVAL:
		return false
	if data.space_type == Enums.SpaceType.FORT:
		return false
	has_conflict_marker = true
	conflict_marker_extra_cost = extra_cost
	return true


func remove_conflict_marker() -> void:
	has_conflict_marker = false
	conflict_marker_extra_cost = false


func get_effective_cost() -> int:
	# Per §5.4.2 Markets, §5.5.2 Political: conflict marker → 1
	# Markets ALSO have isolation → 1 (handled externally; pass via flag)
	var cost := data.base_cost
	if has_conflict_marker:
		cost = 1
	return cost


func is_isolated(all_spaces: Dictionary) -> bool:
	# Only Markets can be isolated. A Market is Isolated if it's flagged but cannot
	# trace a chain of friendly-flagged Markets (no conflict markers) to a controlled
	# Territory/Fort/Naval space.
	if data.space_type != Enums.SpaceType.MARKET:
		return false
	if controlled_by == Enums.Side.NONE:
		return false
	return not _trace_to_anchor(controlled_by, all_spaces, {})


func _trace_to_anchor(side: Enums.Side, all_spaces: Dictionary, visited: Dictionary) -> bool:
	if data.id in visited:
		return false
	visited[data.id] = true
	for conn_id in data.connections:
		if not (conn_id in all_spaces): continue
		var conn = all_spaces[conn_id]
		if conn.controlled_by != side: continue
		var t = conn.data.space_type
		if t == Enums.SpaceType.TERRITORY or t == Enums.SpaceType.FORT or t == Enums.SpaceType.NAVAL:
			return true
		if t == Enums.SpaceType.MARKET and not conn.has_conflict_marker:
			if conn._trace_to_anchor(side, all_spaces, visited):
				return true
	return false


func is_protected(all_spaces: Dictionary, side: Enums.Side) -> bool:
	if controlled_by != side:
		return false
	for conn_id in data.connections:
		if conn_id in all_spaces:
			var conn: SpaceState = all_spaces[conn_id]
			if conn.controlled_by == side:
				if conn.data.space_type == Enums.SpaceType.FORT and not conn.is_fort_damaged:
					return true
				if conn.data.space_type == Enums.SpaceType.NAVAL:
					return true
	return false
