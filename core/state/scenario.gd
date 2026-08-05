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

## Contatori solitari gia' pieni allo schieramento: vedi solo_start_counters().
var start_counters: Dictionary = {}

## Forze Furtive schierate: Mine, Sottomarini, U-Boat gia' sulla mappa allo
## schieramento. Ognuna e' { side, kind, q, r, note }; le regole stanno in
## `Stealth` (RB p.41).
var stealth_forces: Array = []

## Bersagli delle Mine (N1, p.17): { name, q, r, reaction }.
var d_mines: Array = []

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
	var sf: Variant = d.get("stealth_forces", null)
	stealth_forces = sf if typeof(sf) == TYPE_ARRAY else []
	var mt: Variant = d.get("mines_targets", null)
	d_mines = mt if typeof(mt) == TYPE_ARRAY else []
	var sc: Variant = d.get("solo_counters", null)
	start_counters = sc if typeof(sc) == TYPE_DICTIONARY else {}
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


## Contatori solitari gia' pieni allo schieramento. Servono per i segnalini che
## il fascicolo conta ma che il motore non mette sulla mappa: A2 "start with two
## U-Boat force markers" (p.65) e la fine stampata sul risultato 'E' li consuma
## uno alla volta. Modellare il CONTEGGIO non e' modellare la pedina, ed e'
## scritto cosi' anche nel dato: il resto resta una lacuna dichiarata.
## I bersagli delle Mine di N1 (fascicolo p.17). Vuoto per gli altri scenari.
func mines_targets() -> Array:
	return d_mines.duplicate(true)


func solo_start_counters() -> Dictionary:
	return start_counters.duplicate(true)


## Il segnalino Informazioni che una parte puo' piazzare una volta per scenario:
## il B-Dienst tedesco di BL1 e il Bletchley Park britannico di A1 sono la
## stessa facolta' con le parti scambiate. Vuoto = questo scenario non ce l'ha.
func intel_marker_once() -> Dictionary:
	return victory_data.get("intel_marker_once", {})


## L'inserto su cui si gioca questo scenario, o "" per la Mappa Operazionale.
## Cinque scenari solitari su quindici hanno la loro mappa: BL3 e N3 sul Mare
## del Nord, N1, N2 e N5 sul Mare di Norvegia.
func inset_key() -> String:
	return String(map_info.get("inset", ""))


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
		"solo_counters": solo_start_counters(),
		"stealth_forces": stealth_forces.duplicate(true),
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
	var printed := printed_rules_text()
	for key_v: Variant in [["objective", "OBIETTIVO"], ["end", "FINE DELLO SCENARIO"],
			["victory", "VITTORIA"], ["historical", "ESITO STORICO"]]:
		var pair: Array = key_v
		# Le sezioni FINE e VITTORIA hanno la precedenza sul testo importato
		# quando il dato di vittoria le contiene davvero: il briefing dei
		# solitari diceva "vedi il fascicolo", che e' l'unica cosa che chi
		# gioca non puo' fare mentre gioca.
		var replacement := String(printed.get(pair[0], ""))
		if replacement != "":
			parts.append("\n[b]%s[/b]\n%s" % [pair[1], replacement])
			continue
		var txt := String(briefing.get(pair[0], "")).strip_edges()
		if txt != "":
			parts.append("\n[b]%s[/b]\n%s" % [pair[1], txt])
	return "\n".join(parts)


## Le regole di fine e di vittoria come sono STAMPATE, ricavate dal dato di
## vittoria invece che dal testo importato.
##
## Il briefing dei quindici solitari rimandava al fascicolo - "Vedi le
## istruzioni Fine dello scenario nel file solo e nel fascicolo" - cioe'
## chiedeva di alzarsi dal tavolo proprio per la cosa che serve sapere PRIMA di
## cominciare. Il dato invece c'era gia': in `core/data/victory/` stanno la
## condizione di fine stampata con la sua pagina, la Tabella dell'Esito e i
## premi in VP.
##
## Ritorna { "end": String, "victory": String }; una chiave vuota significa
## "non trascritta", e allora il briefing tiene il testo importato.
func printed_rules_text() -> Dictionary:
	var out := {"end": "", "victory": ""}
	var ec := end_conditions()
	if not ec.is_empty():
		var lines: Array[String] = []
		var printed := String(ec.get("_text", "")).strip_edges()
		if printed != "":
			lines.append("[i]%s[/i]" % printed)
		var reasons: Array[String] = []
		for rule_v: Variant in ec.get("any", []):
			var reason := String((rule_v as Dictionary).get("reason", "")).strip_edges()
			if reason != "":
				reasons.append("  - " + reason)
		if not reasons.is_empty():
			lines.append("L'app la applica cosi':")
			lines.append_array(reasons)
		var src := String(ec.get("_source", "")).strip_edges()
		if src != "":
			lines.append("[color=#9a9a9a]%s[/color]" % src)
		out["end"] = "\n".join(lines)

	var mode_name := String(victory_data.get("mode", ""))
	var lines2: Array[String] = []
	if mode_name == "DEBRIEFING":
		lines2.append("Scenario in solitario: non si vince, si legge l'Esito. "
			+ "Si conta UN punteggio e lo si cerca nella tabella qui sotto.")
		lines2.append("")
		lines2.append("[b]Tabella dell'Esito[/b]")
		# Alcune tabelle sono due tabelle affiancate, scelte da una condizione e
		# non dal punteggio (N1: reazione norvegese adirata oppure no), con
		# soglie diverse. Stamparle di seguito senza dirlo darebbe due righe
		# "8 o piu'" e "6 o piu'" che sembrerebbero in conflitto.
		var variant := ""
		for row_v: Variant in victory_data.get("debriefing", []):
			var row: Dictionary = row_v
			var this_variant := String(row.get("variant", ""))
			if this_variant != variant:
				variant = this_variant
				lines2.append("  [i]%s[/i]" % (variant if variant != ""
					else "altrimenti:"))
			# `str()` su un numero JSON stampa "10.0": la soglia di una tabella
			# di Esito e' un punteggio, non una misura.
			var threshold := "%d o piu'" % int(row["min"]) if row.has("min") \
				else "sotto"
			# N5 e' l'unica tabella a due assi: dentro la riga di VP si cerca
			# ancora la banda di Punti Rinforzo spesi. Senza scriverlo, tre
			# righe con la stessa soglia sembrerebbero un errore di stampa.
			var note := String(row.get("threshold_note", ""))
			if note != "":
				threshold += ", " + note
			lines2.append("  [b]%s[/b]  %s" % [threshold, String(row.get("label", ""))])
			var text := String(row.get("text", "")).strip_edges()
			if text != "" and not text.begins_with("Testo completo della riga"):
				lines2.append("     %s" % text)
		lines2.append("")
		lines2.append(_awards_text())
		var cost := _ship_cost_text()
		if cost != "":
			lines2.append("")
			lines2.append(cost)
	elif mode_name == "VP":
		lines2.append("Si contano i Punti Vittoria; vince chi ne ha di piu'.")
		lines2.append(_awards_text())
		var tb := String((victory_data.get("tiebreak", {}) as Dictionary).get(
			"condition", "")).strip_edges()
		if tb != "":
			lines2.append("\n[b]Parita'[/b]\n%s" % tb)
	elif mode_name == "OBJECTIVES":
		lines2.append("Mini-scenario: non si contano punti, si guarda chi ha "
			+ "raggiunto il suo obiettivo.")
		var objs: Dictionary = victory_data.get("objectives", {})
		for side_key in ["ROYAL_NAVY", "KRIEGSMARINE"]:
			var o: Dictionary = objs.get(side_key, {})
			if o.is_empty():
				continue
			lines2.append("\n[b]%s[/b]" % String(o.get("label", side_key)))
			lines2.append("  Decisiva:  %s" % String(o.get("decisive", "-")))
			lines2.append("  Marginale: %s" % String(o.get("marginal", "-")))
	elif mode_name == "CONDITIONS":
		lines2.append("Questo scenario non usa i Punti Vittoria: si vince per "
			+ "condizioni, e vale la PRIMA che si verifica.")
		for c_v: Variant in victory_data.get("conditions", []):
			var c: Dictionary = c_v
			var w := String(c.get("winner", ""))
			var who := "Kriegsmarine" if w == "KRIEGSMARINE" \
				else ("Royal Navy" if w == "ROYAL_NAVY" else w)
			lines2.append("  - %s  ->  vince %s" % [String(c.get("text", "")), who])
	if not lines2.is_empty():
		out["victory"] = "\n".join(lines2)
	return out


## I premi in VP, uno per riga. Le righe che il motore non sa valutare da solo
## restano marcate: una voce "da spuntare a mano" e' un'informazione, non un
## buco - dice al giocatore che quel punto deve contarlo lui.
func _awards_text() -> String:
	var manual: Array[String] = []
	var lines: Array[String] = []
	for a_v: Variant in victory_data.get("awards", []):
		var a: Dictionary = a_v
		var label := String(a.get("label", "")).strip_edges()
		if label.begins_with("Calcolare i VP dalle tabelle stampate"):
			manual.append(label)
			continue
		var side := String(a.get("side", ""))
		var who := "KM" if side == "KRIEGSMARINE" else "RN"
		var pts := float(a.get("points", 0))
		var mark := "  [spunta a mano]" if bool(a.get("manual", false)) else ""
		lines.append("  %s  %s  %s%s" % [who, GameState.vp_str(pts), label, mark])
	if lines.is_empty():
		if manual.is_empty():
			return ""
		return ("[color=#ffcc66]I punti di questo scenario non sono ancora "
			+ "trascritti nel dato: vanno letti sulla pagina dello scenario e "
			+ "contati a mano.[/color]")
	return "[b]Punti[/b]\n" + "\n".join(lines)


## Il costo in VP delle navi schierate, quando lo scenario ne ha uno.
##
## Lo ha un solo scenario dei quindici: A2 L'Ultima Battaglia, dove la
## Kriegsmarine paga al Debriefing ogni nave che ha messo in campo, e il prezzo
## cambia con il porto da cui parte (una BB a Kiel costa 2, a Brest 5). Il
## giocatore deve poterlo leggere PRIMA di schierare, se no la scelta piu'
## importante dello scenario la fa alla cieca.
func _ship_cost_text() -> String:
	var cost: Dictionary = victory_data.get("_ship_vp_cost", {})
	if cost.is_empty():
		return ""
	var cols: Array = cost.get("columns", [])
	var ships: Dictionary = cost.get("ships", {})
	if cols.is_empty() or ships.is_empty():
		return ""
	# Una riga per nave con le colonne scritte per esteso, non incolonnate: il
	# briefing si legge in un font proporzionale, dove gli spazi non allineano
	# niente e una griglia diventa un pasticcio.
	var lines: Array[String] = ["[b]Costo in VP delle navi schierate[/b]"]
	for name_v: Variant in ships.keys():
		var cells: Array[String] = []
		var values: Array = ships[name_v]
		for i in mini(cols.size(), values.size()):
			cells.append("%s %d" % [String(cols[i]), int(values[i])])
		lines.append("  [b]%s[/b]  %s" % [String(name_v), ",  ".join(cells)])
	var rv := String(cost.get("rv_markers", "")).strip_edges()
	if rv != "":
		lines.append("  " + rv)
	var src := String(cost.get("_source", "")).strip_edges()
	if src != "":
		lines.append("[color=#9a9a9a]%s[/color]" % src)
	return "\n".join(lines)
