extends Node

# 보드와 Autoload 진행 상태를 하나의 그래프로 저장한다.
# v1 파일은 행동·전쟁 상태가 없어 완전한 복원이 불가능하다. 원본은 보존한다.
const SAVE_DIR := "user://saves"
const AUTOSAVE_NAME := "autosave"
const Codec = preload("res://scripts/models/session_codec.gd")
const FIELDS := {
	"GameManager": ["state", "_discard_pending_sides", "_ministry_pending_sides", "_initiative_first_player_pending", "_swept_awards_winner", "_swept_demand_winner", "_initial_territories"],
	"GameData": ["ministries"],
	"ActionController": [],
	"WarFlow": [],
	"EventEffects": ["pending_choices", "current_card", "current_side", "current_with_bonus"],
	"WarManager": ["current_war_id", "_resolved_war_id", "_cached_results", "basic_war_tiles", "bonus_war_tiles_in_theater", "basic_tile_in_theater", "pending_cp", "current_theater_index", "territory_refusals", "bonus_tile_pool"],
	"AdvantageManager": ["discounts", "advantages", "_advantages_used_this_round", "_regions_used_this_round", "pending_market_discount", "pending_discount_side"],
	"AwardManager": ["turn_awards", "remaining_awards"],
	"MinistryEffects": ["watt_active_for_britain", "active_flags"],
	"MinistryDecisions": ["pending", "pre_tile_action_used"],
	"AIController": ["enabled", "ai_side"],
	"GameLog": ["entries", "current_turn_section"],
}
var last_error := ""

func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _path(name: String) -> String:
	if name == "" or name != name.validate_filename(): return ""
	return "%s/%s.json" % [SAVE_DIR, name]

func save_game(name: String = AUTOSAVE_NAME) -> bool:
	last_error = ""
	var path = _path(name)
	if path == "" or GameManager.state == null: return false
	ensure_dir()
	var data = _serialize()
	if data.is_empty(): return false
	# 임시 파일 쓰기를 마친 후 교체하여 저장 도중 종료에 대비한다.
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "저장 파일을 쓸 수 없습니다."
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(path, path + ".bak") != OK:
			last_error = "이전 저장을 보존할 수 없습니다."
			return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func load_game(name: String = AUTOSAVE_NAME) -> bool:
	last_error = ""
	var path = _path(name)
	if path == "" or not FileAccess.file_exists(path):
		last_error = "저장된 게임이 없습니다."
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16000000: return false
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version", 0) != 2:
		last_error = "이 저장은 이전 형식이거나 손상되었습니다. 기존 파일은 보존했습니다."
		return false
	return _deserialize(data)

func list_saves() -> Array:
	ensure_dir()
	var result = []
	for filename in DirAccess.get_files_at(SAVE_DIR):
		if filename.ends_with(".json"): result.append(filename.trim_suffix(".json"))
	return result

func _fields_for(node_name: String) -> Array:
	if node_name not in ["ActionController", "WarFlow"]: return FIELDS[node_name]
	var names = []
	for property in get_node("/root/"+node_name).get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: names.append(property.name)
	return names

func _serialize() -> Dictionary:
	var snapshot = {}
	for node_name in FIELDS:
		var node = get_node("/root/" + node_name)
		var fields = {}
		for field in _fields_for(node_name): fields[field] = node.get(field)
		snapshot[node_name] = fields
	var codec = Codec.new()
	var payload = codec.encode(snapshot)
	if not codec.valid:
		last_error = "저장할 수 없는 게임 상태입니다."
		return {}
	return {"version": 2, "saved_at": Time.get_datetime_string_from_system(), "payload": payload}

func _deserialize(data: Dictionary) -> bool:
	var codec = Codec.new()
	var snapshot = codec.decode(data.get("payload"))
	if not codec.valid or not snapshot is Dictionary or not snapshot.has("GameManager"):
		last_error = "저장 데이터 검증에 실패했습니다."
		return false
	# 모두 해석한 다음 적용하여 부분적으로 복원된 판이 기존 판을 덮지 않게 한다.
	# 기록을 저장하기 전의 v2도 게임 자체는 온전하다. 없는 기록은 빈 이력으로 복원한다.
	if not snapshot.has("GameLog"): snapshot["GameLog"] = {"entries": [], "current_turn_section": 1}
	if not snapshot.has("MinistryDecisions"): snapshot["MinistryDecisions"]={"pending":{},"pre_tile_action_used":false}
	for node_name in FIELDS:
		if not snapshot.get(node_name) is Dictionary: return false
		for field in _fields_for(node_name):
			if snapshot[node_name].has(field) and not Codec.compatible(get_node("/root/"+node_name),field,snapshot[node_name][field]): return false
	if not snapshot.GameManager.get("state") is GameState: return false
	for node_name in FIELDS:
		var node = get_node("/root/" + node_name)
		for field in _fields_for(node_name):
			if snapshot[node_name].has(field): Codec.assign_field(node, field, snapshot[node_name][field])
	GameLog.history_changed.emit()
	MinistryDecisions.changed.emit()
	return true
