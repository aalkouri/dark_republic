"""Synthesise the item sounds (audio/items/).

mirror_dodge     Mirror Shard: an attack glances off. A bright glassy shimmer (inharmonic
                 pings sweeping upward) over a soft airy swish, no crack: the mirror holds.
coin_clink       Cursed Coin: a small coin drops. Two quick metal strikes, the second a
                 bounce, ringing with the slightly beating partials of a thin coin.
hourglass_turn   Hourglass: cooldowns cut. A low wooden knock as the glass flips, a soft
                 rising chime and a hiss of sand pouring.

    python3 tools/gen_item_sounds.py
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/items/"


def t_of(d):
    return np.arange(int(SR * d)) / SR


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, min(hi, SR / 2 - 100)], "band", fs=SR, output="sos"), x)


def place(buf, snd, at):
    i = int(at * SR)
    n = min(len(snd), len(buf) - i)
    if n > 0:
        buf[i:i + n] += snd[:n]


def modal(f, d, decay, partials, amp=1.0):
    t = t_of(d)
    x = np.zeros_like(t)
    for r, a, dm in partials:
        x += a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * decay * dm)
    att = np.minimum(1.0, t / 0.002)
    return x * att * amp


def finish(x, name, peak=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(SR * 0.02)
    x[-fade:] *= np.linspace(1, 0, fade)
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(OUT + name + ".wav", SR, (x * 32767).astype(np.int16))


def mirror_dodge(rng):
    buf = np.zeros(int(SR * 0.9))
    glass = [(1.0, 1.0, 1.0), (2.76, 0.55, 1.4), (5.4, 0.3, 2.0), (8.9, 0.15, 3.0)]
    for k, f in enumerate([1900, 2350, 2900, 3500]):
        place(buf, modal(f * rng.uniform(0.98, 1.02), 0.7, 7.0, glass, 0.6 - k * 0.08), 0.03 * k)
    swish = rng.standard_normal(int(SR * 0.25))
    env = np.sin(np.linspace(0, np.pi, len(swish))) ** 2
    place(buf, bp(swish, 3000, 9000) * env * 0.35, 0.0)
    finish(buf, "mirror_dodge", 0.7)


def coin_clink(rng):
    buf = np.zeros(int(SR * 0.6))
    coin = [(1.0, 1.0, 1.0), (1.007, 0.8, 1.0), (2.41, 0.45, 1.6), (3.9, 0.25, 2.4)]
    place(buf, modal(3100, 0.55, 9.0, coin), 0.0)
    place(buf, modal(3150, 0.4, 12.0, coin, 0.45), 0.09)
    click = rng.standard_normal(200) * np.exp(-np.arange(200) / 30.0)
    place(buf, bp(click, 4000, 12000) * 0.5, 0.0)
    finish(buf, "coin_clink", 0.6)


def hourglass_turn(rng):
    buf = np.zeros(int(SR * 1.3))
    wood = [(1.0, 1.0, 1.0), (2.6, 0.4, 2.5)]
    place(buf, modal(210, 0.25, 25.0, wood), 0.0)
    bell = [(1.0, 1.0, 1.0), (2.0, 0.35, 1.5), (3.01, 0.2, 2.0)]
    for k, f in enumerate([880, 1175, 1568]):
        place(buf, modal(f, 0.9, 4.5, bell, 0.35), 0.12 + 0.09 * k)
    sand = rng.standard_normal(int(SR * 0.9))
    env = np.minimum(1.0, np.linspace(0, 4, len(sand))) * np.linspace(1, 0, len(sand)) ** 1.5
    grains = (rng.random(len(sand)) < 0.02) * rng.standard_normal(len(sand)) * 3.0
    place(buf, bp(sand * 0.3 + grains, 2500, 8000) * env * 0.25, 0.15)
    finish(buf, "hourglass_turn", 0.7)


if __name__ == "__main__":
    r = np.random.default_rng(7)
    mirror_dodge(r)
    coin_clink(r)
    hourglass_turn(r)
