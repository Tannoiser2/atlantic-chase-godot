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
	t.add_theme_font_size_override("font_size", 22)
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

	for i in options.size():
		var o: Dictionary = options[i]
		var b := Button.new()
		b.text = "  %s  " % String(o.get("label", "opzione %d" % (i + 1)))
		b.tooltip_text = String(o.get("detail", ""))
		b.custom_minimum_size = Vector2(0, 38)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i
		b.pressed.connect(func() -> void: _pick(idx))
		_list.add_child(b)
		var det := String(o.get("detail", ""))
		if det != "":
			var l := Label.new()
			l.text = "      " + det
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
			_list.add_child(l)

	if allow_cancel:
		var c := Button.new()
		c.text = "  Annulla  "
		c.custom_minimum_size = Vector2(0, 34)
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
			if i < _list.get_child_count():
				_pick(i)
				get_viewport().set_input_as_handled()


static func _style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.14, 0.98)
	sb.border_color = Color(0.55, 0.70, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb
