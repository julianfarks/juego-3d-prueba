#!/usr/bin/env python3
"""Genera los efectos de sonido PROPIOS del tráiler (síntesis, sin muestras externas):
gavel.wav (martillo de juez), gavel_big.wav (martillo con eco de sala), whoosh.wav (barrido),
boom.wav (golpe grave para el logo), stapler.wav (grapadora). Uso: python3 make_sfx.py <carpeta_salida>"""
import sys, wave, numpy as np
SR = 44100
rng = np.random.default_rng(7)

def save(name, x):
    x = np.asarray(x, dtype=np.float64)
    x = x / max(1e-9, np.max(np.abs(x))) * 0.95
    with wave.open(f"{OUT}/{name}", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

def t(dur):
    return np.arange(int(SR * dur)) / SR

def env_exp(dur, k):
    return np.exp(-t(dur) * k)

def lowpass(x, a):
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc); y[i] = acc
    return y

def knock(dur=0.45, f1=520, f2=1340, thump=110):
    tt = t(dur)
    body = 0.9 * np.sin(2*np.pi*f1*tt) * np.exp(-tt*28) + 0.45 * np.sin(2*np.pi*f2*tt) * np.exp(-tt*45)
    body += 0.35 * np.sin(2*np.pi*(f1*1.52)*tt) * np.exp(-tt*38)
    low = 1.1 * np.sin(2*np.pi*thump*tt) * np.exp(-tt*22)
    click = np.zeros_like(tt); n = int(0.004*SR)
    click[:n] = rng.uniform(-1, 1, n) * np.linspace(1, 0, n)
    noise = lowpass(rng.uniform(-1, 1, len(tt)), 0.25) * np.exp(-tt*60) * 0.8
    return body + low + click * 1.4 + noise

def reverb(x, tail=1.6, mix=0.35):
    out = np.concatenate([x, np.zeros(int(SR*tail))])
    for d, g in [(0.031, 0.5), (0.047, 0.42), (0.071, 0.36), (0.113, 0.3), (0.167, 0.24), (0.229, 0.18), (0.311, 0.12)]:
        k = int(d*SR); e = np.zeros_like(out); src = out.copy()
        for rep in range(1, 7):
            off = k*rep
            if off >= len(out): break
            e[off:] += src[:len(out)-off] * (g**rep)
        out = out + e * mix
    return out

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
g = knock()
save("gavel.wav", g)
big = knock(0.6, 470, 1210, 85) * 1.0
big = np.concatenate([big, np.zeros(int(SR*0.05))])
save("gavel_big.wav", reverb(big, 1.8, 0.45))
# whoosh: ruido filtrado con barrido de brillo
tt = t(0.7)
n = rng.uniform(-1, 1, len(tt))
sweep = np.zeros_like(n); acc = 0.0
for i, v in enumerate(n):
    a = 0.02 + 0.35 * np.sin(np.pi * i / len(n))**2
    acc += a * (v - acc); sweep[i] = acc
save("whoosh.wav", sweep * np.sin(np.pi * tt / 0.7)**1.5)
# boom grave (caída de 70 a 32 Hz) + chasquido
tt = t(2.4)
f = 32 + 38 * np.exp(-tt*3.0)
ph = 2*np.pi*np.cumsum(f)/SR
boom = np.sin(ph) * np.exp(-tt*1.6) + 0.25*lowpass(rng.uniform(-1, 1, len(tt)), 0.05)*np.exp(-tt*4)
boom[:int(0.01*SR)] += rng.uniform(-1, 1, int(0.01*SR)) * 0.6
save("boom.wav", reverb(boom, 0.8, 0.2))
# grapadora: dos chasquidos metálicos
def clack(f):
    tt = t(0.09)
    return (np.sin(2*np.pi*f*tt) + 0.6*np.sin(2*np.pi*f*2.7*tt)) * np.exp(-tt*70) + rng.uniform(-1, 1, len(tt))*np.exp(-tt*200)
s = np.zeros(int(SR*0.3)); a = clack(2300); b = clack(1700)
s[:len(a)] += a; s[int(0.11*SR):int(0.11*SR)+len(b)] += b * 1.2
save("stapler.wav", s)
print("ok")
