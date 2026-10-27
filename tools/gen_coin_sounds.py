"""Synthesise the coin sounds (no samples needed).

jingle_loop.wav - a seamless casino-payout loop: a dense shower of metallic coin clinks
                  (inharmonic partials, fast decay), random stereo spread, a little bell
                  shimmer on top.
coin_done.wav   - a bright two-note "ka-ching" for when the count finishes.

    python3 tools/gen_coin_sounds.py
"""
import numpy as np
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(7)


def clink(dur=0.18, base=None, bright=1.0):
    t = np.arange(int(SR * dur)) / SR
    base = base or rng.uniform(2300, 3400)
    # Inharmonic partials of a small struck disc
    ratios = [1.0, 1.59, 2.14, 2.65, 3.16, 3.65]
    out = np.zeros_like(t)
    for k, r in enumerate(ratios):
        f = base * r * rng.uniform(0.99, 1.01)
        amp = (0.9 ** k) * rng.uniform(0.6, 1.0) * (bright if k > 2 else 1.0)
        decay = rng.uniform(18, 35) * (1 + 0.35 * k)
        out += amp * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-decay * t)
    # Tiny noisy strike transient
    n = int(SR * 0.004)
    out[:n] += rng.normal(0, 0.5, n) * np.linspace(1, 0, n)
    return out / np.max(np.abs(out))


def place(buf, snd, at, gain, pan, wrap=True):
    n = len(snd)
    idx = (np.arange(n) + at)
    if wrap:
        idx %= len(buf)
    else:
        keep = idx < len(buf)
        idx, snd = idx[keep], snd[keep]
    buf[idx, 0] += snd * gain * np.sqrt(1 - pan)
    buf[idx, 1] += snd * gain * np.sqrt(pan)


def jingle_loop(seconds=2.0, rate=34):
    n = int(SR * seconds)
    buf = np.zeros((n, 2))
    count = int(seconds * rate)
    for _ in range(count):
        at = rng.integers(0, n)
        place(buf, clink(), at, rng.uniform(0.25, 0.7), rng.uniform(0.15, 0.85))
    # Clusters (coins hitting coins) for a fuller pile sound
    for _ in range(int(seconds * 6)):
        at = rng.integers(0, n)
        for j in range(rng.integers(2, 5)):
            place(buf, clink(0.12), at + int(SR * 0.012 * j), rng.uniform(0.15, 0.35), rng.uniform(0.2, 0.8))
    # Shimmer: soft high bell tones
    t = np.arange(int(SR * 0.6)) / SR
    for _ in range(int(seconds * 2)):
        f = rng.choice([1568.0, 1760.0, 2093.0, 2637.0])
        bell = np.sin(2 * np.pi * f * t) * np.exp(-6 * t) + 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-9 * t)
        place(buf, bell, rng.integers(0, n), 0.12, rng.uniform(0.3, 0.7))
    return buf


def ka_ching():
    n = int(SR * 1.2)
    buf = np.zeros((n, 2))
    t = np.arange(n) / SR
    for k, (f, start) in enumerate([(1318.5, 0.0), (1975.5, 0.09)]):
        s = int(SR * start)
        tt = t[: n - s]
        tone = (np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 2 * tt) + 0.25 * np.sin(2 * np.pi * f * 3.01 * tt)) * np.exp(-3.5 * tt)
        place(buf, tone, s, 0.5, 0.5, wrap=False)
    for j in range(10):
        place(buf, clink(0.25, bright=1.3), int(SR * rng.uniform(0, 0.2)), 0.35, rng.uniform(0.2, 0.8), wrap=False)
    return buf


def save(path, buf, peak=0.85):
    buf = buf / np.max(np.abs(buf)) * peak
    wavfile.write(path, SR, (buf * 32767).astype(np.int16))


save("audio/coins/jingle_loop.wav", jingle_loop())
save("audio/coins/coin_done.wav", ka_ching())
print("ok")
