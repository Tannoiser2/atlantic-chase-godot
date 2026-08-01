class_name Victory
extends RefCounted

## Punti Vittoria e assegnazione della vittoria.
##
## In Atlantic Chase la vittoria non ha una regola sola: ogni scenario porta la
## sua, e leggendo tutti e tre i fascicoli vengono fuori TRE modelli diversi.
## Il motore li tiene distinti invece di forzarli in uno:
##
##   VP          le nove Operazioni tranne la prima: si contano i punti e vince
##               chi ne ha di piu', con una clausola di parita' per scenario.
##   CONDITIONS  Op1 Homecoming non ha nessuna tabella VP: e' un elenco di
##               condizioni ("se il Bremen Completa a Kiel vincono i tedeschi").
##               Contare punti qui sarebbe inventarsi una regola che non c'e'.
##   DEBRIEFING  gli scenari in solitario non si vincono e non si perdono. Si
##               conta un punteggio - UNO SOLO, quello del giocatore, non due
##               contrapposti - e lo si cerca in una tabella di Esiti a soglie:
##               in BL1, 6 o piu' e' "Raiders Triumphant!", da -3 in giu' e'
##               "Raeder e' sollevato dal comando". `solo_side` dice di chi e'
##               quel punteggio.
##
## La tabella sta in core/data/victory/<nome>.json - file separato dallo
## scenario, che invece e' generato dal .vsav: cosi' una rigenerazione non
## cancella una trascrizione fatta a mano.
##
## Schema di un premio:
##   { "side": "ROYAL_NAVY", "event": "SHIP_SUNK",
##     "match": {"names": ["Bismarck"], "nations": ["GE"]}, "points": 7 }
##
## Il filtro `match` accetta names, types, nations, exclude_names, destination,
## damaged e dispersed. Servono tutti: senza `nations` il premio tedesco per una
## corazzata britannica affondata scatterebbe anche sul Bismarck, che e' una
## corazzata; senza `exclude_names` il Bismarck prenderebbe sia la sua riga sia
## quella generica delle corazzate, e la tabella dice "non il Bismarck".
##
## `points` e' in virgola mobile perche' cinque tabelle su nove assegnano MEZZO
## punto per un incrociatore britannico affondato, e puo' essere NEGATIVO (in
## Op3 il britannico perde 1 punto se non ha minato Narvik o Trondheim).
##
## `manual: true` marca i premi che il motore non sa vedere da solo: le mine
## posate, il marcatore Base Aerea, "la TF dell'Hipper ha eseguito un'azione
## Traiettoria", la zona di sicurezza USA. Non vengono assegnati in automatico;
## finiscono in un elenco che i giocatori spuntano a fine scenario. Meglio una
## domanda esplicita che un punteggio inventato.
##
## `tiebreak.auto` false significa lo stesso: la condizione e' scritta a parole
## e la verificano i giocatori.

enum Mode { VP, CONDITIONS, DEBRIEFING }

enum Event { SHIP_DAMAGED, SHIP_SUNK, SHIP_HIT, CONVOY_COMPLETED, HIT_ON_CONVOY,
	SHIP_COMPLETED, CUSTOM }

const EVENT_NAMES := {
	"SHIP_DAMAGED": Event.SHIP_DAMAGED,
	"SHIP_SUNK": Event.SHIP_SUNK,
	"SHIP_HIT": Event.SHIP_HIT,
	"CONVOY_COMPLETED": Event.CONVOY_COMPLETED,
	"HIT_ON_CONVOY": Event.HIT_ON_CONVOY,
	"SHIP_COMPLETED": Event.SHIP_COMPLETED,
	"CUSTOM": Event.CUSTOM,
}

const MODE_NAMES := {
	"VP": Mode.VP,
	"CONDITIONS": Mode.CONDITIONS,
	"DEBRIEFING": Mode.DEBRIEFING,
}

var mode: int = Mode.VP
var awards: Array[Dictionary] = []
var tiebreak: Dictionary = {}
var conditions: Array = []
var debriefing: Array = []
var has_table: bool = false
var notes: Array = []

## Solo in modalita' DEBRIEFING: di chi e' il punteggio che si legge sulla
## tabella degli Esiti. Nel solitario si comanda una parte sola.
var solo_side: int = TaskForce.Side.KRIEGSMARINE


static func from_scenario(sc: Scenario) -> Victory:
	var v := Victory.new()
	var d: Dictionary = sc.victory_data
	v.mode = int(MODE_NAMES.get(String(d.get("mode", "VP")), Mode.VP))
	v.notes = d.get("notes", [])
	v.tiebreak = d.get("tiebreak", {})
	v.conditions = d.get("conditions", [])
	v.debriefing = d.get("debriefing", [])
	v.solo_side = TaskForce.Side.ROYAL_NAVY \
		if String(d.get("solo_side", "KRIEGSMARINE")) == "ROYAL_NAVY" \
		else TaskForce.Side.KRIEGSMARINE
	for a_v: Variant in d.get("awards", []):
		var a: Dictionary = a_v
		v.awards.append({
			"side": TaskForce.Side.KRIEGSMARINE if String(a.get("side", "")) == "KRIEGSMARINE"
				else TaskForce.Side.ROYAL_NAVY,
			"event": EVENT_NAMES.get(String(a.get("event", "CUSTOM")), Event.CUSTOM),
			"match": a.get("match", {}),
			"points": float(a.get("points", 0.0)),
			"label": String(a.get("label", "")),
			"manual": bool(a.get("manual", false)),
			"once": bool(a.get("once", false)),
		})
	v.has_table = not (v.awards.is_empty() and v.conditions.is_empty()
		and v.debriefing.is_empty())
	return v


## La nave corrisponde al filtro? Un filtro vuoto vale per qualunque nave.
##
## `context` porta i dati che non stanno sulla nave: per il Completamento, il
## paese o il porto di destinazione; per un convoglio, se e' disperso. Il valore
## di un Completamento dipende da dove arriva la nave e da come ci arriva: nella
## Rheinubung il Bismarck vale 3 VP se completa in Francia e 0 in Germania, ma
## se e' danneggiato vale 2 in Francia e 3 in Germania - riportarlo a casa
## conciato vale piu' che perderlo.
##
## `ship` puo' essere null: i premi per convoglio non hanno una nave dietro (il
## convoglio non e' nel ruolino). In quel caso i filtri che interrogano la nave
## non possono essere verificati, quindi il premio NON scatta: un premio scritto
## per una nave precisa non deve cadere addosso a un convoglio per distrazione.
static func _matches(ship: Ship, m: Dictionary,
		context: Dictionary = {}) -> bool:
	if m.is_empty():
		return true
	# --- filtri che vivono nel contesto, validi anche senza nave ---
	var dest := String(context.get("destination", ""))
	if m.has("destination"):
		if dest != String(m["destination"]):
			return false
	# `destinations` e' l'elenco delle mete che valgono: "3 punti a Murmansk o
	# Archangel"; `exclude_destinations` e' la riga complementare, "2 punti in
	# un altro porto", che vale ovunque TRANNE quelle.
	if m.has("destinations"):
		var okd := false
		for d_v: Variant in m["destinations"]:
			if dest == String(d_v):
				okd = true
		if not okd:
			return false
	if m.has("exclude_destinations"):
		if dest == "":
			return false
		for d_v: Variant in m["exclude_destinations"]:
			if dest == String(d_v):
				return false
	if m.has("dispersed"):
		if bool(m["dispersed"]) != bool(context.get("dispersed", false)):
			return false
	# CHI CONTROLLA il pezzo, che non e' la sua nazionalita'. Serve in due casi
	# che la nazione non sa distinguere:
	#  - i convogli non stanno nel ruolino navi, quindi non hanno nazione: in
	#    Op3 il britannico prende 1 punto per ogni Colpo su un convoglio
	#    TEDESCO e il tedesco per ogni Colpo su uno BRITANNICO, e senza questo
	#    filtro i due premi si scambierebbero;
	#  - nella Rheinubung la tabella dice "navi tedesche o francesi controllate
	#    dal tedesco" da una parte e "britanniche o francesi controllate dal
	#    britannico" dall'altra. Con la Variante Francese le navi francesi sono
	#    in gioco su ENTRAMBI i lati, quindi la bandiera non basta: conta chi
	#    ha la Task Force.
	# Valori: "KRIEGSMARINE" / "ROYAL_NAVY".
	if m.has("owner"):
		if String(context.get("owner", "")) != String(m["owner"]):
			return false
	# --- filtri che interrogano la nave ---
	var wants_ship: bool = m.has("damaged") or m.has("exclude_names") \
		or m.has("names") or m.has("types") or m.has("nations") \
		or m.has("exclude_types")
	if ship == null:
		return not wants_ship
	if m.has("damaged"):
		if bool(m["damaged"]) != ship.damaged:
			return false
	# le righe generiche escludono le navi che hanno una riga propria: la
	# tabella della Rheinubung lo scrive nero su bianco ("non il Bismarck")
	if m.has("exclude_names"):
		for n_v: Variant in m["exclude_names"]:
			if ship.name.to_lower() == String(n_v).to_lower():
				return false
	if m.has("names"):
		var ok := false
		for n_v: Variant in m["names"]:
			if ship.name.to_lower() == String(n_v).to_lower():
				ok = true
		if not ok:
			return false
	if m.has("types"):
		var ok2 := false
		for t_v: Variant in m["types"]:
			if ship.type_code == String(t_v):
				ok2 = true
		if not ok2:
			return false
	# "ogni ALTRA nave tedesca": la riga generica di Op2 vale per tutto quello
	# che non e' un incrociatore da battaglia, che ha gia' la sua riga
	if m.has("exclude_types"):
		for t_v: Variant in m["exclude_types"]:
			if ship.type_code == String(t_v):
				return false
	if m.has("nations"):
		var ok3 := false
		for n_v: Variant in m["nations"]:
			if ship.nation == String(n_v):
				ok3 = true
		if not ok3:
			return false
	return true


## Punti che un evento assegna, e a chi. I premi `manual` restano fuori: li
## assegnano i giocatori a fine scenario (vedi manual_awards).
## Ritorna un Array di { "side": int, "points": float, "label": String }.
func awards_for(event: int, ship: Ship,
		context: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in awards:
		if int(a["event"]) != event:
			continue
		if bool(a["manual"]):
			continue
		if not _matches(ship, a["match"], context):
			continue
		out.append({"side": int(a["side"]), "points": float(a["points"]),
			"label": String(a["label"]), "once": bool(a["once"])})
	return out


## Chiavi di `match` che si leggono nel contesto e non sulla nave.
const CONTEXT_KEYS := ["destination", "destinations", "exclude_destinations",
	"dispersed", "owner"]


## Premi che questo evento POTREBBE far scattare, ma che restano fermi perche'
## chi ha chiamato non ha passato un dato necessario (tipicamente `owner`, cioe'
## chi controlla il pezzo). Serve a non perdere punti in silenzio: un premio che
## non scatta perche' la nave non corrisponde e' corretto, uno che non scatta
## perche' manca un'informazione e' un bug, e i due casi vanno distinti.
func unevaluated(event: int, ship: Ship,
		context: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in awards:
		if int(a["event"]) != event or bool(a["manual"]):
			continue
		var m: Dictionary = a["match"]
		var missing: Array[String] = []
		for k in CONTEXT_KEYS:
			if m.has(k) and not context.has(k):
				missing.append(k)
		if missing.is_empty():
			continue
		# il premio deve fallire SOLO per quello: se non corrisponde comunque
		# (nave sbagliata) non c'e' niente da segnalare
		var relaxed := m.duplicate()
		for k in missing:
			relaxed.erase(k)
		if _matches(ship, relaxed, context):
			out.append({"label": String(a["label"]), "missing": missing})
	return out


## I premi che il motore non sa valutare da solo, da spuntare a fine partita.
func manual_awards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in awards:
		if bool(a["manual"]):
			out.append({"side": int(a["side"]), "points": float(a["points"]),
				"label": String(a["label"])})
	return out


## Applica a GameState i VP di un evento. Ritorna le righe da mettere nel log.
func apply_event(state: GameState, event: int, ship: Ship = null,
		detail: String = "", context: Dictionary = {}) -> Array[String]:
	var lines: Array[String] = []
	for a in awards_for(event, ship, context):
		var pts := float(a["points"])
		if is_zero_approx(pts):
			continue
		# "il PRIMO Completamento tedesco riuscito a Bergen": vale una volta
		# sola, il secondo non porta niente. Il fatto che sia gia' scattato sta
		# in GameState e non qui, cosi' sopravvive a un salvataggio.
		if bool(a["once"]):
			var key := String(a["label"])
			if state.vp_once.has(key):
				continue
			state.vp_once.append(key)
		state.add_vp(int(a["side"]), pts)
		var who := "Kriegsmarine" if int(a["side"]) == TaskForce.Side.KRIEGSMARINE \
			else "Royal Navy"
		var what := String(a["label"])
		if what == "":
			what = ship.name if ship != null else detail
		var sign_txt := "+" if pts > 0.0 else ""
		lines.append("VP: %s%s a %s  (%s)"
			% [sign_txt, GameState.vp_str(pts), who, what])
	for u in unevaluated(event, ship, context):
		lines.append("VP non assegnati - manca %s: %s"
			% [", ".join(u["missing"]), String(u["label"])])
	return lines


## La riga della tabella degli Esiti raggiunta con questo punteggio.
##
## Le righe sono ordinate dalla migliore alla peggiore e ognuna ha una soglia
## `min`: si scende finche' il punteggio la raggiunge. L'ultima riga fa da
## fondo ("-3 o meno"), quindi non ha soglia. Ritorna {} se la tabella non c'e'.
func debriefing_row(score: float) -> Dictionary:
	for r_v: Variant in debriefing:
		var r: Dictionary = r_v
		if not r.has("min") or score >= float(r["min"]):
			return r
	return {}


## Esito finale. Ritorna:
##   { "mode": int, "km": float, "rn": float, "winner": int (-1 = da risolvere),
##     "tie": bool, "tiebreak_text": String, "resolved": bool }
## `resolved` false significa che l'ultima parola spetta ai giocatori: parita'
## da sciogliere a mano, scenario a condizioni, oppure debriefing.
func outcome(state: GameState) -> Dictionary:
	var km := state.vp_of(TaskForce.Side.KRIEGSMARINE)
	var rn := state.vp_of(TaskForce.Side.ROYAL_NAVY)
	var out := {"mode": mode, "km": km, "rn": rn,
		"tie": is_equal_approx(km, rn), "resolved": true, "winner": -1,
		"tiebreak_text": String(tiebreak.get("condition", ""))}
	if mode == Mode.DEBRIEFING:
		# nel solitario non c'e' un vincitore: c'e' un punteggio e una riga
		out["tie"] = false
		out["winner"] = -1
		out["score"] = state.vp_of(solo_side)
		var row := debriefing_row(float(out["score"]))
		out["row"] = row
		out["resolved"] = not row.is_empty()
		return out
	if mode != Mode.VP:
		# senza tabella VP il punteggio non decide niente
		out["resolved"] = false
		out["tie"] = false
		return out
	if km > rn:
		out["winner"] = TaskForce.Side.KRIEGSMARINE
	elif rn > km:
		out["winner"] = TaskForce.Side.ROYAL_NAVY
	else:
		# parita': decide la clausola dello scenario, che quasi sempre e'
		# scritta a parole e la verificano i giocatori
		out["resolved"] = bool(tiebreak.get("auto", false))
		if out["resolved"]:
			out["winner"] = TaskForce.Side.KRIEGSMARINE \
				if String(tiebreak.get("side", "")) == "KRIEGSMARINE" \
				else TaskForce.Side.ROYAL_NAVY
	return out


func describe(state: GameState) -> String:
	var lines: Array[String] = []
	match mode:
		Mode.CONDITIONS:
			lines.append("Questo scenario non usa i Punti Vittoria: "
				+ "si vince per condizioni.")
			for c_v: Variant in conditions:
				var c: Dictionary = c_v
				var w := String(c.get("winner", ""))
				var who := "Kriegsmarine" if w == "KRIEGSMARINE" \
					else ("Royal Navy" if w == "ROYAL_NAVY" else w)
				lines.append("  - %s -> vince %s" % [String(c.get("text", "")), who])
		Mode.DEBRIEFING:
			var o3 := outcome(state)
			lines.append("Scenario in solitario: non si vince, si legge "
				+ "l'esito.")
			lines.append("Punteggio: %s" % GameState.vp_str(float(o3["score"])))
			var row: Dictionary = o3["row"]
			if row.is_empty():
				lines.append("(tabella degli Esiti non trascritta)")
			else:
				lines.append("-> %s" % String(row.get("label", "")))
				lines.append("   " + String(row.get("text", "")))
		_:
			var o := outcome(state)
			lines.append("Punti Vittoria - Kriegsmarine %s, Royal Navy %s"
				% [GameState.vp_str(o["km"]), GameState.vp_str(o["rn"])])
			if not o["tie"]:
				lines.append("Vince %s." % ("la Kriegsmarine"
					if int(o["winner"]) == TaskForce.Side.KRIEGSMARINE
					else "la Royal Navy"))
			elif o["resolved"]:
				lines.append("Parita': per la regola dello scenario vince %s."
					% ("la Kriegsmarine"
						if int(o["winner"]) == TaskForce.Side.KRIEGSMARINE
						else "la Royal Navy"))
			else:
				lines.append("Parita'. Decide la clausola dello scenario:")
				lines.append("  " + String(o["tiebreak_text"]))
			if not has_table:
				lines.append("(tabella VP non trascritta per questo scenario: "
					+ "i punti vanno contati a mano dal fascicolo)")
	var manual := manual_awards()
	if not manual.is_empty():
		lines.append("Da verificare a mano prima di chiudere il conto:")
		for m in manual:
			var who2 := "Kriegsmarine" if int(m["side"]) == TaskForce.Side.KRIEGSMARINE \
				else "Royal Navy"
			lines.append("  [ ] %s  (%s a %s)" % [String(m["label"]),
				GameState.vp_str(float(m["points"])), who2])
	return "\n".join(lines)
