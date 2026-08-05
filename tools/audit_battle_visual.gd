extends SceneTree

## Audit VISIVO della Battaglia avanzata: percorre una Battaglia intera e
## fotografa ogni fase di ogni Round.
##
##     godot --path . --script res://tools/audit_battle_visual.gd -- <cartella> [scen:<id>]
##
## E' l'unica voce del capitolo Battaglia avanzata che non si chiude scrivendo
## codice: attitudini, rotazione delle pedine, Acquiring, Closing, Fumo,
## Confusione, siluri, Inseguimento e Disingaggio vanno GUARDATI. I test del
## motore dicono che i numeri sono giusti; non dicono se quello che si vede
## sullo schermo e' quello che il fascicolo descrive.
##
## Questo strumento non giudica: raccoglie. Salva un PNG per fase con un nome
## che dice Round e fase, e stampa accanto a ogni scatto lo stato che il motore
## aveva in quel momento - attitudini, zone, effetti, segnalini - cosi' chi
## guarda l'immagine puo' confrontarla con quello che il motore credeva.
##
## Le due cose insieme sono l'audit: se divergono, si vede subito quale delle
## due sbaglia.

var _n := 0
var _root: Node = null
var _dir := "reports/battaglia"
var _shots := 0
var _seen: Array[String] = []
var _idle := 0
## Lo scatto va preso DOPO che la vista ha ridisegnato: fotografare nello
## stesso fotogramma in cui si nota la fase nuova da' l'immagine di quella
## PRECEDENTE, ed e' il primo difetto che questo strumento ha avuto.
var _pending := ""
var _settle := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("scen:"):
		_dir = args[0]
	Session.advanced_battle = true
	Session.scenario_id = "MS9 Sink the Bismarck"
	for a in args:
		if a.begins_with("scen:"):
			Session.scenario_id = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_dir)
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _key(code: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	Input.parse_input_event(down)


## Lo stato che il motore ha ADESSO, in una riga per nave. E' il termine di
## paragone dello scatto: se la pedina sullo schermo dice un'altra cosa, la
## divergenza si vede mettendo le due accanto.
func _describe(bs: BattleState) -> String:
	var lines: Array[String] = []
	lines.append("  Round %d di %d, fase %s, meteo %s" % [bs.round_number,
		bs.last_round, BattleState.PHASE_LABELS[bs.phase],
		"cattivo" if bs.weather == TimeLapse.Weather.BAD else "buono"])
	if bs.confusion_side >= 0:
		lines.append("  Confusione: %s%s" % [
			Initiative.side_name(bs.confusion_side),
			" (gia' usata)" if bs.confusion_used else ""])
	for sh in bs.all_ships():
		var bits: Array[String] = []
		bits.append(BattleState.ZONE_LABELS[sh.battle_zone])
		bits.append(Attitude.label(sh.attitude))
		bits.append("vel. %s" % TimeLapse.speed_label(sh.current_speed()))
		if sh.damaged:
			bits.append("DANNEGGIATA")
		if sh.sunk:
			bits.append("AFFONDATA")
		if sh.smoke:
			bits.append("FUMO")
		if sh.hits > 0:
			bits.append("%d Colpi" % sh.hits)
		if not sh.special_effects.is_empty():
			bits.append("effetti: %s" % ", ".join(sh.special_effects))
		if bs.rudder_control.has(sh):
			bits.append("Timone: comanda %s" % Initiative.side_name(
				TaskForce.Side.ROYAL_NAVY if bool(bs.rudder_control[sh])
				else TaskForce.Side.KRIEGSMARINE))
		lines.append("    %-16s %s" % [sh.name, " | ".join(bits)])
	return "\n".join(lines)


func _shoot(tag: String, bs: BattleState) -> void:
	var img := get_root().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [_dir, _shots, tag]
	img.save_png(path)
	print("\n[%02d] %s  ->  %s" % [_shots, tag, path])
	print(_describe(bs))
	_shots += 1


func _process(_d: float) -> bool:
	_n += 1
	if _n < 24:
		return false
	if _root._status_choice_active:
		_root._complete_status_choice(0)
		return false
	var view: Node = _root._battle_view
	if view == null:
		_idle += 1
		if _shots > 0 and _idle > 60:
			print("\nAUDIT VISIVO: %d scatti in %s" % [_shots, _dir])
			print("Guardare le immagini una per una e confrontarle con lo stato "
				+ "stampato qui sopra.")
			quit(0)
			return true
		if _idle > 900:
			print("AUDIT VISIVO: nessuna Battaglia aperta.")
			quit(1)
			return true
		return false
	_idle = 0
	var bs: BattleState = view.state
	var tag := "r%d_%s" % [bs.round_number,
		BattleState.PHASE_LABELS[bs.phase].replace(" ", "_").to_lower()]
	if _pending != "":
		_settle += 1
		if _settle >= 3:
			_shoot(_pending, bs)
			_pending = ""
		return false
	if not _seen.has(tag):
		_seen.append(tag)
		_pending = tag
		_settle = 0
		return false
	_key(KEY_SPACE)
	if _n > 4000:
		print("AUDIT VISIVO: la Battaglia non si e' conclusa.")
		quit(1)
		return true
	return false
