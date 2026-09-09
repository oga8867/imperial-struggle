extends Node

# §7.1-7.3 전쟁 상태 기계. await로 보류한 함수 대신 단계와 선택 데이터를 저장하므로
# 정복·영토 양도 거부를 기다리는 중에도 저장 후 같은 지점으로 돌아올 수 있다.
signal changed
signal finished
var active = false
var automatic = false
var stage = ""
var index = 0
var operations: Array = []
var choice: Dictionary = {}
var result: Dictionary = {}
var results: Array = []
var refused: Array[String] = []
var naval_used: Array[String] = []
var atlantic_side: int = Enums.Side.NONE
var contributing_conflicts: Array[String] = []

func reset() -> void:
	active = false
	stage = ""
	choice.clear()
	operations.clear()
	results.clear()
	refused.clear()
	naval_used.clear()
	contributing_conflicts.clear()
	atlantic_side = Enums.Side.NONE
	index = 0

func start(auto_resolve: bool = false) -> void:
	if active:
		changed.emit()
		return
	if WarManager._resolved_war_id == WarManager.current_war_id:
		results = WarManager._cached_results.duplicate(true)
		finished.emit()
		return
	reset()
	active = true
	automatic = auto_resolve
	stage = "prepare"
	_pump()

func theater() -> TheaterData:
	return WarManager.wars[WarManager.current_war_id].theaters[index]

func _pump() -> void:
	while active and choice.is_empty():
		match stage:
			"prepare":
				var th = theater()
				result = {"theater_id": th.id, "theater_name": th.name_ko, "br_army": WarManager._calculate_army_strength(th.id, Enums.Side.BRITAIN), "fr_army": WarManager._calculate_army_strength(th.id, Enums.Side.FRANCE)}
				var first = WarManager._closer_to_victory_side()
				for side in [first, WarManager._opp(first)]:
					var tiles = WarManager.bonus_war_tiles_in_theater[th.id][side].duplicate()
					tiles.push_front(WarManager.basic_tile_in_theater[th.id][side])
					for tile in tiles:
						operations.append({"kind":"tile", "side":side, "effect":tile.special_effect})
				stage = "effects"
			"effects", "spoils":
				if operations.is_empty():
					stage = "score" if stage == "effects" else "end_theater"
				else:
					_execute(operations.pop_front())
			"score":
				_score_theater()
				stage = "spoils"
			"end_theater":
				results.append(result.duplicate(true))
				WarManager.theater_resolved.emit(theater().id,result.winner,result.margin)
				GameLog.log_entry(result.winner,"war", "%s: 영국 %d / 프랑스 %d" % [result.theater_name,result.br_strength,result.fr_strength])
				index += 1
				if index == WarManager.wars[WarManager.current_war_id].theaters.size():
					_finish()
				else:
					stage = "prepare"
	changed.emit()

func _score_theater() -> void:
	var th = theater()
	if "conflict_marker" in th.bonus_strength_keys:
		for ss in GameManager.state.spaces.values():
			if ss.has_conflict_marker and ss.controlled_by != Enums.Side.NONE and ss.data.region in th.regions and ss.data.id not in contributing_conflicts: contributing_conflicts.append(ss.data.id)
	result.br_bonus = WarManager._calculate_bonus_strength(th, Enums.Side.BRITAIN)
	result.fr_bonus = WarManager._calculate_bonus_strength(th, Enums.Side.FRANCE)
	result.br_strength = result.br_army + result.br_bonus
	result.fr_strength = result.fr_army + result.fr_bonus
	result.margin = absi(result.br_strength-result.fr_strength)
	result.winner = Enums.Side.NONE if result.margin == 0 else (Enums.Side.BRITAIN if result.br_strength > result.fr_strength else Enums.Side.FRANCE)
	if result.winner == Enums.Side.NONE: return
	for row in th.spoils_table:
		if WarManager._matches_margin(row.margin,result.winner,result.margin):
			for reward in row.winner: _queue_reward(result.winner,reward)
			for reward in row.loser: _queue_reward(WarManager._opp(result.winner),reward)
			break
	if th.id == "jacobite_rebellion_wss" and result.winner == Enums.Side.FRANCE and result.margin >= 3:
		GameManager.state.jacobite_victories += 1
	if th.id == "antilles_war":
		for i in range(mini(result.margin,2)):
			operations.append({"kind":"remove_squadron", "side":WarManager._opp(result.winner), "permanent":true})

func _queue_reward(side: int, reward: String) -> void:
	if reward.ends_with("vp"):
		GameManager.state.score_vp(side,int(reward.trim_suffix("vp")))
	elif reward.ends_with("tp"):
		GameManager.state.get_player(side).add_treaty_points(int(reward.trim_suffix("tp")))
	elif reward.ends_with("cp"):
		operations.append({"kind":"cp","side":side,"amount":int(reward.trim_suffix("cp"))})
	elif reward.begins_with("unflag_"):
		operations.append({"kind":"unflag","side":side,"reward":reward})
	elif reward == "unbuild_squadron":
		operations.append({"kind":"remove_squadron","side":side,"permanent":false})
	elif reward == "atlantic_dominance":
		atlantic_side = side
	elif reward in ["usa","canada"]:
		operations.append({"kind":reward,"side":side})
	elif reward == "jacobite_victory":
		GameManager.state.jacobite_victories += 1
		GameManager.state.jacobite_extra_ministry = true
	elif reward == "jacobite_defeat":
		GameManager.state.jacobite_defeated = true
		for card in GameManager.state.france.ministry_cards.duplicate():
			if card.id == "M-4":
				GameManager.state.france.ministry_cards.erase(card)
				card.is_in_play = false

func _execute(operation: Dictionary) -> void:
	var side: int = operation.side
	var opponent = WarManager._opp(side)
	var options: Array = []
	var prompt = ""
	match operation.kind:
		"tile":
			match int(operation.effect):
				WarTile.SpecialEffect.NONE: return
				WarTile.SpecialEffect.DEBT:
					GameManager.state.get_player(opponent).incur_debt(1)
					return
				WarTile.SpecialEffect.UNFLAG:
					options = _unflag_options(side, theater().regions, false, true)
					prompt = "상대 깃발을 제거할 시장 또는 정치 공간을 선택하세요."
				WarTile.SpecialEffect.DAMAGE_FORT_OR_REMOVE_SQUADRON:
					for ss in GameManager.state.spaces.values():
						if ss.controlled_by != opponent or ss.data.region not in theater().regions: continue
						if ss.data.space_type == Enums.SpaceType.NAVAL or (ss.data.space_type == Enums.SpaceType.FORT and not ss.is_fort_damaged):
							options.append(_option(ss))
					prompt = "손상시킬 상대 요새 또는 해군 상자로 돌려보낼 함대를 선택하세요."
		"unflag":
			var region = Enums.Region.EUROPE
			for key in ["north_america","caribbean","india"]:
				if key in operation.reward: region = WarManager._parse_region(key)
			options = _unflag_options(side,[region],"political" in operation.reward,false)
			prompt = "전리품: 상대 깃발을 제거할 공간을 선택하세요."
		"cp":
			options = conquest_options(side,operation.amount)
			prompt = "정복점수 %d · 이번 전장에서 차지할 공간을 선택하세요." % operation.amount
			if not options.is_empty(): options.append({"id":"skip","label":"남은 정복점수 포기"})
		"remove_squadron":
			var player = GameManager.state.get_player(side)
			if player.squadrons_in_navy_box > 0: options.append({"id":"navy","label":"해군 상자의 함대 1척"})
			for ss in GameManager.state.spaces.values():
				if ss.data.space_type == Enums.SpaceType.NAVAL and ss.controlled_by == side: options.append(_option(ss))
			prompt = "전쟁 손실: 제거할 내 함대를 선택하세요."
		"usa", "canada":
			var ids = ["northern_colonies","carolinas","san_agustin"] if operation.kind == "usa" else ["quebec_and_montreal"]
			for sid in ids:
				if sid in GameManager.state.spaces and not GameManager.state.spaces[sid].has_usa_flag:
					options.append(_option(GameManager.state.spaces[sid]))
			if operation.kind == "usa":
				for ss in GameManager.state.spaces.values():
					if ss.data.space_type == Enums.SpaceType.FORT and ss.data.sub_region == Enums.SubRegion.NORTHERN_COLONIES and ss.controlled_by != Enums.Side.NONE:
						var option = _option(ss)
						option.label += " · 요새 깃발 제거"
						options.append(option)
			if not options.is_empty(): options.append({"id":"skip","label":"미국 깃발 배치 종료"})
			prompt = "미국 독립: 미국 깃발을 놓을 영토를 선택하세요. 배치는 선택 사항입니다."
	if options.is_empty(): return
	choice = operation.duplicate(true)
	choice.options = options
	choice.prompt = prompt
	if automatic or (AIController.enabled and AIController.ai_side == side and not AIController.strategy_mode):
		_apply_choice(options[0])
	else:
		changed.emit()

func choose(option_id: String) -> bool:
	if choice.is_empty(): return false
	for option in choice.options:
		if option.id == option_id:
			_apply_choice(option)
			_pump()
			return true
	return false

func _apply_choice(option: Dictionary) -> void:
	var operation = choice.duplicate(true)
	choice.clear()
	if option.id == "skip": return
	var side: int = operation.side
	var ss: SpaceState = GameManager.state.spaces.get(option.get("target",option.id))
	match operation.kind:
		"tile":
			if int(operation.effect) == WarTile.SpecialEffect.UNFLAG:
				ss.unflag(side)
			elif ss.data.space_type == Enums.SpaceType.FORT:
				ss.is_fort_damaged = true
			else:
				GameManager.state.get_player(ss.controlled_by).squadrons_in_navy_box += 1
				ss.controlled_by = Enums.Side.NONE
		"unflag": ss.unflag(side)
		"cp":
			var remaining = operation.amount - option.cost
			if remaining > 0: operations.push_front({"kind":"cp","side":side,"amount":remaining})
			if ss.data.space_type == Enums.SpaceType.TERRITORY and ss.controlled_by == WarManager._opp(side) and WarManager.territory_refusals.get(ss.controlled_by,0) < 2:
				var defender = ss.controlled_by
				choice = {"kind":"refusal","side":defender,"attacker":side,"target":ss.data.id,"options":[{"id":"accept","label":"영토를 양도"},{"id":"refuse","label":"양도 거부 · 상대에게 %d VP" % (3 if WarManager.territory_refusals.get(defender,0)==0 else 5)}],"prompt":ss.data.name_ko+" · 정복점수는 이미 소비됐습니다. 영토 양도를 거부하시겠습니까?"}
				if automatic or (AIController.enabled and AIController.ai_side == defender and not AIController.strategy_mode): _apply_choice(choice.options[0])
			else:
				_capture(ss,side,option.get("source",""))
		"refusal":
			ss = GameManager.state.spaces[operation.target]
			if option.id == "refuse":
				WarManager.refuse_territory(side,ss.data.id)
				refused.append(ss.data.id)
			else: _capture(ss,operation.attacker,"")
		"remove_squadron":
			var player = GameManager.state.get_player(side)
			if option.id == "navy": player.squadrons_in_navy_box -= 1
			else: ss.controlled_by = Enums.Side.NONE
			if operation.permanent: player.squadrons_removed += 1
		"usa", "canada":
			# 이미 고립돼 있던 시장은 USA 효과로 제거하지 않는다 (§7.3.3).
			var connected_before: Array = []
			for market in GameManager.state.spaces.values():
				if market.data.space_type == Enums.SpaceType.MARKET and market.data.region in [Enums.Region.NORTH_AMERICA,Enums.Region.CARIBBEAN] and market.controlled_by != Enums.Side.NONE and not market.is_isolated(GameManager.state.spaces): connected_before.append(market.data.id)
			ss.controlled_by = Enums.Side.NONE
			if ss.data.space_type == Enums.SpaceType.TERRITORY: ss.has_usa_flag = true
			operations.push_front({"kind":operation.kind,"side":side})
			_remove_isolated_after_usa(connected_before)
	ActionController._recount_squadrons()
	AdvantageManager.recompute_control()
	GameManager.vp_changed.emit(GameManager.state.vp)

func _option(ss: SpaceState) -> Dictionary:
	return {"id":ss.data.id,"label":ss.data.name_ko if ss.data.name_ko != "" else ss.data.display_name}

func _unflag_options(side: int, regions: Array, political_only: bool, tile_effect: bool) -> Array:
	var options: Array = []
	var unsafe: Array = []
	for ss in GameManager.state.spaces.values():
		if ss.data.region not in regions or ss.controlled_by != WarManager._opp(side) or ss.has_conflict_marker: continue
		if ss.data.space_type == Enums.SpaceType.POLITICAL and (political_only or tile_effect): options.append(_option(ss))
		if ss.data.space_type == Enums.SpaceType.MARKET and not political_only:
			if tile_effect and _would_isolate(ss): unsafe.append(_option(ss))
			else: options.append(_option(ss))
	# 시장을 선택한다면 다른 시장을 고립시키지 않는 시장을 우선해야 한다 (§7.1.2).
	if not options.any(func(o): return GameManager.state.spaces[o.id].data.space_type == Enums.SpaceType.MARKET): options.append_array(unsafe)
	return options

func _would_isolate(target: SpaceState) -> bool:
	var connected: Array = []
	for ss in GameManager.state.spaces.values():
		if ss != target and ss.data.space_type == Enums.SpaceType.MARKET and ss.controlled_by == target.controlled_by and not ss.is_isolated(GameManager.state.spaces): connected.append(ss)
	var owner = target.controlled_by
	target.controlled_by = Enums.Side.NONE
	var isolated = connected.any(func(s): return s.is_isolated(GameManager.state.spaces))
	target.controlled_by = owner
	return isolated

func conquest_options(side: int, points: int) -> Array:
	var options: Array = []
	var th = theater()
	for ss in GameManager.state.spaces.values():
		if ss.controlled_by == side or ss.has_usa_flag or ss.data.id in refused: continue
		var territory = ss.data.space_type == Enums.SpaceType.TERRITORY
		if ss.data.region not in th.regions and not (territory and ss.data.id in th.additional_territories): continue
		if ss.data.space_type == Enums.SpaceType.POLITICAL: continue
		var cost = ss.data.conquest_cost + (1 if ss.has_huguenots else 0) if territory else 1
		if cost > points: continue
		if territory and not ss.data.conquest_line_connections.is_empty() and not WarManager._has_conquest_line_to(side,ss.data.id): continue
		var option = _option(ss)
		option.cost = cost
		option.label += " · %d CP" % cost
		if ss.data.space_type == Enums.SpaceType.NAVAL:
			var sources: Array = []
			if GameManager.state.get_player(side).squadrons_in_navy_box > 0: sources.append("navy")
			for from_space in GameManager.state.spaces.values():
				if from_space.data.space_type == Enums.SpaceType.NAVAL and from_space.data.region in th.regions and from_space.controlled_by == side and from_space.data.id not in naval_used: sources.append(from_space.data.id)
			for source in sources:
				var naval_option = option.duplicate()
				naval_option.id = ss.data.id + "|" + source
				naval_option.target = ss.data.id
				naval_option.source = source
				naval_option.label += " ← " + ("해군 상자" if source == "navy" else GameManager.state.spaces[source].data.name_ko)
				options.append(naval_option)
		else: options.append(option)
	return options

func _capture(ss: SpaceState, side: int, source: String) -> void:
	if ss.data.space_type == Enums.SpaceType.NAVAL:
		if ss.controlled_by != Enums.Side.NONE: GameManager.state.get_player(ss.controlled_by).squadrons_in_navy_box += 1
		if source == "navy": GameManager.state.get_player(side).squadrons_in_navy_box -= 1
		else: GameManager.state.spaces[source].controlled_by = Enums.Side.NONE
		naval_used.append(ss.data.id)
	ss.take_control(side)
	if ss.data.space_type == Enums.SpaceType.FORT: ss.is_fort_damaged = false

func _remove_isolated_after_usa(connected_before: Array) -> void:
	for id in connected_before:
		var ss = GameManager.state.spaces[id]
		if ss.is_isolated(GameManager.state.spaces):
			ss.controlled_by = Enums.Side.NONE
			ss.remove_conflict_marker()

func _finish() -> void:
	# 전력에 기여했던 분쟁만 제거한다. 다른 지역의 분쟁은 다음 전쟁까지 남는다 (§7.4).
	if WarManager.current_war_id == "austrian_succession":
		for side in [Enums.Side.BRITAIN,Enums.Side.FRANCE]:
			var count=0
			for th in WarManager.bonus_war_tiles_in_theater.values(): count+=th[side].size()
			GameManager.state.war_carryover_draws[side]=mini(3,count)
	# 마지막 전쟁은 규칙이 Reset Phase를 생략하므로 분쟁도 그대로 남긴다 (§7.5).
	if WarManager.current_war_id != "american_independence":
		for id in contributing_conflicts: GameManager.state.spaces[id].remove_conflict_marker()
		WarManager._return_war_tiles_to_pools()
	GameManager.state.byng_theater=""
	WarManager._resolved_war_id = WarManager.current_war_id
	WarManager._cached_results = results.duplicate(true)
	active = false
	stage = "finished"
	WarManager.war_ended.emit(WarManager.current_war_id)
	finished.emit()
