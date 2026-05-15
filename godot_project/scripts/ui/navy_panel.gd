extends Control

# Navy Box display: shows squadron tokens visually + counts.

signal view_war_tiles_requested(side: Enums.Side)

@onready var br_label: Label = $Panel/VBox/BRRow/Count
@onready var fr_label: Label = $Panel/VBox/FRRow/Count
@onready var br_btn: Button = $Panel/VBox/BRRow/ViewBtn
@onready var fr_btn: Button = $Panel/VBox/FRRow/ViewBtn
@onready var br_tokens: Control = $Panel/VBox/BRRow/Tokens
@onready var fr_tokens: Control = $Panel/VBox/FRRow/Tokens

var _tex_squadron_br: Texture2D
var _tex_squadron_fr: Texture2D


func _ready() -> void:
	_tex_squadron_br = _try_load("res://assets/tokens/Squadron_BR.png")
	_tex_squadron_fr = _try_load("res://assets/tokens/Squadron_FR.png")
	GameManager.phase_changed.connect(func(_p): refresh())
	GameManager.action_round_started.connect(func(_s, _r): refresh())
	if has_node("/root/ActionController"):
		ActionController.ap_changed.connect(refresh)
	br_btn.pressed.connect(func(): view_war_tiles_requested.emit(Enums.Side.BRITAIN))
	fr_btn.pressed.connect(func(): view_war_tiles_requested.emit(Enums.Side.FRANCE))
	# Custom drawing on token containers
	br_tokens.draw.connect(_draw_br_tokens)
	fr_tokens.draw.connect(_draw_fr_tokens)
	refresh()


static func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func refresh() -> void:
	if GameManager.state == null:
		return
	br_label.text = "Navy:%d  Map:%d  Pool:%d" % [
		GameManager.state.britain.squadrons_in_navy_box,
		GameManager.state.britain.squadrons_on_map,
		8 - GameManager.state.britain.total_squadrons()]
	fr_label.text = "Navy:%d  Map:%d  Pool:%d" % [
		GameManager.state.france.squadrons_in_navy_box,
		GameManager.state.france.squadrons_on_map,
		8 - GameManager.state.france.total_squadrons()]
	br_tokens.queue_redraw()
	fr_tokens.queue_redraw()


func _draw_br_tokens() -> void:
	_draw_squadron_row(br_tokens, _tex_squadron_br,
		GameManager.state.britain.squadrons_in_navy_box if GameManager.state else 0)


func _draw_fr_tokens() -> void:
	_draw_squadron_row(fr_tokens, _tex_squadron_fr,
		GameManager.state.france.squadrons_in_navy_box if GameManager.state else 0)


func _draw_squadron_row(container: Control, tex: Texture2D, count: int) -> void:
	if tex == null or count == 0:
		return
	var token_size := 22.0
	var spacing := 2.0
	for i in range(min(count, 8)):
		var x := float(i) * (token_size + spacing)
		container.draw_texture_rect(tex, Rect2(Vector2(x, 0), Vector2(token_size, token_size)), false)
