class_name Session
extends RefCounted

## Ponte fra la schermata iniziale e la partita.
##
## Serve solo a portare la scelta dello scenario da una scena all'altra:
## change_scene_to_packed() non permette di impostare proprieta' sul nodo prima
## che parta il suo _ready(), quindi la scelta si parcheggia qui.

static var scenario_id: String = ""
static var seed_value: int = 0


static func start(p_scenario_id: String, p_seed: int = 0) -> void:
	scenario_id = p_scenario_id
	seed_value = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system())


static func has_choice() -> bool:
	return scenario_id != ""
