class_name Scenario
extends RefCounted

## Uno scenario: schieramento iniziale + briefing.
##
## Lo schieramento viene dai 22 salvataggi ufficiali del modulo VASSAL
## (traiettorie, stazioni, navi in ciascuna Task Force, comandanti, rinforzi);
## il briefing dal fascicolo Scenari per 2 Giocatori.
##
## Le CONDIZIONI DI VITTORIA restano testo. In Atlantic Chase sono discorsive e
## piene di eccezioni per scenario ("il tedesco vince se il Bismarck e' in un
## porto francese; altrimenti vince il britannico"), e trascriverle come regole
## eseguibili e' un lavoro a se'. Mostrarle al giocatore, che le applica, e'
## onesto e utile subito.

const DIR := "res://core/data/scenarios/"
const VICTORY_DIR := "res://core/data/victory/"

var id: String = ""
var title: String = ""
var initiative: int = TaskForce.Side.KRIEGSMARINE
var weather: int = TimeLapse.Weather.GOOD
var round_number: int = 1

var task_forces: Array = []            ## Dictionary grezzi, per GameState
var reinforcements: Dictionary = {}    ## gruppo -> Array[String] di navi
var info_triggers: Array = []

## Testo del briefing: title, initiative, weather, end, victory, historical.
var briefing: Dictionary = {}

## Problemi trovati importando il .vsav: quasi sempre una rotta ricostruita
## che attraversa un lato negato, perche' nel modulo VASSAL le pedine sono
## piazzate a mano su una mappa senza griglia.
var import_warnings: Array = []

## Tabella dei Punti Vittoria, se trascritta. Sta in un file separato perche'
## e' un dato letto a mano dal fascicolo, mentre lo scenario e' generato dal
## .vsav: tenerli distinti evita che una rigenerazione la cancelli.
var victory_data: Dictionary = {}

## Schieramento sulla Mappa di Battaglia, per i dodici mini-scenari.
##
## Quei dodici non sono partite sulla mappa operazionale: sono BATTAGLIE gia'
## schierate. Le navi partono nelle sei bande Lontana/Vicina/Ravvicinata dei
## due contendenti, senza Traiettorie ne' Stazioni - ed e' per questo che a
## lungo sono sembrati "vuoti": l'importatore cercava rotte che non esistono.
var battle_setup: Dictionary = {}

var load_error: String = ""


static func list_ids() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f.substr(0, f.length() - 5))
	out.sort()
	return out


static func load_by_id(scenario_id: String) -> Scenario:
	var s := Scenario.new()
	s.load_from(DIR + scenario_id + ".json")
	return s


func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_error = "impossibile aprire %s" % path
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		load_error = "JSON non valido in %s" % path
		return false
	var d: Dictionary = parsed
	id = String(d.get("name", ""))
	initiative = int(d.get("initiative", 0))
	weather = int(d.get("weather", 0))
	round_number = int(d.get("round", 1))
	task_forces = d.get("task_forces", [])
	reinforcements = d.get("reinforcements", {})
	info_triggers = d.get("info_triggers", [])
	briefing = d.get("briefing", {})
	import_warnings = d.get("import_warnings", [])
	var bs: Variant = d.get("battle_setup", null)
	battle_setup = bs if typeof(bs) == TYPE_DICTIONARY else {}
	title = String(briefing.get("title", id))
	_load_victory()
	return true


## Questo scenario e' una Battaglia gia' schierata invece di una partita sulla
## mappa operazionale?
func is_battle_scenario() -> bool:
	return not (battle_setup.get("ships", []) as Array).is_empty()


## Costruisce la Battaglia iniziale del mini-scenario: due Task Force con le
## navi gia' nelle rispettive bande. Ritorna null se non e' uno scenario di
## Battaglia.
func make_battle_state(weather_override: int = -1) -> BattleState:
	if not is_battle_scenario():
		return null
	var bs := BattleState.new(BattleState.Kind.BATTLE,
		weather if weather_override < 0 else weather_override)
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.name = "Kriegsmarine"
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.name = "Royal Navy"
	var zones := {"FAR": BattleState.Zone.FAR, "NEAR": BattleState.Zone.NEAR,
		"CLOSE": BattleState.Zone.CLOSE}
	for e_v: Variant in battle_setup.get("ships", []):
		var e: Dictionary = e_v
		var sh := ShipRoster.shared().make(String(e.get("ship", "")))
		if sh == null:
			sh = Ship.new(String(e.get("ship", "")))
		sh.battle_zone = int(zones.get(String(e.get("zone", "FAR")),
			BattleState.Zone.FAR))
		if int(e.get("side", 1)) == TaskForce.Side.KRIEGSMARINE:
			km.ships.append(sh)
		else:
			rn.ships.append(sh)
	km.recompute_speed()
	rn.recompute_speed()
	bs.active_tf = km
	bs.target_tf = rn
	return bs


func _load_victory() -> void:
	victory_data = {}
	var f := FileAccess.open(VICTORY_DIR + id + ".json", FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) == TYPE_DICTIONARY:
		victory_data = d


## Chi controlla quali porti in questo scenario. Vuoto = la situazione di
## partenza (vedi Completion.DEFAULT_CONTROL). Dalla quarta Operazione in poi
## "tutti i porti francesi e norvegesi sono controllati dai tedeschi", e alcuni
## scenari chiudono singoli porti: Murmansk in Op9, South America in Op6 e Op8.
func port_control() -> Dictionary:
	return victory_data.get("port_control", {})


## Regole che cambiano da scenario a scenario, lette a mano dal fascicolo.
## Una voce assente NON vuol dire "no": vuol dire "non trascritta", e chi
## chiama deve saper distinguere i due casi.
func rules() -> Dictionary:
	return victory_data.get("rules", {})


## I Convogli possono disperdersi in questo scenario? La dispersione non e' un
## diritto, e' un permesso che danno le istruzioni.
func convoy_dispersal_allowed() -> bool:
	return bool(rules().get("convoy_dispersal", false))


## "Se una Task Force puo' effettuare il Completamento, deve farlo": e' la
## clausola che impedisce di tenere una nave al sicuro in porto senza entrarci.
func completion_is_mandatory() -> bool:
	return bool(rules().get("completion_mandatory", false))


## In quale porto entra ciascun Gruppo di Rinforzi.
##
## Il salvataggio VASSAL non lo dice - i Gruppi stanno in caselle del Display
## Task Force, che non sono esagoni della mappa - quindi e' un dato letto a
## mano dalla mappa dello scenario stampata nel fascicolo. Un Gruppo assente da
## qui non ha un porto noto, e il gioco lo dice invece di sceglierne uno a
## caso: entrare nel porto sbagliato e' peggio che non entrare.
func reinforcement_ports() -> Dictionary:
	return victory_data.get("reinforcement_ports", {})


## Le condizioni di vittoria di questo scenario sono state trascritte?
## Non basta guardare i premi in punti: Op1 Homecoming non ne ha nessuno e non
## per questo e' incompleta - si vince per condizioni, e quelle ci sono.
func has_victory_table() -> bool:
	for k in ["awards", "conditions", "debriefing"]:
		if not (victory_data.get(k, []) as Array).is_empty():
			return true
	return false


## Numero di navi schierate, utile per un controllo rapido.
func ship_count() -> int:
	var n := 0
	for tf_v: Variant in task_forces:
		n += ((tf_v as Dictionary).get("ships", []) as Array).size()
	return n


func reinforcement_count() -> int:
	var n := 0
	for k_v: Variant in reinforcements.keys():
		n += (reinforcements[k_v] as Array).size()
	return n


## Dizionario nel formato che GameState.apply_dict() si aspetta.
func to_state_dict() -> Dictionary:
	return {
		"scenario": id,
		"weather": weather,
		"initiative": initiative,
		"round": round_number,
		"task_forces": task_forces,
		"info_triggers": info_triggers,
	}


func has_import_warnings() -> bool:
	return not import_warnings.is_empty()


func has_briefing() -> bool:
	return not briefing.is_empty()


## Testo del briefing formattato per il pannello, con i titoli di sezione.
func briefing_text() -> String:
	if briefing.is_empty():
		return "(nessun briefing per questo scenario)"
	var parts: Array[String] = []
	parts.append("[b]%s[/b]" % title)
	parts.append("Iniziativa: [b]%s[/b]    Meteo iniziale: [b]%s[/b]" % [
		"Kriegsmarine" if initiative == TaskForce.Side.KRIEGSMARINE else "Royal Navy",
		"cattivo" if weather == TimeLapse.Weather.BAD else "buono"])
	for key_v: Variant in [["end", "FINE DELLO SCENARIO"],
			["victory", "VITTORIA"], ["historical", "ESITO STORICO"]]:
		var pair: Array = key_v
		var txt := String(briefing.get(pair[0], "")).strip_edges()
		if txt != "":
			parts.append("\n[b]%s[/b]\n%s" % [pair[1], txt])
	return "\n".join(parts)
