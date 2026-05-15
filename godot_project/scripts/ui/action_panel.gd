extends Control

@onready var step_label: Label = $Panel/VBox/StepLabel
@onready var hint_label: Label = $Panel/VBox/HintLabel
@onready var ap_label: Label = $Panel/VBox/APLabel
@onready var major_btn: Button = $Panel/VBox/HBox/MajorBtn
@onready var minor_btn: Button = $Panel/VBox/HBox/MinorBtn
@onready var upgrade_btn: Button = $Panel/VBox/HBox/UpgradeBtn
@onready var skip_event_btn: Button = $Panel/VBox/SkipEventBtn
@onready var end_btn: Button = $Panel/VBox/EndBtn
@onready var war_tile_btn: Button = $Panel/VBox/WarTileBtn
@onready var debt_row: HBoxContainer = $Panel/VBox/DebtRow
@onready var debt_btn: Button = $Panel/VBox/DebtRow/DebtBtn
@onready var debt_btn2: Button = $Panel/VBox/DebtRow/DebtBtn2
@onready var tp_btn: Button = $Panel/VBox/DebtRow/TpBtn
@onready var undo_btn: Button = $Panel/VBox/UndoBtn

signal war_tile_requested
signal war_tile_upgrade_requested
signal war_tile_view_requested


func _ready() -> void:
	# Always visible to show current state
	ActionController.action_state_changed.connect(_on_state_changed)
	ActionController.ap_changed.connect(_refresh)
	ActionController.action_round_ended.connect(_on_round_ended)
	GameManager.action_round_started.connect(func(_s, _r): _refresh())
	GameManager.player_action_required.connect(func(_s, _a): _refresh())

	major_btn.pressed.connect(ActionController.switch_to_major)
	minor_btn.pressed.connect(ActionController.switch_to_minor)
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	skip_event_btn.pressed.connect(ActionController.skip_event)
	end_btn.pressed.connect(ActionController.end_action_round)
	war_tile_btn.pressed.connect(func(): war_tile_requested.emit())
	debt_btn.pressed.connect(_on_debt_1_pressed)
	debt_btn2.pressed.connect(_on_debt_2_pressed)
	tp_btn.pressed.connect(_on_tp_pressed)
	undo_btn.pressed.connect(_on_undo_pressed)
	_refresh()


func _on_upgrade_pressed() -> void:
	# Open the War Tile Viewer in upgrade mode
	war_tile_upgrade_requested.emit()


func _on_debt_1_pressed() -> void:
	var before_ap = ActionController.major_ap_remaining
	var p = GameManager.state.get_player(ActionController.current_side) if ActionController.current_side != Enums.Side.NONE else null
	var before_debt = p.current_debt if p else -1
	var got = ActionController.take_debt_for_ap(1)
	print("[ActionPanel] Debt+1: state=%d side=%d ap %d→%d debt %d→%d got=%d" % [
		ActionController.state, ActionController.current_side,
		before_ap, ActionController.major_ap_remaining,
		before_debt, p.current_debt if p else -1, got])
	if has_node("/root/FileLogger"):
		FileLogger.log_debug("Debt+1 click: got=%d ap_now=%d debt_now=%d" % [got, ActionController.major_ap_remaining, p.current_debt if p else -1])
	_refresh()


func _on_debt_2_pressed() -> void:
	var got = ActionController.take_debt_for_ap(2)
	if has_node("/root/FileLogger"):
		FileLogger.log_debug("Debt+2 click: got=%d" % got)
	_refresh()


func _on_tp_pressed() -> void:
	var got = ActionController.spend_treaty_points_for_ap(1)
	if has_node("/root/FileLogger"):
		FileLogger.log_debug("TP click: got=%d" % got)
	_refresh()


func _on_undo_pressed() -> void:
	if ActionController.undo_last():
		_refresh()


func _on_state_changed(_label: String) -> void:
	_refresh()


func _on_round_ended() -> void:
	_refresh()


func _refresh() -> void:
	var ac_state = ActionController.state
	var tile = ActionController.current_tile

	# IDLE — waiting for investment tile selection
	if ac_state == ActionController.ActionState.IDLE or tile == null:
		step_label.text = "1. SELECT INVESTMENT TILE"
		step_label.modulate = Color("fbbf24")
		hint_label.text = "Click one of the 9 tiles on the right →"
		ap_label.text = ""
		major_btn.visible = false
		minor_btn.visible = false
		upgrade_btn.visible = false
		war_tile_btn.visible = false
		end_btn.visible = false
		skip_event_btn.visible = false
		debt_row.visible = false
		return

	# Tile selected - show AP
	var major_letter := _action_letter(tile.major_action_type)
	var minor_letter := _action_letter(tile.minor_action_type)
	var major_text := "%s major %d/%d" % [major_letter, ActionController.major_ap_remaining, tile.major_action_points]
	var minor_text := "%s minor %d/%d" % [minor_letter, ActionController.minor_ap_remaining, tile.minor_action_points]
	var event_text := ""
	if ActionController.event_ap_remaining > 0:
		event_text = "    +Event %s: %d" % [_action_letter(ActionController.event_ap_type), ActionController.event_ap_remaining]
	ap_label.text = "%s    %s%s" % [major_text, minor_text, event_text]

	# Debt/TRP buttons: visible during ANY active action state (rule §6.0)
	var active = ac_state != ActionController.ActionState.IDLE and ActionController.current_side != Enums.Side.NONE
	debt_row.visible = active
	undo_btn.visible = active and ActionController.can_undo()
	if active:
		var p = GameManager.state.get_player(ActionController.current_side)
		debt_btn.disabled = p.available_debt() < 1
		debt_btn2.disabled = p.available_debt() < 2
		tp_btn.disabled = p.treaty_points < 1
		debt_btn.text = "+1 Debt (%d/%d used)" % [p.current_debt, p.debt_limit]
		debt_btn2.text = "+2 Debt"
		tp_btn.text = "+1 TRP (%d)" % p.treaty_points

	match ac_state:
		ActionController.ActionState.AWAITING_EVENT:
			step_label.text = "2. PLAY EVENT  (or skip)"
			step_label.modulate = Color("38bdf8")
			hint_label.text = "Click an Event card from your hand to play it, or press 'No Event' to spend AP directly"
			skip_event_btn.text = "No Event — Continue"
			skip_event_btn.visible = true
			major_btn.visible = false
			minor_btn.visible = false
			upgrade_btn.visible = false
			war_tile_btn.visible = false
			end_btn.visible = false

		ActionController.ActionState.SPENDING_MAJOR:
			step_label.text = "3. SPEND  %s  ACTION POINTS" % _action_full_name(tile.major_action_type)
			step_label.modulate = Color("22c55e")
			hint_label.text = _hint_for_action_type(tile.major_action_type)
			skip_event_btn.visible = false
			major_btn.visible = true
			major_btn.text = "Major " + major_letter
			major_btn.disabled = true  # already in major mode
			minor_btn.visible = ActionController.minor_ap_remaining > 0
			minor_btn.text = "Switch to Minor " + minor_letter
			minor_btn.disabled = false
			upgrade_btn.visible = tile.has_military_upgrade
			upgrade_btn.text = "Upgrade Tile"
			upgrade_btn.disabled = false
			war_tile_btn.visible = tile.major_action_type == Enums.ActionType.MILITARY
			war_tile_btn.text = "War Tiles..."
			war_tile_btn.disabled = ActionController.bonus_tiles_bought_this_ar >= 2
			end_btn.visible = true

		ActionController.ActionState.SPENDING_MINOR:
			step_label.text = "3. SPEND  %s  (MINOR)" % _action_full_name(tile.minor_action_type)
			step_label.modulate = Color("22c55e")
			hint_label.text = _hint_for_action_type(tile.minor_action_type) + "  (Minor: max 1 expense, no removing enemy flags unless conflict marker)"
			skip_event_btn.visible = false
			major_btn.visible = ActionController.major_ap_remaining > 0
			major_btn.text = "Switch to Major " + major_letter
			major_btn.disabled = false
			minor_btn.visible = true
			minor_btn.text = "Minor " + minor_letter
			minor_btn.disabled = true
			upgrade_btn.visible = false
			# Minor military can buy ONE bonus war tile
			war_tile_btn.visible = tile.minor_action_type == Enums.ActionType.MILITARY
			war_tile_btn.text = "War Tiles..."
			war_tile_btn.disabled = ActionController.minor_action_used_first_expense
			end_btn.visible = true

		ActionController.ActionState.UPGRADING:
			step_label.text = "MILITARY UPGRADE"
			step_label.modulate = Color("38bdf8")
			hint_label.text = "Replace one of your Basic War Tiles in the next war"
			major_btn.visible = ActionController.major_ap_remaining > 0
			minor_btn.visible = ActionController.minor_ap_remaining > 0
			upgrade_btn.visible = false
			war_tile_btn.visible = false
			end_btn.visible = true


func _action_letter(t: Enums.ActionType) -> String:
	match t:
		Enums.ActionType.ECONOMIC: return "E"
		Enums.ActionType.DIPLOMATIC: return "D"
		Enums.ActionType.MILITARY: return "M"
	return "?"


func _action_full_name(t: Enums.ActionType) -> String:
	match t:
		Enums.ActionType.ECONOMIC: return "ECONOMIC"
		Enums.ActionType.DIPLOMATIC: return "DIPLOMATIC"
		Enums.ActionType.MILITARY: return "MILITARY"
	return ""


func _hint_for_action_type(t: Enums.ActionType) -> String:
	match t:
		Enums.ActionType.ECONOMIC:
			return "Click Markets (circles) on the map to flag/unflag"
		Enums.ActionType.DIPLOMATIC:
			return "Click Political spaces (diamonds) to flag/unflag"
		Enums.ActionType.MILITARY:
			return "Click Forts/Naval (hexagons) — or use War Tiles button"
	return ""
