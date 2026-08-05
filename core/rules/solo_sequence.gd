class_name SoloSequence
extends RefCounted

## Le decisioni di sequenza del ciclo solitario, in un posto solo.
##
## Il ciclo esiste in due esemplari, e non per pigrizia: `SoloRunner` e'
## sincrono e testabile headless, `ui/main.gd` e' asincrono perche' deve
## aprire dialoghi, animazioni e la Mappa di Battaglia. Fonderli in una
## funzione sola vorrebbe dire trasformare tutto il ciclo in coroutine, cosa
## che si puo' fare ma non di straforo.
##
## Quello che si puo' - e si deve - unificare adesso e' tutto cio' che e'
## REGOLA e non effetto: quale ramo prende un risultato, come si costruisce la
## dichiarazione dell'azione, che cosa succede all'Iniziativa dopo, quando si
## passa alla tabella Tardi. Sono le parti che erano gia' divergute una volta:
## `initiative_changes` era applicato solo in un ramo, e la regola della TF
## Coordinatrice l'ho dovuta scrivere due volte a distanza di minuti.
##
## Regola pratica per chi ci mette mano: se una riga risponde alla domanda
## "che cosa dice il regolamento", va qui. Se risponde a "come lo mostro",
## resta nel chiamante.


## Quale ramo prende un risultato della Tabella delle Azioni.
enum Branch {
	COMPLETION,   ## la procedura porta a un tentativo di Completamento
	ACTION,       ## la procedura dichiara un'azione tabellare
	EFFECT,       ## la procedura cambia lo stato senza dichiarare un'azione
	NOTHING,      ## non c'e' niente da applicare
}

## Che cosa succede all'Iniziativa dopo un'azione risolta.
enum AfterAction {
	CHANGE,       ## un risultato la fa CAMBIARE: passa, non si tira
	OFFER_STEAL,  ## l'Inattivo puo' tentare di Sottrarre
	SEEK,         ## si Cerca l'Iniziativa
}


static func branch_of(decision: Dictionary) -> int:
	if bool(decision.get("completion", false)):
		return Branch.COMPLETION
	if String(decision.get("action_key", "")) != "":
		return Branch.ACTION
	if bool(decision.get("ok", false)):
		return Branch.EFFECT
	return Branch.NOTHING


## Una decisione che non applica niente NON puo' lasciare l'Iniziativa al bot.
##
## Senza questa regola il ciclo si ferma: l'avversario immaginario resta Attivo,
## nessuna procedura e' accodata, e la partita aspetta un giocatore che non deve
## muovere. Nel motore headless si vedeva come un turno senza tiri; nella GUI
## non si vedrebbe affatto, perche' non c'e' niente da mostrare.
static func must_yield_initiative(decision: Dictionary) -> bool:
	return branch_of(decision) == Branch.NOTHING \
		and not bool(decision.get("pass_initiative", false))


## I passi dell'effetto, nell'ordine stampato: prima lo Scorrere del Tempo di
## un Passare forzato, poi l'eventuale nuovo tiro, poi la Traiettoria con la
## sua continuazione.
static func effect_rolls_again(decision: Dictionary) -> bool:
	return bool(decision.get("roll_again", false))


static func effect_is_trajectory(decision: Dictionary) -> bool:
	return String(decision.get("turn_kind", "")) == "trajectory"


static func effect_needs_time_lapse_before_pass(decision: Dictionary) -> bool:
	return bool(decision.get("time_lapse_before_pass", false))


static func has_follow_up(decision: Dictionary) -> bool:
	return not (decision.get("follow_up", {}) as Dictionary).is_empty()


## I PASSI di una decisione del bot, nell'ordine, come dato.
##
## Erano scritti due volte: `SoloRunner._apply_bot_decision` e
## `ui/main.gd::_apply_solo_ai_decision`. Le regole erano gia' qui, ma l'ordine
## no - e le due copie erano gia' divergute su una cosa che si vede solo
## giocando: il runner fermava la ricorsione delle continuazioni a
## MAX_FOLLOW_UPS, la GUI non la fermava affatto. Il fascicolo ne stampa due al
## massimo; una che non si ferma e' un difetto, non un ciclo di gioco.
##
## Qui c'e' solo l'ORDINE, non l'esecuzione: chi cammina l'elenco lo fa a modo
## suo, sincrono nel runner e con gli `await` nella vista, che deve aprire
## dialoghi e la Mappa di Battaglia. E' il motivo per cui i due cicli non si
## possono fondere in una funzione sola, e insieme il motivo per cui l'ordine
## non deve stare in nessuno dei due.
enum Step {
	LOG,               ## le righe che la decisione porta con se'
	STEAL_CHECK,       ## l'Inattivo puo' tentare di Sottrarre l'Iniziativa
	COMPLETION,        ## risolvi il Completamento
	ACTION,            ## risolvi l'azione tabellare
	TIME_LAPSE,        ## Scorrere del Tempo
	ROLL_AGAIN,        ## la tabella ordina un altro tiro immediato
	FOLLOW_UP,         ## continuazione prescritta, senza ritirare la Tabella
	YIELD_INITIATIVE,  ## l'Iniziativa passa al giocatore
	KEEP_INITIATIVE,   ## il bot la mantiene: chi ha una coda, accodi
}

## Quante continuazioni prescritte si concatenano sulla stessa uscita della
## Tabella prima di dichiarare che qualcosa non torna.
const MAX_FOLLOW_UPS := 4


## `depth` e' quante continuazioni si sono gia' concatenate.
##
## Un passo `STEAL_CHECK` porta `on_steal`: i passi da fare AL POSTO del resto
## se l'Inattivo riesce a Sottrarre. Chi cammina l'elenco, se il tentativo
## riesce, esegue quelli e si ferma.
##
## `KEEP_INITIATIVE` non ha effetto nel runner headless, che non ha una coda da
## riempire: un passo che un camminatore ignora e' legittimo, e dichiararlo qui
## e' meglio che avere due elenchi diversi.
static func steps_for(decision: Dictionary, depth: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var active: Variant = decision.get("active", null)
	var goal: Variant = decision.get("target_hex", Vector2i.MAX)
	out.append({"step": Step.LOG, "lines": decision.get("log", [])})
	match branch_of(decision):
		Branch.COMPLETION:
			out.append({"step": Step.STEAL_CHECK,
				"label": "Completamento del bot",
				"refused": "Completamento impedito dal cambio d'Iniziativa.",
				"on_steal": [{"step": Step.TIME_LAPSE, "active": active,
					"goal": goal}]})
			out.append({"step": Step.COMPLETION, "active": active,
				"port": decision.get("completion_port", {})})
			return out
		Branch.ACTION:
			out.append({"step": Step.ACTION})
			return out
		Branch.NOTHING:
			if must_yield_initiative(decision):
				out.append({"step": Step.YIELD_INITIATIVE,
					"reason": "senza effetto applicabile"})
				return out
	if effect_needs_time_lapse_before_pass(decision):
		out.append({"step": Step.TIME_LAPSE, "active": active,
			"goal": Vector2i.MAX,
			"note": "Completamento impossibile: esegue Passare e Scorrere del Tempo."})
	if effect_rolls_again(decision):
		out.append({"step": Step.ROLL_AGAIN})
		return out
	if effect_is_trajectory(decision):
		out.append({"step": Step.TIME_LAPSE, "active": active, "goal": goal})
		out.append({"step": Step.STEAL_CHECK, "label": "Traiettoria del bot",
			"refused": "", "on_steal": []})
		if has_follow_up(decision) and depth < MAX_FOLLOW_UPS:
			out.append({"step": Step.FOLLOW_UP, "depth": depth + 1})
		else:
			out.append({"step": Step.KEEP_INITIATIVE})
		return out
	if bool(decision.get("pass_initiative", false)):
		out.append({"step": Step.YIELD_INITIATIVE,
			"reason": "la procedura cede l'Iniziativa"})
	return out


## La dichiarazione dell'azione decisa dal bot.
##
## Include la regola della TF Coordinatrice: RB p.47 la ammette solo se occupa
## l'esagono Bersaglio, quindi una Coordinatrice indicata dalla procedura ma
## fuori posto va lasciata cadere. Designarla comunque non aiuterebbe l'azione,
## la renderebbe illegale - ed e' un errore che si vede solo come "azione
## rifiutata", senza dire perche'.
##
## Ritorna null se mancano la TF Attiva o il Bersaglio.
static func declaration_for(decision: Dictionary) -> ActionEngine.Declaration:
	var key := String(decision.get("action_key", ""))
	var active: TaskForce = decision.get("active", null)
	var target: TaskForce = decision.get("target", null)
	var stealth: Dictionary = decision.get("active_stealth", {})
	var air_base: Dictionary = decision.get("active_air_base", {})
	if key == "" or target == null:
		return null
	# Un Attacco Furtivo eseguito da una forza Furtiva non ha TF Attiva (RB
	# p.41): li' l'attaccante e' la forza, e pretenderne una sarebbe il difetto
	# gia' visto nel registro BL2, dove "Attacco Furtivo -> Totale Traiettoria
	# 2" tradiva che a eseguirlo era una Task Force.
	if active == null and stealth.is_empty() and air_base.is_empty():
		return null
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = active
	dec.active_stealth = stealth
	dec.active_air_base = air_base
	dec.target = target
	dec.launch_hex = decision.get("launch_hex", Vector2i.MAX)
	dec.target_hex = decision.get("target_hex", Vector2i.MAX)
	# I modificatori che una procedura stampata impone all'azione (per esempio
	# il +3 dell'Attacco Furtivo di N3, p.26). Zero se la procedura non ne da'.
	dec.modifier = int(decision.get("modifier", 0))
	var coordinating: TaskForce = decision.get("coordinating", null)
	if coordinating != null and dec.target_hex != Vector2i.MAX \
			and coordinating.trajectory.occupies(dec.target_hex):
		dec.active_coordinating = coordinating
	return dec


## Quale opzione di Scorrere del Tempo prescrive la procedura stampata.
##
## Le Tabelle Azioni chiudono quasi ogni risultato con una riga "Time Lapse:
## Remove segments farthest from X" - e ogni tanto con "nearest to X", che e'
## la stessa frase al contrario. Il conto era scritto due volte, identico, in
## `SoloRunner` e in `ui/main.gd`, e conosceva solo il caso "farthest": la 'X'
## di N3 (p.26) dice "Remove segments nearest to Scapa Flow", e con una copia
## sola quel caso si aggiunge una volta sola.
##
## Ritorna l'INDICE dell'opzione preferita in `options`, che resta una scelta:
## chi ha un rispondente umano puo' ignorarla.
static func time_lapse_preference(options: Array, traj: Trajectory,
		goal: Vector2i, prefer_near: bool = false) -> int:
	if options.is_empty():
		return -1
	if goal == Vector2i.MAX:
		return 0
	var best := 0
	var best_score := -INF
	var sign := -1.0 if prefer_near else 1.0
	for i in options.size():
		var ends: Array = (options[i] as Dictionary)["ends"]
		var d0 := float(Hex.distance(traj.end_hex(0), goal))
		var d1 := float(Hex.distance(traj.end_hex(1), goal))
		var score := sign * (float(int(ends[0])) * d0 + float(int(ends[1])) * d1)
		if score > best_score:
			best_score = score
			best = i
	return best


## Che cosa succede all'Iniziativa quando l'azione si e' risolta senza aprire
## una Battaglia.
##
## RB p.53: certi risultati la fanno CAMBIARE, e allora passa e basta. La
## Ricerca Navale lascia invece all'Inattivo il tentativo di Sottrarre. In
## tutti gli altri casi si Cerca l'Iniziativa. Confondere il primo caso con
## l'ultimo non produce nessun messaggio d'errore: la partita continua, e il
## Conto dell'Iniziativa si comporta in modo diverso.
static func after_action(action_key: String, initiative_changes: bool) -> int:
	if initiative_changes:
		return AfterAction.CHANGE
	if action_key == "NAVAL_SEARCH":
		return AfterAction.OFFER_STEAL
	return AfterAction.SEEK


## L'evento che fa passare alla tabella Tardi, per azione eseguita. Stringa
## vuota se quell'azione non ne innesca nessuno. Gli inneschi veri e propri
## restano in `SoloOpponent.goes_late_after`, che sa quali scenari li usano.
static func late_event_for_action(action_key: String) -> String:
	match action_key:
		"AIR_STRIKE":
			return "air_strike"
		"STEALTH_ATTACK":
			return "stealth_attack"
	return ""
