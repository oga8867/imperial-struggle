extends Node

# 난수를 고정한 여러 판으로 자동 선택의 정지와 저장 복원을 함께 검사한다.
# UI 완주 검사는 ui_smoke.tscn이 별도로 담당한다.
var seeds=[103,211,419,617,809,1013,1217,1423,1619,1823,2027,2237]
var run=0
var steps=0
var wars=0
var full_games=0
var failed=false

func _ready() -> void:
	GameManager.player_action_required.connect(func(side,action): _answer.call_deferred(side,action))
	WarManager.war_started.connect(func(_id): _war.call_deferred())
	GameManager.game_over.connect(_over)
	_start.call_deferred()

func _start() -> void:
	seed(seeds[run])
	AIController.enable_for(Enums.Side.FRANCE)
	steps=0
	wars=0
	GameManager.start_new_game()

func _answer(side: int,action: String) -> void:
	if failed or GameManager.state.current_phase==Enums.GamePhase.GAME_OVER: return
	steps+=1
	if steps>400:
		push_error("CAMPAIGN stalled seed="+str(seeds[run]))
		get_tree().quit(1)
		return
	AIController.ai_side=side
	match action:
		"select_ministry": GameManager._request_next_ministry_selection()
		"discard_events": GameManager.complete_discard(side,GameManager.state.get_player(side).hand.slice(0,3))
		"choose_first_player": GameManager.choose_first_player(side)
		"select_investment_tile":
			while EventEffects.has_pending():
				if not AIController._resolve_pending(): _fail("전쟁 타일 이월 선택"); return
			GameManager.select_investment_tile(side,AIController.decide_investment_tile())
		"play_actions":
			var round=GameManager.state.current_action_round
			var turn=GameManager.state.current_turn
			AIController.decide_action_round()
			if EventEffects.has_pending():
				while EventEffects.has_pending():
					AIController.ai_side=EventEffects.pending_choices[0].params.get("chooser",side)
					if not AIController._resolve_pending(): _fail("이벤트 선택"); return
				_answer.call_deferred(side,"play_actions")
			elif GameManager.state.phasing_player==side and GameManager.state.current_turn==turn and GameManager.state.current_action_round==round and ActionController.current_tile:
				_fail("행동 미완료")
	# 모델 그래프를 주기적으로 JSON 왕복한다. 실제 파일/메뉴 경로는 시각 검수에서 검사한다.
	if steps%13==0 and GameManager.state.current_phase!=Enums.GamePhase.GAME_OVER:
		if not SaveLoad._deserialize(JSON.parse_string(JSON.stringify(SaveLoad._serialize()))): _fail("저장 복원")

func _war() -> void:
	wars+=1
	GameManager.resolve_war_and_continue()

func _fail(message: String) -> void:
	failed=true
	push_error("CAMPAIGN seed %d / %s" % [seeds[run],message])
	get_tree().quit(1)

func _over(winner: int) -> void:
	if GameManager.state.current_turn==6: full_games+=1
	print("PASS CAMPAIGN seed=%d turn=%d wars=%d winner=%s vp=%d" % [seeds[run],GameManager.state.current_turn,wars,LocaleManager.side(winner),GameManager.state.vp])
	run+=1
	if run==seeds.size():
		print("CAMPAIGN REGRESSION: %d completed, %d reached turn 6" % [run,full_games])
		get_tree().quit()
	else: _start.call_deferred()
