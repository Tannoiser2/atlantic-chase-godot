extends SceneTree

## Verifica meccanica dei 15 scenari solitari: ogni casella delle Tabelle
## Azioni deve produrre un effetto, un Passare esplicito o un buco dichiarato.
## Utile perche' un testo trascritto nel JSON non prova che il motore lo usi.

const ACTION_TABLES := ["actions", "actions_early", "actions_late", "british_actions"]


func _init() -> void:
	var graph := MapGraph.load_default()
	var failures := 0
	var gaps := 0
	var placeholder_procedures := 0
	var checked := 0
	for id in Scenario.list_ids():
		var opponent := SoloOpponent.load_for(id)
		if opponent == null:
			continue
		var scenario := Scenario.load_by_id(id)
		var victory := Victory.from_scenario(scenario)
		var imaginary := 1 - victory.solo_side
		var seen := {}
		for table_id in ACTION_TABLES:
			if not opponent.has(table_id):
				continue
			var table: SoloTable = opponent.table(table_id)
			for procedure_v: Variant in table.legend.values():
				if String(procedure_v).contains("senza automatismi del motore"):
					placeholder_procedures += 1
			for row in table.rows:
				for code_v: Variant in row["cells"]:
					var code := String(code_v)
					var key := "%s:%s" % [table_id, code]
					if seen.has(key):
						continue
					seen[key] = true
					checked += 1
					var state := GameState.new(graph, 1701)
					state.apply_dict(scenario.to_state_dict())
					var decision := SoloAI.execute_code(code, state, graph,
						ActionEngine.load_default(), scenario.port_control(), imaginary)
					var log_text := " ".join(decision.get("log", []))
					var progresses := bool(decision.get("ok", false)) \
						or bool(decision.get("completion", false)) \
						or String(decision.get("action_key", "")) != "" \
						or bool(decision.get("pass_initiative", false))
					var declared_gap := log_text.contains("non modell") \
						or log_text.contains("non sono ancora") \
						or log_text.contains("non calibrat")
					if declared_gap:
						gaps += 1
						print("BUCO DICHIARATO  %s / %s / %s: %s" % [id, table_id,
							code, log_text])
					elif not progresses:
						failures += 1
						print("BLOCCO  %s / %s / %s: %s" % [id, table_id, code, log_text])
	print("Audit solitario: %d caselle uniche, %d procedure ancora segnaposto, "
		% [checked, placeholder_procedures]
		+ "%d buchi dichiarati, %d blocchi." % [gaps, failures])
	quit(1 if failures > 0 else 0)
