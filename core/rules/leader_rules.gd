class_name LeaderRules
extends RefCounted

## Comandanti, RB p.10. Le descrizioni restano qui accanto alla disponibilita':
## la UI puo' dire che cosa fa una pedina anche quando l'effetto non e' ancora
## automatizzato, senza trasformare una semplice presenza nel setup in una regola.

const EFFECTS := {
	"Raeder": "Due volte: durante Passare puo' dichiarare Passare Tutti; ogni TF tedesca effettua Scorrere del Tempo.",
	"Pound": "Due volte: durante Passare puo' dichiarare Passare Tutti; ogni TF britannica effettua Scorrere del Tempo.",
	"Lutjens": "Una volta: un tentativo di Sottrarre l'Iniziativa riesce automaticamente; la sua TF riceve Manovre Evasive e deve essere Attiva nell'azione successiva prevista.",
	"Krancke": "Una volta: tira 2d6 e aggiunge o sottrae la somma al Totale Traiettoria quando la sua TF e' Attiva o Bersaglio.",
	"Marschall": "Una volta: dopo un tiro durante Azione o Battaglia sostituisce un dado con 6, alle condizioni stampate.",
	"Prien": "Una volta: consente alla sua forza U-Boat la Ricognizione Furtiva in un esagono con porto o base aerea nemici.",
	"Forbes": "Una volta: dopo un tiro durante Azione o Battaglia sostituisce un dado con 6, alle condizioni stampate.",
	"Gensoul": "Una volta: quando la sua TF e' Attiva rimuove Informazioni da una TF britannica o francese designata nell'azione.",
	"Somerville": "Una volta: +2 a un tiro che coinvolge la sua TF, esclusi Meteo e Iniziativa.",
	"Tovey": "Una volta: tira 2d6 e aggiunge o sottrae la somma al Totale Traiettoria quando la sua TF e' Attiva o Bersaglio.",
	"Walker": "Una volta: quando la sua TF coordina, il Modificatore Comune di Coordinamento e' +4.",
}


static func effect_text(name: String) -> String:
	return String(EFFECTS.get(name, "Effetto non trascritto nel motore."))


static func is_implemented(name: String) -> bool:
	return ["Raeder", "Pound"].has(name)


static func has_commander(state: GameState, name: String, side: int) -> bool:
	for tf in state.task_forces:
		if tf.side == side and tf.leader == name:
			return true
	return false


static func pass_all_commander(state: GameState, side: int) -> String:
	var name := "Raeder" if side == TaskForce.Side.KRIEGSMARINE else "Pound"
	if has_commander(state, name, side) and uses_left(state, name) > 0:
		return name
	return ""


static func uses_left(state: GameState, name: String) -> int:
	var maximum := 2 if ["Raeder", "Pound"].has(name) else 1
	return maxi(0, maximum - int(state.commander_uses.get(name, 0)))


static func spend(state: GameState, name: String) -> bool:
	if uses_left(state, name) <= 0:
		return false
	state.commander_uses[name] = int(state.commander_uses.get(name, 0)) + 1
	state.changed.emit()
	return true
