class_name WarTile
extends Resource

enum TileType {
	BASIC,
	BONUS,
}

enum SpecialEffect {
	NONE,
	DEBT,
	DAMAGE_FORT_OR_REMOVE_SQUADRON,
	UNFLAG,
}

@export var id: String
@export var tile_type: TileType
@export var side: Enums.Side
@export var strength: int = 0
@export var special_effect: SpecialEffect = SpecialEffect.NONE
@export var war: Enums.War = Enums.War.SPANISH_SUCCESSION
@export var display_name: String = ""

@export var image: String = ""
var display_name_ko: String = ""
