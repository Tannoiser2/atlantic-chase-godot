class_name UiTheme
extends RefCounted

## Il tema dell'interfaccia: colori, caratteri e forme, in un posto solo.
##
## Prima ogni pannello si costruiva il suo `StyleBoxFlat` con i suoi colori, e
## il carattere era quello di riserva del motore. Il risultato era una
## interfaccia fatta di pezzi che non si somigliavano. Qui c'e' una tavolozza
## sola - blu notte, acciaio, ottone - e tre caratteri:
##
## - Barlow per il testo: nitido anche piccolo, con tutte le accentate;
## - Barlow Condensed per pulsanti e intestazioni: stretto, entra nei pulsanti;
## - Stardos Stencil per i titoli: lo stampino delle casse militari.
##
## Tutti e tre con licenza SIL Open Font (i testi sono in `assets/fonts/`).
##
## SOLO caratteri che questi font contengono davvero: niente frecce, niente
## emoji, niente simboli. `tools/controlla_glifi.py` lo verifica su tutte le
## stringhe del progetto - un glifo assente esce come un quadratino, e si vede
## solo guardando lo schermo.

const FONT_DIR := "res://assets/fonts/"

# --- tavolozza ---------------------------------------------------------------
const NOTTE := Color("0b141d")        ## sfondo dietro a tutto
const SCAFO := Color("111c28")        ## pannelli
const SCAFO_ALTO := Color("182736")   ## pannelli in rilievo, righe alterne
const ACCIAIO := Color("3d566b")      ## bordi
const ACCIAIO_CHIARO := Color("7fa3bd")
const CARTA := Color("e8eef3")        ## testo
const CARTA_SPENTA := Color("9db0bf") ## testo secondario
const SPENTO := Color("5c6b77")       ## disabilitato
const OTTONE := Color("e0aa4a")       ## accento: cio' che si puo' fare adesso
const OTTONE_SCURO := Color("5a431a")
const VERDE := Color("5fd6a4")        ## disponibile / legale
const VERDE_SCURO := Color("123a33")
const ROSSO := Color("e5694f")        ## pericolo, conferme distruttive
const ROSSO_SCURO := Color("4a211b")
const AZZURRO := Color("7ecdf5")      ## informazione

# --- misure ------------------------------------------------------------------
const TESTO := 17
const TESTO_PICCOLO := 15
const PULSANTE := 18
const TITOLO := 22

static var _theme: Theme = null
static var _fonts: Dictionary = {}
static var _installed := false


## Un carattere per nome di file. Usa la risorsa importata quando c'e' (e'
## quella che finisce nell'export) e altrimenti legge il TTF direttamente, che
## e' cio' che succede in una copia appena clonata, mai aperta dall'editor.
static func font(file: String) -> Font:
	if _fonts.has(file):
		return _fonts[file]
	var path := FONT_DIR + file
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null and FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) == OK:
			f = ff
	if f == null:
		f = ThemeDB.fallback_font
	_fonts[file] = f
	return f


static func testo() -> Font:
	return font("Barlow-Medium.ttf")


static func grassetto() -> Font:
	return font("Barlow-Bold.ttf")


static func corsivo() -> Font:
	return font("Barlow-Italic.ttf")


static func grassetto_corsivo() -> Font:
	return font("Barlow-SemiBoldItalic.ttf")


static func stretto() -> Font:
	return font("BarlowCondensed-SemiBold.ttf")


static func stretto_leggero() -> Font:
	return font("BarlowCondensed-Medium.ttf")


static func stampino() -> Font:
	return font("StardosStencil-Bold.ttf")


## Riquadro piatto con bordo. E' l'unico mattone: pannelli e pulsanti sono
## tutti questo, con colori diversi.
static func box(bg: Color, border: Color, border_w: int = 1, radius: int = 6,
		pad_h: int = 12, pad_v: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = true
	return sb


static func panel(alpha: float = 0.96) -> StyleBoxFlat:
	return box(Color(SCAFO, alpha), ACCIAIO)


## Pannello che chiede attenzione: bordo d'ottone.
static func panel_accent() -> StyleBoxFlat:
	return box(Color(SCAFO_ALTO, 0.98), OTTONE, 2)


## Applica a un pulsante uno dei quattro ruoli:
## "normale", "primario" (ottone: l'azione consigliata), "azione" (verde:
## un'azione di gioco dichiarabile), "pericolo" (rosso).
static func style_button(b: Button, role: String = "normale",
		font_size: int = PULSANTE) -> void:
	var bg := SCAFO_ALTO
	var hover := Color("223649")
	var border := ACCIAIO
	var fg := CARTA
	match role:
		"primario":
			bg = OTTONE_SCURO
			hover = Color("73561f")
			border = OTTONE
			fg = Color("fff1cf")
		"azione":
			bg = VERDE_SCURO
			hover = Color("17524a")
			border = VERDE
			fg = Color("e6fff3")
		"pericolo":
			bg = ROSSO_SCURO
			hover = Color("652b22")
			border = ROSSO
			fg = Color("ffe1da")
	var bw := 1 if role == "normale" else 2
	b.add_theme_stylebox_override("normal", box(bg, border, bw, 6, 14, 7))
	b.add_theme_stylebox_override("hover", box(hover, border.lightened(0.2), bw, 6, 14, 7))
	b.add_theme_stylebox_override("pressed", box(hover.darkened(0.25), border, bw, 6, 14, 7))
	b.add_theme_stylebox_override("disabled",
		box(Color("0f1820"), Color("27333d"), 1, 6, 14, 7))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", SPENTO)
	b.add_theme_font_override("font", stretto())
	b.add_theme_font_size_override("font_size", font_size)


## Pulsante gia' pronto. `min_h` 44: e' la misura minima che un dito centra
## senza guardare, e su un iPad la finestra e' scalata a circa due terzi.
static func button(text: String, role: String = "normale", min_h: float = 44.0,
		font_size: int = PULSANTE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = min_h
	b.focus_mode = Control.FOCUS_NONE
	style_button(b, role, font_size)
	return b


## Intestazione in stretto maiuscolo, per i titoli dei pannelli.
static func heading(text: String, size: int = TITOLO, color: Color = OTTONE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", stretto())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Testo ricco con i quattro tagli di Barlow gia' assegnati.
static func style_rich(r: RichTextLabel, size: int = TESTO) -> void:
	r.add_theme_font_override("normal_font", testo())
	r.add_theme_font_override("bold_font", grassetto())
	r.add_theme_font_override("italics_font", corsivo())
	r.add_theme_font_override("bold_italics_font", grassetto_corsivo())
	for k in ["normal_font_size", "bold_font_size", "italics_font_size",
			"bold_italics_font_size"]:
		r.add_theme_font_size_override(k, size)
	r.add_theme_color_override("default_color", CARTA)


## La casella di spunta, disegnata pixel per pixel: un quadrato col bordo, e
## dentro un quadrato d'ottone quando e' attiva. Disegnata e non presa da un
## carattere, perche' un segno di spunta che il font non ha diventa un
## quadratino vuoto - cioe' una casella che sembra sempre spenta.
static func _check_icon(on: bool) -> ImageTexture:
	var n := 24
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			if edge:
				img.set_pixel(x, y, OTTONE if on else ACCIAIO_CHIARO)
			elif on and x >= 6 and y >= 6 and x < n - 6 and y < n - 6:
				img.set_pixel(x, y, OTTONE)
			else:
				img.set_pixel(x, y, Color("0d1721"))
	return ImageTexture.create_from_image(img)


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = testo()
	t.default_font_size = TESTO

	t.set_color("font_color", "Label", CARTA)
	t.set_color("default_color", "RichTextLabel", CARTA)
	t.set_font("normal_font", "RichTextLabel", testo())
	t.set_font("bold_font", "RichTextLabel", grassetto())
	t.set_font("italics_font", "RichTextLabel", corsivo())
	t.set_font("bold_italics_font", "RichTextLabel", grassetto_corsivo())
	for k in ["normal_font_size", "bold_font_size", "italics_font_size",
			"bold_italics_font_size"]:
		t.set_font_size(k, "RichTextLabel", TESTO)

	# pulsanti
	t.set_stylebox("normal", "Button", box(SCAFO_ALTO, ACCIAIO, 1, 6, 14, 7))
	t.set_stylebox("hover", "Button", box(Color("223649"), ACCIAIO_CHIARO, 1, 6, 14, 7))
	t.set_stylebox("pressed", "Button", box(Color("0e1a25"), ACCIAIO_CHIARO, 1, 6, 14, 7))
	t.set_stylebox("disabled", "Button", box(Color("0f1820"), Color("27333d"), 1, 6, 14, 7))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CARTA)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", SPENTO)
	t.set_font("font", "Button", stretto())
	t.set_font_size("font_size", "Button", PULSANTE)

	# caselle di spunta: stesso testo dei pulsanti, senza riquadro
	t.set_font("font", "CheckBox", testo())
	t.set_font_size("font_size", "CheckBox", TESTO)
	t.set_color("font_color", "CheckBox", CARTA)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", OTTONE)
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true))
	t.set_constant("h_separation", "CheckBox", 8)

	# pannelli
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	t.set_stylebox("panel", "PopupPanel", panel_accent())
	t.set_stylebox("panel", "TooltipPanel",
		box(Color("05090d"), OTTONE, 1, 5, 10, 6))
	t.set_color("font_color", "TooltipLabel", CARTA)
	t.set_font_size("font_size", "TooltipLabel", TESTO_PICCOLO)

	# elenchi
	t.set_stylebox("panel", "ItemList", box(Color("0d1721"), ACCIAIO, 1, 6, 6, 6))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", box(OTTONE_SCURO, OTTONE, 1, 4, 6, 2))
	t.set_stylebox("selected_focus", "ItemList", box(OTTONE_SCURO, OTTONE, 1, 4, 6, 2))
	t.set_stylebox("hovered", "ItemList", box(Color("1b2c3c"), Color("1b2c3c"), 0, 4, 6, 2))
	t.set_color("font_color", "ItemList", CARTA)
	t.set_color("font_selected_color", "ItemList", Color("fff1cf"))
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_constant("v_separation", "ItemList", 8)
	t.set_font_size("font_size", "ItemList", TESTO)

	# campi di testo
	t.set_stylebox("normal", "LineEdit", box(Color("0d1721"), ACCIAIO, 1, 5, 10, 6))
	t.set_stylebox("focus", "LineEdit", box(Color("0d1721"), OTTONE, 2, 5, 10, 6))

	# separatori sottili
	var sep := StyleBoxLine.new()
	sep.color = Color(ACCIAIO, 0.7)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(ACCIAIO, 0.7)
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	# barre di scorrimento larghe abbastanza per un dito
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, box(Color("0d1721"), Color("0d1721"), 0, 5, 5, 5))
		t.set_stylebox("grabber", cls, box(ACCIAIO, ACCIAIO, 0, 5, 5, 5))
		t.set_stylebox("grabber_highlight", cls,
			box(ACCIAIO_CHIARO, ACCIAIO_CHIARO, 0, 5, 5, 5))
		t.set_stylebox("grabber_pressed", cls, box(OTTONE, OTTONE, 0, 5, 5, 5))
	_theme = t
	return t


## Rende il tema quello di tutta l'applicazione.
##
## Lo fonde nel tema predefinito del motore invece di assegnarlo a un nodo: un
## tema assegnato a un `Control` non attraversa i `CanvasLayer`, e qui
## l'interfaccia, la Battaglia e le finestre di scelta vivono ognuna nel suo.
## Cosi' vale ovunque, compresi suggerimenti e finestre a comparsa.
static func install() -> void:
	if _installed:
		return
	_installed = true
	var base := ThemeDB.get_default_theme()
	if base != null:
		base.merge_with(theme())
		base.default_font = testo()
		base.default_font_size = TESTO
