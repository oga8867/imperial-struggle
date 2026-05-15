extends Control

@onready var bg: ColorRect = $BG
@onready var card_image: TextureRect = $Center/CardImage
@onready var title_label: Label = $Center/Info/Title
@onready var desc_label: RichTextLabel = $Center/Info/Description
@onready var close_btn: Button = $Center/Info/CloseBtn


func _ready() -> void:
	visible = false
	bg.gui_input.connect(_on_bg_input)
	close_btn.pressed.connect(_on_close)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_card(card) -> void:
	if card == null:
		return
	visible = true
	if card is EventCard:
		_show_event(card)
	elif card is MinistryCard:
		_show_ministry(card)


func _show_event(card: EventCard) -> void:
	var display_title := card.title
	if LocaleManager.current_locale == "ko" and card.title_ko != "":
		display_title = "%s  /  %s" % [card.title_ko, card.title]
	title_label.text = "#%d  %s" % [card.id, display_title]
	if card.image != "" and ResourceLoader.exists(card.image):
		card_image.texture = load(card.image)
	else:
		card_image.texture = null
	var lines := []
	if card.bonus_condition != "":
		lines.append("[b]Bonus:[/b] " + card.bonus_condition)
	if card.both_base != "":
		lines.append("[b]Effect:[/b] " + card.both_base)
	if card.both_bonus != "":
		lines.append("[b]Bonus Effect:[/b] " + card.both_bonus)
	if card.british_base != "":
		lines.append("[b][color=#c8423a]British:[/color][/b] " + card.british_base)
	if card.british_bonus != "":
		lines.append("[b][color=#c8423a]British Bonus:[/color][/b] " + card.british_bonus)
	if card.french_base != "":
		lines.append("[b][color=#3a5fb0]French:[/color][/b] " + card.french_base)
	if card.french_bonus != "":
		lines.append("[b][color=#3a5fb0]French Bonus:[/color][/b] " + card.french_bonus)
	if card.special_note != "":
		lines.append("[i]" + card.special_note + "[/i]")
	desc_label.text = "\n\n".join(lines)


func _show_ministry(card: MinistryCard) -> void:
	var display_title := card.title
	if LocaleManager.current_locale == "ko" and card.title_ko != "":
		display_title = "%s  /  %s" % [card.title_ko, card.title]
	title_label.text = "%s  %s" % [card.id, display_title]
	if card.image != "" and ResourceLoader.exists(card.image):
		card_image.texture = load(card.image)
	else:
		card_image.texture = null
	var kw := ", ".join(card.keywords) if card.keywords.size() > 0 else "—"
	desc_label.text = "[b]Keywords:[/b] %s\n\n%s" % [kw, card.abilities]


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_close()


func _on_close() -> void:
	visible = false
