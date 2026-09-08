class_name MinistryCard
extends Resource

@export var id: String
@export var side: Enums.Side
@export var eras: Array[Enums.Era] = []
@export var title: String
@export var keywords: Array[String] = []
@export var abilities: String = ""
@export var image: String = ""

var title_ko: String = ""
var abilities_ko: String = ""

var is_revealed: bool = false
var is_in_play: bool = false
var exhausted_abilities: Dictionary = {}

func disp_title() -> String:
	return LocaleManager.local_name(title,title_ko)

func disp_abilities() -> String:
	return LocaleManager.local_name(abilities,abilities_ko)


func has_keyword(keyword: String) -> bool:
	return keywords.has(keyword)


func is_available_in_era(era: Enums.Era) -> bool:
	return eras.has(era)


func reveal() -> bool:
	if is_revealed: return true
	# §3.5: 전쟁·득점·상대 라운드에서 뒤늦게 공개하는 경로까지 모델에서 막는다.
	if not MinistryDecisions.can_reveal(self,side): return false
	is_revealed = true
	ActionController.clear_undo_stack()
	GameLog.log_entry(side,"ministry",(title_ko if title_ko!="" else title)+" 공개")
	if id=="M-20" and is_in_play: MinistryEffects.defeat_jacobites()
	if id=="M-24": MinistryEffects.apply_trade_bonus(side)
	MinistryDecisions.changed.emit()
	return true


func exhaust_ability(ability_index: int = 0) -> void:
	exhausted_abilities[ability_index] = true


func is_ability_exhausted(ability_index: int = 0) -> bool:
	return exhausted_abilities.get(ability_index, false)


func reset_exhaustion() -> void:
	exhausted_abilities.clear()
