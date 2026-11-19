extends SceneTree

## Gioca da soli, dall'inizio alla fine, gli scenari operativi a due giocatori.
##
##     godot --headless --path . --script res://tools/replay_duel.gd
##     godot --headless --path . --script res://tools/replay_duel.gd -- "Op5 Rheinubung"
##
## Tutte e due le parti seguono la policy di `DuelRunner`. Non dice chi vince:
## dice se lo scenario REGGE una partita - cioe' se le regole girano con due
## parti vere senza errori di script e senza piantarsi al primo turno.
##
## Tre esiti:
##   GIOCATO  la partita e' andata avanti fino a svuotare una parte o al limite;
##   CORTO    si e' fermata prima di dieci turni: da guardare;
##   ERRORE   lo scenario non si carica.

const SEED := 20261119
const OPS := ["Op1 Homecoming", "Op2 First Test", "Op3 Norway", "Op4 Berlin",
	"Op5 Rheinubung", "Op6 New Friends", "Op7 Non Compos Mentis",
	"Op8 Cat and Mouse", "Op9 Actic Calamity"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ids: Array = args if not args.is_empty() else OPS
	var short := 0
	var errors := 0
	for id_v: Variant in ids:
		var id := String(id_v)
		var r := DuelRunner.new()
		if not r.load_scenario(id, SEED):
			print("ERRORE   %-24s %s" % [id, r.load_error])
			errors += 1
			continue
		var out := r.run(300)
		var status := "GIOCATO"
		if int(out["turns"]) < 10:
			status = "CORTO  "
			short += 1
		print("%s  %-24s %3d turni, %2d Battaglie, %2d Completamenti, VP KM %s RN %s - %s"
			% [status, id, int(out["turns"]), int(out["battles"]),
				int(out["completions"]), r.state.vp_text(TaskForce.Side.KRIEGSMARINE),
				r.state.vp_text(TaskForce.Side.ROYAL_NAVY), String(out["stopped"])])
		if args.size() == 1:
			for line in r.transcript:
				print(line)
	print("")
	print("%d scenari: %d corti, %d non caricati." % [ids.size(), short, errors])
	quit(1 if errors > 0 else 0)
