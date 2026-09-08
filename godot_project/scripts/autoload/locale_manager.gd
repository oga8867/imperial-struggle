extends Node

# Central localization. UI code should route ALL user-facing strings through here
# so switching locale (en/ko) updates everything. Emits locale_changed for live refresh.

signal locale_changed(new_locale: String)

var current_locale: String = "ko"
var _translations: Dictionary = {}
var ui_english: Dictionary = {}
var missing_translations: Dictionary = {}
var _message_patterns: Array = []
var _message_literals: Dictionary = {}
var _message_keys: Array = []
var _static_sources: Dictionary = {}

const SUPPORTED_LOCALES := ["en", "ko"]


func _ready() -> void:
	_load_translations("en")
	_load_translations("ko")
	ui_english = JSON.parse_string(FileAccess.get_file_as_string("res://locale/ui_en.json"))
	for source in ui_english:
		_static_sources[source] = source
		_static_sources[ui_english[source]] = source
	var settings = ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		var saved = settings.get_value("interface","language","ko")
		if saved in SUPPORTED_LOCALES: current_locale = saved


func set_locale(locale: String) -> void:
	if locale in SUPPORTED_LOCALES:
		current_locale = locale
		var settings = ConfigFile.new()
		settings.load("user://settings.cfg")
		settings.set_value("interface","language",locale)
		settings.save("user://settings.cfg")
		locale_changed.emit(locale)

# 새 UI는 한국어 원문을 번역 키로 사용한다. 문자열의 의미를 바로 읽을 수 있고,
# 포맷 인자의 개수·종류를 자동 검사할 수 있다. 규칙 ID와 저장 데이터는 바꾸지 않는다.
func tx(source: String) -> String:
	if current_locale == "ko": return source
	if ui_english.has(source): return ui_english[source]
	if not missing_translations.has(source):
		missing_translations[source] = true
		push_error("Missing English UI translation: "+source)
	return source

func local_name(english: String, korean: String) -> String:
	return korean if current_locale == "ko" and not korean.is_empty() else english

func bind_literals(root: Node) -> void:
	# 생성 시의 정적 라벨·버튼을 언어 신호에 연결한다. 숫자·상태처럼 갱신되는
	# 값은 각 화면의 refresh가 처리한다. 연결 뒤 다른 문구로 바뀌었다면 덮어쓰지 않는다.
	if root is Control:
		for property in ["text","tooltip_text"]:
			if property == "text" and not (root is Label or root is Button or root is RichTextLabel): continue
			var value = root.get(property)
			if not _static_sources.has(value): continue
			var binding = {"source":_static_sources[value],"last":value}
			var callback = func(_locale):
				if root.get(property) == binding.last:
					binding.last = tx(binding.source)
					root.set(property,binding.last)
			locale_changed.connect(callback)
			root.tree_exiting.connect(func():
				if locale_changed.is_connected(callback): locale_changed.disconnect(callback),CONNECT_ONE_SHOT)
	for child in root.get_children(): bind_literals(child)

func _has_korean(value: String) -> bool:
	for character in value:
		var code = character.unicode_at(0)
		if code >= 0xac00 and code <= 0xd7a3: return true
	return false

func _prepare_messages() -> void:
	if not _message_keys.is_empty(): return
	var formats = RegEx.new()
	formats.compile("%[+0-9.\\-]*[sdf]")
	for source in ui_english:
		var matches = formats.search_all(source)
		if matches.is_empty():
			_message_literals[source] = ui_english[source]
			continue
		var pattern = "(?s)^"
		var previous = 0
		var types: Array = []
		for token in matches:
			pattern += _regex_escape(source.substr(previous,token.get_start()-previous))
			var type = token.get_string().right(1)
			types.append(type)
			pattern += "(.*?)" if type == "s" else "([+\\-]?[0-9]+(?:\\.[0-9]+)?)"
			previous = token.get_end()
		pattern += _regex_escape(source.substr(previous))+"$"
		var regex = RegEx.new()
		regex.compile(pattern)
		_message_patterns.append({"regex":regex,"types":types,"target":ui_english[source],"length":source.length()})
	# 모델의 표준 영문 이름을 활용한다. 별도의 번역으로 원작 지명이 달라지지 않는다.
	for space in GameData.spaces.values(): _add_name(space.name_ko,space.display_name)
	for card in GameData.ministries: _add_name(card.title_ko,card.title)
	for card in GameData.events: _add_name(card.title_ko,card.title)
	for war in WarManager.wars.values():
		_add_name(war.name_ko,war.name)
		for theater in war.theaters: _add_name(theater.name_ko,theater.name)
	for key in _translations.ko:
		if _translations.en.has(key) and not _translations.ko[key].contains("%"):
			_add_name(_translations.ko[key],_translations.en[key])
	_message_keys = _message_literals.keys()
	_message_keys.sort_custom(func(a,b): return a.length()>b.length())
	_message_patterns.sort_custom(func(a,b): return a.length>b.length)

func _add_name(korean: String, english: String) -> void:
	if not korean.is_empty() and _has_korean(korean): _message_literals[korean] = english

func _regex_escape(value: String) -> String:
	var escaped = ""
	for character in value:
		if character in "\\.^$|?*+()[]{}": escaped += "\\"
		escaped += character
	return escaped

func message(source: String, depth: int = 0) -> String:
	# 규칙 모델의 안내와 과거 한국어 저장 기록은 표시할 때만 번역한다.
	# 완성 문장을 먼저 대조하고, 포맷 인자 속 지명·카드명도 표준 이름으로 바꾼다.
	if current_locale == "ko" or not _has_korean(source): return source
	_prepare_messages()
	if _message_literals.has(source): return _message_literals[source]
	if depth < 3:
		for item in _message_patterns:
			var found = item.regex.search(source)
			if found == null: continue
			var args: Array = []
			for i in item.types.size():
				var value = found.get_string(i+1)
				args.append(message(value,depth+1) if item.types[i]=="s" else (float(value) if item.types[i]=="f" else int(value)))
			return item.target % args
	var result = source
	for key in _message_keys:
		result = result.replace(key,_message_literals[key])
	return result


func toggle_locale() -> void:
	set_locale("en" if current_locale == "ko" else "ko")


# Translate a key. Falls back to English, then to the raw key.
func t(key: String) -> String:
	if current_locale in _translations:
		var dict: Dictionary = _translations[current_locale]
		if key in dict:
			return dict[key]
	if "en" in _translations:
		var dict: Dictionary = _translations["en"]
		if key in dict:
			return dict[key]
	return key


# Backwards-compatible alias
func tr_key(key: String) -> String:
	return t(key)


# Translate + printf-style format: tf("hud_turn", [3, 6]) with value "턴 %d/%d"
func tf(key: String, args: Array) -> String:
	return t(key) % args


# ---- Enum → localized name helpers (single source of truth) ----

func side(s: int) -> String:
	match s:
		Enums.Side.BRITAIN: return t("side_britain")
		Enums.Side.FRANCE: return t("side_france")
	return ""


func era(e: int) -> String:
	match e:
		Enums.Era.SUCCESSION: return t("era_succession")
		Enums.Era.EMPIRE: return t("era_empire")
		Enums.Era.REVOLUTION: return t("era_revolution")
	return ""


func phase(p: int) -> String:
	match p:
		Enums.TurnPhase.DECK_PHASE: return t("phase_deck")
		Enums.TurnPhase.DEBT_LIMIT_INCREASE: return t("phase_debt_limit")
		Enums.TurnPhase.AWARD_PHASE: return t("phase_award")
		Enums.TurnPhase.GLOBAL_DEMAND_PHASE: return t("phase_global_demand")
		Enums.TurnPhase.RESET_PHASE: return t("phase_reset")
		Enums.TurnPhase.DEAL_CARDS_PHASE: return t("phase_deal_cards")
		Enums.TurnPhase.MINISTRY_PHASE: return t("phase_ministry")
		Enums.TurnPhase.INITIATIVE_PHASE: return t("phase_initiative")
		Enums.TurnPhase.ACTION_PHASE: return t("phase_action")
		Enums.TurnPhase.REDUCE_TREATY_POINTS: return t("phase_reduce_tp")
		Enums.TurnPhase.RESOLVE_REMAINING_POWERS: return t("phase_resolve_powers")
		Enums.TurnPhase.SCORING_PHASE: return t("phase_scoring")
		Enums.TurnPhase.VICTORY_CHECK: return t("phase_victory_check")
		Enums.TurnPhase.FINAL_SCORING: return t("phase_final_scoring")
	return ""


func region(r: int) -> String:
	match r:
		Enums.Region.EUROPE: return t("region_europe")
		Enums.Region.NORTH_AMERICA: return t("region_north_america")
		Enums.Region.CARIBBEAN: return t("region_caribbean")
		Enums.Region.INDIA: return t("region_india")
	return ""


func region_short(r: int) -> String:
	match r:
		Enums.Region.EUROPE: return t("region_short_europe")
		Enums.Region.NORTH_AMERICA: return t("region_short_na")
		Enums.Region.CARIBBEAN: return t("region_short_ca")
		Enums.Region.INDIA: return t("region_short_in")
	return ""


func commodity(c: int) -> String:
	match c:
		Enums.Commodity.FISH: return t("commodity_fish")
		Enums.Commodity.FUR: return t("commodity_fur")
		Enums.Commodity.SPICE: return t("commodity_spice")
		Enums.Commodity.SUGAR: return t("commodity_sugar")
		Enums.Commodity.TOBACCO: return t("commodity_tobacco")
		Enums.Commodity.COTTON: return t("commodity_cotton")
	return ""


func action(a: int) -> String:
	match a:
		Enums.ActionType.ECONOMIC: return t("action_economic")
		Enums.ActionType.DIPLOMATIC: return t("action_diplomatic")
		Enums.ActionType.MILITARY: return t("action_military")
	return ""


func action_short(a: int) -> String:
	match a:
		Enums.ActionType.ECONOMIC: return t("action_short_economic")
		Enums.ActionType.DIPLOMATIC: return t("action_short_diplomatic")
		Enums.ActionType.MILITARY: return t("action_short_military")
	return "?"


func war(w: int) -> String:
	match w:
		Enums.War.SPANISH_SUCCESSION: return t("war_spanish_succession")
		Enums.War.AUSTRIAN_SUCCESSION: return t("war_austrian_succession")
		Enums.War.SEVEN_YEARS: return t("war_seven_years")
		Enums.War.AMERICAN_INDEPENDENCE: return t("war_american_independence")
	return ""


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
