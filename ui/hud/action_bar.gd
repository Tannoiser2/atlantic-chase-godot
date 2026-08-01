class_name ActionBar
extends PanelContainer

## Barra dei comandi della mappa operazionale.
##
## Ogni pulsante mostra fra parentesi la scorciatoia da tastiera: i comandi
## restano quelli, la barra li rende scopribili senza aprire l'elenco.
##
## I pulsanti delle azioni si disabilitano da soli quando l'azione non e'
## dichiarabile - nessuna TF selezionata, nessun avversario, o tabella non
## ancora trascritta - e il motivo finisce nel tooltip invece di lasciare il
## giocatore a chiedersi perche' non succede nulla.

signal action_requested(key: String)
signal time_lapse_requested()
signal disperse_requested()
signal undo_requested()
signal redo_requested()
signal briefing_toggled()
signal help_toggled()
signal scenario_step(delta: int)
signal editor_toggled()
signal grid_cycled()
signal menu_requested()

var _act_buttons: Dictionary = {}     ## chiave azione -> Button
var _undo_btn: Button
var _redo_btn: Button

## Tutte e nove le azioni del gioco, comprese quelle che non si possono ancora
## dichiarare. Restano visibili e disabilitate, con il motivo nel tooltip:
## nasconderle lascerebbe il giocatore a chiedersi dove sono finite, e a
## dubitare che il gioco sia completo. Chi conosce Atlantic Chase le cerca.
##
## Il quarto campo dice se l'azione ha bisogno di una Task Force avversaria.
## Passare, Completamento e Traiettoria si dichiarano anche da soli in mezzo
## all'oceano, e pretendere un bersaglio le renderebbe indichiarabili.
const ACTIONS := [
	["ENGAGE", "Ingaggia", "1", true],
	["NAVAL_SEARCH", "Ricerca", "2", true],
	["AIR_STRIKE", "Aereo", "3", true],
	["STEALTH_ATTACK", "Furtivo", "4", true],
	["TRAJECTORY", "Traiettoria", "5", false],
	["COMPLETION", "Completamento", "6", false],
	["PASS", "Passare", "7", false],
	["REORGANIZE", "Riorganizza", "8", false],
	["SIGNAL", "Segnali", "9", false],
]


## L'azione ha bisogno di una Task Force avversaria in gioco?
static func needs_enemy(key: String) -> bool:
	for a in ACTIONS:
		if String(a[0]) == key:
			return bool(a[3])
	return true


func _ready() -> void:
	add_theme_stylebox_override("panel", _panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	for a in ACTIONS:
		var b := _mk(row, "%s (%s)" % [a[1], a[2]])
		_set_icon(b, String(a[0]))
		b.pressed.connect(func() -> void: action_requested.emit(String(a[0])))
		_act_buttons[a[0]] = b

	_sep(row)
	_mk(row, "Scorrere del Tempo (T)").pressed.connect(
		func() -> void: time_lapse_requested.emit())
	var dsp := _mk(row, "Disperdi (D)")
	dsp.tooltip_text = ("Disperdere un Convoglio: incassa un solo Colpo per "
		+ "attacco, ma vale un punto in meno se arriva a destinazione. "
		+ "La scelta non si puo' disfare.")
	dsp.pressed.connect(func() -> void: disperse_requested.emit())

	_sep(row)
	_undo_btn = _mk(row, "Annulla")
	_undo_btn.pressed.connect(func() -> void: undo_requested.emit())
	_redo_btn = _mk(row, "Rifai")
	_redo_btn.pressed.connect(func() -> void: redo_requested.emit())

	_sep(row)
	_mk(row, "Briefing (B)").pressed.connect(func() -> void: briefing_toggled.emit())
	var prev := _mk(row, "<")
	prev.tooltip_text = "Scenario precedente"
	prev.pressed.connect(func() -> void: scenario_step.emit(-1))
	var nxt := _mk(row, ">")
	nxt.tooltip_text = "Scenario successivo"
	nxt.pressed.connect(func() -> void: scenario_step.emit(1))
	_mk(row, "Reticolo (G)").pressed.connect(func() -> void: grid_cycled.emit())
	_mk(row, "Editor (E)").pressed.connect(func() -> void: editor_toggled.emit())
	var h := _mk(row, "?")
	h.tooltip_text = "Elenco dei comandi (F1)"
	h.pressed.connect(func() -> void: help_toggled.emit())
	_mk(row, "Menu").pressed.connect(func() -> void: menu_requested.emit())


const ICON_DIR := "res://assets/art/actions/"


## Icona dell'azione, se e' stata generata. Il testo resta: l'icona lo
## accompagna, non lo sostituisce. Un pulsante con la sola immagine costringe
## a indovinare, e queste nove azioni non si indovinano.
func _set_icon(b: Button, key: String) -> void:
	var path := ICON_DIR + key + ".png"
	if not ResourceLoader.exists(path):
		return
	b.icon = load(path)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 22)
	b.add_theme_constant_override("h_separation", 6)


func _mk(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = " %s " % text
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE     # i tasti restano al gioco
	parent.add_child(b)
	return b


func _sep(parent: Control) -> void:
	var s := VSeparator.new()
	parent.add_child(s)


static func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.92)
	sb.border_color = Color(0.45, 0.60, 0.72, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Aggiorna abilitazione e tooltip. `reasons` associa la chiave azione al
## motivo per cui non e' disponibile (stringa vuota = disponibile).
func update_state(reasons: Dictionary, can_undo: bool, can_redo: bool) -> void:
	for key_v: Variant in _act_buttons.keys():
		var b: Button = _act_buttons[key_v]
		var why := String(reasons.get(key_v, ""))
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Dichiara l'azione con la TF selezionata"
	if _undo_btn:
		_undo_btn.disabled = not can_undo
	if _redo_btn:
		_redo_btn.disabled = not can_redo
