class_name DiceRNG
extends RefCounted

## Generatore deterministico con seme esplicito.
##
## Ogni tiro viene registrato: chi, perche', cosa e' uscito. Serve per
## riprodurre le partite, per il debug delle regole e per il gioco online onesto.
##
## La modalita' "tiri forzati" e' quella che rende possibile trasformare gli
## episodi del Tutorial in test automatici: il libretto dichiara i risultati dei
## dadi, noi li imponiamo e verifichiamo che lo stato risultante coincida.

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0

## Tiri imposti dall'esterno (test / replay). Consumati in ordine.
var _forced: Array[int] = []

## Storico completo: { "n": int, "faces": int, "reason": String, "forced": bool }
var log: Array[Dictionary] = []


func _init(p_seed: int = 0) -> void:
	seed_value = p_seed
	_rng.seed = p_seed


## Impone la sequenza di risultati successivi (usata dai test golden).
func push_forced(values: Array) -> void:
	for v: Variant in values:
		_forced.append(int(v))


func forced_remaining() -> int:
	return _forced.size()


func _next(faces: int, reason: String) -> int:
	var v: int
	var was_forced := false
	if not _forced.is_empty():
		v = _forced.pop_front()
		was_forced = true
		v = clampi(v, 1, faces)
	else:
		v = _rng.randi_range(1, faces)
	log.append({"n": v, "faces": faces, "reason": reason, "forced": was_forced})
	return v


func d6(reason: String = "") -> int:
	return _next(6, reason)


## Due dadi a sei facce sommati (2d6), come richiesto da quasi tutte le tabelle.
## Registra i due dadi separatamente e poi la somma, perche' alcune regole
## avanzate guardano i dadi singoli (es. "LOWEST 2", "HIGHEST 2").
func d6x2(reason: String = "") -> int:
	var a := _next(6, reason + " (dado 1)")
	var b := _next(6, reason + " (dado 2)")
	log.append({"n": a + b, "faces": 12, "reason": reason + " (somma)", "forced": false})
	return a + b


## Ultimi due dadi singoli tirati, per le regole che li leggono separatamente.
func last_pair() -> Array[int]:
	var out: Array[int] = []
	for i in range(log.size() - 1, -1, -1):
		if log[i]["faces"] == 6:
			out.push_front(log[i]["n"])
			if out.size() == 2:
				break
	return out


## Lo stato interno e' un intero SENZA SEGNO a 64 bit, e JSON non ha interi:
## salvandolo come numero diventa un float a doppia precisione e perde i bit
## bassi, cioe' proprio quelli che contano. Ricaricando, la partita ripartiva
## da un punto vicino ma diverso della sequenza, e i tiri successivi non
## coincidevano piu'. Va scritto come STRINGA, che JSON conserva esatta.
func to_dict() -> Dictionary:
	return {"seed": seed_value, "state": str(_rng.state),
		"forced": _forced.duplicate(), "log_size": log.size()}


func restore(d: Dictionary) -> void:
	seed_value = int(d.get("seed", 0))
	_rng.seed = seed_value
	if d.has("state"):
		var raw: Variant = d["state"]
		# i salvataggi vecchi lo scrivevano come numero: si leggono lo stesso
		_rng.state = String(raw).to_int() if typeof(raw) == TYPE_STRING \
			else int(raw)
	_forced.clear()
	for v_v: Variant in d.get("forced", []):
		_forced.append(int(v_v))
