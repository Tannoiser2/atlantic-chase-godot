class_name TrajectoryTotal
extends RefCounted

## Totale Traiettoria (RB p.17-18).
##
## Determina la colonna da usare sulle tabelle di Attacco Aereo, Ingaggiare,
## Ricerca Navale e Attacco Furtivo. Tre passi:
##
##   1. Traiettoria piu' Lunga - fra la TF Attiva e le eventuali TF
##      Coordinatrice / Supporto Aereo del giocatore ATTIVO, si prende la
##      lunghezza maggiore. (La TF Attiva resta Attiva anche se non e' la sua
##      lunghezza a essere usata.)
##   2. Numero Base = quella lunghezza + lunghezza della TF Bersaglio.
##   3. Sottrazioni = lunghezze delle TF Coordinatrice / Supporto Aereo del
##      giocatore INATTIVO. Il risultato non scende sotto zero.
##
## Una Stazione conta zero segmenti, quindi il numero base puo' essere zero.

class Designations extends RefCounted:
	## Lunghezze in segmenti. -1 significa "non designata".
	var active: int = 0
	var active_coordinating: int = -1
	var active_air_support: int = -1
	var target: int = 0
	var target_coordinating: int = -1
	var target_air_support: int = -1

	func _init(p_active: int = 0, p_target: int = 0) -> void:
		active = p_active
		target = p_target


## Passo 1: la lunghezza da usare per il giocatore Attivo.
static func longest_active(d: Designations) -> int:
	var best := d.active
	if d.active_coordinating > best:
		best = d.active_coordinating
	if d.active_air_support > best:
		best = d.active_air_support
	return best


## Passo 2.
static func base_number(d: Designations) -> int:
	return longest_active(d) + d.target


## Passo 3.
static func subtractions(d: Designations) -> int:
	var s := 0
	if d.target_coordinating > 0:
		s += d.target_coordinating
	if d.target_air_support > 0:
		s += d.target_air_support
	return s


## Il Totale Traiettoria finale (mai negativo).
static func compute(d: Designations) -> int:
	return maxi(0, base_number(d) - subtractions(d))


## Spiegazione passo-passo, da mostrare nella UI accanto al numero.
## Un giocatore deve poter verificare il conto senza fidarsi del programma.
static func explain(d: Designations) -> Array[String]:
	var out: Array[String] = []
	var la := longest_active(d)
	var parts: Array[String] = ["TF Attiva %d" % d.active]
	if d.active_coordinating >= 0:
		parts.append("Coordinatrice %d" % d.active_coordinating)
	if d.active_air_support >= 0:
		parts.append("Supporto Aereo %d" % d.active_air_support)
	out.append("1. Traiettoria piu' lunga fra [%s] = %d" % [", ".join(parts), la])
	out.append("2. Numero base = %d + %d (Bersaglio) = %d" % [la, d.target, base_number(d)])
	var sub := subtractions(d)
	if sub > 0:
		var sp: Array[String] = []
		if d.target_coordinating > 0:
			sp.append("Coordinatrice %d" % d.target_coordinating)
		if d.target_air_support > 0:
			sp.append("Supporto Aereo %d" % d.target_air_support)
		out.append("3. Sottrazioni del giocatore inattivo [%s] = -%d"
			% [", ".join(sp), sub])
	else:
		out.append("3. Nessuna sottrazione")
	out.append("Totale Traiettoria = %d" % compute(d))
	return out
