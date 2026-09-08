extends Control

signal closed
@onready var title_label: Label = $Panel/VBox/Title
@onready var theater_box: VBoxContainer = $Panel/VBox/Scroll/Theaters
@onready var ap_label: Label = $Panel/VBox/APLabel
@onready var close_btn: Button = $Panel/VBox/CloseBtn
var current_side: int

func _ready() -> void:
	LocaleManager.locale_changed.connect(func(_l):
		if visible: _refresh())
	hide()
	$Panel/VBox/UpgradeBtn.hide()
	close_btn.text = LocaleManager.tx("닫기")
	close_btn.pressed.connect(func():
		if ActionController.bonus_drawn == null:
			hide()
			closed.emit())

func show_for(side: Enums.Side) -> void:
	current_side = side
	show()
	_refresh()

func _button(text: String, action: Callable) -> void:
	var button = Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 52
	button.pressed.connect(func():
		action.call()
		_refresh())
	theater_box.add_child(button)

func _refresh() -> void:
	for child in theater_box.get_children():
		theater_box.remove_child(child)
		child.queue_free()
	var drawn = ActionController.bonus_drawn
	close_btn.disabled = drawn != null
	ap_label.text = LocaleManager.tx("남은 군사 행동점수 %d · 이번 라운드 구입 %d/2") % [ActionController.ap_for_current(),ActionController.bonus_tiles_bought_this_ar]
	if drawn == null:
		title_label.text = LocaleManager.tx("보너스 전쟁 타일 · 뽑은 뒤 전장을 선택합니다")
		if not ActionController.bonus_purchase_theaters().is_empty():
			_button(LocaleManager.tx("군사 2점 사용하고 타일 뽑기"),ActionController.begin_bonus_purchase)
		return
	title_label.text = LocaleManager.tx("뽑은 타일: %s · 전력 %+d") % [drawn.display_name,drawn.strength]
	for theater in WarManager.get_upcoming_theaters():
		if theater.id not in ActionController.bonus_allowed_theaters: continue
		var tiles: Array = WarManager.bonus_war_tiles_in_theater[theater.id][current_side]
		if tiles.size() < 2:
			_button(LocaleManager.tx("%s에 배치 (%d/2)") % [LocaleManager.local_name(theater.name,theater.name_ko),tiles.size()],ActionController.place_bonus_tile.bind(theater.id))
		else:
			for index in tiles.size():
				for other in WarManager.get_upcoming_theaters():
					if other.id != theater.id and WarManager.bonus_war_tiles_in_theater[other.id][current_side].size()<2:
						_button(LocaleManager.tx("%s에 배치 · 기존 %+d 타일 → %s") % [LocaleManager.local_name(theater.name,theater.name_ko),tiles[index].strength,LocaleManager.local_name(other.name,other.name_ko)],ActionController.place_bonus_tile.bind(theater.id,index,other.id))
