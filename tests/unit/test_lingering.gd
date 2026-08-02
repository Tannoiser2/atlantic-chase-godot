extends TestCase

## Effetti Duraturi e Disingaggio (Regole Avanzate, pp.11 e 14).
##
## Le due TABELLE stanno su una carta player aid che non e' nel PDF, quindi qui
## si verificano le PROCEDURE e il significato dei risultati - che il fascicolo
## scrive per esteso - non la griglia.

func name() -> String:
	return "Effetti Duraturi e Disingaggio"


func run() -> void:
	test_which_effects_check()
	test_damage_control_roll()
	test_results()
	test_disengagement()
	test_german_vulnerability()
	test_no_radar()


func _ship() -> Ship:
	var s := Ship.new("Bismarck", TimeLapse.Speed.FAST)
	s.defense = 3
	s.defense_damaged = 2
	return s


func _rng(v: Array) -> DiceRNG:
	var r := DiceRNG.new(1)
	r.push_forced(v)
	return r


## Le Torrette non passano dagli Effetti Duraturi: si verificano solo
## all'uscita, ed e' l'unica occasione per toglierle.
func test_which_effects_check() -> void:
	_begin("quali effetti si verificano, e quando")
	var s := _ship()
	eq(Lingering.lingering_checks(s).size(), 0, "senza effetti si salta la fase")

	SpecialEffects.apply(s, SpecialEffects.FIRE_SLOW)
	SpecialEffects.apply(s, SpecialEffects.TURRETS)
	var l := Lingering.lingering_checks(s)
	eq(l.size(), 1, "un solo effetto da verificare a ogni Round")
	eq(l[0], SpecialEffects.FIRE_SLOW, "ed e' l'incendio")

	var d := Lingering.disengagement_checks(s)
	eq(d.size(), 2, "all'uscita si verificano tutti e due")
	true_(d.has(SpecialEffects.TURRETS),
		"comprese le Torrette, che li' si possono togliere")


## Il Controllo Danni: tre dadi, i due piu' ALTI. In cambio la nave non spara.
func test_damage_control_roll() -> void:
	_begin("Controllo Danni")
	var plain := Lingering.roll(_rng([2, 5]), false, SpecialEffects.FIRE_SLOW)
	eq((plain["rolled"] as Array).size(), 2, "senza Controllo Danni: due dadi")
	eq(int(plain["sum"]), 7, "somma 7")

	var dc := Lingering.roll(_rng([2, 5, 6]), true, SpecialEffects.FIRE_SLOW)
	eq((dc["rolled"] as Array).size(), 3, "con il Controllo Danni: tre dadi")
	eq(int(dc["sum"]), 11, "e si tengono i due piu' alti: 5+6 = 11")

	true_(Lingering.damage_control_blocks_gunnery(),
		"ma quella nave non spara nel Round successivo: riparare costa")


func test_results() -> void:
	_begin("i risultati degli Effetti Duraturi")
	var s := _ship()
	SpecialEffects.apply(s, SpecialEffects.FIRE_SLOW)

	# aggravamento
	Lingering.apply(s, SpecialEffects.FIRE_SLOW, Lingering.FIRE_STOPPED)
	true_(SpecialEffects.has(s, SpecialEffects.FIRE_STOPPED),
		"l'incendio peggiora")
	false_(SpecialEffects.has(s, SpecialEffects.FIRE_SLOW),
		"e quello lieve sparisce: non si accumulano")

	# miglioramento
	Lingering.apply(s, SpecialEffects.FIRE_STOPPED, Lingering.FIRE_SLOW)
	true_(SpecialEffects.has(s, SpecialEffects.FIRE_SLOW), "e puo' migliorare")

	# riparazione
	Lingering.apply(s, SpecialEffects.FIRE_SLOW, Lingering.REPAIRED)
	eq(s.special_effects.size(), 0, "riparato: l'effetto sparisce")

	# Colpo senza cambiamento
	var s2 := _ship()
	SpecialEffects.apply(s2, SpecialEffects.FIRE_STOPPED)
	Lingering.apply(s2, SpecialEffects.FIRE_STOPPED, Lingering.HIT_NO_CHANGE)
	true_(s2.hits > 0 or s2.damaged, "il Colpo arriva")
	true_(SpecialEffects.has(s2, SpecialEffects.FIRE_STOPPED),
		"e l'effetto resta")

	# affondamento
	var s3 := _ship()
	SpecialEffects.apply(s3, SpecialEffects.FLOOD_STOPPED)
	Lingering.apply(s3, SpecialEffects.FLOOD_STOPPED, Lingering.SUNK)
	true_(s3.sunk, "un effetto duraturo puo' affondare la nave da solo")


func test_disengagement() -> void:
	_begin("Disingaggio")
	var s := _ship()
	SpecialEffects.apply(s, SpecialEffects.RUDDER)

	Lingering.apply_disengagement(s, SpecialEffects.RUDDER, Lingering.DIS_REPAIR)
	eq(s.special_effects.size(), 0, "Riparato: l'effetto se ne va")

	# la nafta: non fa niente alla nave, ma toglie le Manovre Evasive alla TF
	var s2 := _ship()
	SpecialEffects.apply(s2, SpecialEffects.FLOOD_SLOW)
	var txt := Lingering.apply_disengagement(s2, SpecialEffects.FLOOD_SLOW,
		Lingering.DIS_OIL)
	false_(SpecialEffects.has(s2, SpecialEffects.FLOOD_SLOW),
		"l'allagamento se ne va")
	true_(s2.special_effects.has(Lingering.DIS_OIL), "ma resta la scia")
	true_(txt.contains("Manovre Evasive"),
		"e il registro dice qual e' il prezzo")

	# autoaffondamento
	var s3 := _ship()
	SpecialEffects.apply(s3, SpecialEffects.FIRE_STOPPED)
	Lingering.apply_disengagement(s3, SpecialEffects.FIRE_STOPPED,
		Lingering.DIS_SCUTTLE)
	true_(s3.sunk, "l'autoaffondamento e' un affondamento")


## La regola opzionale "vulnerabilita' tedesca" e' l'esatto contrario del
## Controllo Danni: tre dadi, i due piu' BASSI.
func test_german_vulnerability() -> void:
	_begin("vulnerabilita' tedesca (regola opzionale)")
	var plain := Lingering.disengagement_roll(_rng([3, 6]), false)
	eq(int(plain["sum"]), 9, "normalmente due dadi")

	var ge := Lingering.disengagement_roll(_rng([3, 6, 1]), true)
	eq((ge["rolled"] as Array).size(), 3, "il tedesco ne tira tre")
	eq(int(ge["sum"]), 4, "e tiene i due piu' bassi: 1+3 = 4")
	true_(int(ge["sum"]) < int(plain["sum"]),
		"che e' peggio, ed e' esattamente il punto della regola")


## Niente Radar e' l'unica penalita' avanzata di cui il fascicolo da' la
## tabella per esteso, quindi qui e' automatica.
func test_no_radar() -> void:
	_begin("Niente Radar")
	var s := _ship()
	eq(Lingering.no_radar_modifier(s, Gunnery.FireRange.EXTREME), 0,
		"senza il marcatore nessuna penalita'")

	s.special_effects.append(Lingering.NO_RADAR)
	eq(Lingering.no_radar_modifier(s, Gunnery.FireRange.EXTREME), -2,
		"-2 a raggio Estremo")
	eq(Lingering.no_radar_modifier(s, Gunnery.FireRange.LONG), -1,
		"-1 a raggio Lungo")
	eq(Lingering.no_radar_modifier(s, Gunnery.FireRange.SHORT), 0,
		"e niente da vicino: e' un problema di puntamento a distanza")

	# 9 o meno resta, 10-12 se ne va
	var stay := Lingering.no_radar_check(s, _rng([4, 5]))
	eq(int(stay["sum"]), 9, "somma 9")
	false_(stay["removed"], "con 9 resta")
	true_(s.special_effects.has(Lingering.NO_RADAR), "il marcatore c'e' ancora")

	var gone := Lingering.no_radar_check(s, _rng([5, 5]))
	true_(gone["removed"], "con 10 se ne va")
	false_(s.special_effects.has(Lingering.NO_RADAR), "e il marcatore sparisce")
