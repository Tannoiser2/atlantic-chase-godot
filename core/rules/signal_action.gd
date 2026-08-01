class_name SignalAction
extends RefCounted

## Azione Segnalazione (RB p.39): inchiodare una Traiettoria nemica.
##
## E' l'azione che trasforma un sospetto in una posizione. Il bersaglio deve
## essere una Traiettoria nemica con almeno un segnalino Informazioni: si sceglie
## uno di quei segnalini, e l'intera Traiettoria collassa in una Stazione
## nell'esagono di quel segnalino. Tutto il resto - gli altri segmenti, gli altri
## segnalini Informazioni - sparisce.
##
## Non serve avere una Task Force o una forza Furtiva nell'esagono bersaglio: la
## Segnalazione e' intelligence, non ricognizione. E' anche il motivo per cui
## costa: al termine il giocatore Inattivo riceve un'opportunita' di Sottrarre
## l'Iniziativa, e il fascicolo lo commenta con una domanda che vale tutta la
## regola - "per quanto tempo questa informazione rimarra' valida?".
##
## Il nome della classe NON e' `Signal`: Godot ha gia' un tipo `Signal`, e
## ridefinirlo fa fallire il parser in modo silenzioso, senza messaggio.


## Gli esagoni in cui questa Traiettoria puo' essere inchiodata: quelli dei suoi
## segnalini Informazioni. Vuoto = la Segnalazione non e' dichiarabile contro
## questa Task Force.
static func target_hexes(tf: TaskForce) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if tf == null or tf.trajectory.is_station():
		return out
	for s in tf.trajectory.segments:
		if bool(s.get("info", false)):
			out.append(s["hex"] as Vector2i)
	return out


## I bersagli legali fra le Task Force avversarie.
static func candidates(state: GameState, active_side: int) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in state.forces_of(1 - active_side):
		if not tf.ships.is_empty() and not target_hexes(tf).is_empty():
			out.append(tf)
	return out


## Perche' la Segnalazione non e' dichiarabile contro questo bersaglio.
static func refusal(target: TaskForce) -> String:
	if target == null:
		return "questa azione richiede una Task Force Bersaglio"
	if target.ships.is_empty():
		return "la Task Force bersaglio non ha navi"
	if target.trajectory.is_station():
		return "il bersaglio e' gia' una Stazione"
	if target_hexes(target).is_empty():
		return ("il bersaglio non ha nessun segnalino Informazioni: "
			+ "senza, non c'e' niente da segnalare")
	return ""


## Risolve la Segnalazione: la Traiettoria bersaglio diventa una Stazione
## nell'esagono scelto.
##
## Il segnalino Contatto del segmento bersaglio si trasferisce alla Stazione;
## quelli sugli altri segmenti si perdono insieme ai segmenti. E' la differenza
## fra sapere dove una flotta e' passata e sapere dove si trova.
##
## Ritorna { ok, error, hex, contact, removed_segments, log }.
static func resolve(target: TaskForce, at: Vector2i) -> Dictionary:
	var out := {"ok": false, "error": "", "hex": at, "contact": false,
		"removed_segments": 0, "log": [] as Array[String]}
	var why := refusal(target)
	if why != "":
		out["error"] = why
		return out
	if not target_hexes(target).has(at):
		out["error"] = "in %s non c'e' nessun segnalino Informazioni del bersaglio" % str(at)
		return out

	var traj := target.trajectory
	var keep_contact := false
	for s in traj.segments:
		if (s["hex"] as Vector2i) == at and bool(s.get("contact", false)):
			keep_contact = true
	var removed := traj.segments.size()

	traj.become_station(at)
	traj.station_contact = keep_contact

	out["ok"] = true
	out["contact"] = keep_contact
	out["removed_segments"] = removed
	var lines: Array[String] = ["Segnalazione: %s e' localizzata in %s. "
		% [target.display_name(), str(at)]
		+ "La Traiettoria (%d segmenti) e gli altri segnalini Informazioni "
			% removed + "sono rimossi."]
	if keep_contact:
		lines.append("  Il segnalino Contatto passa alla Stazione.")
	out["log"] = lines
	return out
