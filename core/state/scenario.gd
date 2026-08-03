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
var setup_notes: Array = []
var rendezvous_markers: Array = []
var commanders: Array = []
var map_info: Dictionary = {}

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
	setup_notes = d.get("setup_notes", [])
	rendezvous_markers = d.get("rendezvous_markers", [])
	commanders = d.get("commanders", [])
	var map_v: Variant = d.get("_map", {})
	map_info = map_v if typeof(map_v) == TYPE_DICTIONARY else {}
	var bs: Variant = d.get("battle_setup", null)
	battle_setup = bs if typeof(bs) == TYPE_DICTIONARY else {}
	var sp: Variant = d.get("ship_pool", null)
	_pool = sp if typeof(sp) == TYPE_DICTIONARY else {}
	title = String(briefing.get("title", id))
	_load_victory()
	return true


## La riserva navi, presente solo nella Campagna: le navi disponibili alle nove
## Operazioni, per parte. La Campagna non e' uno scenario da giocare - non ha
## nessuno schieramento - e' il contenitore che tiene il conto di chi c'e'
## ancora.
func ship_pool() -> Dictionary:
	return _pool


var _pool: Dictionary = {}


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
	bs.predeployed = true
	bs.skip_snafu = bool(battle_setup.get("skip_snafu", false))
	bs.starting_confusion_side = int(battle_setup.get(
		"starting_confusion_side", -1))
	bs.minimum_break_away_round = int(battle_setup.get(
		"minimum_break_away_round", 1))
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
		sh.torpedo_attack_limit = int(e.get("torpedo_attack_limit",
			sh.torpedo_attack_limit))
		sh.hit_limit = int(e.get("hit_limit", sh.hit_limit))
		sh.battle_zone = int(zones.get(String(e.get("zone", "FAR")),
			BattleState.Zone.FAR))
		sh.smoke = bool(e.get("smoke", false))
		if e.has("smoke_allowed"):
			sh.set_meta("smoke_allowed", bool(e["smoke_allowed"]))
		if bool(e.get("special_effects_immune", false)):
			sh.set_meta("special_effects_immune", true)
		if e.has("break_away_min_round"):
			sh.set_meta("break_away_min_round", int(e["break_away_min_round"]))
		if e.has("break_away_required_zone"):
			sh.set_meta("break_away_required_zone", int(zones.get(
				String(e["break_away_required_zone"]), BattleState.Zone.FAR)))
		# l'attitudine di partenza, se lo scenario la indica. "ANY" resta al
		# valore predefinito (Avvicinamento): la scelta e' del giocatore, e il
		# motore non la fa al posto suo.
		var att := String(attitudes().get(sh.name, ""))
		if att != "" and att != "ANY":
			sh.attitude = Attitude.from_marker(att)
			bs.fixed_setup_attitudes[sh] = sh.attitude
		if int(e.get("side", 1)) == TaskForce.Side.KRIEGSMARINE:
			km.ships.append(sh)
		else:
			rn.ships.append(sh)
		if e.has("entry_round"):
			var phase_name := String(e.get("entry_phase", "LINGERING"))
			var phases := {"LINGERING": BattleState.Phase.LINGERING,
				"BREAK_AWAY": BattleState.Phase.BREAK_AWAY}
			bs.delayed_entry[sh] = {
				"round": int(e["entry_round"]),
				"phase": int(phases.get(phase_name, BattleState.Phase.LINGERING)),
				"zone": sh.battle_zone,
				"attitude": sh.attitude,
			}
	km.recompute_speed()
	rn.recompute_speed()
	if initiative == TaskForce.Side.ROYAL_NAVY:
		bs.active_tf = rn
		bs.target_tf = km
	else:
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


## Attitudine di partenza di ogni nave, per nome (Regole Avanzate p.3).
##
## Non sta nel salvataggio VASSAL: l'attitudine si indica GIRANDO la pedina, e
## la rotazione il modulo non la registra. E' quindi un dato letto a mano dalla
## mappa dello scenario stampata nel fascicolo, come le tabelle di vittoria.
## Il valore "ANY" vuol dire che il fascicolo lascia scegliere al giocatore.
func attitudes() -> Dictionary:
	return victory_data.get("attitudes", {})


## Regole che cambiano da scenario a scenario, lette a mano dal fascicolo.
## Una voce assente NON vuol dire "no": vuol dire "non trascritta", e chi
## chiama deve saper distinguere i due casi.
func rules() -> Dictionary:
	return victory_data.get("rules", {})


## Le condizioni di fine stampate nel riquadro "The End" dello scenario in
## solitario. Un dizionario vuoto significa "non trascritte": lo scenario non
## potra' finire da solo, e questo si vede subito in un replay invece di
## sembrare una partita molto lunga.
func end_conditions() -> Dictionary:
	return victory_data.get("end_conditions", {})


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


func reinforcement_leaders() -> Dictionary:
	return victory_data.get("reinforcement_leaders", {})


## Rotte tirate sul dado per i Gruppi di Rinforzo che non hanno un porto fisso.
## Ne esiste uno solo, il Gruppo A di A1 (fascicolo p.59): partenza e
## destinazione si determinano con un tiro quando il Gruppo entra in gioco.
## Un dizionario vuoto significa "questo scenario non ne ha", non "non
## trascritto": i Gruppi normali stanno in `reinforcement_ports`.
func reinforcement_routes() -> Dictionary:
	return victory_data.get("reinforcement_routes", {})


## Il segnalino Informazioni che una parte puo' piazzare una volta per scenario:
## il B-Dienst tedesco di BL1 e il Bletchley Park britannico di A1 sono la
## stessa facolta' con le parti scambiate. Vuoto = questo scenario non ce l'ha.
func intel_marker_once() -> Dictionary:
	return victory_data.get("intel_marker_once", {})


## Note manuali sullo schieramento, usate soprattutto dagli scenari solitari:
## molte rotte sono stampate come "Halifax -> Clyde/Liverpool, 11 segmenti",
## non come esagoni. Mostrarlo e' piu' onesto che lasciare "0 TF, 0 navi".
func raw_setup_notes() -> Array:
	return setup_notes


## Le condizioni di vittoria di questo scenario sono state trascritte?
## Non basta guardare i premi in punti: Op1 Homecoming non ne ha nessuno e non
## per questo e' incompleta - si vince per condizioni, e quelle ci sono.
func has_victory_table() -> bool:
	for k in ["awards", "conditions", "debriefing"]:
		if not (victory_data.get(k, []) as Array).is_empty():
			return true
	# gli obiettivi dei mini-scenari sono un Dictionary, non un Array: e' il
	# genere di dettaglio che fa dire "non trascritto" a qualcosa che c'e'
	return not (victory_data.get("objectives", {}) as Dictionary).is_empty()


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
		"rendezvous_markers": rendezvous_markers,
		"commanders": commanders,
		"end_conditions": end_conditions(),
		"intel_marker_once": intel_marker_once(),
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
	for key_v: Variant in [["objective", "OBIETTIVO"], ["end", "FINE DELLO SCENARIO"],
			["victory", "VITTORIA"], ["historical", "ESITO STORICO"]]:
		var pair: Array = key_v
		var txt := String(briefing.get(pair[0], "")).strip_edges()
		if txt != "":
			parts.append("\n[b]%s[/b]\n%s" % [pair[1], txt])
	return "\n".join(parts)
