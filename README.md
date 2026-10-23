# LAWYER MAYHEM 3D

Roguelike 3D en tercera persona para Android (Godot 4.3 · GDScript). Eres un abogado de dibujos animados
que reparte "sentencias" con su maletín en arenas llenas de ladrones, élites y jefes. Inspirado en la estructura
de los roguelikes de arenas (cofres, cartas, builds), pero con contenido 100 % original y procedural
(modelos, animaciones, iconos, audio).

## Estado honesto
| Elemento | Estado |
|---|---|
| Proyecto Godot, 8 fases de código | Implementado |
| Probado en PC con renderizado por software (Xvfb + Mesa) mediante autojuego (`tests/selftest.gd`) | Sí (ver `docs/PRUEBAS.md`) |
| Rendimiento en móvil real (60 FPS) | **No medido** (no hay dispositivo; solo hay presets y pooling) |
| APK | Se compila en GitHub Actions (`.github/workflows/android.yml`). Compruébalo en la pestaña *Actions* / *Releases* |
| Prueba táctil en móvil real | **Pendiente** (los controles se probaron con eventos táctiles sintéticos) |

## Jugar
- Móvil: joystick izquierdo (flotante), arrastra a la derecha para la cámara, botones: atacar, saltar, esquivar,
  3 habilidades (Documentos, Sello, Objeción) y USAR (cofres, portales, tienda). Ajustes → *Editar controles*
  permite mover y cambiar el tamaño de cada botón.
- PC (pruebas): WASD, flechas = cámara, J/Ctrl atacar, Espacio saltar, Shift esquivar, Q/E/R habilidades, F usar, Esc pausa.

## Flujo
Arena de eliminación → supervivencia → desafío (minijefe) → élite → jefe de zona. Cada arena completada da un cofre
(cartas) y un portal; algunas tienen tienda. Tras el jefe empieza un ciclo claramente más difícil (escalado centralizado
en `scripts/core/scaling.gd`). Tras vencer 2 jefes aparece la pantalla de victoria (se puede continuar).

## Estructura
Ver `docs/ARQUITECTURA.md`. Regenerar audio: `python3 tools/gen_audio.py` (numpy).

## Compilar el APK
1. Subir a GitHub: el workflow descarga Godot 4.3 + plantillas, crea un keystore de depuración *en el runner*
   (nunca se guarda en el repo) y exporta `LawyerMayhem3D-debug.apk` (artefacto + Release de pre-lanzamiento).
2. Release firmado: crear un keystore propio, guardarlo como *secret* de GitHub y añadir pasos de firma. **No** subas claves al repo.

## Modo desarrollador
Oculto: Ajustes → tocar 7 veces la línea de versión → código. Permite modo Dios, saltar de arena, dar mejoras, depuración.

## Novedades 0.4.0 — 244 mejoras, inventario de 30 tipos y venta
- **244 mejoras funcionales** en una base de datos central (`UpgradeDB` + `UpgradeCatalog`), en 17 categorías. 241 son acumulables; Daño de Maletín llega a nivel 50 y 16 mejoras admiten 20 o más niveles. Cada mejora tiene id estable, nombre, descripción, icono, rareza, etiquetas, requisitos de aparición (arena, mejoras previas, equipamiento) y efecto real.
- **Motor modular (`Perks`)**: en vez de 200 sistemas, las mejoras combinan disparadores (al golpear, crítico, baja, golpe de maletín, habilidad, esquiva, daño recibido, escudo roto, nivel, inicio/fin de arena, cada 3/5/8/12 s), condiciones (contra quemados, a distancia, con poca vida…), fuentes (maletín, documentos, ecos, bumerán…) y efectos (curar, escudo, explosión, rayo, aturdir, monedas, misil…). Nada se recalcula por fotograma: `Build` precalcula las listas al cambiar.
- **Inventario táctil** (botón «MEJ n/30» en la HUD): cuadrícula de 30 espacios, filtros por categoría, rareza y nombre, detalle con efecto acumulado, pestaña de sinergias (activas y por completar).
- **Límite de 30 tipos** (los niveles no ocupan espacio). Con 30/30 el cofre solo ofrece mejoras que ya tienes y lo explica; el botón INVENTARIO abre la gestión encima del cofre sin perderlo y, al liberar un espacio, se relanza gratis una vez.
- **Vender / desechar** con confirmación (aviso en niveles altos y si se pierde una sinergia). Vender paga el valor mostrado, elimina todos los niveles y recalcula todo desde cero.
- 11 sinergias nuevas por etiqueta y 14 mejoras «Catalizador» que amplifican las etiquetas que ya tienes.
- Pruebas: `tests/progression_test.tscn` (numérica), `tests/inventory_test.tscn` (catálogo, límite, venta, cofres, guardado) y `--invtest` (renderizado con toques y comportamiento real en combate).

## Novedades 0.3.0 — builds acumulables y dificultad continua
- **Mejoras con nivel (hasta 50).** Cada mejora muestra "NIVEL n → n+1" y su máximo propio (de 2 a 50). Daño de Maletín, Velocidad de ataque, Ojo de Perito, Salud, Barrido (radio), Armadura… suben de verdad en cada nivel. Una mejora al nivel máximo, o cuya estadística ya tocó su límite duro, **no vuelve a salir** en cofres ni tiendas.
- **Hitos cada 10 niveles** (p. ej. Maletín: ×1.10 de daño total en 10, 20, 30, 40 y 50) y **7 sinergias por nivel** nuevas (Maestro del Maletín, Artillería Total, Aplastamiento Crítico…). Se calculan siempre desde cero, así que nada se aplica dos veces.
- **Cofres:** la 2.ª carta sale de las mejoras que ya llevas (para poder profundizar una build), y el equipamiento de la Sala Central hace salir más las mejoras afines. La carta muestra el cambio real ("Daño 256% → 272%") y los hitos próximos.
- **Dificultad continua:** vida, daño, cantidad, velocidad, afijos, resistencia y ritmo de ataque de élites/jefes dependen solo del número de arena (sin escalones cada 5 arenas, sin efecto de tiendas ni mejoras). Peor salto entre rondas: vida +12%, daño +7%.
- Pruebas numéricas: `godot --headless res://tests/progression_test.tscn` (77 comprobaciones + tablas de progresión).
- Una sola release en GitHub ("ultima-version") que se sobrescribe con el APK nuevo.

## Novedades 0.2.0
- **Guardar y continuar partida**: guardado atómico con copia de seguridad y validación; autoguardado al empezar
  cada arena, al completarla y al recoger la recompensa; CONTINUAR / NUEVA PARTIDA (con aviso antes de
  sobrescribir); "Guardar y salir" en la pausa. Perder o abandonar una partida elimina el guardado.
- **Cofre**: cartel flotante ABRIR con icono de mano, botón táctil por cercanía, el portal indica que primero
  hay que abrir el cofre. Cada cofre da su recompensa una sola vez.
- **Sala Central** (menú → Sala Central): portales NUEVA / CONTINUAR PARTIDA, Armería (herramienta, habilidad,
  estilo, equipo — afectan al combate de verdad), Mesa del Juez (4 dificultades), Despacho (mejoras permanentes),
  Archivo de Casos (estadísticas) y zona de práctica con muñecos.
- Pruebas: `tests/system_test.tscn` (sin render, 2 procesos), `--flowtest` y `--lobbytest` (con render).
