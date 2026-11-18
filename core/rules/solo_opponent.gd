class_name SoloOpponent
extends RefCounted

## L'avversario immaginario del modo solitario.
##
## Non e' un bot e non prova a esserlo. Il fascicolo in solitario non chiede al
## giocatore di simulare un avversario intelligente: gli da' delle TABELLE, e
## quelle decidono. Si tira un dado, si legge la casella, si esegue la
## procedura. Dove la procedura e' ambigua - "scegli la Task Force piu' vicina",
## "evita i porti nemici se possibile" - il fascicolo dice esplicitamente di
## usare il proprio giudizio.
##
## Quindi questa classe fa tre cose e nessuna di piu':
##
##   1. sceglie la tabella giusta (Presto o Tardi) e la riga giusta;
##   2. tira, applica i modificatori e legge la casella;
##   3. mostra la procedura per esteso, con le parole del fascicolo.
##
## Quello che NON fa: scegliere per il giocatore. Automatizzare "la TF piu'
## vicina" sembra facile finche' non ci si accorge che "vicina" a volte vuol
## dire in esagoni e a volte in segmenti di Traiettoria, e che il fascicolo
## aggiunge "se possibile" a meta' delle condizioni. Un avversario che decide
## male in silenzio e' peggio di uno che chiede.

## La partita passa da una tabella all'altra: il fascicolo di BL2 dice di
## cominciare con la "Presto" e passare alla "Tardi" dopo che c'e' stata una
## Battaglia, o un Convoglio e' stato distrutto, o qualcuno ha eseguito un
## Attacco Aereo.
enum Phase { EARLY, LATE }

var scenario_id: String = ""
var tables: Dictionary = {}          ## id -> SoloTable
var phase: int = Phase.EARLY

## Perche' si e' passati alla tabella "Tardi". Serve nel registro: la
## transizione e' un momento importante della partita e va spiegata.
var phase_reason: String = ""


## L'avversario immaginario tenta SEMPRE di Sottrarre l'Iniziativa, senza
## tirare il dado di p.2. Lo stampano tre scenari, ognuno a parole sue (N1
## p.17, N4 p.28, N5 p.32); il dato sta nel file dello scenario, sotto
## `seize_initiative`, con la frase e la pagina.
var always_seizes: bool = false
var always_seizes_source: String = ""


static func from_dict(d: Dictionary) -> SoloOpponent:
	var o := SoloOpponent.new()
	o.scenario_id = String(d.get("_scenario", ""))
	var seize: Dictionary = d.get("seize_initiative", {})
	o.always_seizes = bool(seize.get("always_attempt", false))
	o.always_seizes_source = String(seize.get("source", ""))
	for t_v: Variant in d.get("tables", []):
		var t := SoloTable.from_dict(t_v)
		o.tables[t.id] = t
	return o


static func load_for(scenario_id: String) -> SoloOpponent:
	var path := "res://core/data/solo/%s.json" % scenario_id
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)


func has(table_id: String) -> bool:
	return tables.has(table_id)


func table(table_id: String) -> SoloTable:
	return tables.get(table_id, null)


func set_phase(new_phase: int, reason: String = "") -> void:
	phase = Phase.LATE if new_phase == Phase.LATE else Phase.EARLY
	phase_reason = reason if phase == Phase.LATE else ""


## Quale tabella decide la prossima azione dell'avversario immaginario.
## Alcuni scenari della seconda edizione non la chiamano genericamente
## "Actions", ma "British Actions": e' comunque la Tabella delle Azioni.
func action_table_id() -> String:
	var tid := "actions_late" if phase == Phase.LATE else "actions_early"
	if has(tid):
		return tid
	if has("actions"):
		return "actions"
	if has("british_actions"):
		return "british_actions"
	return ""


## Passa alla tabella "Tardi". Idempotente: si passa una volta sola.
func go_late(reason: String) -> bool:
	if phase == Phase.LATE:
		return false
	phase = Phase.LATE
	phase_reason = reason
	return true


## Inneschi stampati delle quattro tabelle Presto/Tardi (AC Solo scenarios
## 2022 pp.10, 13, 18, 22). Tenerli nel core evita che la UI decida una regola.
func goes_late_after(event: String) -> bool:
	var prefix := scenario_id.get_slice(" ", 0)
	var triggers := {
		"BL2": ["battle", "convoy_destroyed", "air_strike"],
		"BL3": ["battle", "air_strike"],
		"N1": ["battle", "result_i"],
		"N2": ["battle", "stealth_attack", "aggressive_reaction"],
	}
	return triggers.has(prefix) and (triggers[prefix] as Array).has(event)


## Quale numero sceglie la RIGA della Tabella delle Azioni.
##
## Non e' la stessa quantita' in tutti gli scenari, ed e' una regola stampata,
## non una comodita' dell'interfaccia: per questo sta qui e non nella GUI.
##
##   BL2 Presto  "Number of successful British Completion actions"
##               (AC Solo scenarios 2022 p.10). Il britannico e' il GIOCATORE.
##   BL1         "Number of successful British Convoy Completion actions and/or
##               destroyed Convoys" (p.7). Qui il britannico e' l'avversario
##               IMMAGINARIO, quindi contano i suoi Completamenti di Convoglio
##               piu' i Convogli britannici distrutti dal giocatore tedesco.
##   Tardi       la riga e' il meteo, non un conteggio.
##
## La versione precedente usava sempre i Completamenti del giocatore: in BL1
## contava quelli tedeschi, cioe' quasi sempre zero, e la tabella restava
## inchiodata alla prima riga per tutta la partita.
func action_row_selector(state: GameState, player_side: int,
		table_id: String = "") -> int:
	var tid := table_id if table_id != "" else action_table_id()
	if tid == "actions_late":
		return state.weather
	var imaginary := 1 - player_side
	if scenario_id.begins_with("BL1"):
		return state.convoys_completed_for(imaginary) \
			+ state.sunk_count(imaginary, true)
	return state.convoys_completed_for(player_side) if player_side >= 0 \
		else state.convoys_completed


## Etichetta leggibile del selettore, per il registro e il pannello di stato.
func action_row_selector_label(state: GameState, player_side: int,
		table_id: String = "") -> String:
	var tid := table_id if table_id != "" else action_table_id()
	if tid == "actions_late":
		return "meteo %s" % ("cattivo" if state.weather == TimeLapse.Weather.BAD
			else "buono")
	var value := action_row_selector(state, player_side, tid)
	if scenario_id.begins_with("BL1"):
		return "%d Completamenti di Convoglio britannici e Convogli distrutti" % value
	# "1 Completamenti riusciti" si leggeva in ogni partita.
	return "%d Completamento riuscito" % value if value == 1 \
		else "%d Completamenti riusciti" % value


## L'azione dell'avversario immaginario, letta sulla tabella giusta.
##
## `selector` e' quello che sceglie la riga: lo produce `action_row_selector`.
##
## Ritorna il risultato di SoloTable.roll_and_read piu' `table` e `phase`.
func act(rng: DiceRNG, selector: int,
		active_modifiers: Array = []) -> Dictionary:
	var tid := action_table_id()
	var t: SoloTable = table(tid)
	if t == null:
		return {"ok": false, "error":
			"lo scenario %s non ha una Tabella delle Azioni trascritta"
			% scenario_id, "table": tid}
	var out := t.roll_and_read(rng, selector, active_modifiers)
	out["table"] = tid
	out["phase"] = phase
	return out


## Identifica una Task Force finora sconosciuta.
##
## Il fascicolo dice che alcune caselle vanno rimpiazzate a seconda di cosa c'e'
## gia' in gioco ("se ci sono gia' due CA, sostituisci con un BC"): quelle
## sostituzioni le fa il giocatore, e sono riportate nella nota della tabella.
func identify(rng: DiceRNG, tf: TaskForce) -> Dictionary:
	if not has("identify"):
		return {"ok": false, "error":
			"lo scenario %s non ha la tabella di Identificazione" % scenario_id}
	if tf != null and not tf.unidentified:
		return {"ok": false, "error": "%s e' gia' identificata" % tf.display_name()}
	var out := (table("identify") as SoloTable).roll_and_read(rng, 0)
	out["task_force"] = tf.display_name() if tf != null else ""
	return out



## Sottrarre l'Iniziativa o prendere Manovre Evasive?
##
## AC Solo scenarios 2022 p.2, riquadro "Evasive Maneuvers": "When the imaginary
## opponent has the choice between attempting to Seize Initiative or take an
## Evasive Maneuvers marker, make the decision by rolling a die: If 1-4, it
## attempts to Seize Initiative, and if 5-6 it takes the Evasive Maneuvers
## marker (attach it to a TF with a Convoy, or if no Convoy in play, to a TF
## with a Damaged ship; and if none of those are in play, on any TF). If all TFs
## already have an Evasive Maneuvers marker (or if no TFs are in play), it
## attempts to Seize Initiative."
##
## E subito sotto: "When to use an Evasive Maneuvers Marker? As soon as
## possible. If the imaginary player has the option to use it, it does so."
## Quindi, quando tenta, spende sul tiro un segnalino che ha gia'.
##
## Prima di questa funzione l'avversario immaginario tentava SEMPRE, e i
## segnalini Manovre Evasive non li prendeva ne' li spendeva mai.
##
## Ritorna:
##   attempt     true = tenta di Sottrarre
##   evasive_to  la TF che riceve il segnalino (se non tenta)
##   spend_from  la TF che spende il proprio segnalino sul tiro (se tenta)
##   log         le righe da mettere nel registro
func steal_choice(state: GameState, imaginary_side: int) -> Dictionary:
	var out := {"attempt": true, "evasive_to": null, "spend_from": null,
		"log": [] as Array[String]}
	var own: Array[TaskForce] = []
	for tf in state.forces_of(imaginary_side):
		if not tf.completed:
			own.append(tf)
	var free: Array[TaskForce] = []
	for tf in own:
		if not tf.evasive:
			free.append(tf)
	if always_seizes:
		out["log"].append("L'avversario immaginario tenta sempre di Sottrarre (%s)."
			% always_seizes_source)
	elif free.is_empty():
		out["log"].append("Nessuna TF puo' ricevere Manovre Evasive: "
			+ "l'avversario immaginario tenta di Sottrarre (p.2).")
	else:
		var die := state.rng.d6("Sottrarre o Manovre Evasive (solitario p.2)")
		if die >= 5:
			var chosen := evasive_recipient(free)
			out["attempt"] = false
			out["evasive_to"] = chosen
			out["log"].append("Sottrarre o Manovre Evasive: 1d6 = %d -> prende "
				% die + "Manovre Evasive su %s (p.2)." % chosen.display_name())
			return out
		out["log"].append("Sottrarre o Manovre Evasive: 1d6 = %d -> tenta di "
			% die + "Sottrarre (p.2).")
	out["spend_from"] = evasive_holder(state, imaginary_side)
	return out


## A quale TF va il segnalino: una con un Convoglio, altrimenti una con una nave
## Danneggiata, altrimenti una qualsiasi. A parita' la prima per id: il
## fascicolo non lo dice, e serve un criterio stabile perche' la stessa partita
## con lo stesso seme faccia la stessa scelta.
static func evasive_recipient(free: Array[TaskForce]) -> TaskForce:
	var sorted := free.duplicate()
	sorted.sort_custom(func(a: TaskForce, b: TaskForce) -> bool: return a.id < b.id)
	for tf: TaskForce in sorted:
		if Convoy.has_convoy(tf):
			return tf
	for tf: TaskForce in sorted:
		for ship in tf.afloat_ships():
			if ship.damaged:
				return tf
	return sorted[0] if not sorted.is_empty() else null


## La TF dell'avversario immaginario che spende il proprio segnalino Manovre
## Evasive appena puo' ("as soon as possible", p.2). null se nessuna ne ha.
static func evasive_holder(state: GameState, side: int) -> TaskForce:
	var best: TaskForce = null
	for tf in state.forces_of(side):
		if tf.completed or not tf.evasive:
			continue
		if best == null or tf.id < best.id:
			best = tf
	return best


## Sfuggire (Interruzione) quando a scegliere e' l'avversario immaginario.
## RB p.22 e p.54: "Quando il giocatore immaginario ottiene un risultato 'S'
## Sfuggire, tirate un dado per definire la scelta del non giocatore: 1-4 =
## azione Segnalazione, 5-6 = Manovre Evasive".
##
## Prima la scelta veniva chiesta al GIOCATORE anche quando l'Inattivo era il
## bot, e nel ciclo headless non si faceva affatto.
static func slip_away_choice(rng: DiceRNG) -> Dictionary:
	var die := rng.d6("Sfuggire: scelta dell'avversario immaginario")
	return {"die": die, "choice": "signal" if die <= 4 else "evasive"}


## Applica Sfuggire per conto dell'avversario immaginario e ritorna le righe
## per il registro.
##
## La Segnalazione "inaspettata" puo' colpire solo la TF Attiva o una
## Coordinatrice (RB p.54), e solo dove hanno un segnalino Informazioni. Se il
## dado dice Segnalazione ma l'unico segnalino sta sulla TF di Supporto Aereo,
## non c'e' un bersaglio legale: resta l'altra meta' della scelta, le Manovre
## Evasive alla TF Bersaglio.
static func apply_slip_away(state: GameState,
		dec: ActionEngine.Declaration) -> Array[String]:
	var lines: Array[String] = []
	var roll := slip_away_choice(state.rng)
	var signal_target: TaskForce = null
	for tf in [dec.active, dec.active_coordinating]:
		if tf != null and not SignalAction.target_hexes(tf).is_empty():
			signal_target = tf
			break
	if String(roll["choice"]) == "signal" and signal_target != null:
		var at: Vector2i = SignalAction.target_hexes(signal_target)[0]
		var r := SignalAction.resolve(signal_target, at)
		lines.append("Sfuggire: 1d6 = %d -> Segnalazione contro %s in %s."
			% [int(roll["die"]), signal_target.display_name(), str(at)])
		for l_v: Variant in r.get("log", []):
			lines.append(String(l_v))
		return lines
	if String(roll["choice"]) == "signal":
		lines.append(("Sfuggire: 1d6 = %d -> Segnalazione, ma ne' la TF Attiva ne' "
			+ "una Coordinatrice hanno un segnalino Informazioni: Manovre Evasive.")
			% int(roll["die"]))
	else:
		lines.append("Sfuggire: 1d6 = %d -> Manovre Evasive." % int(roll["die"]))
	if dec.target != null:
		if dec.target.evasive:
			lines.append("%s ha gia' un segnalino Manovre Evasive: resta uno."
				% dec.target.display_name())
		else:
			dec.target.evasive = true
			lines.append("Manovre Evasive assegnate a %s."
				% dec.target.display_name())
	return lines
