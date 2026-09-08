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

var townshend_commodity: int = Enums.Commodity.NONE
var selected_investment_tile = null
var squadrons_returning: Dictionary = {}
var squadrons_removed: int = 0
var action_rounds_taken: int = 0
var tiles_taken_this_turn: Array = []
var condorcet_free_event: bool = false  # M-25: play event without event symbol this AR


func available_debt() -> int:
	return debt_limit - current_debt


func can_take_debt() -> bool:
	return current_debt < debt_limit


func take_debt(amount: int = 1) -> int:
	var actual := mini(maxi(0, amount), maxi(0, debt_limit - current_debt))
	current_debt += actual
	return actual

func incur_debt(amount: int = 1) -> int:
	if side==Enums.Side.BRITAIN and amount>maxi(0,available_debt()):
		if MinistryDecisions.offer(side,["M-19"],{"kind":"forced_debt","side":side,"amount":amount}): return 0
	# §6.0b: 강제로 생긴 부채를 한도 때문에 받지 못하면 상대에게 그만큼 VP를 준다.
	var actual := take_debt(amount)
	if amount > actual and not (side==Enums.Side.BRITAIN and MinistryEffects._has(side,"M-19")):
		var opponent = Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
		GameManager.state.score_vp(opponent, amount - actual)
	elif amount>actual and side==Enums.Side.BRITAIN:
		MinistryEffects._reveal(side,"M-19")
	return actual


func reduce_debt(amount: int = 1) -> int:
	var actual := mini(maxi(0, amount), current_debt)
	current_debt -= actual
	return actual


func total_squadrons() -> int:
	return squadrons_in_navy_box + squadrons_on_map + squadrons_returning.values().reduce(func(total,n): return total+n,0)


func max_squadrons() -> int:
	return 8 - squadrons_removed


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
	var turn = GameManager.state.current_turn
	if squadrons_returning.has(turn):
		squadrons_in_navy_box += squadrons_returning[turn]
		squadrons_returning.erase(turn)
	action_rounds_taken = 0
	tiles_taken_this_turn.clear()
	selected_investment_tile = null
	for card in ministry_cards:
		card.reset_exhaustion()
