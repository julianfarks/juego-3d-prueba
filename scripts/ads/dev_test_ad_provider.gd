class_name DevTestAdProvider
extends AdProvider
## PROVEEDOR DE PRUEBA — SOLO MODO DESARROLLO. NO muestra ni reproduce ningún anuncio, NO hay temporizador de 30 s y
## NO es una recompensa real: sirve únicamente para comprobar la interfaz y el flujo de reanimación.
## Muestra un diálogo claramente rotulado con botones para simular cada resultado.
## Solo se activa en compilaciones de depuración o con el menú DESARROLLADOR desbloqueado (ver RewardedAdService).

## Disponibilidad simulada (las pruebas automáticas y el diálogo la pueden cambiar).
var available := true
## Si es >= 0, show_ad() responde con ese Result sin abrir el diálogo (pruebas automáticas).
var scripted_result := -1
var shown := 0


func _init() -> void:
	provider_name = "PROVEEDOR DE PRUEBA (modo desarrollo)"
	is_real = false


func is_ready() -> bool:
	return available


func show_ad(_placement: String, host: Node) -> void:
	shown += 1
	if scripted_result >= 0:
		var r := scripted_result
		await host.get_tree().process_frame
		finished.emit(r)
		return
	if not available:
		finished.emit(Result.UNAVAILABLE)
		return
	var dlg := Control.new()
	dlg.name = "DevTestAdDialog"
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	dlg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(UIKit.dim_background(0.88))
	var vs := host.get_viewport().get_visible_rect().size
	var v := UIKit.center_box(dlg, Vector2(minf(720.0, vs.x - 40.0), 0))
	v.add_theme_constant_override("separation", 12)
	v.add_child(UIKit.label("MODO DESARROLLO", 40, UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER))
	var l := UIKit.label("PROVEEDOR DE PRUEBA: esto NO es un anuncio. No se ha mostrado ningún anuncio ni existe temporizador de 30 s. Elige qué resultado simular.", 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	v.add_child(l)
	var done := false
	var finish := func(res: int):
		if done:
			return
		done = true
		dlg.queue_free()
		finished.emit(res)
	var defs := [["Simular: recompensa CONCEDIDA", Result.COMPLETED, "DevAd_completed"], ["Simular: cancelado", Result.CANCELLED, "DevAd_cancel"],
		["Simular: error", Result.ERROR, "DevAd_error"], ["Simular: no disponible", Result.UNAVAILABLE, "DevAd_unavailable"]]
	for d in defs:
		var b: Button = UIKit.accent_button(String(d[0]), Vector2(300, 60), 22) if int(d[1]) == Result.COMPLETED else UIKit.button(String(d[0]), Vector2(300, 60), 22)
		b.name = String(d[2])
		var res: int = d[1]
		b.pressed.connect(func(): finish.call(res))
		v.add_child(b)
	host.add_child(dlg)
