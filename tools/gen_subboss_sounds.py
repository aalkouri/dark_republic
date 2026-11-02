"""Synthesise the sub-boss's and the waygates' sounds (no samples needed).

audio/subboss/arrive.wav        a sub-boss arrives: a wet burst of bog mud and a deep, guttural
                                two-note chant (about 2.2 s)
audio/subboss/slam.wav          Mud Slam: a heavy thud into wet ground, a splat and a low rumble
audio/subboss/bolt.wav          Bog Bolt: a gurgling hiss that rips past (about 0.9 s)
audio/subboss/death.wav         its death: a falling groan and a sloppy collapse
audio/subboss/gate_rise.wav     a waygate grinds up out of the ground (about 1.5 s)
audio/subboss/gate_activate.wav both gates light up: a rising airy chord and a soft "whomp"
audio/subboss/gate_hum.wav      a gate's hum, a seamless loop (exactly 4 s)
audio/subboss/gate_teleport.wav going through: a quick whoosh with a shimmer (about 1.1 s)

    python3 tools/gen_subboss_sounds.py
"""
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "subboss")


def lowpass(x, hz, order=4):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def highpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bandpass(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def osc(f):
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def env(t, a, d):
    return np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-np.maximum(t - a, 0) / d)


def finish(x, fade_s=0.05, peak=0.9, drive=1.3):
    x = np.tanh(x * drive)
    if fade_s > 0:
        n = int(SR * fade_s)
        x[-n:] *= np.linspace(1, 0, n) ** 2
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    return (x * 32767).astype(np.int16)


def mud(t, r, at=0.0, dur=0.5, lo=120, hi=1600):
    n = r.normal(0, 1, t.size)
    e = env(np.maximum(t - at, 0), 0.01, dur * 0.35) * (t >= at)
    bub = 0.5 + 0.5 * np.sin(2 * np.pi * (18 + 30 * r.random()) * t) ** 2
    return bandpass(n, lo, hi) * e * bub


def arrive():
    t = np.arange(int(SR * 2.3)) / SR
    r = np.random.default_rng(1)
    x = mud(t, r, 0.0, 0.8, 80, 1400) * 1.4
    x += lowpass(r.normal(0, 1, t.size), 90) * env(t, 0.02, 0.5) * 3.0   # the ground heaving
    # the chant: two growled notes, rough with a sub-harmonic buzz
    for k, (at, f0) in enumerate([(0.35, 82.0), (1.05, 73.0)]):
        tt = t - at
        on = (tt > 0) & (tt < 0.95)
        f = f0 * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * t)) * np.where(tt > 0.6, 1 - 0.08 * (tt - 0.6), 1)
        v = sum(np.sin(2 * np.pi * np.cumsum(f * h) / SR) / h ** 0.8 for h in range(1, 9))
        v *= 1 + 0.6 * np.sign(np.sin(2 * np.pi * np.cumsum(f * 0.5) / SR))   # growl
        v = bandpass(v, 60, 2200) * np.clip(tt / 0.08, 0, 1) * np.clip((0.95 - tt) / 0.25, 0, 1) * on
        x += v * 0.5
    return finish(lowpass(x, 5000), 0.2)


def slam():
    t = np.arange(int(SR * 1.4)) / SR
    r = np.random.default_rng(2)
    thud = np.sin(2 * np.pi * np.cumsum(70 * np.exp(-t * 5) + 32) / SR) * env(t, 0.003, 0.25)
    x = thud * 2.5 + mud(t, r, 0.01, 0.5, 150, 2500) * 1.2
    x += lowpass(r.normal(0, 1, t.size), 120) * env(t, 0.01, 0.6) * 2.0
    return finish(x, 0.2, drive=1.6)


def bolt():
    t = np.arange(int(SR * 0.95)) / SR
    r = np.random.default_rng(3)
    hiss = bandpass(r.normal(0, 1, t.size), 900, 6000) * env(t, 0.05, 0.3)
    gurgle = np.sin(2 * np.pi * np.cumsum(180 + 120 * np.sin(2 * np.pi * 23 * t) + 300 * np.exp(-t * 4)) / SR)
    x = hiss + gurgle * env(t, 0.02, 0.25) * 0.6 + mud(t, r, 0.0, 0.4, 200, 2000) * 0.6
    return finish(x, 0.15)


def death():
    t = np.arange(int(SR * 2.0)) / SR
    r = np.random.default_rng(4)
    f = 120 * np.exp(-t * 0.9) + 40
    v = sum(np.sin(2 * np.pi * np.cumsum(f * h) / SR) / h for h in range(1, 7))
    v = bandpass(v, 50, 1800) * np.clip(t / 0.05, 0, 1) * np.clip((1.3 - t) / 0.5, 0, 1)
    x = v * 0.8 + mud(t, r, 1.05, 0.8, 90, 1500) * 1.5
    x += lowpass(r.normal(0, 1, t.size), 100) * env(np.maximum(t - 1.05, 0), 0.01, 0.4) * (t > 1.05) * 2.5
    return finish(x, 0.3)


def gate_rise():
    t = np.arange(int(SR * 1.6)) / SR
    r = np.random.default_rng(5)
    grind = bandpass(r.normal(0, 1, t.size), 60, 700) * (0.6 + 0.4 * np.sin(2 * np.pi * 13 * t) ** 2)
    grind *= np.minimum(1, t / 0.1) * np.clip((1.45 - t) / 0.3, 0, 1)
    x = grind + lowpass(r.normal(0, 1, t.size), 70) * np.clip((1.45 - t) / 0.3, 0, 1) * 1.5
    x += np.sin(2 * np.pi * 55 * t) * env(np.maximum(t - 1.3, 0), 0.005, 0.15) * (t > 1.3) * 2.0   # settles
    return finish(x, 0.1)


def gate_activate():
    t = np.arange(int(SR * 2.0)) / SR
    x = np.zeros_like(t)
    for f in (220.0, 277.2, 329.6, 440.0):
        ff = f * (0.94 + 0.06 * np.minimum(1, t / 0.8))
        x += np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.minimum(1, t / 0.6) * np.exp(-np.maximum(t - 0.8, 0) / 0.6)
    r = np.random.default_rng(6)
    x += bandpass(r.normal(0, 1, t.size), 2000, 8000) * np.minimum(1, t / 0.7) * np.exp(-np.maximum(t - 0.7, 0) / 0.3) * 0.5
    x += np.sin(2 * np.pi * np.cumsum(90 * np.exp(-np.maximum(t - 0.75, 0) * 6) + 45) / SR) * env(np.maximum(t - 0.75, 0), 0.01, 0.35) * (t > 0.75) * 1.5
    return finish(x * 0.6, 0.3)


def gate_hum():
    n = SR * 4
    t = np.arange(n) / SR
    # whole cycles in 4 s so it loops cleanly
    x = np.sin(2 * np.pi * 110 * t) + 0.7 * np.sin(2 * np.pi * 110.5 * t) + 0.35 * np.sin(2 * np.pi * 165 * t)
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t)
    r = np.random.default_rng(7)
    air = r.normal(0, 1, n)
    air = np.fft.irfft(np.fft.rfft(air) * ((np.fft.rfftfreq(n, 1 / SR) > 1500) & (np.fft.rfftfreq(n, 1 / SR) < 5000)), n)   # circular: loops
    x += air / (np.max(np.abs(air)) + 1e-9) * 0.25 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.25 * t))
    x = x / np.max(np.abs(x)) * 0.8
    return (x * 32767).astype(np.int16)


def gate_teleport():
    t = np.arange(int(SR * 1.1)) / SR
    r = np.random.default_rng(8)
    n = r.normal(0, 1, t.size)
    sweep = np.zeros_like(t)
    # a band of noise sweeping up then away
    for lo, hi, w in ((300, 900, 1.0), (900, 2500, 0.8), (2500, 7000, 0.5)):
        sweep += bandpass(n, lo, hi) * w * np.exp(-((t - 0.2 - lo / 9000) / 0.15) ** 2)
    shimmer = sum(np.sin(2 * np.pi * f * t) for f in (1320.0, 1760.0, 2640.0)) * env(np.maximum(t - 0.25, 0), 0.01, 0.35) * (t > 0.25)
    return finish(sweep * 1.5 + shimmer * 0.25, 0.2)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("arrive", arrive), ("slam", slam), ("bolt", bolt), ("death", death),
                     ("gate_rise", gate_rise), ("gate_activate", gate_activate),
                     ("gate_hum", gate_hum), ("gate_teleport", gate_teleport)]:
        wavfile.write(os.path.join(OUT, name + ".wav"), SR, fn())
        print("wrote", name)


if __name__ == "__main__":
    main()
