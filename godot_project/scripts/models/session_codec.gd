class_name SessionCodec
extends RefCounted

# 임의의 파일 경로를 실행하지 않고 허용한 모델만 생성한다.
# 공유된 카드 참조와 정수 Dictionary 키도 손실 없이 보존한다.
const MODELS = {
	"GameState": preload("res://scripts/models/game_state.gd"),
	"PlayerState": preload("res://scripts/models/player_state.gd"),
	"SpaceState": preload("res://scripts/models/space_state.gd"),
	"SpaceData": preload("res://scripts/models/space_data.gd"),
	"EventCard": preload("res://scripts/models/event_card.gd"),
	"MinistryCard": preload("res://scripts/models/ministry_card.gd"),
	"InvestmentTile": preload("res://scripts/models/investment_tile.gd"),
	"WarTile": preload("res://scripts/models/war_tile.gd"),
	"Advantage": preload("res://scripts/models/advantage.gd"),
}
var references: Dictionary = {}
var valid: bool = true

func encode(value):
	if value is Object:
		var instance_id = value.get_instance_id()
		if references.has(instance_id): return {"ref": references[instance_id]}
		var kind = ""
		for model in MODELS:
			if value.get_script() == MODELS[model]: kind = model
		if kind == "":
			valid = false
			return null
		var reference = references.size() + 1
		references[instance_id] = reference
		var fields = {}
		for property in value.get_script().get_script_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				fields[property.name] = encode(value.get(property.name))
		return {"model": kind, "id": reference, "fields": fields}
	if value is Dictionary:
		var entries = []
		for key in value: entries.append([encode(key), encode(value[key])])
		return {"entries": entries}
	if value is Array:
		var entries = []
		for item in value: entries.append(encode(item))
		return entries
	if value is Vector2: return {"vector2": [value.x, value.y]}
	if value is int: return {"integer": value}
	return value

func decode(value):
	if value is Array:
		var output = []
		for item in value: output.append(decode(item))
		return output
	if not value is Dictionary: return value
	if value.has("integer"):
		if not (value.integer is float or value.integer is int): valid=false; return null
		return int(value.integer)
	if value.has("vector2"):
		if not value.vector2 is Array or value.vector2.size()!=2 or not value.vector2.all(func(v): return v is float or v is int): valid=false; return null
		return Vector2(value.vector2[0],value.vector2[1])
	if value.has("ref"):
		if not (value.ref is float or value.ref is int): valid=false; return null
		if not references.has(int(value.ref)): valid = false
		return references.get(int(value.ref))
	if value.has("entries"):
		var output = {}
		if not value.entries is Array: valid=false; return null
		for pair in value.entries:
			if not pair is Array or pair.size()!=2: valid=false; return null
			output[decode(pair[0])] = decode(pair[1])
		return output
	if value.has("model") and MODELS.has(value.model):
		if not value.get("fields") is Dictionary or not (value.get("id") is float or value.get("id") is int): valid=false; return null
		if int(value.id)<=0 or references.has(int(value.id)): valid=false; return null
		var object = MODELS[value.model].new()
		references[int(value.id)] = object
		for property in object.get_script().get_script_property_list():
			if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
			if not value.fields.has(property.name): continue
			var decoded=decode(value.fields[property.name])
			if not compatible(object,property.name,decoded): valid=false; return null
			assign_field(object, property.name, decoded)
		return object
	valid = false
	return null

static func compatible(object: Object,field: String,value) -> bool:
	for property in object.get_property_list():
		if property.name!=field: continue
		if property.type!=TYPE_NIL and typeof(value)!=property.type and not (property.type==TYPE_OBJECT and value==null): return false
		break
	var existing=object.get(field)
	if existing is Array and existing.is_typed() and value is Array:
		for item in value:
			if typeof(item)!=existing.get_typed_builtin(): return false
			if item is Object and existing.get_typed_script()!=null and item.get_script()!=existing.get_typed_script(): return false
	return true

static func assign_field(object: Object, field: String, value) -> void:
	# 기존 배열의 Array[EventCard] 같은 타입을 유지하여 요소를 복사한다.
	var existing = object.get(field)
	if existing is Array and value is Array: existing.assign(value)
	elif existing is Dictionary and value is Dictionary:
		existing.clear()
		existing.merge(value)
	else: object.set(field, value)
