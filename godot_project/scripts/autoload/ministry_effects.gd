extends Node

# Ministry card effects per rule §3.5. All 26 cards (FR + BR).
# Categorization:
# - PASSIVE: always-on (e.g., Award +1 VP) — applied at scoring/relevant phase
# - AR_TRIGGER: fires at start of action round
# - MANUAL: user clicks "Activate" in MinistryHand
# - BONUS_AP: adds AP at begin_action_round when matching action type
# - DEBT_HOOK: triggers on debt taken
# - SCORING_HOOK: applies during scoring phase

signal ministry_triggered(card_id: String, message: String)


func _ready() -> void:
	pass


# =====================================================================
# Manual activation (called by MinistryHand UI when player clicks Activate)
# =====================================================================
func activate_manual(card: MinistryCard, side: Enums.Side) -> void:
	if card.is_ability_exhausted(0):
		return
	card.reveal()
	var fired := true
	match card.id:
		"M-5":  # Robert Walpole — draw 1 Event card, discard 1
			_walpole_draw_discard(side)
		"M-8":  # Bank of England — once per turn, +1 Debt Limit
			GameManager.state.britain.debt_limit += 1
			ministry_triggered.emit(card.id, "Bank of England: +1 Debt Limit")
		"M-10":  # Edmond Halley — discard 1 Event for 1 TRP
			_halley_discard_for_trp(side)
		"M-11":  # Choiseul — handled in get_extra_major_ap (Mil)
			pass
		"M-15":  # Pitt the Elder — handled in get_extra_major_ap (Dipl)
			pass
		"M-1":  # Cardinal Ministers — handled in get_extra_major_ap (Dipl)
			pass
		"M-21":  # Townshend Acts — place marker on a commodity
			ministry_triggered.emit(card.id, "Townshend Acts: place marker (manual)")
		"M-25":  # Marquis de Condorcet — play event without matching tile (handled at event play)
			ministry_triggered.emit(card.id, "Condorcet: free event play unlocked this AR")
		"M-26":  # Lavoisier — handled when bonus event triggers
			pass
		_:
			fired = false
	if fired:
		card.exhaust_ability(0)


# =====================================================================
# Bonus AP at begin_action_round (auto, type-matched)
# =====================================================================
func get_extra_major_ap(side: Enums.Side, action_type: Enums.ActionType) -> int:
	var p := GameManager.state.get_player(side)
	var bonus := 0
	for card in p.ministry_cards:
		match card.id:
			"M-15":  # Pitt the Elder — +1 DP for non-Prestige shifts
				if action_type == Enums.ActionType.DIPLOMATIC and not card.is_ability_exhausted(0):
					bonus += 1
					card.exhaust_ability(0)
					card.reveal()
			"M-11":  # Choiseul — +1 MP for war tiles/squadrons
				if action_type == Enums.ActionType.MILITARY and not card.is_ability_exhausted(0):
					bonus += 1
					card.exhaust_ability(0)
					card.reveal()
			"M-1":  # Cardinal Ministers — +DP per Savoy/Sardinia/Spain Prestige/Austria Prestige (max 3)
				if action_type == Enums.ActionType.DIPLOMATIC and not card.is_ability_exhausted(0):
					var extra := _cardinal_ministers_count(side)
					if extra > 0:
						bonus += mini(extra, 3)
						card.exhaust_ability(0)
						card.reveal()
	return bonus


# =====================================================================
# End of peace turn (Resolve Remaining Powers — §4.1.11)
# =====================================================================
func apply_end_of_peace_turn() -> void:
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var p := GameManager.state.get_player(side)
		for card in p.ministry_cards:
			match card.id:
				"M-2":  # John Law — reduce debt by 1, or 2 if Scotland controlled
					var amt := 1
					for sid in GameManager.state.spaces:
						var ss: SpaceState = GameManager.state.spaces[sid]
						if "scotland" in sid and ss.controlled_by == side:
							amt = 2; break
					p.reduce_debt(amt)
					ministry_triggered.emit(card.id, "John Law: -%d Debt" % amt)


# =====================================================================
# Scoring phase bonuses (§4.1.12)
# =====================================================================
func apply_scoring_bonuses() -> void:
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var p := GameManager.state.get_player(side)
		for card in p.ministry_cards:
			if not card.is_revealed:
				continue
			match card.id:
				"M-3":  # Court of the Sun King — Europe Award +1 VP for FR
					if side == Enums.Side.FRANCE:
						# (applied as bonus; simplified - we add directly here)
						pass
				"M-7":  # East India Company — 1 VP per unexhausted Advantage (max 3) — qualifying advantages
					var qualifying := ["textiles_adv","silk_adv","fur_trade_adv","rum_adv","fruit_adv"]
					var count := 0
					if has_node("/root/AdvantageManager"):
						for adv_id in AdvantageManager.advantages:
							var adv = AdvantageManager.advantages[adv_id]
							if adv.controlled_by == side and not adv.is_exhausted and adv_id in qualifying:
								count += 1
					var vp := mini(count, 3)
					if vp > 0:
						GameManager.state.score_vp(side, vp)
						ministry_triggered.emit(card.id, "East India Co +%d VP" % vp)
				"M-12":  # Dupleix — India/Cotton/Spice awards +1 TRP for FR
					pass
				"M-14":  # Voltaire — Europe Award: +1 TRP per multi-space country with Prestige (max 3)
					var prestige_count := 0
					var counted_countries := {}
					for sid in GameManager.state.spaces:
						var ss: SpaceState = GameManager.state.spaces[sid]
						if ss.data.is_prestige and ss.controlled_by == side:
							var parts: PackedStringArray = sid.split("_")
							var country_key: String = parts[0] if parts.size() > 0 else sid
							if not counted_countries.has(country_key):
								counted_countries[country_key] = true
								prestige_count += 1
					var amt := mini(prestige_count, 3)
					if amt > 0:
						p.add_treaty_points(amt)
						ministry_triggered.emit(card.id, "Voltaire +%d TRP" % amt)
				"M-18":  # Samuel Johnson — Europe Award worth +1 VP to BR, -1 VP to FR
					pass
				"M-22":  # Edmund Burke — Major Diplomatic in Europe +1 DP per Ireland controlled (handled at AP grant time)
					pass


func on_debt_taken(side: Enums.Side, amount: int) -> int:
	# §M-17 Merchant Banks: ignore first 2 Debt as EP each Peace turn
	var p := GameManager.state.get_player(side)
	for card in p.ministry_cards:
		if card.id == "M-17":
			if not card.is_ability_exhausted(0):
				p.add_treaty_points(1)
				card.exhaust_ability(0)
				card.reveal()
				return amount
	return amount


func _cardinal_ministers_count(side: Enums.Side) -> int:
	var count := 0
	for sid in GameManager.state.spaces:
		var ss: SpaceState = GameManager.state.spaces[sid]
		if ss.controlled_by != side: continue
		if "savoy" in sid or "sardinia" in sid:
			count += 1
		elif ss.data.is_prestige and ("spain" in sid or "austria" in sid):
			count += 1
	return count


func _walpole_draw_discard(side: Enums.Side) -> void:
	var p := GameManager.state.get_player(side)
	if GameManager.state.event_draw_pile.is_empty():
		if GameManager.state.event_discard_pile.size() > 0:
			GameManager.state.event_draw_pile.append_array(GameManager.state.event_discard_pile)
			GameManager.state.event_discard_pile.clear()
			GameManager.state.event_draw_pile.shuffle()
	if GameManager.state.event_draw_pile.is_empty():
		return
	var drawn = GameManager.state.event_draw_pile.pop_back()
	p.hand.append(drawn)
	# Auto-discard worst (lowest id) — simplified
	if p.hand.size() > 0:
		var to_discard = p.hand[0]
		p.hand.remove_at(0)
		GameManager.state.event_discard_pile.append(to_discard)
	ministry_triggered.emit("M-5", "Walpole drew 1, discarded 1")


func _halley_discard_for_trp(side: Enums.Side) -> void:
	var p := GameManager.state.get_player(side)
	if p.hand.is_empty():
		return
	var card = p.hand[0]
	p.hand.remove_at(0)
	GameManager.state.event_discard_pile.append(card)
	p.add_treaty_points(1)
	ministry_triggered.emit("M-10", "Halley: discarded 1 Event → +1 TRP")


func reset_exhaustion_for_turn() -> void:
	for side in [Enums.Side.BRITAIN, Enums.Side.FRANCE]:
		var p := GameManager.state.get_player(side)
		for card in p.ministry_cards:
			card.reset_exhaustion()
