class_name AdvancedGunnery
extends RefCounted

## Tabella del Fuoco di Cannoni delle Regole Avanzate (fascicolo avanzato p.5).
##
## Sostituisce quella stampata sulla mappa. La procedura e' la stessa - stessi
## dadi, stessi modificatori - ma i risultati sono piu' vari, e soprattutto le
## COLONNE diventano due:
##
##   dadi (2d6)   Avvicinamento / Corsa / Divide     Acquisizione
##   6 o meno     Splash                             Splash
##   7-8          Splash                             Colpo
##   9-10         Colpo                              Risultato Grave
##   11           Risultato Grave                    Risultato Grave
##   12 o piu'    Risultato Grave                    Risultato Catastrofico
##
## La colonna Acquisizione e' meglio di una casella su tutta la tabella: dove
## l'altra fa Splash lei colpisce, dove l'altra colpisce lei fa un Risultato
## Grave. E' il premio per aver rinunciato a manovrare, silurare e fuggire.
##
## "AZZOPPATA" (crippled) = Danneggiata OPPURE con un effetto speciale
## assegnato. Una nave azzoppata NON puo' usare la colonna Acquisizione, ma
## puo' comunque adottare l'Acquisizione come attitudine e dividere il fuoco:
## il beneficio che perde e' la colonna, non l'attitudine.

enum Result { SPLASH, HIT, SEVERE, CATASTROPHIC }

const RESULT_LABELS := ["Splash", "Colpo", "Risultato Grave",
	"Risultato Catastrofico"]

## Le due colonne, come soglie crescenti: [somma minima, risultato].
## Si legge dal basso verso l'alto e si prende la prima soglia raggiunta.
const COLUMN_CLOSING := [
	[12, Result.SEVERE],
	[11, Result.SEVERE],
	[9, Result.HIT],
	[0, Result.SPLASH],
]

const COLUMN_ACQUIRING := [
	[12, Result.CATASTROPHIC],
	[11, Result.SEVERE],
	[9, Result.SEVERE],
	[7, Result.HIT],
	[0, Result.SPLASH],
]


static func label(result: int) -> String:
	return RESULT_LABELS[clampi(result, 0, RESULT_LABELS.size() - 1)]


## Una nave "azzoppata": Danneggiata oppure con un effetto speciale.
## Il fascicolo usa una parola sola per due condizioni diverse, e conviene
## averla anche qui: compare in molte istruzioni degli scenari ("cripple the
## Graf Spee") e nelle condizioni di vittoria dei mini-scenari.
static func is_crippled(ship: Ship) -> bool:
	return ship.damaged or ship.has_special_effect()


## La colonna da usare per questo attaccante contro questo numero di bersagli.
##
## L'Acquisizione da' due benefici ALTERNATIVI: la colonna migliore oppure la
## divisione del fuoco. Chi divide rinuncia alla colonna, e chi e' azzoppato la
## perde comunque.
static func column_for(ship: Ship, targets: int = 1) -> Array:
	if ship.attitude == Attitude.Kind.ACQUIRING and targets <= 1 \
			and not is_crippled(ship):
		return COLUMN_ACQUIRING
	return COLUMN_CLOSING


## Legge la tabella. `total` e' la somma dei dadi gia' modificata.
static func read(column: Array, total: int) -> int:
	for row_v: Variant in column:
		var row: Array = row_v
		if total >= int(row[0]):
			return int(row[1])
	return Result.SPLASH


## Risultato del Fuoco per questo attaccante.
static func resolve(ship: Ship, total: int, targets: int = 1) -> int:
	return read(column_for(ship, targets), total)


## La divisione del fuoco e' legale, e come si ripartisce il valore?
##
## Serve valore dei cannoni 1 o piu', due bersagli allo stesso raggio, e a
## ciascuno va una parte non negativa. Un valore di 1 si puo' dividere in 1 e 0:
## il fascicolo lo dice esplicitamente, ed e' il caso limite che conta - vuol
## dire che con GV 1 si puo' comunque disturbare un secondo bersaglio.
static func split_refusal(ship: Ship, band: String, parts: Array) -> String:
	if ship.attitude != Attitude.Kind.ACQUIRING:
		return "solo una nave in Acquisizione puo' dividere il fuoco"
	if parts.size() != 2:
		return "il fuoco si divide fra esattamente due bersagli"
	var v: Variant = ship.gun_value(band)
	if v == null:
		return "questa nave non puo' sparare a quel raggio"
	var gv := int(round(float(v)))
	if gv < 1:
		return "serve un valore dei cannoni di 1 o piu' per dividere il fuoco"
	var total := 0
	for p_v: Variant in parts:
		var p := int(p_v)
		if p < 0:
			return "una parte non puo' essere negativa"
		total += p
	if total != gv:
		return ("le due parti devono sommare al valore dei cannoni (%d), "
			+ "non %d") % [gv, total]
	return ""


## Modificatore per la velocita' del bersaglio.
##
## Le regole avanzate aggiungono il bersaglio FERMO. Il valore +3 e' quello
## stampato sulla tabella dei Siluri (fascicolo avanzato p.9, insieme a "molto
## lento +2" e "lento +1", che coincidono con i modificatori del Fuoco base):
## la tabella dei modificatori del Fuoco avanzato sta sul player aid, che non
## ho letto, ma la scala e' la stessa e il fascicolo dice "gli stessi
## modificatori, piu' uno nuovo per la nave Ferma".
static func target_speed_modifier(target: Ship) -> int:
	match target.current_speed():
		TimeLapse.Speed.STOPPED:
			return 3
		TimeLapse.Speed.VERY_SLOW:
			return 2
		TimeLapse.Speed.SLOW:
			return 1
	return 0
