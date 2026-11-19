class_name CommonModifiers
extends RefCounted

## I quattro Modificatori Comuni (RB pp.45-47) e i modificatori stampati sulla
## Tabella dell'Attacco Furtivo (RB p.41).
##
## Fino a questo file NON esistevano. `ActionEngine.resolve` tirava 2d6 e
## sommava soltanto `Declaration.modifier`, che nessuno riempiva se non una
## procedura solitaria (il +3 di N3): Supporto Aereo, Contatto, Manovre Evasive
## e Coordinamento contavano per la LUNGHEZZA nel Totale Traiettoria e basta.
## Il regolamento li chiede in tutte e quattro le azioni su tabella - "Calcolate
## il Totale Traiettoria, tirate 2d6. Applicate i Modificatori Comuni" (RB
## pp.27, 31, 33, 41) - e chi subisce l'azione non poteva nemmeno designare le
## proprie forze.
##
## Le tabelle qui sotto sono lette sulle pagine renderizzate, non sul testo
## estratto:
##
##   SUPPORTO AEREO (p.45)        Attivo   Bersaglio
##     nell'esagono bersaglio       +3        -2
##     esagono adiacente            +2        -1
##     a due esagoni                +1         0
##   Solo con Meteo Buono.
##
##   CONTATTO (p.46), solo l'Attivo, se la Stazione o il segmento bersaglio ha
##   un segnalino Contatto: +4 molto lenta, +3 lenta, +2 media o veloce.
##
##   MANOVRE EVASIVE (p.46), solo l'Inattivo, spendendo il segnalino della TF
##   Bersaglio: -1 Meteo Buono, -2 Meteo Avverso.
##
##   COORDINAMENTO (p.47): Attivo +2 Meteo Buono, +1 Avverso; Bersaglio -1
##   sempre. La forza Coordinatrice - una TF o una forza Furtiva - deve stare
##   nell'esagono Bersaglio.
##
## Linea Artica e Zona U-Boat (dato in `core/data/map_zones.json`):
##   - p.45: un Punto di Lancio o un bersaglio sulla Linea Artica e' sempre in
##     Meteo Avverso, quindi li' il Supporto Aereo non si applica (ma puo'
##     attraversarla);
##   - p.41 e tabella stampata: +3 all'Attacco Furtivo se il bersaglio e' nella
##     Zona U-Boat, per qualunque forza Furtiva.

## Le azioni a cui si applicano (RB p.23: "Attacco Aereo, Ingaggiare, Ricerca
## Navale ed Attacco Furtivo").
const APPLIES_TO := ["AIR_STRIKE", "ENGAGE", "NAVAL_SEARCH", "STEALTH_ATTACK"]

## Indice = distanza in esagoni fra Punto di Lancio ed esagono Bersaglio.
const AIR_SUPPORT_ACTIVE := [3, 2, 1]
const AIR_SUPPORT_TARGET := [-2, -1, 0]
const AIR_SUPPORT_RANGE := 2

## Indice = TimeLapse.Speed (molto lenta, lenta, media, veloce).
const CONTACT_BY_SPEED := [4, 3, 2, 2]

## RB p.41, stampato sulla Tabella dell'Attacco Furtivo.
const DISPERSED_CONVOY_BONUS := 2


static func applies_to(action_key: String) -> bool:
	return APPLIES_TO.has(action_key)


## Valore del Supporto Aereo a quella distanza; 0 fuori raggio.
static func air_support_value(distance: int, for_active: bool) -> int:
	if distance < 0 or distance > AIR_SUPPORT_RANGE:
		return 0
	return int(AIR_SUPPORT_ACTIVE[distance]) if for_active \
		else int(AIR_SUPPORT_TARGET[distance])


static func contact_value(speed: int) -> int:
	return int(CONTACT_BY_SPEED[clampi(speed, 0, CONTACT_BY_SPEED.size() - 1)])


static func evasive_value(weather: int) -> int:
	return -2 if weather == TimeLapse.Weather.BAD else -1


static func coordination_value(weather: int, for_active: bool) -> int:
	if not for_active:
		return -1
	return 1 if weather == TimeLapse.Weather.BAD else 2


## L'esagono Bersaglio della dichiarazione. Ingaggio e Ricerca Navale non lo
## portano sempre scritto: li' e' l'esagono condiviso, e per una Stazione e' il
## suo.
static func target_hex_of(dec: ActionEngine.Declaration) -> Vector2i:
	if dec.target_hex != Vector2i.MAX:
		return dec.target_hex
	if dec.target != null and dec.target.trajectory.is_station():
		return dec.target.trajectory.station_hex
	return Vector2i.MAX


## Il Punto di Lancio del Supporto Aereo dell'Attivo. Nell'Attacco Aereo "la
## fonte dell'Attacco Aereo e' automaticamente la forza di Supporto Aereo" (RB
## p.27), quindi e' il Punto di Lancio dell'attacco.
static func active_air_hex(dec: ActionEngine.Declaration) -> Vector2i:
	if dec.action_key == "AIR_STRIKE":
		return dec.launch_hex
	if dec.active_air_support_hex != Vector2i.MAX:
		return dec.active_air_support_hex
	return _nearest_launch_hex(dec.active_air_support, target_hex_of(dec))


## Il Punto di Lancio del Supporto Aereo del Bersaglio.
static func target_air_hex(dec: ActionEngine.Declaration) -> Vector2i:
	if dec.target_air_support_hex != Vector2i.MAX:
		return dec.target_air_support_hex
	return _nearest_launch_hex(dec.target_air_support, target_hex_of(dec))


## Chi designa una TF di Supporto Aereo senza dire da quale esagono lancia
## intende quello che gli rende di piu': il piu' vicino al bersaglio.
static func _nearest_launch_hex(tf: TaskForce, th: Vector2i) -> Vector2i:
	if tf == null or th == Vector2i.MAX:
		return Vector2i.MAX
	var best := Vector2i.MAX
	var best_d := 99
	for h in ActionEngine.air_launch_hexes(tf):
		var d := Hex.distance(h, th)
		if d < best_d:
			best_d = d
			best = h
	return best


## Somma i modificatori che la dichiarazione si e' guadagnata.
## Ritorna { "total": int, "lines": Array[String] }: una riga per modificatore,
## col motivo, perche' il giocatore deve poter rifare il conto.
##
## NON spende il segnalino Manovre Evasive: lo fa `ActionEngine.resolve` quando
## si tira davvero, perche' un'Interruzione puo' annullare l'Azione prima.
static func compute(dec: ActionEngine.Declaration, state: GameState) -> Dictionary:
	var lines: Array[String] = []
	var total := 0
	if not applies_to(dec.action_key):
		return {"total": 0, "lines": lines}
	var th := target_hex_of(dec)
	var good := state.weather == TimeLapse.Weather.GOOD

	# --- Supporto Aereo, Attivo e Bersaglio
	for role in [true, false]:
		var for_active: bool = role
		var from: Vector2i = active_air_hex(dec) if for_active \
			else target_air_hex(dec)
		if from == Vector2i.MAX or th == Vector2i.MAX:
			continue
		var who := "dell'Attivo" if for_active else "del Bersaglio"
		if not good:
			lines.append("Supporto Aereo %s: non si applica col Meteo Avverso."
				% who)
			continue
		var d := Hex.distance(from, th)
		if d > AIR_SUPPORT_RANGE:
			continue
		if state.is_arctic(th) or state.is_arctic(from):
			lines.append("Supporto Aereo %s: non si applica, %s e' sulla Linea "
				% [who, "l'esagono Bersaglio" if state.is_arctic(th)
					else "il Punto di Lancio"]
				+ "Artica (sempre Meteo Avverso).")
			continue
		var v := air_support_value(d, for_active)
		total += v
		lines.append("Supporto Aereo %s, %s: %+d" % [who,
			["nell'esagono Bersaglio", "esagono adiacente", "a due esagoni"][d], v])

	# --- Contatto
	if dec.target != null and th != Vector2i.MAX \
			and dec.target.trajectory.has_contact_at(th):
		var cv := contact_value(dec.target.speed)
		total += cv
		lines.append("Contatto sul bersaglio (TF %s): %+d"
			% [TimeLapse.SPEED_LABELS[clampi(dec.target.speed, 0, 3)], cv])

	# --- Manovre Evasive
	if dec.target_spends_evasive and dec.target != null and dec.target.evasive:
		var ev := evasive_value(state.weather)
		total += ev
		lines.append("Manovre Evasive spese da %s: %+d"
			% [dec.target.display_name(), ev])

	# --- Coordinamento
	if dec.active_coordinating != null or not dec.active_coordinating_stealth.is_empty():
		var ca := coordination_value(state.weather, true)
		# Walker (RB p.10): "Quando la sua Task Force e' la Task Force
		# Coordinatrice, il Modificatore Comune per il Coordinamento e' +4."
		if dec.leader_benefits.has("Walker") and dec.active_coordinating != null \
				and dec.active_coordinating.leader == "Walker":
			ca = LeaderRules.WALKER_COORDINATION
		total += ca
		lines.append("Coordinamento dell'Attivo (%s): %+d"
			% [_coordinator_name(dec.active_coordinating,
				dec.active_coordinating_stealth), ca])
	if dec.target_coordinating != null or not dec.target_coordinating_stealth.is_empty():
		var ct := coordination_value(state.weather, false)
		total += ct
		lines.append("Coordinamento del Bersaglio (%s): %+d"
			% [_coordinator_name(dec.target_coordinating,
				dec.target_coordinating_stealth), ct])

	# --- Somerville (RB p.10): "+2 a qualsiasi tiro di dado o dadi che
	# coinvolge la TF di questo Comandante. 'Coinvolge' significa che la Task
	# Force e' designata in una azione."
	if dec.leader_benefits.has("Somerville"):
		total += LeaderRules.SOMERVILLE_BONUS
		lines.append("Somerville: %+d" % LeaderRules.SOMERVILLE_BONUS)

	# --- Tabella dell'Attacco Furtivo
	if dec.action_key == "STEALTH_ATTACK":
		if dec.acting_side() == TaskForce.Side.KRIEGSMARINE \
				and _has_dispersed_convoy(dec.target):
			total += DISPERSED_CONVOY_BONUS
			lines.append("Attacco tedesco a un Convoglio Disperso: %+d"
				% DISPERSED_CONVOY_BONUS)
		if th != Vector2i.MAX and state.in_uboat_zone(th):
			total += UBOAT_ZONE_BONUS
			lines.append("Bersaglio nella Zona U-Boat: %+d" % UBOAT_ZONE_BONUS)
	return {"total": total, "lines": lines}


## Tabella Attacco Furtivo stampata sulla mappa: "+3 in U-Boat Zone".
const UBOAT_ZONE_BONUS := 3


static func _coordinator_name(tf: TaskForce, stealth: Dictionary) -> String:
	if tf != null:
		return tf.display_name()
	return "forza %s" % Stealth.kind_name(int(stealth.get("kind", -1)))


static func _has_dispersed_convoy(tf: TaskForce) -> bool:
	if tf == null:
		return false
	for ship in Convoy.convoys_in(tf):
		if ship.dispersed and not ship.sunk:
			return true
	return false


# ------------------------------------------------------------- designazioni --

## Che cosa una parte PUO' designare per questa dichiarazione.
##
## Ritorna:
##   coordinating_tfs      Array[TaskForce]  nell'esagono Bersaglio
##   coordinating_stealth  Array[Dictionary] forze Furtive nell'esagono Bersaglio
##   air_tfs               Array[Dictionary] { "tf", "hex", "distance" }
##   air_bases             Array[Dictionary] { "base", "hex", "distance" }
##   evasive               bool  la TF Bersaglio ha un segnalino da spendere
##
## Regole applicate: una sola Coordinatrice e una sola fonte di Supporto Aereo
## per giocatore (pp.45, 47); la Coordinatrice sta nell'esagono Bersaglio; la
## fonte aerea e' entro due esagoni e serve il Meteo Buono; la TF Attiva e la
## TF Bersaglio non si designano come propria spalla. Nell'Attacco Aereo
## l'Attivo non ha una fonte da scegliere: e' quella dell'attacco.
static func options_for(dec: ActionEngine.Declaration, state: GameState,
		graph: MapGraph, side: int) -> Dictionary:
	var out := {
		"coordinating_tfs": [] as Array[TaskForce],
		"coordinating_stealth": [] as Array[Dictionary],
		"air_tfs": [] as Array[Dictionary],
		"air_bases": [] as Array[Dictionary],
		"evasive": false,
	}
	if not applies_to(dec.action_key) or side < 0:
		return out
	var th := target_hex_of(dec)
	if th == Vector2i.MAX:
		return out
	var is_active := side == dec.acting_side()
	for tf in state.forces_of(side):
		if tf.completed or tf == dec.active or tf == dec.target \
				or PortBox.is_in_box(tf):
			continue
		if tf.trajectory.occupies(th):
			out["coordinating_tfs"].append(tf)
	for f in Stealth.forces_at(state, th):
		if int(f.get("side", -1)) != side:
			continue
		if is_same(f, dec.active_stealth):
			continue
		out["coordinating_stealth"].append(f)
	var wants_air := not (is_active and dec.action_key == "AIR_STRIKE")
	if wants_air and state.weather == TimeLapse.Weather.GOOD:
		for tf in state.forces_of(side):
			if tf.completed or tf == dec.active or tf == dec.target \
					or PortBox.is_in_box(tf):
				continue
			if OptionalRules.enabled(state, "cv_limit") \
					and tf.length() > OptionalRules.CV_MAX_SEGMENTS:
				continue
			var best_hex := Vector2i.MAX
			var best_d := 99
			for h in ActionEngine.air_launch_hexes(tf):
				var d := Hex.distance(h, th)
				if d <= AIR_SUPPORT_RANGE and d < best_d:
					best_d = d
					best_hex = h
			if best_hex != Vector2i.MAX:
				out["air_tfs"].append({"tf": tf, "hex": best_hex, "distance": best_d})
		if graph != null:
			for base in AirBase.sources_for(state, graph, side):
				var bh := AirBase.hex_of(base)
				var bd := Hex.distance(bh, th)
				if bd <= AIR_SUPPORT_RANGE:
					out["air_bases"].append({"base": base, "hex": bh, "distance": bd})
	if not is_active and dec.target != null and dec.target.evasive:
		out["evasive"] = true
	return out


## Designa per `side` tutto quello che gli conviene, senza chiedere.
##
## E' la policy dell'avversario immaginario - AC Solo scenarios 2022 p.1:
## "Coordination: If the imaginary player has another TF or stealth force in the
## target hex, it uses Coordination. Air Support: If the imaginary player has an
## air base or TF with a CV in range, it uses Air Support. Good Weather only." -
## e p.2 per il segnalino: "As soon as possible. If the imaginary player has the
## option to use it, it does so".
##
## Non tocca una designazione gia' fatta: se la procedura stampata ha scelto la
## Coordinatrice, resta quella.
##
## Fra piu' fonti aeree sceglie la piu' vicina (modificatore migliore); a
## parita' una base aerea, che non deve poi fare lo Scorrere del Tempo; poi la
## TF con l'id piu' basso, per un esito stabile a parita' di seme.
static func designate_all(dec: ActionEngine.Declaration, state: GameState,
		graph: MapGraph, side: int, spend_evasive: bool = true) -> void:
	var o := options_for(dec, state, graph, side)
	var is_active := side == dec.acting_side()
	var has_coord := (dec.active_coordinating != null
			or not dec.active_coordinating_stealth.is_empty()) if is_active \
		else (dec.target_coordinating != null
			or not dec.target_coordinating_stealth.is_empty())
	if not has_coord:
		var tfs: Array[TaskForce] = o["coordinating_tfs"]
		var stealths: Array[Dictionary] = o["coordinating_stealth"]
		if not tfs.is_empty():
			var chosen := tfs[0]
			for tf in tfs:
				if tf.id < chosen.id:
					chosen = tf
			if is_active:
				dec.active_coordinating = chosen
			else:
				dec.target_coordinating = chosen
		elif not stealths.is_empty():
			if is_active:
				dec.active_coordinating_stealth = stealths[0]
			else:
				dec.target_coordinating_stealth = stealths[0]
	var has_air := (dec.active_air_support != null
			or dec.active_air_support_hex != Vector2i.MAX) if is_active \
		else (dec.target_air_support != null
			or dec.target_air_support_hex != Vector2i.MAX)
	if not has_air:
		var coord: TaskForce = dec.active_coordinating if is_active \
			else dec.target_coordinating
		var best := {}
		for entry_v: Variant in o["air_bases"]:
			var entry: Dictionary = entry_v
			if best.is_empty() or int(entry["distance"]) < int(best["distance"]):
				best = entry
		for entry_v: Variant in o["air_tfs"]:
			var entry: Dictionary = entry_v
			if entry["tf"] == coord:
				continue
			if best.is_empty() or int(entry["distance"]) < int(best["distance"]) \
					or (int(entry["distance"]) == int(best["distance"])
						and best.has("tf")
						and (entry["tf"] as TaskForce).id < (best["tf"] as TaskForce).id):
				best = entry
		if not best.is_empty():
			set_air_support(dec, is_active, best)
	if not is_active and spend_evasive and bool(o["evasive"]):
		dec.target_spends_evasive = true


## Scrive nella dichiarazione la fonte aerea scelta: una voce di
## `options_for()["air_tfs"]` o `["air_bases"]`.
static func set_air_support(dec: ActionEngine.Declaration, for_active: bool,
		entry: Dictionary) -> void:
	var tf: TaskForce = entry.get("tf", null)
	var base: Dictionary = entry.get("base", {})
	var h: Vector2i = entry.get("hex", Vector2i.MAX)
	if for_active:
		dec.active_air_support = tf
		dec.active_air_support_base = base
		dec.active_air_support_hex = h
	else:
		dec.target_air_support = tf
		dec.target_air_support_base = base
		dec.target_air_support_hex = h
