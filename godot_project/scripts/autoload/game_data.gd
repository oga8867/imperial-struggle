extends Node

var events: Array[EventCard] = []
var ministries: Array[MinistryCard] = []
var spaces: Dictionary = {}
var investment_tile_pool: Array[InvestmentTile] = []


func _ready() -> void:
	_load_events()
	_load_ministries()
	_load_spaces()
	_load_korean_overrides()
	_create_investment_tiles()


func _load_korean_overrides() -> void:
	var ev_path := "res://data/events_ko.json"
	if FileAccess.file_exists(ev_path):
		var f := FileAccess.open(ev_path, FileAccess.READ)
		var json := JSON.new()
		if json.parse(f.get_as_text()) == OK:
			var data: Dictionary = json.data
			for c in events:
				var key := str(c.id)
				if key in data:
					c.title_ko = data[key].get("title", "")
	var mn_path := "res://data/ministries_ko.json"
	if FileAccess.file_exists(mn_path):
		var f := FileAccess.open(mn_path, FileAccess.READ)
		var json := JSON.new()
		if json.parse(f.get_as_text()) == OK:
			var data: Dictionary = json.data
			for c in ministries:
				if c.id in data:
					c.title_ko = data[c.id].get("title", "")


func _load_events() -> void:
	var file := FileAccess.open("res://data/events.json", FileAccess.READ)
	if not file:
		push_error("Cannot load events.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("Failed to parse events.json")
		return

	var data: Array = json.data
	for entry in data:
		var card := EventCard.new()
		card.id = int(entry["id"])
		card.era = _parse_era(entry["era"])
		card.title = entry["title"]
		card.major_action = _parse_action_type(entry.get("major_action"))
		card.bonus_condition = _safe_str(entry.get("bonus_condition"))
		card.both_base = _safe_str(entry.get("both_base"))
		card.both_bonus = _safe_str(entry.get("both_bonus"))
		card.british_base = _safe_str(entry.get("british_base"))
		card.british_bonus = _safe_str(entry.get("british_bonus"))
		card.french_base = _safe_str(entry.get("french_base"))
		card.french_bonus = _safe_str(entry.get("french_bonus"))
		card.special_note = _safe_str(entry.get("special_note"))
		card.image = _safe_str(entry.get("image"))
		events.append(card)


func _load_ministries() -> void:
	var file := FileAccess.open("res://data/ministries.json", FileAccess.READ)
	if not file:
		push_error("Cannot load ministries.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("Failed to parse ministries.json")
		return

	var data: Array = json.data
	for entry in data:
		var card := MinistryCard.new()
		card.id = entry["id"]
		card.side = Enums.Side.FRANCE if entry["side"] == "france" else Enums.Side.BRITAIN
		for era_str in entry["eras"]:
			card.eras.append(_parse_era(era_str))
		card.title = entry["title"]
		for kw in entry.get("keywords", []):
			card.keywords.append(kw)
		card.abilities = entry.get("abilities", "")
		card.image = _safe_str(entry.get("image"))
		ministries.append(card)


func _load_spaces() -> void:
	var file := FileAccess.open("res://data/spaces.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		return
	var data: Array = json.data
	for entry in data:
		var sd := SpaceData.new()
		sd.id = entry["id"]
		sd.display_name = entry.get("display_name", entry.get("name", ""))
		sd.space_type = _parse_space_type(entry["type"])
		sd.region = _parse_region(entry["region"])
		sd.base_cost = int(entry.get("base_cost", entry.get("cost", 1)))
		sd.commodity = _parse_commodity(entry.get("commodity", ""))
		sd.is_prestige = entry.get("is_prestige", entry.get("prestige", false))
		sd.is_alliance = entry.get("is_alliance", entry.get("alliance", false))
		sd.is_local_alliance = entry.get("is_local_alliance", entry.get("local_alliance", false))
		sd.starting_control = _parse_side(entry.get("starting_control", ""))
		sd.conquest_cost = int(entry.get("conquest_cost", 1))
		for conn in entry.get("connections", []):
			sd.connections.append(conn)
		for cline in entry.get("conquest_lines", []):
			sd.conquest_line_connections.append(cline)
		spaces[sd.id] = sd


func _create_investment_tiles() -> void:
	# Standard Imperial Struggle tile pattern (per Vassal images):
	# 2-pt Major: Event + Upgrade (X,C)
	# 3-pt Major: Event only (X)
	# 4-pt Major: no symbols
	# 6 tiles per major type (3 values × 2 minor types) = 18 total
	var tile_id := 0
	var configs: Array = []
	for major_type in [Enums.ActionType.ECONOMIC, Enums.ActionType.DIPLOMATIC, Enums.ActionType.MILITARY]:
		var minors: Array = _other_action_types(major_type)
		for major_pts in [2, 3, 4]:
			var has_event: bool = major_pts <= 3
			var has_upgrade: bool = major_pts == 2
			for minor in minors:
				configs.append([major_type, major_pts, minor, has_event, has_upgrade])

	for cfg in configs:
		tile_id += 1
		investment_tile_pool.append(
			InvestmentTile.create(tile_id, cfg[0], cfg[1], cfg[2], cfg[3], cfg[4])
		)


func _other_action_types(major: Enums.ActionType) -> Array:
	var out: Array = []
	for t in [Enums.ActionType.ECONOMIC, Enums.ActionType.DIPLOMATIC, Enums.ActionType.MILITARY]:
		if t != major: out.append(t)
	return out


func get_events_for_era(era: Enums.Era) -> Array[EventCard]:
	var result: Array[EventCard] = []
	for card in events:
		if card.era == era:
			result.append(card)
	return result


func get_ministries_for_side(side: Enums.Side) -> Array[MinistryCard]:
	var result: Array[MinistryCard] = []
	for card in ministries:
		if card.side == side:
			result.append(card)
	return result


func get_ministries_for_era(side: Enums.Side, era: Enums.Era) -> Array[MinistryCard]:
	var result: Array[MinistryCard] = []
	for card in ministries:
		if card.side == side and card.is_available_in_era(era):
			result.append(card)
	return result


func _parse_era(s) -> Enums.Era:
	if s == null:
		return Enums.Era.SUCCESSION
	match str(s):
		"succession": return Enums.Era.SUCCESSION
		"empire": return Enums.Era.EMPIRE
		"revolution": return Enums.Era.REVOLUTION
	return Enums.Era.SUCCESSION


func _parse_action_type(s) -> Enums.ActionType:
	if s == null:
		return Enums.ActionType.NONE
	match str(s):
		"economic": return Enums.ActionType.ECONOMIC
		"diplomatic": return Enums.ActionType.DIPLOMATIC
		"military": return Enums.ActionType.MILITARY
	return Enums.ActionType.NONE


func _parse_space_type(s: String) -> Enums.SpaceType:
	match s:
		"political": return Enums.SpaceType.POLITICAL
		"market": return Enums.SpaceType.MARKET
		"territory": return Enums.SpaceType.TERRITORY
		"naval": return Enums.SpaceType.NAVAL
		"fort": return Enums.SpaceType.FORT
	return Enums.SpaceType.POLITICAL


func _parse_region(s: String) -> Enums.Region:
	match s:
		"europe": return Enums.Region.EUROPE
		"north_america": return Enums.Region.NORTH_AMERICA
		"caribbean": return Enums.Region.CARIBBEAN
		"india": return Enums.Region.INDIA
	return Enums.Region.EUROPE


func _parse_commodity(s) -> Enums.Commodity:
	if s == null or s == "":
		return Enums.Commodity.NONE
	match str(s):
		"fish": return Enums.Commodity.FISH
		"fur": return Enums.Commodity.FUR
		"spice": return Enums.Commodity.SPICE
		"sugar": return Enums.Commodity.SUGAR
		"tobacco": return Enums.Commodity.TOBACCO
		"cotton": return Enums.Commodity.COTTON
	return Enums.Commodity.NONE


func _parse_side(s) -> Enums.Side:
	if s == null or s == "":
		return Enums.Side.NONE
	match str(s):
		"britain": return Enums.Side.BRITAIN
		"france": return Enums.Side.FRANCE
	return Enums.Side.NONE


func _safe_str(val) -> String:
	if val == null:
		return ""
	return str(val)
