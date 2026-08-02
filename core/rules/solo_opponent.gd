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


static func from_dict(d: Dictionary) -> SoloOpponent:
	var o := SoloOpponent.new()
	o.scenario_id = String(d.get("_scenario", ""))
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


## Passa alla tabella "Tardi". Idempotente: si passa una volta sola.
func go_late(reason: String) -> bool:
	if phase == Phase.LATE:
		return false
	phase = Phase.LATE
	phase_reason = reason
	return true


## L'azione dell'avversario immaginario, letta sulla tabella giusta.
##
## `selector` e' quello che sceglie la riga: nella tabella Presto e' il numero
## di Completamenti riusciti dell'altra parte, nella Tardi e' il meteo.
##
## Ritorna il risultato di SoloTable.roll_and_read piu' `table` e `phase`.
func act(rng: DiceRNG, selector: int,
		active_modifiers: Array = []) -> Dictionary:
	var tid := "actions_late" if phase == Phase.LATE else "actions_early"
	if not has(tid):
		tid = "actions"          # gli scenari con una tabella sola
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
