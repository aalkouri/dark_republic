"""Synthesise the intro's sound effects (no samples).

  audio/intro/horn.wav    a low, rough goblin war horn: two swelling blasts with vibrato
  audio/intro/snore.wav   a cartoon snore: a nasal rumble in, a whistle out
  audio/intro/whoosh.wav  a quick airy whoosh (heroes dropping in)
  audio/intro/pop.wav     a squelchy flask pop with fizz (Dr. Croc's mishap)

    python3 tools/gen_intro_sounds.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
rng = np.random.default_rng(21)


def t_of(d):
    return np.arange(int(SR * d)) / SR


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, hi], "band", fs=SR, output="sos"), x)


def lp(x, hz, o=3):
    return sosfilt(butter(o, hz, "low", fs=SR, output="sos"), x)


def out(x, name, peak=0.9):
    x = np.tanh(x * 1.2)
    x /= np.max(np.abs(x)) / peak
    f = int(SR * 0.03)
    x[-f:] *= np.linspace(1, 0, f)
    wavfile.write("audio/intro/" + name, SR, (np.stack([x, x], 1) * 32767).astype(np.int16))


def horn():
    d = 3.2
    t = t_of(d)
    x = np.zeros_like(t)
    for start, dur, f0 in [(0.0, 1.1, 98.0), (1.25, 1.9, 92.5)]:
        tt = t_of(dur)
        f = f0 * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * tt)) * (1 + 0.03 * np.minimum(1, tt / 0.25))
        ph = 2 * np.pi * np.cumsum(f) / SR
        saw = sum(np.sin(ph * h) / h for h in range(1, 14))
        env = np.minimum(1, tt / 0.18) * np.minimum(1, (dur - tt) / 0.35)
        blast = lp(saw * env, 1400) + bp(rng.normal(0, 1, tt.size), 200, 900) * env * 0.08
        i = int(start * SR)
        x[i:i + tt.size] += blast[: max(0, min(tt.size, x.size - i))]
    out(x, "horn.wav")


def snore():
    d = 2.6
    t = t_of(d)
    inhale = (t < 1.3)
    rumble = lp(rng.normal(0, 1, t.size), 300) * (1 + 0.8 * np.sign(np.sin(2 * np.pi * 28 * t)))
    rumble *= np.where(inhale, np.sin(np.pi * np.clip(t / 1.3, 0, 1)), 0)
    whistle = np.sin(2 * np.pi * np.cumsum(900 - 300 * np.clip((t - 1.4) / 1.0, 0, 1)) / SR)
    whistle *= np.where(~inhale, np.sin(np.pi * np.clip((t - 1.35) / 1.15, 0, 1)), 0) * 0.35
    out(rumble * 0.9 + whistle, "snore.wav", 0.6)


def whoosh():
    d = 0.7
    t = t_of(d)
    n = rng.normal(0, 1, t.size)
    x = np.zeros_like(t)
    for k in range(6):
        a, b = int(t.size * k / 6), int(t.size * (k + 1) / 6)
        c = 3000 * (0.6 ** k) + 300
        x[a:b] = bp(n, c * 0.5, c * 1.5)[a:b]
    x *= np.sin(np.pi * t / d) ** 2
    out(x, "whoosh.wav", 0.6)


def pop():
    d = 0.9
    t = t_of(d)
    thump = np.sin(2 * np.pi * np.cumsum(180 * np.exp(-t / 0.05) + 60) / SR) * np.exp(-t * 18)
    fizz = bp(rng.normal(0, 1, t.size), 2500, 9000) * np.exp(-t * 4) * 0.4
    bubbles = np.zeros_like(t)
    for k in range(30):
        at = rng.uniform(0.05, 0.8)
        tt = t_of(0.03)
        b = np.sin(2 * np.pi * rng.uniform(600, 1500) * tt) * np.exp(-tt * 120)
        i = int(at * SR)
        bubbles[i:i + tt.size] += b[: max(0, min(tt.size, t.size - i))] * 0.3
    out(thump + fizz + bubbles, "pop.wav", 0.8)


for f in [horn, snore, whoosh, pop]:
    f()
print("wrote audio/intro/*.wav")
