"""Synthesise the Desert's sounds (no samples needed), with the little synth voices of
tools/gen_thog_kit_sounds.py:

audio/desert/zombie_groan_1..3.wav  a wet, rattling moan from a rotten throat (three pitches)
audio/desert/mummy_rasp_1..2.wav    a dry, dusty wheeze through bandages
audio/desert/mummy_curse.wav        a hollow whisper and a sinister shimmer (a mummy's touch)
audio/desert/mummy_crumble.wav      dry linen tearing and dust pouring away
audio/desert/vulture_screech_1..2   a harsh, hissing screech
audio/desert/vulture_flap.wav       two heavy wingbeats
audio/desert/vulture_peck.wav       a vulture's beak attack: a quick whoosh, a hard bony strike, a hiss
audio/desert/pharaoh_roar.wav       a huge, dry, echoing bellow from inside the gold mask
audio/desert/pharaoh_curse.wav      the curse beam: a rising choir-like drone and a crackling hiss
audio/desert/pharaoh_summon.wav     stone grinding, sand pouring, a low call
audio/desert/sandstorm.wav          a roaring, howling gust of sand
audio/desert/scarabs.wav            thousands of beetle legs and clicking shells rushing past
audio/desert/tomb_rumble.wav        the tomb slabs grinding apart over a deep rumble

    python3 tools/gen_desert_sounds.py
"""
import importlib.util
import os
import numpy as np

_spec = importlib.util.spec_from_file_location("g", os.path.join(os.path.dirname(__file__), "gen_thog_kit_sounds.py"))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
SR = g.SR
g.OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "desert") + os.sep
rng = np.random.default_rng(23)


def moan(d, f0, f1, formants, rasp=0.6, wobble=4.0):
    """A voiced moan gliding from f0 to f1 through vowel formants, with a rattle."""
    t = g.t_of(d)
    f = f0 + (f1 - f0) * (t / d) + np.sin(2 * np.pi * wobble * t) * f0 * 0.04
    ph = 2 * np.pi * np.cumsum(f) / SR
    src = np.sign(np.sin(ph)) * 0.5 + np.sin(ph) * 0.5
    src = src * (1 + rasp * (np.abs(np.sin(2 * np.pi * 27 * t)) - 0.5)) + rasp * 0.4 * g.noise(d)
    out = sum(g.bp(src, lo, hi) * w for (lo, hi, w) in formants)
    return out * g.env(t, 0.12, d * 0.45)


def wheeze(d, lo=600, hi=3000):
    """Dry breath through cloth: band noise in a slow swell, a little wobble."""
    t = g.t_of(d)
    n = g.bp(g.noise(d), lo, hi)
    return n * np.sin(np.pi * t / d) ** 1.5 * (1 + 0.3 * np.sin(2 * np.pi * 7 * t))


def screech(d, f0):
    """A harsh hissing screech: a noisy, buzzing tone that rises and cracks."""
    t = g.t_of(d)
    f = f0 * (1 + 0.35 * np.sin(np.pi * t / d)) + rng.normal(0, f0 * 0.03, t.size)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sign(np.sin(ph)) * 0.6 + np.sin(3 * ph) * 0.3
    hiss = g.hp(g.noise(d), 3000) * 0.5
    return g.bp(tone + hiss, 1200, 6000) * g.env(t, 0.03, d * 0.5)


def wingbeat(d):
    t = g.t_of(d)
    return g.lp(g.noise(d), 500) * np.exp(-t / 0.06) + g.boom(d, 70, 40, 0.06) * 0.4


def peck(d=0.5):
    """A beak lunging and striking: a short whoosh, a hard knock of bone with a woody ring, a
    rasping hiss after it."""
    t = g.t_of(d)
    swish = g.bp(g.noise(d), 700, 3500) * np.exp(-((t - 0.05) / 0.035) ** 2) * 0.5
    tt = np.clip(t - 0.08, 0, None)
    hit = (t >= 0.08)
    knock = (np.sin(2 * np.pi * 1650 * tt) * 0.6 + np.sin(2 * np.pi * 2900 * tt) * 0.3) * np.exp(-tt / 0.018) * hit
    thud = np.sin(2 * np.pi * (190 - 60 * np.clip(tt / 0.08, 0, 1)) * tt) * np.exp(-tt / 0.05) * hit * 0.7
    crack = g.hp(g.noise(d), 2500) * np.exp(-tt / 0.008) * hit * 0.6
    hiss = g.bp(g.noise(d), 2500, 7000) * np.exp(-np.clip(t - 0.14, 0, None) / 0.12) * (t >= 0.12) * 0.25
    return swish + knock + thud + crack + hiss


def grind(d, f0=55):
    """Stone dragging on stone: a rough, pulsing low rasp."""
    t = g.t_of(d)
    clicks = np.zeros_like(t)
    step = max(1, int(SR / f0))
    clicks[::step] = 1.0
    jitter = 1 + 0.6 * g.noise(d)
    return g.bp(clicks * jitter, 80, 900) * 1.5 + g.bp(g.noise(d), 150, 600) * 0.4


def pour(d):
    """Sand pouring: fine crackle over a soft hiss."""
    t = g.t_of(d)
    crackle = (rng.random(t.size) > 0.997).astype(float) * rng.uniform(0.3, 1.0, t.size)
    return g.hp(crackle, 2000) * 1.2 + g.bp(g.noise(d), 1500, 7000) * 0.25


def gale(d, lo=150, hi=1200):
    """Wind howling: band noise with its centre slowly wandering, a whistle on top."""
    t = g.t_of(d)
    n = g.noise(d)
    out = np.zeros_like(t)
    k = 10
    for s in range(k):
        sl = slice(s * t.size // k, (s + 1) * t.size // k)
        c = lo + (hi - lo) * (0.5 + 0.5 * np.sin(s * 1.7))
        out[sl] = g.bp(n, c, c * 2.2)[sl]
    whistle = np.sin(2 * np.pi * np.cumsum(900 + 200 * np.sin(2 * np.pi * 0.7 * t)) / SR) * 0.08
    return (out + whistle) * np.sin(np.pi * t / d) ** 0.8


def skitter(d, n=600, lo=2500, hi=7000):
    t = g.t_of(d)
    out = np.zeros_like(t)
    for _ in range(n):
        t0 = rng.uniform(0, d * 0.97)
        f = rng.uniform(lo, hi)
        tt = np.clip(t - t0, 0, None)
        out += np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.003) * (t >= t0) * rng.uniform(0.2, 1.0)
    return out


def at(x, d, start):
    return np.roll(g.fit(x, int(d * SR)), int(start * SR))


def main():
    vowels = [(250, 700, 1.0), (900, 1400, 0.6), (2200, 2800, 0.25)]
    for k, (f0, f1) in enumerate([(110, 85), (95, 70), (130, 100)]):
        d = 1.4 + 0.2 * k
        g.write("zombie_groan_%d" % (k + 1), g.mix(d, moan(d, f0, f1, vowels, 0.7), g.lp(g.noise(d), 400) * 0.08))
    for k in range(2):
        d = 1.1 + 0.3 * k
        g.write("mummy_rasp_%d" % (k + 1), g.mix(d, wheeze(d, 500 + k * 200, 2600) * 0.9, moan(d, 70, 60, [(200, 500, 0.6), (700, 1100, 0.3)], 0.9, 2.0) * 0.4))
    d = 1.2
    t = g.t_of(d)
    g.write("mummy_curse", g.mix(d, wheeze(d, 900, 4000) * 0.6, g.shimmer(d, 1800, 5200, 50) * 0.5, g.chime(d, [233, 277, 330], 0.6) * 0.35))
    d = 1.3
    t = g.t_of(d)
    tear = g.bp(g.noise(d), 1500, 6000) * (rng.random(t.size) > 0.6) * np.exp(-t / 0.35)
    g.write("mummy_crumble", g.mix(d, tear * 0.8, pour(d) * np.exp(-t / 0.6), g.boom(d, 90, 50, 0.15) * 0.4))
    for k, f0 in enumerate([1500, 1900]):
        d = 0.75 + 0.15 * k
        g.write("vulture_screech_%d" % (k + 1), screech(d, f0))
    d = 0.7
    g.write("vulture_flap", g.mix(d, wingbeat(0.25), at(wingbeat(0.25), d, 0.3)))
    g.write("vulture_peck", peck(0.5))
    # The Pharaoh
    d = 2.6
    t = g.t_of(d)
    roar = moan(d, 75, 48, [(150, 450, 1.0), (500, 900, 0.5), (1500, 2200, 0.15)], 1.0, 3.0)
    echo = np.roll(roar, int(0.18 * SR)) * 0.4 + np.roll(roar, int(0.37 * SR)) * 0.2
    g.write("pharaoh_roar", g.mix(d, roar, echo, g.boom(d, 50, 28, 0.6) * 0.5, pour(d) * 0.2))
    d = 1.6
    t = g.t_of(d)
    drone = sum(np.sin(2 * np.pi * np.cumsum(f * (1 + 0.6 * t / d)) / SR) * w for f, w in [(220, 0.5), (277, 0.4), (330, 0.35), (440, 0.2)])
    crack = g.hp(g.noise(d), 3000) * (rng.random(t.size) > 0.93) * 0.6
    g.write("pharaoh_curse", g.mix(d, drone * g.env(t, 0.5, 0.8), crack * np.clip(t / d * 2 - 0.5, 0, 1), g.shimmer(d, 2000, 6000, 60) * 0.3))
    d = 2.4
    t = g.t_of(d)
    g.write("pharaoh_summon", g.mix(d, grind(d, 40) * np.sin(np.pi * t / d), pour(d) * 0.6, moan(d, 60, 55, [(150, 400, 1.0), (500, 800, 0.4)], 0.8, 1.5) * 0.5))
    d = 3.0
    g.write("sandstorm", g.mix(d, gale(d) * 1.0, pour(d) * 0.5, g.lp(g.noise(d), 200) * np.sin(np.pi * g.t_of(d) / d) * 0.4))
    d = 1.4
    t = g.t_of(d)
    g.write("scarabs", g.mix(d, skitter(d) * np.sin(np.pi * t / d) ** 0.5 * 0.6, g.bp(g.noise(d), 3000, 8000) * 0.15 * np.sin(np.pi * t / d)))
    d = 3.4
    t = g.t_of(d)
    g.write("tomb_rumble", g.mix(d, grind(d, 32) * np.clip(t / 0.4, 0, 1) * np.exp(-np.clip(t - 1.6, 0, None) / 0.6), g.boom(d, 38, 22, 1.5) * 0.9, pour(d) * 0.5, at(g.boom(0.8, 60, 30, 0.3), d, 1.4) * 0.6))


if __name__ == "__main__":
    main()
