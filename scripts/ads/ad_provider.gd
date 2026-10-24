class_name AdProvider
extends RefCounted
## Contrato que debe cumplir CUALQUIER proveedor de anuncios recompensados (AdMob, otro SDK, o el de pruebas).
## El juego NUNCA habla con un SDK concreto: solo con RewardedAdService, que usa un AdProvider.
##
## Para conectar un SDK real: crear una clase que extienda AdProvider (ver docs/ANUNCIOS.md), sobrescribir los
## 3 métodos y asignarla con RewardedAdService.set_provider(). Solo debe emitir Result.COMPLETED cuando el SDK
## confirme la recompensa (p. ej. onUserEarnedReward de AdMob); cualquier otro desenlace emite CANCELLED/UNAVAILABLE/ERROR.

enum Result { COMPLETED, CANCELLED, UNAVAILABLE, ERROR }

## Se emite UNA vez por cada show_ad(), con un valor de Result.
signal finished(result: int)

## Nombre legible (se muestra en la interfaz de desarrollo y en los registros).
var provider_name := "sin proveedor"
## true SOLO en un proveedor publicitario real. El proveedor de pruebas debe dejarlo en false.
var is_real := false


## ¿Hay un anuncio cargado y listo para mostrarse ahora?
func is_ready() -> bool:
	return false


## Pide al SDK que precargue un anuncio para 'placement' (puede ser asíncrono; is_ready() pasará a true).
func load_ad(_placement: String) -> void:
	pass


## Muestra el anuncio. 'host' es un nodo del árbol por si el proveedor necesita colgar una interfaz.
## Debe terminar emitiendo 'finished' exactamente una vez.
func show_ad(_placement: String, _host: Node) -> void:
	finished.emit(Result.UNAVAILABLE)
