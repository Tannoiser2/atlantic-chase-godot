extends TestCase

## Ruolino navi: valori letti dalle pedine (OCR + correzioni a occhio).
##
## I valori attesi qui sotto sono stati VERIFICATI GUARDANDO le pedine
## ingrandite, non presi dall'OCR. Se una rigenerazione del ruolino li cambia,
## questo test lo dice.

var roster: ShipRoster


func name() -> String:
	return "Ruolino navi"


func run() -> void:
	roster = ShipRoster.load_default()
	test_loads()
	test_known_ships()
	test_carriers_cannot_fire()
	test_flip_changes_everything()
	test_convoys_and_squadrons()
	test_tf_speed_follows_slowest_current_side()


func test_loads() -> void:
	_begin("caricamento")
	eq(roster.load_error, "", "nessun errore")
	true_(roster.count() >= 80, "il ruolino ha %d navi" % roster.count())
	true_(roster.has("Bismarck"), "la Bismarck c'e'")
	true_(roster.has("bismarck"), "la ricerca ignora maiuscole e minuscole")
	false_(roster.has("Nave Inesistente"), "un nome sconosciuto non c'e'")
	eq(roster.make("Nave Inesistente"), null,
		"un nome sconosciuto non produce una nave fantasma")


func test_known_ships() -> void:
	_begin("valori verificati sulle pedine")
	# Bismarck: BB, 4/2, Difesa 2, media -> danneggiata 3/1, Difesa 4, lenta
	var b := roster.make("Bismarck")
	ne(b, null, "Bismarck costruita")
	eq(b.type_code, "BB", "tipo")
	eq(b.nation, "GE", "nazione")
	eq(b.gun_close, 4, "cannoni a bruciapelo/corto")
	eq(b.gun_far, 2, "cannoni a lungo/estremo")
	eq(b.defense, 2, "Difesa")
	eq(b.speed, TimeLapse.Speed.MEDIUM, "velocita'")
	eq(b.gun_close_damaged, 3, "cannoni vicini da danneggiata")
	eq(b.gun_far_damaged, 1, "cannoni lontani da danneggiata")
	eq(b.defense_damaged, 4, "Difesa da danneggiata")
	eq(b.speed_damaged, TimeLapse.Speed.SLOW, "velocita' da danneggiata")

	# Hood: BC, 3/1, Difesa 2, veloce
	var h := roster.make("Hood")
	eq(h.type_code, "BC", "Hood e' un incrociatore da battaglia")
	eq(h.gun_close, 3, "Hood cannoni vicini")
	eq(h.gun_far, 1, "Hood cannoni lontani")
	eq(h.speed, TimeLapse.Speed.FAST, "Hood e' veloce")

	# Duke of York: 4/2 Difesa 2 media -> 2/0 Difesa 3 lenta
	var d := roster.make("Doy")
	if d == null:
		d = roster.make("Duke Of York")
	ne(d, null, "Duke of York costruita")
	eq(d.gun_close, 4, "DoY cannoni vicini")
	eq(d.defense_damaged, 3, "DoY Difesa da danneggiata")

	# Nelson: 3/2 Difesa 2 lenta
	var n := roster.make("Nelson")
	eq(n.gun_close, 3, "Nelson cannoni vicini")
	eq(n.gun_far, 2, "Nelson cannoni lontani")
	eq(n.speed, TimeLapse.Speed.SLOW, "Nelson e' lenta")


func test_carriers_cannot_fire() -> void:
	_begin("le portaerei non fanno Fuoco di Cannoni")
	# Sulle pedine delle portaerei integre, al posto dei valori dei cannoni
	# c'e' l'icona di un aereo: significa 'na' a ogni raggio.
	for cv in ["Ark Royal", "Furious", "Glorious", "Victorious", "Bearn"]:
		var s := roster.make(cv)
		if s == null:
			continue
		eq(s.gun_close, null, "%s: 'na' a bruciapelo/corto" % cv)
		eq(s.gun_far, null, "%s: 'na' a lungo/estremo" % cv)
		false_(s.can_fire("close"), "%s non puo' sparare da vicino" % cv)
		false_(s.can_fire("far"), "%s non puo' sparare da lontano" % cv)
		eq(s.type_code, "CV", "%s e' una portaerei" % cv)


func test_flip_changes_everything() -> void:
	_begin("girando la pedina cambiano cannoni, Difesa e velocita'")
	var b := roster.make("Bismarck")
	eq(b.current_speed(), TimeLapse.Speed.MEDIUM, "integra: media")
	eq(b.gun_value("close"), 4, "integra: 4 a bruciapelo")
	eq(b.gun_value("far"), 2, "integra: 2 a lungo")

	# due Colpi la portano al numero di Difesa e la girano
	b.apply_hits(2)
	true_(b.damaged, "danneggiata dopo due Colpi")
	eq(b.current_speed(), TimeLapse.Speed.SLOW, "danneggiata: lenta")
	eq(b.gun_value("close"), 3, "danneggiata: 3 a bruciapelo")
	eq(b.gun_value("far"), 1, "danneggiata: 1 a lungo")
	true_(b.is_slow_or_slower(), "e conta come bersaglio lento (+1 ai cannoni)")

	# quattro altri Colpi la affondano
	b.apply_hits(4)
	true_(b.sunk, "affondata alla Difesa del lato danneggiato")


func test_convoys_and_squadrons() -> void:
	_begin("Convogli e Squadroni DD")
	var c := roster.make("Convoy x3")
	ne(c, null, "il Convoglio britannico da 3 esiste nel ruolino")
	if c == null:
		return
	eq(c.kind, Ship.Kind.CONVOY, "e' di tipo Convoglio")
	false_(c.can_be_damaged(), "non si danneggia mai")
	eq(c.gun_far, null, "'na' a lungo raggio")

	eq(c.gun_close, -2, "il Convoglio ha -2 a bruciapelo/corto")

	var dd := roster.make("DD Squadron")
	ne(dd, null, "lo Squadrone DD esiste")
	if dd == null:
		return
	eq(dd.kind, Ship.Kind.DD_SQUADRON, "e' di tipo Squadrone DD")
	false_(dd.can_be_damaged(), "non si danneggia mai")


func test_tf_speed_follows_slowest_current_side() -> void:
	_begin("la velocita' della TF segue il lato attuale della nave piu' lenta")
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var b := roster.make("Bismarck")        # media -> lenta se danneggiata
	var pe := roster.make("Preugen")
	if pe == null:
		pe = roster.make("Hood")
	tf.ships = [b, pe] as Array[Ship]
	var before := tf.recompute_speed()
	b.apply_hits(2)
	var after := tf.recompute_speed()
	true_(after <= before,
		"danneggiare la nave piu' lenta non puo' rendere la TF piu' veloce")
	eq(after, TimeLapse.Speed.SLOW, "la Bismarck danneggiata rallenta la TF")
