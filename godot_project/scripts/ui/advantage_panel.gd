extends Control

@onready var br_box: VBoxContainer = $Panel/Margin/HBox/BritainBox
@onready var fr_box: VBoxContainer = $Panel/Margin/HBox/FranceBox


func _ready() -> void:
	GameManager.phase_changed.connect(func(_p): refresh())
	if has_node("/root/ActionController"):
		ActionController.action_state_changed.connect(func(_l): refresh())
	refresh()


func refresh() -> void:
	for box in [br_box, fr_box]:
		for child in box.get_children():
			if child.name != "Title":
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
	btn.text = adv.name
	if adv.is_exhausted:
		btn.text += " (used)"
		btn.disabled = true
	elif not AdvantageManager.can_activate(adv.id):
		btn.disabled = true  # Not your turn or other restriction
	btn.custom_minimum_size = Vector2(0, 28)
	btn.tooltip_text = "Region: %s" % _region_name(adv.region)
	btn.pressed.connect(_on_advantage_pressed.bind(adv))
	return btn


func _on_advantage_pressed(adv: Advantage) -> void:
	if not AdvantageManager.can_activate(adv.id):
		return
	if AdvantageManager.activate(adv.id):
		if has_node("/root/GameLog"):
			GameLog.log_entry(adv.controlled_by, "advantage", "activated %s" % adv.name)
	refresh()


func _region_name(r: Enums.Region) -> String:
	match r:
		Enums.Region.EUROPE: return "Europe"
		Enums.Region.NORTH_AMERICA: return "N. America"
		Enums.Region.CARIBBEAN: return "Caribbean"
		Enums.Region.INDIA: return "India"
	return ""
