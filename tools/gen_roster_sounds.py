"""Synthesise the roster wizards' ability sounds (no samples needed).

audio/abilities/
  freeze.wav       Flash Freeze: a glassy crack and a crystalline shimmer settling
  glacial.wav      Glacial Path: a skating whoosh with an icy sparkle
  blizzard.wav     Absolute Zero: 8 s of howling wind with whistling gusts
  shatter.wav      a frozen goblin bursting: a short bright tinkle of ice
  overcharge.wav   Overcharge: a rising electric whine and crackle
  zap.wav          a short electric snap (shocks, chain strikes)
  thunderclap.wav  Thunderclap: a sharp crack and a rolling boom
  storm.wav        Storm Lord: 10 s of rumbling thunder and rain hiss
  siphon.wav       Siphon: a low breathy drone pulling inward
  raise_dead.wav   Raise Dead: a deep groan, earth crumbling, a ghostly choir swell
  eclipse.wav      Eclipse: a falling sub boom into a dark shimmering pad

    python3 tools/gen_roster_sounds.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/abilities/"


def t_of(dur):
    return np.arange(int(SR * dur)) / SR


def lp(x, hz, order=4):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def hp(x, hz, order=4):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def env(t, attack, decay):
    return (1 - np.exp(-t / max(attack, 1e-4))) * np.exp(-t / decay)


def fade(x, fin=0.01, fout=0.2):
    n = len(x)
    a = int(SR * fin)
    b = int(SR * fout)
    x = x.copy()
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def save(name, l, r=None, gain=0.85):
    if r is None:
        r = l
    st = np.stack([l, r], 1)
    st = st / (np.max(np.abs(st)) + 1e-9) * gain
    wavfile.write(OUT + name + ".wav", SR, (st * 32767).astype(np.int16))
    print("wrote", OUT + name + ".wav", f"{len(l) / SR:.2f}s")


def chimes(t, rng, n, lo, hi, spread, decay):
    x = np.zeros_like(t)
    for _ in range(n):
        f = rng.uniform(lo, hi)
        t0 = rng.uniform(0, spread)
        tt = np.clip(t - t0, 0, None)
        x += np.sin(2 * np.pi * f * tt) * np.exp(-tt / decay) * (t >= t0) * rng.uniform(0.3, 1)
    return x


def freeze():
    t = t_of(1.8)
    out = []
    for seed in (1, 2):
        rng = np.random.default_rng(seed)
        crack = bp(rng.normal(0, 1, t.size), 2000, 9000) * env(t, 0.001, 0.03) * 2.5
        thump = np.sin(2 * np.pi * np.cumsum(70 + 80 * np.exp(-t / 0.05)) / SR) * env(t, 0.002, 0.18)
        shimmer = chimes(t, rng, 40, 2500, 7000, 0.6, 0.35) * 0.25
        hiss = hp(rng.normal(0, 1, t.size), 6000) * env(t, 0.01, 0.5) * 0.25
        out.append(fade(crack + thump + shimmer + hiss))
    save("freeze", *out)


def glacial():
    t = t_of(1.4)
    out = []
    for seed in (3, 4):
        rng = np.random.default_rng(seed)
        sweep = np.exp(-((t - 0.35) / 0.25) ** 2)
        noise = rng.normal(0, 1, t.size)
        whoosh = bp(noise, 600, 3500) * sweep * 1.2
        scrape = bp(noise, 3000, 8000) * (0.4 + 0.6 * np.sin(2 * np.pi * 9 * t) ** 2) * np.exp(-t / 0.6) * 0.5
        sparkle = chimes(t, rng, 18, 3000, 8000, 0.9, 0.18) * 0.2
        out.append(fade(whoosh + scrape + sparkle, 0.02, 0.3))
    save("glacial", *out)


def blizzard():
    t = t_of(8.5)
    out = []
    for seed in (5, 6):
        rng = np.random.default_rng(seed)
        noise = rng.normal(0, 1, t.size)
        gust = 0.55 + 0.45 * np.sin(2 * np.pi * 0.23 * t + seed) * np.sin(2 * np.pi * 0.61 * t)
        wind = lp(noise, 900) * gust * 1.6 + bp(noise, 900, 2600) * gust ** 2 * 0.6
        whistle_f = 700 + 260 * np.sin(2 * np.pi * 0.17 * t + seed)
        whistle = np.sin(2 * np.pi * np.cumsum(whistle_f) / SR) * gust ** 3 * 0.18
        swell = np.clip(t / 0.6, 0, 1) * np.clip((8.5 - t) / 1.2, 0, 1)
        out.append((wind + whistle) * swell)
    save("blizzard", *out, gain=0.7)


def shatter():
    t = t_of(0.7)
    out = []
    for seed in (7, 8):
        rng = np.random.default_rng(seed)
        crack = bp(rng.normal(0, 1, t.size), 3000, 10000) * env(t, 0.0005, 0.02) * 2
        tinkle = chimes(t, rng, 22, 3000, 9000, 0.15, 0.12) * 0.5
        out.append(fade(crack + tinkle, 0.0, 0.1))
    save("shatter", *out)


def overcharge():
    t = t_of(1.6)
    out = []
    for seed in (9, 10):
        rng = np.random.default_rng(seed)
        f = 120 + 900 * (t / 1.6) ** 1.5
        whine = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.25 * np.clip(t / 0.3, 0, 1)
        whine = lp(whine, 4000)
        crackle = np.zeros_like(t)
        for _ in range(90):
            t0 = rng.uniform(0, 1.5)
            tt = np.clip(t - t0, 0, None)
            crackle += rng.normal(0, 1, t.size) * np.exp(-tt / 0.004) * (t >= t0) * rng.uniform(0.3, 1)
        crackle = hp(crackle, 1500) * 0.6
        out.append(fade(whine + crackle, 0.01, 0.35))
    save("overcharge", *out)


def zap():
    t = t_of(0.35)
    out = []
    for seed in (11, 12):
        rng = np.random.default_rng(seed)
        buzz = np.sign(np.sin(2 * np.pi * (220 + rng.uniform(-20, 20)) * t)) * env(t, 0.001, 0.08) * 0.5
        snap = hp(rng.normal(0, 1, t.size), 2000) * env(t, 0.0005, 0.03) * 1.5
        out.append(fade(lp(buzz, 5000) + snap, 0.0, 0.08))
    save("zap", *out)


def thunderclap():
    t = t_of(3.2)
    out = []
    for seed in (13, 14):
        rng = np.random.default_rng(seed)
        noise = rng.normal(0, 1, t.size)
        crack = hp(noise, 1200) * env(t, 0.0008, 0.06) * 2.5
        boom = lp(noise, 160) * env(t, 0.02, 0.9) * 6
        roll_env = np.exp(-t / 1.4) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 1.7 * t + seed)))
        roll = lp(rng.normal(0, 1, t.size), 320) * roll_env * 4
        out.append(fade(crack + boom + roll, 0.0, 0.5))
    save("thunderclap", *out)


def storm():
    t = t_of(10.5)
    out = []
    for seed in (15, 16):
        rng = np.random.default_rng(seed)
        rain = hp(rng.normal(0, 1, t.size), 3500) * 0.12
        rumble = lp(rng.normal(0, 1, t.size), 120) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.3 * t + seed)) * 2.5
        cracks = np.zeros_like(t)
        r2 = np.random.default_rng(99)   # same strike times on both channels
        for _ in range(14):
            t0 = r2.uniform(0.2, 9.5)
            tt = np.clip(t - t0, 0, None)
            on = t >= t0
            cracks += hp(rng.normal(0, 1, t.size), 1500) * np.exp(-tt / 0.05) * on * 1.4
            cracks += lp(rng.normal(0, 1, t.size), 200) * np.exp(-tt / 0.7) * on * 3
        swell = np.clip(t / 0.5, 0, 1) * np.clip((10.5 - t) / 1.5, 0, 1)
        out.append((rain + rumble + cracks) * swell)
    save("storm", *out, gain=0.8)


def siphon():
    t = t_of(4.2)
    out = []
    for seed in (17, 18):
        rng = np.random.default_rng(seed)
        drone = sum(np.sin(2 * np.pi * f * t + seed) / (k + 1) for k, f in enumerate([55, 82.5, 110, 165]))
        drone *= 0.5 + 0.5 * np.sin(2 * np.pi * 2.2 * t) ** 2
        breath = bp(rng.normal(0, 1, t.size), 300, 1800) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.9 * t)) * 0.8
        f = 900 - 500 * (t / 4.2)
        suck = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.12
        swell = np.clip(t / 0.3, 0, 1) * np.clip((4.2 - t) / 0.6, 0, 1)
        out.append((drone * 0.6 + breath + suck) * swell)
    save("siphon", *out)


def raise_dead():
    t = t_of(2.8)
    out = []
    for seed in (19, 20):
        rng = np.random.default_rng(seed)
        groan_f = 70 + 25 * np.sin(2 * np.pi * 1.3 * t) - 15 * t
        groan = lp(np.sign(np.sin(2 * np.pi * np.cumsum(groan_f) / SR)), 600) * env(t, 0.2, 1.2) * 0.6
        earth = lp(rng.normal(0, 1, t.size), 500) * env(t, 0.05, 0.8) * 1.5
        pebbles = np.zeros_like(t)
        for _ in range(60):
            t0 = rng.uniform(0.05, 1.5)
            tt = np.clip(t - t0, 0, None)
            pebbles += bp(rng.normal(0, 1, t.size), 800, 3000) * np.exp(-tt / 0.01) * (t >= t0) * rng.uniform(0.2, 0.7)
        choir = sum(np.sin(2 * np.pi * f * t) for f in [220, 261.6, 311.1]) * np.clip((t - 0.6) / 1.2, 0, 1) * np.exp(-np.clip(t - 1.8, 0, None) / 0.6) * 0.15
        out.append(fade(groan + earth + pebbles * 0.6 + choir, 0.01, 0.4))
    save("raise_dead", *out)


def eclipse():
    t = t_of(3.5)
    out = []
    for seed in (21, 22):
        rng = np.random.default_rng(seed)
        f = 90 * np.exp(-t / 0.9) + 28
        boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.01, 1.3)
        whoosh = lp(rng.normal(0, 1, t.size), 700) * env(t, 0.3, 0.7) * 1.2
        pad = sum(np.sin(2 * np.pi * fr * t + seed) for fr in [110, 116.5, 164.8]) * np.clip((t - 0.4) / 1.0, 0, 1) * np.exp(-np.clip(t - 2.0, 0, None) / 0.7) * 0.18
        shimmer = chimes(t, rng, 12, 1200, 2600, 2.0, 0.6) * 0.08
        out.append(fade(boom + whoosh + pad + shimmer, 0.0, 0.4))
    save("eclipse", *out)


if __name__ == "__main__":
    for f in (freeze, glacial, blizzard, shatter, overcharge, zap, thunderclap, storm, siphon, raise_dead, eclipse):
        f()
