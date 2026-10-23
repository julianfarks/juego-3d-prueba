#!/usr/bin/env python3
"""Generador procedural de audio para LAWYER MAYHEM 3D.

Sintetiza (sin muestras externas) música y efectos como WAV mono 16-bit @ 22050 Hz
dentro de assets/audio/. Todo el material es original.

Uso:  python3 tools/gen_audio.py
"""
import math
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
RNG = np.random.default_rng(7)


# ---------------------------------------------------------------------------
# Utilidades de síntesis
# ---------------------------------------------------------------------------
def ts(dur):
    return np.arange(int(SR * dur)) / SR


def hz(note):
    """MIDI -> Hz."""
    return 440.0 * 2 ** ((note - 69) / 12.0)


def sine(f, dur, phase=0.0):
    t = ts(dur)
    return np.sin(2 * np.pi * f * t + phase)


def saw(f, dur):
    t = ts(dur)
    return 2.0 * ((f * t) % 1.0) - 1.0


def square(f, dur, duty=0.5):
    t = ts(dur)
    return np.where(((f * t) % 1.0) < duty, 1.0, -1.0)


def tri(f, dur):
    t = ts(dur)
    return 2.0 * np.abs(2.0 * ((f * t) % 1.0) - 1.0) - 1.0


def noise(dur):
    return RNG.uniform(-1, 1, int(SR * dur))


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.1):
    a_n, d_n, r_n = int(SR * a), int(SR * d), int(SR * r)
    a_n = max(a_n, 1)
    s_n = max(n - a_n - d_n - r_n, 0)
    env = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False),
        np.linspace(1, s, d_n, endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, r_n),
    ])
    if len(env) < n:
        env = np.concatenate([env, np.zeros(n - len(env))])
    return env[:n]


def exp_env(n, decay):
    t = np.arange(n) / SR
    return np.exp(-t * decay)


def lowpass(x, cutoff):
    """Filtro paso bajo de un polo (vectorizado por bloques mediante recursión)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    out = np.zeros_like(x)
    y = 0.0
    a = 1.0 - np.exp(-2 * np.pi * cutoff / SR)
    for i in range(len(x)):
        y += a[i] * (x[i] - y)
        out[i] = y
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def sweep(f0, f1, dur, shape="exp"):
    t = ts(dur)
    if shape == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * (t / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase)


def pad_to(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix_into(buf, x, start, vol=1.0, wrap=True):
    """Suma x en buf desde 'start' (segundos); el desbordamiento envuelve al principio."""
    i0 = int(start * SR)
    n = len(x)
    end = i0 + n
    if end <= len(buf):
        buf[i0:end] += x * vol
    elif wrap:
        first = len(buf) - i0
        buf[i0:] += x[:first] * vol
        rest = n - first
        while rest > 0:
            chunk = min(rest, len(buf))
            buf[:chunk] += x[first:first + chunk] * vol
            first += chunk
            rest -= chunk
    else:
        buf[i0:] += x[: len(buf) - i0] * vol


def finish(x, peak=0.9, soft=True):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * 1.2 if soft else x / m * peak
    if soft:
        x = np.tanh(x) * (peak / math.tanh(1.2))
    return x


def write_wav(name, x):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    data = np.clip(x, -1.0, 1.0)
    pcm = (data * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("  %-22s %6.2fs  %5.0f KB" % (name, len(x) / SR, os.path.getsize(path) / 1024))


# ---------------------------------------------------------------------------
# Instrumentos
# ---------------------------------------------------------------------------
def piano(note, dur, vol=1.0):
    f = hz(note)
    n = int(SR * dur)
    x = sine(f, dur) + 0.5 * sine(2 * f, dur) + 0.25 * sine(3 * f, dur) + 0.12 * sine(4.01 * f, dur)
    return x * exp_env(n, 3.2) * adsr(n, 0.004, 0.05, 1.0, 0.08) * vol


def sax(note, dur, vol=1.0, vib=5.0):
    f = hz(note)
    t = ts(dur)
    vibrato = 1 + 0.006 * np.sin(2 * np.pi * vib * t) * np.minimum(t / 0.25, 1.0)
    phase = 2 * np.pi * np.cumsum(f * vibrato) / SR
    x = np.sin(phase) + 0.55 * np.sin(2 * phase) + 0.4 * np.sin(3 * phase) + 0.2 * np.sin(5 * phase)
    x += 0.04 * noise(dur)
    return x * adsr(len(x), 0.04, 0.08, 0.8, 0.1) * vol


def upright_bass(note, dur, vol=1.0):
    f = hz(note)
    n = int(SR * dur)
    x = sine(f, dur) + 0.4 * sine(2 * f, dur) + 0.15 * sine(3 * f, dur)
    x *= exp_env(n, 2.6) * adsr(n, 0.006, 0.02, 1.0, 0.05)
    return x * vol


def synth_bass(note, dur, vol=1.0, cutoff=700):
    f = hz(note)
    x = saw(f, dur) * 0.7 + square(f / 2, dur) * 0.5
    n = len(x)
    x = lowpass(x, np.linspace(cutoff * 2.5, cutoff * 0.6, n))
    return x * adsr(n, 0.004, 0.06, 0.7, 0.04) * vol


def kick(vol=1.0):
    n = int(SR * 0.28)
    x = sweep(150, 38, 0.28) * exp_env(n, 12)
    click = noise(0.01) * 0.4
    x[: len(click)] += click
    return x * vol


def snare(vol=1.0):
    n = int(SR * 0.22)
    body = sine(190, 0.22) * exp_env(n, 22) * 0.6
    nz = highpass(noise(0.22), 1500) * exp_env(n, 17)
    return (body + nz) * vol


def hat(vol=1.0, open_=False):
    d = 0.2 if open_ else 0.05
    n = int(SR * d)
    return highpass(noise(d), 6000) * exp_env(n, 9 if open_ else 55) * vol


def brush(vol=1.0):
    d = 0.14
    n = int(SR * d)
    return highpass(noise(d), 2500) * adsr(n, 0.03, 0.05, 0.4, 0.06) * vol * 0.6


def tom(note, vol=1.0):
    n = int(SR * 0.35)
    return sweep(hz(note) * 1.6, hz(note), 0.35) * exp_env(n, 9) * vol


def brass(note, dur, vol=1.0):
    n = int(SR * dur)
    x = saw(hz(note), dur) + 0.9 * saw(hz(note) * 1.004, dur) + 0.9 * saw(hz(note) * 0.996, dur)
    x = lowpass(x, np.linspace(500, 3200, n) * 1.0)
    return x * adsr(n, 0.03, 0.1, 0.85, 0.08) * vol * 0.4


def pad(note, dur, vol=1.0):
    n = int(SR * dur)
    x = tri(hz(note), dur) + 0.7 * tri(hz(note) * 1.005, dur) + 0.5 * sine(hz(note) * 2, dur)
    return x * adsr(n, 0.5, 0.2, 0.8, 0.6) * vol * 0.35


def pluck(note, dur, vol=1.0):
    n = int(SR * dur)
    x = square(hz(note), dur, 0.35) * 0.8 + saw(hz(note), dur) * 0.3
    x = lowpass(x, np.linspace(5000, 900, n))
    return x * exp_env(n, 9) * vol


# ---------------------------------------------------------------------------
# Música
# ---------------------------------------------------------------------------
def render_loop(bpm, bars, builder):
    beat = 60.0 / bpm
    total = bars * 4 * beat
    buf = np.zeros(int(SR * total))
    builder(buf, beat)
    return buf


def music_menu():
    def build(buf, beat):
        # Re menor noir: Dm7 Gm7 A7 Dm7 | Bbmaj7 Gm7 A7 Dm
        chords = [
            (50, [62, 65, 69, 72]), (43, [58, 62, 65, 69]), (45, [61, 64, 67, 71]), (50, [62, 65, 69, 72]),
            (46, [62, 65, 69, 70]), (43, [58, 62, 65, 69]), (45, [61, 64, 67, 71]), (50, [62, 65, 69, 74]),
        ]
        walks = [
            [50, 53, 57, 55], [43, 46, 50, 48], [45, 49, 52, 50], [50, 53, 57, 59],
            [46, 50, 53, 52], [43, 46, 50, 51], [45, 49, 52, 48], [50, 48, 45, 49],
        ]
        for bar, (root, voicing) in enumerate(chords):
            t0 = bar * 4 * beat
            for b in range(4):
                mix_into(buf, upright_bass(walks[bar][b], beat * 0.95, 0.9), t0 + b * beat)
                mix_into(buf, brush(0.7), t0 + b * beat + beat * 0.0)
                mix_into(buf, brush(0.45), t0 + b * beat + beat * 0.66)
            for b in (1, 3):
                for n in voicing:
                    mix_into(buf, piano(n, beat * 1.4, 0.16), t0 + b * beat + (0.0 if b == 1 else 0.02))
            if bar % 2 == 0:
                mix_into(buf, piano(voicing[0] - 12, beat * 3.0, 0.2), t0)
        # Melodía de saxo
        mel = [
            (0, 74, 1.5), (1.5, 72, 0.5), (2, 69, 2), (4, 70, 1.5), (5.5, 69, 0.5), (6, 65, 2),
            (8, 69, 1.0), (9, 72, 1.0), (10, 76, 1.5), (11.5, 74, 0.5), (12, 73, 4),
            (16, 70, 1.5), (17.5, 74, 0.5), (18, 77, 2), (20, 76, 1.5), (21.5, 74, 0.5), (22, 69, 2),
            (24, 65, 1.0), (25, 69, 1.0), (26, 73, 1.5), (27.5, 72, 0.5), (28, 74, 4),
        ]
        for start, note, d in mel:
            mix_into(buf, sax(note, d * beat * 0.95, 0.5), start * beat)

    return finish(render_loop(92, 8, build), 0.85)


def music_combat_base():
    def build(buf, beat):
        # Mi menor, 150 bpm
        roots = [40, 40, 43, 38, 36, 36, 43, 47]
        for bar in range(8):
            t0 = bar * 4 * beat
            r = roots[bar]
            pattern = [0, 0, 12, 0, 0, 7, 0, 10]
            for i in range(8):
                note = r + pattern[i] + (12 if i in (2, 6) else 0)
                mix_into(buf, synth_bass(note, beat * 0.45, 0.8, 600 + 80 * (bar % 4)), t0 + i * beat * 0.5)
            for b in range(4):
                if b in (0, 2) or (bar % 2 == 1 and b == 3):
                    mix_into(buf, kick(1.0), t0 + b * beat)
                if b in (1, 3):
                    mix_into(buf, snare(0.8), t0 + b * beat)
            for i in range(8):
                mix_into(buf, hat(0.3 if i % 2 else 0.45), t0 + i * beat * 0.5)
            if bar == 7:
                for i in range(4):
                    mix_into(buf, snare(0.5 + i * 0.1), t0 + 3 * beat + i * beat * 0.25)

    return finish(render_loop(150, 8, build), 0.8)


def music_combat_intense():
    def build(buf, beat):
        notes_by_bar = [
            [64, 67, 71, 76], [64, 67, 71, 76], [67, 71, 74, 79], [62, 66, 69, 74],
            [60, 64, 67, 72], [60, 64, 67, 72], [67, 71, 74, 79], [71, 74, 78, 83],
        ]
        for bar in range(8):
            t0 = bar * 4 * beat
            arp = notes_by_bar[bar]
            for i in range(16):
                mix_into(buf, pluck(arp[i % 4] + (12 if (i // 4) % 2 else 0), beat * 0.24, 0.35), t0 + i * beat * 0.25)
            for n in arp[:3]:
                mix_into(buf, pad(n - 12, beat * 4, 0.35), t0)
            if bar % 2 == 1:
                mix_into(buf, tom(50, 0.7), t0 + 2.5 * beat)
                mix_into(buf, tom(47, 0.7), t0 + 3 * beat)
                mix_into(buf, tom(43, 0.7), t0 + 3.5 * beat)
            mix_into(buf, hat(0.5, True), t0 + 1.5 * beat)
            mix_into(buf, hat(0.5, True), t0 + 3.5 * beat)

    return finish(render_loop(150, 8, build), 0.7)


def music_boss():
    def build(buf, beat):
        # Re menor frigio, 160 bpm
        roots = [38, 38, 39, 38, 34, 34, 39, 37]
        for bar in range(8):
            t0 = bar * 4 * beat
            r = roots[bar]
            for b in range(4):
                mix_into(buf, kick(1.1), t0 + b * beat)
                if b in (1, 3):
                    mix_into(buf, snare(0.9), t0 + b * beat)
                mix_into(buf, hat(0.45), t0 + b * beat + beat * 0.5)
            for i in range(8):
                mix_into(buf, synth_bass(r + (0 if i % 4 else 12), beat * 0.45, 0.9, 500), t0 + i * beat * 0.5)
            # acordes de metal
            third = 3 if bar not in (4, 5) else 4
            for n in (r + 24, r + 24 + third, r + 24 + 7):
                mix_into(buf, brass(n, beat * 0.8, 0.5), t0 + 0.0)
                mix_into(buf, brass(n, beat * 0.5, 0.5), t0 + 2.5 * beat)
            mix_into(buf, pad(r + 12, beat * 4, 0.6), t0)
            if bar % 4 == 3:
                for i in range(8):
                    mix_into(buf, snare(0.4 + i * 0.07), t0 + 3 * beat + i * beat * 0.125)
                mix_into(buf, tom(45, 1.0), t0 + 2 * beat)

    return finish(render_loop(160, 8, build), 0.85)


def ambient_city():
    dur = 12.0
    n = int(SR * dur)
    base = lowpass(noise(dur), 220) * 3.0
    wind = lowpass(noise(dur), np.linspace(300, 700, n) + 250 * np.sin(np.linspace(0, 2 * np.pi * 2, n))) * 2.0
    hum = sine(55, dur) * 0.12 + sine(110.5, dur) * 0.05
    x = base + wind * 0.5 + hum
    # claxon distante
    for st in (3.1, 8.4):
        h = sine(392, 0.35) * adsr(int(SR * 0.35), 0.02, 0.05, 0.6, 0.1) * 0.05
        mix_into(x, lowpass(h, 900), st)
    # fundido circular para bucle sin costuras
    xf = int(SR * 0.5)
    x[:xf] = x[:xf] * np.linspace(0, 1, xf) + x[-xf:] * np.linspace(1, 0, xf)
    x = x[:-xf]
    return finish(x, 0.6, soft=False)


# ---------------------------------------------------------------------------
# Efectos
# ---------------------------------------------------------------------------
def sfx_step(var=0):
    n = int(SR * 0.09)
    x = lowpass(noise(0.09), 700 + 150 * var) * exp_env(n, 40)
    x += sine(90 + 12 * var, 0.09) * exp_env(n, 50) * 0.8
    return x


def sfx_jump():
    return sweep(220, 520, 0.18) * adsr(int(SR * 0.18), 0.005, 0.05, 0.5, 0.1) * 0.8


def sfx_land():
    n = int(SR * 0.15)
    return (lowpass(noise(0.15), 500) * 1.2 + sine(70, 0.15)) * exp_env(n, 28)


def sfx_dodge():
    n = int(SR * 0.3)
    x = highpass(lowpass(noise(0.3), np.linspace(600, 5000, n)), 400)
    return x * adsr(n, 0.05, 0.1, 0.5, 0.12)


def sfx_slam():
    n = int(SR * 0.45)
    low = sweep(130, 35, 0.45) * exp_env(n, 8)
    crack = highpass(noise(0.45), 900) * exp_env(n, 20) * 0.7
    whoosh = lowpass(noise(0.12), np.linspace(400, 3000, int(SR * 0.12))) * adsr(int(SR * 0.12), 0.03, 0.04, 0.4, 0.05)
    out = low + crack
    out[: len(whoosh)] += whoosh * 0.6
    return out


def sfx_swing():
    n = int(SR * 0.2)
    return highpass(lowpass(noise(0.2), np.linspace(500, 4500, n)), 300) * adsr(n, 0.04, 0.06, 0.4, 0.08)


def sfx_docs():
    out = np.zeros(int(SR * 0.5))
    for i in range(6):
        fl = highpass(noise(0.07), 3000) * adsr(int(SR * 0.07), 0.005, 0.02, 0.5, 0.03)
        mix_into(out, fl, i * 0.06, 0.8, wrap=False)
    mix_into(out, sweep(500, 900, 0.3) * adsr(int(SR * 0.3), 0.02, 0.05, 0.4, 0.15) * 0.3, 0.0, 1.0, wrap=False)
    return out


def sfx_seal():
    out = np.zeros(int(SR * 0.9))
    for i, nt in enumerate((72, 76, 79, 84)):
        mix_into(out, sine(hz(nt), 0.6) * exp_env(int(SR * 0.6), 4.5) * 0.5, i * 0.07, 1.0, wrap=False)
        mix_into(out, sine(hz(nt) * 2, 0.4) * exp_env(int(SR * 0.4), 7) * 0.2, i * 0.07, 1.0, wrap=False)
    out += lowpass(noise(0.9), 400) * exp_env(len(out), 4) * 0.3
    return out


def sfx_barrier():
    n = int(SR * 0.7)
    t = ts(0.7)
    hum = (sine(110, 0.7) + 0.5 * sine(165, 0.7)) * adsr(n, 0.05, 0.1, 0.8, 0.3)
    zap = highpass(noise(0.7), 2500) * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t)) * exp_env(n, 5) * 0.5
    return hum * 0.7 + zap


def _hit_core(f0, dur, click_hp, crunch_lp, body_k=26.0):
    """Impacto en tres capas: cuerpo grave con caída de tono, chasquido de ataque y 'crujido'."""
    n = int(SR * dur)
    body = sweep(f0 * 1.7, f0 * 0.5, dur) * exp_env(n, body_k)
    click = highpass(noise(dur), click_hp) * exp_env(n, 150) * 0.85
    crunch = lowpass(noise(dur), crunch_lp) * exp_env(n, 40) * 0.55
    return body + click + crunch


def sfx_hit(var=0):
    f0 = [205, 165, 245, 185, 225][var % 5]
    return _hit_core(f0, 0.17, 1700 + 280 * var, 3300 - 240 * var)


def sfx_crit(var=0):
    """Golpe + campanilla brillante + 'shing' ascendente: se distingue al instante."""
    n = int(SR * 0.36)
    x = pad_to(_hit_core(230 + 25 * var, 0.17, 2200, 3600), n) * 1.05
    f = 1320 if var == 0 else 1480
    for k, a in ((1.0, 0.5), (1.5, 0.32), (2.0, 0.2)):
        x += sine(f * k, 0.36) * exp_env(n, 11 + 3 * k) * a
    x += highpass(sweep(1800, 5200, 0.36), 1500) * exp_env(n, 14) * 0.18
    return x


def sfx_hit_heavy():
    n = int(SR * 0.32)
    x = pad_to(_hit_core(120, 0.3, 1200, 2200, 14.0), n) * 1.1
    x += sine(58, 0.32) * exp_env(n, 9) * 0.8
    return x


def sfx_hit_boss():
    """Golpe a jefe: subgrave + metal inarmónico, más largo y pesado."""
    n = int(SR * 0.5)
    x = sweep(120, 38, 0.5) * exp_env(n, 6.5) * 1.1
    x += pad_to(_hit_core(95, 0.3, 1000, 1800, 12.0), n) * 0.9
    for f, a in ((312, 0.35), (487, 0.25), (731, 0.16)):
        x += sine(f, 0.5) * exp_env(n, 9) * a
    return x


def sfx_hit_fire():
    n = int(SR * 0.3)
    t = ts(0.3)
    crackle = highpass(noise(0.3), 2800) * (RNG.uniform(0, 1, n) > 0.82) * exp_env(n, 9)
    whoosh = lowpass(noise(0.3), np.linspace(2600, 500, n)) * exp_env(n, 8) * 0.8
    return pad_to(_hit_core(190, 0.17, 1600, 3000), n) * 0.8 + crackle * 1.2 + whoosh


def sfx_hit_ice():
    n = int(SR * 0.3)
    x = pad_to(_hit_core(260, 0.15, 2600, 4200), n) * 0.7
    for f, a in ((2400, 0.4), (3100, 0.3), (3900, 0.22)):
        x += sine(f, 0.3) * exp_env(n, 26) * a
    x += highpass(noise(0.3), 4000) * exp_env(n, 40) * 0.5
    return x


def sfx_hit_shock():
    n = int(SR * 0.26)
    t = ts(0.26)
    buzz = highpass(noise(0.26), 1500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 110 * t))) * exp_env(n, 14)
    zip_ = sweep(2600, 260, 0.26) * exp_env(n, 17) * 0.45
    return pad_to(_hit_core(210, 0.14, 2000, 3800), n) * 0.7 + buzz * 0.9 + zip_


def sfx_dot_tick():
    """Tic suave de efecto periódico (quemadura, zona): no compite con los golpes."""
    n = int(SR * 0.13)
    return highpass(noise(0.13), 2200) * exp_env(n, 38) * 0.6 + sine(320, 0.13) * exp_env(n, 40) * 0.4


def sfx_combo():
    """Arpegio ascendente cristalino: cadena de impactos de una sinergia."""
    n = int(SR * 0.42)
    x = np.zeros(n)
    for i, note in enumerate((76, 79, 83, 88)):
        seg = sine(hz(note), 0.3) * exp_env(int(SR * 0.3), 9) + sine(hz(note) * 2, 0.3) * exp_env(int(SR * 0.3), 14) * 0.35
        mix_into(x, seg, i * 0.055, 0.7, wrap=False)
    x += highpass(noise(0.42), 5000) * exp_env(n, 12) * 0.12
    return x


def sfx_kill():
    n = int(SR * 0.3)
    x = sweep(420, 90, 0.3) * exp_env(n, 9) * 0.8 + highpass(noise(0.3), 1000) * exp_env(n, 14) * 0.5
    return x


def sfx_kill_boss():
    n = int(SR * 0.9)
    x = sweep(360, 34, 0.9) * exp_env(n, 4.5) * 0.9
    x += lowpass(noise(0.9), np.linspace(3000, 150, n)) * exp_env(n, 4) * 1.2
    x += sine(55, 0.9) * exp_env(n, 5) * 0.8
    for f, a in ((523, 0.25), (784, 0.2)):
        x += sine(f, 0.9) * exp_env(n, 6) * a
    return x


def sfx_explosion():
    n = int(SR * 0.7)
    x = lowpass(noise(0.7), np.linspace(2500, 120, n)) * exp_env(n, 5) * 1.5
    x += sweep(90, 28, 0.7) * exp_env(n, 6)
    return x


def sfx_zap():
    n = int(SR * 0.28)
    t = ts(0.28)
    x = highpass(noise(0.28), 1800) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 90 * t))) * exp_env(n, 9)
    x += sweep(1800, 300, 0.28) * exp_env(n, 12) * 0.4
    return x


def sfx_spawn():
    n = int(SR * 0.4)
    return sweep(90, 420, 0.4) * adsr(n, 0.1, 0.1, 0.6, 0.15) * 0.7 + lowpass(noise(0.4), 900) * exp_env(n, 7) * 0.4


def sfx_enemy_shoot():
    n = int(SR * 0.22)
    return sweep(900, 220, 0.22) * exp_env(n, 12) * 0.8 + highpass(noise(0.22), 2000) * exp_env(n, 28) * 0.3


def sfx_telegraph():
    n = int(SR * 0.35)
    return sweep(300, 750, 0.35, "lin") * adsr(n, 0.02, 0.05, 0.7, 0.1) * 0.4


def sfx_boss_roar():
    n = int(SR * 1.2)
    t = ts(1.2)
    x = saw(70, 1.2)
    x = lowpass(x + 0.6 * saw(105, 1.2) + noise(1.2) * 0.25, np.linspace(300, 1200, n))
    return x * adsr(n, 0.15, 0.3, 0.8, 0.4)


def sfx_hurt():
    n = int(SR * 0.3)
    return (sweep(300, 140, 0.3) * exp_env(n, 8) + lowpass(noise(0.3), 1500) * exp_env(n, 16) * 0.6) * 0.9


def sfx_chest():
    out = np.zeros(int(SR * 1.3))
    creak = sweep(110, 190, 0.5, "lin") * (0.6 + 0.4 * np.sin(2 * np.pi * 26 * ts(0.5))) * adsr(int(SR * 0.5), 0.05, 0.1, 0.6, 0.15)
    mix_into(out, lowpass(creak, 1100) * 0.6, 0.0, 1.0, wrap=False)
    for i, nt in enumerate((79, 83, 86, 91, 95)):
        mix_into(out, sine(hz(nt), 0.5) * exp_env(int(SR * 0.5), 6) * 0.4, 0.45 + i * 0.07, 1.0, wrap=False)
    return out


def sfx_card():
    out = np.zeros(int(SR * 0.5))
    for i, nt in enumerate((76, 83, 88)):
        mix_into(out, sine(hz(nt), 0.4) * exp_env(int(SR * 0.4), 8) * 0.5, i * 0.06, 1.0, wrap=False)
    return out


def sfx_card_flip():
    n = int(SR * 0.12)
    return highpass(noise(0.12), 2200) * adsr(n, 0.01, 0.04, 0.3, 0.05) * 0.6


def sfx_buy():
    out = np.zeros(int(SR * 0.7))
    mix_into(out, highpass(noise(0.06), 2000) * exp_env(int(SR * 0.06), 50), 0.0, 1.0, wrap=False)
    mix_into(out, sine(hz(88), 0.5) * exp_env(int(SR * 0.5), 6) * 0.5, 0.08, 1.0, wrap=False)
    mix_into(out, sine(hz(95), 0.6) * exp_env(int(SR * 0.6), 5) * 0.5, 0.16, 1.0, wrap=False)
    return out


def sfx_deny():
    n = int(SR * 0.25)
    return square(110, 0.25) * adsr(n, 0.01, 0.05, 0.7, 0.1) * 0.35


def sfx_coin():
    n = int(SR * 0.22)
    return (sine(hz(88), 0.22) + 0.5 * sine(hz(95), 0.22)) * exp_env(n, 14) * adsr(n, 0.002, 0.02, 1.0, 0.05) * 0.6


def sfx_alert():
    out = np.zeros(int(SR * 0.9))
    for i in range(3):
        beep = square(880, 0.12, 0.5) * adsr(int(SR * 0.12), 0.005, 0.02, 0.8, 0.04) * 0.35
        mix_into(out, beep, i * 0.25, 1.0, wrap=False)
    return out


def sfx_victory():
    out = np.zeros(int(SR * 2.4))
    seq = [(60, 0.0, 0.25), (64, 0.2, 0.25), (67, 0.4, 0.25), (72, 0.6, 0.5), (67, 1.1, 0.2), (72, 1.3, 1.0)]
    for nt, st, d in seq:
        mix_into(out, brass(nt + 12, d, 1.0), st, 1.0, wrap=False)
        mix_into(out, brass(nt, d, 0.6), st, 1.0, wrap=False)
    return out


def sfx_defeat():
    out = np.zeros(int(SR * 2.4))
    seq = [(67, 0.0, 0.5), (64, 0.5, 0.5), (60, 1.0, 0.5), (55, 1.5, 0.9)]
    for nt, st, d in seq:
        mix_into(out, sax(nt, d, 0.9, 4.0), st, 1.0, wrap=False)
        mix_into(out, upright_bass(nt - 24, d, 0.9), st, 1.0, wrap=False)
    return out


def sfx_click():
    n = int(SR * 0.05)
    return sine(1000, 0.05) * exp_env(n, 70) * 0.7


def sfx_levelup():
    out = np.zeros(int(SR * 0.9))
    for i, nt in enumerate((72, 76, 79, 84)):
        mix_into(out, pluck(nt, 0.3, 0.7), i * 0.09, 1.0, wrap=False)
    return out


def sfx_heal():
    n = int(SR * 0.5)
    return sweep(400, 900, 0.5, "lin") * adsr(n, 0.05, 0.1, 0.6, 0.2) * 0.4


def sfx_portal():
    n = int(SR * 1.0)
    return (sweep(150, 700, 1.0, "lin") * 0.6 + sine(260, 1.0) * 0.3) * adsr(n, 0.2, 0.2, 0.6, 0.4) * 0.8


def sfx_phase():
    n = int(SR * 1.0)
    x = sfx_boss_roar()
    return pad_to(x, n) + sweep(80, 400, 1.0, "lin") * 0.4


def sfx_shield():
    n = int(SR * 0.35)
    return sweep(300, 900, 0.35) * adsr(n, 0.01, 0.05, 0.5, 0.15) * 0.6 + highpass(noise(0.35), 3000) * exp_env(n, 12) * 0.3


# ---------------------------------------------------------------------------
def main():
    print("Generando audio en", os.path.normpath(OUT))
    print("Música:")
    write_wav("music_menu", music_menu())
    write_wav("music_combat_a", music_combat_base())
    write_wav("music_combat_b", music_combat_intense())
    write_wav("music_boss", music_boss())
    write_wav("amb_city", ambient_city())
    print("Efectos:")
    sfx = {
        "step_0": sfx_step(0), "step_1": sfx_step(1), "step_2": sfx_step(2),
        "jump": sfx_jump(), "land": sfx_land(), "dodge": sfx_dodge(),
        "slam": sfx_slam(), "swing": sfx_swing(), "docs": sfx_docs(), "seal": sfx_seal(),
        "barrier": sfx_barrier(), "hit_0": sfx_hit(0), "hit_1": sfx_hit(1), "hit_2": sfx_hit(2),
        "hit_3": sfx_hit(3), "hit_4": sfx_hit(4),
        "crit": sfx_crit(0), "crit_1": sfx_crit(1), "hit_heavy": sfx_hit_heavy(), "hit_boss": sfx_hit_boss(),
        "hit_fire": sfx_hit_fire(), "hit_ice": sfx_hit_ice(), "hit_shock": sfx_hit_shock(),
        "dot_tick": sfx_dot_tick(), "combo": sfx_combo(), "kill_boss": sfx_kill_boss(), "kill": sfx_kill(), "explosion": sfx_explosion(), "zap": sfx_zap(),
        "spawn": sfx_spawn(), "enemy_shoot": sfx_enemy_shoot(), "telegraph": sfx_telegraph(),
        "boss_roar": sfx_boss_roar(), "hurt": sfx_hurt(), "chest": sfx_chest(), "card": sfx_card(),
        "card_flip": sfx_card_flip(), "buy": sfx_buy(), "deny": sfx_deny(), "coin": sfx_coin(),
        "alert": sfx_alert(), "victory": sfx_victory(), "defeat": sfx_defeat(), "click": sfx_click(),
        "levelup": sfx_levelup(), "heal": sfx_heal(), "portal": sfx_portal(), "phase": sfx_phase(),
        "shield": sfx_shield(),
    }
    for name, data in sfx.items():
        write_wav("sfx_" + name, finish(data, 0.9))
    print("Listo.")


if __name__ == "__main__":
    main()
