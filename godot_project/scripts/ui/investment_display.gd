extends Control

signal tile_selected(tile: InvestmentTile)
signal expanded_changed

var expanded = true
var toggle: Button
var _previous_tile: InvestmentTile

const InvTileScene := preload("res://scenes/ui/investment_tile_view.tscn")

@onready var grid: GridContainer = $Panel/Margin/VBox/Grid
@onready var title: Label = $Panel/Margin/VBox/Title


func _ready() -> void:
	# 선택이 끝나면 공용 타일을 접어 행동 공간을 돌려준다. 열고 닫아도
	# 모델의 타일 선택은 바뀌지 않으며 이미 고른 타일을 다시 고를 수 없다.
	var heading = HBoxContainer.new()
	var box = title.get_parent()
	box.remove_child(title)
	box.add_child(heading)
	box.move_child(heading,0)
	heading.add_child(title)
	title.add_theme_font_size_override("font_size",21)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle = Button.new()
	toggle.custom_minimum_size = Vector2(112,32)
	toggle.pressed.connect(func(): expanded = not expanded; refresh())
	heading.add_child(toggle)
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.action_round_started.connect(func(_s, _r): refresh())
	if has_node("/root/ActionController"):
		ActionController.action_state_changed.connect(func(_l): refresh())
	LocaleManager.locale_changed.connect(func(_l): refresh())
	refresh()


func refresh() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	if GameManager.state == null:
		return
	# Show whose turn it is
	var phasing := GameManager.state.phasing_player
	var is_idle = ActionController.state == ActionController.ActionState.IDLE if has_node("/root/ActionController") else true
	if is_idle:
		expanded = true
	elif _previous_tile != ActionController.current_tile:
		expanded = false
	_previous_tile = ActionController.current_tile
	grid.visible = expanded
	toggle.visible = not is_idle
	toggle.text = LocaleManager.tx("접기") if expanded else LocaleManager.tx("펼치기")
	if GameManager.state.current_turn_phase == Enums.TurnPhase.ACTION_PHASE and is_idle:
		title.text = LocaleManager.tf("inv_pick_tile", [LocaleManager.side(phasing)])
		title.modulate = Color("fbbf24")
	else:
		title.text = LocaleManager.tx("남은 투자 타일 · %d장") % GameManager.state.available_investment_tiles.size()
		title.modulate = Color(1, 1, 1)

	for tile in GameManager.state.available_investment_tiles:
		var view := InvTileScene.instantiate()
		view.custom_minimum_size = Vector2(180,120)
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(view)
		view.bind(tile)
		view.tile_clicked.connect(_on_tile_clicked)
	expanded_changed.emit()


func _on_tile_clicked(tile: InvestmentTile) -> void:
	tile_selected.emit(tile)


func _on_phase_changed(phase: Enums.TurnPhase) -> void:
	if phase in [Enums.TurnPhase.DEAL_CARDS_PHASE, Enums.TurnPhase.ACTION_PHASE, Enums.TurnPhase.RESET_PHASE]:
		refresh()
