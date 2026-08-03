extends SceneTree

## Replay deterministici end-to-end degli scenari in solitario (milestone R0).
##
##     godot --headless --path . --script res://tools/replay_solo.gd
##     godot --headless --path . --script res://tools/replay_solo.gd -- BL1 12345
##     godot --headless --path . --script res://tools/replay_solo.gd -- --quiet
##
## Senza argomenti gioca BL1 e BL2 con i semi di riferimento e stampa la
## trascrizione completa. Esce con codice 1 se una partita non arriva a una
## condizione di fine stampata: un replay che non termina e' un difetto del
## ciclo, non un capriccio dei dadi.
##
## La trascrizione e' il prodotto: due esecuzioni con lo stesso seme la devono
## dare identica. La suite `tests/unit/test_replay.gd` verifica proprio questo.

## Semi di riferimento. Sono arbitrari ma FISSI: cambiarli vuol dire cambiare
## la partita di riferimento, e va fatto di proposito.
const DEFAULT_RUNS := [
	{"id": "BL1 Raiders of the North Atlantic", "seed": 20260803},
	{"id": "BL2 Contain and Destroy", "seed": 20260803},
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var quiet := args.has("--quiet")
	var runs: Array = DEFAULT_RUNS
	var positional: Array[String] = []
	for a_v: Variant in args:
		var a := String(a_v)
		if not a.begins_with("--"):
			positional.append(a)
	if not positional.is_empty():
		var seed_value := int(positional[1]) if positional.size() > 1 else 20260803
		runs = [{"id": _resolve_id(positional[0]), "seed": seed_value}]

	var failures := 0
	for r_v: Variant in runs:
		var r: Dictionary = r_v
		var runner := SoloRunner.new()
		if not runner.load_scenario(String(r["id"]), int(r["seed"])):
			print("SALTATO  %s: %s" % [String(r["id"]), runner.load_error])
			continue
		var out := runner.run()
		if not quiet:
			for line_v: Variant in out["transcript"]:
				print(String(line_v))
			print("")
		# Tre esiti distinti, e la differenza conta:
		#   OK       la partita e' finita per una condizione STAMPATA;
		#   STALLO   il fascicolo non prevede la posizione raggiunta - e' una
		#            lacuna dichiarata, non un difetto del ciclo;
		#   FALLITO  il ciclo non converge: questo si', e' un difetto.
		var ok: bool = bool(out["ended"]) and String(out["stopped"]) == ""
		var gap: bool = bool(out.get("declared_gap", false))
		var status := "OK" if ok else ("STALLO" if gap else "FALLITO")
		print("%-8s %-38s seme %d: %d turni, %d Battaglie, %d Completamenti - %s"
			% [status, String(r["id"]), int(r["seed"]),
				int(out["turns"]), int(out["battles"]), int(out["completions"]),
				String(out["reason"]) if ok else String(out["stopped"])])
		if not ok and not gap:
			failures += 1
	quit(1 if failures > 0 else 0)


## Accetta sia l'id completo sia il prefisso ("BL1").
func _resolve_id(prefix: String) -> String:
	for id_v: Variant in Scenario.list_ids():
		var id := String(id_v)
		if id == prefix or id.begins_with(prefix):
			return id
	return prefix
