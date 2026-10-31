"""Synthesise the bomber skeletons' sounds (no samples needed).

audio/castle/barrel_blast.wav - a keg of black powder going off in a stone hall: a sharp crack,
                                a deep boom, splintering wood and a long rumbling tail.
audio/castle/bomber_rise.wav  - the dead clawing up through the floor: grinding stone, cracking
                                flagstones and a trickle of falling grit.

    python3 tools/gen_bomber_sounds.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/castle/"


def lp(x, hz, order=3):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def reverb(x, rng, seconds=2.2, wet=0.4):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = lp(rng.normal(0, 1, n) * np.exp(-t / (seconds / 6.0)), 2200)
    ir /= np.sqrt(np.sum(ir ** 2))
    out = np.convolve(x, ir)[: x.size + n]
    return np.pad(x, (0, out.size - x.size)) * (1 - wet) + out * wet


def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    wavfile.write(OUT + name, SR, (x * 32767).astype(np.int16))
    print("wrote", OUT + name)


def blast(rng):
    n = int(SR * 1.6)
    t = np.arange(n) / SR
    crack = rng.normal(0, 1, n) * np.exp(-t / 0.012)
    boom = lp(rng.normal(0, 1, n), 180, 4) * np.exp(-t / 0.35) * 6.0
    thump = np.sin(2 * np.pi * (55 - 25 * t) * t) * np.exp(-t / 0.25) * 1.5
    splinter = np.zeros(n)
    for k in range(40):
        at = int(SR * rng.uniform(0.01, 0.5))
        ln = int(SR * 0.02)
        if at + ln < n:
            splinter[at:at + ln] += bp(rng.normal(0, 1, ln), 1500, 6000) * np.exp(-np.arange(ln) / (SR * 0.004)) * rng.uniform(0.1, 0.4)
    rumble = lp(rng.normal(0, 1, n), 90, 2) * np.exp(-t / 0.7) * 3.0
    return reverb(crack + boom + thump + splinter + rumble, rng, 2.4, 0.35)


def rise(rng):
    n = int(SR * 1.3)
    t = np.arange(n) / SR
    grind = bp(rng.normal(0, 1, n), 120, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t) ** 2) * np.minimum(t / 0.2, 1) * np.exp(-t / 0.9)
    cracks = np.zeros(n)
    for k in range(6):
        at = int(SR * rng.uniform(0.05, 0.9))
        ln = int(SR * 0.05)
        cracks[at:at + ln] += bp(rng.normal(0, 1, ln), 600, 4000) * np.exp(-np.arange(ln) / (SR * 0.008)) * rng.uniform(0.6, 1.2)
    grit = bp(rng.normal(0, 1, n), 3000, 9000) * (rng.random(n) < 0.004) * 3.0
    return reverb(grind * 0.8 + cracks + grit, rng, 1.4, 0.3)


if __name__ == "__main__":
    rng = np.random.default_rng(7)
    save("barrel_blast.wav", blast(rng))
    save("bomber_rise.wav", rise(rng))
