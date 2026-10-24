class_name RewardedAdService
extends RefCounted
## Servicio ÚNICO de anuncios recompensados. El resto del juego (reanimación, etc.) solo usa esta clase:
##   var r: int = await RewardedAdService.show_rewarded("revive", host_node)
## y recibe uno de: COMPLETED (recompensa autorizada), CANCELLED, UNAVAILABLE, ERROR  (BUSY = ya hay una petición en curso).
## La recompensa SOLO se concede con COMPLETED, y COMPLETED solo lo emite el proveedor (un SDK real en producción).
## No hay temporizadores locales que concedan nada. Ver docs/ANUNCIOS.md para conectar un SDK real.

const Result := AdProvider.Result
const BUSY := 99
const PLACEMENT_REVIVE := "revive"
## Si el proveedor no responde nunca, la petición acaba en ERROR (jamás en COMPLETED) pasado este tiempo.
const TIMEOUT_MS := 180000

static var _provider: AdProvider = null
static var _busy := false


## Conecta un proveedor (SDK real o de pruebas). null = valor por defecto.
static func set_provider(p: AdProvider) -> void:
	_provider = p


static func provider() -> AdProvider:
	if _provider == null:
		# El proveedor de PRUEBA solo existe en compilaciones de depuración o con DESARROLLADOR desbloqueado.
		# En una compilación de producción sin SDK no hay anuncios: siempre «no disponible».
		if OS.is_debug_build() or Config.dev_mode:
			_provider = DevTestAdProvider.new()
		else:
			_provider = NullAdProvider.new()
	return _provider


static func is_busy() -> bool:
	return _busy


static func is_available(_placement := PLACEMENT_REVIVE) -> bool:
	return provider().is_ready()


## Pide al proveedor que precargue un anuncio (llamar con antelación, p. ej. al empezar la partida).
static func preload_ad(placement := PLACEMENT_REVIVE) -> void:
	provider().load_ad(placement)


static func show_rewarded(placement: String, host: Node) -> int:
	if _busy:
		return BUSY
	var p := provider()
	if not p.is_ready():
		p.load_ad(placement)
		if not p.is_ready():
			return Result.UNAVAILABLE
	_busy = true
	var st := {"done": false, "r": Result.ERROR}
	var on_done := func(r: int):
		if not st["done"]:
			st["done"] = true
			st["r"] = r
	p.finished.connect(on_done, CONNECT_ONE_SHOT)
	p.show_ad(placement, host)
	var t0 := Time.get_ticks_msec()
	while not st["done"] and Time.get_ticks_msec() - t0 < TIMEOUT_MS:
		await host.get_tree().process_frame
	if p.finished.is_connected(on_done):
		p.finished.disconnect(on_done)
	_busy = false
	var res: int = int(st["r"])
	if not st["done"] or res < Result.COMPLETED or res > Result.ERROR:
		return Result.ERROR
	return res
