class_name SpaceData
extends Resource

@export var id: String
@export var display_name: String
@export var space_type: Enums.SpaceType
@export var region: Enums.Region
@export var sub_region: Enums.SubRegion = Enums.SubRegion.NONE
@export var base_cost: int = 1
@export var commodity: Enums.Commodity = Enums.Commodity.NONE
@export var is_prestige: bool = false
@export var is_alliance: bool = false
@export var is_local_alliance: bool = false
@export var war_dots: Array[Enums.War] = []
@export var connections: Array[String] = []
@export var conquest_line_connections: Array[String] = []
@export var conquest_cost: int = 1
@export var starting_control: Enums.Side = Enums.Side.NONE
@export var available_from_era: Enums.Era = Enums.Era.SUCCESSION
@export var connected_advantage: String = ""
