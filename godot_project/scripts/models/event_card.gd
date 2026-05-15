class_name EventCard
extends Resource

@export var id: int
@export var era: Enums.Era
@export var title: String
@export var major_action: Enums.ActionType = Enums.ActionType.NONE
@export var bonus_condition: String = ""

@export var both_base: String = ""
@export var both_bonus: String = ""
@export var british_base: String = ""
@export var british_bonus: String = ""
@export var french_base: String = ""
@export var french_bonus: String = ""
@export var special_note: String = ""
@export var image: String = ""

var title_ko: String = ""
var both_base_ko: String = ""
var both_bonus_ko: String = ""
var british_base_ko: String = ""
var british_bonus_ko: String = ""
var french_base_ko: String = ""
var french_bonus_ko: String = ""
var special_note_ko: String = ""


func is_symmetric() -> bool:
	return both_base != "" and british_base == "" and french_base == ""


func has_bonus() -> bool:
	return bonus_condition != ""


func get_base_text(side: Enums.Side) -> String:
	if is_symmetric():
		return both_base
	if side == Enums.Side.BRITAIN:
		return british_base
	return french_base


func get_bonus_text(side: Enums.Side) -> String:
	if is_symmetric():
		return both_bonus
	if side == Enums.Side.BRITAIN:
		return british_bonus
	return french_bonus
