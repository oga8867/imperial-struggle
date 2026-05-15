extends Control

# Modal for purchasing Bonus War Tiles or doing Military Upgrade.

signal closed

@onready var title_label: Label = $Panel/VBox/Title
@onready var theater_box: VBoxContainer = $Panel/VBox/Scroll/Theaters
@onready var ap_label: Label = $Panel/VBox/APLabel
@onready var close_btn: Button = $Panel/VBox/CloseBtn
@onready var upgrade_btn: Button = $Panel/VBox/UpgradeBtn

var current_side: Enums.Side = Enums.Side.NONE


func _ready() -> void:
	visible = false
	close_btn.pressed.connect(_on_close)
	upgrade_btn.pressed.connect(_on_upgrade)


func show_for(side: Enums.Side) -> void:
	current_side = side
	visible = true
	_refresh()


func _refresh() -> void:
	for child in theater_box.get_children():
		child.queue_free()

	var war_id := WarManager.get_upcoming_war_id()
	if war_id == "":
		title_label.text = "No upcoming war"
		return

	var war: WarData = WarManager.wars[war_id]
	title_label.text = "%s — Buy Bonus War Tiles" % war.name

	for theater in war.theaters:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0, 80)
		var hbox := HBoxContainer.new()
		hbox.position = Vector2(12, 8)
		hbox.size = Vector2(640, 64)
		var name_lbl := Label.new()
		name_lbl.custom_minimum_size = Vector2(220, 0)
		name_lbl.text = theater.name
		hbox.add_child(name_lbl)

		var theater_dict: Dictionary = WarManager.bonus_war_tiles_in_theater.get(theater.id, {})
		var bonus_arr: Array = theater_dict.get(current_side, [])
		var bonus_count: int = bonus_arr.size()
		var info_lbl := Label.new()
		info_lbl.custom_minimum_size = Vector2(160, 0)
		info_lbl.text = "Bonus: %d/2" % bonus_count
		hbox.add_child(info_lbl)

		var buy_btn := Button.new()
		buy_btn.text = "Buy (-2 MP)"
		buy_btn.disabled = bonus_count >= 2 or not _can_afford(2)
		buy_btn.pressed.connect(_on_buy.bind(theater.id))
		hbox.add_child(buy_btn)

		panel.add_child(hbox)
		theater_box.add_child(panel)

	_refresh_ap()


func _refresh_ap() -> void:
	if ActionController.current_tile == null:
		ap_label.text = "No active action"
		return
	var ap := ActionController.ap_for_current()
	ap_label.text = "Available MP: %d" % ap


func _can_afford(cost: int) -> bool:
	# Allow during SPENDING_MAJOR or SPENDING_MINOR (Minor allows ONE buy)
	if ActionController.state not in [ActionController.ActionState.SPENDING_MAJOR, ActionController.ActionState.SPENDING_MINOR]:
		return false
	if ActionController.current_action_type() != Enums.ActionType.MILITARY:
		return false
	if ActionController.bonus_tiles_bought_this_ar >= 2:
		return false
	if ActionController.state == ActionController.ActionState.SPENDING_MINOR and ActionController.minor_action_used_first_expense:
		return false
	return ActionController.ap_for_current() >= cost


func _on_buy(theater_id: String) -> void:
	# Use ActionController's purchase which enforces §5.6.1 limits
	if ActionController.purchase_bonus_war_tile(theater_id):
		_refresh()


func _on_upgrade() -> void:
	# Pick the worst basic tile theater and upgrade it
	var war_id := WarManager.get_upcoming_war_id()
	if war_id == "" or not ActionController.current_tile.has_military_upgrade:
		return
	var war: WarData = WarManager.wars[war_id]
	for theater in war.theaters:
		if WarManager.military_upgrade(current_side, theater.id):
			break
	_refresh()


func _on_close() -> void:
	visible = false
	closed.emit()
