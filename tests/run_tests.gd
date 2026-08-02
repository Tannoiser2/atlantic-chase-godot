extends SceneTree

## Runner headless.  Uso:
##     godot --headless --path . --script res://tests/run_tests.gd
##
## Esce con codice 1 se un test fallisce, cosi' e' usabile direttamente in CI.

## Quante verifiche deve produrre ogni suite.
##
## Serve contro un difetto vero del runner: un errore a RUNTIME dentro un test
## (una chiamata a una funzione che non esiste, un accesso fuori dai limiti)
## interrompe quella funzione e basta. La suite prosegue, il runner stampa
## "TUTTO OK", e le verifiche perse spariscono senza che nessuno se ne accorga.
## E' successo davvero: una suite era passata da 56 a 23 verifiche e il totale
## sembrava sano.
##
## Con il conto atteso, una verifica che non gira e' un test fallito - che e'
## quello che e'. Quando si aggiungono test, questi numeri vanno alzati: e'
## una seccatura di dieci secondi che compra il non fidarsi di un OK falso.
const EXPECTED := {
	"res://tests/unit/test_hex_and_graph.gd": 284,
	"res://tests/unit/test_trajectory.gd": 49,
	"res://tests/unit/test_rules.gd": 115,
	"res://tests/unit/test_state_and_undo.gd": 37,
	"res://tests/unit/test_actions.gd": 131,
	"res://tests/unit/test_battle.gd": 145,
	"res://tests/unit/test_ships.gd": 71,
	"res://tests/unit/test_scenarios.gd": 152,
	"res://tests/unit/test_victory.gd": 181,
	"res://tests/unit/test_reorganize_signal.gd": 138,
	"res://tests/unit/test_solo.gd": 75,
	"res://tests/unit/test_attitude.gd": 158,
	"res://tests/unit/test_special_effects.gd": 67,
	"res://tests/unit/test_result_tables.gd": 34,
	"res://tests/unit/test_lingering.gd": 63,
	"res://tests/unit/test_snafu.gd": 75,
}

const SUITES := [
	"res://tests/unit/test_hex_and_graph.gd",
	"res://tests/unit/test_trajectory.gd",
	"res://tests/unit/test_rules.gd",
	"res://tests/unit/test_state_and_undo.gd",
	"res://tests/unit/test_actions.gd",
	"res://tests/unit/test_battle.gd",
	"res://tests/unit/test_ships.gd",
	"res://tests/unit/test_scenarios.gd",
	"res://tests/unit/test_victory.gd",
	"res://tests/unit/test_reorganize_signal.gd",
	"res://tests/unit/test_solo.gd",
	"res://tests/unit/test_attitude.gd",
	"res://tests/unit/test_special_effects.gd",
	"res://tests/unit/test_result_tables.gd",
	"res://tests/unit/test_lingering.gd",
	"res://tests/unit/test_snafu.gd",
]


func _init() -> void:
	var total_checks := 0
	var all_failures: Array[String] = []
	var suite_count := 0

	print("")
	print("Atlantic Chase - suite di test")
	print("=".repeat(64))

	for path: String in SUITES:
		var script: Variant = load(path)
		if script == null:
			all_failures.append("impossibile caricare %s" % path)
			continue
		# Una suite che non si carica NON deve passare inosservata. Prima il
		# runner la saltava e stampava "TUTTO OK" lo stesso: un errore di
		# compilazione in core/ faceva sparire una suite intera senza che
		# nessuno se ne accorgesse, e il conto delle verifiche calava in
		# silenzio. Un test che non gira e' un test fallito.
		var inst: Variant = script.new()
		if inst == null:
			all_failures.append("%s: la suite non si istanzia "
				% path + "(errore di compilazione in questo file o in un suo "
				+ "dipendente)")
			continue
		var t: TestCase = inst
		suite_count += 1
		t.run()
		total_checks += t.check_count()
		var f := t.failures()
		# una suite che produce MENO verifiche del previsto si e' interrotta a
		# meta' per un errore a runtime: e' un fallimento, non un OK
		var want := int(EXPECTED.get(path, -1))
		if want >= 0 and t.check_count() < want:
			all_failures.append(("%s: solo %d verifiche su %d attese - "
				+ "un test si e' interrotto a meta'")
				% [t.name(), t.check_count(), want])
			f.append("interrotta: %d verifiche invece di %d"
				% [t.check_count(), want])
		var status := "OK  " if f.is_empty() else "FALLITO"
		print("%-7s %-42s %4d verifiche" % [status, t.name(), t.check_count()])
		for msg in f:
			print("          - %s" % msg)
			all_failures.append("%s: %s" % [t.name(), msg])

	print("=".repeat(64))
	if all_failures.is_empty():
		print("TUTTO OK  -  %d suite, %d verifiche" % [suite_count, total_checks])
		quit(0)
	else:
		print("%d FALLIMENTI su %d verifiche (%d suite)"
			% [all_failures.size(), total_checks, suite_count])
		quit(1)
