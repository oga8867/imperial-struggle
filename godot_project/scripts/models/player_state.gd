class_name PlayerState
extends Resource

@export var side: Enums.Side
@export var current_debt: int = 0
@export var debt_limit: int = 4
@export var treaty_points: int = 0
@export var ministry_cards: Array[MinistryCard] = []
@export var hand: Array[EventCard] = []
@export var squadrons_in_navy_box: int = 0
@export var squadrons_on_map: int = 0
@export var bonus_war_tiles_used: int = 0

var selected_investment_tile = null
var action_rounds_taken: int = 0
var tiles_taken_this_turn: Array = []


func available_debt() -> int:
	return debt_limit - current_debt


func can_take_debt() -> bool:
	return current_debt < debt_limit


func take_debt(amount: int = 1) -> int:
	var actual := mini(amount, debt_limit - current_debt)
	current_debt += actual
	return actual


func reduce_debt(amount: int = 1) -> int:
	var actual := mini(amount, current_debt)
	current_debt -= actual
	return actual


func total_squadrons() -> int:
	return squadrons_in_navy_box + squadrons_on_map


func max_squadrons() -> int:
	return 8


func can_build_squadron() -> bool:
	return total_squadrons() < max_squadrons()


func add_treaty_points(amount: int) -> void:
	treaty_points += amount


func spend_treaty_points(amount: int) -> bool:
	if treaty_points >= amount:
		treaty_points -= amount
		return true
	return false


func reduce_excess_treaty_points() -> int:
	var excess := maxi(0, treaty_points - 4)
	treaty_points -= excess
	return excess


func get_revealed_ministry_cards() -> Array[MinistryCard]:
	var revealed: Array[MinistryCard] = []
	for card in ministry_cards:
		if card.is_revealed:
			revealed.append(card)
	return revealed


func has_keyword(keyword: String) -> bool:
	for card in ministry_cards:
		if card.is_revealed and card.has_keyword(keyword):
			return true
	return false


func reset_for_new_turn() -> void:
	action_rounds_taken = 0
	tiles_taken_this_turn.clear()
	selected_investment_tile = null
	for card in ministry_cards:
		card.reset_exhaustion()
