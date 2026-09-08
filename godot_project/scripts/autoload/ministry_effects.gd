extends Node

# Ministry card effects per rule §3.5. Covers all 26 cards (FR + BR) via several hooks:
# - get_extra_major_ap()      : bonus AP granted at begin_action_round (type-matched)
# - passive_shift_discount()  : per-space DP/EP cost reduction (queried by ActionController)
# - get_first_debt_bonus()    : extra AP on the first Debt of an AR (M-23 Turgot)
# - on_debt_taken()           : Merchant Banks (M-17)
# - on_advantage_exhausted()  : Pompadour (M-13) / James Watt (M-19) TRP
# - apply_award_bonus()       : region Award VP/TRP modifiers (M-3/M-18/M-12) — called by AwardManager
# - apply_end_of_peace_turn() : John Law (M-2)
# - apply_scoring_bonuses()   : East India Co (M-7), Voltaire (M-14)
# - activate_manual()         : user-clicked one-shot abilities

signal ministry_triggered(card_id: String, message: String)

# James Watt (M-19): when true, opponent forced over-limit debt scores no VP (checked by GameManager)
var watt_active_for_britain: bool = false


func _ready() -> void:
	pass


func _has(side: int, card_id: String) -> bool:
	if GameManager.state == null:
		return false
	for c in GameManager.state.get_player(side).ministry_cards:
		if c.id == card_id and MinistryDecisions.active(c):
			return true
	return false


func _reveal(side: int, card_id: String) -> void:
	for c in GameManager.state.get_player(side).ministry_cards:
		if c.id == card_id:
			c.reveal()
			return


# =====================================================================
# Manual activation (MinistryHand "Activate")
# =====================================================================
func activate_manual(card: MinistryCard, side: int) -> void:
	if card.is_ability_exhausted(0):
		return
	card.reveal()
	var fired := true
	match card.id:
		"M-5":  # Robert Walpole — draw 1 Event, discard 1
			_walpole_draw_discard(side)
		"M-8":  # Bank of England — +1 Debt Limit (once/turn)
			GameManager.state.britain.debt_limit += 1
			_log(side, "잉글랜드 은행: 채무 한도 +1")
		"M-10":  # Edmond Halley — discard 1 Event → +1 TRP
			_halley_discard_for_trp(side)
		"M-4":  # Jacobite Uprisings — spend 3 MP to score VP for FR Scotland/Ireland spaces (max 4)
			_jacobite_score(side)
		"M-9":  # New World Huguenots — place a Huguenots marker (adds +1 CP cost) on a FR territory
			_place_huguenots(side)
		"M-21":  # Townshend Acts — flavor marker; enables minor unflag of a commodity's markets
			_log(side, "타운센드법: 이번 턴 부수 행동으로 지정 상품 시장 깃발 제거 가능")
		"M-25":  # Marquis de Condorcet — allow event play without event symbol (flag set)
			GameManager.state.get_player(side).condorcet_free_event = true
			_log(side, "콩도르세: 이번 라운드 이벤트 심볼 없이 이벤트 사용 가능")
		"M-11", "M-15", "M-1", "M-24", "M-20", "M-22", "M-6", "M-16":
			# These are auto-applied via get_extra_major_ap / passive_shift_discount; no manual effect
			fired = false
		"M-26", "M-13", "M-19", "M-23", "M-17", "M-2", "M-3", "M-7", "M-12", "M-14", "M-18":
			# Passive / hook-driven; manual click just reveals
			fired = false
		_:
			fired = false
	if fired:
		card.exhaust_ability(0)


# =====================================================================
# Bonus AP at begin_action_round (auto, type-matched)
# =====================================================================
func get_extra_major_ap(side: int, action_type: int) -> int:
	var p := GameManager.state.get_player(side)
	var bonus := 0
	for card in p.ministry_cards:
		match card.id:
			"M-15":  # Pitt the Elder — +1 DP (non-Prestige shifts), once/turn
				if action_type == Enums.ActionType.DIPLOMATIC and not card.is_ability_exhausted(0):
					bonus += 1
					card.exhaust_ability(0); card.reveal()
			"M-11":  # Choiseul — +1 MP (war tiles/squadrons), once/turn
				if action_type == Enums.ActionType.MILITARY and not card.is_ability_exhausted(0):
					bonus += 1
					card.exhaust_ability(0); card.reveal()
			"M-1":  # Cardinal Ministers — +DP per Savoy/Sardinia/Spain-Prestige/Austria-Prestige (max 3)
				if action_type == Enums.ActionType.DIPLOMATIC and not card.is_ability_exhausted(0):
					var extra := _cardinal_ministers_count(side)
					if extra > 0:
						bonus += mini(extra, 3)
						card.exhaust_ability(0); card.reveal()
			"M-20":  # Papacy-Hanover — +2 DP (Scotland/Ireland only), once/turn
				if action_type == Enums.ActionType.DIPLOMATIC and not card.is_ability_exhausted(0):
					bonus += 2
					card.exhaust_ability(0); card.reveal()
			"M-22":  # Edmund Burke — Major Diplomatic in Europe +1 DP per Ireland space controlled (max 2)
				if action_type == Enums.ActionType.DIPLOMATIC and not card.is_ability_exhausted(0):
					var ire := _count_controlled_containing(side, "ireland")
					if ire > 0:
						bonus += mini(ire, 2)
						card.exhaust_ability(0); card.reveal()
			"M-24":  # North American Trade — Economic +1 EP if more Fur+Fish markets than opp, once/turn
				if action_type == Enums.ActionType.ECONOMIC and not card.is_ability_exhausted(0):
					if _fur_fish_advantage(side):
						bonus += 1
						card.exhaust_ability(0); card.reveal()
	return bonus


# =====================================================================
# Passive per-space shift cost reduction (queried by ActionController.calculate_shift_cost)
# Idempotent (no consumption) — safe for cost preview + actual.
# =====================================================================
func passive_shift_discount(side: int, space_id: String, action_type: int) -> int:
	var p := GameManager.state.get_player(side)
	var disc := 0
	if action_type == Enums.ActionType.DIPLOMATIC:
		# M-6 Jonathan Swift — Ireland/Scotland flagging costs 1 less DP
		if _has(side, "M-6") and ("ireland" in space_id or "scotland" in space_id):
			disc += 1
		# M-16 Charles Hanbury Williams — FR-flagged Prussia/German/Russia cost 1 less to unflag
		if _has(side, "M-16") and ("prussia" in space_id or "german" in space_id or "russia" in space_id):
			disc += 1
		# M-22 Edmund Burke — Sons of Liberty / USA cost 1 less
		if _has(side, "M-22") and ("sons_of_liberty" in space_id or "usa" in space_id):
			disc += 1
	return disc


# =====================================================================
# First Debt of an AR bonus (M-23 Turgot)
# =====================================================================
func get_first_debt_bonus(side: int) -> int:
	if not _has(side, "M-23"):
		return 0
	var p := GameManager.state.get_player(side)
	var opp := GameManager.state.get_opponent(side)
	if p.available_debt() > opp.available_debt():
		_reveal(side, "M-23")
		return 1
	return 0


# =====================================================================
# Debt-taken hook (M-17 Merchant Banks)
# =====================================================================
func on_debt_taken(side: int, amount: int) -> int:
	var p := GameManager.state.get_player(side)
	for card in p.ministry_cards:
		if card.id == "M-17" and not card.is_ability_exhausted(0):
			p.add_treaty_points(1)
			card.exhaust_ability(0); card.reveal()
			return amount
	return amount


# =====================================================================
# Advantage exhausted hook (M-13 Pompadour, M-19 James Watt)
# =====================================================================
func on_advantage_exhausted(exhauster_side: int, region: int) -> void:
	# 활성 구현은 ministry_effects_v2.gd에서 '첫 기회'와 공개 선택을 함께 처리한다.
	# M-13 Pompadour (FR): first Europe-advantage exhaust each AR → +1 TRP to FR
	if region == Enums.Region.EUROPE and _has(Enums.Side.FRANCE, "M-13") and exhauster_side == Enums.Side.FRANCE:
		for c in GameManager.state.france.ministry_cards:
			if c.id == "M-13" and not c.is_ability_exhausted(0):
				GameManager.state.france.add_treaty_points(1)
				c.exhaust_ability(0); c.reveal()
				_log(Enums.Side.FRANCE, "퐁파두르: 조약점수 +1")
	# M-19 James Watt (BR): first time opponent (FR) exhausts an advantage each AR → +1 TRP to BR
	if _has(Enums.Side.BRITAIN, "M-19") and exhauster_side == Enums.Side.FRANCE:
		for c in GameManager.state.britain.ministry_cards:
			if c.id == "M-19" and not c.is_ability_exhausted(1):
				GameManager.state.britain.add_treaty_points(1)
				c.exhaust_ability(1); c.reveal()
				_log(Enums.Side.BRITAIN, "제임스 와트: 조약점수 +1")


# =====================================================================
# Region Award bonus (called by AwardManager.score_region after base VP)
# =====================================================================
func apply_award_bonus(region: int, winner: int) -> void:
	if winner == Enums.Side.NONE:
		return
	if region == Enums.Region.EUROPE:
		# M-3 Court of the Sun King — Europe Award +1 VP to FR (if FR won and controls it revealed)
		if winner == Enums.Side.FRANCE and _has(Enums.Side.FRANCE, "M-3"):
			GameManager.state.score_vp(Enums.Side.FRANCE, 1)
			_reveal(Enums.Side.FRANCE, "M-3")
			_log(Enums.Side.FRANCE, "태양왕의 궁정: 유럽 상 승점 +1")
		# M-18 Samuel Johnson — Europe Award +1 VP to BR, -1 VP to FR (min 0)
		if _has(Enums.Side.BRITAIN, "M-18"):
			if winner == Enums.Side.BRITAIN:
				GameManager.state.score_vp(Enums.Side.BRITAIN, 1)
			elif winner == Enums.Side.FRANCE:
				# reduce FR's award by 1 (give 1 VP toward Britain to offset)
				GameManager.state.score_vp(Enums.Side.BRITAIN, 1)
			_reveal(Enums.Side.BRITAIN, "M-18")
			_log(Enums.Side.BRITAIN, "새뮤얼 존슨: 유럽 상 조정")
	if region == Enums.Region.INDIA:
		# M-12 Dupleix — India Award +1 TRP to FR
		if winner == Enums.Side.FRANCE and _has(Enums.Side.FRANCE, "M-12"):
			GameManager.state.france.add_treaty_points(1)
			_reveal(Enums.Side.FRANCE, "M-12")
			_log(Enums.Side.FRANCE, "뒤플렉스: 인도 상 조약점수 +1")


# =====================================================================
# End of peace turn (§4.1.11)
# =====================================================================
func apply_end_of_peace_turn() -> void:
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var p := GameManager.state.get_player(side)
		for card in p.ministry_cards:
			if card.id == "M-2":  # John Law — -1 Debt (-2 if Scotland controlled)
				if not card.is_revealed: continue
				var amt := 1
				if _count_controlled_containing(side, "scotland") > 0:
					amt = 2
				p.reduce_debt(amt)
				card.reveal()
				_log(side, "존 로: 채무 -%d" % amt)


# =====================================================================
# Scoring phase (§4.1.12)
# =====================================================================
func apply_scoring_bonuses() -> void:
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var p := GameManager.state.get_player(side)
		for card in p.ministry_cards:
			if not card.is_revealed:
				continue
			match card.id:
				"M-7":  # East India Company — 1 VP per unexhausted qualifying Advantage (max 3)
					var qualifying := ["textiles_adv", "silk_adv", "fur_trade_adv", "rum_adv", "fruit_adv"]
					var count := 0
					if has_node("/root/AdvantageManager"):
						for adv_id in AdvantageManager.advantages:
							var adv = AdvantageManager.advantages[adv_id]
							if adv.controlled_by == side and not adv.is_exhausted and adv_id in qualifying:
								count += 1
					var vp := mini(count, 3)
					if vp > 0:
						GameManager.state.score_vp(side, vp)
						_log(side, "동인도 회사: 승점 +%d" % vp)
				"M-14":  # Voltaire — +1 TRP per multi-space country with a Prestige space (max 3)
					var counted := {}
					for sid in GameManager.state.spaces:
						var ss: SpaceState = GameManager.state.spaces[sid]
						if ss.data.is_prestige and ss.controlled_by == side:
							var parts: PackedStringArray = sid.split("_")
							var key: String = parts[0] if parts.size() > 0 else sid
							counted[key] = true
					var amt := mini(counted.size(), 3)
					if amt > 0:
						p.add_treaty_points(amt)
						_log(side, "볼테르: 조약점수 +%d" % amt)


# =====================================================================
# Helpers
# =====================================================================
func _cardinal_ministers_count(side: int) -> int:
	var count := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by != side or ss.has_conflict_marker: continue
		if "savoy" in sid or "sardinia" in sid:
			count += 1
		elif ss.data.is_prestige and ("spain" in sid or "austria" in sid):
			count += 1
	return count


func _count_controlled_containing(side: int, needle: String) -> int:
	var count := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by == side and needle in sid and not ss.has_conflict_marker:
			count += 1
	return count


func _fur_fish_advantage(side: int) -> bool:
	var opp := GameManager.state.get_opponent(side).side
	var mine := 0
	var theirs := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.data.space_type != Enums.SpaceType.MARKET or ss.has_conflict_marker: continue
		if ss.data.commodity == Enums.Commodity.FUR or ss.data.commodity == Enums.Commodity.FISH:
			if ss.controlled_by == side: mine += 1
			elif ss.controlled_by == opp: theirs += 1
	return mine > theirs


func _jacobite_score(side: int) -> void:
	# Score 1 VP (max 4) per FR-flagged Scotland/Ireland space
	var n := _count_controlled_containing(side, "scotland") + _count_controlled_containing(side, "ireland")
	var vp := mini(n + GameManager.state.jacobite_victories, 4)
	if vp > 0:
		GameManager.state.score_vp(side, vp)
		_log(side, "재커바이트 봉기: 승점 +%d" % vp)


func _place_huguenots(side: int) -> void:
	# Place on a FR-flagged territory in NA/Caribbean without a marker (adds +1 conquest cost)
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by != side: continue
		if ss.data.space_type != Enums.SpaceType.TERRITORY: continue
		if ss.data.region != Enums.Region.NORTH_AMERICA and ss.data.region != Enums.Region.CARIBBEAN: continue
		if ss.has_huguenots: continue
		ss.has_huguenots = true
		_log(side, "%s에 위그노 마커 배치" % ss.data.display_name)
		return


func _walpole_draw_discard(side: int) -> void:
	var p := GameManager.state.get_player(side)
	if GameManager.state.event_draw_pile.is_empty() and GameManager.state.event_discard_pile.size() > 0:
		GameManager.state.event_draw_pile.append_array(GameManager.state.event_discard_pile)
		GameManager.state.event_discard_pile.clear()
		GameManager.state.event_draw_pile.shuffle()
	if GameManager.state.event_draw_pile.is_empty():
		return
	p.hand.append(GameManager.state.event_draw_pile.pop_back())
	if p.hand.size() > 0:
		GameManager.state.event_discard_pile.append(p.hand.pop_front())
	_log(side, "월폴: 이벤트 1장 뽑고 1장 버림")


func _halley_discard_for_trp(side: int) -> void:
	var p := GameManager.state.get_player(side)
	if p.hand.is_empty():
		return
	GameManager.state.event_discard_pile.append(p.hand.pop_front())
	p.add_treaty_points(1)
	_log(side, "핼리: 이벤트 1장 버리고 조약점수 +1")


func reset_exhaustion_for_turn() -> void:
	watt_active_for_britain = false
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var p := GameManager.state.get_player(side)
		for card in p.ministry_cards:
			card.reset_exhaustion()
		p.condorcet_free_event = false


func _log(side: int, msg: String) -> void:
	if has_node("/root/GameLog"):
		GameLog.log_entry(side, "ministry", msg)
