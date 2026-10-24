#!/usr/bin/env python3
"""Montaje del tráiler a partir de la grabación de Godot (Movie Maker).

El director (trailer_director.gd) imprime una línea por plano conservado:
    KEEP <primer_fotograma> <fotograma_final_exclusivo> <G_inicio> <nombre>
Este script recorta esos tramos del AVI (imagen + sonido del juego), los concatena y mezcla la canción original
del juego (assets/audio/music_main.mp3) empezando en MUSIC_START, para que G=0 coincida con el segundo 90.65.

Uso:
  assemble.py LOG AVI SALIDA.mp4 [--music RUTA] [--stills DIR t1,t2,...] [--preview]
"""
import re, subprocess, sys, os, argparse

FPS = 30
MUSIC_START = 90.65      # G = 0 en la canción (tramo que sube hasta el «drop» en G = 15.5 ↔ 106.15 s)


def keeps(log):
    out = []
    for line in open(log, errors="ignore"):
        m = re.match(r"KEEP (\d+) (\d+) ([\d.]+) (\S+)", line.strip())
        if m:
            out.append((int(m.group(1)), int(m.group(2)), float(m.group(3)), m.group(4)))
    return out


def run(cmd):
    print(" ".join(cmd[:6]), "…")
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("avi")
    ap.add_argument("out")
    ap.add_argument("--music", default="")
    ap.add_argument("--stills", nargs=2, metavar=("DIR", "TIMES"))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--fade-out", type=float, default=1.2)
    a = ap.parse_args()
    ks = keeps(a.log)
    if not ks:
        sys.exit("no hay líneas KEEP en el registro")
    total = sum(b - s for s, b, _, _ in ks) / FPS
    print(f"{len(ks)} planos, {total:.2f} s")
    work = os.path.splitext(a.out)[0] + "_work"
    os.makedirs(work, exist_ok=True)
    # 1) cortar cada plano exacto por fotogramas (imagen) y su sonido, a archivos intermedios sin pérdidas
    parts = []
    for i, (s, e, g, name) in enumerate(ks):
        p = os.path.join(work, f"p{i:02d}.mkv")
        vf = f"select='between(n\\,{s}\\,{e - 1})',setpts=N/{FPS}/TB"
        af = f"atrim=start={s / FPS:.6f}:end={e / FPS:.6f},asetpts=PTS-STARTPTS"
        run(["ffmpeg", "-v", "error", "-y", "-i", a.avi, "-vf", vf, "-af", af,
             "-c:v", "libx264", "-preset", "veryfast" if a.preview else "slow", "-crf", "28" if a.preview else "12",
             "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", p])
        parts.append(p)
    lst = os.path.join(work, "list.txt")
    with open(lst, "w") as f:
        for p in parts:
            f.write(f"file '{os.path.abspath(p)}'\n")
    joined = os.path.join(work, "joined.mkv")
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", joined])
    if a.stills:
        d, times = a.stills
        os.makedirs(d, exist_ok=True)
        for t in times.split(","):
            run(["ffmpeg", "-v", "error", "-y", "-ss", t, "-i", joined, "-frames:v", "1", os.path.join(d, f"G{float(t):05.2f}.png")])
    # 2) mezcla: canción original (con fundidos) + sonido del juego/efectos por encima
    if a.music:
        fo = a.fade_out
        filt = (f"[1:a]atrim=start={MUSIC_START}:duration={total:.3f},asetpts=PTS-STARTPTS,"
                f"afade=t=in:st=0:d=0.6,afade=t=out:st={total - fo:.3f}:d={fo},volume=0.82[m];"
                f"[0:a]volume=1.35,asplit=2[s1][s2];"
                f"[m][s1]sidechaincompress=threshold=0.08:ratio=3:attack=5:release=180[md];"
                f"[md][s2]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]")
        run(["ffmpeg", "-v", "error", "-y", "-i", joined, "-i", a.music, "-filter_complex", filt,
             "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-preset", "veryfast" if a.preview else "slow",
             "-crf", "26" if a.preview else "19", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
             "-c:a", "aac", "-b:a", "192k", a.out])
    else:
        run(["ffmpeg", "-v", "error", "-y", "-i", joined, "-c:v", "libx264", "-preset", "veryfast", "-crf", "26",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", a.out])
    print("OK", a.out)


if __name__ == "__main__":
    main()
