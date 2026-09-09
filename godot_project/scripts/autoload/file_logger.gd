extends Node

# Writes all GameLog entries + key debug messages to a persistent file.
# File path: user://imperial_struggle.log (resolves to %APPDATA%/Godot/app_userdata/...)

const LOG_PATH := "user://imperial_struggle.log"
var _file: FileAccess


func _ready() -> void:
	# 탐색용 별도 프로세스는 사용자의 실제 플레이 기록을 열거나 지우지 않는다.
	if "--ai-worker" in OS.get_cmdline_user_args(): return
	# Open in WRITE mode (truncates) at start of each session
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file:
		_write("=== Imperial Struggle session started @ %s ===" % Time.get_datetime_string_from_system())
	if has_node("/root/GameLog"):
		GameLog.entry_added.connect(_on_log_entry)


func _on_log_entry(entry: Dictionary) -> void:
	if _file == null:
		return
	if entry.get("is_separator", false):
		_write("\n>>> %s <<<" % entry["text"])
		return
	var side_label := "···"
	match entry["side"]:
		Enums.Side.BRITAIN: side_label = "[BR]"
		Enums.Side.FRANCE: side_label = "[FR]"
	_write("T%d R%d %s %s" % [entry["turn"], entry["round"], side_label, entry["text"]])


func _write(line: String) -> void:
	if _file:
		_file.store_line(line)
		_file.flush()


func log_debug(text: String) -> void:
	_write("[DEBUG] " + text)


func get_log_path_resolved() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)
