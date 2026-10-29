"""Synthesise the Magical Forest bush rustles (no samples needed).

audio/forest/rustle_1..4.wav - pushing through leaves: a band-passed noise swish shaped by a
few overlapping leaf-brush envelopes, with dry twig ticks and a soft papery crackle on top.
Each variant has a different length, brightness and rhythm.

    python3 tools/gen_forest_sounds.py
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/forest/"


def bp(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def hp(x, hz, order=3):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def rustle(seed, dur, lo, hi, brushes):
    rng = np.random.default_rng(seed)
    t = np.arange(int(SR * dur)) / SR
    chans = []
    for c in range(2):
        noise = rng.normal(0, 1, t.size)
        env = np.zeros_like(t)
        for _ in range(brushes):   # each leaf brush: a quick swell and a slower fade
            t0 = rng.uniform(0, dur * 0.55)
            a = rng.uniform(0.02, 0.06)
            d = rng.uniform(0.08, 0.22)
            tt = np.clip(t - t0, 0, None)
            env += (1 - np.exp(-tt / a)) * np.exp(-tt / d) * (t >= t0) * rng.uniform(0.5, 1.0)
        # flutter: leaves slapping against each other
        env *= 0.7 + 0.3 * np.abs(np.sin(2 * np.pi * rng.uniform(18, 30) * t + c))
        swish = bp(noise, lo, hi) * env
        ticks = np.zeros_like(t)
        for _ in range(rng.integers(4, 10)):
            t0 = rng.uniform(0, dur * 0.7)
            tt = np.clip(t - t0, 0, None)
            ticks += hp(rng.normal(0, 1, t.size), 2500) * np.exp(-tt / 0.003) * (t >= t0) * rng.uniform(0.3, 0.8)
        crackle = hp(noise * (rng.random(t.size) < 0.004), 3000) * env * 2.0
        x = swish + ticks * 0.5 + crackle
        fade = np.minimum(1.0, (dur - t) / 0.08)
        chans.append(x * np.clip(fade, 0, 1))
    st = np.stack(chans, 1)
    return st / (np.max(np.abs(st)) + 1e-9) * 0.8


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    specs = [(31, 0.55, 900, 5500, 3), (32, 0.7, 700, 4500, 4), (33, 0.45, 1200, 7000, 2), (34, 0.85, 600, 4000, 5)]
    for k, s in enumerate(specs, 1):
        wavfile.write(f"{OUT}rustle_{k}.wav", SR, (rustle(*s) * 32767).astype(np.int16))
        print("wrote", f"{OUT}rustle_{k}.wav")
