extends Control

## Schermata iniziale: presentazione e scelta dello scenario.
##
## A sinistra la copertina, a destra l'elenco degli scenari con il briefing di
## quello selezionato, cosi' si sceglie sapendo cosa si sta per giocare invece
## di indovinare da un nome in codice.

const SPLASH := "res://assets/ui/splash.jpg"
const GAME_SCENE := "res://ui/main.tscn"

var _list: ItemList
var _brief: RichTextLabel

## Miniatura dello scenario. Manca per gli scenari senza illustrazione
## generata, e in quel caso sparisce invece di lasciare un riquadro vuoto.
var _art: TextureRect
var _start_btn: Button
var _adv: CheckBox
var _optional: Dictionary = {}      ## chiave Regola Opzionale -> CheckBox
var _resume_btn: Button
var _ids: Array[String] = []


func _ready() -> void:
	UiTheme.install()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_populate()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UiTheme.NOTTE
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28
	row.offset_top = 22
	row.offset_right = -28
	row.offset_bottom = -22
	row.add_theme_constant_override("separation", 26)
	add_child(row)

	# --- copertina ---
	var cover := TextureRect.new()
	var tex: Texture2D = load(SPLASH)
	if tex != null:
		cover.texture = tex
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.custom_minimum_size = Vector2(360, 0)
	cover.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cover.size_flags_stretch_ratio = 0.42
	cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(cover)

	# --- colonna destra ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)

	var title := Label.new()
	title.text = "ATLANTIC CHASE"
	title.add_theme_font_override("font", UiTheme.stampino())
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", UiTheme.OTTONE)
	right.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "La campagna navale della Kriegsmarine, 1939-1942. Scegli uno scenario."
	subtitle.add_theme_color_override("font_color", UiTheme.CARTA_SPENTA)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size.x = 400
	right.add_child(subtitle)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	right.add_child(body)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(380, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _start())
	body.add_child(_list)

	# colonna del briefing: miniatura in cima, testo sotto
	var briefcol := VBoxContainer.new()
	briefcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefcol.size_flags_vertical = Control.SIZE_EXPAND_FILL
	briefcol.custom_minimum_size.x = 380
	briefcol.add_theme_constant_override("separation", 10)
	body.add_child(briefcol)

	_art = TextureRect.new()
	_art.custom_minimum_size = Vector2(0, 170)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.visible = false
	briefcol.add_child(_art)

	var briefpanel := PanelContainer.new()
	briefpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefpanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	briefpanel.add_theme_stylebox_override("panel", _panel_style())
	briefcol.add_child(briefpanel)
	_brief = RichTextLabel.new()
	_brief.bbcode_enabled = true
	_brief.custom_minimum_size.x = 340
	UiTheme.style_rich(_brief, 16)
	briefpanel.add_child(_brief)

	# --- regole ---
	# Sono moduli che si accettano PRIMA di cominciare, non scelte da fare
	# azione per azione: quindi stanno qui, una volta sola.
	var rules := PanelContainer.new()
	rules.add_theme_stylebox_override("panel", _panel_style())
	right.add_child(rules)
	var rules_col := VBoxContainer.new()
	rules_col.add_theme_constant_override("separation", 4)
	rules.add_child(rules_col)
	rules_col.add_child(UiTheme.heading("REGOLE", 18))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 22)
	flow.add_theme_constant_override("v_separation", 4)
	rules_col.add_child(flow)
	_adv = CheckBox.new()
	_adv.text = "Battaglie con le Regole Avanzate"
	_adv.tooltip_text = ("Attitudini (Acquisizione, Accostata, Corsa), Verifica "
		+ "Snafu, Effetti Speciali al posto dei soli Colpi, Effetti Duraturi, "
		+ "Disingaggio, Battaglia Estesa.\nCambia solo le Battaglie: la partita "
		+ "sulla mappa resta identica.")
	_adv.button_pressed = Session.advanced_battle
	_adv.focus_mode = Control.FOCUS_NONE
	flow.add_child(_adv)
	var tips := {
		"damaged_ship_limit": ("Regola Opzionale (RB p.62): una Task Force con "
			+ "una nave Danneggiata non puo' essere la TF Attiva di Ingaggiare "
			+ "ne' di Ricerca Navale."),
		"cv_limit": ("Regola Opzionale (RB p.62): una portaerei da' Supporto "
			+ "Aereo e lancia Attacchi solo con una Traiettoria di sei segmenti "
			+ "o meno."),
		"battle_removes_evasive": ("Regola Opzionale (RB p.62): chi esce da una "
			+ "Battaglia perde il segnalino Manovre Evasive."),
	}
	for key in OptionalRules.KEYS:
		var cb := CheckBox.new()
		cb.text = String(OptionalRules.LABELS.get(key, key))
		cb.tooltip_text = String(tips.get(key, "Regola Opzionale (RB p.62)"))
		cb.button_pressed = bool(Session.optional_rules.get(key, false))
		cb.focus_mode = Control.FOCUS_NONE
		flow.add_child(cb)
		_optional[key] = cb

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	right.add_child(buttons)

	_start_btn = UiTheme.button("Inizia la partita", "primario", 54.0, 24)
	_start_btn.custom_minimum_size.x = 260
	_start_btn.pressed.connect(_start)
	buttons.add_child(_start_btn)

	_resume_btn = UiTheme.button("Riprendi una partita", "normale", 54.0, 20)
	_resume_btn.pressed.connect(_resume)
	_resume_btn.disabled = SaveGame.list_saves().is_empty()
	_resume_btn.tooltip_text = ("Nessuna partita salvata" if _resume_btn.disabled
		else "Riapre un salvataggio, automatico o fatto a mano")
	buttons.add_child(_resume_btn)

	# In un browser "Esci" non esce da niente: si chiude la scheda.
	if not OS.has_feature("web"):
		var quit_btn := UiTheme.button("Esci", "normale", 54.0, 20)
		quit_btn.pressed.connect(func() -> void: get_tree().quit())
		buttons.add_child(quit_btn)

	var credit := RichTextLabel.new()
	credit.bbcode_enabled = true
	credit.fit_content = true
	credit.custom_minimum_size = Vector2(400, 44)
	UiTheme.style_rich(credit, 14)
	credit.add_theme_color_override("default_color", UiTheme.CARTA_SPENTA)
	credit.text = ("[i]Atlantic Chase[/i] e' un gioco di [b]GMT Games[/b], "
		+ "design di Jeremy White, (c) 2020 GMT Games LLC. "
		+ "Implementazione amatoriale non affiliata a GMT, per uso personale. "
		+ "Regole tradotte da G. Sorio.")
	right.add_child(credit)


static func _panel_style() -> StyleBoxFlat:
	return UiTheme.box(UiTheme.SCAFO, UiTheme.ACCIAIO, 1, 6, 14, 10)


## Gli scenari non sono tutti la stessa cosa, e un elenco piatto lo nascondeva:
## un solitario, una Operazione a due giocatori e un mini-scenario si giocano in
## modi diversi e durano tempi diversi. Qui sono in quattro gruppi, con
## un'intestazione non selezionabile davanti a ciascuno.
##
## `_ids` resta allineato all'elenco: le righe di intestazione hanno "" al loro
## posto, cosi' l'indice della lista e quello dello scenario non divergono - il
## difetto piu' facile da introdurre qui.
func _populate() -> void:
	var all := Scenario.list_ids()
	var solo: Array[String] = []
	var operations: Array[String] = []
	var battles: Array[String] = []
	var other: Array[String] = []
	for id in all:
		if id.begins_with("MS"):
			battles.append(id)
		elif id.begins_with("Op"):
			operations.append(id)
		elif SoloOpponent.load_for(id) != null:
			solo.append(id)
		else:
			other.append(id)

	_ids = [] as Array[String]
	var default_index := 0
	for group_v: Variant in [
		["SOLITARIO  (15)", solo],
		["DUE GIOCATORI - Operazioni  (9)", operations],
		["DUE GIOCATORI - Battaglie  (12)", battles],
		["ALTRO", other],
	]:
		var group: Array = group_v
		var ids: Array[String] = group[1]
		if ids.is_empty():
			continue
		_list.add_item(String(group[0]))
		var header := _list.item_count - 1
		_list.set_item_selectable(header, false)
		_list.set_item_custom_fg_color(header, UiTheme.OTTONE)
		_list.set_item_custom_bg_color(header, UiTheme.SCAFO_ALTO)
		_ids.append("")
		for id in ids:
			var sc := Scenario.load_by_id(id)
			_list.add_item("  %s" % (sc.title if sc.title != "" else id))
			_ids.append(id)
			# Si parte dal primo solitario: e' cio' che si puo' giocare subito,
			# da soli, senza dover sapere che cosa sia "Op5". Se si torna qui
			# da una partita, resta selezionato lo scenario appena lasciato.
			if id == Session.scenario_id or (default_index == 0
					and Session.scenario_id == "" and ids == solo):
				default_index = _ids.size() - 1
	if default_index > 0:
		_list.select(default_index)
		_on_selected(default_index)


func _on_selected(index: int) -> void:
	if index < 0 or index >= _ids.size() or _ids[index] == "":
		return
	var sc := Scenario.load_by_id(_ids[index])
	_show_art(_ids[index])
	var txt := sc.briefing_text()
	txt += "\n\n[b]SCHIERAMENTO[/b]\n%d Task Force, %d navi" % [
		sc.task_forces.size(), sc.ship_count()]
	if sc.reinforcement_count() > 0:
		txt += ", %d navi di rinforzo" % sc.reinforcement_count()
	for n_v: Variant in sc.raw_setup_notes():
		txt += "\n- " + String(n_v)
	if sc.has_import_warnings():
		txt += "\n\n[color=#ff9a3c][b]Avvisi di import[/b][/color]"
		for w_v: Variant in sc.import_warnings:
			txt += "\n  " + String(w_v)
	_brief.text = txt


const ART_DIR := "res://assets/art/scenarios/"


func _show_art(scenario_id: String) -> void:
	if _art == null:
		return
	var path := ART_DIR + scenario_id.replace(" ", "_") + ".png"
	if not ResourceLoader.exists(path):
		_art.visible = false
		return
	_art.texture = load(path)
	_art.visible = true


func _start() -> void:
	var i := _list.get_selected_items()
	if i.is_empty() or _ids.is_empty():
		return
	# Le intestazioni di gruppo non sono selezionabili, ma un doppio clic o
	# INVIO potrebbero comunque arrivare qui: senza questo controllo si
	# avvierebbe uno scenario con id vuoto.
	if _ids[i[0]] == "":
		return
	_store_rules()
	Session.resume_path = ""
	Session.start(_ids[i[0]])
	get_tree().change_scene_to_file(GAME_SCENE)


func _store_rules() -> void:
	Session.advanced_battle = _adv.button_pressed
	Session.optional_rules = {}
	for key_v: Variant in _optional.keys():
		Session.optional_rules[key_v] = (_optional[key_v] as CheckBox).button_pressed


## Riprende un salvataggio. Le regole con cui era stato giocato stanno nel
## salvataggio stesso, non nelle caselle di questa schermata.
func _resume() -> void:
	var saves := SaveGame.list_saves()
	if saves.is_empty():
		return
	var opts: Array = []
	for sv in saves.slice(0, 8):
		opts.append({"label": String(sv["name"]),
			"detail": "%s - round %d - salvata il %s" % [String(sv["scenario"]),
				int(sv["round"]), String(sv["saved_at"]).replace("T", " alle ")]})
	_dialog_open = true
	var i: int = await Choice.ask(self, "Riprendi una partita",
		"Il salvataggio contiene anche lo stato dei dadi: si riprende la "
		+ "stessa partita, non una simile.", opts)
	_dialog_open = false
	if i < 0 or i >= saves.size():
		return
	Session.resume_path = String(saves[i]["path"])
	Session.start(Session.scenario_id)
	get_tree().change_scene_to_file(GAME_SCENE)


var _dialog_open := false


func _unhandled_input(event: InputEvent) -> void:
	if _dialog_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			_start()
		elif k.keycode == KEY_ESCAPE and not OS.has_feature("web"):
			get_tree().quit()
