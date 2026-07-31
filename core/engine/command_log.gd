class_name CommandLog
extends RefCounted

## Registro delle mosse con undo/redo.
##
## Scelta implementativa: undo per istantanee dello stato invece che per
## comandi invertibili. Uno stato di Atlantic Chase serializzato pesa pochi KB
## (poche decine di TF, al massimo 15 segmenti ciascuna), quindi il costo in
## memoria e' irrilevante, mentre la correttezza e' garantita: non esiste il
## rischio classico di un undo scritto male che lascia lo stato incoerente.
##
## Il registro serve anche a: replay della partita, salvataggi, PBEM
## (si scambia il log, non lo stato), e debug delle regole.

signal entry_added(entry: Dictionary)
signal undone(entry: Dictionary)
signal redone(entry: Dictionary)

var _entries: Array[Dictionary] = []
var _cursor: int = 0            ## numero di voci applicate
var _base: Dictionary = {}      ## stato iniziale
var _state: GameState = null


func _init(p_state: GameState) -> void:
	_state = p_state
	_base = p_state.to_dict()


## Registra una mossa gia' applicata allo stato.
## `label` e' il testo mostrato nel pannello di log.
func record(label: String, meta: Dictionary = {}) -> void:
	# taglia l'eventuale ramo di redo
	if _cursor < _entries.size():
		_entries.resize(_cursor)
	var e := {
		"label": label,
		"meta": meta,
		"snapshot": _state.to_dict(),
		"index": _entries.size(),
	}
	_entries.append(e)
	_cursor = _entries.size()
	entry_added.emit(e)


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _entries.size()


func undo() -> bool:
	if not can_undo():
		return false
	var e := _entries[_cursor - 1]
	_cursor -= 1
	var target: Dictionary = _base if _cursor == 0 else _entries[_cursor - 1]["snapshot"]
	_state.apply_dict(target)
	undone.emit(e)
	return true


func redo() -> bool:
	if not can_redo():
		return false
	var e := _entries[_cursor]
	_cursor += 1
	_state.apply_dict(e["snapshot"])
	redone.emit(e)
	return true


func entries() -> Array[Dictionary]:
	return _entries


func applied_count() -> int:
	return _cursor


## Etichette delle mosse applicate, per il pannello di log.
func labels() -> Array[String]:
	var out: Array[String] = []
	for i in _cursor:
		out.append(String(_entries[i]["label"]))
	return out


## Log compatto per salvataggio / PBEM: solo etichette e metadati, senza
## istantanee (che si possono ricostruire rigiocando).
func to_dict() -> Dictionary:
	var moves: Array = []
	for i in _cursor:
		moves.append({"label": _entries[i]["label"], "meta": _entries[i]["meta"]})
	return {"base": _base, "moves": moves}
