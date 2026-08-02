class_name SoloTable
extends RefCounted

## Le tabelle a dado del modo solitario.
##
## L'avversario immaginario non ha un'intelligenza: ha delle TABELLE. Si tira
## un dado, si legge la casella, e si esegue quello che dice. Tutte le tabelle
## del fascicolo in solitario hanno la stessa forma - righe scelte da una
## condizione, colonne scelte dal dado - quindi qui c'e' una struttura sola che
## le rappresenta tutte:
##
##   Tabella delle Azioni     riga = quante azioni di Completamento sono
##                            riuscite all'avversario (oppure il meteo);
##                            casella = una lettera che rimanda a una procedura
##   Identificare la TF       riga unica; casella = il tipo di nave che c'era
##                            dentro quella Task Force sconosciuta
##   Rifornimento             riga = meteo; casella = che cosa succede al
##                            Rendezvous
##   Incidente Internazionale riga unica; casella = conseguenza diplomatica
##
## Le PROCEDURE dietro le lettere restano testo. Sono lunghe, piene di
## eccezioni e di giudizi ("scegli la TF piu' vicina", "evita i porti nemici se
## possibile"), e il fascicolo stesso dice che in caso di ambiguita' decide il
## giocatore. Il motore tira il dado, sceglie la riga giusta, applica i
## modificatori e MOSTRA la procedura per esteso: fa la parte meccanica e
## lascia quella di giudizio a chi gioca. Fingere di automatizzarla vorrebbe
## dire inventare decisioni che il fascicolo non prende.

var id: String = ""
var title: String = ""
var note: String = ""

## Righe: [{ "label", "min"/"max" opzionali, "cells": [String] }].
## `cells` ha una voce per valore del dado, da 1 a 6, oppure una sola voce se
## la tabella non dipende dal dado.
var rows: Array[Dictionary] = []

## Modificatori al tiro, con il perche' scritto: { "label", "value" }.
var modifiers: Array[Dictionary] = []

## Legenda: codice della casella -> procedura, per esteso.
var legend: Dictionary = {}


static func from_dict(d: Dictionary) -> SoloTable:
	var t := SoloTable.new()
	t.id = String(d.get("id", ""))
	t.title = String(d.get("title", ""))
	t.note = String(d.get("note", ""))
	for r_v: Variant in d.get("rows", []):
		var r: Dictionary = r_v
		var cells: Array[String] = []
		for c_v: Variant in r.get("cells", []):
			cells.append(String(c_v))
		t.rows.append({"label": String(r.get("label", "")),
			"min": int(r.get("min", -9999)), "max": int(r.get("max", 9999)),
			"cells": cells})
	for m_v: Variant in d.get("modifiers", []):
		var m: Dictionary = m_v
		t.modifiers.append({"label": String(m.get("label", "")),
			"value": int(m.get("value", 0))})
	t.legend = d.get("legend", {})
	return t


## La riga che corrisponde a questo valore di selezione (numero di
## Completamenti riusciti, meteo, ...). Ritorna -1 se nessuna.
func row_for(selector: int) -> int:
	for i in rows.size():
		var r: Dictionary = rows[i]
		if selector >= int(r["min"]) and selector <= int(r["max"]):
			return i
	return -1 if rows.is_empty() else 0


## Legge la tabella. `roll` e' gia' modificato; viene comunque bloccato dentro
## i limiti della riga, perche' una tabella a sei colonne non ha una settima.
##
## Ritorna { ok, error, row, row_label, column, code, text }.
func read(selector: int, roll: int) -> Dictionary:
	var i := row_for(selector)
	if i < 0:
		return {"ok": false, "error": "nessuna riga per il valore %d" % selector,
			"row": -1, "row_label": "", "column": 0, "code": "", "text": ""}
	var r: Dictionary = rows[i]
	var cells: Array = r["cells"]
	if cells.is_empty():
		return {"ok": false, "error": "riga vuota", "row": i,
			"row_label": String(r["label"]), "column": 0, "code": "", "text": ""}
	var col := clampi(roll, 1, cells.size()) - 1
	var code := String(cells[col])
	return {"ok": true, "error": "", "row": i, "row_label": String(r["label"]),
		"column": col + 1, "code": code,
		"text": String(legend.get(code, ""))}


## Somma dei modificatori applicabili. `active` elenca le etichette dei
## modificatori in vigore: il motore non sa da solo se "una nave tedesca e'
## danneggiata", glielo dice chi chiama.
func modifier_total(active: Array) -> int:
	var total := 0
	for m in modifiers:
		if active.has(String(m["label"])):
			total += int(m["value"])
	return total


## Tira e leggi in un colpo solo. Ritorna il risultato di read() con in piu'
## `raw_roll`, `modifier` e `roll`, cosi' chi legge il registro vede il conto.
func roll_and_read(rng: DiceRNG, selector: int,
		active_modifiers: Array = []) -> Dictionary:
	var raw := rng.d6(title if title != "" else id)
	var mod := modifier_total(active_modifiers)
	var out := read(selector, raw + mod)
	out["raw_roll"] = raw
	out["modifier"] = mod
	out["roll"] = raw + mod
	return out


## Riga da mettere nel registro: il tiro, il conto, la casella e la procedura.
static func describe(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return String(result.get("error", "tabella illeggibile"))
	var mod := int(result.get("modifier", 0))
	var head := "1d6 = %d" % int(result.get("raw_roll", 0))
	if mod != 0:
		head += " %+d = %d" % [mod, int(result.get("roll", 0))]
	var row_label := String(result.get("row_label", ""))
	if row_label != "":
		head += "   [%s]" % row_label
	head += "   ->   %s" % String(result.get("code", ""))
	var text := String(result.get("text", ""))
	return head if text == "" else "%s\n%s" % [head, text]
