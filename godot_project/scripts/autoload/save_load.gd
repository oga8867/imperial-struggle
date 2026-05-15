extends Node

# Save/Load using JSON serialization of GameState.

const SAVE_DIR := "user://saves"
const AUTOSAVE_NAME := "autosave"


func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func save_game(name: String = AUTOSAVE_NAME) -> bool:
	ensure_dir()
	var path := "%s/%s.json" % [SAVE_DIR, name]
	var data := _serialize()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


func load_game(name: String = AUTOSAVE_NAME) -> bool:
	var path := "%s/%s.json" % [SAVE_DIR, name]
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return false
	_deserialize(json.data)
	return true


func list_saves() -> Array:
	ensure_dir()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return []
	var files := []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			files.append(f.trim_suffix(".json"))
		f = dir.get_next()
	return files


# ----------- Serialization -----------

func _serialize() -> Dictionary:
	var s := GameManager.state
	if s == null:
		return {}
	var out := {
		"version": 1,
		"current_turn": s.current_turn,
		"current_era": s.current_era,
		"current_phase": s.current_phase,
		"current_turn_phase": s.current_turn_phase,
		"vp": s.vp,
		"initiative": s.initiative,
		"first_player": s.first_player,
		"phasing_player": s.phasing_player,
		"current_action_round": s.current_action_round,
		"current_global_demand": s.current_global_demand,
		"britain": _serialize_player(s.britain),
		"france": _serialize_player(s.france),
		"spaces": _serialize_spaces(s.spaces),
		"available_investment_tiles": _serialize_tiles(s.available_investment_tiles),
		"event_draw_pile_ids": _card_ids(s.event_draw_pile),
		"event_discard_pile_ids": _card_ids(s.event_discard_pile),
		"awards": AwardManager.turn_awards,
		"ai_enabled": AIController.enabled,
		"ai_side": AIController.ai_side,
	}
	return out


func _serialize_player(p: PlayerState) -> Dictionary:
	return {
		"side": p.side,
		"current_debt": p.current_debt,
		"debt_limit": p.debt_limit,
		"treaty_points": p.treaty_points,
		"squadrons_in_navy_box": p.squadrons_in_navy_box,
		"squadrons_on_map": p.squadrons_on_map,
		"action_rounds_taken": p.action_rounds_taken,
		"hand_ids": _card_ids(p.hand),
		"ministry_ids": _ministry_ids(p.ministry_cards),
	}


func _serialize_spaces(spaces: Dictionary) -> Array:
	var out := []
	for sid in spaces:
		var ss: SpaceState = spaces[sid]
		out.append({
			"id": sid,
			"controlled_by": ss.controlled_by,
			"has_conflict_marker": ss.has_conflict_marker,
			"conflict_marker_extra_cost": ss.conflict_marker_extra_cost,
			"is_fort_damaged": ss.is_fort_damaged,
			"has_usa_flag": ss.has_usa_flag,
		})
	return out


func _serialize_tiles(tiles: Array) -> Array:
	var out := []
	for t in tiles:
		out.append({
			"major": t.major_action_type,
			"major_pts": t.major_action_points,
			"minor": t.minor_action_type,
			"event": t.has_event_symbol,
			"upgrade": t.has_military_upgrade,
		})
	return out


func _card_ids(arr: Array) -> Array:
	var out := []
	for c in arr:
		if c is EventCard:
			out.append(c.id)
	return out


func _ministry_ids(arr: Array) -> Array:
	var out := []
	for c in arr:
		if c is MinistryCard:
			out.append(c.id)
	return out


# ----------- Deserialization -----------

func _deserialize(data: Dictionary) -> void:
	var s := GameState.new()
	s.current_turn = int(data.get("current_turn", 1))
	s.current_era = int(data.get("current_era", 0))
	s.current_phase = int(data.get("current_phase", 1))
	s.current_turn_phase = int(data.get("current_turn_phase", 0))
	s.vp = int(data.get("vp", 15))
	s.initiative = int(data.get("initiative", 2))
	s.first_player = int(data.get("first_player", 2))
	s.phasing_player = int(data.get("phasing_player", 2))
	s.current_action_round = int(data.get("current_action_round", 0))
	for c in data.get("current_global_demand", []):
		s.current_global_demand.append(int(c))

	_deserialize_player(s.britain, data.get("britain", {}))
	_deserialize_player(s.france, data.get("france", {}))

	# Re-init spaces from GameData, then apply state
	for sid in GameData.spaces:
		var sd: SpaceData = GameData.spaces[sid]
		s.spaces[sid] = SpaceState.new(sd)
		s.spaces[sid].controlled_by = sd.starting_control
	for entry in data.get("spaces", []):
		if entry["id"] in s.spaces:
			var ss: SpaceState = s.spaces[entry["id"]]
			ss.controlled_by = int(entry.get("controlled_by", 0))
			ss.has_conflict_marker = entry.get("has_conflict_marker", false)
			ss.conflict_marker_extra_cost = entry.get("conflict_marker_extra_cost", false)
			ss.is_fort_damaged = entry.get("is_fort_damaged", false)
			ss.has_usa_flag = entry.get("has_usa_flag", false)

	# Investment tiles
	for tile_data in data.get("available_investment_tiles", []):
		s.available_investment_tiles.append(InvestmentTile.create(
			0, int(tile_data["major"]), int(tile_data["major_pts"]),
			int(tile_data["minor"]), bool(tile_data["event"]), bool(tile_data["upgrade"])))

	# Restore card piles by ID lookup
	for cid in data.get("event_draw_pile_ids", []):
		var card := _find_event(int(cid))
		if card: s.event_draw_pile.append(card)
	for cid in data.get("event_discard_pile_ids", []):
		var card := _find_event(int(cid))
		if card: s.event_discard_pile.append(card)

	GameManager.state = s
	AwardManager.turn_awards = data.get("awards", {})
	if data.get("ai_enabled", false):
		AIController.enable_for(int(data.get("ai_side", 1)))
	else:
		AIController.disable()
	GameManager.phase_changed.emit(s.current_turn_phase)
	GameManager.vp_changed.emit(s.vp)


func _deserialize_player(p: PlayerState, data: Dictionary) -> void:
	p.current_debt = int(data.get("current_debt", 0))
	p.debt_limit = int(data.get("debt_limit", 4))
	p.treaty_points = int(data.get("treaty_points", 0))
	p.squadrons_in_navy_box = int(data.get("squadrons_in_navy_box", 0))
	p.squadrons_on_map = int(data.get("squadrons_on_map", 0))
	p.action_rounds_taken = int(data.get("action_rounds_taken", 0))

	p.hand.clear()
	for cid in data.get("hand_ids", []):
		var card := _find_event(int(cid))
		if card: p.hand.append(card)

	p.ministry_cards.clear()
	for mid in data.get("ministry_ids", []):
		var m := _find_ministry(str(mid))
		if m:
			m.is_in_play = true
			p.ministry_cards.append(m)


func _find_event(id: int) -> EventCard:
	for c in GameData.events:
		if c.id == id:
			return c
	return null


func _find_ministry(id: String) -> MinistryCard:
	for c in GameData.ministries:
		if c.id == id:
			return c
	return null
