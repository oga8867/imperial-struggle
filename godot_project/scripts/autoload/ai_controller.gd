extends "res://scripts/ai/baseline_ai.gd"

# 기본 AI는 비교 기준으로 그대로 보존한다. 전략 모드만 독립 프로세스에 계산을 맡긴다.
signal thinking_changed
const Observation = preload("res://scripts/ai/observation.gd")
const Commands = preload("res://scripts/ai/commands.gd")
const Eval = preload("res://scripts/ai/evaluation.gd")
var strategy_mode = false
var budget_seconds = 20
var round_key = ""
var search_spent_ms = 0
var thinking = false
var last_report: Dictionary = {}
var _pid = -1
var _job_path = ""
var _job_id = ""
var _job_deadline = 0
var _charged_at = 0
var _context: GameState
var _active = false
var _paused = false
var _plan: Array = []
var _next_step = 0
var _last_poll = 0
var _fallback_seen: Dictionary = {}
var _sequence = 0

func enable_for(side: Enums.Side, strategic: bool = false) -> void:
	cancel()
	super.enable_for(side)
	strategy_mode = strategic
	round_key = ""
	search_spent_ms = 0
	_paused = false

func disable() -> void:
	cancel()
	super.disable()

func suspend() -> void:
	cancel()
	_paused = true

func resume() -> void:
	_paused = false
	request_turn()

func cancel() -> void:
	checkpoint_time()
	if _pid>0 and OS.is_process_running(_pid): OS.kill(_pid)
	_pid = -1
	if _job_path!="" and FileAccess.file_exists(_job_path): DirAccess.remove_absolute(_job_path)
	thinking = false
	_active = false
	_plan.clear()
	_context = null
	thinking_changed.emit()

func checkpoint_time() -> void:
	if not thinking: return
	var now = Time.get_ticks_msec()
	search_spent_ms += maxi(0,now-_charged_at)
	_charged_at = now

func request_turn() -> void:
	if not enabled or not strategy_mode or _paused or "--ai-worker" in OS.get_cmdline_user_args(): return
	if GameManager.state==null or Commands.chooser()!=ai_side: return
	if GameManager.state.current_turn_phase!=Enums.TurnPhase.ACTION_PHASE and not WarFlow.active: return
	if GameManager.state.winner!=Enums.Side.NONE: return
	_context = GameManager.state
	_active = true
	var key = "%d:%d:%s" % [_context.current_turn,_context.current_action_round,WarManager.current_war_id if WarFlow.active else "peace"]
	if key!=round_key:
		round_key=key
		search_spent_ms=0
		_fallback_seen.clear()
	_next_step = Time.get_ticks_msec()+100

func _process(_delta: float) -> void:
	if not _active or not enabled or not strategy_mode or _paused: return
	if GameManager.state!=_context or GameManager.state.winner!=Enums.Side.NONE:
		cancel()
		return
	if thinking:
		checkpoint_time()
		var now = Time.get_ticks_msec()
		if now-_last_poll<100: return
		_last_poll=now
		_read_result()
		thinking_changed.emit()
		if now>=_job_deadline or not OS.is_process_running(_pid) or last_report.get("done",false): _finish_job()
		return
	if Commands.chooser()!=ai_side:
		_active=false
		return
	if Time.get_ticks_msec()<_next_step: return
	if not _plan.is_empty():
		var command = _plan.pop_front()
		if not Commands.apply(command,ai_side): _plan.clear()
		elif Commands.boundary(command): _plan.clear()
		_next_step=Time.get_ticks_msec()+160
		return
	if search_spent_ms < budget_seconds*1000-600:
		_start_job()
	else:
		_fast_step()

func _start_job() -> void:
	var remaining = budget_seconds*1000-search_spent_ms
	var allocation = mini(remaining,9000 if ActionController.current_tile==null and not WarFlow.active else 3000)
	if remaining<4500: allocation=remaining-150
	if allocation<300: _fast_step(); return
	thinking=true
	_charged_at=Time.get_ticks_msec()
	_sequence+=1
	_job_id="%d-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec(),_sequence]
	var dir="user://ai_jobs"
	DirAccess.make_dir_recursive_absolute(dir)
	_job_path=ProjectSettings.globalize_path(dir.path_join(_job_id+".json"))
	# 시계에서 독립 seed를 만든다. 실제 게임의 난수열은 소비하지 않는다.
	var sample_seed=Time.get_ticks_usec() ^ (_sequence*3571)
	var snapshots=[]
	for i in 3: snapshots.append(Observation.build(ai_side,sample_seed+i*7919))
	var job={"id":_job_id,"side":ai_side,"seed":sample_seed,"budget_ms":maxi(100,allocation-500),"snapshots":snapshots}
	var file=FileAccess.open(_job_path,FileAccess.WRITE)
	if file==null:
		thinking=false
		_fast_step()
		return
	file.store_string(JSON.stringify(job))
	file.close()
	last_report={}
	_job_deadline=_charged_at+allocation
	var args=PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",_job_path+".log","res://scenes/ai_worker.tscn","--","--ai-worker",_job_path])
	_pid=OS.create_process(OS.get_executable_path(),args,false)
	if _pid<0: _finish_job()
	thinking_changed.emit()

func _read_result() -> void:
	if not FileAccess.file_exists(_job_path+".result"): return
	var report=JSON.parse_string(FileAccess.get_file_as_string(_job_path+".result"))
	if report is Dictionary and report.get("job_id","")==_job_id: last_report=report

func _finish_job() -> void:
	checkpoint_time()
	if _pid>0 and OS.is_process_running(_pid): OS.kill(_pid)
	_pid=-1
	_read_result()
	thinking=false
	_plan=last_report.get("plan",[]).duplicate(true)
	thinking_changed.emit()
	if _plan.is_empty(): _fast_step()
	_next_step=Time.get_ticks_msec()+100
	# 이 프로세스가 만든 입력만 삭제한다. 결과와 로그는 진단 자료다.
	if FileAccess.file_exists(_job_path): DirAccess.remove_absolute(_job_path)

func decide_now() -> void:
	# 기다리기를 그만두어도 가장 최근의 완료된 계획 또는 합법적인 빠른 선택을 쓴다.
	search_spent_ms=budget_seconds*1000
	if thinking: _finish_job()
	else: _fast_step()

func _fast_step() -> void:
	var options=Commands.options(ai_side)
	if options.is_empty(): _active=false; return
	options.sort_custom(func(a,b):return a.rank>b.rank)
	var context_key=str([round_key,ActionController.major_ap_remaining,ActionController.minor_ap_remaining,ActionController.event_grants,GameManager.state.vp,GameManager.state.get_player(ai_side).current_debt,GameManager.state.get_player(ai_side).treaty_points])
	var picked={}
	for command in options:
		var key=context_key+str(command)
		if _fallback_seen.has(key): continue
		picked=command
		_fallback_seen[key]=true
		break
	if picked.is_empty():
		picked=options.filter(func(c):return c.kind=="end")[0] if options.any(func(c):return c.kind=="end") else options[0]
	Commands.apply(picked,ai_side)
	_next_step=Time.get_ticks_msec()+100

func status_text() -> String:
	return LocaleManager.tx("AI 계산 중 · %d초 · %d개 계획 비교") % [search_spent_ms/1000,int(last_report.get("iterations",0))]

func decide_discard() -> Array:
	var hand=GameManager.state.get_player(ai_side).hand.duplicate()
	if strategy_mode: hand.sort_custom(func(a,b):return Eval.card_value(a,ai_side)>Eval.card_value(b,ai_side))
	return hand.slice(0,3) if strategy_mode else hand.slice(maxi(0,hand.size()-3))

func decide_ministry_selection() -> Array:
	if not strategy_mode: return super.decide_ministry_selection()
	var cards=GameData.get_ministries_for_era(ai_side,GameManager.state.current_era)
	if cards.size()<2: return cards.duplicate()
	var best=[]
	var best_score=-INF
	for i in cards.size():
		for j in range(i+1,cards.size()):
			var pair=[cards[i],cards[j]]
			var score=float(super._ministry_score(cards[i])+super._ministry_score(cards[j]))
			for card in pair: score+=Eval.passive_ministry_value(card,ai_side)*0.4
			# 같은 키워드를 중복 보유하는 것보다 현재 손패의 서로 다른 보너스를 여는 쌍.
			for event in GameManager.state.get_player(ai_side).hand:
				if pair.any(func(c):return c.has_keyword(event.bonus_condition)): score+=4.0
			if score>best_score: best_score=score; best=pair
	return best

func _exit_tree() -> void:
	cancel()
