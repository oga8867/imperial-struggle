extends Control

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


func _ready() -> void:
	GameManager.player_action_required.connect(_on_action_required)
	GameManager.action_round_started.connect(_on_action_round_started)
	GameManager.game_over.connect(_on_game_over)
	GameManager.phase_changed.connect(_on_phase_changed)

	if inv_display:
		inv_display.tile_selected.connect(_on_tile_selected)
	if hand_display:
		hand_display.card_clicked.connect(_on_card_clicked)
	if ministry_select:
		ministry_select.ministry_selected.connect(_on_ministry_selected)
	if action_panel and action_panel.has_signal("war_tile_requested"):
		action_panel.war_tile_requested.connect(_on_war_tile_requested)
	if action_panel and action_panel.has_signal("war_tile_upgrade_requested"):
		action_panel.war_tile_upgrade_requested.connect(_on_upgrade_requested)
	if navy_panel and navy_panel.has_signal("view_war_tiles_requested"):
		navy_panel.view_war_tiles_requested.connect(_on_view_war_tiles)
	if log_panel and log_panel.has_signal("hover_spaces_changed"):
		log_panel.hover_spaces_changed.connect(_on_log_hover_spaces)


func _on_log_hover_spaces(space_ids: Array) -> void:
	if game_board and game_board.has_method("highlight_spaces"):
		game_board.highlight_spaces(space_ids)
	pass_btn.pressed.connect(_on_pass)


func _on_upgrade_requested() -> void:
	if war_tile_viewer:
		war_tile_viewer.show_for(GameManager.state.phasing_player, true)


func _on_view_war_tiles(side: Enums.Side) -> void:
	if war_tile_viewer:
		war_tile_viewer.show_for(side, false)
	pass_btn.visible = false
	save_btn.pressed.connect(_on_save)
	menu_btn.pressed.connect(_on_menu)
	cards_btn.pressed.connect(_on_cards_btn)
	GameManager.status_message.connect(_on_status_message)


func _on_cards_btn() -> void:
	if card_browser:
		card_browser.show_in_game()


func _on_save() -> void:
	if SaveLoad.save_game():
		prompt_label.text = "Game saved."


func _on_menu() -> void:
	menu_requested.emit()


func _on_status_message(text: String) -> void:
	prompt_label.text = text


func _on_war_tile_requested() -> void:
	if war_tile_purchase:
		war_tile_purchase.show_for(GameManager.state.phasing_player)


func bind_to_state() -> void:
	if game_board.has_method("bind_to_state"):
		game_board.bind_to_state()
	if hand_display:
		hand_display.set_side(active_player_view)
	if hud and hud.has_method("refresh"):
		hud.refresh()


func _on_action_round_started(side: Enums.Side, round_num: int) -> void:
	active_player_view = side
	if hand_display:
		hand_display.set_side(side)
	prompt_label.text = "%s — Action Round %d/4" % [_side_name(side), round_num]


func _on_action_required(side: Enums.Side, action: String) -> void:
	match action:
		"select_investment_tile":
			prompt_label.text = "%s: Select an Investment Tile" % _side_name(side)
			pass_btn.visible = true
			_check_ai(side, "select_tile")
		"play_actions":
			prompt_label.text = "%s: Play event (optional), then spend AP" % _side_name(side)
			pass_btn.visible = false
			_check_ai(side, "play_actions")
		"select_ministry":
			prompt_label.text = "%s: Choose Ministry Cards" % _side_name(side)
			pass_btn.visible = false
			ministry_select.show_for_side(side)


func _check_ai(side: Enums.Side, what: String) -> void:
	if not AIController.enabled or AIController.ai_side != side:
		return
	await get_tree().create_timer(0.4).timeout
	match what:
		"select_tile":
			var tile = AIController.decide_investment_tile()
			if tile:
				GameManager.select_investment_tile(side, tile)
		"play_actions":
			AIController.decide_action_round()


func _on_ministry_selected(_side: Enums.Side, _cards: Array) -> void:
	pass


func _on_phase_changed(phase: Enums.TurnPhase) -> void:
	if phase == Enums.TurnPhase.SCORING_PHASE or phase == Enums.TurnPhase.VICTORY_CHECK:
		prompt_label.text = "Scoring..."
		pass_btn.visible = false


func _on_tile_selected(tile: InvestmentTile) -> void:
	GameManager.select_investment_tile(GameManager.state.phasing_player, tile)


func _on_card_clicked(card) -> void:
	# If we're in AWAITING_EVENT state, attempt to play the card; else show modal.
	if (card is EventCard
			and ActionController.state == ActionController.ActionState.AWAITING_EVENT
			and ActionController.current_side == active_player_view):
		var played := ActionController.play_event(card, true)
		if not played:
			# Fall back to showing the card if it can't be played
			if card_modal and card_modal.has_method("show_card"):
				card_modal.show_card(card)
		else:
			if hand_display:
				hand_display.refresh()
	elif card_modal and card_modal.has_method("show_card"):
		card_modal.show_card(card)


func _on_pass() -> void:
	GameManager.pass_action_round(GameManager.state.phasing_player)


func _on_game_over(winner: Enums.Side) -> void:
	prompt_label.text = "%s WINS! Final VP: %d" % [_side_name(winner), GameManager.state.vp]
	pass_btn.visible = false


func _side_name(side: Enums.Side) -> String:
	match side:
		Enums.Side.BRITAIN: return "Britain"
		Enums.Side.FRANCE: return "France"
	return ""
