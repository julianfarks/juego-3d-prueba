# Anuncios recompensados (reanimación) — estado y cómo conectar un SDK

**Estado actual: NO hay ningún SDK publicitario integrado ni anuncios reales.** Solo existe la arquitectura y un
*proveedor de prueba* (`DevTestAdProvider`) que **no muestra anuncios**: abre un diálogo «MODO DESARROLLO» para simular
el resultado. Solo se activa en compilaciones de depuración o con el menú DESARROLLADOR desbloqueado; en producción
sin SDK el botón de reanimar responde «Anuncio no disponible. Inténtalo más tarde» y nunca concede nada.

## Piezas
- `scripts/ads/ad_provider.gd` — contrato (`is_ready()`, `load_ad()`, `show_ad()`, señal `finished(result)`).
- `scripts/ads/rewarded_ad_service.gd` — servicio que usa el juego: `await RewardedAdService.show_rewarded("revive", nodo)`.
  Devuelve `COMPLETED`, `CANCELLED`, `UNAVAILABLE`, `ERROR` (o `BUSY` si ya hay una petición).
- `scripts/ads/dev_test_ad_provider.gd` — proveedor de prueba (identificado como tal, `is_real = false`).
- `scripts/ads/null_ad_provider.gd` — proveedor por defecto en producción sin SDK (nunca disponible).
- La lógica de reanimar (`main.gd`, `GameState.ad_revives_*`) no conoce a ningún proveedor.

## Conectar AdMob (u otro) más adelante
1. Añadir el plugin de Godot para Android del proveedor (p. ej. un plugin AdMob para Godot 4.3) y activarlo en el preset de exportación.
2. Configuración necesaria: *App ID* de AdMob en el manifiesto de Android y un *Ad Unit ID* de tipo «recompensado»
   (usar los IDs de prueba oficiales de Google durante el desarrollo; **no** se incluye ninguno en este repositorio), consentimiento de
   usuario (UMP/GDPR) y política de privacidad.
3. Crear `scripts/ads/admob_ad_provider.gd` con `class_name AdMobAdProvider extends AdProvider`:
   - `load_ad(placement)`: pedir al SDK cargar el anuncio recompensado; cuando el SDK avise de carga correcta, `is_ready()` devuelve true.
   - `show_ad(...)`: mostrar el anuncio. Conectar los callbacks del SDK:
     * recompensa obtenida (`onUserEarnedReward`) → recordar `earned = true`;
     * anuncio cerrado → emitir `finished(Result.COMPLETED)` si `earned`, si no `finished(Result.CANCELLED)`;
     * fallo de carga o de reproducción → `finished(Result.ERROR)`; sin anuncio → `finished(Result.UNAVAILABLE)`.
   - `is_real = true`, `provider_name = "AdMob"`.
4. Registrarlo al arrancar (p. ej. en `main.gd::_ready`): `RewardedAdService.set_provider(AdMobAdProvider.new())` y llamar a
   `RewardedAdService.preload_ad()` al empezar la partida y tras cada anuncio mostrado.
5. Probar con anuncios de prueba del proveedor en un dispositivo real antes de publicar. Hasta entonces nada de esto está probado.

## Reglas que ya cumple el juego
- La reanimación solo se concede si el servicio devuelve `COMPLETED`; cancelar, error o «no disponible» no consumen oportunidades.
- Máximo 2 reanimaciones por partida; el contador se guarda con la partida (`ad_revives` en el guardado) y se reinicia en una partida nueva.
- No existe cuenta atrás local ni reanimación automática por tiempo.
