extends Node

# Manages Award tile distribution per turn and scoring.

var all_awards: Array = []  # Award tile data
var remaining_awards: Array = []
var turn_awards: Dictionary = {}  # region -> award entry


func _ready() -> void:
	_load_awards()


func _load_awards() -> void:
	var file := FileAccess.open("res://data/awards.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	all_awards = json.data


func assign_awards_for_era_start() -> void:
	assign_awards_for_turn(true)

func assign_awards_for_turn(new_era: bool) -> void:
	# §4.1.3: 앞선 턴에서 쓰인 타일은 제외하고, 시대의 두 번째 턴은 남은 4장으로 진행한다.
	if new_era:
		remaining_awards = all_awards.duplicate(true)
		remaining_awards.shuffle()
	turn_awards.clear()
	for region in ["europe", "north_america", "caribbean", "india"]:
		if not remaining_awards.is_empty():
			turn_awards[region] = remaining_awards.pop_back()


func get_award_for_region(region: Enums.Region) -> Dictionary:
	var key := _region_key(region)
	return turn_awards.get(key, {})


func score_region(region: Enums.Region, br_count: int, fr_count: int) -> int:
	# Returns Enums.Side of winner, or NONE if tie/no margin
	var award := get_award_for_region(region)
	if award.is_empty():
		return Enums.Side.NONE
	var margin: int = award.get("margin_required", 1)
	var diff := absi(br_count - fr_count)
	if diff < margin:
		return Enums.Side.NONE
	var winner: int = Enums.Side.NONE
	if br_count > fr_count:
		winner = Enums.Side.BRITAIN
	elif fr_count > br_count:
		winner = Enums.Side.FRANCE
	if winner != Enums.Side.NONE:
		var vp: int = award.get("vp", 2)
		GameManager.state.score_vp(winner, vp)
		var tp: int = award.get("tp", 0)
		if tp > 0:
			GameManager.state.get_player(winner).add_treaty_points(tp)
		# Ministry award modifiers (M-3 Sun King, M-18 Johnson, M-12 Dupleix)
		if has_node("/root/MinistryEffects"):
			MinistryEffects.apply_award_bonus(region, winner)
	return winner


func _region_key(region: Enums.Region) -> String:
	match region:
		Enums.Region.EUROPE: return "europe"
		Enums.Region.NORTH_AMERICA: return "north_america"
		Enums.Region.CARIBBEAN: return "caribbean"
		Enums.Region.INDIA: return "india"
	return ""
