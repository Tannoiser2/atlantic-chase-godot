class_name Choice
extends RefCounted

## Apre un ChoiceDialog modale e attende la risposta.
##
##     var i := await Choice.ask(self, "titolo", "spiegazione", opzioni)
##     if i < 0: ...   # annullato
##
## Sta qui e non dentro ChoiceDialog perche' in GDScript un metodo statico che
## nomina la propria classe non compila, e l'errore e' silenzioso: il runner
## dei test si ferma senza stampare nulla.

const DIALOG := preload("res://ui/hud/choice_dialog.gd")


static func ask(parent: Node, title: String, description: String,
		options: Array, allow_cancel: bool = true) -> int:
	if options.is_empty():
		return -1
	var layer := CanvasLayer.new()
	layer.layer = 40
	parent.add_child(layer)

	# Un Control figlio di un CanvasLayer non eredita il rettangolo del
	# viewport: gli ancoraggi dei figli si calcolerebbero su una dimensione
	# nulla e il pannello finirebbe nell'angolo. Serve una radice dimensionata
	# a mano; da li' in poi gli ancoraggi funzionano.
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.position = Vector2.ZERO
	root.size = parent.get_viewport().get_visible_rect().size
	layer.add_child(root)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)

	var d: ChoiceDialog = DIALOG.new()
	root.add_child(d)
	d.build(title, description, options, allow_cancel)
	var idx: int = await d.chosen
	layer.queue_free()
	return idx
