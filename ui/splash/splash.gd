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
var _start_btn: Button
var _ids: Array[String] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_populate()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.08, 0.12)
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 28
	row.offset_top = 24
	row.offset_right = -28
	row.offset_bottom = -24
	row.add_theme_constant_override("separation", 28)
	add_child(row)

	# --- copertina ---
	var cover := TextureRect.new()
	var tex: Texture2D = load(SPLASH)
	if tex != null:
		cover.texture = tex
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.custom_minimum_size = Vector2(420, 0)
	cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(cover)

	# --- colonna destra ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)

	var title := Label.new()
	title.text = "Scegli lo scenario"
	title.add_theme_font_size_override("font_size", 30)
	right.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	right.add_child(body)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(330, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i: int) -> void: _start())
	body.add_child(_list)

	var briefpanel := PanelContainer.new()
	briefpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefpanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	briefpanel.add_theme_stylebox_override("panel", _panel_style())
	body.add_child(briefpanel)
	_brief = RichTextLabel.new()
	_brief.bbcode_enabled = true
	briefpanel.add_child(_brief)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	right.add_child(buttons)

	_start_btn = Button.new()
	_start_btn.text = "  Inizia la partita  "
	_start_btn.custom_minimum_size = Vector2(0, 44)
	_start_btn.pressed.connect(_start)
	buttons.add_child(_start_btn)

	var quit_btn := Button.new()
	quit_btn.text = "  Esci  "
	quit_btn.custom_minimum_size = Vector2(0, 44)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit_btn)

	var credit := RichTextLabel.new()
	credit.bbcode_enabled = true
	credit.fit_content = true
	credit.custom_minimum_size = Vector2(0, 62)
	credit.text = ("[i]Atlantic Chase[/i] e' un gioco di [b]GMT Games[/b], "
		+ "design di Jeremy White, © 2020 GMT Games LLC.\n"
		+ "Questa e' una implementazione amatoriale non affiliata a GMT, "
		+ "per uso personale. Regole tradotte da G. Sorio.")
	right.add_child(credit)


static func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.15, 0.95)
	sb.border_color = Color(0.35, 0.48, 0.60)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _populate() -> void:
	_ids = Scenario.list_ids()
	var default_index := 0
	for i in _ids.size():
		var sc := Scenario.load_by_id(_ids[i])
		var label := sc.title if sc.title != "" else _ids[i]
		# i mini-scenari si giocano tutti sulla Mappa di Battaglia
		var tag := "  [mini]" if _ids[i].begins_with("MS") else ""
		_list.add_item("%s%s" % [label, tag])
		if _ids[i].begins_with("Op5"):
			default_index = i
	if not _ids.is_empty():
		_list.select(default_index)
		_on_selected(default_index)


func _on_selected(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	var sc := Scenario.load_by_id(_ids[index])
	var txt := sc.briefing_text()
	txt += "\n\n[b]SCHIERAMENTO[/b]\n%d Task Force, %d navi" % [
		sc.task_forces.size(), sc.ship_count()]
	if sc.reinforcement_count() > 0:
		txt += ", %d navi di rinforzo" % sc.reinforcement_count()
	if sc.has_import_warnings():
		txt += "\n\n[color=#ff9a3c][b]Avvisi di import[/b][/color]"
		for w_v: Variant in sc.import_warnings:
			txt += "\n  " + String(w_v)
	_brief.text = txt


func _start() -> void:
	var i := _list.get_selected_items()
	if i.is_empty() or _ids.is_empty():
		return
	Session.start(_ids[i[0]])
	get_tree().change_scene_to_file(GAME_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			_start()
		elif k.keycode == KEY_ESCAPE:
			get_tree().quit()
