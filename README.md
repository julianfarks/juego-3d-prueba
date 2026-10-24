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
- Móvil: joystick izquierdo (flotante), arrastra a la derecha para la cámara, botones: **ATACAR** (lanza el maletín bumerán),
  **DOCS**, **ESQUIVAR**, **SALTAR** y USAR (cofres, portales, tienda). SELLO y OBJECIÓN ya no son botones (ver 0.6.0).
  Ajustes → *Editar controles* permite mover y cambiar el tamaño de cada botón.
- PC (pruebas): WASD, flechas = cámara, J/Ctrl atacar, Espacio saltar, Shift esquivar, Q documentos, F usar, Esc pausa.

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

## Novedades 0.10.0 — cámara ajustable y navegación fiable de los enemigos
- **Cámara más lejos por defecto** (9,6 m, altura 1,7 m, inclinación 25°): se ve el terreno por delante y el abogado sigue siendo reconocible. La colisión de la cámara usa un barrido de esfera contra el mundo (capa `L_CAMERA`): nunca atraviesa muros ni sólidos, se acerca al instante si algo se interpone, recupera la distancia despacio y dentro de la arena se recorta al recinto (sin saltos al girar junto al borde).
- **Ajustes → CÁMARA** (también desde la pausa): Distancia (5–16 m), Altura (1–3,2 m), Inclinación (15–55°), Sensibilidad horizontal y vertical, invertir eje vertical y Restablecer. Botones −/+ y deslizador (táctil y mando); efecto inmediato y se guarda (`cam_dist`, `cam_height`, `cam_pitch`, `cam_sens_x/y`, `cam_invert_y`).
- **Navegación de enemigos** (`scripts/enemy/nav_grid.gd`): rejilla de 1 m por arena (suelo, pendiente, hueco libre para dos tamaños de enemigo, escalones físicos), campo de flujo desde el jugador repartido en ticks y punto de paso suavizado. Los ladrones rodean muros, cajas y plataformas (rampas incluidas), los de distancia buscan una posición con línea de tiro, los cuerpo a cuerpo se reparten alrededor del jugador y se mantienen las diferencias por tipo (corredor rápido, tanque lento).
- **Anti-atasco** escalonado: sin avance real (medido contra lo que *quiere* avanzar, no tras deslizarse) → 0,5 s recalcula la ruta y reanaliza el entorno · 1 s punto alternativo · 2 s celda libre más cercana y otro hueco · 4 s pequeño desplazamiento comprobado con `test_move` (nunca atraviesa geometría).
- Pruebas: `--cameratest --stage=1|2` y `--navtest [--only=map,wall,u,zig,group,ranged,stuck,platform,biomes,perf]`.

## Novedades 0.9.0 — el juego abre directamente en el Vestíbulo del Bufete
- **Arranque**: `scenes/main.tscn` → `main.gd` construye el mundo y llama a `_enter_lobby(true)`: la primera pantalla jugable es la escena 3D real del vestíbulo (aparición en `Lobby.spawn_position()`, cámara detrás del personaje). Se eliminó el menú inicial (`MainMenu`, el escenario del personaje sobre la plataforma y el estado `MENU`).
- **Dónde está ahora cada función del antiguo menú**: NUEVA PARTIDA y CONTINUAR PARTIDA → portales del vestíbulo (y «CONTINUAR PARTIDA GUARDADA» en la pausa del vestíbulo; al abrir con un guardado el vestíbulo lo avisa); El Despacho y Récords → estaciones del vestíbulo y botones de la pausa; Ajustes → pausa; Salir (solo PC) → pausa del vestíbulo.
- **Pausa completa** (`pause_menu.gd`, botón «II» o Start/Atrás): en el vestíbulo = CONTINUAR, CONTINUAR PARTIDA GUARDADA, RÉCORDS, EL DESPACHO, AJUSTES, VÍDEO Y GRÁFICOS, AUDIO, CONTROLES; en una run = CONTINUAR, INVENTARIO, MI BUILD, GUARDAR PARTIDA, AJUSTES, VÍDEO Y GRÁFICOS, AUDIO, CONTROLES, VOLVER AL VESTÍBULO (confirmación: guardar y volver / abandonar run / cancelar). La pantalla de fin ofrece VOLVER AL VESTÍBULO y AJUSTES.
- **Vídeo y gráficos reales** (`Config.apply_graphics`): calidad (preset), sombras (apagadas/bajas/altas: sol, atlas y alcance), distancia de dibujado (plano lejano de la cámara 90/140/220), efectos (24/48/80 simultáneos y densidad de partículas), escala de renderizado (50–100 %, `Viewport.scaling_3d_scale`) y límite de FPS (30/60; 90/120 solo si la pantalla lo permite). Se aplican al instante, persisten y se pueden restaurar. Un guardado anterior parte del preset que tenía elegido.
- Pruebas: `--starttest` (3 etapas: arranque en frío + pausa + vídeo/audio/controles con toques y mando reales; reinicio de la app; guardado antiguo).

## Novedades 0.8.0 — mandos Xbox/PlayStation, ajustes CONTROLES y joystick táctil corregido
- **Joystick táctil con zona limitada** (`touch_controls.gd`): solo nace al tocar el cuadrante inferior izquierdo (≤34 % del ancho, ≥45 % de la altura; configurable 0.6–1.4×). Antes cualquier toque en el 46 % izquierdo de la pantalla lo activaba. Aparece bajo el pulgar (con la base siempre dentro de la pantalla), no se activa al tocar botones, inventario o pausa, un segundo dedo no lo roba, y se suelta al pausar/abrir menús. Magnitud ≤ 1 en todas las direcciones (la diagonal no es más rápida), curva suave con zona muerta, sensibilidad ajustable.
- **Mandos** (`scripts/core/pad_input.gd`, `scripts/ui/pad_nav.gd`): detección por `joy_connection_changed`, dispositivo activo = el último usado, modo automático (al conectar se ocultan los controles táctiles; al desconectar reaparecen) o forzado desde ajustes. Seguro contra «mandos fantasma»: con el mando inactivo 8 s, un toque en pantalla devuelve los controles táctiles. Nombres de botones según Xbox (A/B/X/Y, LB/RB, LT/RT) o PlayStation (Cruz/Círculo/Cuadrado/Triángulo, L1/R1, L2/R2); en Godot los códigos internos son los mismos (posicionales, vía SDL) y solo cambia lo que se muestra.
- **Distribución por defecto**: stick izq. mover, stick der. cámara, RT/R2 lanzar el maletín, LT/L2 DOCS, A/Cruz saltar, B/Círculo esquivar, X/Cuadrado interactuar, Y/Triángulo inventario, Start/Options pausa, LB/RB (L1/R1) anterior/siguiente en menús y cartas, A confirmar, B cancelar, cruceta/stick izq. navegar.
- **Ajustes → CONTROLES** (`controls_menu.gd`): pestañas TÁCTIL (zona y sensibilidad del joystick, editar botones), MANDO (modo, sticks intercambiables, sensibilidad y zonas muertas, reasignar cada acción pulsando el botón nuevo, aviso de conflicto con INTERCAMBIAR / REEMPLAZAR / CANCELAR, restaurar) y TECLADO. Todo se guarda y no se restablece al empezar una run.
- **Menús con mando**: los botones, deslizadores y cartas pasan a ser enfocables solo en modo mando; el foco se limita al panel más reciente; B cierra/vuelve (pausa, inventario, tienda, ajustes, confirmaciones…). Avisos de interacción y barra de ayuda con los nombres del mando conectado.
- **Pruebas**: `tests/padtest.gd` (`--padtest --stage=1|2`, eventos de toque y de mando reales, 2 procesos para la persistencia). **No hay un mando ni un Android reales en el entorno de pruebas**: solo se verifican la lógica de detección, los nombres reportados por Xbox/PlayStation y el mapeo.

## Novedades 0.7.1 — inventario visible y ataque 100% manual
- **Botón INVENTARIO** (HUD, junto a pausa): icono de maletín + texto «INVENTARIO» + contador de tipos distintos «n/30», 190×72 px con 17 px de separación respecto a pausa. Abre/cierra el inventario (mejoras, niveles, sinergias) sin perder la partida.
- **Sin ataque automático**: `player.gd` ya no lanza el maletín al haber enemigos cerca ni repite mientras se mantiene pulsado; una pulsación (`attack` *just pressed*) = un lanzamiento, y solo si el maletín está listo. Eliminados el ajuste «Ataque automático» y su valor guardado (los guardados antiguos lo ignoran). Los efectos de mejoras (explosiones, cohetes, fragmentos…) siguen saliendo de los impactos, sin iniciar lanzamientos principales.
- **Mando**: ATACAR = X, SALTAR = A, ESQUIVAR = B, DOCS = Y, USAR = RB, pausa = Start, stick izquierdo = mover (antes no había mapeo de mando).
- **Pruebas**: `tests/controltest.gd` (`--controltest`, 44 comprobaciones con toques y botones de mando reales).

## Novedades 0.7.0 — 6 biomas con terreno real, fondo en capas y transición de región
- **6 biomas** (`scripts/arena/biome_db.gd`, datos puros): Ruinas urbanas, Bosque judicial encantado, Complejo industrial, Desierto de expedientes, Ciudadela flotante y Tribunal final. Cada uno define materiales de suelo, tipo de relieve, arquitectura, paleta, luz/niebla, props, tienda/cofre/portal temáticos y elementos de fondo. El bioma cambia **solo tras cada jefe principal** (5 arenas por región; `Scaling.cycle_of(i) % 6`).
- **Terreno con relieve y colisión** (`terrain.gd`): altura procedural (`Terrain.height`), malla de 1 m con color por vértice, `HeightMapShape3D`; zonas reservadas (obstáculos, plataformas, recompensas) se aplanan. Jugador, enemigos, monedas, recompensas, maletín y proyectiles siguen el relieve.
- **Escenario** (`biome_scenery.gd`, `biome_props.gd`): fachadas con ventanas/balcones/ruinas, cielo procedural, niebla y sol por bioma, fondo en 3 capas fusionadas (cercana/media/lejana) sin sombras, partículas ambientales y haces de luz.
- **Transición de región** (`main.gd`): al cruzar el portal tras un jefe, efecto distinto por bioma (fundido/destello/barras/polvo/iris) y cartel con el nombre de la región; la partida (mejoras, monedas, vida, estadísticas) no se toca.
- **Pruebas**: `tests/biometest.gd` (`--biometest`; datos, estructura, rutas transitables con física real, enemigos atascados, maletín, recompensas, distinción visual, rendimiento, flujo del portal) y `tests/terrain_probe.gd`.
- **Pendiente / sin probar**: rendimiento en un móvil Android real (solo se midió con render por software); los enemigos aún no cambian por bioma; el jefe es el mismo en todos; con la victoria a los 2 jefes los biomas 3–6 solo aparecen al continuar la partida.

## Novedades 0.6.0 — maletín bumerán, controles simplificados y builds de proyectiles
- **ATACAR lanza el maletín** (`scripts/combat/case_throw.gd`, nodo `CaseThrow`): objeto 3D visible durante todo el recorrido, trayectoria **curva** de ida, giro rápido, estela, regreso curvo hacia la mano y recuperación (el maletín de la mano se oculta mientras vuela y reaparece al atraparlo). Hasta que vuelve **no se puede lanzar otro** (sin lanzamientos infinitos ni maletines duplicados). El golpe cuerpo a cuerpo (`_slam_hit`) fue eliminado.
- **Botones**: se quitan SELLO y OBJECIÓN (ni botón, ni zona táctil, ni acción de teclado). Quedan ATACAR, DOCS, ESQUIVAR, SALTAR (+ USAR contextual), redistribuidos sin solapes; los guardados antiguos se migran a la nueva disposición. Las mecánicas se conservan: el **Sello Mágico** se deposita solo en el punto más lejano de la ida del maletín (con su enfriamiento y mejoras) y la **Objeción** salta sola con la vida por debajo del 45 % y enemigos cerca.
- **24 mejoras nuevas del maletín** (`scripts/core/case_catalog.gd`; datos `bc_*` que lee `CaseThrow.make_profile()`): Maletín Pirotécnico, Rastro de Fuego, Explosión Legal, Documentos Explosivos, Multilanzamiento, Fragmentación, Cadena de Impactos, Maletín Eléctrico, Maletín Corrosivo, Retorno Explosivo, Rebote Judicial, Perforación Documental, Crítico Contractual, Lluvia de Documentos, Doble Maletín, Rebotes de Maletín (≈3 s por el entorno), Multi Maletín (+1 maletín por nivel) y mejoras base (daño, alcance, tamaño, velocidad, teledirección, golpe en el regreso, prisa al atrapar). Se suben de nivel al repetirse en cofres (máximo propio de cada una) y entran en el inventario de 30 tipos con descripción y efecto acumulado. 6 sinergias nuevas (Fiesta Pirotécnica, Pararrayos Judicial, Gran Final, Estela Infernal, Pinball Legal, Arsenal Aéreo).
- **Todo se combina en la misma tirada** (`CaseThrow._impact`): daño normal/crítico → explosión → fuegos artificiales → fragmentos → documentos → lluvia → rayo → corrosión/propagación de estados → onda residual → el maletín perfora/rebota/vuelve → efectos de retorno (una sola vez por lanzamiento, aunque haya varios maletines).
- **Daño y feedback**: cada impacto, explosión, fragmento, cohete, rayo, minimaletín o brasa llama a `Combat.player_hit/explode`, así que usa los números y sonidos de 0.5.0. Orígenes nuevos: `case`, `case_boom`, `firework`, `frag`, `mini`, `rain`, `fire_trail`, `return_blast`, `docs_boom`. Las mejoras `s:slam`/`s:boomerang` también potencian el maletín lanzado.
- **Rendimiento**: límites duros (7 maletines, 40 secundarios vivos, 24 brasas, 14 explosiones/s, 90 proyectiles), objetos reutilizados (pools), destellos tenues en cascadas para no tapar enemigos, y 7 sonidos nuevos propios (`throw`, `catch`, `bounce`, `shard`, `fw_launch`, `fw_pop`, `paper`) bajo el mismo presupuesto por ventana de 100 ms.
- Pruebas: `--casetest` (renderizado, 128 comprobaciones: lanzar/volver/relanzar, trayectoria curva, impactos correctos y sin duplicados, cada mejora, combinaciones en una tirada, secundarios con números y sonidos, DOCS/ESQUIVAR/SALTAR, botones, migración de guardado, niveles/sinergias/límite de 30, estrés y capturas).
- **Límites honestos**: el tacto y el rendimiento en un Android real **no están medidos** (solo CPU en PC con renderizado por software: ≈1 ms/fotograma de media en cascada extrema, ×3-5 estimado en móvil); el audio se verifica por flujo, no se ha escuchado; el equilibrio de daño de las mejoras es una primera pasada sin ajustar con partidas reales.

## Novedades 0.5.0 — números de daño flotantes y sonido de impacto
- **Un único punto de verdad** (`scripts/combat/feedback.gd`): todo daño a un enemigo llega a `Enemy.take_damage()`, que ya recibe el valor final (`Combat.calc` + resistencia de élite) y llama una sola vez a `Feedback.on_damage()`. Número y sonido salen de ese mismo evento y de ese mismo valor; el muñeco de práctica usa el mismo camino.
- **Números** con separador de miles («1.250», «2.750.000»; por encima de 10¹⁵ pasan a «1,23e18» sin desbordar). Muestran el **daño completo del impacto aunque supere la vida restante** (5.000 sobre 300 de vida → «5.000»; la vida queda en 0 y el exceso no pasa a otros enemigos).
- **Estilos**: normal (blanco), crítico (ámbar, mayor, «!», animación más fuerte), elemental (color del elemento), área/explosión (un número por enemigo afectado), cadena, ejecución, periódico (quemadura/zonas: más pequeño y de otro color) y **masivo** (≥ 10.000 o ≥ 35 % de la vida máxima: escala y duración extra, borde rojo). Tamaño siempre acotado (0,7–2,0 × ajuste de usuario, compensado por distancia).
- **Anti-saturación visual**: pool de `Label3D` reutilizados, tope de números vivos, **prioridad** (los críticos/masivos expulsan a los periódicos y normales), **agrupación por enemigo** (los ticks periódicos siempre; los golpes normales cuando hay presión; la suma mostrada = suma real), separación lateral/vertical entre impactos seguidos del mismo enemigo y modo «Reducir efectos con muchos impactos» (tope a la mitad, partículas al 50 %).
- **Sonido de combate** (`AudioManager.combat_sfx`): 5 golpes con variantes, 2 críticos, golpe pesado, golpe a jefe, golpes de fuego/hielo/rayo, tic de efecto periódico, muerte normal y de jefe, explosión (una por explosión, más grave cuanto mayor el radio) y «combo» ascendente cuando una sinergia encadena impactos. Cada reproducción varía tono (±7 %) y volumen (±1,5 dB), con **presupuesto por ventana de 100 ms**, prioridades (el sonido importante roba la voz de uno menor), antirrepetición, atenuación por densidad y un **limitador** en el bus `Combat`. Todo el audio es original y procedural (`tools/gen_audio.py`).
- Sin impacto no hay sonido de impacto: el empuje/aturdimiento sin daño y la muerte masiva al caer un jefe son silenciosos; golpear a un muerto no genera nada; el sonido duplicado del proyectil se eliminó.
- **Ajustes**: números de daño (sí/no), tamaño (60–160 %), reducir efectos con muchos impactos, y volúmenes **0–100 %** reales por bus (Música, Efectos de combate, Otros efectos, Ambiente).
- Pruebas: `--fbtest` (renderizado, 83 comprobaciones: tipos de ataque, críticos/sinergias/marca/élite, sobredaño, explosiones y cadenas, kills sin duplicados, saturación de sonido, 36 enemigos, rendimiento, ajustes, capturas).
- **Límites honestos**: el audio se verifica por flujo (qué suena, cuántas voces, tono/volumen, buses, limitador, propiedades de los WAV), no se ha «escuchado» en un móvil; el rendimiento se midió por CPU en PC (≈65 µs por impacto, ≈0,65 ms/fotograma a 360 impactos/s), no en un Android real.

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
- **Sala Central / Vestíbulo del Bufete** (desde 0.9.0 es la primera pantalla al abrir el juego): portales NUEVA / CONTINUAR PARTIDA, Armería (herramienta, habilidad,
  estilo, equipo — afectan al combate de verdad), Mesa del Juez (4 dificultades), Despacho (mejoras permanentes),
  Archivo de Casos (estadísticas) y zona de práctica con muñecos.
- Pruebas: `tests/system_test.tscn` (sin render, 2 procesos), `--flowtest` y `--lobbytest` (con render).
