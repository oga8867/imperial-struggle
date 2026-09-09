extends Node

# 별도 검사 프로세스의 가상 대국이다. 같은 seed에서 전략 진영을 바꾸어 비교한다.
# 개발용 짧은 예산과 실제 게임의 20초 예산은 보고서에서 구분한다.
const Observation=preload("res://scripts/ai/observation.gd")
const Search=preload("res://scripts/ai/search.gd")
const Commands=preload("res://scripts/ai/commands.gd")
var results=[]
var game_seed=0
var strategic_side=Enums.Side.FRANCE
var round_budget=1500
var decision=0
var searches=0
var simulated=0
var errors=0

func _ready() -> void:
	await get_tree().process_frame
	var args=OS.get_cmdline_user_args()
	var arg_index=args.find("--budget-ms")
	if arg_index>=0: round_budget=int(args[arg_index+1])
	var seeds=[71237,89119]
	arg_index=args.find("--seed")
	if arg_index>=0: seeds=[int(args[arg_index+1])]
	for value in seeds:
		for side in [Enums.Side.BRITAIN,Enums.Side.FRANCE]:
			game_seed=value
			strategic_side=side
			decision=0
			searches=0
			simulated=0
			seed(value)
			AIController.disable()
			GameManager.start_new_game()
			var started=Time.get_ticks_msec()
			for step in 800:
				if GameManager.state.winner!=Enums.Side.NONE: break
				await get_tree().process_frame
				if not _step():
					errors+=1
					push_error("AI BENCHMARK STALL seed=%d side=%d state=%s pending=%s ministry=%s" % [value,side,ActionController.state,EventEffects.pending_choices,MinistryDecisions.pending])
					break
			var st=GameManager.state
			var row={"seed":value,"strategic_side":side,"winner":st.winner,"strategic_win":st.winner==side,"turn":st.current_turn,"vp":st.vp,"round_budget_ms":round_budget,"searches":searches,"simulated_actions":simulated,"elapsed_ms":Time.get_ticks_msec()-started}
			results.append(row)
			print("AI MATCH ",JSON.stringify(row))
			_write()
			if st.winner==Enums.Side.NONE: errors+=1
	print("AI BENCHMARK COMPLETE games=",results.size()," wins=",results.filter(func(r):return r.strategic_win).size()," errors=",errors)
	get_tree().quit(0 if errors==0 else 1)

func _step() -> bool:
	var st=GameManager.state
	if st.current_phase==Enums.GamePhase.WAR:
		AIController.enabled=false
		WarFlow.start(false)
		for i in 150:
			if not WarFlow.active: break
			if WarFlow.choice.is_empty(): return false
			var side=WarFlow.choice.side
			var options=Commands.options(side)
			if options.is_empty(): return false
			if side==strategic_side: options.sort_custom(func(a,b):return a.rank>b.rank)
			if not Commands.apply(options[0],side): return false
		if WarFlow.active: return false
		GameManager.resolve_war_and_continue()
		return true
	if not GameManager._discard_pending_sides.is_empty():
		var side=GameManager._discard_pending_sides[0]
		AIController.ai_side=side
		AIController.strategy_mode=side==strategic_side
		AIController.enabled=false
		return GameManager.complete_discard(side,AIController.decide_discard())
	if not GameManager._ministry_pending_sides.is_empty():
		AIController.ai_side=GameManager._ministry_pending_sides[0]
		AIController.enabled=true
		AIController.strategy_mode=AIController.ai_side==strategic_side
		GameManager._request_next_ministry_selection()
		return true
	if GameManager._initiative_first_player_pending:
		GameManager.choose_first_player(st.initiative)
		return true
	if st.current_turn_phase!=Enums.TurnPhase.ACTION_PHASE: return false
	var side=st.phasing_player
	AIController.enabled=true
	AIController.ai_side=side
	AIController.strategy_mode=side==strategic_side
	var turn=st.current_turn
	var round_number=st.current_action_round
	if side!=strategic_side:
		for attempt in 10:
			if EventEffects.has_pending():
				var chooser=Commands.chooser()
				AIController.ai_side=chooser
				if not AIController._resolve_pending(): return false
				AIController.ai_side=side
			if ActionController.current_tile==null: GameManager.select_investment_tile(side,AIController.decide_investment_tile())
			AIController.decide_action_round()
			if st.phasing_player!=side or st.current_turn!=turn or st.current_action_round!=round_number: return true
		return false
	var remaining=round_budget
	var seen={}
	var plan=[]
	for attempt in 140:
		st=GameManager.state
		if st.phasing_player!=side or st.current_turn!=turn or st.current_action_round!=round_number or st.winner!=Enums.Side.NONE: return true
		var chooser=Commands.chooser()
		var options=Commands.options(chooser)
		if options.is_empty(): return false
		if plan.is_empty() and chooser==side and remaining>120:
			var actual=SaveLoad._serialize()
			var before=Time.get_ticks_msec()
			var observation=Observation.build(side,game_seed+decision*7919)
			var allocation=mini(remaining,round_budget/2 if ActionController.current_tile==null else round_budget/3)
			var report=Search.new().run({"side":side,"snapshots":[observation],"seed":game_seed+decision*3571,"budget_ms":maxi(100,allocation)})
			searches+=1
			simulated+=report.nodes
			SaveLoad._deserialize(actual)
			remaining-=Time.get_ticks_msec()-before
			plan=report.plan.duplicate(true)
		var command={}
		if not plan.is_empty(): command=plan.pop_front()
		else:
			options.sort_custom(func(a,b):return a.rank>b.rank)
			var key=str([ActionController.major_ap_remaining,ActionController.minor_ap_remaining,ActionController.event_grants,ActionController.finished_pools,EventEffects.pending_choices,MinistryDecisions.pending])
			for option in options:
				var signature=key+str(option)
				if seen.has(signature): continue
				seen[signature]=true
				command=option
				break
			if command.is_empty(): command=options[0]
		decision+=1
		# 모의 진행에 사용한 전역 RNG를 실제 대국 난수와 분리하는 검사 전용 재시드다.
		seed(game_seed+turn*100003+round_number*1009+side*137+decision*3)
		if not Commands.apply(command,chooser): plan.clear()
		if Commands.boundary(command): plan.clear()
	return false

func _write() -> void:
	var path=ProjectSettings.globalize_path("res://../output/validation/ai-benchmark-%d-%d.json" % [game_seed,round_budget])
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"results":results,"errors":errors},"  "))
