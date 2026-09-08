extends Control

var box: VBoxContainer
var title: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade=ColorRect.new()
	shade.color=Color(0.02,0.04,0.05,0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel=PanelContainer.new()
	panel.position=Vector2(410,170)
	panel.size=Vector2(1100,710)
	add_child(panel)
	var margin=MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	panel.add_child(margin)
	var body=VBoxContainer.new()
	body.add_theme_constant_override("separation",16)
	margin.add_child(body)
	title=Label.new()
	title.add_theme_font_size_override("font_size",24)
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(title)
	var scroll=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	box=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",10)
	scroll.add_child(box)
	EventEffects.pending_choices_changed.connect(func(_c): refresh())
	EventEffects.effects_resolved.connect(refresh)
	LocaleManager.locale_changed.connect(func(_l): refresh())
	hide()

func refresh() -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var options=EventEffects.choice_options()
	if options.is_empty():
		hide()
		return
	var choice=EventEffects.pending_choices[0]
	var side=choice.params.get("chooser",choice.params.side)
	if AIController.enabled and AIController.ai_side==side:
		hide()
		return
	var card=EventEffects.current_card
	title.text=(card.disp_title()+" · " if card else LocaleManager.tx("효과 선택 · "))+LocaleManager.side(side)
	if choice.type=="place_bonus": title.text+=LocaleManager.tx("\n뽑은 타일 전력 %+d") % choice.params.tile.strength
	for option in options:
		var button=Button.new()
		button.text=LocaleManager.message(option.label)
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y=54
		button.pressed.connect(func(): EventEffects.resolve_option(option.id))
		box.add_child(button)
	show()
