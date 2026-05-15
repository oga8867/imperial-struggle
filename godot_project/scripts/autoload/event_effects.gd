extends Node

# Per-card event effects, plus a regex fallback parser for AP grants and simple effects.

signal pending_choices_changed(choices: Array)
signal effects_resolved

var pending_choices: Array = []  # {type, params, count_remaining}
var current_card: EventCard = null
var current_side: Enums.Side = Enums.Side.NONE
var current_with_bonus: bool = false


func apply_event(card: EventCard, side: Enums.Side, with_bonus: bool) -> void:
	pending_choices.clear()
	current_card = card
	current_side = side
	current_with_bonus = with_bonus

	# Try per-card handler first
	var method_name := "_event_%d" % card.id
	if has_method(method_name):
		call(method_name, side, with_bonus)
	else:
		# Fallback: regex-based parsing
		_apply_text(card.get_base_text(side), side)
		if with_bonus:
			_apply_text(card.get_bonus_text(side), side)

	if pending_choices.size() > 0:
		pending_choices_changed.emit(pending_choices)
	else:
		effects_resolved.emit()


# ---------- Per-card handlers ----------

# #1 Carnatic War: Place 1 Conflict marker in India for each Local Alliance there
func _event_1(side: Enums.Side, bonus: bool) -> void:
	var count := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.is_local_alliance and ss.data.region == Enums.Region.INDIA and ss.controlled_by == side:
			count += 1
	if count > 0:
		_add_pending("place_conflict_marker_choice", {"count": count, "region": Enums.Region.INDIA, "side": side})
	if bonus:
		# Damage enemy Fort or shift Cotton market in India
		_add_pending("damage_fort_or_shift_cotton_india", {"side": side, "count": 1})


# #2 Acts of Union: more Prestige spaces in Scotland and Ireland
func _event_2(side: Enums.Side, bonus: bool) -> void:
	if _is_symmetric():
		_apply_text(current_card.both_base, side)
		if bonus: _apply_text(current_card.both_bonus, side)
	else:
		_apply_text(current_card.get_base_text(side), side)
		if bonus: _apply_text(current_card.get_bonus_text(side), side)


# #3 Tropical Diseases: Remove 1 enemy then 1 friendly flag from Caribbean Markets
func _event_3(side: Enums.Side, bonus: bool) -> void:
	_add_pending("unflag_market_caribbean", {"side": side, "from": "enemy"})
	_add_pending("unflag_market_caribbean", {"side": side, "from": "friendly"})
	if bonus:
		_add_pending("unflag_market_caribbean", {"side": side, "from": "enemy"})


# #4 South Sea Speculation: Unflag a Market whose removal does not Isolate others
func _event_4(side: Enums.Side, bonus: bool) -> void:
	_add_pending("unflag_market_safe", {"side": side})
	if bonus:
		_add_pending("squadron_discount_2mp", {"side": side})


# #5 War of Jenkins' Ear (BR/FR asymmetric)
func _event_5(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		GameManager.state.britain.reduce_debt(2)
		if bonus: GameManager.state.france.take_debt(1)
	else:
		_add_pending("place_conflict_marker_choice", {"count": 1, "region": Enums.Region.CARIBBEAN, "side": side, "br_flagged": true})
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC)


# #6 Native American Alliances
func _event_6(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("shift_local_alliance_na", {"side": side})
		if bonus: _add_pending("activate_advantage_na", {"side": side})
	else:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC)
		if bonus: _add_pending("unflag_local_alliance_na", {"side": side})


# #7 Austro-Spanish Rivalry
func _event_7(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("place_conflict_marker_in_country", {"country": "spain", "side": side})
		if bonus: _add_pending("remove_fr_bonus_war_tile", {"side": side})
	else:
		_add_pending("unflag_in_country", {"country": "dutch_republic", "side": side})
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC)


# #8 Tax Reform
func _event_8(side: Enums.Side, bonus: bool) -> void:
	var reduced := GameManager.state.get_player(side).reduce_debt(2)
	if bonus:
		GameManager.state.get_player(side).reduce_debt(1)


# #9 Great Northern War
func _event_9(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("shift_in_country", {"country": "german_states", "side": side, "vp_if_both": 2})
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC)
	else:
		_add_pending("shift_country_if_fr_score", {"country": "russia", "side": side})
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC)


# #10 Vatican Politics
func _event_10(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_grant_event_ap(2, Enums.ActionType.DIPLOMATIC)
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC)
	else:
		_add_pending("shift_in_country", {"country": "spain_or_austria", "side": side})
		if bonus: _add_pending("vp_if_no_br_in_spain_austria", {"side": side, "vp": 2})


# #11 Calico Acts
func _event_11(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC)
		if bonus: _add_pending("score_cotton_demand", {"side": side})
	else:
		_add_pending("unflag_cotton_market", {"side": side})
		if bonus: _add_pending("move_br_squadron_to_navy", {"side": side})


# #12 Military Spending Overruns: opponent damages fort/removes squadron/removes bonus tile
func _event_12(side: Enums.Side, bonus: bool) -> void:
	_add_pending("opponent_choice_damage_or_squadron", {"side": side})
	if bonus:
		_add_pending("opponent_choice_damage_or_squadron", {"side": side})


# #13 Alberoni's Ambition
func _event_13(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC)
		if bonus: _grant_event_ap(1, Enums.ActionType.ECONOMIC)
	else:
		_add_pending("shift_alliance_in_countries", {"countries": ["austria","dutch_republic","spain"], "side": side})
		if bonus: _add_pending("vp_savoy_sardinia_fr", {"side": side, "vp": 3})


# #14 Famine in Ireland
func _event_14(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("unflag_in_country", {"country": "ireland_or_scotland", "side": side, "fr_only": true})
	else:
		_add_pending("draw_war_tiles_ireland", {"side": side})


# #15 Interest Payments
func _event_15(side: Enums.Side, bonus: bool) -> void:
	var opp := GameManager.state.get_opponent(side)
	opp.debt_limit = maxi(0, opp.debt_limit - 1)
	if opp.current_debt > opp.debt_limit:
		# Per rule: if at debt limit, also reduce debt by 1, then score 1 VP
		opp.current_debt -= 1
		GameManager.state.score_vp(side, 1)
	if bonus:
		GameManager.state.get_player(side).reduce_debt(2)


# #16 Caribbean Slave Unrest
func _event_16(side: Enums.Side, bonus: bool) -> void:
	_add_pending("place_conflict_marker_choice", {"count": 1, "region": Enums.Region.CARIBBEAN, "side": side})
	if bonus:
		_add_pending("place_conflict_marker_choice", {"count": 1, "region": Enums.Region.CARIBBEAN, "side": side})


# #17 Pacte de Famille
func _event_17(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_grant_event_ap(1, Enums.ActionType.DIPLOMATIC)  # Discount represented as bonus AP
	else:
		_add_pending("refresh_advantages_europe", {"count": 2, "side": side})
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC)


# #18 Byng's Trial
func _event_18(side: Enums.Side, bonus: bool) -> void:
	# Setup-time: just notes - mark for next war
	pass


# #19 Le Beau Monde
func _event_19(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("set_global_demand_fur_or_cotton", {"side": side})
		if bonus: _grant_event_ap(1, Enums.ActionType.ECONOMIC)
	else:
		_grant_event_ap(1, Enums.ActionType.DIPLOMATIC)
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC)


# #20 Hyder Ali
func _event_20(side: Enums.Side, bonus: bool) -> void:
	_add_pending("hyder_ali_choice", {"side": side})
	if bonus:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC)


# #21 Co-Hong System
func _event_21(side: Enums.Side, bonus: bool) -> void:
	_add_pending("redraw_global_demand", {"side": side})
	if bonus:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC)


# #22 Corsican Crisis
func _event_22(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("shift_in_country", {"country": "savoy_or_sardinia", "side": side})
		if bonus: _add_pending("vp_if_no_fr_squad_europe", {"side": side, "vp": 1})
	else:
		_add_pending("unflag_political_europe", {"side": side})
		if bonus: _add_pending("vp_if_no_br_in_spain", {"side": side, "vp": 1})


# #23 European Panic
func _event_23(side: Enums.Side, bonus: bool) -> void:
	var opp := GameManager.state.get_opponent(side)
	var diff := opp.current_debt - GameManager.state.get_player(side).current_debt
	var vp := mini(maxi(0, diff), 4)
	GameManager.state.score_vp(side, vp)
	if bonus:
		_add_pending("unflag_political_europe", {"side": side})


# #24 West African Gold Mining
func _event_24(side: Enums.Side, bonus: bool) -> void:
	_grant_event_ap(1, Enums.ActionType.ECONOMIC)
	if bonus:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC)  # Caribbean only


# #25 War of the Quadruple Alliance
func _event_25(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("move_br_squadron_for_vp", {"side": side, "vp": 2})
		if bonus:
			_add_pending("build_squadron_then_debt", {"side": side})
	else:
		_add_pending("shift_in_country", {"country": "spain", "side": side})
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC)


# #26 Salon d'Hercule
func _event_26(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		GameManager.state.france.take_debt(1)
		if bonus: GameManager.state.france.take_debt(2)
	else:
		_grant_event_ap(2, Enums.ActionType.DIPLOMATIC)
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC)


# #27 Bengal Famine
func _event_27(side: Enums.Side, bonus: bool) -> void:
	_add_pending("place_conflict_marker_choice", {"count": 2, "region": Enums.Region.INDIA, "side": side})


# #28 Father Le Loutre
func _event_28(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("place_conflict_marker_in_commodity", {"commodity": Enums.Commodity.FISH, "side": side})
		if bonus: _grant_event_ap(2, Enums.ActionType.MILITARY)
	else:
		_add_pending("place_conflict_marker_br_market", {"side": side})
		if bonus: _grant_event_ap(2, Enums.ActionType.ECONOMIC)


# #29 War of the Polish Succession
func _event_29(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		GameManager.state.britain.add_treaty_points(2)
		if bonus: _add_pending("shift_in_country", {"country": "russia", "side": side})
	else:
		GameManager.state.score_vp(side, 2)
		if bonus: _add_pending("shift_in_country", {"country": "russia_or_sweden", "side": side})


# #30 Jonathan's Coffee-House
func _event_30(side: Enums.Side, bonus: bool) -> void:
	_grant_event_ap(2, Enums.ActionType.ECONOMIC)
	if bonus:
		_grant_event_ap(1, Enums.ActionType.ECONOMIC)
		GameManager.state.get_player(side).reduce_debt(1)


# #31 Nootka Incident
func _event_31(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_grant_event_ap(2, Enums.ActionType.DIPLOMATIC)
		if bonus: _add_pending("score_per_br_alliance_spain_remove", {"side": side, "vp_each": 2})
	else:
		_add_pending("displace_br_squadron_navy_box", {"side": side})
		if bonus: _add_pending("construct_squadron", {"side": side})


# #32 Haitian Revolution
func _event_32(side: Enums.Side, bonus: bool) -> void:
	_add_pending("place_conflict_marker_in_caribbean_sugar", {"count": 1, "side": side, "extra_cost": true})
	if bonus:
		_add_pending("place_conflict_marker_in_caribbean_sugar", {"count": 2, "side": side, "extra_cost": true})


# #33 Loge des Neuf Sœurs
func _event_33(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("place_conflict_marker_in_subregion", {"subregion": "northern_colonies", "count": 1, "side": side})
		if bonus: _add_pending("vp_if_more_br_flags_na", {"side": side, "vp": 3})
	else:
		_add_pending("activate_advantage_outside_europe", {"side": side})
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC)


# #34 La Gabelle
func _event_34(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("exhaust_advantages_europe", {"count": 2, "side": side})
		if bonus: _grant_event_ap(2, Enums.ActionType.ECONOMIC)
	else:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC)
		if bonus:
			var vp := 3 if GameManager.state.france.has_keyword("Governance") else 2
			GameManager.state.score_vp(side, vp)


# #35 Jesuit Abolition
func _event_35(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("unflag_sugar_market", {"side": side})
		if bonus: _grant_event_ap(3, Enums.ActionType.ECONOMIC)
	else:
		GameManager.state.france.reduce_debt(2)
		if bonus: GameManager.state.score_vp(side, 2)


# #36 Wealth of Nations
func _event_36(side: Enums.Side, bonus: bool) -> void:
	GameManager.state.get_player(side).reduce_debt(2)
	if bonus:
		_grant_event_ap(3, Enums.ActionType.ECONOMIC)


# #37 Debt Crisis
func _event_37(side: Enums.Side, bonus: bool) -> void:
	var p := GameManager.state.get_player(side)
	var opp := GameManager.state.get_opponent(side)
	if p.available_debt() > opp.available_debt():
		_grant_event_ap(3, Enums.ActionType.ECONOMIC)
	if bonus:
		GameManager.state.score_vp(side, 2)


# #38 East Asia Piracy
func _event_38(side: Enums.Side, bonus: bool) -> void:
	var us := _count_squadrons_forts_local_alliances(side, Enums.Region.INDIA)
	var them := _count_squadrons_forts_local_alliances(GameManager.state.get_opponent(side).side, Enums.Region.INDIA)
	if us > them:
		GameManager.state.score_vp(side, 3)


# #39 Stamp Act
func _event_39(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		GameManager.state.britain.reduce_debt(2)
		if bonus: _grant_event_ap(2, Enums.ActionType.ECONOMIC)
	else:
		_add_pending("place_conflict_marker_in_subregion", {"subregion": "northern_colonies", "count": 1, "side": side})
		if bonus: _add_pending("place_conflict_marker_in_subregion", {"subregion": "northern_colonies", "count": 3, "side": side})


# #40 Falklands Crisis
func _event_40(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		var has_br := false
		for sid in GameManager.state.spaces:
			var ss: SpaceState = GameManager.state.spaces[sid]
			if ss.controlled_by == Enums.Side.BRITAIN and "spain" in sid:
				has_br = true; break
		if has_br: GameManager.state.score_vp(side, 1)
		if bonus: _add_pending("unflag_in_country", {"country": "spain", "side": side})
	else:
		var fr_in_spain := 0
		for sid in GameManager.state.spaces:
			var ss: SpaceState = GameManager.state.spaces[sid]
			if ss.controlled_by == Enums.Side.FRANCE and "spain" in sid:
				fr_in_spain += 1
		_grant_event_ap(fr_in_spain, Enums.ActionType.MILITARY)
		if bonus: _add_pending("remove_br_squadron_from_game", {"side": side})


# #41 Cook and Bougainville
func _event_41(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		var sq := GameManager.state.britain.total_squadrons()
		_grant_event_ap(sq / 2, Enums.ActionType.ECONOMIC)
		if bonus: _add_pending("draw_bonus_war_tile", {"side": side})
	else:
		if GameManager.state.france.can_build_squadron():
			GameManager.state.france.squadrons_in_navy_box += 1
		if bonus: GameManager.state.france.reduce_debt(2)


# ---------- Helpers ----------

func _is_symmetric() -> bool:
	return current_card.both_base != "" and current_card.british_base == "" and current_card.french_base == ""


func _grant_event_ap(amount: int, ap_type: Enums.ActionType) -> void:
	if amount <= 0:
		return
	# Stack onto ActionController's event AP pool. If already has same type, add; else replace.
	if ActionController.event_ap_type == Enums.ActionType.NONE or ActionController.event_ap_type == ap_type:
		ActionController.event_ap_type = ap_type
		ActionController.event_ap_remaining += amount
	else:
		ActionController.event_ap_remaining += amount  # Mixed; treat as same for simplicity


func _count_squadrons_forts_local_alliances(side: Enums.Side, region: Enums.Region) -> int:
	var count := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.region != region:
			continue
		if ss.controlled_by != side:
			continue
		if ss.data.space_type == Enums.SpaceType.NAVAL: count += 1
		elif ss.data.space_type == Enums.SpaceType.FORT and not ss.is_fort_damaged: count += 1
		elif ss.data.is_local_alliance: count += 1
	return count


# Generic regex-based fallback parser
func _apply_text(text: String, side: Enums.Side) -> void:
	if text == "":
		return
	var player := GameManager.state.get_player(side)
	var opponent := GameManager.state.get_opponent(side)

	var vp_re := RegEx.new()
	vp_re.compile(r"[Ss]core\s+(\d+)\s+VP")
	var m := vp_re.search(text)
	if m:
		GameManager.state.score_vp(side, int(m.get_string(1)))
		GameManager.vp_changed.emit(GameManager.state.vp)

	var rd_re := RegEx.new()
	rd_re.compile(r"[Rr]educe your Debt by (\d+)")
	m = rd_re.search(text)
	if m:
		player.reduce_debt(int(m.get_string(1)))

	var tp_re := RegEx.new()
	tp_re.compile(r"(?:[Gg]ain|[Tt]ake)\s+(\d+)\s+TRP")
	m = tp_re.search(text)
	if m:
		player.add_treaty_points(int(m.get_string(1)))


func _add_pending(choice_type: String, params: Dictionary) -> void:
	pending_choices.append({"type": choice_type, "params": params})


func resolve_choice(_index: int, target_space_id: String) -> bool:
	if pending_choices.is_empty():
		return false
	var choice = pending_choices[0]
	var params = choice["params"]
	if not (target_space_id in GameManager.state.spaces):
		return false
	var ss: SpaceState = GameManager.state.spaces[target_space_id]
	var side: Enums.Side = params["side"]

	var ok := false
	match choice["type"]:
		"place_conflict_marker_choice":
			if "region" in params and params["region"] >= 0 and ss.data.region != params["region"]:
				return false
			if "br_flagged" in params and ss.controlled_by != Enums.Side.BRITAIN:
				return false
			ok = ss.place_conflict_marker(params.get("extra_cost", false))
		"unflag_market_caribbean":
			if ss.data.region != Enums.Region.CARIBBEAN: return false
			if ss.data.space_type != Enums.SpaceType.MARKET: return false
			var from_kind: String = params.get("from", "")
			if from_kind == "enemy" and ss.controlled_by == side: return false
			if from_kind == "friendly" and ss.controlled_by != side: return false
			ok = ss.unflag(side) if ss.controlled_by != side else ss.unflag(_opp(side))
		"unflag_market_safe":
			if ss.data.space_type != Enums.SpaceType.MARKET: return false
			ok = ss.unflag(side)
		"unflag_political_europe":
			if ss.data.region != Enums.Region.EUROPE: return false
			if ss.data.space_type != Enums.SpaceType.POLITICAL: return false
			ok = ss.unflag(side)
		"unflag_in_country", "unflag_local_alliance_na":
			ok = ss.unflag(side)
		"unflag_cotton_market", "unflag_sugar_market":
			var commodity := Enums.Commodity.COTTON if "cotton" in choice["type"] else Enums.Commodity.SUGAR
			if ss.data.commodity != commodity: return false
			ok = ss.unflag(side)
		"shift_local_alliance_na", "shift_in_country", "shift_alliance_in_countries":
			ok = ss.shift(side)
		"place_conflict_marker_in_country", "place_conflict_marker_in_subregion", "place_conflict_marker_in_commodity":
			ok = ss.place_conflict_marker()
		"place_conflict_marker_in_caribbean_sugar":
			if ss.data.region != Enums.Region.CARIBBEAN or ss.data.commodity != Enums.Commodity.SUGAR:
				return false
			ok = ss.place_conflict_marker(params.get("extra_cost", false))
		"place_conflict_marker_br_market":
			if ss.data.space_type != Enums.SpaceType.MARKET or ss.controlled_by != Enums.Side.BRITAIN:
				return false
			ok = ss.place_conflict_marker()
		"damage_fort_or_shift_cotton_india":
			if ss.data.space_type == Enums.SpaceType.FORT and ss.controlled_by == _opp(side):
				ss.is_fort_damaged = true; ok = true
			elif ss.data.space_type == Enums.SpaceType.MARKET and ss.data.commodity == Enums.Commodity.COTTON and ss.data.region == Enums.Region.INDIA:
				ok = ss.shift(side)
		_:
			# Generic fallback - try a shift
			ok = ss.shift(side)

	if not ok:
		return false

	if "count" in params and params["count"] > 1:
		params["count"] -= 1
	else:
		pending_choices.remove_at(0)

	if pending_choices.is_empty():
		effects_resolved.emit()
	else:
		pending_choices_changed.emit(pending_choices)
	return true


func skip_choice(_index: int) -> void:
	if pending_choices.is_empty():
		return
	pending_choices.remove_at(0)
	if pending_choices.is_empty():
		effects_resolved.emit()
	else:
		pending_choices_changed.emit(pending_choices)


func has_pending() -> bool:
	return pending_choices.size() > 0


func _opp(side: Enums.Side) -> Enums.Side:
	return Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN
