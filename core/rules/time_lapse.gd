class_name TimeLapse
extends RefCounted

## Scorrere del Tempo (RB p.19-20).
##
## Rimuove segmenti da una Traiettoria. Quanti dipende dalla velocita' della TF
## (la sua nave piu' lenta) e dalle condizioni meteo:
##
##   meteo Buono   -> valore fisso dalla tabella (2/2/3/4)
##   meteo Cattivo -> 1d6, tirato separatamente per ciascuna TF
##
## Il vincolo che rende la regola interessante: NON si possono rimuovere
## segmenti con un segnalino Informazioni... a meno di invocare il Limite di
## Informazioni, che permette di rimuoverne UNO solo ma riduce il totale
## rimovibile (1 per TF lente, 2 per TF medie/veloci).
##
## Inoltre i segmenti si rimuovono solo dai capi, quindi un segnalino
## Informazioni in mezzo alla Traiettoria e' semplicemente irraggiungibile.

## FERMA e' una velocita' delle sole Regole Avanzate, imposta da un effetto
## speciale (incendio, allagamento).
##
## Vale -1 e non 0 di proposito. Metterla in testa avrebbe rinumerato tutto
## l'enum, e gli scenari salvano la velocita' come INTERO: "speed": 2 sarebbe
## passato da media a lenta in tutti e 22 i file, in silenzio. Con -1 la
## numerazione esistente resta intatta E l'ordine resta giusto, quindi i
## confronti "<= lenta" continuano a funzionare senza toccare niente.
enum Speed { STOPPED = -1, VERY_SLOW = 0, SLOW, MEDIUM, FAST }
enum Weather { GOOD, BAD }

const SPEED_KEYS := ["very_slow", "slow", "medium", "fast"]
const SPEED_LABELS := ["molto lenta", "lenta", "media", "veloce"]


## Il nome della velocita'. Non si indicizza SPEED_LABELS direttamente perche'
## FERMA vale -1: l'indice negativo prenderebbe l'ultimo elemento.
static func speed_label(speed: int) -> String:
	if speed == Speed.STOPPED:
		return "ferma"
	return SPEED_LABELS[clampi(speed, 0, SPEED_LABELS.size() - 1)]

## Segmenti rimossi con meteo Buono, per velocita'.
const GOOD_REMOVAL := [2, 2, 3, 4]
## Totale massimo rimovibile quando si invoca il Limite di Informazioni.
const INTEL_LIMIT := [1, 1, 2, 2]


## Quanti segmenti richiede lo Scorrere del Tempo, prima dei vincoli.
## Con meteo Cattivo serve `rng`, perche' si tira 1d6.
static func required_removal(speed: int, weather: int, rng: DiceRNG) -> int:
	if weather == Weather.BAD:
		return rng.d6("scorrere del tempo (meteo cattivo)")
	return GOOD_REMOVAL[speed]


static func intel_limit(speed: int) -> int:
	return INTEL_LIMIT[speed]


## Descrive tutte le opzioni legali di rimozione per una Traiettoria.
##
## Ritorna un Array di Dictionary, ciascuna:
##   { "ends": [n_dalla_testa, n_dalla_coda], "total": int,
##     "uses_intel_limit": bool, "removes_info": bool, "label": String }
##
## La UI presenta queste opzioni al giocatore; i test verificano che i conteggi
## corrispondano agli esempi del regolamento.
static func removal_options(traj: Trajectory, speed: int, amount: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := traj.length()
	if n == 0:
		return out

	var limit := intel_limit(speed)

	# --- opzioni SENZA Limite di Informazioni: non si tocca alcun segmento
	#     con Informazioni, e si rimuove esattamente `amount` (o tutti se meno)
	var target := mini(amount, n)
	for front in range(target + 1):
		var back := target - front
		if front + back > n:
			continue
		if _touches_info(traj, front, back):
			continue
		out.append({
			"ends": [front, back],
			"total": front + back,
			"uses_intel_limit": false,
			"removes_info": false,
			"label": _label(front, back, false),
		})

	# --- opzioni CON Limite di Informazioni: si deve rimuovere davvero almeno
	#     un segmento con Informazioni, e il totale non puo' superare `limit`
	var cap := mini(limit, n)
	for front in range(cap + 1):
		var back := cap - front
		if front + back > n:
			continue
		var removed_info := _count_info(traj, front, back)
		if removed_info != 1:
			continue  # esattamente UN segnalino Informazioni (RB p.20)
		out.append({
			"ends": [front, back],
			"total": front + back,
			"uses_intel_limit": true,
			"removes_info": true,
			"label": _label(front, back, true),
		})
	# stessa combinazione puo' emergere due volte: dedup
	var seen := {}
	var dedup: Array[Dictionary] = []
	for o in out:
		var k := "%d-%d-%s" % [o["ends"][0], o["ends"][1], str(o["uses_intel_limit"])]
		if seen.has(k):
			continue
		seen[k] = true
		dedup.append(o)
	return dedup


static func _touches_info(traj: Trajectory, front: int, back: int) -> bool:
	return _count_info(traj, front, back) > 0


static func _count_info(traj: Trajectory, front: int, back: int) -> int:
	var n := traj.length()
	if front + back > n:
		return 0
	var c := 0
	for i in range(front):
		if traj.segments[i]["info"]:
			c += 1
	for i in range(back):
		if traj.segments[n - 1 - i]["info"]:
			c += 1
	return c


static func _label(front: int, back: int, intel: bool) -> String:
	var parts: Array[String] = []
	if front > 0:
		parts.append("%d dalla testa" % front)
	if back > 0:
		parts.append("%d dalla coda" % back)
	var s := " + ".join(parts) if parts.size() > 0 else "nessuna rimozione"
	if intel:
		s += "  (Limite di Informazioni)"
	return s


## Applica una delle opzioni restituite da removal_options().
## Se la Traiettoria si svuota, il chiamante deve scegliere in quale degli
## esagoni appena liberati porre la Stazione (RB p.14): gli esagoni liberati
## sono restituiti qui.
static func apply(traj: Trajectory, option: Dictionary) -> Array[Vector2i]:
	var freed: Array[Vector2i] = []
	var front: int = option["ends"][0]
	var back: int = option["ends"][1]
	for i in range(front):
		var h := traj.remove_end(0)
		if h != Vector2i.MAX:
			freed.append(h)
	for i in range(back):
		var h := traj.remove_end(1)
		if h != Vector2i.MAX:
			freed.append(h)
	return freed
