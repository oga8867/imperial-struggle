extends Control

@onready var title_label: Label = $Panel/VBox/Title
@onready var theaters_box: VBoxContainer = $Panel/VBox/Scroll/Theaters
@onready var resolve_btn: Button = $Panel/VBox/HBox/ResolveBtn
@onready var continue_btn: Button = $Panel/VBox/HBox/ContinueBtn

var resolution_results: Array = []


func _ready() -> void:
	visible = false
	WarManager.war_started.connect(_on_war_started)
	resolve_btn.pressed.connect(_on_resolve)
	continue_btn.pressed.connect(_on_continue)
	continue_btn.visible = false
	resolve_btn.text = LocaleManager.t("war_resolve")
	continue_btn.text = LocaleManager.t("war_continue")
	LocaleManager.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_new_locale: String) -> void:
	resolve_btn.text = LocaleManager.t("war_resolve")
	continue_btn.text = LocaleManager.t("war_continue")
	if visible and resolution_results.size() > 0:
		_show_results()


func _on_war_started(war_id: String) -> void:
	visible = true
	resolve_btn.visible = true
	continue_btn.visible = false
	resolution_results.clear()
	var war: WarData = WarManager.wars[war_id]
	title_label.text = war.name
	_refresh_theaters(war)


func _refresh_theaters(war: WarData) -> void:
	for child in theaters_box.get_children():
		child.queue_free()
	for theater in war.theaters:
		var th_panel := _make_theater_panel(theater)
		theaters_box.add_child(th_panel)


func _make_theater_panel(theater: TheaterData) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(0, 80)
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(12, 8)
	vbox.size = Vector2(900, 80)
	var name_lbl := Label.new()
	name_lbl.text = theater.name
	name_lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_lbl)

	var br_str := WarManager.calculate_theater_strength(theater.id, Enums.Side.BRITAIN)
	var fr_str := WarManager.calculate_theater_strength(theater.id, Enums.Side.FRANCE)
	var str_lbl := Label.new()
	str_lbl.text = "BR: %d   FR: %d" % [br_str, fr_str]
	str_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(str_lbl)
	panel.add_child(vbox)
	return panel


func _on_resolve() -> void:
	resolution_results = WarManager.resolve_full_war()
	resolve_btn.visible = false
	continue_btn.visible = true
	_show_results()


func _show_results() -> void:
	for child in theaters_box.get_children():
		child.queue_free()
	for r in resolution_results:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0, 60)
		var vbox := VBoxContainer.new()
		vbox.position = Vector2(12, 8)
		vbox.size = Vector2(900, 60)
		var lbl := Label.new()
		var winner_text := LocaleManager.t("war_tie")
		if r["winner"] == Enums.Side.BRITAIN:
			winner_text = LocaleManager.tf("war_wins_by", [LocaleManager.side(Enums.Side.BRITAIN), r["margin"]])
		elif r["winner"] == Enums.Side.FRANCE:
			winner_text = LocaleManager.tf("war_wins_by", [LocaleManager.side(Enums.Side.FRANCE), r["margin"]])
		lbl.text = LocaleManager.tf("war_result_line", [
			r["theater_name"], r["br_strength"], r["fr_strength"], winner_text])
		lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(lbl)
		panel.add_child(vbox)
		theaters_box.add_child(panel)


func _on_continue() -> void:
	visible = false
	GameManager.resolve_war_and_continue()
