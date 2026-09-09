extends "res://scripts/validation_capture.gd"

func _ready() -> void:
	seed(43017)
	english="--english" in OS.get_cmdline_user_args()
	LocaleManager.set_locale("en" if english else "ko")
	output_path=ProjectSettings.globalize_path("res://../output/screenshots/ai-en" if english else "res://../output/screenshots/ai-ko")
	DirAccess.make_dir_recursive_absolute(output_path)
	main=load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await snap("01-ai-menu")
	verify("전략 20초 기본 선택",main.ai_mode_select.selected==2)
	var font=ThemeManager.theme.default_font
	verify("AI 안내 한글 글꼴 지원",font!=null and font.has_char("계".unicode_at(0)) and font.has_char("략".unicode_at(0)))
	main._on_new_game(Enums.Side.FRANCE)
	var selector=main.current_session.ministry_select
	for i in mini(2,selector.available_cards.size()): selector._on_card_clicked(selector.available_cards[i])
	selector._on_confirm()
	var until=Time.get_ticks_msec()+6000
	while not AIController.thinking and Time.get_ticks_msec()<until: await get_tree().process_frame
	verify("게임 화면에서 전략 계산 시작",AIController.thinking)
	await snap("02-ai-thinking")
	verify("즉시 결정 버튼 표시",main.current_session.pass_btn.visible and main.current_session.pass_btn.text==LocaleManager.tx("지금 결정"))
	main.current_session._on_save()
	verify("계산 중 저장 가능",FileAccess.file_exists(SaveLoad._path("autosave")))
	var pid=AIController._pid
	main.current_session._on_menu()
	verify("메뉴 이동 시 계산 중지",not AIController.thinking and (pid<=0 or not OS.is_process_running(pid)))
	await snap("03-ai-menu-paused")
	main._on_load()
	until=Time.get_ticks_msec()+6000
	while not AIController.thinking and Time.get_ticks_msec()<until: await get_tree().process_frame
	verify("화면에서 저장 불러오기와 계산 재개",AIController.strategy_mode and AIController.thinking)
	await snap("04-ai-resumed")
	main.current_session.pass_btn.pressed.emit()
	verify("즉시 결정으로 기다리기 종료",not AIController.thinking)
	await get_tree().create_timer(0.4).timeout
	AIController.suspend()
	verify("영어 번역 누락 없음",LocaleManager.missing_translations.is_empty())
	print("AI VISUAL VALIDATION ","FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
