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
var bonus_condition_ko: String = ""
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


# --- Localized accessors: use Korean when locale is ko and translation exists ---
func _ko() -> bool:
	return LocaleManager.current_locale == "ko"


func disp_title() -> String:
	return title_ko if (_ko() and title_ko != "") else title


func disp_bonus_condition() -> String:
	return bonus_condition_ko if (_ko() and bonus_condition_ko != "") else bonus_condition


func disp_both_base() -> String:
	return both_base_ko if (_ko() and both_base_ko != "") else both_base


func disp_both_bonus() -> String:
	return both_bonus_ko if (_ko() and both_bonus_ko != "") else both_bonus


func disp_british_base() -> String:
	return british_base_ko if (_ko() and british_base_ko != "") else british_base


func disp_british_bonus() -> String:
	return british_bonus_ko if (_ko() and british_bonus_ko != "") else british_bonus


func disp_french_base() -> String:
	return french_base_ko if (_ko() and french_base_ko != "") else french_base


func disp_french_bonus() -> String:
	return french_bonus_ko if (_ko() and french_bonus_ko != "") else french_bonus


func disp_special_note() -> String:
	return special_note_ko if (_ko() and special_note_ko != "") else special_note
