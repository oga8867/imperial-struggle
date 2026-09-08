extends Node

# Targeted verification of ministry + advantage effects.

func _ready() -> void:
	print("=== EFFECT VERIFICATION ===")
	await get_tree().process_frame
	AIController.disable()
	GameManager.start_new_game()
	# Skip ministry select
	while GameManager.state.current_turn_phase == Enums.TurnPhase.MINISTRY_PHASE and not GameManager._ministry_pending_sides.is_empty():
		var side = GameManager._ministry_pending_sides[0]
		var p = GameManager.state.get_player(side)
		p.ministry_cards.clear()
		GameManager.complete_ministry_selection(side)
	await get_tree().process_frame
	var s = GameManager.state
	var fr = s.france
	var br = s.britain
	var ok := 0
	var fail := 0

	# --- M-8 Bank of England: activate → debt_limit +1 ---
	var m8 = _find_ministry("M-8")
	br.ministry_cards.assign([m8]); m8.reset_exhaustion()
	var before = br.debt_limit
	MinistryEffects.activate_manual(m8, Enums.Side.BRITAIN)
	_check("M-8 Bank of England +1 Debt Limit", br.debt_limit == before + 1, ok, fail)
	if br.debt_limit == before + 1: ok += 1
	else: fail += 1

	# --- M-2 John Law: end of turn → -1 debt ---
	var m2 = _find_ministry("M-2")
	fr.ministry_cards.assign([m2]); fr.current_debt = 3
	MinistryEffects.apply_end_of_peace_turn()
	if fr.current_debt == 2: ok += 1; print("  + M-2 John Law -1 Debt")
	else: fail += 1; print("  ! M-2 John Law FAILED debt=%d" % fr.current_debt)

	# --- M-15 Pitt: +1 DP ---
	var m15 = _find_ministry("M-15")
	br.ministry_cards.assign([m15]); m15.reset_exhaustion()
	var dp = MinistryEffects.get_extra_major_ap(Enums.Side.BRITAIN, Enums.ActionType.DIPLOMATIC)
	if dp == 1: ok += 1; print("  + M-15 Pitt +1 DP")
	else: fail += 1; print("  ! M-15 Pitt FAILED dp=%d" % dp)

	# --- M-6 passive discount on Ireland space ---
	var m6 = _find_ministry("M-6")
	br.ministry_cards.assign([m6])
	var disc = MinistryEffects.passive_shift_discount(Enums.Side.BRITAIN, "ireland_alliance", Enums.ActionType.DIPLOMATIC)
	if disc >= 1: ok += 1; print("  + M-6 Swift discount on Ireland = %d" % disc)
	else: fail += 1; print("  ! M-6 Swift FAILED disc=%d" % disc)

	# --- Advantage: Wheat market discount ---
	br.ministry_cards.clear()
	var wheat = AdvantageManager.advantages.get("wheat_adv")
	if wheat:
		wheat.controlled_by = Enums.Side.BRITAIN
		wheat.is_exhausted = false
		wheat.gained_this_round = false
		s.phasing_player = Enums.Side.BRITAIN
		# simulate an action state so can_activate passes
		AdvantageManager._advantages_used_this_round = 0
		AdvantageManager._regions_used_this_round.clear()
		# Force apply effect directly (bypass can_activate action-state gating)
		AdvantageManager.pending_market_discount = 0
		AdvantageManager._apply_effect(wheat)
		var peek = AdvantageManager.peek_market_discount(Enums.Side.BRITAIN)
		if peek == 1: ok += 1; print("  + Wheat advantage: market discount = 1")
		else: fail += 1; print("  ! Wheat FAILED peek=%d" % peek)

	# --- Advantage: Algonquin Raids places a conflict marker ---
	var alg = AdvantageManager.advantages.get("algonquin_raids_adv")
	if alg:
		alg.controlled_by = Enums.Side.FRANCE
		var before_markers = _count_conflict_markers()
		AdvantageManager._apply_effect(alg)
		var after_markers = _count_conflict_markers()
		if after_markers > before_markers: ok += 1; print("  + Algonquin Raids placed a conflict marker (%d→%d)" % [before_markers, after_markers])
		else: fail += 1; print("  ! Algonquin Raids FAILED markers %d→%d" % [before_markers, after_markers])

	# --- Award bonus: M-3 Sun King → Europe FR +1 VP ---
	var m3 = _find_ministry("M-3")
	fr.ministry_cards.assign([m3]); m3.reveal()
	var vp_before = s.vp
	MinistryEffects.apply_award_bonus(Enums.Region.EUROPE, Enums.Side.FRANCE)
	# FR VP increases vp (France scores positive)
	if s.vp == vp_before + 1: ok += 1; print("  + M-3 Sun King: Europe FR award +1 VP")
	else: fail += 1; print("  ! M-3 FAILED vp %d→%d" % [vp_before, s.vp])

	# ================= EVENT EFFECT CHECKS =================
	# #2 Acts of Union BR bonus → score 2 VP (BR scoring lowers s.vp) + 1 DP event AP
	_reset_event_ap()
	var v0 = s.vp
	EventEffects.apply_event(_find_event(2), Enums.Side.BRITAIN, true)
	if s.vp == v0 - 2 and ActionController.event_ap_remaining >= 1:
		ok += 1; print("  + Event #2 BR: +2 VP & +1 DP")
	else: fail += 1; print("  ! Event #2 FAILED vp %d→%d ap=%d" % [v0, s.vp, ActionController.event_ap_remaining])

	# #8 Tax Reform with Debt=1, bonus → reduce 1, 2 EP compensation
	_reset_event_ap()
	fr.current_debt = 1
	EventEffects.apply_event(_find_event(8), Enums.Side.FRANCE, true)
	if fr.current_debt == 0 and ActionController.event_ap_remaining == 2:
		ok += 1; print("  + Event #8 FR: reduced 1 + 2 EP compensation")
	else: fail += 1; print("  ! Event #8 FAILED debt=%d ap=%d" % [fr.current_debt, ActionController.event_ap_remaining])

	# #25 Quad Alliance BR base → move own squadron off map + 2 VP
	_reset_event_ap()
	br.squadrons_on_map = 2
	v0 = s.vp
	EventEffects.apply_event(_find_event(25), Enums.Side.BRITAIN, false)
	if br.squadrons_on_map == 1 and s.vp == v0 - 2:
		ok += 1; print("  + Event #25 BR: squadron moved + 2 VP")
	else: fail += 1; print("  ! Event #25 FAILED sq=%d vp %d→%d" % [br.squadrons_on_map, v0, s.vp])

	# #9 Great Northern War FR base → Russia already FR-flagged → +2 VP
	_reset_event_ap()
	if "russia_alliance" in s.spaces:
		s.spaces["russia_alliance"].controlled_by = Enums.Side.FRANCE
		v0 = s.vp
		EventEffects.apply_event(_find_event(9), Enums.Side.FRANCE, false)
		if s.vp == v0 + 2: ok += 1; print("  + Event #9 FR: Russia FR-flagged → +2 VP")
		else: fail += 1; print("  ! Event #9 FAILED vp %d→%d" % [v0, s.vp])

	# #39 Stamp Act FR bonus → exactly 3 markers pending (not 4)
	_reset_event_ap()
	EventEffects.apply_event(_find_event(39), Enums.Side.FRANCE, true)
	var cnt39 = 0
	if EventEffects.pending_choices.size() > 0:
		cnt39 = EventEffects.pending_choices[0]["params"].get("count", 0)
	if cnt39 == 3: ok += 1; print("  + Event #39 FR bonus: 3 markers (not 4)")
	else: fail += 1; print("  ! Event #39 FAILED count=%d" % cnt39)
	EventEffects.pending_choices.clear()

	print("\n=== RESULT: %d passed, %d failed ===" % [ok, fail])
	get_tree().quit(1 if fail else 0)


func _find_ministry(id: String):
	for m in GameData.ministries:
		if m.id == id: return m
	return null


func _find_event(id: int):
	for e in GameData.events:
		if e.id == id: return e
	return null


func _reset_event_ap() -> void:
	ActionController.event_ap_remaining = 0
	ActionController.event_ap_type = Enums.ActionType.NONE
	EventEffects.pending_choices.clear()


func _count_conflict_markers() -> int:
	var n := 0
	for sid in GameManager.state.spaces:
		if GameManager.state.spaces[sid].has_conflict_marker: n += 1
	return n


func _check(_name, _cond, _ok, _fail): pass
