class_name Interruption
extends RefCounted

## Interruzione (RB p.22).
##
## Quando il giocatore Attivo dichiara Attacco Aereo, Ingaggiare, Ricerca Navale
## o Attacco Furtivo designando una propria TF che ha almeno un segnalino
## Informazioni, il giocatore Inattivo verifica l'Interruzione.
##
## Si tira 2d6 SENZA modificatori. La riga e' la somma; la colonna e' il numero
## totale di segnalini Informazioni su TUTTE le TF designate del giocatore
## Attivo (Attiva + Coordinatrice + Supporto Aereo). I segnalini del giocatore
## Inattivo si ignorano.
##
## Tabella letta direttamente dalla mappa a risoluzione nativa; l'estrazione
## testuale del PDF perde le celle e va sotto-riga.

enum Result {
	ALERT,               ## riprendi l'azione con un modificatore (0, -1, -2)
	SLIP_AWAY,           ## "S"     - Sfuggire
	VIE_FOR_INITIATIVE,  ## "VforI" - Cercare l'Iniziativa
	INITIATIVE_CHANGE,   ## "I C"   - Cambio di Iniziativa
}

const _A0 := "ALERT_0"
const _A1 := "ALERT_1"
const _A2 := "ALERT_2"
const _S := "SLIP_AWAY"
const _V := "VIE_FOR_INITIATIVE"
const _I := "INITIATIVE_CHANGE"

## righe: [min, max, [col1, col2, col3, col4+]]
const TABLE := [
	[2, 4, [_A0, _A1, _A2, _S]],
	[5, 7, [_A1, _A2, _S, _V]],
	[8, 8, [_A2, _S, _V, _I]],
	[9, 9, [_S, _V, _I, _I]],
	[10, 12, [_V, _I, _I, _I]],
]


## Serve l'Interruzione? RB p.22: si', se almeno una TF designata del giocatore
## Attivo ha un segnalino Informazioni.
static func is_triggered(info_markers_on_designated: int) -> bool:
	return info_markers_on_designated > 0


## Indice di colonna (0..3) dal numero di segnalini; l'ultima colonna e' "4+".
static func column_for(info_markers: int) -> int:
	return clampi(info_markers - 1, 0, 3)


## Codice risultato grezzo per una data somma e colonna.
static func lookup(dice_sum: int, info_markers: int) -> String:
	var col := column_for(info_markers)
	for row: Array in TABLE:
		if dice_sum >= int(row[0]) and dice_sum <= int(row[1]):
			return String((row[2] as Array)[col])
	# fuori tabella non dovrebbe accadere con 2d6
	push_error("Interruzione: somma %d fuori tabella" % dice_sum)
	return _I


## Esegue la verifica completa. Ritorna un Dictionary:
##   { "triggered": bool, "sum": int, "info": int, "code": String,
##     "result": Result, "modifier": int, "label": String, "effect": String }
static func check(info_markers_on_designated: int, rng: DiceRNG) -> Dictionary:
	if not is_triggered(info_markers_on_designated):
		return {
			"triggered": false, "sum": 0, "info": info_markers_on_designated,
			"code": "", "result": Result.ALERT, "modifier": 0,
			"label": "nessuna Interruzione", "effect": "",
		}
	var s := rng.d6x2("Interruzione")
	return resolve(s, info_markers_on_designated)


## Come check() ma con la somma gia' nota (usato dai test golden).
static func resolve(dice_sum: int, info_markers: int) -> Dictionary:
	var code := lookup(dice_sum, info_markers)
	var out := {
		"triggered": true, "sum": dice_sum, "info": info_markers, "code": code,
	}
	match code:
		_A0, _A1, _A2:
			out["result"] = Result.ALERT
			out["modifier"] = -int(code.substr(6))
			out["label"] = "Allerta %d" % out["modifier"]
			out["effect"] = ("Riprendete l'Azione interrotta, modificando di %d "
				+ "la somma del tiro del giocatore Attivo.") % out["modifier"]
		_S:
			out["result"] = Result.SLIP_AWAY
			out["modifier"] = 0
			out["label"] = "Sfuggire"
			out["effect"] = ("Il giocatore Inattivo sceglie: azione Segnalazione "
				+ "contro la TF Attiva o una Coordinatrice, oppure assegnare un "
				+ "segnalino Manovre Evasive alla TF Bersaglio. Poi l'Azione e' "
				+ "annullata e si Cerca l'Iniziativa.")
		_V:
			out["result"] = Result.VIE_FOR_INITIATIVE
			out["modifier"] = 0
			out["label"] = "Cercare l'Iniziativa"
			out["effect"] = ("Ciascun giocatore tira 1d6; l'Inattivo somma il "
				+ "Conto dell'Iniziativa e il modificatore Manovre Evasive. "
				+ "Parita' = l'Attivo mantiene l'Iniziativa.")
		_:
			out["result"] = Result.INITIATIVE_CHANGE
			out["modifier"] = 0
			out["label"] = "Cambio di Iniziativa"
			out["effect"] = ("Azione annullata; il giocatore Inattivo ottiene "
				+ "l'Iniziativa. Effettuate una Verifica delle Condizioni Meteo.")
	return out


## Conta i segnalini Informazioni sulle TF designate del giocatore Attivo.
## RB p.22: "Ignorate i segnalini Informazioni assegnati alle Traiettorie del
## giocatore Inattivo."
static func count_designated_info(designated: Array) -> int:
	var n := 0
	for t: Variant in designated:
		if t is Trajectory:
			n += (t as Trajectory).info_count()
	return n
