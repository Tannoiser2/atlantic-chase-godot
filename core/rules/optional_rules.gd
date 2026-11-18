class_name OptionalRules
extends RefCounted

## Le tre Regole Opzionali di RB p.62. Sono SPENTE se nessuno le accende.
##
## La terza - "La Battaglia Rimuove le Manovre Evasive" - era applicata sempre:
## `Battle.finish` toglieva il segnalino a tutte e due le Task Force citando
## "RB p.62" come se fosse la regola. E' l'ultima pagina del regolamento, sotto
## il titolo "Regole Opzionali".
##
##   damaged_ship_limit   una TF con una nave Danneggiata non puo' eseguire
##                        Attacco Aereo, Ingaggio o Ricerca Navale; puo' ancora
##                        coordinare e dare Supporto Aereo.
##   cv_limit             una TF con una CV da' Supporto Aereo o esegue un
##                        Attacco Aereo solo se e' una Stazione o una
##                        Traiettoria di sei segmenti o meno.
##   battle_removes_evasive  a fine Battaglia le due TF perdono il segnalino.

const KEYS := ["damaged_ship_limit", "cv_limit", "battle_removes_evasive"]

const LABELS := {
	"damaged_ship_limit": "Limitazione per Nave Danneggiata",
	"cv_limit": "Limite CV",
	"battle_removes_evasive": "La Battaglia rimuove le Manovre Evasive",
}

const CV_MAX_SEGMENTS := 6


static func enabled(state: GameState, key: String) -> bool:
	return state != null and bool(state.optional_rules.get(key, false))


static func declaration_error(dec: ActionEngine.Declaration,
		state: GameState) -> String:
	if enabled(state, "damaged_ship_limit") and dec.active != null \
			and ["AIR_STRIKE", "ENGAGE", "NAVAL_SEARCH"].has(dec.action_key):
		for ship in dec.active.afloat_ships():
			if ship.damaged:
				return ("regola opzionale: %s ha una nave Danneggiata e non puo' "
					+ "eseguire questa azione") % dec.active.display_name()
	if enabled(state, "cv_limit"):
		var carriers: Array[TaskForce] = []
		if dec.action_key == "AIR_STRIKE" and dec.active != null:
			carriers.append(dec.active)
		for tf in [dec.active_air_support, dec.target_air_support]:
			if tf != null:
				carriers.append(tf)
		for tf in carriers:
			if tf.length() > CV_MAX_SEGMENTS:
				return ("regola opzionale Limite CV: %s ha %d segmenti, piu' di %d"
					% [tf.display_name(), tf.length(), CV_MAX_SEGMENTS])
	return ""
