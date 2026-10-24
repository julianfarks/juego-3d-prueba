class_name NullAdProvider
extends AdProvider
## Proveedor por defecto en producción mientras NO haya un SDK conectado: nunca hay anuncios ni recompensas.

func _init() -> void:
	provider_name = "sin proveedor de anuncios"
	is_real = false


func is_ready() -> bool:
	return false


func show_ad(_placement: String, _host: Node) -> void:
	finished.emit(Result.UNAVAILABLE)
