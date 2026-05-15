class_name MinistryCard
extends Resource

@export var id: String
@export var side: Enums.Side
@export var eras: Array[Enums.Era] = []
@export var title: String
@export var keywords: Array[String] = []
@export var abilities: String = ""
@export var image: String = ""

var title_ko: String = ""
var abilities_ko: String = ""

var is_revealed: bool = false
var is_in_play: bool = false
var exhausted_abilities: Dictionary = {}


func has_keyword(keyword: String) -> bool:
	return keywords.has(keyword)


func is_available_in_era(era: Enums.Era) -> bool:
	return eras.has(era)


func reveal() -> void:
	is_revealed = true


func exhaust_ability(ability_index: int = 0) -> void:
	exhausted_abilities[ability_index] = true


func is_ability_exhausted(ability_index: int = 0) -> bool:
	return exhausted_abilities.get(ability_index, false)


func reset_exhaustion() -> void:
	exhausted_abilities.clear()
