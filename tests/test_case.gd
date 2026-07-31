class_name TestCase
extends RefCounted

## Micro-framework di test, senza dipendenze esterne.
##
## Volutamente non usiamo gdUnit4: il core e' GDScript puro senza nodi, quindi
## bastano poche funzioni di asserzione e un runner headless. Meno da
## installare, e i test partono in CI con un solo comando.

var _failures: Array[String] = []
var _checks: int = 0
var _current: String = ""


func name() -> String:
	return "TestCase"


## Le sottoclassi implementano questo metodo chiamando i propri test_*().
func run() -> void:
	pass


func _begin(t: String) -> void:
	_current = t


func check(cond: bool, message: String) -> void:
	_checks += 1
	if not cond:
		_failures.append("[%s] %s" % [_current, message])


func eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_checks += 1
	if actual != expected:
		_failures.append("[%s] %s atteso %s, ottenuto %s"
			% [_current, message, str(expected), str(actual)])


func ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	_checks += 1
	if actual == unexpected:
		_failures.append("[%s] %s non doveva essere %s"
			% [_current, message, str(unexpected)])


func true_(cond: bool, message: String = "") -> void:
	check(cond, message + " (atteso vero)")


func false_(cond: bool, message: String = "") -> void:
	check(not cond, message + " (atteso falso)")


func almost(actual: float, expected: float, tol: float, message: String = "") -> void:
	_checks += 1
	if absf(actual - expected) > tol:
		_failures.append("[%s] %s atteso %f +-%f, ottenuto %f"
			% [_current, message, expected, tol, actual])


func failures() -> Array[String]:
	return _failures


func check_count() -> int:
	return _checks
