"""Synthesise the Magical Forest bush rustles (no samples needed).

audio/forest/rustle_1..4.wav - pushing through leaves: a band-passed noise swish shaped by a
few overlapping leaf-brush envelopes, with dry twig ticks and a soft papery crackle on top.
Each variant has a different length, brightness and rhythm.
audio/forest/sizzle.wav - a seamless 4 s loop for burnt-out scorch marks: a soft hiss of steam
under random ember crackles and pops. The end crossfades into the start so it loops cleanly.

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


def sizzle(seed=41, dur=4.0):
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    t = np.arange(n) / SR
    hiss = bp(rng.normal(0, 1, n), 2500, 9000) * (0.18 + 0.08 * np.sin(2 * np.pi * 0.7 * t) + 0.05 * np.sin(2 * np.pi * 1.9 * t))
    crackle = np.zeros(n)
    for _ in range(90):   # tiny ember pops
        i = rng.integers(0, n - 2000)
        L = rng.integers(60, 400)
        crackle[i:i + L] += rng.normal(0, 1, L) * np.exp(-np.arange(L) / (L / 4)) * rng.uniform(0.2, 0.9)
    x = hiss + hp(crackle, 1200) * 0.7
    # seamless loop: crossfade the last 0.3 s into the start
    f = int(SR * 0.3)
    ramp = np.linspace(0, 1, f)
    x[:f] = x[:f] * ramp + x[-f:] * (1 - ramp)
    x = x[:-f]
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.7
    return x


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    specs = [(31, 0.55, 900, 5500, 3), (32, 0.7, 700, 4500, 4), (33, 0.45, 1200, 7000, 2), (34, 0.85, 600, 4000, 5)]
    for k, s in enumerate(specs, 1):
        wavfile.write(f"{OUT}rustle_{k}.wav", SR, (rustle(*s) * 32767).astype(np.int16))
        print("wrote", f"{OUT}rustle_{k}.wav")
    wavfile.write(f"{OUT}sizzle.wav", SR, (sizzle() * 32767).astype(np.int16))
    print("wrote", f"{OUT}sizzle.wav")
