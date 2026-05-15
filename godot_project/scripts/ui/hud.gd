extends Control

@onready var vp_value: Label = $TopBar/Margin/HBox/CenterPanel/VBox/VPRow/VPValue
@onready var turn_label: Label = $TopBar/Margin/HBox/CenterPanel/VBox/InfoRow/TurnLabel
@onready var era_label: Label = $TopBar/Margin/HBox/CenterPanel/VBox/InfoRow/EraLabel
@onready var phase_label: Label = $TopBar/Margin/HBox/CenterPanel/VBox/InfoRow/PhaseLabel
@onready var demand_label: Label = $TopBar/Margin/HBox/CenterPanel/VBox/DemandRow/DemandLabel

@onready var br_panel: Panel = $TopBar/Margin/HBox/BritainPanel
@onready var br_debt: Label = $TopBar/Margin/HBox/BritainPanel/VBox/DebtLabel
@onready var br_tp: Label = $TopBar/Margin/HBox/BritainPanel/VBox/TPLabel

@onready var fr_panel: Panel = $TopBar/Margin/HBox/FrancePanel
@onready var fr_debt: Label = $TopBar/Margin/HBox/FrancePanel/VBox/DebtLabel
@onready var fr_tp: Label = $TopBar/Margin/HBox/FrancePanel/VBox/TPLabel

@onready var active_indicator: Panel = $ActiveTurnIndicator
@onready var active_label: Label = $ActiveTurnIndicator/Label

const COLOR_BR := Color(0.85, 0.3, 0.3, 1)
const COLOR_FR := Color(0.3, 0.5, 0.85, 1)
const COLOR_NEUTRAL := Color(0.3, 0.32, 0.4, 0.6)


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.vp_changed.connect(_on_vp_changed)
	GameManager.action_round_started.connect(_on_ar_started)
	GameManager.player_action_required.connect(_on_action_required)
	if has_node("/root/ActionController"):
		ActionController.ap_changed.connect(refresh)
		ActionController.action_state_changed.connect(func(_l): refresh())
	if GameManager.state and GameManager.state.britain:
		refresh()


func refresh() -> void:
	var s: GameState = GameManager.state
	if s == null:
		return

	vp_value.text = str(s.vp)
	turn_label.text = "Turn %d/6" % s.current_turn
	era_label.text = _era_name(s.current_era)
	phase_label.text = _phase_name(s.current_turn_phase)

	br_debt.text = "Debt: %d/%d  Avail: %d" % [s.britain.current_debt, s.britain.debt_limit, s.britain.available_debt()]
	br_tp.text = "Treaty: %d  Squad: %d (%d in Navy)  Hand: %d" % [
		s.britain.treaty_points, s.britain.total_squadrons(),
		s.britain.squadrons_in_navy_box, s.britain.hand.size()]

	fr_debt.text = "Debt: %d/%d  Avail: %d" % [s.france.current_debt, s.france.debt_limit, s.france.available_debt()]
	fr_tp.text = "Treaty: %d  Squad: %d (%d in Navy)  Hand: %d" % [
		s.france.treaty_points, s.france.total_squadrons(),
		s.france.squadrons_in_navy_box, s.france.hand.size()]

	var d_names: Array[String] = []
	for c in s.current_global_demand:
		d_names.append(_commodity_name(c))
	# Regional awards (per-region VP value this turn)
	var awards_str := ""
	if has_node("/root/AwardManager"):
		var rg_short := ["Eu", "NA", "Ca", "In"]
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
			parts.append("%s:%s" % [rg_short[i], vp_text])
		awards_str = "  Awards: " + " · ".join(parts)
	var demand_str := "Global Demand: " + ", ".join(d_names) if d_names.size() > 0 else "Global Demand: -"
	demand_label.text = demand_str + awards_str

	_refresh_active_indicator()


func _refresh_active_indicator() -> void:
	var s := GameManager.state
	if s == null:
		return
	# Highlight the active panel
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
	refresh()
	active_label.text = "%s — Action Round %d / 4" % [_side_name(side), round_num]


func _on_action_required(side: Enums.Side, action: String) -> void:
	var prompt := ""
	match action:
		"select_investment_tile":
			prompt = "%s: Select Investment Tile" % _side_name(side)
		"play_actions":
			prompt = "%s: Play event or spend AP" % _side_name(side)
		"select_ministry":
			prompt = "%s: Choose 2 Ministry cards" % _side_name(side)
		"choose_first_player":
			prompt = "%s holds Initiative — choose first player" % _side_name(side)
	if prompt != "":
		active_label.text = prompt


func _side_name(s: Enums.Side) -> String:
	match s:
		Enums.Side.BRITAIN: return "BRITAIN"
		Enums.Side.FRANCE: return "FRANCE"
	return ""


func _era_name(era: Enums.Era) -> String:
	match era:
		Enums.Era.SUCCESSION: return "Succession Era"
		Enums.Era.EMPIRE: return "Empire Era"
		Enums.Era.REVOLUTION: return "Revolution Era"
	return ""


func _phase_name(phase: Enums.TurnPhase) -> String:
	match phase:
		Enums.TurnPhase.DECK_PHASE: return "Deck"
		Enums.TurnPhase.AWARD_PHASE: return "Award"
		Enums.TurnPhase.GLOBAL_DEMAND_PHASE: return "Global Demand"
		Enums.TurnPhase.RESET_PHASE: return "Reset"
		Enums.TurnPhase.DEAL_CARDS_PHASE: return "Deal Cards"
		Enums.TurnPhase.MINISTRY_PHASE: return "Ministry"
		Enums.TurnPhase.INITIATIVE_PHASE: return "Initiative"
		Enums.TurnPhase.ACTION_PHASE: return "Action"
		Enums.TurnPhase.SCORING_PHASE: return "Scoring"
		Enums.TurnPhase.VICTORY_CHECK: return "Victory Check"
		Enums.TurnPhase.FINAL_SCORING: return "Final Scoring"
	return ""


func _commodity_name(c: Enums.Commodity) -> String:
	match c:
		Enums.Commodity.FISH: return "Fish"
		Enums.Commodity.FUR: return "Fur"
		Enums.Commodity.SPICE: return "Spice"
		Enums.Commodity.SUGAR: return "Sugar"
		Enums.Commodity.TOBACCO: return "Tobacco"
		Enums.Commodity.COTTON: return "Cotton"
	return ""
