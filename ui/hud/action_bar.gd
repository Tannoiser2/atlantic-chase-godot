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
signal disperse_requested()
signal outcome_requested()
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
var _editor_btn: Button
var _menu_btn: Button
## Dove la mappa mette la frase di guida e i suoi pulsanti.
var guide_box: HBoxContainer
var _lbl_scenario: Label
var _chip_weather: Label
var _chip_initiative: Label
var _chip_phase: Label

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

const AVAILABLE_TOOLTIPS := {
	"SIGNAL": ("Sostituisce un segnalino Informazioni su una Traiettoria "
		+ "nemica con la sua Stazione; non piazza un nuovo segnalino Signal."),
	"AIR_STRIKE": ("Scegli una TF con CV integra, il Punto di Lancio e un "
		+ "esagono bersaglio entro due esagoni."),
}


## L'azione ha bisogno di una Task Force avversaria in gioco?
static func needs_enemy(key: String) -> bool:
	for a in ACTIONS:
		if String(a[0]) == key:
			return bool(a[3])
	return true


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(
		Color(UiTheme.NOTTE, 0.97), UiTheme.ACCIAIO, 1, 8, 10, 7))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	# --- riga della guida e dei comandi di servizio ---
	# A sinistra la frase che dice che cosa aspetta il gioco, col pulsante per
	# farlo; a destra i comandi che non sono azioni di gioco. Prima qui
	# c'erano "<", ">" ed "Editor": strumenti di chi il gioco lo costruisce,
	# non di chi lo gioca.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var guide := PanelContainer.new()
	guide.name = "GuideStrip"
	guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide.add_theme_stylebox_override("panel", UiTheme.box(
		UiTheme.SCAFO_ALTO, UiTheme.OTTONE, 2, 7, 12, 3))
	top.add_child(guide)
	guide_box = HBoxContainer.new()
	guide_box.add_theme_constant_override("separation", 8)
	guide.add_child(guide_box)

	_undo_btn = _mk(top, "Annulla")
	_undo_btn.tooltip_text = "Annulla l'ultima mossa (Ctrl+Z)"
	_undo_btn.pressed.connect(func() -> void: undo_requested.emit())
	_redo_btn = _mk(top, "Rifai")
	_redo_btn.tooltip_text = "Ripete la mossa annullata (Ctrl+Shift+Z)"
	_redo_btn.pressed.connect(func() -> void: redo_requested.emit())
	_sep(top)
	var briefing := _mk(top, "Scenario")
	briefing.tooltip_text = "Obiettivo, fine dello scenario, schieramento e tabelle (B)"
	briefing.pressed.connect(func() -> void: briefing_toggled.emit())
	var out := _mk(top, "Punteggio")
	out.tooltip_text = ("Punteggio corrente, Esito raggiunto e condizioni che "
		+ "vanno valutate a mano (V)")
	out.pressed.connect(func() -> void: outcome_requested.emit())
	var h := _mk(top, "Aiuto")
	h.tooltip_text = "Come si gioca e l'elenco dei comandi (F1)"
	h.pressed.connect(func() -> void: help_toggled.emit())
	_menu_btn = _mk(top, "Menu")
	_menu_btn.tooltip_text = "Salva, carica, reticolo, torna alla scelta dello scenario"
	_menu_btn.pressed.connect(func() -> void: menu_requested.emit())

	# --- le nove azioni ---
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	for a in ACTIONS:
		var b := Button.new()
		b.text = String(a[1])
		b.focus_mode = Control.FOCUS_NONE     # i tasti restano al gioco
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(96, 50)
		b.add_theme_font_override("font", UiTheme.stretto())
		b.add_theme_font_size_override("font_size", 20)
		_set_icon(b, String(a[0]))
		b.pressed.connect(func() -> void: action_requested.emit(String(a[0])))
		row.add_child(b)
		_act_buttons[a[0]] = b
		# Il tasto di scelta rapida, piccolo nell'angolo: chi usa la tastiera
		# lo trova, chi tocca lo schermo non se lo vede in mezzo al nome.
		var key := Label.new()
		key.text = String(a[2])
		key.add_theme_font_override("font", UiTheme.stretto_leggero())
		key.add_theme_font_size_override("font_size", 14)
		key.add_theme_color_override("font_color", UiTheme.CARTA_SPENTA)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		key.offset_left = -18
		key.offset_top = 2
		key.offset_right = -6
		b.add_child(key)


## La riga di stato - che scenario, che tempo fa, a chi tocca - che la mappa
## mette in cima al riquadro in basso. La costruisce la barra perche' e' lei a
## tenerla aggiornata insieme ai pulsanti.
##
## Un contenitore che va a capo: nella colonna stretta delle mappe inserto
## titolo e tre etichette in fila pretendevano 650 px e spingevano il riquadro
## sopra il registro.
func make_status_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 4)
	_lbl_scenario = Label.new()
	_lbl_scenario.add_theme_font_override("font", UiTheme.stretto())
	_lbl_scenario.add_theme_font_size_override("font_size", 22)
	_lbl_scenario.add_theme_color_override("font_color", UiTheme.OTTONE)
	_lbl_scenario.clip_text = true
	_lbl_scenario.custom_minimum_size.x = 300
	row.add_child(_lbl_scenario)
	_chip_weather = _chip(row)
	_chip_initiative = _chip(row)
	_chip_phase = _chip(row)
	return row


func _chip(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiTheme.stretto())
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_stylebox_override("normal", UiTheme.box(
		UiTheme.SCAFO_ALTO, UiTheme.ACCIAIO, 1, 12, 10, 2))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.visible = false
	parent.add_child(l)
	return l


## Che scenario, che tempo fa, a chi tocca. `phase` vuoto = non solitario.
func set_status(scenario_title: String, bad_weather: bool, initiative: String,
		initiative_is_player: bool, phase: String) -> void:
	if _lbl_scenario == null:
		return
	_lbl_scenario.text = scenario_title
	_lbl_scenario.tooltip_text = scenario_title
	_chip_weather.visible = true
	_chip_weather.text = "Meteo cattivo" if bad_weather else "Meteo buono"
	_chip_weather.add_theme_color_override("font_color",
		UiTheme.AZZURRO if bad_weather else UiTheme.CARTA)
	_chip_initiative.visible = true
	_chip_initiative.text = "Iniziativa: %s" % initiative
	_chip_initiative.add_theme_color_override("font_color",
		UiTheme.VERDE if initiative_is_player else UiTheme.OTTONE)
	_chip_phase.visible = phase != ""
	_chip_phase.text = phase
	_chip_phase.add_theme_color_override("font_color", UiTheme.CARTA_SPENTA)


## Dove ancorare il menu a comparsa: sotto il suo pulsante.
func menu_anchor() -> Vector2:
	if _menu_btn == null:
		return Vector2.ZERO
	var r := _menu_btn.get_global_rect()
	return Vector2(r.end.x, r.end.y)


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
	b.add_theme_constant_override("icon_max_width", 26)
	b.add_theme_constant_override("h_separation", 6)


func _mk(parent: Control, text: String) -> Button:
	var b := UiTheme.button(text, "normale", 38.0, 18)
	parent.add_child(b)
	return b


static func _action_style(available: bool, hover: bool = false) -> StyleBoxFlat:
	if available:
		return UiTheme.box(Color("17524a") if hover else UiTheme.VERDE_SCURO,
			UiTheme.VERDE, 2, 7, 8, 5)
	return UiTheme.box(Color("0f1820"), Color("27333d"), 1, 7, 8, 5)


func _sep(parent: Control) -> void:
	var s := VSeparator.new()
	parent.add_child(s)


## Aggiorna abilitazione e tooltip. `reasons` associa la chiave azione al
## motivo per cui non e' disponibile (stringa vuota = disponibile).
func update_state(reasons: Dictionary, can_undo: bool, can_redo: bool,
		editor_active: bool = false) -> void:
	for key_v: Variant in _act_buttons.keys():
		var b: Button = _act_buttons[key_v]
		var why := String(reasons.get(key_v, ""))
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else String(AVAILABLE_TOOLTIPS.get(key_v,
			"Dichiara l'azione con la TF selezionata"))
		b.add_theme_stylebox_override("normal", _action_style(why == ""))
		b.add_theme_stylebox_override("hover", _action_style(why == "", true))
		b.add_theme_stylebox_override("pressed", _action_style(why == "", true))
		b.add_theme_stylebox_override("disabled", _action_style(false))
		b.add_theme_color_override("font_color", Color("e6fff3"))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_disabled_color", UiTheme.SPENTO)
		# l'icona di un'azione spenta si spegne con lei
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.28))
	if _undo_btn:
		_undo_btn.disabled = not can_undo
	if _redo_btn:
		_redo_btn.disabled = not can_redo
