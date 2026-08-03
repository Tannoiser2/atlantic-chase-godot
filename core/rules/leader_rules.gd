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


static func is_implemented(name: String) -> bool:
	return ["Raeder", "Pound", "Gensoul"].has(name)


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
