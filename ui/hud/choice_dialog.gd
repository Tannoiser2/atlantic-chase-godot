class_name ChoiceDialog
extends PanelContainer

## Pannello modale di scelta.
##
## Serve ovunque le regole lascino decidere al giocatore e finora decideva il
## codice: quale opzione di Scorrere del Tempo usare, quale nave colpire, quale
## troncone di Traiettoria eliminare dopo un buco.
##
## Si costruisce tramite Choice.ask(), non direttamente:
##     var i := await Choice.ask(self, "titolo", "spiegazione", opzioni)
##     if i < 0: ...   # annullato
##
## La funzione sta in un helper separato perche' un metodo statico che nomina
## la propria classe non compila, e il fallimento e' silenzioso: il runner dei
## test si blocca senza stampare nulla.
##
## Ogni opzione e' un Dictionary { "label": String, "detail": String }.

signal chosen(index: int)

var _list: VBoxContainer
var _closed := false
var _option_count := 0


func build(title: String, description: String, options: Array,
		allow_cancel: bool) -> void:
	add_theme_stylebox_override("panel", _style())
	custom_minimum_size = Vector2(640, 0)
	# centrato nel genitore: si aspetta di stare dentro un Control gia'
	# dimensionato (vedi Choice.ask)
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UiTheme.stretto())
	t.add_theme_color_override("font_color", UiTheme.OTTONE)
	t.add_theme_font_size_override("font_size", 26)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 590
	v.add_child(t)

	if description != "":
		var d := RichTextLabel.new()
		d.bbcode_enabled = true
		d.fit_content = true
		d.custom_minimum_size = Vector2(590, 0)
		d.text = description
		v.add_child(d)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)

	_option_count = options.size()
	for i in options.size():
		var o: Dictionary = options[i]
		var b := UiTheme.button(String(o.get("label", "opzione %d" % (i + 1))),
			"primario", 46.0)
		if i < 9:
			b.text = "%d.  %s" % [i + 1, b.text]
		b.tooltip_text = String(o.get("detail", ""))
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i
		b.pressed.connect(func() -> void: _pick(idx))
		_list.add_child(b)
		var det := String(o.get("detail", ""))
		if det != "":
			var l := Label.new()
			l.text = det
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 590
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", UiTheme.CARTA_SPENTA)
			_list.add_child(l)

	if allow_cancel:
		var c := UiTheme.button("Annulla", "normale", 44.0)
		c.pressed.connect(func() -> void: _pick(-1))
		v.add_child(c)


func _pick(i: int) -> void:
	if _closed:
		return
	_closed = true
	chosen.emit(i)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			_pick(-1)
			get_viewport().set_input_as_handled()
		elif k >= KEY_1 and k <= KEY_9:
			var i: int = k - KEY_1
			if i < _option_count:
				_pick(i)
				get_viewport().set_input_as_handled()


static func _style() -> StyleBoxFlat:
	return UiTheme.box(UiTheme.SCAFO, UiTheme.OTTONE, 2, 8, 20, 16)
