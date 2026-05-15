extends Node

signal locale_changed(new_locale: String)

var current_locale: String = "en"
var _translations: Dictionary = {}

const SUPPORTED_LOCALES := ["en", "ko"]


func _ready() -> void:
	_load_translations("en")
	_load_translations("ko")


func set_locale(locale: String) -> void:
	if locale in SUPPORTED_LOCALES:
		current_locale = locale
		locale_changed.emit(locale)


func tr_key(key: String) -> String:
	if current_locale in _translations:
		var dict: Dictionary = _translations[current_locale]
		if key in dict:
			return dict[key]
	if "en" in _translations:
		var dict: Dictionary = _translations["en"]
		if key in dict:
			return dict[key]
	return key


func _load_translations(locale: String) -> void:
	var path := "res://locale/%s.json" % locale
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		if err == OK:
			_translations[locale] = json.data
