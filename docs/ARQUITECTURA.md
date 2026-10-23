# Arquitectura

- `scripts/autoload/` — `SaveSystem` (JSON), `Config` (constantes/calidad), `AudioManager` (buses, SFX, música dinámica), `GameState` (estado de partida, señales).
- `scripts/core/` — `UpgradeDB` (52 mejoras, 12 categorías, 4 rarezas, 10 sinergias), `Build` (estadísticas calculadas), `Scaling` (dificultad centralizada).
- `scripts/gen/` — arte procedural: `MeshBuilder`, `Mats` (shader toon), `Rig` (esqueleto + animación por código), `ModelFactory` (abogado y enemigos), `PropsFactory` (obstáculos, plataformas, cofre, portal, tienda), `FX` (pool de efectos).
- `scripts/combat/` — `Combat` (daño, críticos, procs, explosiones, cadenas), `Projectiles` (pool, sin físicas), `Feedback` (único punto de número flotante + sonido por impacto real: formato, estilos, prioridades, combos).
- `scripts/player/` — `Player`, `Skills`, `CameraRig` (órbita, colisión de cámara sin tirones).
- `scripts/enemy/` — `EnemyDefs` (datos), `Enemy` (máquina de estados, ataques telegrafiados, jefe por fases, estados alterados).
- `scripts/arena/` — `ArenaBuilder`, `WaveDirector`, `Arena` (objetivos, oleadas, monedas, cofre/portal/tienda), `Interactable`.
- `scripts/ui/` — HUD, controles táctiles editables, cartas, tienda, menús, ajustes, pantalla final, herramientas de desarrollo.
- `scripts/main.gd` — orquestador del flujo. `tests/selftest.gd` — autojuego.

Decisiones: sin assets externos; un `ShaderMaterial` por personaje; pooling de enemigos/FX/proyectiles; límites de enemigos por calidad.
Limitación: una partida en curso no se guarda (solo ajustes, mejoras permanentes, récords y estadísticas).

## Retroalimentación de daño (v0.5.0)
Flujo de un impacto: `Combat.player_hit/explode/chain_lightning` → `Combat.calc` (daño final) → `Enemy.take_damage` (resistencia de élite, vida) → `Feedback.on_damage(enemy, dmg, info, hp_before, max_hp, killed)` →
`Fx.spawn_number` (pool de `Label3D`, prioridad, agrupación, separación) y `AudioManager.combat_sfx` (bus `Combat` con limitador, presupuesto por ventana, prioridades, antirrepetición).
`info` admite `silent` (sin número ni sonido: empuje, muerte por jefe), `aoe`/`area` (estilo de área) y `src` (periódico: `burn`, `zone`; combo: `chain`, `nova`, `crit_explosion`, `echo`).
Ganchos de prueba: `Feedback.record/event_log`, `AudioManager.record_combat/combat_log`, `Fx.num_stats`.
