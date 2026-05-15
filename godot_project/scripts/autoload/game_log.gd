extends Node

# Centralized game event log with optional space references for board hover-highlighting.

signal entry_added(entry: Dictionary)

var entries: Array = []
var current_turn_section: int = 1


func log_entry(side: Enums.Side, kind: String, text: String, space_ids: Array = []) -> void:
	var st = GameManager.state if GameManager else null
	var entry := {
		"turn": st.current_turn if st else 0,
		"round": st.current_action_round if st else 0,
		"side": side,
		"kind": kind,
		"text": text,
		"space_ids": space_ids,
		"timestamp": Time.get_ticks_msec(),
		"is_separator": false,
	}
	entries.append(entry)
	entry_added.emit(entry)


func log_separator(text: String) -> void:
	var entry := {
		"turn": GameManager.state.current_turn if GameManager and GameManager.state else 0,
		"round": 0,
		"side": Enums.Side.NONE,
		"kind": "separator",
		"text": text,
		"space_ids": [],
		"timestamp": Time.get_ticks_msec(),
		"is_separator": true,
	}
	entries.append(entry)
	entry_added.emit(entry)


func log_system(text: String) -> void:
	log_entry(Enums.Side.NONE, "system", text)


func clear() -> void:
	entries.clear()


func format_entry(entry: Dictionary) -> String:
	var prefix := "T%d R%d" % [entry["turn"], entry["round"]]
	var side_label := "·"
	match entry["side"]:
		Enums.Side.BRITAIN: side_label = "[BR]"
		Enums.Side.FRANCE: side_label = "[FR]"
		Enums.Side.NONE: side_label = "···"
	return "%s %s %s" % [prefix, side_label, entry["text"]]
