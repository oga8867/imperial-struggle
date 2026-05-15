extends Control

# Hovering on entries with space_ids highlights spaces on the board.

signal hover_spaces_changed(space_ids: Array)

@onready var rich: RichTextLabel = $Panel/Margin/VBox/Scroll/Rich
@onready var scroll: ScrollContainer = $Panel/Margin/VBox/Scroll
@onready var title: Label = $Panel/Margin/VBox/Title


func _ready() -> void:
	if has_node("/root/GameLog"):
		GameLog.entry_added.connect(_on_entry)
	rich.clear()
	rich.bbcode_enabled = true
	rich.meta_clicked.connect(_on_meta_clicked)
	rich.meta_hover_started.connect(_on_meta_hover)
	rich.meta_hover_ended.connect(_on_meta_unhover)
	if has_node("/root/GameLog"):
		for e in GameLog.entries:
			_append_entry(e)


func _on_entry(entry: Dictionary) -> void:
	_append_entry(entry)
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _append_entry(entry: Dictionary) -> void:
	if entry.get("is_separator", false):
		rich.append_text("\n[color=#fbbf24][b]%s[/b][/color]\n" % entry["text"])
		return

	var color_hex := "#9ca3af"
	var label := "···"
	match entry["side"]:
		Enums.Side.BRITAIN: color_hex = "#c8423a"; label = "BR"
		Enums.Side.FRANCE: color_hex = "#3a5fb0"; label = "FR"
	var prefix := "[color=#6b7280]T%d R%d[/color]" % [entry["turn"], entry["round"]]
	var side_tag := "[color=%s][b]%s[/b][/color]" % [color_hex, label]
	# Wrap space references in clickable [url=space_id] meta tags
	var text: String = entry["text"]
	for sid in entry.get("space_ids", []):
		# Find display name and replace
		if sid in GameData.spaces:
			var sd: SpaceData = GameData.spaces[sid]
			# Wrap occurrence in url tag
			var display := sd.display_name
			text = text.replace("[" + display + "]",
				"[[url=%s][color=#fbbf24]%s[/color][/url]]" % [sid, display])
	rich.append_text("%s %s %s\n" % [prefix, side_tag, text])


func _on_meta_clicked(meta: Variant) -> void:
	# Click on space ref → could pan/zoom to it
	hover_spaces_changed.emit([str(meta)])


func _on_meta_hover(meta: Variant) -> void:
	hover_spaces_changed.emit([str(meta)])


func _on_meta_unhover(_meta: Variant) -> void:
	hover_spaces_changed.emit([])
