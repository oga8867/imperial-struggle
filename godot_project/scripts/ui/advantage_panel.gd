extends Control

@onready var br_box: VBoxContainer = $Panel/Margin/HBox/BritainBox
@onready var fr_box: VBoxContainer = $Panel/Margin/HBox/FranceBox
@onready var br_title: Label = $Panel/Margin/HBox/BritainBox/Title
@onready var fr_title: Label = $Panel/Margin/HBox/FranceBox/Title


func _ready() -> void:
	# 여러 이점을 얻어도 손패 영역을 덮지 않도록 패널 내부에서 스크롤한다.
	var row = br_box.get_parent()
	var margin = row.get_parent()
	margin.remove_child(row)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	scroll.add_child(row)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br_title.add_theme_font_size_override("font_size",16)
	fr_title.add_theme_font_size_override("font_size",16)
	br_title.add_theme_color_override("font_color",Color("eb8576"))
	fr_title.add_theme_color_override("font_color",Color("80b9ed"))
	br_box.custom_minimum_size.x=0
	fr_box.custom_minimum_size.x=0
	GameManager.phase_changed.connect(func(_p): refresh())
	if has_node("/root/ActionController"):
		ActionController.action_state_changed.connect(func(_l): refresh())
	LocaleManager.locale_changed.connect(func(_l): refresh())
	refresh()


func refresh() -> void:
	if br_title:
		br_title.text = LocaleManager.t("adv_britain")
	if fr_title:
		fr_title.text = LocaleManager.t("adv_france")
	for box in [br_box, fr_box]:
		for child in box.get_children():
			if child.name != "Title":
				box.remove_child(child)
				child.queue_free()

	if not has_node("/root/AdvantageManager"):
		return

	for adv_id in AdvantageManager.advantages:
		var adv: Advantage = AdvantageManager.advantages[adv_id]
		if adv.controlled_by == Enums.Side.NONE:
			continue
		var btn := _make_advantage_button(adv)
		if adv.controlled_by == Enums.Side.BRITAIN:
			br_box.add_child(btn)
		else:
			fr_box.add_child(btn)


func _make_advantage_button(adv: Advantage) -> Button:
	var btn := Button.new()
	btn.text = LocaleManager.local_name(adv.name,adv.name_ko)
	if adv.is_exhausted:
		btn.text += LocaleManager.t("adv_used_suffix")
		btn.disabled = true
	elif AIController.is_ai_turn() or not AdvantageManager.can_activate(adv.id):
		btn.disabled = true  # Not your turn or other restriction
	btn.add_theme_font_size_override("font_size",14)
	btn.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	btn.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 28)
	btn.tooltip_text = LocaleManager.tf("adv_region_tooltip", [LocaleManager.region(adv.region)])
	btn.pressed.connect(_on_advantage_pressed.bind(adv))
	return btn


func _on_advantage_pressed(adv: Advantage) -> void:
	if not AdvantageManager.can_activate(adv.id):
		return
	if AdvantageManager.activate(adv.id):
		if has_node("/root/GameLog"):
			GameLog.log_entry(adv.controlled_by, "advantage", "activated %s" % adv.name)
	refresh()
