class_name InvestmentTile
extends Resource

@export var id: int
@export var major_action_type: Enums.ActionType
@export var major_action_points: int
@export var minor_action_type: Enums.ActionType
@export var minor_action_points: int = 2
@export var has_event_symbol: bool = false
@export var has_military_upgrade: bool = false


static func create(p_id: int, major_type: Enums.ActionType, major_pts: int,
		minor_type: Enums.ActionType, event: bool, upgrade: bool) -> InvestmentTile:
	var tile := InvestmentTile.new()
	tile.id = p_id
	tile.major_action_type = major_type
	tile.major_action_points = major_pts
	tile.minor_action_type = minor_type
	tile.has_event_symbol = event
	tile.has_military_upgrade = upgrade
	return tile
