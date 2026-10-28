"""Synthesise the Meteor impact explosion (no samples needed).

audio/abilities/meteor_impact.wav - a heavy boom: a sharp noisy crack, a deep sub-bass thump
that pitches down, a rumbling low-passed roar, and crackling debris that fades out.

    python3 tools/gen_explosion_sound.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
DUR = 3.2
rng = np.random.default_rng(11)
t = np.arange(int(SR * DUR)) / SR


def lowpass(x, hz, order=4):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def bandpass(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def channel(seed):
    r = np.random.default_rng(seed)
    noise = r.normal(0, 1, t.size)
    # 1) crack: a bright noise transient, first ~60 ms
    crack = bandpass(noise, 900, 7000) * np.exp(-t / 0.025) * 1.1
    # 2) thump: a sine that drops from 95 Hz to 32 Hz
    f = 32 + 63 * np.exp(-t / 0.12)
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.55) * 1.0
    # 3) roar: low-passed noise that swells fast and rumbles out
    roar_env = (1 - np.exp(-t / 0.02)) * np.exp(-t / 0.9)
    roar = lowpass(noise, 420) * roar_env * 2.6
    rumble = lowpass(r.normal(0, 1, t.size), 90) * np.exp(-t / 1.4) * 3.5
    # 4) debris: sparse crackles and pops scattered over the tail
    debris = np.zeros_like(t)
    for _ in range(140):
        at = 0.08 + r.exponential(0.55)
        if at >= DUR - 0.05:
            continue
        n = int(SR * r.uniform(0.004, 0.02))
        i = int(at * SR)
        pop = r.normal(0, 1, n) * np.exp(-np.linspace(0, 6, n))
        debris[i:i + n] += pop * r.uniform(0.1, 0.45) * np.exp(-at / 1.0)
    debris = bandpass(debris, 600, 5000)
    return crack + thump + roar + rumble + debris


left = channel(1)
right = channel(2)
st = np.stack([left, right], axis=1)
# soft-clip for a dense, punchy boom, then normalise
st = np.tanh(st * 1.4)
fade = np.ones(t.size)
fade[-int(SR * 0.3):] = np.linspace(1, 0, int(SR * 0.3))
st *= fade[:, None]
st /= np.max(np.abs(st)) / 0.95
wavfile.write("audio/abilities/meteor_impact.wav", SR, (st * 32767).astype(np.int16))
print("wrote audio/abilities/meteor_impact.wav")
