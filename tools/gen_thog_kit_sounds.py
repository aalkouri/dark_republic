"""Synthesise Thog's ability sounds (no samples needed): the toll booth's clank and coins,
the goat charge's hoofbeats and snort, and the bridge's whoosh and stone crash.

    python3 tools/gen_thog_kit_sounds.py
"""

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/abilities/"
rng = np.random.default_rng(7)


def t_of(d):
    return np.arange(int(SR * d)) / SR


def lp(x, hz, o=3):
    return sosfilt(butter(o, hz, "low", fs=SR, output="sos"), x)


def hp(x, hz, o=3):
    return sosfilt(butter(o, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, hi], "band", fs=SR, output="sos"), x)


def env(t, a, d):
    return np.clip(t / a, 0, 1) * np.exp(-np.clip(t - a, 0, None) / d)


def fit(x, n):
    y = np.zeros(n)
    m = min(n, x.size)
    y[:m] = x[:m]
    return y


def mix(dur, *parts):
    n = int(SR * dur)
    return sum(fit(p, n) for p in parts)


def noise(d):
    return rng.normal(0, 1, int(SR * d))


def whoosh(d, lo, hi, peak=0.5):
    t = t_of(d)
    n = noise(d)
    k = np.exp(-((t / d - peak) / 0.22) ** 2)
    out = np.zeros_like(t)
    for s in range(8):   # sweep the band up through the swell
        sl = slice(s * t.size // 8, (s + 1) * t.size // 8)
        c = lo + (hi - lo) * (s / 7.0)
        out[sl] = bp(n, c, c * 2.2)[sl]
    return out * k


def boom(d, f0=60, f1=30, decay=0.35):
    t = t_of(d)
    f = f1 + (f0 - f1) * np.exp(-t * 4)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay) + lp(noise(d), 250) * np.exp(-t / 0.08)


def chime(d, freqs, decay=0.6, start=0.0):
    t = t_of(d)
    out = np.zeros_like(t)
    for k, f in enumerate(freqs):
        t0 = start + k * 0.06
        tt = np.clip(t - t0, 0, None)
        out += np.sin(2 * np.pi * f * tt) * np.exp(-tt / decay) * (t >= t0)
    return out


def shimmer(d, lo=2000, hi=6000, n=40):
    t = t_of(d)
    out = np.zeros_like(t)
    for _ in range(n):
        f = rng.uniform(lo, hi)
        t0 = rng.uniform(0, d * 0.8)
        tt = np.clip(t - t0, 0, None)
        out += np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.08) * (t >= t0) * rng.uniform(0.2, 0.6)
    return out


def growl(d, f0=90, formant=(300, 700), rasp=0.5):
    t = t_of(d)
    f = f0 * (1 + 0.15 * np.sin(np.pi * t / d)) + 3 * np.sin(2 * np.pi * 7 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    v = sum(np.sin(h * ph) / h for h in range(1, 20))
    src = v + rasp * noise(d)
    return bp(src, *formant) * env(t, 0.08, d * 0.5)


def bubbles(d, n=30, lo=300, hi=900):
    t = t_of(d)
    out = np.zeros_like(t)
    for _ in range(n):
        t0 = rng.uniform(0, d * 0.85)
        f = rng.uniform(lo, hi)
        tt = np.clip(t - t0, 0, None)
        out += np.sin(2 * np.pi * (f + 900 * tt) * tt) * np.exp(-tt / 0.04) * (t >= t0)
    return out


def clank(d, f=900):
    t = t_of(d)
    return (np.sin(2 * np.pi * f * t) + 0.6 * np.sin(2 * np.pi * f * 2.76 * t) + 0.3 * np.sin(2 * np.pi * f * 5.4 * t)) * np.exp(-t / 0.12)


def write(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.88
    fade = int(SR * 0.03)
    x[-fade:] *= np.linspace(1, 0, fade)
    st = np.stack([x, np.roll(x, int(SR * 0.003))], axis=1)
    wavfile.write(OUT + name + ".wav", SR, (st * 32767).astype(np.int16))
    print(name, f"{x.size / SR:.2f}s")


def main():
    write("toll_booth", mix(1.0, clank(1.0, 700) * 0.8, chime(1.0, [1318, 1568, 2093], 0.25, 0.1) * 0.6))
    t = t_of(1.2)
    gallop = np.zeros_like(t)
    for k in range(6):
        gallop += np.roll(boom(1.2, 80, 40, 0.06) * 0.6, int(k * 0.12 * SR))[:t.size]
    write("goat_charge", mix(1.2, gallop, growl(1.2, 85, (200, 600), 0.6) * 0.6))
    t = t_of(2.6)
    crash = np.roll(boom(2.6, 55, 22, 0.9) * 1.5 + bp(noise(2.6), 200, 3000) * np.exp(-t_of(2.6) / 0.4), int(0.6 * SR))
    write("bridge_collapse", mix(2.6, whoosh(2.6, 100, 400, 0.18) * 0.6, crash))



if __name__ == "__main__":
    main()
