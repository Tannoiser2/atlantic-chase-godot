extends SceneTree

## Runner headless.  Uso:
##     godot --headless --path . --script res://tests/run_tests.gd
##
## Esce con codice 1 se un test fallisce, cosi' e' usabile direttamente in CI.

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
		var t: TestCase = script.new()
		suite_count += 1
		t.run()
		total_checks += t.check_count()
		var f := t.failures()
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
