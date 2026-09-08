extends Node

# 게임 자체 Viewport를 저장한다. 다른 앱의 창이나 비공개 정보가 섞이지 않는다.
var main: Control
var failed=false
var output_path: String
var english = false

func snap(name: String) -> void:
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	if english: _check_language(main,name)
	verify("화면 저장 "+name,get_viewport().get_texture().get_image().save_jpg(output_path.path_join(name+".jpg"),0.94)==OK)

func _check_language(node: Node, screen: String) -> void:
	if node is Control and node.is_visible_in_tree():
		for property in ["text","tooltip_text"]:
			if property=="text" and not (node is Label or node is Button or node is RichTextLabel): continue
			var value = str(node.get(property))
			if LocaleManager._has_korean(value): verify("English text "+screen+" "+str(node.get_path())+" "+property+" "+value.left(120),false)
	for child in node.get_children(): _check_language(child,screen)

func ready_player() -> void:
	var overlay=main.current_session.session_overlay
	if overlay.visible: overlay.actions.get_child(0).pressed.emit()

func verify(label: String,condition: bool) -> void:
	print(("PASS " if condition else "FAIL ")+label)
	if not condition: failed=true

func _ready() -> void:
	seed(43017)
	english = "--english" in OS.get_cmdline_user_args()
	LocaleManager.set_locale("en" if english else "ko")
	output_path=ProjectSettings.globalize_path("res://").path_join("../output/screenshots").simplify_path()
	if english: output_path = output_path.path_join("en")
	DirAccess.make_dir_recursive_absolute(output_path)
	main=load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await snap("01-title")
	main._on_new_game(Enums.Side.NONE)
	verify("로컬 내각 선택 전에 화면 가림",main.current_session.session_overlay.visible)
	await snap("02-handoff")
	ready_player()
	await snap("03-ministry")
	var selector=main.current_session.ministry_select
	verify("내각 선택 중 자기 손패 표시",selector.hand_box.get_child_count()==GameManager.state.get_player(selector.current_side).hand.size()+2)
	selector.card_detail_requested.emit(GameManager.state.get_player(selector.current_side).hand[0])
	await snap("03a-hand-detail")
	verify("손패 상세 확인은 내각 선택을 유지",selector.visible and main.current_session.card_modal.visible and selector.selected_cards.is_empty())
	main.current_session.card_modal.hide()
	if english:
		selector._on_card_clicked(selector.available_cards[0])
		var chosen_id=selector.selected_cards[0].id
		LocaleManager.set_locale("ko")
		verify("한국어 전환 후 내각 미확정 선택 보존",selector.selected_cards.size()==1 and selector.selected_cards[0].id==chosen_id)
		LocaleManager.set_locale("en")
		verify("영어 복귀 후 내각 미확정 선택 보존",selector.selected_cards.size()==1 and selector.selected_cards[0].id==chosen_id)
		await snap("03a-language-roundtrip")
		selector._on_card_clicked(selector.available_cards[0])
	for i in 2:
		ready_player()
		var select=main.current_session.ministry_select
		if i==1: await snap("03b-ministry-france")
		select._on_card_clicked(select.available_cards[0])
		select._on_card_clicked(select.available_cards[1])
		select._on_confirm()
		await get_tree().process_frame
	ready_player()
	var side=GameManager.state.phasing_player
	await snap("03c-investment-selection")
	var tiles=GameManager.state.available_investment_tiles
	var hand=GameManager.state.get_player(side).hand
	var pick=tiles.filter(func(t):return t.has_event_symbol and hand.any(func(c):return c.major_action in [Enums.ActionType.NONE,t.major_action_type]))
	main.current_session._on_tile_selected(pick[0] if not pick.is_empty() else tiles[0])
	await snap("04-investment")
	var playable=hand.filter(func(c):return ActionController._can_play_event(c))
	main.current_session._on_card_clicked(playable[0] if not playable.is_empty() else hand[0])
	await snap("05-card-detail")
	verify("사람 이벤트 사용 버튼 표시",main.current_session.card_modal.play_btn.visible)
	main.current_session.card_modal.play_btn.pressed.emit()
	if MinistryDecisions.has_pending():
		verify("이벤트 사용 전 비공개 내각 공개 질문",ActionController.state==ActionController.ActionState.AWAITING_EVENT)
		main.current_session._on_save()
		main._on_load()
		ready_player()
		verify("실제 메뉴에서 공개 질문 재개",MinistryDecisions.has_pending())
		await snap("05a-ministry-reveal")
		for i in 4:
			if MinistryDecisions.has_pending(): MinistryDecisions.choose(true)
	verify("카드 사용 뒤 이벤트 대기 종료",ActionController.state!=ActionController.ActionState.AWAITING_EVENT)
	if EventEffects.has_pending():
		await snap("05b-card-choice")
		for step in 20:
			if not EventEffects.has_pending() or not AIController._resolve_pending(): break
	verify("이벤트 선택 완료",not EventEffects.has_pending())
	await snap("06-board")
	main.current_session._on_cards_btn()
	var browser=main.current_session.card_browser
	verify("하단 버튼은 사용된 카드",main.current_session.cards_btn.text==LocaleManager.tx("사용된 카드"))
	browser._on_card_clicked(GameManager.state.event_played_pile[0])
	await snap("06a-played-detail")
	var modal=main.current_session.card_modal
	verify("사용된 카드 상세가 목록 앞에 표시",browser.visible and modal.visible and modal.z_index>browser.z_index and modal.get_index()>browser.get_index())
	modal.hide()
	browser.hide()
	# 실제 외교 뽑기 버튼을 누르고 카드 상세·손패·상단 숫자·저장 재개를 확인한다.
	# 위에서 실제로 고른 타일이 외교라면 부족한 점수를 일반 채무로 보충한다.
	if ActionController.current_action_type()==Enums.ActionType.DIPLOMATIC:
		for i in 3:
			if ActionController.can_draw_event(): break
			ActionController.take_debt_for_ap(1)
			if MinistryDecisions.has_pending(): MinistryDecisions.choose(true)
		var draw_button=main.current_session.action_panel.body.get_node("DrawEventButton")
		verify("외교 뽑기 버튼 활성화",not draw_button.disabled)
		await snap("06b-diplomacy-ready")
		var old_hand_size=GameManager.state.get_player(side).hand.size()
		draw_button.pressed.emit()
		verify("실제 버튼으로 외교 3점 지출 후 새 카드 상세",GameManager.state.get_player(side).hand.size()==old_hand_size+1 and main.current_session.card_modal.visible)
		var drawn_card_id=GameManager.state.get_player(side).hand.back().id
		await snap("06c-drawn-card")
		main.current_session.card_modal.hide()
		verify("상단 손패 숫자가 즉시 갱신",main.current_session.hud.players[side].values[4].text==str(old_hand_size+1))
		main.current_session._on_save()
		main._on_load()
		ready_player()
		verify("실제 메뉴 재개 후 외교 뽑기 결과 보존",GameManager.state.get_player(side).hand.back().id==drawn_card_id and not ActionController.can_undo())
		var display=main.current_session.inv_display
		display.toggle.pressed.emit()
		verify("남은 타일 펼쳐도 행동 패널과 겹치지 않음",display.expanded and display.get_global_rect().end.y<=main.current_session.action_panel.get_global_rect().position.y)
		await snap("06d-remaining-investments")
		display.toggle.pressed.emit()
		await snap("06e-dashboard")
		if english:
			var state_before=JSON.stringify(SaveLoad._serialize())
			LocaleManager.set_locale("ko")
			LocaleManager.set_locale("en")
			verify("언어 전환은 게임 상태를 바꾸지 않음",JSON.stringify(SaveLoad._serialize())==state_before)
			await snap("06e-dashboard-roundtrip")
			main.current_session._on_view_war_tiles(side)
			await snap("06g-war-navigation")
			main.current_session.war_tile_viewer.hide()
		# 이벤트로 세계 수요가 추가된 경계 화면도 검수한다. 레이아웃 검사용
		# 상태임을 파일명에 남기고, 캡처 후 원래 수요를 복원한다.
		var original_demand=GameManager.state.current_global_demand.duplicate()
		GameManager.state.current_global_demand.append(Enums.Commodity.COTTON)
		main.current_session.hud.refresh()
		await snap("06f-four-demand-layout-check")
		verify("세계 수요 4종 모두 표시",main.current_session.hud.demand_cells.filter(func(c):return c.panel.visible).size()==4)
		for cell in main.current_session.hud.demand_cells:
			if cell.panel.visible: verify("수요 보상 글자가 칸 안에 표시",cell.reward.position.x+cell.reward.size.x<=cell.panel.size.x and cell.reward.position.y+cell.reward.size.y<=cell.panel.size.y)
		GameManager.state.current_global_demand.assign(original_demand)
		main.current_session.hud.refresh()
	else:
		verify("외교 UI 검사에 사용할 타일",false)
	await _check_navy_display(side)
	# 실제 메뉴의 불러오기 버튼과 같은 경로로 선택 대기 상태를 복원한다.
	ActionController.begin_action_round(side,InvestmentTile.create(99,Enums.ActionType.MILITARY,4,Enums.ActionType.ECONOMIC,false,true))
	verify("보너스 타일 뽑기",ActionController.begin_bonus_purchase())
	var drawn_id=ActionController.bonus_drawn.id
	main.current_session._on_save()
	main.current_session._on_menu()
	main._on_load()
	ready_player()
	verify("저장 후 뽑은 타일과 배치 창 복원",ActionController.bonus_drawn.id==drawn_id and main.current_session.war_tile_purchase.visible)
	await snap("07-war-tile")
	ActionController.place_bonus_tile(ActionController.bonus_allowed_theaters[0])
	main.current_session.war_tile_purchase.hide()
	main.current_session._on_upgrade_requested()
	main.current_session.war_tile_viewer._on_pick_theater(WarManager.get_upcoming_theaters()[0].id)
	main.current_session._on_save()
	main._on_load()
	ready_player()
	verify("교체 선택 대기와 교체 창 복원",ActionController.upgrade_drawn!=null and main.current_session.war_tile_viewer.visible)
	await snap("08-upgrade")
	main.current_session.war_tile_viewer._on_upgrade_decision(true,false)
	GameManager.state.current_phase=Enums.GamePhase.WAR
	WarManager.begin_war(WarManager.current_war_id)
	await snap("09-war")
	WarFlow.start(false)
	ready_player()
	await snap("10-war-choice")
	GameManager._declare_victory(Enums.Side.FRANCE,"Visual verification result" if english else "화면 검수용 승리 결과")
	await snap("11-result")
	print("VISUAL / RESUME "+("FAIL" if failed else "PASS"))
	get_tree().quit(1 if failed else 0)

func _check_navy_display(side: int) -> void:
	# UI의 임의 숫자 교체만 검사하지 않는다. 실제 건조·배치 명령을 실행하고,
	# 같은 프레임의 모델 변경이 지도와 정보창 양쪽에 전달되는지 대조한다.
	var original = SaveLoad._serialize()
	var player = GameManager.state.get_player(side)
	var before = player.squadrons_in_navy_box
	ActionController.begin_action_round(side,InvestmentTile.create(98,Enums.ActionType.MILITARY,4,Enums.ActionType.ECONOMIC,false,false))
	verify("실제 함대 건조",ActionController.construct_squadron())
	await get_tree().process_frame
	await get_tree().process_frame
	_verify_navy_count(side,before+1,"건조 후")
	ActionController.begin_action_round(side,InvestmentTile.create(98,Enums.ActionType.MILITARY,4,Enums.ActionType.ECONOMIC,false,false))
	var naval = GameManager.state.spaces.values().filter(func(s):return s.data.space_type==Enums.SpaceType.NAVAL and s.controlled_by==Enums.Side.NONE)
	verify("실제 해군 상자에서 지도에 배치",not naval.is_empty() and ActionController.deploy_squadron_to(naval[0].data.id,"navy"))
	await get_tree().process_frame
	await get_tree().process_frame
	_verify_navy_count(side,before,"배치 후")
	await snap("06h-navy-deployed")
	var board = main.current_session.game_board
	var overlay = board.navy_box_view.get_parent()
	board._zoom_at(overlay.position+overlay.size/2,2.6)
	await snap("06i-navy-map-zoom")
	verify("지도 함대 말은 지도와 함께 확대",is_equal_approx(board.navy_box_view.get_global_transform().get_scale().x,board.zoom_level))
	board.reset_view()
	# 0척·8척은 명시적 표시 경계용 상태다. 검사 뒤 원래 게임 그래프를 복원한다.
	GameManager.state.britain.squadrons_in_navy_box = 8
	GameManager.state.france.squadrons_in_navy_box = 0
	GameManager.state.france.squadrons_returning[GameManager.state.current_turn+1] = 2
	main.current_session.hud.refresh()
	await snap("06j-navy-count-boundary")
	_verify_navy_count(Enums.Side.BRITAIN,8,"8척 경계")
	_verify_navy_count(Enums.Side.FRANCE,0,"귀환 예정은 대기에 제외")
	for view in [main.current_session.navy_panel.navy_view,board.navy_box_view]:
		for row in view.rows.values():
			for rect in row.tokens.token_rects:
				verify("함대 말이 표시 영역 안에 있음",rect.end.x<=row.tokens.size.x+0.1 and rect.end.y<=row.tokens.size.y+0.1)
	for cell in main.current_session.hud.demand_cells:
		if cell.panel.visible:
			verify("세계 수요 상품 그림과 승점 아이콘 표시",cell.commodity_icon.texture!=null and cell.icons[0].visible)
	verify("해군 표시 검사 전 저장 상태 복원",SaveLoad._deserialize(JSON.parse_string(JSON.stringify(original))))
	board.bind_to_state()
	main.current_session.hud.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	_verify_navy_count(side,before,"저장 복원 후")

func _verify_navy_count(side: int, expected: int, stage: String) -> void:
	var panel = main.current_session.navy_panel.navy_view.rows[side]
	var board = main.current_session.game_board.navy_box_view.rows[side]
	verify(stage+" 정보창·지도 대기 수와 숫자 일치",panel.tokens.count==expected and board.tokens.count==expected and panel.count.text==LocaleManager.tx("대기 %d척") % expected)
