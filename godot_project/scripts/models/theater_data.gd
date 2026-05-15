class_name TheaterData
extends Resource

@export var id: String
@export var name: String
@export var name_ko: String = ""
@export var region: Enums.Region
@export var bonus_strength_keys: Array[String] = []
@export var spoils_table: Array = []  # Array of {margin: String, winner: Array, loser: Array}
@export var additional_territories: Array[String] = []
