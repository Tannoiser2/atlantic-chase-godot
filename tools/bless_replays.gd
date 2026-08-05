extends SceneTree

## Fissa le trascrizioni dei quindici replay solitari.
##
##     godot --headless --path . --script res://tools/bless_replays.gd
##
## Il paracadute dei replay non c'era davvero. `test_replay.gd` confrontava DUE
## esecuzioni dello stesso codice nello stesso processo: prova il determinismo -
## utile - ma non puo' accorgersi che una modifica ha cambiato la partita,
## perche' entrambe le esecuzioni sono gia' quelle nuove. CLAUDE.md prometteva
## l'altra cosa ("se dopo una modifica un seme da' una partita diversa"), e
## quella promessa non era mantenuta da nessun test.
##
## Serve un termine di paragone SCRITTO: l'impronta di ogni riga di ogni
## trascrizione, salvata nel repository. Il test la confronta con una partita
## fresca e dice a quale riga le due divergono.
##
## Questo strumento la riscrive. Va eseguito di PROPOSITO, quando una modifica
## alle regole o al bot cambia il gioco per davvero, e il commit che lo fa deve
## dire perche': e' il momento in cui si decide che la partita nuova e' quella
## giusta.

const OUT := "res://tests/data/replay_fingerprints.json"


func _init() -> void:
	var doc := {
		"_what": ("Impronta riga per riga dei quindici replay solitari al seme "
			+ "fisso. La rigenera tools/bless_replays.gd, di proposito."),
		"_seed": SoloRunner.BLESSED_SEED,
		"scenarios": {},
	}
	for id_v: Variant in SoloRunner.ALL_SOLO:
		var id := String(id_v)
		var runner := SoloRunner.new()
		if not runner.load_scenario(id, SoloRunner.BLESSED_SEED):
			printerr("impossibile caricare %s" % id)
			quit(1)
			return
		runner.run()
		var hashes: Array[int] = []
		for line_v: Variant in runner.transcript:
			hashes.append(String(line_v).hash())
		(doc["scenarios"] as Dictionary)[id] = {
			"lines": runner.transcript.size(),
			"hashes": hashes,
		}
		print("%-36s %4d righe" % [id, runner.transcript.size()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		printerr("impossibile scrivere %s" % OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	print("\nScritto %s" % OUT)
	quit(0)
