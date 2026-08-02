class_name Snafu
extends RefCounted

## Verifica Snafu (Regole Avanzate p.2, tabella sulla carta di aiuto faccia A).
##
## Si tira UNA VOLTA sola, prima del Round Uno, e decide con che disgrazia
## comincia la Battaglia. Il giocatore Attivo tira 2d6 senza modificatori e
## legge la colonna del meteo.
##
## E' la prima cosa che succede in una Battaglia avanzata, e cambia il carattere
## di tutto quello che viene dopo: con Buona Visibilita' la Battaglia dura un
## Round in piu' (piu' tempo per affondare qualcuno), con Scarsa Visibilita'
## tutti sparano peggio, e con la Confusione uno dei due giocatori si porta in
## tasca un jolly da giocare quando serve.
##
## LA COLONNA E' IL METEO, ma il fascicolo aggiunge che la colonna Cattivo vale
## anche sopra la Linea Artica con meteo buono: al circolo polare la visibilita'
## e' un problema comunque.

enum Result { CONFUSION, MECHANICAL, BOILER, UNEXPECTED_BEARING,
	GOOD_VISIBILITY, NO_RADAR, FOG, OPEN_ARC, POOR_VISIBILITY }

const LABELS := {
	Result.CONFUSION: "Confusione",
	Result.MECHANICAL: "Problemi Meccanici",
	Result.BOILER: "Sala Caldaie",
	Result.UNEXPECTED_BEARING: "Rotta Inaspettata",
	Result.GOOD_VISIBILITY: "Buona Visibilita'",
	Result.NO_RADAR: "Niente Radar",
	Result.FOG: "Nebbia",
	Result.OPEN_ARC: "Arco Aperto",
	Result.POOR_VISIBILITY: "Scarsa Visibilita'",
}

const EXPLAIN := {
	Result.CONFUSION: ("Un giocatore riceve il segnalino Confusione: una volta "
		+ "in questa Battaglia potra' spostare un Colpo o un Effetto Speciale "
		+ "su un'altra nave AMICA, oppure comandare una nave nemica durante la "
		+ "Manovra o l'Attitudine. Chi lo riceve si decide con un dado: PARI, "
		+ "l'Attivo."),
	Result.MECHANICAL: ("Il giocatore Bersaglio sceglie una nave Attiva che "
		+ "entrera' piu' tardi, negli Effetti Duraturi del Round Due. Se "
		+ "l'Attivo ha una nave sola, vale invece Confusione (tira il dado)."),
	Result.BOILER: ("Il giocatore Bersaglio sceglie una nave Attiva che "
		+ "entrera' piu' tardi, negli Effetti Duraturi del Round Uno. Se "
		+ "l'Attivo ha una nave sola, vale invece Confusione (tira il dado)."),
	Result.UNEXPECTED_BEARING: ("Le navi del giocatore Bersaglio si schierano "
		+ "con l'attitudine che vuole lui, non quella imposta."),
	Result.GOOD_VISIBILITY: "Questa Battaglia dura un Round in piu'.",
	Result.NO_RADAR: ("Un giocatore sceglie una nave nemica e le mette il "
		+ "marcatore Niente Radar: -2 al Fuoco a raggio Estremo e -1 a Lungo. "
		+ "Chi sceglie si decide con un dado: PARI, l'Attivo. Non e' un Effetto "
		+ "Speciale, quindi la nave non e' azzoppata."),
	Result.FOG: ("A ogni tentativo di Fuga si tirano TRE dadi e si tengono i "
		+ "due piu' alti. Vale per tutti e due i giocatori."),
	Result.OPEN_ARC: ("Le navi del giocatore Attivo si schierano con "
		+ "l'attitudine che vuole lui, non quella imposta."),
	Result.POOR_VISIBILITY: ("-1 al Fuoco di Cannoni a raggio Estremo, Lungo "
		+ "e Corto."),
}

## Colonna Meteo Buono: [somma minima, risultato].
const GOOD := [
	[7, Result.GOOD_VISIBILITY],
	[6, Result.UNEXPECTED_BEARING],
	[5, Result.BOILER],
	[4, Result.MECHANICAL],
	[2, Result.CONFUSION],
]

## Colonna Meteo Cattivo. Vale anche con meteo buono sopra la Linea Artica.
const BAD := [
	[9, Result.POOR_VISIBILITY],
	[8, Result.OPEN_ARC],
	[7, Result.FOG],
	[5, Result.NO_RADAR],
	[2, Result.CONFUSION],
]


static func label(result: int) -> String:
	return String(LABELS.get(result, "?"))


static func explain(result: int) -> String:
	return String(EXPLAIN.get(result, ""))


static func read(bad_weather: bool, total: int) -> int:
	for row_v: Variant in (BAD if bad_weather else GOOD):
		var row: Array = row_v
		if total >= int(row[0]):
			return int(row[1])
	return Result.CONFUSION


## Tira la Verifica Snafu. `arctic` forza la colonna Cattivo anche con meteo
## buono: sopra la Linea Artica la visibilita' e' un problema comunque.
static func check(rng: DiceRNG, weather: int, arctic: bool = false) -> Dictionary:
	var bad := weather == TimeLapse.Weather.BAD or arctic
	var total := rng.d6x2("Verifica Snafu")
	var res := read(bad, total)
	return {"sum": total, "bad_column": bad, "result": res,
		"label": label(res), "explain": explain(res),
		"extra_round": res == Result.GOOD_VISIBILITY,
		"gunnery_penalty": res == Result.POOR_VISIBILITY}


## Il -1 di Scarsa Visibilita', che vale a Estremo, Lungo e Corto ma non a
## Bruciapelo: da quella distanza non c'e' visibilita' che tenga.
static func visibility_modifier(active: bool, range_index: int) -> int:
	if not active:
		return 0
	return 0 if range_index == Gunnery.FireRange.POINT_BLANK else -1


## Chi riceve il beneficio di un risultato che assegna una scelta.
## Si tira un dado: PARI, sceglie il giocatore Attivo.
static func beneficiary_is_active(rng: DiceRNG) -> bool:
	return rng.d6("chi beneficia del risultato Snafu") % 2 == 0


# ------------------------------------------------------------ Confusione --

## Il segnalino Confusione: un jolly da giocare UNA VOLTA in tutta la Battaglia.
##
## Chi lo ha puo' fare una di tre cose, e sono tre cose molto diverse fra loro:
##
##   nel FUOCO       spostare un Colpo o un Effetto Speciale da una sua nave a
##                   un'altra SUA nave - non a una nemica. Va deciso nel
##                   momento in cui il risultato esce, senza aspettare di
##                   sapere quale effetto e';
##   nella MANOVRA   comandare una nave NEMICA per quel movimento: muoverla,
##                   non muoverla, farle fare Fumo o no;
##   nell'ATTITUDINE decidere l'attitudine di una nave nemica.
##
## E' l'unico elemento del gioco che permette di toccare le navi altrui, ed e'
## per questo che vale una volta sola.
enum ConfusionUse { GUNNERY_TRANSFER, MANEUVER_CONTROL, ATTITUDE_CONTROL }

const CONFUSION_USES := {
	ConfusionUse.GUNNERY_TRANSFER: ("sposta un Colpo o un Effetto Speciale su "
		+ "un'altra nave TUA"),
	ConfusionUse.MANEUVER_CONTROL: "comanda una nave nemica durante la Manovra",
	ConfusionUse.ATTITUDE_CONTROL: "decide l'attitudine di una nave nemica",
}


## Chi ha il segnalino puo' ancora usarlo?
static func confusion_available(state: BattleState, side: int) -> bool:
	return state.confusion_side == side and not state.confusion_used


## Sposta un Colpo o un Effetto da una propria nave a un'altra propria nave.
## Ritorna { ok, error, log }.
static func confusion_transfer(state: BattleState, side: int, from: Ship,
		to: Ship, effect: String = "") -> Dictionary:
	if not confusion_available(state, side):
		return {"ok": false, "log": "", "error":
			"la Confusione non e' disponibile: o non e' tua o e' gia' stata usata"}
	if from == null or to == null or from == to:
		return {"ok": false, "log": "", "error": "servono due navi diverse"}
	if to.sunk:
		return {"ok": false, "log": "", "error":
			"non si puo' spostare un danno su una nave affondata"}
	var txt := ""
	if effect == "":
		if from.hits <= 0:
			return {"ok": false, "log": "", "error":
				"%s non ha Colpi da spostare" % from.name}
		from.hits -= 1
		txt = "%s passa un Colpo a %s. %s" % [from.name, to.name,
			to.apply_hits(1)]
	else:
		if not from.special_effects.has(effect):
			return {"ok": false, "log": "", "error":
				"%s non ha l'effetto %s" % [from.name, effect]}
		from.special_effects.erase(effect)
		var r := SpecialEffects.apply(to, effect)
		txt = "%s passa %s a %s. %s" % [from.name, effect, to.name,
			String(r["log"])]
	state.confusion_used = true
	return {"ok": true, "error": "", "log": "Confusione: " + txt}


## Consuma il segnalino per un uso che non sposta danni (Manovra o Attitudine):
## il controllo della nave nemica lo esercita il giocatore, qui si registra
## solo che il jolly e' stato speso.
static func confusion_spend(state: BattleState, side: int,
		use: int) -> Dictionary:
	if not confusion_available(state, side):
		return {"ok": false, "log": "", "error":
			"la Confusione non e' disponibile"}
	state.confusion_used = true
	return {"ok": true, "error": "", "log": "Confusione usata: %s."
		% String(CONFUSION_USES.get(use, ""))}


# ------------------------------------------------------------ durata della Battaglia --

## Quanti Round dura la Battaglia, con le Regole Avanzate.
##
## Due condizioni allungano la Battaglia e si SOMMANO (fascicolo p.13):
##   A. la Verifica Snafu ha dato Buona Visibilita' (solo con meteo buono);
##   B. alla fine dell'Ultimo Round nessuna nave e' in Corsa.
##
## La seconda e' la piu' bella regola del fascicolo avanzato: la Battaglia
## finisce quando qualcuno vuole andarsene. Finche' tutti hanno voglia di
## combattere, si combatte.
static func extra_rounds(good_visibility: bool, nobody_running: bool) -> int:
	var n := 0
	if good_visibility:
		n += 1
	if nobody_running:
		n += 1
	return n


## Nessuna nave e' in Corsa: la Battaglia continua.
static func nobody_running(state: BattleState) -> bool:
	for s in state.all_ships():
		if not s.sunk and s.attitude == Attitude.Kind.RUNNING:
			return false
	return true
