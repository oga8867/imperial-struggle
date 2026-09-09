extends Control

const Layout = preload("res://scripts/ui/session_layout.gd")

@onready var game_board: Control = $GameBoardLayer/GameBoard
@onready var hud: Control = $UILayer/HUD
@onready var inv_display: Control = $UILayer/InvestmentDisplay
@onready var hand_display: Control = $UILayer/HandDisplay
@onready var card_modal: Control = $UILayer/CardModal
@onready var log_panel: Control = $UILayer/LogPanel
@onready var ministry_select: Control = $UILayer/MinistrySelect
@onready var war_display: Control = $UILayer/WarDisplay
@onready var war_tile_purchase: Control = $UILayer/WarTilePurchase
@onready var war_tile_viewer: Control = $UILayer/WarTileViewer
@onready var navy_panel: Control = $UILayer/NavyPanel
@onready var action_panel: Control = $UILayer/ActionPanel
@onready var prompt_label: Label = $UILayer/PromptBar/PromptLabel
@onready var pass_btn: Button = $UILayer/PromptBar/PassBtn
@onready var save_btn: Button = $UILayer/PromptBar/SaveBtn
@onready var menu_btn: Button = $UILayer/PromptBar/MenuBtn
@onready var cards_btn: Button = $UILayer/PromptBar/CardsBtn
@onready var card_browser: Control = $UILayer/CardBrowser

signal menu_requested

var active_player_view: Enums.Side = Enums.Side.FRANCE
var ai_pending_side: Enums.Side = Enums.Side.NONE
var _prompt_is_dynamic: bool = false
var decision_overlay: Control
var session_overlay: Control
var private_side: int = Enums.Side.NONE


func _ready() -> void:
	theme = ThemeManager.theme
	ActionController.event_card_drawn.connect(_on_event_card_drawn)
	inv_display.expanded_changed.connect(_layout_work_area)
	_layout_work_area()
	GameManager.player_action_required.connect(_on_action_required)
	GameManager.action_round_started.connect(_on_action_round_started)
	GameManager.game_over.connect(_on_game_over)
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.status_message.connect(_on_status_message)
	LocaleManager.locale_changed.connect(_on_locale_changed)
	AIController.thinking_changed.connect(_refresh_ai_status)
	MinistryDecisions.changed.connect(func(): AIController.request_turn())
	if has_node("/root/EventEffects"):
		EventEffects.pending_choices_changed.connect(_on_event_choices_changed)
		EventEffects.effects_resolved.connect(_on_event_effects_resolved)
	_refresh_static_texts()
	decision_overlay = preload("res://scripts/ui/decision_overlay.gd").new()
	$UILayer.add_child(decision_overlay)
	$UILayer.add_child(preload("res://scripts/ui/card_choice_overlay.gd").new())
	$UILayer.add_child(preload("res://scripts/ui/ministry_reveal_overlay.gd").new())
	MinistryDecisions.changed.connect(func():
		if MinistryDecisions.has_pending(): card_modal.hide())
	MinistryDecisions.resolved.connect(func():
		if AIController.is_ai_turn() and ActionController.current_tile: _check_ai(GameManager.state.phasing_player,"play_actions"))
	session_overlay=preload("res://scripts/ui/session_overlay.gd").new()
	$UILayer.add_child(session_overlay)
	WarFlow.changed.connect(func():
		if WarFlow.active and not WarFlow.choice.is_empty():
			_guard_private_side(WarFlow.choice.side)
			AIController.request_turn())

	# Top prompt-bar buttons
	pass_btn.pressed.connect(_on_pass)
	save_btn.pressed.connect(_on_save)
	menu_btn.pressed.connect(_on_menu)
	cards_btn.pressed.connect(_on_cards_btn)

	if inv_display:
		inv_display.tile_selected.connect(_on_tile_selected)
	if hand_display:
		hand_display.card_clicked.connect(_on_card_clicked)
	if ministry_select:
		ministry_select.ministry_selected.connect(_on_ministry_selected)
		ministry_select.card_detail_requested.connect(_on_card_clicked)
	card_browser.card_modal_node=card_modal
	if action_panel and action_panel.has_signal("war_tile_requested"):
		action_panel.war_tile_requested.connect(_on_war_tile_requested)
	if action_panel and action_panel.has_signal("war_tile_upgrade_requested"):
		action_panel.war_tile_upgrade_requested.connect(_on_upgrade_requested)
	if navy_panel and navy_panel.has_signal("view_war_tiles_requested"):
		navy_panel.view_war_tiles_requested.connect(_on_view_war_tiles)
	if log_panel and log_panel.has_signal("hover_spaces_changed"):
		log_panel.hover_spaces_changed.connect(_on_log_hover_spaces)
	LocaleManager.bind_literals(self)


func _refresh_static_texts() -> void:
	pass_btn.text = LocaleManager.t("btn_pass")
	save_btn.text = LocaleManager.t("btn_save")
	menu_btn.text = LocaleManager.t("btn_menu")
	cards_btn.text = LocaleManager.tx("사용된 카드")
	if not _prompt_is_dynamic:
		prompt_label.text = LocaleManager.t("prompt_welcome")

func _on_event_card_drawn(side: Enums.Side, card: EventCard) -> void:
	hand_display.refresh()
	hud.refresh()
	if card != null and side == active_player_view and not AIController.is_ai_turn():
		_on_card_clicked(card)
		prompt_label.text = LocaleManager.tx("외교 3점으로 카드를 뽑았습니다. 이번 라운드의 이벤트 사용 시점은 이미 지났습니다.")

func _layout_work_area() -> void:
	# 투자 선택 이후에는 현재 행동이 주된 작업이다. 남은 타일은 언제든
	# 펼쳐 볼 수 있으며, 두 패널이 같은 위치를 덮지 않도록 함께 재배치한다.
	Layout.place(log_panel,Rect2(968,280,296,160))
	Layout.place(navy_panel,Rect2(968,456,296,232))
	Layout.place($UILayer/AdvantagePanel,Rect2(968,704,296,160))
	Layout.place($UILayer/MinistryHand,Rect2(24,872,352,152))
	Layout.place(hand_display,Rect2(392,872,872,152))
	var investment_height = 444.0 if inv_display.expanded else 56.0
	Layout.place(inv_display,Rect2(Layout.RIGHT_X,Layout.WORK_TOP,Layout.RIGHT_WIDTH,investment_height))
	var action_top = Layout.WORK_TOP+investment_height+16
	Layout.place(action_panel,Rect2(Layout.RIGHT_X,action_top,Layout.RIGHT_WIDTH,Layout.WORK_BOTTOM-action_top))


func _on_locale_changed(_new_locale: String) -> void:
	_refresh_static_texts()
	if GameManager.state:
		var key = "prompt_select_tile" if ActionController.current_tile == null else "prompt_play_actions"
		prompt_label.text = LocaleManager.tf(key,[LocaleManager.side(GameManager.state.phasing_player)])
	_refresh_ai_status()


func _on_log_hover_spaces(space_ids: Array) -> void:
	if game_board and game_board.has_method("highlight_spaces"):
		game_board.highlight_spaces(space_ids)


func _on_upgrade_requested() -> void:
	if war_tile_viewer:
		war_tile_viewer.show_for(GameManager.state.phasing_player, true)


func _on_view_war_tiles(side: Enums.Side) -> void:
	if war_tile_viewer:
		war_tile_viewer.show_for(active_player_view, false)
	pass_btn.visible = false


func _on_cards_btn() -> void:
	if card_browser:
		card_browser.show_in_game()


func _on_save() -> void:
	if SaveLoad.save_game():
		_prompt_is_dynamic = true
		prompt_label.text = LocaleManager.t("prompt_game_saved")
	else:
		prompt_label.text=LocaleManager.tx("저장 실패: ")+SaveLoad.last_error


func _on_menu() -> void:
	AIController.suspend()
	menu_requested.emit()


func _on_status_message(text: String) -> void:
	_prompt_is_dynamic = true
	prompt_label.text = LocaleManager.message(text)


func _on_war_tile_requested() -> void:
	if war_tile_purchase:
		war_tile_purchase.show_for(GameManager.state.phasing_player)


func bind_to_state() -> void:
	active_player_view = (Enums.Side.FRANCE if AIController.ai_side == Enums.Side.BRITAIN else Enums.Side.BRITAIN) if AIController.enabled else (private_side if private_side!=Enums.Side.NONE else GameManager.state.phasing_player)
	if game_board.has_method("bind_to_state"):
		game_board.bind_to_state()
	if hand_display:
		hand_display.set_side(active_player_view)
	if hud and hud.has_method("refresh"):
		hud.refresh()
	if not AIController.enabled: _guard_private_side(active_player_view)
	if ActionController.upgrade_drawn: war_tile_viewer.show_for(active_player_view,true)
	if ActionController.bonus_drawn: war_tile_purchase.show_for(active_player_view)


func _on_action_round_started(side: Enums.Side, round_num: int) -> void:
	_guard_private_side(side)
	active_player_view = (Enums.Side.FRANCE if AIController.ai_side == Enums.Side.BRITAIN else Enums.Side.BRITAIN) if AIController.enabled else side
	if hand_display:
		hand_display.set_side(active_player_view)
	_prompt_is_dynamic = true
	prompt_label.text = LocaleManager.tf("hud_action_round", [LocaleManager.side(side), round_num])


func _on_action_required(side: Enums.Side, action: String) -> void:
	_guard_private_side(side)
	_prompt_is_dynamic = true
	match action:
		"discard_events", "choose_first_player":
			decision_overlay.show_decision(side, action)
			pass_btn.hide()
		"select_investment_tile":
			prompt_label.text = LocaleManager.tf("prompt_select_tile", [LocaleManager.side(side)])
			pass_btn.visible = false
			_check_ai(side, "select_tile")
		"play_actions":
			prompt_label.text = LocaleManager.tf("prompt_play_actions", [LocaleManager.side(side)])
			pass_btn.visible = false
			_check_ai(side, "play_actions")
		"select_ministry":
			prompt_label.text = LocaleManager.tf("prompt_select_ministry", [LocaleManager.side(side)])
			pass_btn.visible = false
			ministry_select.show_for_side(side)


func _check_ai(side: Enums.Side, what: String) -> void:
	if AIController.strategy_mode:
		if is_visible_in_tree(): AIController.request_turn()
		return
	if MinistryDecisions.has_pending(): return
	if not AIController.enabled or AIController.ai_side != side:
		return
	var expected_state=GameManager.state
	var expected_turn=expected_state.current_turn
	var expected_round=expected_state.current_action_round
	var expected_tile=ActionController.current_tile
	await get_tree().create_timer(0.4).timeout
	if not is_visible_in_tree() or not AIController.enabled or AIController.ai_side != side or GameManager.state.phasing_player != side:
		return
	if GameManager.state!=expected_state or expected_state.current_turn!=expected_turn or expected_state.current_action_round!=expected_round or expected_state.current_phase==Enums.GamePhase.GAME_OVER or ActionController.current_tile!=expected_tile: return
	match what:
		"select_tile":
			while EventEffects.has_pending():
				if not AIController._resolve_pending(): return
			var tile = AIController.decide_investment_tile()
			if tile:
				GameManager.select_investment_tile(side, tile)
		"play_actions":
			AIController.decide_action_round()


func _on_ministry_selected(_side: Enums.Side, _cards: Array) -> void:
	pass


func _on_phase_changed(phase: Enums.TurnPhase) -> void:
	if phase == Enums.TurnPhase.SCORING_PHASE or phase == Enums.TurnPhase.VICTORY_CHECK:
		_prompt_is_dynamic = true
		prompt_label.text = LocaleManager.t("prompt_scoring")
		pass_btn.visible = false


func _on_tile_selected(tile: InvestmentTile) -> void:
	if AIController.is_ai_turn(): return
	GameManager.select_investment_tile(GameManager.state.phasing_player, tile)


func _on_card_clicked(card) -> void:
	if card_modal: card_modal.show_card(card)


func _on_pass() -> void:
	if AIController.thinking:
		AIController.decide_now()
		return
	# While an Event effect is awaiting a target, the Pass button acts as "Skip Effect".
	if has_node("/root/EventEffects") and EventEffects.has_pending():
		EventEffects.skip_choice(0)
		return
	GameManager.pass_action_round(GameManager.state.phasing_player)


func _on_event_choices_changed(_choices: Array) -> void:
	AIController.request_turn()
	if not EventEffects.pending_choices.is_empty():
		var p=EventEffects.pending_choices[0].params
		_guard_private_side(p.get("chooser",p.get("side",GameManager.state.phasing_player)))
	_prompt_is_dynamic = true
	prompt_label.text = LocaleManager.t("prompt_event_choice")
	pass_btn.text = LocaleManager.t("btn_skip_effect")
	pass_btn.visible = not EventEffects.pending_choices.is_empty() and EventEffects.pending_choices[0].params.get("optional",false)
	if AIController.enabled and AIController.Commands.chooser()==AIController.ai_side: pass_btn.visible=false

func _refresh_ai_status() -> void:
	if AIController.thinking:
		_prompt_is_dynamic=true
		prompt_label.text=AIController.status_text()
		pass_btn.text=LocaleManager.tx("지금 결정")
		pass_btn.visible=true
	elif pass_btn.text==LocaleManager.tx("지금 결정"):
		pass_btn.hide()


func _on_event_effects_resolved() -> void:
	if GameManager.state: _guard_private_side(GameManager.state.phasing_player)
	if AIController.is_ai_turn(): _check_ai(GameManager.state.phasing_player,"select_tile" if ActionController.current_tile==null else "play_actions")
	pass_btn.text = LocaleManager.t("btn_pass")
	# Return to the normal play-actions prompt for the active side.
	if GameManager.state and GameManager.state.current_phase != Enums.GamePhase.GAME_OVER:
		prompt_label.text = LocaleManager.tf("prompt_play_actions", [LocaleManager.side(active_player_view)])
	pass_btn.visible = false


func _on_game_over(winner: Enums.Side) -> void:
	_prompt_is_dynamic = true
	prompt_label.text = LocaleManager.tf("prompt_wins", [LocaleManager.side(winner), GameManager.state.vp])
	pass_btn.visible = false
	war_display.hide()
	session_overlay.victory(winner,func(): pass,func(): menu_requested.emit())

func _guard_private_side(side: int) -> void:
	if AIController.enabled or session_overlay==null or side==Enums.Side.NONE or side==private_side: return
	private_side=side
	card_modal.hide()
	war_tile_viewer.hide()
	card_browser.hide()
	session_overlay.handoff(side,func():
		active_player_view=side
		hand_display.set_side(side)
		$UILayer/MinistryHand.set_view_side(side))
