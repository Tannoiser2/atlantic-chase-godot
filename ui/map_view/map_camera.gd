class_name MapCamera
extends Camera2D

## Camera della mappa principale: trascinamento, zoom verso il cursore, limiti.
##
## La mappa e' 4203x2763, quindi il vincolo ai bordi conta: senza di esso e'
## facilissimo perdersi nel vuoto nero e non ritrovare l'Atlantico.

@export var min_zoom := 0.12
@export var max_zoom := 2.5
@export var zoom_step := 1.12
@export var keyboard_pan_speed := 900.0

var map_size := Vector2(4203, 2763)

var _dragging := false
var _drag_anchor := Vector2.ZERO
var _target_zoom := 1.0

## Touch: due dita spostano la mappa, e allontanandole o avvicinandole si
## zooma. Con un dito solo il gesto resta al gioco (selezione e disegno della
## Traiettoria), altrimenti si trascinerebbe la mappa invece di tracciare.
var _touches: Dictionary = {}          ## indice dito -> posizione
var _pinch_distance: float = 0.0
var _pinch_mid_prev: Vector2 = Vector2.ZERO


func _ready() -> void:
	_target_zoom = zoom.x
	set_process(true)


func setup(p_map_size: Vector2) -> void:
	map_size = p_map_size
	# parte inquadrando tutta la mappa
	var vp := get_viewport_rect().size
	var fit: float = minf(vp.x / map_size.x, vp.y / map_size.y)
	min_zoom = minf(min_zoom, fit * 0.9)
	_target_zoom = fit
	zoom = Vector2(fit, fit)
	position = map_size * 0.5
	_clamp_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch_distance = 0.0
		_pinch_mid_prev = Vector2.ZERO
		if _touches.size() >= 2:
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			_handle_pinch(sd)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_drag_anchor = mb.position
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, zoom_step)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / zoom_step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		position -= mm.relative / zoom.x
		_clamp_position()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var dir := Vector2(
		Input.get_action_strength("pan_right") - Input.get_action_strength("pan_left"),
		Input.get_action_strength("pan_down") - Input.get_action_strength("pan_up"))
	if dir != Vector2.ZERO:
		position += dir.normalized() * keyboard_pan_speed * delta / zoom.x
		_clamp_position()
	# zoom morbido
	var z: float = lerpf(zoom.x, _target_zoom, clampf(delta * 14.0, 0.0, 1.0))
	if absf(z - zoom.x) > 0.0001:
		zoom = Vector2(z, z)
		_clamp_position()


## Due dita: la distanza fra loro comanda lo zoom, il loro punto medio comanda
## lo spostamento. Sono i due gesti che ci si aspetta su uno schermo tattile.
func _handle_pinch(_last: InputEventScreenDrag) -> void:
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var dist := a.distance_to(b)
	var mid := (a + b) * 0.5
	if _pinch_distance > 0.0 and dist > 1.0:
		var factor := dist / _pinch_distance
		if absf(factor - 1.0) > 0.005:
			_zoom_at(mid, factor)
	_pinch_distance = dist
	# lo spostamento del punto medio muove la mappa
	if _pinch_mid_prev != Vector2.ZERO:
		position -= (mid - _pinch_mid_prev) / zoom.x
		_clamp_position()
	_pinch_mid_prev = mid


## Zoom mantenendo fermo il punto sotto il cursore: senza questo, zoomare su un
## dettaglio richiede di ricentrare a mano ogni volta.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := get_canvas_transform().affine_inverse() * screen_pos
	_target_zoom = clampf(_target_zoom * factor, min_zoom, max_zoom)
	zoom = Vector2(_target_zoom, _target_zoom)
	var after := get_canvas_transform().affine_inverse() * screen_pos
	position += before - after
	_clamp_position()


func _clamp_position() -> void:
	var half := get_viewport_rect().size * 0.5 / zoom.x
	var min_x: float = minf(half.x, map_size.x * 0.5)
	var max_x: float = maxf(map_size.x - half.x, map_size.x * 0.5)
	var min_y: float = minf(half.y, map_size.y * 0.5)
	var max_y: float = maxf(map_size.y - half.y, map_size.y * 0.5)
	position.x = clampf(position.x, min_x, max_x)
	position.y = clampf(position.y, min_y, max_y)


func world_from_screen(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


func focus_on(world_pos: Vector2) -> void:
	position = world_pos
	_clamp_position()
