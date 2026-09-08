extends Control

# Hovering on entries with space_ids highlights spaces on the board.

signal hover_spaces_changed(space_ids: Array)

@onready var rich: RichTextLabel = $Panel/Margin/VBox/Scroll/Rich
@onready var scroll: ScrollContainer = $Panel/Margin/VBox/Scroll
@onready var title: Label = $Panel/Margin/VBox/Title


func _ready() -> void:
	title.add_theme_font_size_override("font_size",18)
	rich.add_theme_font_size_override("normal_font_size",16)
	rich.add_theme_font_size_override("bold_font_size",16)
	if has_node("/root/GameLog"):
		GameLog.entry_added.connect(_on_entry)
		GameLog.history_changed.connect(_rebuild_history)
	rich.clear()
	rich.bbcode_enabled = true
	rich.meta_clicked.connect(_on_meta_clicked)
	rich.meta_hover_started.connect(_on_meta_hover)
	rich.meta_hover_ended.connect(_on_meta_unhover)
	title.text = LocaleManager.t("log_title")
	LocaleManager.locale_changed.connect(func(_l): title.text = LocaleManager.t("log_title"))
	LocaleManager.locale_changed.connect(func(_l): _rebuild_history())
	if has_node("/root/GameLog"):
		for e in GameLog.entries:
			_append_entry(e)


func _on_entry(entry: Dictionary) -> void:
	_append_entry(entry)
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _rebuild_history() -> void:
	# 저장 복원과 실행 취소는 기록도 함께 되돌린다. 기존 화면 위에 다시 더하지 않는다.
	rich.clear()
	for entry in GameLog.entries:
		_append_entry(entry)


func _append_entry(entry: Dictionary) -> void:
	if entry.get("is_separator", false):
		rich.append_text("\n[color=#fbbf24][b]%s[/b][/color]\n" % LocaleManager.message(entry["text"]))
		return

	var color_hex := "#9ca3af"
	var label := "···"
	match entry["side"]:
		Enums.Side.BRITAIN: color_hex = "#eb8576"; label = LocaleManager.tx("영국")
		Enums.Side.FRANCE: color_hex = "#80b9ed"; label = LocaleManager.tx("프랑스")
	var prefix := LocaleManager.tx("[color=#b8c6c8]%d턴 %d라운드[/color]") % [entry["turn"], entry["round"]]
	var side_tag := "[color=%s][b]%s[/b][/color]" % [color_hex, label]
	# Wrap space references in clickable [url=space_id] meta tags
	var text: String = LocaleManager.message(entry["text"])
	for sid in entry.get("space_ids", []):
		# Find display name and replace
		if sid in GameData.spaces:
			var sd: SpaceData = GameData.spaces[sid]
			# Wrap occurrence in url tag
			var display := sd.display_name
			var shown := display
			if LocaleManager.current_locale == "ko" and sd.name_ko != "":
				shown = sd.name_ko
			text = text.replace("[" + display + "]",
				"[[url=%s][color=#fbbf24]%s[/color][/url]]" % [sid, shown])
	rich.append_text("%s %s %s\n" % [prefix, side_tag, text])


func _on_meta_clicked(meta: Variant) -> void:
	# Click on space ref → could pan/zoom to it
	hover_spaces_changed.emit([str(meta)])


func _on_meta_hover(meta: Variant) -> void:
	hover_spaces_changed.emit([str(meta)])


func _on_meta_unhover(_meta: Variant) -> void:
	hover_spaces_changed.emit([])
