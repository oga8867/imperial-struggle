extends "res://scripts/card_regression.gd"

func _ready() -> void:
	await get_tree().process_frame
	fresh()
	# 실제 별도 프로세스를 시작해 화면 갱신과 취소를 확인한다.
	AIController.enable_for(Enums.Side.FRANCE,true)
	AIController.budget_seconds=10
	AIController.request_turn()
	var until=Time.get_ticks_msec()+7000
	while not AIController.thinking and Time.get_ticks_msec()<until: await get_tree().process_frame
	check("백그라운드 계산 시작",AIController.thinking and AIController._pid>0)
	var running_pid=AIController._pid
	var before=SaveLoad._serialize().payload
	var frames=0
	var wait_until=Time.get_ticks_msec()+250
	while Time.get_ticks_msec()<wait_until:
		frames+=1
		await get_tree().process_frame
	check("계산 중에도 화면 갱신 지속",frames>5)
	# 생각 시간만 바뀌며 실제 규칙 모델은 계산 시작 전과 같아야 한다.
	var codec=preload("res://scripts/models/session_codec.gd")
	var old=codec.new().decode(before)
	var current=codec.new().decode(SaveLoad._serialize().payload)
	old.AIController.search_spent_ms=current.AIController.search_spent_ms
	check("계산 중 실제 게임 상태 불변",codec.new().encode(old)==codec.new().encode(current))
	AIController.suspend()
	check("메뉴에서 소유 작업 프로세스 중단",not AIController.thinking and not OS.is_process_running(running_pid))
	check("검색 예산 저장",SaveLoad.save_game("ai_runtime") and AIController.search_spent_ms>0)
	var used=AIController.search_spent_ms
	AIController.search_spent_ms=0
	check("검색 예산과 모드 복원",SaveLoad.load_game("ai_runtime") and AIController.strategy_mode and AIController.search_spent_ms==used)
	AIController.resume()
	var resumed_at=Time.get_ticks_msec()
	until=Time.get_ticks_msec()+35000
	var root=GameManager.state
	while GameManager.state==root and root.phasing_player==Enums.Side.FRANCE and Time.get_ticks_msec()<until:
		await get_tree().process_frame
	print("AI FINAL STATE ",AIController._active," chooser=",AIController.Commands.chooser()," side=",AIController.ai_side," pending=",EventEffects.pending_choices," ministry=",MinistryDecisions.pending)
	check("전략 AI 라운드 완료",GameManager.state.phasing_player!=Enums.Side.FRANCE or ActionController.current_tile==null)
	check("라운드 계산 예산을 누적 적용",AIController.search_spent_ms<=11000 and Time.get_ticks_msec()-resumed_at<30000)
	print("AI RUNTIME REPORT ",JSON.stringify(AIController.last_report)," spent=",AIController.search_spent_ms)
	AIController.disable()
	print("AI RUNTIME REGRESSION: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed==0 else 1)
