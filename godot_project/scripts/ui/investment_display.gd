extends Control

signal tile_selected(tile: InvestmentTile)

const InvTileScene := preload("res://scenes/ui/investment_tile_view.tscn")

@onready var grid: GridContainer = $Panel/Margin/VBox/Grid
@onready var title: Label = $Panel/Margin/VBox/Title


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.action_round_started.connect(func(_s, _r): refresh())
	if has_node("/root/ActionController"):
		ActionController.action_state_changed.connect(func(_l): refresh())
	refresh()


func refresh() -> void:
	for child in grid.get_children():
		child.queue_free()
	if GameManager.state == null:
		return
	# Show whose turn it is
	var phasing := GameManager.state.phasing_player
	var is_idle = ActionController.state == ActionController.ActionState.IDLE if has_node("/root/ActionController") else true
	if GameManager.state.current_turn_phase == Enums.TurnPhase.ACTION_PHASE and is_idle:
		var name := "BRITAIN" if phasing == Enums.Side.BRITAIN else "FRANCE"
		title.text = "%s — Pick a Tile" % name
		title.modulate = Color("fbbf24")
	else:
		title.text = "Investment Tiles"
		title.modulate = Color(1, 1, 1)

	for tile in GameManager.state.available_investment_tiles:
		var view := InvTileScene.instantiate()
		grid.add_child(view)
		view.bind(tile)
		view.tile_clicked.connect(_on_tile_clicked)


func _on_tile_clicked(tile: InvestmentTile) -> void:
	tile_selected.emit(tile)


func _on_phase_changed(phase: Enums.TurnPhase) -> void:
	if phase in [Enums.TurnPhase.DEAL_CARDS_PHASE, Enums.TurnPhase.ACTION_PHASE, Enums.TurnPhase.RESET_PHASE]:
		refresh()
