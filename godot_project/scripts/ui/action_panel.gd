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
	ActionController.action_state_changed.connect(_on_state_changed)
	ActionController.ap_changed.connect(_refresh)
	ActionController.action_round_ended.connect(_on_round_ended)
	GameManager.action_round_started.connect(func(_s, _r): _refresh())
	GameManager.player_action_required.connect(func(_s, _a): _refresh())
	LocaleManager.locale_changed.connect(func(_l): _refresh())

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
	war_tile_upgrade_requested.emit()


func _on_debt_1_pressed() -> void:
	ActionController.take_debt_for_ap(1)
	_refresh()


func _on_debt_2_pressed() -> void:
	ActionController.take_debt_for_ap(2)
	_refresh()


func _on_tp_pressed() -> void:
	ActionController.spend_treaty_points_for_ap(1)
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
		step_label.text = LocaleManager.t("ap_step_select_tile")
		step_label.modulate = Color("fbbf24")
		hint_label.text = LocaleManager.t("ap_hint_select_tile")
		ap_label.text = ""
		major_btn.visible = false
		minor_btn.visible = false
		upgrade_btn.visible = false
		war_tile_btn.visible = false
		end_btn.visible = false
		skip_event_btn.visible = false
		debt_row.visible = false
		undo_btn.visible = false
		return

	# AP line
	var maj := LocaleManager.action_short(tile.major_action_type)
	var minr := LocaleManager.action_short(tile.minor_action_type)
	var event_extra := ""
	if ActionController.event_ap_remaining > 0:
		event_extra = LocaleManager.tf("ap_event_extra", [LocaleManager.action_short(ActionController.event_ap_type), ActionController.event_ap_remaining])
	ap_label.text = LocaleManager.tf("ap_ap_line", [
		maj, ActionController.major_ap_remaining, tile.major_action_points,
		minr, ActionController.minor_ap_remaining, tile.minor_action_points, event_extra])

	# Debt / TRP / Undo — visible during any active state (rule §6.0)
	var active = ac_state != ActionController.ActionState.IDLE and ActionController.current_side != Enums.Side.NONE
	debt_row.visible = active
	undo_btn.visible = active and ActionController.can_undo()
	undo_btn.text = LocaleManager.t("btn_undo")
	if active:
		var p = GameManager.state.get_player(ActionController.current_side)
		debt_btn.disabled = p.available_debt() < 1
		debt_btn2.disabled = p.available_debt() < 2
		tp_btn.disabled = p.treaty_points < 1
		debt_btn.text = LocaleManager.tf("btn_debt1", [p.current_debt, p.debt_limit])
		debt_btn2.text = LocaleManager.t("btn_debt2")
		tp_btn.text = LocaleManager.tf("btn_tp", [p.treaty_points])

	match ac_state:
		ActionController.ActionState.AWAITING_EVENT:
			step_label.text = LocaleManager.t("ap_step_play_event")
			step_label.modulate = Color("38bdf8")
			hint_label.text = LocaleManager.t("ap_hint_play_event")
			skip_event_btn.text = LocaleManager.t("btn_no_event")
			skip_event_btn.visible = true
			major_btn.visible = false
			minor_btn.visible = false
			upgrade_btn.visible = false
			war_tile_btn.visible = false
			end_btn.visible = false

		ActionController.ActionState.SPENDING_MAJOR:
			step_label.text = LocaleManager.tf("ap_step_spend_major", [LocaleManager.action(tile.major_action_type)])
			step_label.modulate = Color("22c55e")
			hint_label.text = _hint(tile.major_action_type)
			skip_event_btn.visible = false
			major_btn.visible = true
			major_btn.text = LocaleManager.tf("btn_major", [maj])
			major_btn.disabled = true
			minor_btn.visible = ActionController.minor_ap_remaining > 0
			minor_btn.text = LocaleManager.tf("btn_switch_minor", [minr])
			minor_btn.disabled = false
			upgrade_btn.visible = tile.has_military_upgrade
			upgrade_btn.text = LocaleManager.t("btn_upgrade_tile")
			upgrade_btn.disabled = false
			war_tile_btn.visible = tile.major_action_type == Enums.ActionType.MILITARY
			war_tile_btn.text = LocaleManager.t("btn_war_tiles")
			war_tile_btn.disabled = ActionController.bonus_tiles_bought_this_ar >= 2
			end_btn.visible = true
			end_btn.text = LocaleManager.t("btn_end_round")

		ActionController.ActionState.SPENDING_MINOR:
			step_label.text = LocaleManager.tf("ap_step_spend_minor", [LocaleManager.action(tile.minor_action_type)])
			step_label.modulate = Color("22c55e")
			hint_label.text = _hint(tile.minor_action_type) + LocaleManager.t("ap_hint_minor_suffix")
			skip_event_btn.visible = false
			major_btn.visible = ActionController.major_ap_remaining > 0
			major_btn.text = LocaleManager.tf("btn_switch_major", [maj])
			major_btn.disabled = false
			minor_btn.visible = true
			minor_btn.text = LocaleManager.tf("btn_minor", [minr])
			minor_btn.disabled = true
			upgrade_btn.visible = false
			war_tile_btn.visible = tile.minor_action_type == Enums.ActionType.MILITARY
			war_tile_btn.text = LocaleManager.t("btn_war_tiles")
			war_tile_btn.disabled = ActionController.minor_action_used_first_expense
			end_btn.visible = true
			end_btn.text = LocaleManager.t("btn_end_round")

		ActionController.ActionState.UPGRADING:
			step_label.text = LocaleManager.t("ap_step_upgrade")
			step_label.modulate = Color("38bdf8")
			hint_label.text = LocaleManager.t("ap_hint_upgrade")
			major_btn.visible = ActionController.major_ap_remaining > 0
			minor_btn.visible = ActionController.minor_ap_remaining > 0
			upgrade_btn.visible = false
			war_tile_btn.visible = false
			end_btn.visible = true
			end_btn.text = LocaleManager.t("btn_end_round")


func _hint(t: Enums.ActionType) -> String:
	match t:
		Enums.ActionType.ECONOMIC: return LocaleManager.t("hint_economic")
		Enums.ActionType.DIPLOMATIC: return LocaleManager.t("hint_diplomatic")
		Enums.ActionType.MILITARY: return LocaleManager.t("hint_military")
	return ""
