"""Synthesise Thog the Troll's sounds (no samples needed).

audio/thog/roar.wav   - a huge throaty bellow: a low growling voice (sawtooth-ish pulse train
                        through formant filters) with a rough noise rasp, rising then falling.
audio/thog/slam.wav   - two fists into the ground: a sub-bass boom, a mud splat and debris.
audio/thog/sweep.wav  - a club swung through the air: a big doppler whoosh ending in a thud.
audio/thog/step.wav   - a footstep: a soft, deep thump with a squelch.
audio/thog/fall.wav   - Thog crashing down: a long low rumble and a splash.

    python3 tools/gen_thog_sounds.py
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/thog/"


def lp(x, hz, order=3):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def env_adsr(t, a, d_end, total):
    e = np.clip(t / a, 0, 1)
    e *= np.clip((total - t) / max(total - d_end, 1e-3), 0, 1)
    return e


def write(name, x, stereo_spread=0.0, seed=0):
    rng = np.random.default_rng(seed)
    l = x
    r = np.roll(x, int(SR * 0.004)) if stereo_spread else x
    st = np.stack([l, r], axis=1)
    st /= np.max(np.abs(st)) + 1e-9
    st *= 0.9
    fade = int(SR * 0.03)
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    wavfile.write(OUT + name, SR, (st * 32767).astype(np.int16))
    print(name, f"{st.shape[0] / SR:.2f}s")


def roar():
    dur = 2.4
    rng = np.random.default_rng(1)
    t = np.arange(int(SR * dur)) / SR
    f0 = 62 + 30 * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5 + 4 * np.sin(2 * np.pi * 6.5 * t)   # pitch arc + vibrato
    ph = 2 * np.pi * np.cumsum(f0) / SR
    voice = np.zeros_like(t)
    for h in range(1, 28):   # a buzzy glottal pulse
        voice += np.sin(h * ph) / h ** 0.9
    rasp = rng.normal(0, 1, t.size) * (0.6 + 0.4 * np.sin(ph * 0.5))
    src = voice * 0.7 + rasp * 0.5
    # "OOAARRGH": formants sliding from an 'oo' to an open 'aa'
    k = np.clip(t / (dur * 0.5), 0, 1)
    out = bp(src, 260, 520) * (1 - k) + bp(src, 600, 1100) * k
    out += bp(src, 1900, 2800) * 0.35 + lp(src, 180) * 0.8
    out *= env_adsr(t, 0.18, dur * 0.6, dur)
    write("roar.wav", out, 1, 1)


def slam():
    dur = 1.6
    rng = np.random.default_rng(2)
    t = np.arange(int(SR * dur)) / SR
    f = 48 * np.exp(-t * 2.5) + 24
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.35)
    thud = lp(rng.normal(0, 1, t.size), 300) * np.exp(-t / 0.08) * 2.0
    splat = bp(rng.normal(0, 1, t.size), 400, 2500) * np.exp(-t / 0.12) * 0.7
    debris = np.zeros_like(t)
    for _ in range(26):
        t0 = rng.uniform(0.05, 0.9)
        tt = np.clip(t - t0, 0, None)
        debris += bp(rng.normal(0, 1, t.size), 800, 4000) * np.exp(-tt / 0.01) * (t >= t0) * rng.uniform(0.05, 0.2)
    write("slam.wav", boom * 1.4 + thud + splat + debris, 1, 2)


def sweep():
    dur = 1.1
    rng = np.random.default_rng(3)
    t = np.arange(int(SR * dur)) / SR
    n = rng.normal(0, 1, t.size)
    swell = np.exp(-((t - 0.45) / 0.16) ** 2)
    # band sweeping up then down: the club passing by
    lo = 150 + 500 * swell
    out = np.zeros_like(t)
    for k in range(6):
        s = slice(k * t.size // 6, (k + 1) * t.size // 6)
        c = float(np.mean(lo[s]))
        out[s] = bp(n, c, c * 3.0)[s]
    out *= swell
    tt = np.clip(t - 0.62, 0, None)
    out += lp(rng.normal(0, 1, t.size), 220) * np.exp(-tt / 0.07) * (t >= 0.62) * 1.2
    write("sweep.wav", out, 1, 3)


def step():
    dur = 0.6
    rng = np.random.default_rng(4)
    t = np.arange(int(SR * dur)) / SR
    boom = np.sin(2 * np.pi * np.cumsum(55 * np.exp(-t * 4) + 30) / SR) * np.exp(-t / 0.12)
    squelch = bp(rng.normal(0, 1, t.size), 300, 1200) * np.exp(-np.clip(t - 0.04, 0, None) / 0.06) * (t > 0.04) * 0.4
    write("step.wav", boom + squelch, 0, 4)


def fall():
    dur = 3.0
    rng = np.random.default_rng(5)
    t = np.arange(int(SR * dur)) / SR
    rumble = lp(rng.normal(0, 1, t.size), 90) * np.exp(-t / 0.9) * 3.0
    boom = np.sin(2 * np.pi * np.cumsum(40 * np.exp(-t * 1.5) + 22) / SR) * np.exp(-t / 0.6)
    splash = bp(rng.normal(0, 1, t.size), 500, 5000) * np.exp(-t / 0.35) * 0.6
    write("fall.wav", rumble + boom * 1.5 + splash, 1, 5)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    roar()
    slam()
    sweep()
    step()
    fall()
