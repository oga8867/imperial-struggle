class_name Advantage
extends Resource

@export var id: String
@export var name: String
@export var name_ko: String = ""
@export var region: Enums.Region
@export var sub_region: Enums.SubRegion = Enums.SubRegion.NONE
@export var connected_space_ids: Array[String] = []
@export var image_path: String = ""

# Runtime
var controlled_by: Enums.Side = Enums.Side.NONE
var is_exhausted: bool = false
var gained_this_round: bool = false


func is_controlled() -> bool:
	return controlled_by != Enums.Side.NONE


func reset_round() -> void:
	gained_this_round = false


func reset_exhaustion() -> void:
	is_exhausted = false


func can_use(any_connected_has_conflict: bool) -> bool:
	if controlled_by == Enums.Side.NONE:
		return false
	if is_exhausted:
		return false
	if gained_this_round:
		return false
	if any_connected_has_conflict:
		return false
	return true
