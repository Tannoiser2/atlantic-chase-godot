class_name MapInputProxy
extends Node

## Il mondo della mappa vive in un SubViewport separato dall'HUD. Questo nodo
## inoltra al controller principale soltanto gli eventi puntatore ricevuti da
## quel viewport; le coordinate sono gia' locali alla superficie della mappa.

var receiver: Node = null


func _unhandled_input(event: InputEvent) -> void:
	if receiver == null:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		receiver.call("_handle_map_input", event)
