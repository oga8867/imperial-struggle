extends Control

signal clicked(card)

@onready var texture: TextureRect = $Texture
@onready var highlight: Panel = $HighlightBorder
@onready var fallback: Label = $FallbackLabel

var bound_card = null
var image_path: String = ""
var is_selected: bool = false


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if is_selected:
		draw_rect(rect.grow(6), Color("fbbf24", 0.6), false, 6)
		draw_rect(rect, Color("fbbf24"), false, 4)
	elif _hover:
		draw_rect(rect, Color("ffffff", 0.7), false, 2)


var _hover: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func bind_event(card: EventCard) -> void:
	bound_card = card
	if card:
		_load_image(card.get("image") if card.get("image") else "")
		_setup_fallback("#%d %s" % [card.id, card.title])


func bind_ministry(card: MinistryCard) -> void:
	bound_card = card
	if card:
		_load_image(card.get("image") if card.get("image") else "")
		_setup_fallback("%s\n%s" % [card.id, card.title])


func bind_image(path: String, label_text: String = "") -> void:
	_load_image(path)
	_setup_fallback(label_text)


func _load_image(path: String) -> void:
	image_path = path
	if path == "" or not ResourceLoader.exists(path):
		texture.texture = null
		fallback.visible = true
		return
	var tex := load(path)
	if tex is Texture2D:
		texture.texture = tex
		fallback.visible = false
	else:
		fallback.visible = true


func _setup_fallback(text: String) -> void:
	fallback.text = text


func _on_mouse_entered() -> void:
	_hover = true
	z_index = 10
	queue_redraw()


func _on_mouse_exited() -> void:
	_hover = false
	z_index = 0
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(bound_card)
