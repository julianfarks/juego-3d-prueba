class_name PadNav
extends Node
## Navegación de menús con mando (y teclado): con el modo mando activo, los botones, deslizadores y cartas pasan a ser
## enfocables, el foco se mantiene siempre dentro del panel más reciente (el "modal" que está encima) y B/círculo
## (ui_cancel) pulsa su botón de cerrar/volver. Con controles táctiles nada de esto cambia (los botones no toman foco).

var main: Node
var _flagged: Array = []        # nodos a los que se les puso FOCUS_ALL (para revertir al volver a táctil)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	if PadInput.inst != null:
		PadInput.inst.mode_changed.connect(_on_mode)


func _excluded(n: Node) -> bool:
	if n.has_meta("no_pad_focus"):
		return true
	if main != null:
		if main.hud != null and main.hud.is_ancestor_of(n):
			return true
		if main.touch != null and main.touch.is_ancestor_of(n):
			return true
	return false


func _prep(n: Node) -> void:
	if n is ScrollContainer:
		(n as ScrollContainer).follow_focus = true
	if (n is BaseButton or n is Slider or n.has_meta("pad_card")) and not _excluded(n):
		var c := n as Control
		if c.focus_mode == Control.FOCUS_NONE:
			c.focus_mode = Control.FOCUS_ALL
			_flagged.append(c)


func _on_node_added(n: Node) -> void:
	if PadInput.pad_mode:
		_prep(n)


func _on_mode(on: bool) -> void:
	if on:
		_walk(get_tree().root)
	else:
		_walk_off(get_tree().root)
		_flagged.clear()
		var fo := get_viewport().gui_get_focus_owner()
		if fo != null:
			fo.release_focus()


func _walk_off(n: Node) -> void:
	if n is BaseButton or n is Slider or n.has_meta("pad_card"):
		(n as Control).focus_mode = Control.FOCUS_NONE
	for ch in n.get_children():
		_walk_off(ch)


func _walk(n: Node) -> void:
	_prep(n)
	for ch in n.get_children():
		_walk(ch)


## Panel modal más reciente (el último fondo atenuado visible) 
func top_scope() -> Control:
	var best: Node = null
	for d in get_tree().get_nodes_in_group("pad_dim"):
		if not (d as CanvasItem).is_visible_in_tree():
			continue
		if best == null or (d as Node).is_greater_than(best):
			best = d
	if best != null:
		return best.get_parent() as Control
	return null


static func _focusable(c: Control) -> bool:
	if c.focus_mode != Control.FOCUS_ALL or not c.is_visible_in_tree():
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	return true


func first_focusable(root: Node) -> Control:
	if root is Control and _focusable(root as Control) and not (root is ScrollContainer):
		return root as Control
	for ch in root.get_children():
		var f := first_focusable(ch)
		if f != null:
			return f
	return null


func _process(_delta: float) -> void:
	if not PadInput.pad_mode or (PadInput.inst != null and PadInput.inst.capturing):
		return
	var scope := top_scope()
	var fo := get_viewport().gui_get_focus_owner()
	if scope == null:
		if fo != null and fo.is_visible_in_tree() and not _excluded(fo) and not _in_any_modal(fo):
			fo.release_focus()
		return
	if fo == null or not scope.is_ancestor_of(fo) or not fo.is_visible_in_tree():
		var f := first_focusable(scope)
		if f != null:
			f.grab_focus()


func _in_any_modal(_c: Control) -> bool:
	return false


func _input(event: InputEvent) -> void:
	if not PadInput.pad_mode or PadInput.inst == null or PadInput.inst.capturing:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if press_cancel():
			get_viewport().set_input_as_handled()


## Pulsa el botón de cerrar/volver/cancelar del panel modal más reciente. Devuelve true si había alguno.
func press_cancel() -> bool:
	var scope := top_scope()
	if scope == null:
		return false
	var btn := _find_cancel(scope, ["cerrar", "volver", "cancelar", "listo", "salir de la tienda", "atrás"] + (["continuar", "reanudar"] if scope is PauseMenu else []))
	if btn == null:
		return false
	btn.pressed.emit()
	return true


## Último botón visible de cerrar/volver dentro del panel (el más interior si hay una confirmación encima).
func _find_cancel(root: Node, names: Array) -> BaseButton:
	var found: BaseButton = null
	for ch in root.get_children():
		var f := _find_cancel(ch, names)
		if f != null:
			found = f
	if root is BaseButton and (root as BaseButton).is_visible_in_tree() and not (root as BaseButton).disabled:
		var t := String((root as BaseButton).get("text")).strip_edges().to_lower()
		if t in names:
			found = root as BaseButton
	return found
