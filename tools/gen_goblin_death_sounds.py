"""Synthesise the goblin death sounds (no samples, no voices).

audio/goblin/death_1..4.wav - short, punchy "splat-pop" kills: a soft body thud, a wet squelch
(band-passed noise with a quick pitch drop) and a little puff of air. Four variants so a big
wave of kills doesn't sound like a machine gun.

    python3 tools/gen_goblin_death_sounds.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def lp(x, hz, order=3):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def death(seed):
    r = np.random.default_rng(seed)
    dur = 0.34
    t = np.arange(int(SR * dur)) / SR
    # thud: a short sine that drops in pitch
    f0 = r.uniform(120, 160)
    f = f0 * 0.45 + f0 * 0.55 * np.exp(-t / 0.035)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.07)
    # squelch: noise through a band that sweeps down (wet splat)
    noise = r.normal(0, 1, t.size)
    sq = np.zeros_like(t)
    hi_band = r.uniform(2200, 3000)
    for k in range(6):   # piecewise sweep
        a, b = int(t.size * k / 6), int(t.size * (k + 1) / 6)
        c = max(260.0, hi_band * (0.6 ** k))
        sq[a:b] = bp(noise, c * 0.45, c, 2)[a:b]
    squelch = sq * np.exp(-t / 0.06) * 1.6
    # puff: soft low-passed air
    puff = lp(r.normal(0, 1, t.size), 900) * np.exp(-((t - 0.03) / 0.05) ** 2) * 0.8
    x = thud * 0.9 + squelch + puff
    x[: int(SR * 0.002)] *= np.linspace(0, 1, int(SR * 0.002))   # no click
    x = np.tanh(x * 1.3)
    x /= np.max(np.abs(x)) / 0.85
    return x


for i in range(4):
    x = death(100 + i)
    wavfile.write("audio/goblin/death_%d.wav" % (i + 1), SR, (x * 32767).astype(np.int16))
print("wrote audio/goblin/death_1..4.wav")
