"""Synthesise the shield-break sound (no samples needed) into audio/ui/shield_break.wav:
a pane of magic glass shattering - a sharp crack, a burst of bright inharmonic glass shards
tinkling away, and a soft shimmer of the shield fading.

    python3 tools/gen_shield_sounds.py
"""
import numpy as np
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(23)
DUR = 1.1
n = int(SR * DUR)
t = np.arange(n) / SR
out = np.zeros((n, 2))


def shard(f, dur, decay):
    k = int(SR * dur)
    tt = np.arange(k) / SR
    s = np.zeros(k)
    for r, a in [(1.0, 1.0), (2.76, 0.5), (5.4, 0.3), (8.9, 0.15)]:
        s += a * np.sin(2 * np.pi * f * r * tt + rng.uniform(0, 6.28)) * np.exp(-decay * (1 + 0.5 * r) * tt)
    return s


def put(snd, at, gain, pan):
    i = int(SR * at)
    j = min(n, i + len(snd))
    out[i:j, 0] += snd[: j - i] * gain * np.sqrt(1 - pan)
    out[i:j, 1] += snd[: j - i] * gain * np.sqrt(pan)


# The crack: a short band of bright noise with a snap
k = int(SR * 0.05)
crack = rng.normal(0, 1, k) * np.exp(-np.arange(k) / SR * 90)
crack = np.diff(np.concatenate([[0], crack]))   # high-passed
put(crack, 0.0, 1.6, 0.5)
# Shards scattering: many short glassy pings, dense at first then thinning out
for _ in range(70):
    at = rng.exponential(0.12)
    if at > 0.8:
        continue
    put(shard(rng.uniform(2200, 6500), 0.25, rng.uniform(14, 30)), at, rng.uniform(0.15, 0.45) * np.exp(-at * 2.0), rng.uniform(0.1, 0.9))
# Shimmer of the shield fading (a soft descending sweep)
k = int(SR * 0.9)
tt = np.arange(k) / SR
f = 1800 * np.exp(-tt * 1.4)
shimmer = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 3.5) * 0.25
put(shimmer, 0.02, 1.0, 0.5)
out /= np.max(np.abs(out)) + 1e-9
out *= 0.85
wavfile.write("audio/ui/shield_break.wav", SR, (out * 32767).astype(np.int16))
print("audio/ui/shield_break.wav")
