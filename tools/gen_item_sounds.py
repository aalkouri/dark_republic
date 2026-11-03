"""Synthesise the item sounds (audio/items/).

mirror_dodge     Mirror Shard: an attack glances off. A bright glassy shimmer (inharmonic
                 pings sweeping upward) over a soft airy swish, no crack: the mirror holds.
coin_clink       Cursed Coin: a small coin drops. Two quick metal strikes, the second a
                 bounce, ringing with the slightly beating partials of a thin coin.
hourglass_turn   Hourglass: cooldowns cut. A low wooden knock as the glass flips, a soft
                 rising chime and a hiss of sand pouring.
item_drop        An item pops out of a burnt tree / crypt / statue: an airy upward whoosh
                 and a bright little sparkle.
item_found       Picking an item up (the "item found" card): a warm three-note arpeggio on a
                 bell with a shimmering tail.
crypt_open       A crypt door scraping open: stone grinding on stone, a low thud.
statue_crack     A statue cracking: sharp stone cracks and a patter of grit.
sink_rumble      The crypt / statue sinking into the earth: a long low rumble with grinding,
                 dirt trickling.

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


def lp(x, hz, o=2):
    return sosfilt(butter(o, hz, "low", fs=SR, output="sos"), x)


def item_drop(rng):
    buf = np.zeros(int(SR * 0.8))
    n = rng.standard_normal(int(SR * 0.45))
    t = t_of(0.45)
    env = np.sin(np.pi * np.minimum(t / 0.45, 1.0)) ** 2
    place(buf, bp(n, 800, 5000) * env * 0.4, 0.0)
    spark = [(1.0, 1.0, 1.0), (2.7, 0.4, 1.5), (5.1, 0.2, 2.2)]
    for k, f in enumerate([2400, 3200, 4300]):
        place(buf, modal(f, 0.4, 10.0, spark, 0.35), 0.18 + 0.05 * k)
    finish(buf, "item_drop", 0.6)


def item_found(rng):
    buf = np.zeros(int(SR * 1.6))
    bell = [(1.0, 1.0, 1.0), (2.0, 0.4, 1.4), (3.0, 0.22, 2.0), (4.2, 0.1, 2.8)]
    for k, f in enumerate([659.3, 830.6, 987.8, 1318.5]):
        place(buf, modal(f, 1.3, 3.0, bell, 0.5 if k < 3 else 0.6), 0.09 * k)
    sh = rng.standard_normal(int(SR * 1.2))
    env = np.linspace(0, 1, len(sh)) ** 0.5 * np.linspace(1, 0, len(sh)) ** 2
    place(buf, bp(sh, 6000, 14000) * env * 0.08, 0.25)
    finish(buf, "item_found", 0.75)


def crypt_open(rng):
    buf = np.zeros(int(SR * 1.4))
    n = rng.standard_normal(int(SR * 1.0))
    t = t_of(1.0)
    grind = bp(n, 150, 1400) * (0.6 + 0.4 * np.sin(2 * np.pi * 13 * t) ** 2)
    env = np.minimum(1.0, t / 0.1) * np.minimum(1.0, (1.0 - t) / 0.2)
    place(buf, grind * env * 0.6, 0.0)
    thud = lp(rng.standard_normal(int(SR * 0.3)), 180) * np.exp(-t_of(0.3) * 14) * 3.0
    place(buf, thud, 1.0)
    finish(buf, "crypt_open", 0.75)


def statue_crack(rng):
    buf = np.zeros(int(SR * 1.2))
    for k in range(5):
        c = rng.standard_normal(int(SR * 0.08)) * np.exp(-t_of(0.08) * 60)
        place(buf, bp(c, 600, 6000) * (1.0 - k * 0.12), 0.05 + k * rng.uniform(0.04, 0.12))
    grit = rng.standard_normal(int(SR * 0.8))
    gr = (rng.random(len(grit)) < 0.01) * grit * 4.0
    place(buf, bp(gr, 2000, 8000) * np.linspace(1, 0, len(grit)) * 0.3, 0.3)
    finish(buf, "statue_crack", 0.75)


def sink_rumble(rng):
    d = 2.9
    buf = np.zeros(int(SR * d))
    t = t_of(d)
    n = rng.standard_normal(len(t))
    env = np.minimum(1.0, t / 0.3) * np.minimum(1.0, (d - t) / 0.8)
    rum = lp(n, 90, 4) * 6.0 * (0.8 + 0.2 * np.sin(2 * np.pi * 3.1 * t))
    grind = bp(rng.standard_normal(len(t)), 200, 900) * 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t) ** 2)
    dirt = bp((rng.random(len(t)) < 0.004) * rng.standard_normal(len(t)) * 3.0, 1500, 7000) * 0.3
    buf += (rum + grind + dirt) * env
    finish(buf, "sink_rumble", 0.8)


if __name__ == "__main__":
    r = np.random.default_rng(7)
    mirror_dodge(r)
    coin_clink(r)
    hourglass_turn(r)
    item_drop(r)
    item_found(r)
    crypt_open(r)
    statue_crack(r)
    sink_rumble(r)
