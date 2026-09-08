extends Node

# Per-card event effects, plus a regex fallback parser for AP grants and simple effects.

signal pending_choices_changed(choices: Array)
signal effects_resolved

var pending_choices: Array = []  # {type, params, count_remaining}
var current_card: EventCard = null
var current_side: Enums.Side = Enums.Side.NONE
var current_with_bonus: bool = false

# Choice types that require the player to click a board space (resolve_choice handles them).
# Anything NOT in this set is a non-spatial effect executed immediately in _finalize_pending,
# so an Event can never leave a human stuck with an unclickable pending choice.
const _SPATIAL_TYPES := {
	"place_conflict_marker_choice": true,
	"advantage_remove_naval":true,
	"unflag_market_caribbean": true,
	"unflag_market_safe": true,
	"unflag_political_europe": true,
	"unflag_in_country": true,
	"unflag_local_alliance_na": true,
	"unflag_cotton_market": true,
	"unflag_sugar_market": true,
	"shift_local_alliance_na": true,
	"shift_in_country": true,
	"shift_alliance_in_countries": true,
	"place_conflict_marker_in_country": true,
	"place_conflict_marker_in_subregion": true,
	"place_conflict_marker_in_commodity": true,
	"place_conflict_marker_in_caribbean_sugar": true,
	"place_conflict_marker_br_market": true,
	"damage_fort_or_shift_cotton_india": true,
}


func bonus_condition_met(card: EventCard, side: Enums.Side, reveal_keyword: bool = true) -> bool:
	var condition = card.bonus_condition
	if condition == "":
		return false
	var player = GameManager.state.get_player(side)
	var opponent = GameManager.state.get_opponent(side)
	if condition in ["Mercantilism", "Governance", "Finance", "Scholarship", "Style"]:
		for ministry in player.ministry_cards:
			if ministry.has_keyword(condition) and (ministry.is_revealed or (not reveal_keyword and MinistryDecisions.can_reveal(ministry,side))):
				return true
		return false
	if "Available Debt" in condition:
		var margin = 3 if "at least 3" in condition else 1
		return player.available_debt() - opponent.available_debt() >= margin
	if "Bonus War Tiles" in condition:
		var own = 0
		var other = 0
		for theater in WarManager.bonus_war_tiles_in_theater.values():
			own += theater.get(side, []).size()
			other += theater.get(opponent.side, []).size()
		return own > other
	if condition == "Mediterranean Intrigue":
		var advantage = AdvantageManager.advantages.get("mediterranean_intrigue_adv")
		return advantage != null and advantage.controlled_by == side
	if "Prestige spaces in Scotland and Ireland" in condition:
		var score = 0
		for ss in GameManager.state.spaces.values():
			if ss.data.is_prestige and not ss.has_conflict_marker and ("scotland" in ss.data.id or "ireland" in ss.data.id):
				if ss.controlled_by == side: score += 1
				elif ss.controlled_by == opponent.side: score -= 1
		return score > 0
	return false

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

	_finalize_pending()


# ---------- Per-card handlers ----------

# #1 Carnatic War: Place 1 Conflict marker in India for each Local Alliance there
func _event_1(side: Enums.Side, bonus: bool) -> void:
	var count := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.is_local_alliance and ss.data.region == Enums.Region.INDIA and ss.controlled_by == side and not ss.has_conflict_marker:
			count += 1
	if count > 0:
		_add_pending("place_conflict_marker_choice", {"count": count, "region": Enums.Region.INDIA, "side": side})
	if bonus:
		# Damage enemy Fort or shift Cotton market in India
		_add_pending("damage_fort_or_shift_cotton_india", {"side": side, "count": 1})


# #2 Acts of Union (asymmetric)
func _event_2(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		# 1 DP (unflagging in Europe only) — approximated as a Diplomatic AP grant.
		_grant_event_ap(1, Enums.ActionType.DIPLOMATIC, {"region":Enums.Region.EUROPE,"unflag":true})
		if bonus: GameManager.state.score_vp(side, 2)
	else:
		_grant_event_ap(2, Enums.ActionType.DIPLOMATIC)
		if bonus: _add_pending("unflag_political_europe", {"side": side,"exclude_countries":["spain","austria"]})


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
		if bonus: GameManager.state.france.incur_debt(1)
	else:
		_add_pending("place_conflict_marker_choice", {"count": 1, "region": Enums.Region.CARIBBEAN, "side": side, "br_flagged": true,"market_only":true})
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC)


# #6 Native American Alliances
func _event_6(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("shift_local_alliance_na", {"side": side})
		if bonus: _activate_owned_advantage(side, [Enums.Region.NORTH_AMERICA])
	else:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC, {"region":Enums.Region.NORTH_AMERICA})
		if bonus: _add_pending("unflag_local_alliance_na", {"side": side})


# #7 Austro-Spanish Rivalry
func _event_7(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("place_conflict_marker_in_country", {"country": "spain", "side": side})
		if bonus: _add_pending("remove_bonus",{"side":side,"owner":Enums.Side.FRANCE})
	else:
		_add_pending("unflag_in_country", {"country": "dutch_republic", "side": side})
		if bonus: _add_pending("ap_type", {"side":side,"amount":2,"restrictions":{"region":Enums.Region.INDIA}})


# #8 Tax Reform — reduce Debt; unreduced amount becomes EP (special note)
func _event_8(side: Enums.Side, bonus: bool) -> void:
	var want := 3 if bonus else 2
	var got := GameManager.state.get_player(side).reduce_debt(want)
	var shortfall := want - got
	if shortfall > 0:
		_grant_event_ap(shortfall, Enums.ActionType.ECONOMIC)


# #9 Great Northern War
func _event_9(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("shift_in_country", {"country": "german_states", "side": side, "vp_if_both": 2})
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC)
	else:
		# Shift Russia; if it is already FR-flagged, score 2 VP instead of shifting.
		var russia := _find_space_in_country("russia")
		if russia != null and russia.controlled_by == Enums.Side.FRANCE:
			GameManager.state.score_vp(side, 2)
		elif russia != null:
			russia.shift(side)
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC)


# #10 Vatican Politics
func _event_10(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_grant_event_ap(2, Enums.ActionType.DIPLOMATIC,{"countries":["german_states","prussia","dutch_republic"]})
		if bonus: _grant_event_ap(1, Enums.ActionType.DIPLOMATIC,{"region":Enums.Region.EUROPE})
	else:
		_add_pending("shift_in_country", {"country": "spain_or_austria", "side": side})
		if bonus: _add_pending("conditional_vp", {"side":side,"condition":"no_enemy_country_flags","countries":["spain","austria"],"vp":2})


# #11 Calico Acts
func _event_11(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC, {"unflag":true})
		if bonus: _add_pending("score_commodity", {"side":side,"commodity":Enums.Commodity.COTTON,"optional":true})
	else:
		_add_pending("unflag_cotton_market", {"side": side})
		if bonus: _add_pending("squadron_choice",{"side":side,"owner":Enums.Side.BRITAIN,"navy":false})


# #12 Military Spending Overruns: opponent damages fort/removes squadron/removes bonus tile
func _event_12(side: Enums.Side, bonus: bool) -> void:
	_add_pending("war_loss",{"side":side,"owner":_opp(side),"chooser":_opp(side),"navy":false})
	if bonus:
		_add_pending("war_loss",{"side":side,"owner":_opp(side),"chooser":_opp(side),"navy":false})


# #13 Alberoni's Ambition
func _event_13(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC, {"flag_adjacent_market":true})
		if bonus: _grant_event_ap(1, Enums.ActionType.ECONOMIC, {"flag_adjacent_market":true})
	else:
		_add_pending("shift_alliance_in_countries", {"countries": ["austria","dutch_republic","spain"], "side": side})
		if bonus and _is_flagged_by("savoy", side) and _is_flagged_by("sardinia", side):
			GameManager.state.score_vp(side, 3)


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
	_add_pending("place_conflict_marker_choice", {"count": 1, "region": Enums.Region.CARIBBEAN, "side": side,"market_only":true})
	if bonus:
		_add_pending("place_conflict_marker_choice", {"count": 1, "region": Enums.Region.CARIBBEAN, "side": side,"market_only":true})


# #17 Pacte de Famille
func _event_17(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		ActionController.event_diplomatic_discount=true
		if bonus: _grant_event_ap(1,Enums.ActionType.DIPLOMATIC)
	else:
		_add_pending("advantage_choice",{"side":side,"owner":side,"regions":[Enums.Region.EUROPE],"mode":"refresh","count":2,"optional":true})
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC,{"countries":["spain","austria"]})


# #18 Byng's Trial
func _event_18(side: Enums.Side, _bonus: bool) -> void:
	if side==Enums.Side.BRITAIN: _add_pending("byng",{"side":side})
	else: _add_pending("squadron_choice",{"side":side,"owner":Enums.Side.BRITAIN,"destination":"next_turn"})

# #19 Le Beau Monde
func _event_19(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_put_commodity_in_global_demand(side, [Enums.Commodity.FUR, Enums.Commodity.COTTON])
		if bonus: _grant_event_ap(1, Enums.ActionType.ECONOMIC)
	else:
		_grant_event_ap(1, Enums.ActionType.DIPLOMATIC, {"region":Enums.Region.EUROPE})
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC, {"region":Enums.Region.EUROPE})


# #20 Hyder Ali — take a Local Alliance -or- place 2 Conflict markers in India.
# Implemented as the place-2-markers option (also the AI-friendly branch).
func _event_20(side: Enums.Side, bonus: bool) -> void:
	_add_pending("hyder",{"side":side})
	if bonus:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC, {"region":Enums.Region.INDIA})


# #21 Co-Hong System
func _event_21(side: Enums.Side, bonus: bool) -> void:
	_redraw_global_demand(side)
	if bonus:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC, {"region":Enums.Region.INDIA})


# #22 Corsican Crisis
func _event_22(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("shift_in_country", {"country": "savoy_or_sardinia", "side": side})
		# Score 1 VP if France has no Squadrons (Naval spaces) in Europe.
		if bonus and _count_naval_controlled(Enums.Side.FRANCE, Enums.Region.EUROPE) == 0:
			GameManager.state.score_vp(side, 1)
	else:
		_add_pending("unflag_political_europe", {"side": side})
		# Score 1 VP if Britain has no flags in Spain.
		if bonus: _add_pending("conditional_vp", {"side":side,"condition":"no_enemy_country_flags","countries":["spain"],"vp":1})


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
		_grant_event_ap(2, Enums.ActionType.ECONOMIC, {"region":Enums.Region.CARIBBEAN})


# #25 War of the Quadruple Alliance
func _event_25(side: Enums.Side, bonus: bool) -> void:
	if side==Enums.Side.BRITAIN:
		_add_pending("squadron_choice",{"side":side,"owner":side,"destination":"next_turn","vp":2})
		if bonus: _add_pending("build_squadron_then_debt",{"side":side})
	else:
		_add_pending("shift_in_country",{"country":"spain","side":side})
		if bonus: _grant_event_ap(1,Enums.ActionType.DIPLOMATIC)

# #26 Salon d'Hercule
func _event_26(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		GameManager.state.france.incur_debt(1)
		if bonus: GameManager.state.france.incur_debt(2)
	else:
		_grant_event_ap(2, Enums.ActionType.DIPLOMATIC, {"region":Enums.Region.EUROPE})
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC, {"region":Enums.Region.EUROPE})


# #27 Bengal Famine
func _event_27(side: Enums.Side, bonus: bool) -> void:
	_add_pending("place_conflict_marker_choice", {"count": 2, "region": Enums.Region.INDIA, "side": side,"optional":true})


# #28 Father Le Loutre
func _event_28(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("place_conflict_marker_in_commodity", {"commodity": Enums.Commodity.FISH, "side": side})
		if bonus: _grant_event_ap(2, Enums.ActionType.MILITARY, {"region":Enums.Region.NORTH_AMERICA})
	else:
		_add_pending("place_conflict_marker_br_market", {"side": side})
		if bonus: _grant_event_ap(2, Enums.ActionType.ECONOMIC, {"region":Enums.Region.NORTH_AMERICA})


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
		_add_pending("ap_type",{"side":side,"amount":2})
		if bonus: _score_and_remove_alliances(side, "spain", 2)
	else:
		_add_pending("squadron_choice",{"side":side,"owner":Enums.Side.BRITAIN,"navy":false})
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
		# Score 3 VP if there are more BR than FR flags in North America.
		if bonus: _add_pending("conditional_vp", {"side":side,"condition":"more_region_flags","region":Enums.Region.NORTH_AMERICA,"vp":3})
	else:
		_activate_owned_advantage(side, [Enums.Region.NORTH_AMERICA, Enums.Region.CARIBBEAN, Enums.Region.INDIA])
		if bonus: _grant_event_ap(2, Enums.ActionType.DIPLOMATIC)


# #34 La Gabelle
func _event_34(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("advantage_choice",{"side":side,"mode":"exhaust","count":2,"optional":true})
		if bonus: _grant_event_ap(2, Enums.ActionType.ECONOMIC)
	else:
		_grant_event_ap(2, Enums.ActionType.ECONOMIC)
		if bonus:
			var vp=2
			for minister in GameManager.state.france.ministry_cards:
				if minister.is_revealed and minister.has_keyword("Governance"):
					vp=3
			GameManager.state.score_vp(side, vp)


# #35 Jesuit Abolition
func _event_35(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		_add_pending("unflag_sugar_market", {"side": side})
		if bonus: _grant_event_ap(3, Enums.ActionType.ECONOMIC, {"region":Enums.Region.CARIBBEAN})
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
		_grant_event_ap(3, Enums.ActionType.ECONOMIC, {"unflag":true})
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
		# Base places 1; bonus makes it 3 total ("Place 3 instead"), not 1+3.
		var cnt := 3 if bonus else 1
		_add_pending("place_conflict_marker_in_subregion", {"subregion": "northern_colonies", "count": cnt, "side": side})


# #40 Falklands Crisis
func _event_40(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		var has_br := false
		for sid in GameManager.state.spaces:
			var ss: SpaceState = GameManager.state.spaces[sid]
			if ss.controlled_by == Enums.Side.BRITAIN and "spain" in sid and not ss.has_conflict_marker:
				has_br = true; break
		if has_br: GameManager.state.score_vp(side, 1)
		if bonus: _add_pending("unflag_in_country", {"country": "spain", "side": side})
	else:
		var fr_in_spain := 0
		for sid in GameManager.state.spaces:
			var ss: SpaceState = GameManager.state.spaces[sid]
			if ss.controlled_by == Enums.Side.FRANCE and "spain" in sid and not ss.has_conflict_marker:
				fr_in_spain += 1
		_grant_event_ap(fr_in_spain, Enums.ActionType.MILITARY)
		if bonus: _add_pending("squadron_choice",{"side":side,"owner":Enums.Side.BRITAIN,"destination":"removed"})


# #41 Cook and Bougainville
func _event_41(side: Enums.Side, bonus: bool) -> void:
	if side == Enums.Side.BRITAIN:
		var sq := GameManager.state.britain.total_squadrons()
		_grant_event_ap(sq / 2, Enums.ActionType.ECONOMIC)
		if bonus: _add_pending("draw_bonus",{"side":side})
	else:
		if GameManager.state.france.can_build_squadron():
			GameManager.state.france.squadrons_in_navy_box += 1
		if bonus: GameManager.state.france.reduce_debt(2)


# ---------- Helpers ----------

func _is_symmetric() -> bool:
	return current_card.both_base != "" and current_card.british_base == "" and current_card.french_base == ""


func _grant_event_ap(amount: int, ap_type: Enums.ActionType, restrictions: Dictionary = {}) -> void:
	ActionController.grant_event_ap(amount,ap_type,restrictions)


func _count_squadrons_forts_local_alliances(side: Enums.Side, region: Enums.Region) -> int:
	var count := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.region != region:
			continue
		if ss.controlled_by != side:
			continue
		if ss.data.space_type == Enums.SpaceType.NAVAL: count += 1
		# 손상된 요새도 지배는 유지한다. 전쟁 전력 보너스와 카드의 보유 수는 다르다.
		elif ss.data.space_type == Enums.SpaceType.FORT: count += 1
		elif ss.data.is_local_alliance and not ss.has_conflict_marker: count += 1
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
	if MinistryDecisions.has_pending(): return false
	if pending_choices.is_empty():
		return false
	var choice = pending_choices[0]
	if not is_valid_target(target_space_id): return false
	var params = choice["params"]
	if not (target_space_id in GameManager.state.spaces):
		return false
	var ss: SpaceState = GameManager.state.spaces[target_space_id]
	var side: Enums.Side = params["side"]

	var ok := false
	match choice["type"]:
		"advantage_remove_naval":
			GameManager.state.get_player(ss.controlled_by).squadrons_in_navy_box += 1
			ss.controlled_by = Enums.Side.NONE
			ActionController._recount_squadrons()
			ok = true
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
	if params.has("vp_if_both") and _count_flags_in(["german_states"],side)==2:
		GameManager.state.score_vp(side,params.vp_if_both)
	ActionController._recount_squadrons()
	AdvantageManager.recompute_control()

	if "count" in params and params["count"] > 1:
		params["count"] -= 1
	else:
		pending_choices.remove_at(0)

	_drop_unresolvable_front()
	if pending_choices.is_empty():
		effects_resolved.emit()
	else:
		pending_choices_changed.emit(pending_choices)
	return true


func skip_choice(_index: int) -> void:
	if pending_choices.is_empty() or not pending_choices[0].params.get("optional",false):
		return
	pending_choices.remove_at(0)
	_drop_unresolvable_front()
	if pending_choices.is_empty():
		effects_resolved.emit()
	else:
		pending_choices_changed.emit(pending_choices)


func has_pending() -> bool:
	return pending_choices.size() > 0


func is_valid_target(space_id: String) -> bool:
	# Public: does this board space satisfy the CURRENT pending choice? Used by the
	# board to highlight clickable targets during an Event effect.
	if pending_choices.is_empty():
		return false
	if not (space_id in GameManager.state.spaces):
		return false
	var choice = pending_choices[0]
	if not _SPATIAL_TYPES.has(choice["type"]):
		return false
	return _space_matches(choice, GameManager.state.spaces[space_id])


func _opp(side: Enums.Side) -> Enums.Side:
	return Enums.Side.FRANCE if side == Enums.Side.BRITAIN else Enums.Side.BRITAIN


# ---------- Soft-lock-safe finalization ----------

func _finalize_pending() -> void:
	if MinistryDecisions.has_pending(): return
	_drop_unresolvable_front()
	if MinistryDecisions.has_pending(): return
	ActionController._recount_squadrons()
	AdvantageManager.recompute_control()
	if pending_choices.is_empty(): effects_resolved.emit()
	else: pending_choices_changed.emit(pending_choices)


func _drop_unresolvable_front() -> void:
	# After a resolve/skip, discard any leading spatial choice that no longer has a
	# legal target (e.g. its only targets were just consumed).
	while not pending_choices.is_empty():
		if MinistryDecisions.has_pending(): return
		var choice = pending_choices[0]
		if CardChoices.handles(choice.type) and not CardChoices.options(choice).is_empty(): break
		if not _SPATIAL_TYPES.has(choice["type"]):
			pending_choices.remove_at(0)
			_execute_nonspatial(choice)
			continue
		if _count_valid_targets(choice) <= 0:
			_log_skip(choice)
			pending_choices.remove_at(0)
			continue
		break


func _count_valid_targets(choice: Dictionary) -> int:
	var n := 0
	for sid in GameManager.state.spaces:
		if _space_matches(choice, GameManager.state.spaces[sid]):
			n += 1
	return n


func _can_place_marker(ss: SpaceState) -> bool:
	if ss.has_conflict_marker:
		return false
	return ss.data.space_type == Enums.SpaceType.MARKET or ss.data.space_type == Enums.SpaceType.POLITICAL


func _space_matches(choice: Dictionary, ss: SpaceState) -> bool:
	# Dry-run mirror of resolve_choice's success conditions (no mutation).
	var params: Dictionary = choice["params"]
	var side: int = params.get("side", current_side)
	if ss.has_usa_flag or ss.data.available_from_era > GameManager.state.current_era: return false
	if ss.data.id.begins_with("usa_") and (GameManager.state.current_turn!=6 or not GameManager.state.spaces.values().any(func(s): return s.has_usa_flag)): return false
	if params.has("region") and params.region >= 0 and ss.data.region != params.region: return false
	if params.get("alliance_only",false) and not ss.data.is_alliance: return false
	if params.has("country"):
		var countries: Array = params.country.split("_or_")
		if not countries.any(func(c): return _sid_in_country(ss.data.id,c)): return false
	if params.has("countries") and not params.countries.any(func(c): return _sid_in_country(ss.data.id,c)): return false
	if params.has("commodity") and ss.data.commodity != params.commodity: return false
	if params.has("subregion") and ss.data.sub_region != Enums.SubRegion.get(params.subregion.to_upper(),-1): return false
	if "local_alliance_na" in choice.type and (not ss.data.is_local_alliance or ss.data.region != Enums.Region.NORTH_AMERICA): return false
	if choice.type == "shift_alliance_in_countries" and not ss.data.is_alliance: return false
	if choice.type == "shift_in_country" and ss.data.space_type != Enums.SpaceType.POLITICAL: return false
	if choice.type == "unflag_market_safe" and WarFlow._would_isolate(ss): return false
	if choice.type == "damage_fort_or_shift_cotton_india" and ss.data.region != Enums.Region.INDIA: return false
	if params.get("unprotected",false) and ActionController._is_market_protected(ss,ss.controlled_by): return false
	if params.get("market_only",false) and ss.data.space_type != Enums.SpaceType.MARKET: return false
	if params.has("exclude_countries") and params.exclude_countries.any(func(c):return _sid_in_country(ss.data.id,c)): return false
	match choice["type"]:
		"advantage_remove_naval": return ss.data.space_type == Enums.SpaceType.NAVAL and ss.controlled_by == _opp(side)
		"place_conflict_marker_choice":
			if "region" in params and params["region"] >= 0 and ss.data.region != params["region"]:
				return false
			if params.get("br_flagged", false) and ss.controlled_by != Enums.Side.BRITAIN:
				return false
			return _can_place_marker(ss)
		"unflag_market_caribbean":
			if ss.data.region != Enums.Region.CARIBBEAN or ss.data.space_type != Enums.SpaceType.MARKET:
				return false
			var from_kind: String = params.get("from", "")
			if from_kind == "enemy":
				return ss.controlled_by == _opp(side)
			if from_kind == "friendly":
				return ss.controlled_by == side
			return ss.controlled_by != Enums.Side.NONE
		"unflag_market_safe":
			return ss.data.space_type == Enums.SpaceType.MARKET and ss.controlled_by == _opp(side)
		"unflag_political_europe":
			return ss.data.region == Enums.Region.EUROPE and ss.data.space_type == Enums.SpaceType.POLITICAL and ss.controlled_by == _opp(side)
		"unflag_in_country", "unflag_local_alliance_na":
			return ss.controlled_by == _opp(side)
		"unflag_cotton_market", "unflag_sugar_market":
			var commodity := Enums.Commodity.COTTON if "cotton" in choice["type"] else Enums.Commodity.SUGAR
			return ss.data.commodity == commodity and ss.controlled_by == _opp(side)
		"shift_local_alliance_na", "shift_in_country", "shift_alliance_in_countries":
			return ss.is_empty() or ss.controlled_by == _opp(side)
		"place_conflict_marker_in_country", "place_conflict_marker_in_subregion", "place_conflict_marker_in_commodity":
			return _can_place_marker(ss)
		"place_conflict_marker_in_caribbean_sugar":
			return ss.data.region == Enums.Region.CARIBBEAN and ss.data.commodity == Enums.Commodity.SUGAR and _can_place_marker(ss)
		"place_conflict_marker_br_market":
			return ss.data.space_type == Enums.SpaceType.MARKET and ss.controlled_by == Enums.Side.BRITAIN and _can_place_marker(ss)
		"damage_fort_or_shift_cotton_india":
			if ss.data.space_type == Enums.SpaceType.FORT and ss.controlled_by == _opp(side) and not ss.is_fort_damaged:
				return true
			return ss.data.space_type == Enums.SpaceType.MARKET and ss.data.commodity == Enums.Commodity.COTTON \
				and ss.data.region == Enums.Region.INDIA and (ss.is_empty() or ss.controlled_by == _opp(side))
	return false


func _execute_nonspatial(choice: Dictionary) -> void:
	# Best-effort immediate resolution for effects that don't target a board space.
	var params: Dictionary = choice["params"]
	var side: int = params.get("side", current_side)
	var p := GameManager.state.get_player(side)
	var opp := GameManager.state.get_opponent(side)
	match choice["type"]:
		"squadron_discount_2mp":
			ActionController.event_construct_discount += 2
		"construct_squadron":
			if p.can_build_squadron():
				p.squadrons_in_navy_box += 1
				_log_effect(side, "함대 1척 건조")
		"build_squadron_then_debt":
			if p.can_build_squadron():
				p.squadrons_in_navy_box += 1
				pending_choices.push_front({"type":"build_payment","params":{"side":side}})
		"move_br_squadron_to_navy", "displace_br_squadron_navy_box":
			if opp.squadrons_on_map > 0:
				opp.squadrons_on_map -= 1
				opp.squadrons_in_navy_box += 1
				_log_effect(side, "상대 함대 1척을 해군 상자로 이동")
		"remove_br_squadron_from_game":
			if opp.squadrons_on_map > 0:
				opp.squadrons_on_map -= 1
				_log_effect(side, "상대 함대 1척 제거")
			elif opp.squadrons_in_navy_box > 0:
				opp.squadrons_in_navy_box -= 1
				_log_effect(side, "상대 함대 1척 제거")
		"move_br_squadron_for_vp":
			if opp.squadrons_on_map > 0:
				opp.squadrons_on_map -= 1
				opp.squadrons_in_navy_box += 1
				GameManager.state.score_vp(side, params.get("vp", 2))
				_log_effect(side, "상대 함대 이동, 승점 +%d" % params.get("vp", 2))
		"opponent_choice_damage_or_squadron":
			if opp.squadrons_on_map > 0:
				opp.squadrons_on_map -= 1
			else:
				_damage_one_fort(opp.side)
			_log_effect(side, "상대: 함대 제거 또는 요새 손상")
		"refresh_advantages_europe":
			_set_advantage_exhaustion(side, Enums.Region.EUROPE, params.get("count", 1), false)
		"exhaust_advantages_europe":
			_set_advantage_exhaustion(_opp(side), Enums.Region.EUROPE, params.get("count", 1), true)
		"draw_war_tiles_ireland":
			var count = _count_flags_in(["ireland"],side)
			for th in WarManager.get_upcoming_theaters():
				if "jacobite" in th.id and count>0: pending_choices.push_front({"type":"draw_bonus","params":{"side":side,"count":count,"only_theater":th.id}})
		"conditional_vp":
			# 보너스 사용 자격은 카드 사용 전에 확정하지만, 보너스 효과의 결과 조건은
			# 기본 효과를 완료한 상태에서 판정한다 (§5.2.2, Vatican Politics).
			var met = false
			if params.condition=="no_enemy_country_flags": met=_count_flags_in(params.countries,_opp(side))==0
			if params.condition=="more_region_flags": met=_count_flags_in_region(side,params.region)>_count_flags_in_region(_opp(side),params.region)
			if met: GameManager.state.score_vp(side,params.vp)
		_:
			# Effect requires a subsystem not modeled precisely (global demand redraw,
			# advantage activation, conditional VP). Skip safely and log rather than
			# apply a wrong effect or soft-lock.
			_log_skip(choice)


func _set_advantage_exhaustion(side: int, region: int, count: int, exhausted: bool) -> void:
	if not has_node("/root/AdvantageManager"):
		return
	var done := 0
	for adv_id in AdvantageManager.advantages:
		if done >= count:
			break
		var adv = AdvantageManager.advantages[adv_id]
		if adv.controlled_by == side and adv.region == region and adv.is_exhausted != exhausted:
			adv.is_exhausted = exhausted
			done += 1
	if done > 0:
		_log_effect(side, ("이점 %d개 소진" if exhausted else "이점 %d개 회복") % done)


func _damage_one_fort(side: int) -> void:
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.space_type == Enums.SpaceType.FORT and ss.controlled_by == side and not ss.is_fort_damaged:
			ss.is_fort_damaged = true
			return


func _log_effect(side: int, msg: String) -> void:
	if has_node("/root/GameLog"):
		GameLog.log_entry(side, "event", msg)


func _log_skip(choice: Dictionary) -> void:
	if has_node("/root/GameLog"):
		GameLog.log_entry(current_side, "event", "효과 건너뜀: %s" % choice["type"])


# ---------- Country / region / commodity queries (used by per-card conditionals) ----------

func _sid_in_country(sid: String, country: String) -> bool:
	# Prefix match so "russia" does not match "prussia_alliance", etc.
	return sid == country or sid.begins_with(country + "_")


func _find_space_in_country(country: String) -> SpaceState:
	for sid in GameManager.state.spaces:
		if _sid_in_country(sid, country):
			return GameManager.state.spaces[sid]
	return null


func _count_flags_in(countries: Array, side: int) -> int:
	var n := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by != side or ss.has_conflict_marker:
			continue
		for c in countries:
			if _sid_in_country(sid, c):
				n += 1
				break
	return n


func _is_flagged_by(country: String, side: int) -> bool:
	for sid in GameManager.state.spaces:
		if _sid_in_country(sid, country) and GameManager.state.spaces[sid].controlled_by == side and not GameManager.state.spaces[sid].has_conflict_marker:
			return true
	return false


func _count_flags_in_region(side: int, region: int) -> int:
	var n := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by == side and ss.data.region == region and not ss.has_conflict_marker and ss.data.space_type!=Enums.SpaceType.NAVAL:
			n += 1
	return n


func _count_naval_controlled(side: int, region: int) -> int:
	var n := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by == side and ss.data.region == region and ss.data.space_type == Enums.SpaceType.NAVAL:
			n += 1
	return n


func _count_commodity_markets(side: int, commodity: int) -> int:
	var n := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by == side and ss.data.space_type == Enums.SpaceType.MARKET \
				and ss.data.commodity == commodity and not ss.has_conflict_marker:
			n += 1
	return n


func _activate_owned_advantage(side: int, regions: Array) -> void:
	_add_pending("advantage_choice",{"side":side,"mode":"activate","regions":regions})


func _score_and_remove_alliances(side: int, country: String, vp_each: int) -> void:
	# Event #31 bonus: score per own alliance flag in a country, then remove those flags.
	var scored := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if _sid_in_country(sid, country) and ss.controlled_by == side and ss.data.is_alliance:
			GameManager.state.score_vp(side, vp_each)
			ss.controlled_by = Enums.Side.NONE
			ss.remove_conflict_marker()
			scored += vp_each
	if scored > 0:
		_log_effect(side, "%s 동맹 제거, 승점 +%d" % [country, scored])


func _put_commodity_in_global_demand(side: int, options: Array) -> void:
	_add_pending("demand_add",{"side":side,"commodities":options,"optional":true})

func _redraw_global_demand(side: int) -> void:
	var options: Array = [Enums.Commodity.FISH,Enums.Commodity.FUR,Enums.Commodity.SPICE,Enums.Commodity.SUGAR,Enums.Commodity.TOBACCO,Enums.Commodity.COTTON]
	options=options.filter(func(c): return c not in GameManager.state.current_global_demand)
	if options.is_empty(): return
	options.shuffle()
	_add_pending("demand_replace",{"side":side,"drawn":options[0]})


func choice_options() -> Array:
	if pending_choices.is_empty(): return []
	return CardChoices.options(pending_choices[0]) if CardChoices.handles(pending_choices[0].type) else []

func resolve_option(id: String) -> bool:
	if MinistryDecisions.has_pending(): return false
	if pending_choices.is_empty(): return false
	for option in choice_options():
		if option.id != id: continue
		var choice = pending_choices.pop_front()
		if option.id != "skip" and choice.params.get("count",1)>1:
			choice.params.count -= 1
			pending_choices.push_front(choice.duplicate(true))
		CardChoices.resolve(choice,option)
		_finalize_pending()
		return true
	return false
