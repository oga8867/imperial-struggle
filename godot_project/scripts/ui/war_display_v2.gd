extends Control

@onready var title_label: Label = $Panel/VBox/Title
@onready var theaters_box: VBoxContainer = $Panel/VBox/Scroll/Theaters
@onready var resolve_btn: Button = $Panel/VBox/HBox/ResolveBtn
@onready var continue_btn: Button = $Panel/VBox/HBox/ContinueBtn
var resolution_results: Array = []

func _ready() -> void:
	hide()
	WarManager.war_started.connect(_on_war_started)
	WarFlow.changed.connect(_refresh)
	WarFlow.finished.connect(_refresh)
	LocaleManager.locale_changed.connect(func(_l): _refresh())
	resolve_btn.pressed.connect(func(): WarFlow.start(false))
	continue_btn.pressed.connect(_on_continue)
	resolve_btn.text = LocaleManager.tx("전쟁 시작 · 전장 순서대로 해결")
	continue_btn.text = LocaleManager.tx("결과 확인 · 다음 턴")

func _on_war_started(_war_id: String) -> void:
	show()
	_refresh()

func _clear() -> void:
	for child in theaters_box.get_children():
		theaters_box.remove_child(child)
		child.queue_free()

func _text(value: String, font_size: int = 18) -> Label:
	var label = Label.new()
	label.text = LocaleManager.message(value)
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	theaters_box.add_child(label)
	return label

func _refresh() -> void:
	if not visible or not WarManager.current_war_id in WarManager.wars: return
	_clear()
	var war = WarManager.wars[WarManager.current_war_id]
	title_label.text = LocaleManager.local_name(war.name,war.name_ko)
	var completed = WarManager._resolved_war_id == WarManager.current_war_id
	resolve_btn.visible = not WarFlow.active and not completed
	continue_btn.visible = completed
	resolution_results = WarManager._cached_results if completed else WarFlow.results
	if not WarFlow.active and not completed:
		_text(LocaleManager.tx("각 전장의 타일 효과 → 전력 비교 → 전리품과 정복을 차례로 처리합니다. 다음 전장은 바뀐 지도를 기준으로 계산합니다."))
		for th in war.theaters:
			_text(LocaleManager.local_name(th.name,th.name_ko) + " · " + LocaleManager.region(th.region),22)
		return
	for r in resolution_results:
		var winner = LocaleManager.tx("무승부") if r.winner == Enums.Side.NONE else LocaleManager.side(r.winner) + LocaleManager.tx(" 승리")
		_text(LocaleManager.tx("%s · %s  |  영국 %d + %d = %d   /   프랑스 %d + %d = %d") % [r.theater_name,winner,r.br_army,r.br_bonus,r.br_strength,r.fr_army,r.fr_bonus,r.fr_strength])
	if WarFlow.active and not WarFlow.choice.is_empty():
		_text(LocaleManager.tx("현재 전장 · ") + LocaleManager.local_name(WarFlow.theater().name,WarFlow.theater().name_ko),24).add_theme_color_override("font_color",ThemeManager.COLOR_GOLD)
		_text(LocaleManager.side(WarFlow.choice.side) + " · " + LocaleManager.message(WarFlow.choice.prompt))
		var grid = GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation",12)
		grid.add_theme_constant_override("v_separation",12)
		theaters_box.add_child(grid)
		for option in WarFlow.choice.options:
			var button = Button.new()
			button.text = LocaleManager.message(option.label)
			button.custom_minimum_size = Vector2(278,70)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(func(): WarFlow.choose(option.id))
			grid.add_child(button)
	if completed:
		_text(LocaleManager.tx("전쟁 후 승점: %d · 모든 전장의 선택이 완료되었습니다.") % GameManager.state.vp,22)

func _on_continue() -> void:
	if WarFlow.active: return
	hide()
	GameManager.resolve_war_and_continue()
