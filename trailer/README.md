# Tráiler de LAWYER MAYHEM 3D

Tráiler promocional generado **con el propio juego**: el motor (Godot 4.3) renderiza escenas reales (modelos, enemigos,
habilidades, biomas, cofres, cartas de mejora, jefes) dirigidas por un script, y `ffmpeg` monta imagen + sonido
con la canción original del juego.

## Vídeos (`trailer/video/`)

| Archivo | Formato |
|---|---|
| `LawyerMayhem3D_trailer_16x9_1080p.mp4` | 16:9, 1920×1080, 30 fps |
| `LawyerMayhem3D_trailer_9x16_1080x1920.mp4` | 9:16 (Shorts/Reels/TikTok), 1080×1920, 30 fps |

## Estructura del montaje

1. **Historia (0–15,5 s)**: despacho → juicio absurdo (coartada, «¡NO CULPABLES!») → ladrones celebran → pausa →
   el abogado abre el maletín, martillo del juez, cambia la expresión → lanza el maletín a cámara (flash).
2. **Acción (15,5–45,5 s)**: boomerang, ladrones golpeados que vuelven a recibir el golpe, lluvia de documentos,
   explosiones, cofres, selección de cartas, esquivas, persecuciones, cambio de biomas, jefe, build avanzada.
   Textos: «UN CASO PERDIDO.», «UNA JUSTICIA MUY PERSONAL.», «CONSTRUYE UNA BUILD IMPARABLE.», «NINGÚN LADRÓN ESTÁ A SALVO.»
3. **Final**: lanzamiento del maletín hacia cámara, corte al impacto, martillazo, logo y lema
   «OBJECIÓN… ¡Y A REPARTIR SENTENCIAS!».

## Música y sonido

- Música: la **canción original del juego** (`assets/audio/music_main.mp3`), empezando en el segundo 90,65 para que
  el «drop» (106,15 s) coincida con el paso de la historia a la acción. Con fundidos y compresión sidechain para no tapar los efectos.
- Efectos: los del propio juego (lanzamientos, impactos, recompensas…) grabados del motor + efectos de oficina/juicio
  (grapadora, martillo, boom, whoosh) **sintetizados con numpy** (`tools/make_sfx.py`, sin muestras externas).
- Fuentes: Inter / Inter Display (licencia OFL, `fonts/OFL.txt`).

## Cómo regenerarlo

Requisitos: Godot 4.3, `xvfb-run`, `ffmpeg`, Python 3.

```bash
trailer/tools/render.sh horizontal      # 1080p 16:9
trailer/tools/render.sh vertical        # 1080x1920 9:16
trailer/tools/render.sh preview         # 640x360 rápido
# opcional: --only=story,action,logo
```

`render.sh` ejecuta `godot --write-movie … -- --trailer` (modo Movie Maker a 30 fps fijos, determinista).
`trailer_director.gd` imprime qué fotogramas se conservan de cada plano (las preparaciones se descartan) y
`tools/assemble.py` los corta, concatena y mezcla con la música.

## Limitaciones

- Renderizado por software (Mesa llvmpipe, sin GPU), calidad gráfica del juego en preset alto; no se probó en un dispositivo Android.
- El logo es el icono oficial del proyecto más el título tipográfico en Inter; no hay arte de logo separado en el repositorio.
- La carpeta `trailer/` está excluida de la exportación del APK.
