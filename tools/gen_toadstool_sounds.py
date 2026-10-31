"""Synthesise the Toadstool Knight's sounds (no samples needed), using the same little synth voices
as tools/gen_thog_kit_sounds.py:

audio/abilities/spore_slash.wav    a bright sword swish with a soft puff of spores behind it
audio/abilities/fungal_shield.wav  a springy rubbery "boing" of the cap popping up, a low hum
audio/abilities/spore_burst.wav    a muffled pop and a hissing cloud of spores rushing out
audio/abilities/fairy_ring.wav     mushrooms popping up one after another round a sparkling chime
audio/abilities/fungus_court.wav   a deep rumble, earth heaving as the guardians rise, a fanfare-ish chord
audio/abilities/court_slam.wav     one guardian's heavy, squashy thud

    python3 tools/gen_toadstool_sounds.py
"""
import importlib.util
import os
import numpy as np

_spec = importlib.util.spec_from_file_location("g", os.path.join(os.path.dirname(__file__), "gen_thog_kit_sounds.py"))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
SR = g.SR


def at(x, secs, n):
    """Place clip `x` at `secs` in a buffer of `n` samples."""
    return np.roll(g.fit(x, n), int(secs * SR))


def puff(d, lo=500, hi=3000, decay=0.25):
    """A soft breathy puff (spores)."""
    t = g.t_of(d)
    return g.bp(g.noise(d), lo, hi) * g.env(t, 0.02, decay)


def pop(d, f0=700, f1=180, decay=0.07):
    """A little cork pop: a fast downward pitch blip."""
    t = g.t_of(d)
    f = f1 + (f0 - f1) * np.exp(-t * 40)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)


def boing(d, f0=180, depth=0.35, rate=9.0):
    """A springy wobbling tone (rubbery mushroom cap)."""
    t = g.t_of(d)
    f = f0 * (1 + depth * np.exp(-t * 5) * np.sin(2 * np.pi * rate * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + 0.35 * np.sin(2 * ph)) * np.exp(-t / (d * 0.4))


def main():
    # Spore Blade: swish + spore puff (short: it plays every swing)
    d = 0.45
    n = int(d * SR)
    swish = g.whoosh(0.3, 1800, 6500, 0.35) * 1.2
    ring = g.chime(0.3, [2600, 3900], 0.06) * 0.15
    g.write("spore_slash", g.mix(d, swish, ring, at(puff(0.3, 400, 2200, 0.12) * 0.5, 0.12, n)))
    # Fungal Shield: boing + hum + a sparkle
    d = 1.2
    n = int(d * SR)
    hum = np.sin(2 * np.pi * 110 * g.t_of(d)) * g.env(g.t_of(d), 0.15, 0.6) * 0.25
    g.write("fungal_shield", g.mix(d, boing(1.0, 190) * 0.9, hum, at(g.shimmer(0.6, 2500, 5500, 14) * 0.25, 0.1, n)))
    # Spore burst: pop + rushing hiss
    d = 1.1
    t = g.t_of(d)
    hiss = g.hp(g.noise(d), 1800) * g.env(t, 0.03, 0.35) * 0.6
    g.write("spore_burst", g.mix(d, pop(0.3, 300, 70, 0.12) * 1.2, g.boom(0.4, 90, 40, 0.12) * 0.6, hiss,
                                 puff(1.0, 300, 1500, 0.4) * 0.6))
    # Fairy Ring: a run of pops in a circle, over a sparkly chime
    d = 1.8
    n = int(d * SR)
    pops = sum(at(pop(0.12, 900 + 40 * k, 250, 0.04) * 0.5, 0.03 * k, n) for k in range(18))
    chimes = g.chime(d, [1320, 1760, 2093, 2637], 0.5, 0.15) * 0.35
    g.write("fairy_ring", g.mix(d, pops, chimes, at(g.shimmer(1.2, 3000, 7000, 30) * 0.3, 0.3, n)))
    # The Fungus Court: rumble, earth heaving, rising chord
    d = 3.0
    n = int(d * SR)
    t = g.t_of(d)
    rumble = g.lp(g.noise(d), 140) * g.env(t, 0.5, 1.2) * 1.4
    heaves = sum(at(g.boom(0.6, 70, 35, 0.25) * 0.7, 0.2 + 0.12 * k, n) for k in range(6))
    chord = sum(np.sin(2 * np.pi * f * t) for f in (196, 247, 294, 392)) * g.env(t, 0.9, 1.2) * 0.12
    g.write("fungus_court", g.mix(d, rumble, heaves, chord, at(g.chime(1.5, [784, 988, 1175], 0.5) * 0.25, 1.0, n)))
    # One guardian's slam
    d = 0.6
    g.write("court_slam", g.mix(d, g.boom(0.6, 80, 35, 0.18) * 1.2, boing(0.4, 95, 0.25, 12) * 0.4, puff(0.4, 200, 900, 0.1) * 0.5))


if __name__ == "__main__":
    main()
