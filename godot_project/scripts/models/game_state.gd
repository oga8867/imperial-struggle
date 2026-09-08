class_name GameState
extends Resource

@export var current_turn: int = 1
@export var current_era: Enums.Era = Enums.Era.SUCCESSION
@export var current_phase: Enums.GamePhase = Enums.GamePhase.SETUP
@export var current_turn_phase: Enums.TurnPhase = Enums.TurnPhase.DECK_PHASE
@export var vp: int = 15
@export var initiative: Enums.Side = Enums.Side.FRANCE
@export var first_player: Enums.Side = Enums.Side.FRANCE

@export var britain: PlayerState
@export var france: PlayerState

var available_investment_tiles: Array[InvestmentTile] = []
var investment_draw_pile: Array[InvestmentTile] = []
var investment_used_pile: Array[InvestmentTile] = []
var investment_dealt_this_turn: Array[InvestmentTile] = []
var byng_theater: String = ""
var war_carryover_draws: Dictionary = {}
var jacobite_victories: int = 0
var jacobite_defeated: bool = false
var jacobite_extra_ministry: bool = false
var winner: Enums.Side = Enums.Side.NONE
var victory_reason: String = ""
var event_draw_pile: Array[EventCard] = []
var event_discard_pile: Array[EventCard] = []   # discarded from hand (face-up, can be reshuffled)
var event_played_pile: Array[EventCard] = []    # played events (REMOVED from game per §5.2.5, but kept for UI reference)
var current_global_demand: Array[Enums.Commodity] = []
var current_awards: Dictionary = {}  # Region -> AwardTile

var spaces: Dictionary = {}  # space_id -> SpaceState
var current_action_round: int = 0
var phasing_player: Enums.Side = Enums.Side.FRANCE

var current_war: Enums.War = Enums.War.SPANISH_SUCCESSION
var war_tiles_in_play: Dictionary = {}  # theater -> {britain: [], france: []}


func _init() -> void:
	britain = PlayerState.new()
	britain.side = Enums.Side.BRITAIN
	france = PlayerState.new()
	france.side = Enums.Side.FRANCE


func get_player(side: Enums.Side) -> PlayerState:
	if side == Enums.Side.BRITAIN:
		return britain
	return france


func get_opponent(side: Enums.Side) -> PlayerState:
	if side == Enums.Side.BRITAIN:
		return france
	return britain


func score_vp(side: Enums.Side, amount: int) -> void:
	if side == Enums.Side.FRANCE:
		vp += amount
	else:
		vp -= amount


func get_era_for_turn(turn: int) -> Enums.Era:
	if turn <= 2:
		return Enums.Era.SUCCESSION
	elif turn <= 4:
		return Enums.Era.EMPIRE
	else:
		return Enums.Era.REVOLUTION


func get_war_after_turn(turn: int) -> Enums.War:
	match turn:
		2: return Enums.War.SPANISH_SUCCESSION
		3: return Enums.War.AUSTRIAN_SUCCESSION
		4: return Enums.War.SEVEN_YEARS
		5: return Enums.War.AMERICAN_INDEPENDENCE
		_: return Enums.War.SPANISH_SUCCESSION


func is_new_era_turn() -> bool:
	return current_turn in [1, 3, 5]


func is_war_turn() -> bool:
	return current_turn in [2, 3, 4, 5]


func check_auto_victory() -> Enums.Side:
	if vp >= 30:
		return Enums.Side.FRANCE
	elif vp <= 0:
		return Enums.Side.BRITAIN
	return Enums.Side.NONE


func determine_initiative() -> Enums.Side:
	if vp < 15:
		return Enums.Side.FRANCE
	elif vp > 15:
		return Enums.Side.BRITAIN
	return initiative
