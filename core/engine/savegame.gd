class_name SaveGame
extends RefCounted

## Salvare e riprendere una partita.
##
## Il grosso del lavoro era gia' fatto: GameState sa serializzarsi per intero -
## Task Force, Traiettorie, segnalini, meteo, Iniziativa, Punti Vittoria,
## premi una tantum gia' scattati, Convogli arrivati, e persino lo stato del
## generatore di dadi. Mancava solo scriverlo su disco.
##
## Salvare il seme e la posizione del RNG non e' un dettaglio: senza, ricaricare
## e rifare la stessa mossa darebbe tiri diversi, e si potrebbe salvare prima di
## una Battaglia per ripeterla finche' non va bene. Con il RNG dentro il
## salvataggio, ricaricare restituisce la stessa partita, non una simile.

const DIR := "user://partite/"
const EXT := ".acsave"
const FORMAT := 1


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


static func path_for(slot_name: String) -> String:
	return DIR + slot_name + EXT


## I salvataggi presenti, dal piu' recente.
## Ritorna [{ name, path, scenario, round, saved_at }].
static func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_ensure_dir()
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(EXT):
			continue
		var fh := FileAccess.open(DIR + f, FileAccess.READ)
		if fh == null:
			continue
		var parsed: Variant = JSON.parse_string(fh.get_as_text())
		fh.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var doc: Dictionary = parsed
		out.append({
			"name": f.substr(0, f.length() - EXT.length()),
			"path": DIR + f,
			"scenario": String(doc.get("scenario_title", doc.get("scenario", ""))),
			"round": int((doc.get("state", {}) as Dictionary).get("round", 1)),
			"saved_at": String(doc.get("saved_at", "")),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["saved_at"]) > String(b["saved_at"]))
	return out


## Scrive la partita. Ritorna { ok, error, path }.
static func save(state: GameState, scenario_id: String, scenario_title: String,
		slot_name: String) -> Dictionary:
	_ensure_dir()
	var doc := {
		"format": FORMAT,
		"scenario": scenario_id,
		"scenario_title": scenario_title,
		"saved_at": Time.get_datetime_string_from_system(true),
		"state": state.to_dict(),
	}
	var p := path_for(slot_name)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "impossibile scrivere %s" % p, "path": p}
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	return {"ok": true, "error": "", "path": p}


## Legge un salvataggio SENZA applicarlo: chi chiama deve prima caricare lo
## scenario giusto, se no si applicherebbe uno stato a una mappa sbagliata.
## Ritorna { ok, error, scenario, state }.
static func read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "impossibile aprire %s" % path,
			"scenario": "", "state": {}}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "salvataggio illeggibile: %s" % path,
			"scenario": "", "state": {}}
	var doc: Dictionary = parsed
	if int(doc.get("format", 0)) != FORMAT:
		return {"ok": false, "scenario": "", "state": {},
			"error": "salvataggio di un'altra versione (formato %d, atteso %d)"
				% [int(doc.get("format", 0)), FORMAT]}
	return {"ok": true, "error": "", "scenario": String(doc.get("scenario", "")),
		"state": doc.get("state", {})}


static func erase(path: String) -> bool:
	return DirAccess.remove_absolute(path) == OK
