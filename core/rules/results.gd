class_name Results
extends RefCounted

## Applicazione dei Risultati Comuni (RB p.49-54).
##
## Ogni funzione ritorna la descrizione di cosa e' successo, cosi' che il log di
## partita spieghi l'effetto invece di limitarsi a nominare il risultato.
##
## I risultati che aprono una Battaglia (BATTLE, SURPRISE, e CLOSING/SKIRMISH
## quando si risolvono in battaglia) non sono applicati qui: restituiscono una
## richiesta che il livello superiore usera' per aprire la Mappa di Battaglia (M5).

enum Battle { NONE, FULL, SURPRISE, LIMITED }


static func apply(code: String, active: TaskForce, target: TaskForce,
		target_hex: Vector2i, state: GameState) -> Dictionary:
	var out := {"code": code, "text": "", "battle": Battle.NONE,
		"initiative_changes": false, "steal_initiative_offer": false}
	match code:
		"MISS":
			# RB p.53: nessun effetto, ma se una TF designata ha Informazioni
			# l'Iniziativa cambia di mano.
			if active != null and active.info_count() > 0:
				out["initiative_changes"] = true
				out["text"] = ("Mancato, ma la TF Attiva ha un segnalino "
					+ "Informazioni: l'Iniziativa cambia di mano.")
			else:
				out["text"] = "Mancato: nessun effetto."
		"CONTACT":
			out["text"] = _contact(target, target_hex)
		"SIGHTED":
			out["text"] = _sighted(target, target_hex)
		"SHADOW":
			out["text"] = _shadow(target, target_hex)
			out["steal_initiative_offer"] = true
		"EARLY_LATE":
			out["text"] = _early_late(target, target_hex, state)
		"LOSE_CONTACT":
			out["text"] = _lose_contact(target, target_hex)
		"CLOSING":
			# RB p.50: piu' veloce -> BATTAGLIA, altrimenti -> CONTATTO
			if active != null and target != null and active.speed > target.speed:
				out["battle"] = Battle.FULL
				out["text"] = "Ridurre le Distanze: la TF Attiva e' piu' veloce -> BATTAGLIA."
			else:
				out["text"] = ("Ridurre le Distanze: la TF Attiva non e' piu' veloce -> "
					+ _contact(target, target_hex))
		"SKIRMISH":
			# RB p.54: piu' veloce -> Battaglia Limitata a scelta, altrimenti CONTATTO
			if active != null and target != null and active.speed > target.speed:
				out["battle"] = Battle.LIMITED
				out["text"] = ("Schermaglia: la TF Attiva e' piu' veloce, puo' iniziare "
					+ "una Battaglia Limitata (un solo round).")
			else:
				out["text"] = ("Schermaglia: la TF Attiva non e' piu' veloce -> "
					+ _contact(target, target_hex))
		"BATTLE":
			out["battle"] = Battle.FULL
			out["text"] = "Battaglia."
		"SURPRISE":
			out["battle"] = Battle.SURPRISE
			out["text"] = "Sorpresa: battaglia con vantaggio di piazzamento e primo fuoco."
		"STEAL_INITIATIVE":
			out["steal_initiative_offer"] = true
			out["text"] = "Il giocatore Inattivo puo' tentare di Sottrarre l'Iniziativa."
		"HIT":
			out["text"] = _hit(target, -1)
		"HIT_IF_SLOW":
			out["text"] = _hit(target, TimeLapse.Speed.SLOW)
		"HIT_IF_VERY_SLOW":
			out["text"] = _hit(target, TimeLapse.Speed.VERY_SLOW)
		"DAMAGED":
			out["text"] = _damage(target)
		"SPLASH":
			out["text"] = "Splash: nessun colpo."
		_:
			out["text"] = "risultato '%s' non ancora implementato" % code
	return out


## Colpo, eventualmente condizionato alla velocita' del bersaglio.
## `max_speed` -1 significa "nessuna condizione"; altrimenti solo le navi con
## velocita' <= max_speed possono essere colpite (Charts: "Colpo, bersaglio
## Lento" e "Colpo, bersaglio Molto Lento").
## La scelta della nave spetta al giocatore Attivo; qui si prende la prima
## ammissibile, preferendo quelle gia' danneggiate perche' e' la scelta
## normalmente piu' dannosa. In M5 la scelta passera' al giocatore.
static func _hit(target: TaskForce, max_speed: int) -> String:
	if target == null:
		return "Colpo: nessun bersaglio."
	var eligible: Array[Ship] = []
	for s in target.afloat_ships():
		if max_speed < 0 or s.speed <= max_speed:
			eligible.append(s)
	if eligible.is_empty():
		if target.ships.is_empty():
			return ("Colpo: la TF %s non ha ancora un elenco navi "
				+ "(statistiche non trascritte).") % target.display_name()
		return ("Colpo: nessuna nave di %s ha la velocita' richiesta, "
			+ "nessun effetto.") % target.display_name()
	eligible.sort_custom(func(a: Ship, b: Ship) -> bool:
		return int(a.damaged) > int(b.damaged))
	var txt := eligible[0].apply_hit()
	target.recompute_speed()
	return "Colpo su %s: %s" % [target.display_name(), txt]


static func _damage(target: TaskForce) -> String:
	if target == null:
		return "Danneggiato: nessun bersaglio."
	var afloat := target.afloat_ships()
	if afloat.is_empty():
		if target.ships.is_empty():
			return ("Danneggiato: la TF %s non ha ancora un elenco navi "
				+ "(statistiche non trascritte).") % target.display_name()
		return "Danneggiato: %s non ha piu' navi a galla." % target.display_name()
	afloat.sort_custom(func(a: Ship, b: Ship) -> bool:
		return int(a.damaged) > int(b.damaged))
	var txt := afloat[0].apply_damage()
	target.recompute_speed()
	return "Danneggiato su %s: %s" % [target.display_name(), txt]


static func _contact(target: TaskForce, h: Vector2i) -> String:
	if target == null:
		return "Contatto: nessun bersaglio."
	if target.trajectory.set_contact_at(h, true):
		return "Contatto assegnato a %s in %s." % [target.display_name(), str(h)]
	return "Contatto: %s non occupa %s." % [target.display_name(), str(h)]


## RB p.54: il Bersaglio diventa subito Stazione nell'esagono bersaglio.
## Segmenti e segnalini Informazioni via; il Contatto sopravvive solo se era
## assegnato al segmento nell'esagono bersaglio.
static func _sighted(target: TaskForce, h: Vector2i) -> String:
	if target == null:
		return "Avvistato: nessun bersaglio."
	var t := target.trajectory
	if t.is_station():
		return "Avvistato: %s era gia' una Stazione." % target.display_name()
	var keep := false
	var i := t.index_of_hex(h)
	if i >= 0:
		keep = bool(t.segments[i]["contact"])
	var n := t.length()
	t.become_station(h, keep)
	return ("Avvistato: %s perde %d segmenti e diventa Stazione in %s%s."
		% [target.display_name(), n, str(h),
			"; conserva il segnalino Contatto" if keep else ""])


## RB p.53: lascia 3 segmenti; il segmento nell'esagono bersaglio non si rimuove.
## Se la Traiettoria ne aveva gia' 3 o meno, nessuna rimozione e Manovre Evasive.
static func _shadow(target: TaskForce, h: Vector2i) -> String:
	if target == null:
		return "Seguire: nessun bersaglio."
	var t := target.trajectory
	if t.length() <= 3:
		if not target.evasive:
			target.evasive = true
			return ("Seguire: %s ha gia' 3 segmenti o meno, nessuna rimozione; "
				+ "riceve Manovre Evasive.") % target.display_name()
		return ("Seguire: %s ha gia' 3 segmenti o meno e possiede gia' Manovre Evasive."
			% target.display_name())
	var removed := 0
	# rimuove dai capi finche' restano 3, senza toccare l'esagono bersaglio
	var guard := 0
	while t.length() > 3 and guard < 40:
		guard += 1
		var removed_this := false
		for end in [0, 1]:
			if t.length() <= 3:
				break
			if t.end_hex(end) == h:
				continue
			t.remove_end(end)
			removed += 1
			removed_this = true
			break
		if not removed_this:
			break
	return ("Seguire: rimossi %d segmenti da %s, ne restano %d."
		% [removed, target.display_name(), t.length()])


## RB p.51: rimuove il segmento bersaglio; se cio' crea un buco, il giocatore
## Attivo sceglie uno dei due tronconi e lo elimina. Qui applichiamo la scelta
## piu' dannosa per il bersaglio (troncone piu' lungo): in M4 completo la scelta
## passera' al giocatore, ma il conteggio dei segmenti resta corretto.
static func _early_late(target: TaskForce, h: Vector2i, state: GameState) -> String:
	if target == null:
		return "In Anticipo o In Ritardo: nessun bersaglio."
	var t := target.trajectory
	if t.is_station():
		return "In Anticipo o In Ritardo: %s e' una Stazione." % target.display_name()
	var i := t.index_of_hex(h)
	if i < 0:
		return ("In Anticipo o In Ritardo: %s non ha segmenti in %s."
			% [target.display_name(), str(h)])
	if t.length() == 1:
		t.become_station(h)
		target.evasive = true
		return ("In Anticipo o In Ritardo: %s perde il suo unico segmento, "
			+ "diventa Stazione e riceve Manovre Evasive.") % target.display_name()

	var before := i
	var after := t.length() - i - 1
	t.segments.remove_at(i)
	if before == 0 or after == 0:
		# nessun buco: il bersaglio prende Manovre Evasive
		if not target.evasive:
			target.evasive = true
			return ("In Anticipo o In Ritardo: rimosso il segmento di %s in %s; "
				+ "non crea buco, quindi riceve Manovre Evasive.")\
				% [target.display_name(), str(h)]
		return ("In Anticipo o In Ritardo: rimosso il segmento di %s in %s (nessun buco)."
			% [target.display_name(), str(h)])

	# buco: si elimina uno dei due tronconi
	var drop_front := before >= after
	var dropped := before if drop_front else after
	if drop_front:
		for k in before:
			t.segments.pop_front()
	else:
		for k in after:
			t.segments.pop_back()
	return ("In Anticipo o In Ritardo: rimosso il segmento in %s; il buco costa a %s "
		+ "altri %d segmenti, ne restano %d.")\
		% [str(h), target.display_name(), dropped, t.length()]


static func _lose_contact(target: TaskForce, h: Vector2i) -> String:
	if target == null:
		return "Perdere il Contatto: nessun bersaglio."
	var t := target.trajectory
	var did := false
	if t.is_station() and t.station_hex == h and t.station_contact:
		t.station_contact = false
		did = true
	var i := t.index_of_hex(h)
	if i >= 0:
		if t.segments[i]["contact"]:
			t.segments[i]["contact"] = false
			did = true
		if t.segments[i]["info"]:
			t.segments[i]["info"] = false
			did = true
	if did:
		return "Perdere il Contatto: rimossi i segnalini di %s in %s." \
			% [target.display_name(), str(h)]
	return "Perdere il Contatto: nessun segnalino da rimuovere in %s." % str(h)
