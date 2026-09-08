extends Control

@onready var vp_value: Label = $TopBar/Margin/HBox/CenterPanel/VBox/VPRow/VPValue
@onready var vp_caption: Label = $TopBar/Margin/HBox/CenterPanel/VBox/VPRow/VPLabel if has_node("TopBar/Margin/HBox/CenterPanel/VBox/VPRow/VPLabel") else null
@onready var turn_label: Label = $TopBar/Margin/HBox/CenterPanel/VBox/InfoRow/TurnLabel
@onready var era_label: Label = $TopBar/Margin/HBox/CenterPanel/VBox/InfoRow/EraLabel
@onready var phase_label: Label = $TopBar/Margin/HBox/CenterPanel/VBox/InfoRow/PhaseLabel
@onready var demand_label: Label = $TopBar/Margin/HBox/CenterPanel/VBox/DemandRow/DemandLabel

@onready var br_panel: Panel = $TopBar/Margin/HBox/BritainPanel
@onready var br_title: Label = $TopBar/Margin/HBox/BritainPanel/VBox/Title if has_node("TopBar/Margin/HBox/BritainPanel/VBox/Title") else null
@onready var br_debt: Label = $TopBar/Margin/HBox/BritainPanel/VBox/DebtLabel
@onready var br_tp: Label = $TopBar/Margin/HBox/BritainPanel/VBox/TPLabel

@onready var fr_panel: Panel = $TopBar/Margin/HBox/FrancePanel
@onready var fr_title: Label = $TopBar/Margin/HBox/FrancePanel/VBox/Title if has_node("TopBar/Margin/HBox/FrancePanel/VBox/Title") else null
@onready var fr_debt: Label = $TopBar/Margin/HBox/FrancePanel/VBox/DebtLabel
@onready var fr_tp: Label = $TopBar/Margin/HBox/FrancePanel/VBox/TPLabel

@onready var active_indicator: Panel = $ActiveTurnIndicator
@onready var active_label: Label = $ActiveTurnIndicator/Label

const COLOR_BR := Color(0.85, 0.3, 0.3, 1)
const COLOR_FR := Color(0.3, 0.5, 0.85, 1)
const COLOR_NEUTRAL := Color(0.3, 0.32, 0.4, 0.6)

var _last_prompt := ""


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.vp_changed.connect(_on_vp_changed)
	GameManager.action_round_started.connect(_on_ar_started)
	GameManager.player_action_required.connect(_on_action_required)
	if has_node("/root/ActionController"):
		ActionController.ap_changed.connect(refresh)
		ActionController.action_state_changed.connect(func(_l): refresh())
	LocaleManager.locale_changed.connect(func(_l): refresh())
	if GameManager.state and GameManager.state.britain:
		refresh()


func refresh() -> void:
	var s: GameState = GameManager.state
	if s == null:
		return

	if br_title: br_title.text = LocaleManager.side(Enums.Side.BRITAIN)
	if fr_title: fr_title.text = LocaleManager.side(Enums.Side.FRANCE)
	if vp_caption: vp_caption.text = LocaleManager.t("hud_vp")

	vp_value.text = str(s.vp)
	turn_label.text = LocaleManager.tf("hud_turn", [s.current_turn])
	era_label.text = LocaleManager.era(s.current_era)
	phase_label.text = LocaleManager.phase(s.current_turn_phase)

	br_debt.text = LocaleManager.tf("hud_debt", [s.britain.current_debt, s.britain.debt_limit, s.britain.available_debt()])
	br_tp.text = LocaleManager.tf("hud_player_line", [
		s.britain.treaty_points, s.britain.total_squadrons(),
		s.britain.squadrons_in_navy_box, s.britain.hand.size()])

	fr_debt.text = LocaleManager.tf("hud_debt", [s.france.current_debt, s.france.debt_limit, s.france.available_debt()])
	fr_tp.text = LocaleManager.tf("hud_player_line", [
		s.france.treaty_points, s.france.total_squadrons(),
		s.france.squadrons_in_navy_box, s.france.hand.size()])

	var d_names: Array[String] = []
	for c in s.current_global_demand:
		d_names.append(LocaleManager.commodity(c))
	var demand_str := LocaleManager.tf("hud_demand", [", ".join(d_names)]) if d_names.size() > 0 else LocaleManager.t("hud_demand_none")

	var awards_str := ""
	if has_node("/root/AwardManager"):
		var rg_enums := [Enums.Region.EUROPE, Enums.Region.NORTH_AMERICA, Enums.Region.CARIBBEAN, Enums.Region.INDIA]
		var parts: Array[String] = []
		for i in range(4):
			var aw = AwardManager.get_award_for_region(rg_enums[i])
			var vp_text := "-"
			if not aw.is_empty():
				var vp_v = aw.get("vp", 0)
				var tp_v = aw.get("tp", 0)
				var margin = aw.get("margin_required", 1)
				vp_text = "%dVP" % vp_v
				if tp_v > 0: vp_text += "+%dTP" % tp_v
				if margin > 1: vp_text += "(m%d)" % margin
			parts.append("%s:%s" % [LocaleManager.region_short(rg_enums[i]), vp_text])
		awards_str = "   " + LocaleManager.tf("hud_awards", [" · ".join(parts)])
	demand_label.text = demand_str + awards_str

	_refresh_active_indicator()
	_refresh_prompt()


func _refresh_active_indicator() -> void:
	var s := GameManager.state
	if s == null:
		return
	var br_active := false
	var fr_active := false
	if s.current_turn_phase == Enums.TurnPhase.ACTION_PHASE:
		br_active = (s.phasing_player == Enums.Side.BRITAIN)
		fr_active = (s.phasing_player == Enums.Side.FRANCE)
	_set_panel_active(br_panel, br_active, COLOR_BR)
	_set_panel_active(fr_panel, fr_active, COLOR_FR)


func _set_panel_active(p: Panel, active: bool, accent: Color) -> void:
	var sb := StyleBoxFlat.new()
	if active:
		sb.bg_color = accent.darkened(0.7)
		sb.border_color = accent
		sb.set_border_width_all(3)
	else:
		sb.bg_color = COLOR_NEUTRAL
		sb.border_color = Color(0.4, 0.42, 0.5, 0.4)
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)


func _on_phase_changed(_phase: Enums.TurnPhase) -> void:
	refresh()


func _on_vp_changed(_new_vp: int) -> void:
	refresh()


func _on_ar_started(side: Enums.Side, round_num: int) -> void:
	_last_prompt = LocaleManager.tf("hud_action_round", [LocaleManager.side(side), round_num])
	refresh()


func _on_action_required(side: Enums.Side, action: String) -> void:
	var key := ""
	match action:
		"select_investment_tile": key = "prompt_select_tile"
		"play_actions": key = "prompt_play_actions"
		"select_ministry": key = "prompt_select_ministry"
		"choose_first_player": key = "prompt_choose_first"
	if key != "":
		_last_prompt = LocaleManager.tf(key, [LocaleManager.side(side)])
		_refresh_prompt()


func _refresh_prompt() -> void:
	if _last_prompt != "" and active_label:
		active_label.text = _last_prompt
