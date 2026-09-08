extends Control

# Compact ministry hand: shows current player's 2 ministry cards small,
# with card-back image when hidden, and small Activate button.

const CardViewScene := preload("res://scenes/ui/card_view.tscn")

@onready var hbox: HBoxContainer = $Panel/Margin/VBox/HBox
@onready var title: Label = $Panel/Margin/VBox/Title


func _ready() -> void:
	GameManager.phase_changed.connect(func(_p): refresh())
	GameManager.action_round_started.connect(func(_s, _r): refresh())
	if has_node("/root/ActionController"):
		ActionController.action_state_changed.connect(func(_l): refresh())
	LocaleManager.locale_changed.connect(func(_l): refresh())
	refresh()


func refresh() -> void:
	for child in hbox.get_children():
		child.queue_free()
	if GameManager.state == null:
		return
	var side := GameManager.state.phasing_player
	if side == Enums.Side.NONE:
		title.text = LocaleManager.t("ministry_cards_generic")
		return
	var player := GameManager.state.get_player(side)
	title.text = LocaleManager.tf("ministry_your_cards", [LocaleManager.side(side)])

	for card in player.ministry_cards:
		hbox.add_child(_make_card_entry(card, side))


func _make_card_entry(card: MinistryCard, side: Enums.Side) -> Control:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(96, 0)
	vbox.add_theme_constant_override("separation", 2)

	# Card image: front if revealed, back image if hidden
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(96, 134)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if card.is_revealed:
		if card.image != "" and ResourceLoader.exists(card.image):
			img.texture = load(card.image)
	else:
		var back_path := _back_path(side)
		if ResourceLoader.exists(back_path):
			img.texture = load(back_path)
	img.mouse_filter = Control.MOUSE_FILTER_PASS
	img.gui_input.connect(_on_card_input.bind(card))
	vbox.add_child(img)

	# Status text — tiny
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 9)
	if card.is_revealed:
		var kw := ", ".join(card.keywords) if card.keywords.size() > 0 else "-"
		status.text = kw
		status.add_theme_color_override("font_color", Color(0.5, 0.85, 0.55))
	else:
		status.text = LocaleManager.t("ministry_hidden")
		status.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status)

	# Activate button — only enabled when allowed
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 22)
	btn.add_theme_font_size_override("font_size", 11)
	if card.is_ability_exhausted(0):
		btn.text = LocaleManager.t("ministry_used")
		btn.disabled = true
	else:
		btn.text = LocaleManager.t("ministry_activate")
		btn.disabled = not _can_activate(card, side)
	btn.pressed.connect(func(): _activate(card, side))
	vbox.add_child(btn)
	return vbox


func _back_path(side: Enums.Side) -> String:
	if side == Enums.Side.BRITAIN:
		return "res://assets/cards/Card-BR Ministry Back.png"
	return "res://assets/cards/Card-FR MInistry Back.png"


func _on_card_input(event: InputEvent, card: MinistryCard) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# Reveal and show modal
			card.reveal()
			var modals = get_tree().get_nodes_in_group("card_modal")
			var modal: Node = null
			if modals.size() > 0:
				modal = modals[0]
			else:
				# Fallback path
				var root = get_tree().get_root()
				modal = root.find_child("CardModal", true, false)
			if modal and modal.has_method("show_card"):
				modal.show_card(card)
			refresh()


func _can_activate(card: MinistryCard, side: Enums.Side) -> bool:
	if GameManager.state.phasing_player != side:
		return false
	if has_node("/root/ActionController"):
		var s = ActionController.state
		if s == ActionController.ActionState.IDLE:
			return false
	if card.is_ability_exhausted(0):
		return false
	return true


func _activate(card: MinistryCard, side: Enums.Side) -> void:
	if not _can_activate(card, side):
		return
	if has_node("/root/MinistryEffects"):
		MinistryEffects.activate_manual(card, side)
	if has_node("/root/GameLog"):
		GameLog.log_entry(side, "ministry", "activated %s" % card.title)
	refresh()
