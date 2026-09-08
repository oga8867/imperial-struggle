extends Node

# UI smoke test: instantiates the REAL game_session.tscn (exercising every
# localized UI panel + the prompt-bar button wiring) and drives a full
# AI-vs-AI game to completion. Fails on any script error or a stall.

var session: Node = null
var done := false


func _ready() -> void:
	LocaleManager.set_locale("en" if "--english" in OS.get_cmdline_user_args() else "ko")
	print("UI LOCALE "+LocaleManager.current_locale)
	print("=== UI SMOKE TEST ===")
	AIController.enabled = true
	AIController.ai_side = Enums.Side.BRITAIN
	GameManager.game_over.connect(_on_over)
	GameManager.player_action_required.connect(_on_action)
	WarManager.war_started.connect(_on_war_started)
	EventEffects.pending_choices_changed.connect(_on_choices)

	var scene = load("res://scenes/game_session.tscn")
	session = scene.instantiate()
	add_child(session)  # runs game_session._ready() -> wires buttons, shows UI
	print("  game_session instantiated OK")

	GameManager.start_new_game()
	if session.has_method("bind_to_state"):
		session.bind_to_state()

	# Safety timeout so a stall can't hang the run.
	await get_tree().create_timer(60.0).timeout
	if not done:
		print("!!! TIMEOUT: game did not reach GAME OVER")
		print("    turn=%d phase=%d" % [GameManager.state.current_turn, GameManager.state.current_turn_phase])
	_finish()


func _on_action(side: int, action: String) -> void:
	# Make the phasing side the AI so game_session._check_ai drives tile/actions.
	AIController.ai_side = side
	if action == "discard_events":
		GameManager.complete_discard(side, GameManager.state.get_player(side).hand.slice(0,3))
	elif action == "choose_first_player":
		GameManager.choose_first_player(side)
	if action == "select_ministry":
		# game_session shows the UI but does not auto-resolve; do it here.
		var picks: Array = AIController.decide_ministry_selection()
		var p := GameManager.state.get_player(side)
		p.ministry_cards.clear()
		for c in picks:
			if c is MinistryCard:
				p.ministry_cards.append(c)
				c.is_in_play = true
		GameManager.complete_ministry_selection(side)
	# tile / play_actions are driven by game_session._check_ai (real UI path).


func _on_war_started(war_id: String) -> void:
	# Simulate the human clicking Resolve then Continue in the War Display.
	print("  WAR started: %s (turn %d) — auto-resolving" % [war_id, GameManager.state.current_turn])
	call_deferred("_resolve_war")


func _resolve_war() -> void:
	GameManager.resolve_war_and_continue()


func _on_over(winner: int) -> void:
	if done:
		return
	done = true
	print("  GAME OVER — winner=%s VP=%d turn=%d" % [
		LocaleManager.side(winner), GameManager.state.vp, GameManager.state.current_turn])
	await get_tree().process_frame
	# Verify the localized prompt bar rendered a Korean win string.
	var pl = session.get_node_or_null("UILayer/PromptBar/PromptLabel")
	if pl:
		print("  prompt='%s'" % pl.text)
		if not LocaleManager.side(winner) in pl.text: done=false
	_finish()


func _finish() -> void:
	print("=== UI SMOKE %s ===" % ("PASS" if done else "FAIL(timeout)"))
	get_tree().quit(0 if done else 1)

func _on_choices(_choices: Array) -> void:
	# AI 대 AI 검수에서는 상대에게 선택권이 넘어가는 카드도 자동으로 응답한다.
	call_deferred("_answer_other_player")

func _answer_other_player() -> void:
	if EventEffects.pending_choices.is_empty(): return
	var choice = EventEffects.pending_choices[0]
	if choice.params.get("chooser",AIController.ai_side)==AIController.ai_side: return
	var options = EventEffects.choice_options()
	if not options.is_empty(): EventEffects.resolve_option(options[0].id)
