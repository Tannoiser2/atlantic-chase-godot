class_name LeaderRules
extends RefCounted

## Comandanti, RB p.10. Le descrizioni restano qui accanto alla disponibilita':
## la UI puo' dire che cosa fa una pedina anche quando l'effetto non e' ancora
## automatizzato, senza trasformare una semplice presenza nel setup in una regola.

## Testo trascritto da RB p.10 (traduzione italiana, letta a 300 dpi). Non e'
## un riassunto: e' la condizione stampata, perche' e' quella che decide se il
## beneficio si puo' usare adesso.
const EFFECTS := {
	"Raeder": "Due volte: quando effettuate un'azione Passare, potete dichiararla una azione Passare Tutto.",
	"Pound": "Due volte: quando effettuate un'azione Passare, potete dichiararla una azione Passare Tutto.",
	"Lutjens": "Una volta: un tentativo di Sottrazione dell'Iniziativa ha successo automaticamente e la sua TF ottiene Manovre Evasive (se non ne ha gia' uno). La sua TF deve poi essere la TF Attiva in una azione di Completamento, Ingaggio, Ricerca Navale o Traiettoria.",
	"Krancke": "Una volta: quando la sua TF e' la TF Attiva o il bersaglio designato, tirate 2d6 e aggiungete o sottraete la somma al Totale Traiettoria. Potete tirare prima di decidere se usarlo.",
	"Marschall": "Una volta: dopo aver tirato uno o piu' dadi durante un'Azione o Battaglia, con la sua TF Attiva o sulla Mappa di Battaglia, potete sostituire uno dei numeri con un 6. Vale anche su un tiro per Meteo o Iniziativa; in quel caso la sua TF deve essere designata nell'Azione successiva.",
	"Prien": "Una volta: assegnatelo a una forza di U-Boat, che puo' effettuare la Ricognizione Furtiva in un esagono con base aerea o porto nemici.",
	"Forbes": "Una volta: dopo aver tirato uno o piu' dadi durante un'Azione o Battaglia, con la sua TF Attiva o sulla Mappa di Battaglia, potete sostituire uno dei numeri con un 6. Vale anche su un tiro per Meteo o Iniziativa; in quel caso la sua TF deve essere designata nell'Azione successiva.",
	"Gensoul": "Una volta: quando la sua Task Force e' designata quale Task Force Attiva, si puo' rimuovere un segnalino Informazioni da qualsiasi TF britannica o francese. Quella TF deve essere designata nell'Azione corrente.",
	"Somerville": "Una volta: +2 a qualsiasi tiro di dado o dadi che coinvolge la sua TF, cioe' quando e' designata in un'azione. Non vale per Meteo o Iniziativa.",
	"Tovey": "Una volta: quando la sua TF e' la TF Attiva o il bersaglio designato, tirate 2d6 e aggiungete o sottraete la somma al Totale Traiettoria. Potete tirare prima di decidere se usarlo.",
	"Walker": "Una volta: quando la sua Task Force e' la Task Force Coordinatrice, il Modificatore Comune per il Coordinamento e' +4.",
}

## Nel testo di Forbes la traduzione italiana ripete "la TF di Marschall deve
## essere designata nell'Azione successiva": e' un refuso, le due voci sono
## identiche parola per parola e quella clausola parla della TF del Comandante
## che sta usando il beneficio. Preso alla lettera, un comandante britannico
## vincolerebbe una Task Force tedesca. Qui e' trascritto come "la sua TF",
## e la discrepanza resta dichiarata invece di essere nascosta.
const FORBES_TRANSLATION_NOTE := ("RB p.10 italiano: nella voce Forbes la "
	+ "clausola finale nomina Marschall. E' un refuso di traduzione: la "
	+ "clausola vale per la TF del Comandante che usa il beneficio.")


static func effect_text(name: String) -> String:
	return String(EFFECTS.get(name, "Effetto non trascritto nel motore."))


## Quali benefici l'app offre al GIOCATORE. Forbes e Marschall valgono sul tiro
## di un'Azione; in Battaglia, sul Meteo e sull'Iniziativa non sono ancora
## offerti. Prien non e' automatizzato. L'avversario immaginario non usa nessun
## Comandante: il fascicolo solitario non dice quando lo farebbe.
static func is_implemented(name: String) -> bool:
	return ["Raeder", "Pound", "Gensoul", "Walker", "Somerville", "Krancke",
		"Tovey", "Lutjens", "Forbes", "Marschall"].has(name)


const WALKER_COORDINATION := 4
const SOMERVILLE_BONUS := 2

## I Comandanti il cui beneficio si sceglie mentre si DICHIARA un'azione su
## tabella, con la condizione stampata che lo rende disponibile.
##
## Somerville: la traduzione dice "aggiungete +2 a qualsiasi tiro che coinvolge
## la TF". Qui si offre solo a chi TIRA, cioe' alla parte Attiva: con la sua TF
## dalla parte del Bersaglio un +2 al tiro aiuterebbe l'avversario, e il testo
## non dice che diventi un -2. Quel caso resta fuori invece di essere inventato.
static func declarable(state: GameState, dec: ActionEngine.Declaration,
		side: int) -> Array[String]:
	var out: Array[String] = []
	if dec == null or side != dec.acting_side():
		return out
	if dec.active_coordinating != null and dec.active_coordinating.leader == "Walker" \
			and uses_left(state, "Walker") > 0:
		out.append("Walker")
	for tf in dec.designated_active():
		if tf.leader == "Somerville" and uses_left(state, "Somerville") > 0:
			out.append("Somerville")
			break
	return out


## Krancke o Tovey, se la loro TF e' la TF Attiva o il Bersaglio designato
## (RB p.10). Ritorna il nome, o "" se nessuno dei due e' utilizzabile da
## `side`.
static func trajectory_total_roller(state: GameState,
		dec: ActionEngine.Declaration, side: int) -> String:
	if dec == null:
		return ""
	for tf in [dec.active, dec.target]:
		if tf == null or tf.side != side:
			continue
		if ["Krancke", "Tovey"].has(tf.leader) and uses_left(state, tf.leader) > 0:
			return tf.leader
	return ""


## Forbes o Marschall, se la loro TF e' la TF Attiva dell'azione appena tirata.
static func six_replacer(state: GameState, dec: ActionEngine.Declaration) -> String:
	if dec == null or dec.active == null:
		return ""
	if ["Forbes", "Marschall"].has(dec.active.leader) \
			and uses_left(state, dec.active.leader) > 0:
		return dec.active.leader
	return ""


## Lutjens (RB p.10): "Quando effettuato un tentativo di Sottrazione
## dell'Iniziativa, ha successo automaticamente e la TF di Lutjens ottiene una
## pedina di Manovre Evasive (se non ne ha gia' uno)."
##
## Ritorna la TF di Lutjens se `side` puo' usarlo adesso, altrimenti null.
static func lutjens_force(state: GameState, side: int) -> TaskForce:
	if uses_left(state, "Lutjens") <= 0:
		return null
	for tf in state.forces_of(side):
		if tf.leader == "Lutjens" and not tf.completed:
			return tf
	return null


## Consuma i benefici dichiarati nell'azione. Lo chiama `ActionEngine.resolve`
## quando si tira davvero: un'Interruzione che annulla non brucia il Comandante.
static func spend_declared(state: GameState, dec: ActionEngine.Declaration) -> void:
	for name in dec.leader_benefits:
		spend(state, name)
	if dec.trajectory_total_shift != 0 and dec.trajectory_total_shift_by != "":
		spend(state, dec.trajectory_total_shift_by)


# ------------------------------------------------------------------ Gensoul --

## Gensoul, RB p.10: "Quando la sua Task Force e' designata quale Task Force
## Attiva, si puo' rimuovere un segnalino Informazioni da qualsiasi TF
## britannica o francese. Quella TF deve essere designata nell'Azione corrente."
##
## Il motore non ha una parte francese separata: le navi francesi stanno nella
## Royal Navy e portano la propria nazione sulla pedina. "Britannica o
## francese" copre quindi tutte le TF di quella parte, e non serve distinguere.
##
## Il momento giusto e' PRIMA di risolvere l'azione: l'Interruzione (RB p.22)
## si tira sui segnalini Informazioni delle TF designate, quindi toglierne uno
## dopo non servirebbe a niente - ed e' proprio a quello che serve il beneficio.
static func gensoul_available(state: GameState,
		dec: ActionEngine.Declaration) -> bool:
	if dec == null or dec.active == null:
		return false
	if dec.active.leader != "Gensoul":
		return false
	return uses_left(state, "Gensoul") > 0 and not gensoul_targets(dec).is_empty()


## Le TF su cui il beneficio puo' agire: designate nell'Azione corrente, della
## parte di Gensoul, e con almeno un segnalino Informazioni da togliere.
static func gensoul_targets(dec: ActionEngine.Declaration) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	if dec == null or dec.active == null:
		return out
	for tf in dec.designated_active():
		if tf.side == dec.active.side and tf.info_count() > 0:
			out.append(tf)
	return out


## Toglie un segnalino Informazioni. `segment_hex` sceglie quale, quando la
## Traiettoria ne ha piu' d'uno; con `Vector2i.MAX` si prende il primo.
## Ritorna { ok, error, hex, log }.
static func gensoul_remove_info(state: GameState, tf: TaskForce,
		segment_hex: Vector2i = Vector2i.MAX) -> Dictionary:
	var out := {"ok": false, "error": "", "hex": Vector2i.MAX,
		"log": [] as Array[String]}
	if tf == null or tf.info_count() == 0:
		out["error"] = "nessun segnalino Informazioni da rimuovere"
		return out
	if uses_left(state, "Gensoul") <= 0:
		out["error"] = "Gensoul ha gia' usato il suo beneficio"
		return out
	var traj := tf.trajectory
	for i in traj.segments.size():
		var seg: Dictionary = traj.segments[i]
		if not bool(seg["info"]):
			continue
		if segment_hex != Vector2i.MAX and seg["hex"] != segment_hex:
			continue
		traj.set_info(i, false)
		spend(state, "Gensoul")
		out["ok"] = true
		out["hex"] = seg["hex"]
		(out["log"] as Array[String]).append(("Gensoul: rimosso il segnalino "
			+ "Informazioni da %s in %s. Il beneficio vale una volta per scenario.")
			% [tf.display_name(), str(seg["hex"])])
		return out
	# Ci si arriva solo chiedendo un segmento che non ha Informazioni: meglio
	# dirlo che togliere il segnalino da un altro segmento a caso.
	out["error"] = "%s non ha un segnalino Informazioni in %s" \
		% [tf.display_name(), str(segment_hex)]
	return out


static func has_commander(state: GameState, name: String, side: int) -> bool:
	if state.commanders.has(name):
		return (name == "Raeder" and side == TaskForce.Side.KRIEGSMARINE) \
			or (name == "Pound" and side == TaskForce.Side.ROYAL_NAVY)
	for tf in state.task_forces:
		if tf.side == side and tf.leader == name:
			return true
	return false


static func pass_all_commander(state: GameState, side: int) -> String:
	var name := "Raeder" if side == TaskForce.Side.KRIEGSMARINE else "Pound"
	if has_commander(state, name, side) and uses_left(state, name) > 0:
		return name
	return ""


static func uses_left(state: GameState, name: String) -> int:
	var maximum := 2 if ["Raeder", "Pound"].has(name) else 1
	return maxi(0, maximum - int(state.commander_uses.get(name, 0)))


static func spend(state: GameState, name: String) -> bool:
	if uses_left(state, name) <= 0:
		return false
	state.commander_uses[name] = int(state.commander_uses.get(name, 0)) + 1
	state.changed.emit()
	return true
