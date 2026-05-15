extends Node

# Manages War data and resolution.

signal war_started(war_id: String)         # Emitted when entering WAR phase (UI shows)
signal war_setup(war_id: String)            # Emitted when tiles are placed (silent, peace-turn prep)
signal theater_resolved(theater_id: String, winner: Enums.Side, margin: int)
signal war_ended(war_id: String)
signal cp_awarded(side: Enums.Side, cp: int)

var wars: Dictionary = {}  # id -> WarData
var current_war_id: String = ""

# Per-war state
var basic_war_tiles: Dictionary = {}  # side -> Array of WarTile
var bonus_war_tiles_in_theater: Dictionary = {}  # theater_id -> {side: [WarTile]}
var basic_tile_in_theater: Dictionary = {}  # theater_id -> {side: WarTile}

var pending_cp: Dictionary = {}  # side -> int (Conquest Points to spend)
var current_theater_index: int = 0
var territory_refusals: Dictionary = {}  # side -> count
var bonus_tile_pool: Dictionary = {}  # side -> Array of WarTile (drawable)


func _create_bonus_pool() -> void:
	# Per Counter Manifest: 12 Bonus War Tiles per side per war (historically named)
	# Generic distribution (since names are flavor only — gameplay effects identical across wars):
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var pool: Array = []
		var configs := [
			# [count, strength, effect]
			[3, 1, WarTile.SpecialEffect.NONE],
			[3, 2, WarTile.SpecialEffect.NONE],
			[2, 3, WarTile.SpecialEffect.NONE],
			[1, 4, WarTile.SpecialEffect.NONE],
			[1, 2, WarTile.SpecialEffect.DEBT],
			[1, 2, WarTile.SpecialEffect.DAMAGE_FORT_OR_REMOVE_SQUADRON],
			[1, 1, WarTile.SpecialEffect.UNFLAG],
		]
		for cfg in configs:
			for i in range(cfg[0]):
				var t := WarTile.new()
				t.tile_type = WarTile.TileType.BONUS
				t.side = side
				t.strength = cfg[1]
				t.special_effect = cfg[2]
				pool.append(t)
		bonus_tile_pool[side] = pool


func purchase_bonus_war_tile(side: Enums.Side, theater_id: String) -> bool:
	if current_war_id == "":
		# Use upcoming war
		var upcoming := get_war_for_after_turn(GameManager.state.current_turn)
		if upcoming == "":
			return false
		current_war_id = upcoming
		setup_war(upcoming)

	if not (theater_id in bonus_war_tiles_in_theater):
		return false

	var theater_tiles: Array = bonus_war_tiles_in_theater[theater_id][side]
	if theater_tiles.size() >= 2:
		return false  # Max 2 per theater

	if not (side in bonus_tile_pool) or bonus_tile_pool[side].is_empty():
		return false

	bonus_tile_pool[side].shuffle()
	var tile = bonus_tile_pool[side].pop_back()
	theater_tiles.append(tile)
	return true


func military_upgrade(side: Enums.Side, theater_id: String) -> bool:
	# Replace basic war tile in theater with newly drawn one
	if current_war_id == "" or basic_war_tiles[side].is_empty():
		return false
	if not (theater_id in basic_tile_in_theater):
		return false
	var current_tile = basic_tile_in_theater[theater_id].get(side)
	if current_tile == null:
		return false

	basic_war_tiles[side].shuffle()
	var new_tile = basic_war_tiles[side].pop_back()

	# Always keep the better one
	if new_tile.strength > current_tile.strength:
		basic_tile_in_theater[theater_id][side] = new_tile
		basic_war_tiles[side].append(current_tile)
	else:
		basic_war_tiles[side].append(new_tile)
	return true


func get_upcoming_war_id() -> String:
	if current_war_id != "":
		return current_war_id
	return get_war_for_after_turn(GameManager.state.current_turn)


func get_upcoming_theaters() -> Array:
	var war_id := get_upcoming_war_id()
	if war_id == "" or not (war_id in wars):
		return []
	return (wars[war_id] as WarData).theaters


func _ready() -> void:
	_load_wars()
	_create_basic_tiles()
	_create_bonus_pool()


func _load_wars() -> void:
	var file := FileAccess.open("res://data/wars.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	for war_id in data:
		var war_d := WarData.new()
		war_d.id = war_id
		war_d.name = data[war_id]["name"]
		war_d.name_ko = data[war_id].get("name_ko", "")
		war_d.war_dot = int(data[war_id].get("war_dot", 1))
		for t in data[war_id]["theaters"]:
			var th := TheaterData.new()
			th.id = t["id"]
			th.name = t["name"]
			th.name_ko = t.get("name_ko", "")
			th.region = _parse_region(t["region"])
			for k in t.get("bonus_strength", []):
				th.bonus_strength_keys.append(k)
			th.spoils_table = t.get("spoils", [])
			for ter in t.get("additional_territories", []):
				th.additional_territories.append(ter)
			war_d.theaters.append(th)
		wars[war_id] = war_d


func _create_basic_tiles() -> void:
	# Per rulebook Counter Manifest: 16 Basic War Tiles per side
	# - 4× strength 0 + Debt effect
	# - 4× strength +1 (no effect)
	# - 3× strength +2 (no effect)
	# - 3× strength -1 + Unflag effect
	# - 2× strength 0 + Damage Fort/Remove Squadron effect
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var pool: Array = []
		var configs := [
			# [count, strength, effect]
			[4, 0, WarTile.SpecialEffect.DEBT],
			[4, 1, WarTile.SpecialEffect.NONE],
			[3, 2, WarTile.SpecialEffect.NONE],
			[3, -1, WarTile.SpecialEffect.UNFLAG],
			[2, 0, WarTile.SpecialEffect.DAMAGE_FORT_OR_REMOVE_SQUADRON],
		]
		for cfg in configs:
			for i in range(cfg[0]):
				var t := WarTile.new()
				t.tile_type = WarTile.TileType.BASIC
				t.side = side
				t.strength = cfg[1]
				t.special_effect = cfg[2]
				pool.append(t)
		basic_war_tiles[side] = pool


func get_war_for_after_turn(turn: int) -> String:
	match turn:
		2: return "spanish_succession"
		3: return "austrian_succession"
		4: return "seven_years"
		5: return "american_independence"
	return ""


func setup_war(war_id: String) -> void:
	# Silent setup: place basic war tiles for upcoming war. Does NOT show UI.
	current_war_id = war_id
	current_theater_index = 0
	bonus_war_tiles_in_theater.clear()
	basic_tile_in_theater.clear()
	pending_cp = {Enums.Side.BRITAIN: 0, Enums.Side.FRANCE: 0}
	territory_refusals = {Enums.Side.BRITAIN: 0, Enums.Side.FRANCE: 0}

	var war: WarData = wars[war_id]
	for theater in war.theaters:
		bonus_war_tiles_in_theater[theater.id] = {Enums.Side.BRITAIN: [], Enums.Side.FRANCE: []}
		basic_tile_in_theater[theater.id] = {}
		for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
			var pool: Array = basic_war_tiles[side]
			if pool.size() > 0:
				pool.shuffle()
				basic_tile_in_theater[theater.id][side] = pool.pop_back()
	war_setup.emit(war_id)


func begin_war(war_id: String) -> void:
	# Trigger UI to show War Display for resolution. Use after Peace Turn ends.
	war_started.emit(war_id)


func calculate_theater_strength(theater_id: String, side: Enums.Side) -> int:
	# Pre-resolution preview (used by UI). Combined Army + Bonus.
	var war: WarData = wars[current_war_id]
	var theater: TheaterData = null
	for t in war.theaters:
		if t.id == theater_id:
			theater = t; break
	if theater == null:
		return 0
	return _calculate_army_strength(theater_id, side) + _calculate_bonus_strength(theater, side)


func _calculate_bonus_strength(theater: TheaterData, side: Enums.Side) -> int:
	# Per §7.1.3: count alliances + Forts + Squadrons + ministry keywords + conflict markers
	# matching this theater's bonus_strength keys. Use war_dots to match per-war.
	var bonus := 0
	var opponent: Enums.Side = Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
	var current_war_enum: Enums.War = _war_id_to_enum(current_war_id)

	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		var data: SpaceData = ss.data
		if ss.has_conflict_marker:
			# A flagged space with conflict marker grants strength to the OPPOSITE side
			if data.region == theater.region and ss.controlled_by != Enums.Side.NONE:
				if ss.controlled_by == opponent and "conflict_marker" in theater.bonus_strength_keys:
					bonus += 1
			continue

		# Alliance contribution per-war via war_dots
		if data.is_alliance and ss.controlled_by == side:
			# Check key match for region
			var region_key := "alliance_" + _region_short(data.region)
			if region_key in theater.bonus_strength_keys:
				if data.war_dots.is_empty() or current_war_enum in data.war_dots:
					bonus += 1
			# Specific country keys (e.g., "alliance_spain")
			for key in theater.bonus_strength_keys:
				if key.begins_with("alliance_") and not key in ["alliance_europe","alliance_north_america","alliance_caribbean","alliance_india"]:
					var country_part := key.substr(9)
					if country_part in sid:
						if data.war_dots.is_empty() or current_war_enum in data.war_dots:
							bonus += 1

		# Naval (Squadron) contribution
		if data.space_type == Enums.SpaceType.NAVAL and ss.controlled_by == side:
			var region_key := "squadron_" + _region_short(data.region)
			if region_key in theater.bonus_strength_keys:
				bonus += 1

		# Fort contribution (intact only)
		if data.space_type == Enums.SpaceType.FORT and ss.controlled_by == side and not ss.is_fort_damaged:
			var region_key := "fort_" + _region_short(data.region)
			if region_key in theater.bonus_strength_keys:
				bonus += 1

		# Local Alliance
		if data.is_local_alliance and ss.controlled_by == side:
			var key := "local_alliance_" + _region_short(data.region)
			if key in theater.bonus_strength_keys:
				bonus += 1

	# Ministry keyword bonuses
	for key in theater.bonus_strength_keys:
		if key.begins_with("keyword_"):
			var keyword := key.substr(8).capitalize()
			if GameManager.state.get_player(side).has_keyword(keyword):
				bonus += 1
	return bonus


func _war_id_to_enum(war_id: String) -> Enums.War:
	match war_id:
		"spanish_succession": return Enums.War.SPANISH_SUCCESSION
		"austrian_succession": return Enums.War.AUSTRIAN_SUCCESSION
		"seven_years": return Enums.War.SEVEN_YEARS
		"american_independence": return Enums.War.AMERICAN_INDEPENDENCE
	return Enums.War.SPANISH_SUCCESSION


func _region_short(r: Enums.Region) -> String:
	match r:
		Enums.Region.EUROPE: return "europe"
		Enums.Region.NORTH_AMERICA: return "north_america"
		Enums.Region.CARIBBEAN: return "caribbean"
		Enums.Region.INDIA: return "india"
	return ""


func resolve_theater(theater_id: String) -> Dictionary:
	# Per §7.1: 1) reveal Army Strength tiles → 2) apply tile effects → 3) add Bonus Strength → 4) compare
	var war: WarData = wars[current_war_id]
	var theater: TheaterData = null
	for t in war.theaters:
		if t.id == theater_id:
			theater = t; break

	# Step 1: Army Strength = sum of tile strengths only
	var br_army := _calculate_army_strength(theater_id, Enums.Side.BRITAIN)
	var fr_army := _calculate_army_strength(theater_id, Enums.Side.FRANCE)

	# Step 2: Apply tile effects (closer-to-victory player first)
	_apply_tile_effects(theater_id)

	# Step 3: Bonus Strength (computed from current board state, AFTER tile effects)
	var br_bonus := _calculate_bonus_strength(theater, Enums.Side.BRITAIN)
	var fr_bonus := _calculate_bonus_strength(theater, Enums.Side.FRANCE)

	var br_str := br_army + br_bonus
	var fr_str := fr_army + fr_bonus

	var winner := Enums.Side.NONE
	var margin := 0
	if br_str > fr_str:
		winner = Enums.Side.BRITAIN
		margin = br_str - fr_str
	elif fr_str > br_str:
		winner = Enums.Side.FRANCE
		margin = fr_str - br_str

	_apply_spoils(theater_id, winner, margin)
	theater_resolved.emit(theater_id, winner, margin)
	return {
		"winner": winner, "margin": margin,
		"br_strength": br_str, "fr_strength": fr_str,
		"br_army": br_army, "fr_army": fr_army,
		"br_bonus": br_bonus, "fr_bonus": fr_bonus,
	}


func _calculate_army_strength(theater_id: String, side: Enums.Side) -> int:
	var s := 0
	if theater_id in basic_tile_in_theater and side in basic_tile_in_theater[theater_id]:
		var basic: WarTile = basic_tile_in_theater[theater_id][side]
		s += basic.strength
	if theater_id in bonus_war_tiles_in_theater:
		for tile in bonus_war_tiles_in_theater[theater_id][side]:
			s += (tile as WarTile).strength
	return s


func _apply_tile_effects(theater_id: String) -> void:
	# Per §7.1: closer-to-victory player resolves first
	var first_side := _closer_to_victory_side()
	var sides := [first_side, Enums.Side.FRANCE if first_side == Enums.Side.BRITAIN else Enums.Side.BRITAIN]
	# Find theater data
	var war: WarData = wars[current_war_id]
	var theater: TheaterData = null
	for t in war.theaters:
		if t.id == theater_id: theater = t; break
	for side in sides:
		var tile: WarTile = basic_tile_in_theater[theater_id].get(side)
		if tile:
			_apply_single_tile_effect(tile, theater)
		for bt in bonus_war_tiles_in_theater[theater_id][side]:
			_apply_single_tile_effect(bt, theater)


func _closer_to_victory_side() -> Enums.Side:
	# Per §7.1.2: player closer to auto-victory goes first.
	# FR auto-victory at VP=30, BR at VP=0. Distances: FR=30-vp, BR=vp.
	var vp = GameManager.state.vp
	var fr_dist = 30 - vp
	var br_dist = vp
	if fr_dist < br_dist: return Enums.Side.FRANCE
	if br_dist < fr_dist: return Enums.Side.BRITAIN
	# Tie at vp=15: player who went first in preceding peace turn
	return GameManager.state.first_player


func _apply_single_tile_effect(tile: WarTile, theater: TheaterData = null) -> void:
	var opponent: Enums.Side = Enums.Side.FRANCE if tile.side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
	match tile.special_effect:
		WarTile.SpecialEffect.DEBT:
			GameManager.state.get_player(opponent).take_debt(1)
		WarTile.SpecialEffect.DAMAGE_FORT_OR_REMOVE_SQUADRON:
			# Per §7.1.2: damage opposing Fort in theater, or remove opposing Squadron from theater
			if theater != null:
				for sid in GameManager.state.spaces:
					var ss: SpaceState = GameManager.state.spaces[sid]
					if ss.data.region != theater.region: continue
					if ss.data.space_type == Enums.SpaceType.FORT and ss.controlled_by == opponent and not ss.is_fort_damaged:
						ss.is_fort_damaged = true
						return
				# Else squadron in theater
				for sid in GameManager.state.spaces:
					var ss: SpaceState = GameManager.state.spaces[sid]
					if ss.data.region != theater.region: continue
					if ss.data.space_type == Enums.SpaceType.NAVAL and ss.controlled_by == opponent:
						var op := GameManager.state.get_player(opponent)
						if op.squadrons_on_map > 0:
							op.squadrons_on_map -= 1
							op.squadrons_in_navy_box += 1
							ss.controlled_by = Enums.Side.NONE
							return
		WarTile.SpecialEffect.UNFLAG:
			# Per §7.1.2: unflag a Market or Political space in theater's Region
			# Markets must not cause Isolation (where possible)
			if theater != null:
				# Try Market without Isolation impact first
				var fallback_market: SpaceState = null
				for sid in GameManager.state.spaces:
					var ss: SpaceState = GameManager.state.spaces[sid]
					if ss.data.region != theater.region: continue
					if ss.data.space_type == Enums.SpaceType.MARKET and ss.controlled_by == opponent and not ss.has_conflict_marker:
						# Check isolation impact: simplified — accept any
						ss.unflag(tile.side)
						return
				# Else Political in theater region
				for sid in GameManager.state.spaces:
					var ss: SpaceState = GameManager.state.spaces[sid]
					if ss.data.region != theater.region: continue
					if ss.data.space_type == Enums.SpaceType.POLITICAL and ss.controlled_by == opponent and not ss.has_conflict_marker:
						ss.unflag(tile.side)
						return


func _apply_spoils(theater_id: String, winner: Enums.Side, margin: int) -> void:
	if winner == Enums.Side.NONE:
		return
	var war: WarData = wars[current_war_id]
	var theater: TheaterData = null
	for t in war.theaters:
		if t.id == theater_id:
			theater = t
			break
	if theater == null:
		return

	var spoils_row: Dictionary = {}
	for row in theater.spoils_table:
		if _matches_margin(row["margin"], winner, margin):
			spoils_row = row
			break
	if spoils_row.is_empty():
		return

	var loser: Enums.Side = Enums.Side.FRANCE if winner == Enums.Side.BRITAIN else Enums.Side.BRITAIN

	for reward in spoils_row.get("winner", []):
		_apply_reward(winner, reward)
	for penalty in spoils_row.get("loser", []):
		_apply_reward(loser, penalty)


func _matches_margin(margin_spec: String, winner: Enums.Side, margin: int) -> bool:
	# Specs: "1-2", "3-4", "5+", "br_1-2", "fr_1+", "br_1+", etc.
	var spec := margin_spec
	if spec.begins_with("br_"):
		if winner != Enums.Side.BRITAIN:
			return false
		spec = spec.substr(3)
	elif spec.begins_with("fr_"):
		if winner != Enums.Side.FRANCE:
			return false
		spec = spec.substr(3)

	if spec.ends_with("+"):
		var min_val := int(spec.trim_suffix("+"))
		return margin >= min_val
	if "-" in spec:
		var parts := spec.split("-")
		var min_val := int(parts[0])
		var max_val := int(parts[1])
		return margin >= min_val and margin <= max_val
	return margin == int(spec)


func _apply_reward(side: Enums.Side, reward) -> void:
	var s := str(reward)
	if s.ends_with("cp"):
		var cp := int(s.trim_suffix("cp"))
		pending_cp[side] = pending_cp.get(side, 0) + cp
		cp_awarded.emit(side, cp)
	elif s.ends_with("vp"):
		var vp := int(s.trim_suffix("vp"))
		GameManager.state.score_vp(side, vp)
	elif s.ends_with("tp"):
		var tp := int(s.trim_suffix("tp"))
		GameManager.state.get_player(side).add_treaty_points(tp)
	elif s == "jacobite_defeat":
		# Remove Jacobite Uprisings ministry from game
		pass
	elif s == "jacobite_victory":
		pass
	elif s == "usa":
		# Mark American Revolution as French win - USA flags
		pass
	elif s == "canada":
		pass
	elif s.begins_with("unflag_"):
		# Auto-pick first valid target - real game requires player choice
		_auto_unflag(side, s)


func _auto_unflag(side: Enums.Side, reward: String) -> void:
	var opponent: Enums.Side = Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
	var region_filter: Enums.Region = Enums.Region.EUROPE
	if "north_america" in reward:
		region_filter = Enums.Region.NORTH_AMERICA
	elif "caribbean" in reward:
		region_filter = Enums.Region.CARIBBEAN
	elif "india" in reward:
		region_filter = Enums.Region.INDIA
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.region == region_filter and ss.controlled_by == opponent and ss.data.space_type == Enums.SpaceType.MARKET and not ss.has_conflict_marker:
			ss.unflag(side)
			return


func resolve_full_war() -> Array:
	var results := []
	var war: WarData = wars[current_war_id]
	# Determine first-resolver: closer to auto-victory (VP-distance from 15)
	# If VP=15, the player who went first in preceding peace turn resolves first
	for theater in war.theaters:
		var result := resolve_theater(theater.id)
		result["theater_id"] = theater.id
		result["theater_name"] = theater.name
		results.append(result)
	_auto_spend_cp()
	_cleanup_conflict_markers()
	# Per §7.5: return basic war tiles to player pools (only basics; bonus tiles removed)
	_return_war_tiles_to_pools()
	war_ended.emit(current_war_id)
	return results


func _return_war_tiles_to_pools() -> void:
	# Basic war tiles in theaters → return to player's basic_war_tiles pool
	for theater_id in basic_tile_in_theater:
		var theater_dict: Dictionary = basic_tile_in_theater[theater_id]
		for side in theater_dict:
			var t = theater_dict[side]
			if t and t is WarTile and t.tile_type == WarTile.TileType.BASIC:
				if not basic_war_tiles.has(side):
					basic_war_tiles[side] = []
				basic_war_tiles[side].append(t)
	# Bonus tiles for THIS war are removed from game (per §3.7)
	# but bonus_tile_pool is generic in our impl, so just clear the in-theater bonuses
	basic_tile_in_theater.clear()
	bonus_war_tiles_in_theater.clear()


func _auto_spend_cp() -> void:
	# Per §7.2.1: track which theater earned the CP for region-aware spending.
	# Simplification: distribute CP across theaters this side won.
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var cp: int = pending_cp.get(side, 0)
		if cp <= 0:
			continue
		var opponent: Enums.Side = Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
		# Build list of allowed Territories per won theater
		var allowed_territory_ids: Dictionary = {}  # sid -> true
		var allowed_other_ids: Dictionary = {}      # for forts/markets/naval (must be in theater Region)

		var war: WarData = wars[current_war_id]
		for theater in war.theaters:
			# Only count theaters this side won
			# (we don't have a per-theater win record post-resolution; use _theater_winners if available)
			# For simplicity, allow all theaters' eligible spaces
			# Territories: in theater Region OR in additional_territories
			for sid in GameManager.state.spaces:
				var ss: SpaceState = GameManager.state.spaces[sid]
				if ss.data.space_type == Enums.SpaceType.TERRITORY:
					if ss.data.region == theater.region or sid in theater.additional_territories:
						allowed_territory_ids[sid] = true
				elif ss.data.space_type in [Enums.SpaceType.FORT, Enums.SpaceType.MARKET, Enums.SpaceType.NAVAL]:
					if ss.data.region == theater.region:
						allowed_other_ids[sid] = true

		# 1. Take Territories with Conquest Line connection first
		for sid in allowed_territory_ids:
			if cp <= 0: break
			if not (sid in GameManager.state.spaces): continue
			var ss = GameManager.state.spaces[sid]
			if ss.controlled_by != opponent: continue
			if ss.has_usa_flag: continue
			if _has_conquest_line_to(side, sid):
				ss.take_control(side)
				cp -= 1
		# 2. Take Territories without Conquest Lines (Gibraltar etc.)
		for sid in allowed_territory_ids:
			if cp <= 0: break
			if not (sid in GameManager.state.spaces): continue
			var ss = GameManager.state.spaces[sid]
			if ss.controlled_by != opponent: continue
			if ss.has_usa_flag: continue
			if ss.data.conquest_line_connections.is_empty():
				ss.take_control(side)
				cp -= 1
		# 3. Forts (must be in theater)
		for sid in allowed_other_ids:
			if cp <= 0: break
			var ss = GameManager.state.spaces[sid]
			if ss.controlled_by == opponent and ss.data.space_type == Enums.SpaceType.FORT:
				ss.take_control(side)
				cp -= 1
		# 4. Markets
		for sid in allowed_other_ids:
			if cp <= 0: break
			var ss = GameManager.state.spaces[sid]
			if ss.controlled_by == opponent and ss.data.space_type == Enums.SpaceType.MARKET:
				ss.take_control(side)
				cp -= 1
		pending_cp[side] = cp


func refuse_territory(side: Enums.Side, territory_id: String) -> bool:
	# Per §7.2.2: twice per war, costs 3 VP first time, 5 VP second time
	var count: int = territory_refusals.get(side, 0)
	if count >= 2:
		return false
	var vp_cost := 3 if count == 0 else 5
	# Cost is borne by side: BR refusing → BR loses 3 VP (FR gains? No, just VP cost)
	# Per rule: "Using this option costs 3 VP the first time it is used in a War, and 5 VP the second time."
	# The opponent's CP is still spent
	GameManager.state.score_vp(_opp(side), vp_cost)  # Cost = VP to opponent direction
	territory_refusals[side] = count + 1
	if has_node("/root/GameLog"):
		GameLog.log_entry(side, "refuse", "refused territory cession (-%d VP)" % vp_cost)
	return true


func _opp(side: Enums.Side) -> Enums.Side:
	return Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN


func _has_conquest_line_to(side: Enums.Side, target_id: String) -> bool:
	if not (target_id in GameManager.state.spaces):
		return false
	var target: SpaceState = GameManager.state.spaces[target_id]
	for conn_id in target.data.conquest_line_connections:
		if conn_id in GameManager.state.spaces:
			var conn: SpaceState = GameManager.state.spaces[conn_id]
			if conn.controlled_by == side:
				return true
	return false


func _cleanup_conflict_markers() -> void:
	# Remove conflict markers in regions that contributed bonus strength
	# Simplification: remove all conflict markers
	for sid in GameManager.state.spaces:
		(GameManager.state.spaces[sid] as SpaceState).remove_conflict_marker()


func _parse_region(s: String) -> Enums.Region:
	match s:
		"europe": return Enums.Region.EUROPE
		"north_america": return Enums.Region.NORTH_AMERICA
		"caribbean": return Enums.Region.CARIBBEAN
		"india": return Enums.Region.INDIA
	return Enums.Region.EUROPE
