extends RefCounted

# 시간 제한 몬테카를로 롤아웃: 후보별로 라운드 끝까지 진행해 평균을 비교한다.
# UCB는 유망한 후보와 덜 시험한 후보에 계산 시간을 배분한다. 승률 보장은 아니다.
const Commands = preload("res://scripts/ai/commands.gd")
const Eval = preload("res://scripts/ai/evaluation.gd")
var rng = RandomNumberGenerator.new()
var deadline = 0
var nodes = 0

func run(job: Dictionary, publish: Callable = Callable()) -> Dictionary:
	rng.seed = int(job.get("seed",9173))
	var started = Time.get_ticks_msec()
	deadline = started + int(job.get("budget_ms",18000))
	var snapshots = job.snapshots
	if snapshots.is_empty() or not SaveLoad._deserialize(snapshots[0]): return {"error":"invalid snapshot"}
	var side = int(job.side)
	var candidates = Commands.options(side)
	candidates.sort_custom(func(a,b): return a.rank>b.rank)
	# 공간이 많은 판의 폭발을 막되 모든 투자 타일과 의무 선택지는 유지한다.
	if ActionController.current_tile and not EventEffects.has_pending() and not MinistryDecisions.has_pending(): candidates = candidates.slice(0,18)
	if candidates.is_empty(): return {"plan":[],"iterations":0,"elapsed_ms":0}
	var stats = []
	for command in candidates: stats.append({"command":command,"visits":0,"total":0.0,"best":-INF,"plan":[]})
	var iterations = 0
	var iteration_limit = int(job.get("iterations",0))
	while Time.get_ticks_msec()<deadline and (iteration_limit<=0 or iterations<iteration_limit):
		var index = iterations if iterations<stats.size() else _select(stats,iterations)
		var root = stats[index]
		if not SaveLoad._deserialize(snapshots[iterations%snapshots.size()]): break
		AIController.enabled = false
		seed(int(job.get("seed",9173))+iterations*3571)
		var trial = _rollout(root.command,side,iterations>=stats.size())
		if trial.get("complete",false):
			root.visits += 1
			root.total += trial.value
			if trial.value>root.best:
				root.best = trial.value
				root.plan = trial.plan
		iterations += 1
		if publish.is_valid() and (iterations%4==0 or iterations==1): publish.call(_result(stats,iterations,started))
	return _result(stats,iterations,started)

func _select(stats: Array,total: int) -> int:
	var best = -INF
	var selected = 0
	for i in stats.size():
		if stats[i].visits==0: return i
		var score = stats[i].total/stats[i].visits + 18.0*sqrt(log(total+1.0)/stats[i].visits)
		if score>best: best=score; selected=i
	return selected

func _rollout(first: Dictionary,side: int,varied: bool) -> Dictionary:
	var plan = []
	var can_record = true
	var command = first
	var visited = {}
	var completed = false
	for step in 70:
		if Time.get_ticks_msec()>=deadline: break
		var chooser = Commands.chooser()
		if chooser!=side: can_record=false
		if can_record: plan.append(command.duplicate(true))
		if command.kind=="end": completed=true; break
		if not Commands.apply(command,chooser,false): break
		nodes += 1
		if command.kind=="pass": completed=true; break
		if Commands.boundary(command): can_record=false
		if GameManager.state.winner!=Enums.Side.NONE: completed=true; break
		if WarFlow.active:
			# 전쟁은 현재 공개된 선택 하나를 비교한 뒤 다음 공개에서 다시 계산한다.
			completed=true
			break
		var key = _position_key()
		visited[key] = visited.get(key,0)+1
		var legal = Commands.options(Commands.chooser())
		if legal.is_empty(): completed=true; break
		legal.sort_custom(func(a,b): return a.rank>b.rank)
		if visited[key]>1:
			# AP를 쓰지 않고 풀을 오가는 순환을 제거한다.
			legal = legal.filter(func(c): return c.kind not in ["pool","assign","reveal"])
		if legal.is_empty(): break
		var pick = 0
		if varied and rng.randf()<0.22: pick=rng.randi_range(0,mini(4,legal.size()-1))
		command=legal[pick]
	var after = Eval.value(side)
	# 검색 깊이 끝에서 남은 행동이 있는 미완성 판은 최선 계획으로 채택하지 않는다.
	if not completed: return {"complete":false}
	# 상대의 한 번의 응수를 실제 규칙으로 적용해 바로 되빼앗기는 계획을 낮춘다.
	# 상대 정책은 자신의 손패와 공개 전력만 평가한다.
	if command.kind=="end" and Time.get_ticks_msec()+25<deadline:
		var turn = GameManager.state.current_turn
		Commands.apply(command,side,false)
		if GameManager.state.winner!=Enums.Side.NONE: after=Eval.value(side)
		var opponent = WarManager._opp(side)
		if GameManager.state.current_turn==turn and GameManager.state.phasing_player==opponent and GameManager.state.current_phase==Enums.GamePhase.PEACE_TURN:
			var response_visited = {}
			for step in 45:
				if Time.get_ticks_msec()>=deadline: break
				var chooser = Commands.chooser()
				var legal = Commands.options(chooser)
				if legal.is_empty(): break
				legal.sort_custom(func(a,b): return a.rank>b.rank)
				var key = _position_key()
				if response_visited.has(key): legal=legal.filter(func(c):return c.kind not in ["pool","assign","reveal"])
				response_visited[key]=true
				if legal.is_empty() or legal[0].kind=="end": break
				if not Commands.apply(legal[0],chooser,false): break
				nodes += 1
			after = after*0.45+Eval.value(side)*0.55
	return {"complete":true,"value":after,"plan":plan}

func _position_key() -> String:
	# 표현만 다른 명령으로 같은 상태를 방문했는지 확인한다. 로그/실행취소는 제외한다.
	var ac=ActionController
	var st=GameManager.state
	var flags=[]
	for ss in st.spaces.values(): flags.append([ss.controlled_by,ss.has_conflict_marker,ss.is_fort_damaged])
	return str(hash([flags,st.vp,st.britain.current_debt,st.france.current_debt,ac.major_ap_remaining,ac.minor_ap_remaining,ac.event_grants,ac.finished_pools,ac.event_played,ac.upgrade_used,ac.bonus_tiles_bought_this_ar]))

func _result(stats: Array,iterations: int,started: int) -> Dictionary:
	var chosen = {}
	var score = -INF
	for root in stats:
		if root.visits==0: continue
		var mean = root.total/root.visits
		if mean>score: score=mean; chosen=root
	return {"plan":chosen.get("plan",[]),"score":score if not chosen.is_empty() else 0.0,"iterations":iterations,"nodes":nodes,"elapsed_ms":Time.get_ticks_msec()-started,"candidates":stats.size()}
