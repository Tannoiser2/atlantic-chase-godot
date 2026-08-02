extends TestCase

## Tabelle dei Risultati Speciali (player aid delle Regole Avanzate).
##
## Chiudono la catena del Fuoco avanzato: un Risultato Grave non e' ancora un
## effetto, e' un rimando. Due tiri in piu' dicono dove e' entrato il colpo e
## che cosa ha rotto.

func name() -> String:
	return "Tabelle dei Risultati Speciali"


func run() -> void:
	test_range_matters()
	test_belt()
	test_superstructure()
	test_waterline()
	test_false_and_exaggerated()
	test_full_chain()


func _rng(values: Array) -> DiceRNG:
	var r := DiceRNG.new(1)
	r.push_forced(values)
	return r


## Il raggio cambia tutto: da lontano si sbaglia, da vicino si affonda.
func test_range_matters() -> void:
	_begin("il raggio decide dove entra il colpo")
	var ext := Gunnery.FireRange.EXTREME
	var pb := Gunnery.FireRange.POINT_BLANK

	# GRAVE con 2: da lontano e' un Rapporto Falso, da vicino la Cintura non
	# c'entra ancora ma la Sovrastruttura si'
	eq(ResultTables.hit_location(false, ext, 2), ResultTables.FALSE_REPORT,
		"Grave, Estremo, 2: gli avvistatori si erano sbagliati")
	eq(ResultTables.hit_location(false, pb, 2), ResultTables.FALSE_REPORT,
		"anche da vicino un 2 e' un falso allarme")

	# GRAVE con 12
	eq(ResultTables.hit_location(false, ext, 12), ResultTables.BELT,
		"Grave, Estremo, 12: Cintura")
	eq(ResultTables.hit_location(false, pb, 12), ResultTables.WATERLINE,
		"Grave, Bruciapelo, 12: sotto la linea di galleggiamento")

	# CATASTROFICO con 2: da lontano e' solo un rapporto esagerato
	eq(ResultTables.hit_location(true, ext, 2), ResultTables.EXAGGERATED,
		"Catastrofico, Estremo, 2: il danno non era grave")
	eq(ResultTables.hit_location(true, pb, 2), ResultTables.SUPERSTRUCTURE,
		"ma a Bruciapelo lo stesso tiro rompe la sovrastruttura")

	# CATASTROFICO alto: da vicino e' quasi sempre la linea di galleggiamento
	eq(ResultTables.hit_location(true, pb, 12), ResultTables.WATERLINE, "12")
	eq(ResultTables.hit_location(true, pb, 7), ResultTables.WATERLINE, "7")
	eq(ResultTables.hit_location(true, ext, 12), ResultTables.BELT,
		"mentre da lontano il 12 arriva alla Cintura")


func test_belt() -> void:
	_begin("Cintura")
	eq(String(ResultTables.effect_for(ResultTables.BELT, false, 2)["effect"]),
		SpecialEffects.RUDDER, "Grave 2-4: Timone Fuori Uso")
	eq(String(ResultTables.effect_for(ResultTables.BELT, false, 5)["effect"]),
		SpecialEffects.TURRETS, "Grave 5-6: Torrette")
	eq(String(ResultTables.effect_for(ResultTables.BELT, false, 12)["effect"]),
		SpecialEffects.FIRE_STOPPED, "Grave 10-12: Incendio (ferma)")
	eq(String(ResultTables.effect_for(ResultTables.BELT, true, 5)["effect"]),
		SpecialEffects.MAGAZINE, "Catastrofico 5-6: Santabarbara")


func test_superstructure() -> void:
	_begin("Sovrastruttura")
	eq(String(ResultTables.effect_for(
		ResultTables.SUPERSTRUCTURE, false, 2)["effect"]),
		SpecialEffects.BATTERIES, "Grave 2-6: Batterie")
	eq(String(ResultTables.effect_for(
		ResultTables.SUPERSTRUCTURE, false, 7)["effect"]),
		SpecialEffects.BRIDGE, "Grave 7: Plancia")
	eq(String(ResultTables.effect_for(
		ResultTables.SUPERSTRUCTURE, true, 12)["effect"]), "Affondata",
		"Catastrofico 12: la nave affonda - l'unica casella che lo fa")

	# con valore dei cannoni zero non c'e' effetto: e' solo un Colpo. E' il
	# caso dell'esempio del fascicolo, il Bismarck che divide il fuoco e
	# assegna 0 al secondo bersaglio.
	var zero := ResultTables.effect_for(
		ResultTables.SUPERSTRUCTURE, false, 7, 0)
	eq(String(zero["effect"]), "", "con GV 0 nessun effetto")
	true_(zero["hit"], "ma un Colpo si'")


func test_waterline() -> void:
	_begin("Linea di Galleggiamento")
	eq(String(ResultTables.effect_for(ResultTables.WATERLINE, false, 2)["effect"]),
		SpecialEffects.RUDDER, "Grave 2-5: Timone Fuori Uso")
	eq(String(ResultTables.effect_for(ResultTables.WATERLINE, false, 6)["effect"]),
		SpecialEffects.FLOOD_STOPPED, "Grave 6-7: Allagamento (ferma)")
	eq(String(ResultTables.effect_for(ResultTables.WATERLINE, false, 8)["effect"]),
		SpecialEffects.FLOOD_SLOW, "Grave 8-12: Allagamento (molto lenta)")
	# nella colonna Catastrofica le due gravita' si invertono
	eq(String(ResultTables.effect_for(ResultTables.WATERLINE, true, 8)["effect"]),
		SpecialEffects.FLOOD_STOPPED,
		"Catastrofico 8-12: allagamento che ferma, non che rallenta")


func test_false_and_exaggerated() -> void:
	_begin("rapporti sbagliati")
	var f := ResultTables.effect_for(ResultTables.FALSE_REPORT, false, 0)
	eq(String(f["effect"]), "", "Rapporto Falso: nessun effetto")
	false_(f["hit"], "e nemmeno un Colpo")

	var e := ResultTables.effect_for(ResultTables.EXAGGERATED, true, 0)
	eq(String(e["effect"]), "", "Rapporto Esagerato: nessun effetto")
	true_(e["hit"], "ma un Colpo si'")


## La catena intera, con i dadi imposti.
func test_full_chain() -> void:
	_begin("dalla casella all'effetto")
	# Grave a Bruciapelo: primo tiro 6+6 = 12 -> Linea di Galleggiamento;
	# secondo tiro 1+1 = 2 -> Timone Fuori Uso
	var r := ResultTables.resolve(false, Gunnery.FireRange.POINT_BLANK, 3,
		_rng([6, 6, 1, 1]))
	eq(String(r["location"]), ResultTables.WATERLINE, "colpito sotto la linea")
	eq(String(r["effect"]), SpecialEffects.RUDDER, "e salta il timone")
	eq((r["rolls"] as Array).size(), 2, "due tiri")

	# un Rapporto Falso si ferma al primo tiro: non c'e' niente da guardare
	var f := ResultTables.resolve(false, Gunnery.FireRange.EXTREME, 3,
		_rng([1, 1]))
	eq(String(f["location"]), ResultTables.FALSE_REPORT, "falso allarme")
	eq((f["rolls"] as Array).size(), 1, "un tiro solo")
	false_(f["hit"], "e non succede niente")

	# Catastrofico a Bruciapelo con 12+12: Linea di Galleggiamento, allagamento
	# che ferma la nave
	var c := ResultTables.resolve(true, Gunnery.FireRange.POINT_BLANK, 4,
		_rng([6, 6, 6, 6]))
	eq(String(c["location"]), ResultTables.WATERLINE, "sotto la linea")
	eq(String(c["effect"]), SpecialEffects.FLOOD_STOPPED, "e la nave si ferma")
