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

## Maletín bumerán (v0.6.0)
`Skills._cast_slam` (slot 0, ATACAR) ya no golpea: reproduce la animación `throw` y, en su latigazo (0,4·dur), llama a `CaseThrow.throw_case(dir)`.
`CaseThrow` (nodo hijo de `World`, `GameState.case_throw`) es dueño de todo el ciclo: `make_profile()` congela las estadísticas `bc_*` + parámetros del arma al lanzar; `plan_cases()` decide cuántos maletines salen (Multi/Doble/Bumerán/Doble golpe) y sus ángulos; `_step_case()` mueve cada maletín (ida con giro constante + guiado, rebote por el entorno con `Config.L_WORLD`, regreso con giro creciente que atraviesa el mundo para garantizar la vuelta); `_impact()` aplica **todas** las mejoras en orden; `_catch()` devuelve el maletín a la mano y dispara los efectos de retorno (solo el principal).
Reglas: un enemigo solo recibe un impacto por fase (ida/regreso; en rebote, 0,45 s entre reimpactos); los proyectiles secundarios (`S`) usan pools por tipo; límites `MAX_CASES/MAX_SECONDARY/MAX_BLASTS_PER_SEC/MAX_EMBERS`; `clear_all()` se llama al empezar arena y en `ArenaManager.clear`.
Sello y Objeción: `Skills.auto_seal(pos)` (al final de la ida) y `_auto_barrier_check()` (vida < 45 %). `TouchControls.BUTTONS` solo tiene ataque/salto/esquiva/DOCS/USAR; `SaveSystem._sanitize_after_load` migra disposiciones antiguas (`settings.controls_v`).
Catálogo: `CaseCatalog.register()` (mejoras `case_*`, etiquetas `LABELS`, sinergias). Ganchos de prueba: `CaseThrow.record/impact_log/counts`.

## Retroalimentación de daño (v0.5.0)
Flujo de un impacto: `Combat.player_hit/explode/chain_lightning` → `Combat.calc` (daño final) → `Enemy.take_damage` (resistencia de élite, vida) → `Feedback.on_damage(enemy, dmg, info, hp_before, max_hp, killed)` →
`Fx.spawn_number` (pool de `Label3D`, prioridad, agrupación, separación) y `AudioManager.combat_sfx` (bus `Combat` con limitador, presupuesto por ventana, prioridades, antirrepetición).
`info` admite `silent` (sin número ni sonido: empuje, muerte por jefe), `aoe`/`area` (estilo de área) y `src` (periódico: `burn`, `zone`; combo: `chain`, `nova`, `crit_explosion`, `echo`).
Ganchos de prueba: `Feedback.record/event_log`, `AudioManager.record_combat/combat_log`, `Fx.num_stats`.
