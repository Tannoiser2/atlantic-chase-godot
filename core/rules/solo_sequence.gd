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
	if key == "" or active == null or target == null:
		return null
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = active
	dec.target = target
	dec.launch_hex = decision.get("launch_hex", Vector2i.MAX)
	dec.target_hex = decision.get("target_hex", Vector2i.MAX)
	var coordinating: TaskForce = decision.get("coordinating", null)
	if coordinating != null and dec.target_hex != Vector2i.MAX \
			and coordinating.trajectory.occupies(dec.target_hex):
		dec.active_coordinating = coordinating
	return dec


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
