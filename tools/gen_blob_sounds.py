"""Synthesise the Blob's ability sounds (no samples needed), using the same little synth voices
as tools/gen_thog_kit_sounds.py:

audio/abilities/engulf.wav        a wet slurp sucking inward, a big GULP, then muffled bubbling
audio/abilities/split.wav         two squelchy pops, one after the other (blip, bloop)
audio/abilities/great_puddle.wav  a big wet splat spreading out, bubbling, and a slurp back together

    python3 tools/gen_blob_sounds.py
"""
import importlib.util
import os
import numpy as np

_spec = importlib.util.spec_from_file_location("g", os.path.join(os.path.dirname(__file__), "gen_thog_kit_sounds.py"))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
SR = g.SR


def squelch(d, f0, f1, decay=0.12):
    """A wet, gloopy pitch glide (a pop of slime)."""
    t = g.t_of(d)
    f = f1 + (f0 - f1) * np.exp(-t * 18)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = (np.sin(ph) + 0.4 * np.sin(2 * ph + 0.3 * np.sin(ph))) * np.exp(-t / decay)
    wet = g.bp(g.noise(d), 300, 1800) * np.exp(-t / (decay * 0.6)) * 0.5
    return tone + wet


def slurp(d, lo=200, hi=1400):
    """Sucking in: a band of wet noise sweeping up, wobbling."""
    t = g.t_of(d)
    out = np.zeros_like(t)
    n = g.noise(d)
    for s in range(10):
        sl = slice(s * t.size // 10, (s + 1) * t.size // 10)
        c = lo + (hi - lo) * (s / 9.0)
        out[sl] = g.bp(n, c, c * 1.6)[sl]
    return out * (0.6 + 0.4 * np.sin(2 * np.pi * 14 * t)) * np.clip(t / 0.1, 0, 1) * np.clip((d - t) / 0.08, 0, 1)


def main():
    # Engulf: slurp in, GULP, muffled digesting bubbles
    d = 1.8
    slurp_in = slurp(0.45, 250, 1500) * 0.6
    gulp = np.roll(g.fit(squelch(0.5, 420, 70, 0.16) * 1.4 + g.boom(0.5, 90, 45, 0.15) * 0.8, int(d * SR)), int(0.42 * SR))
    gurgle = np.roll(g.fit(g.lp(g.bubbles(1.2, 26, 120, 420), 900) * 0.7, int(d * SR)), int(0.6 * SR))
    g.write("engulf", g.mix(d, slurp_in, gulp, gurgle))
    # Split: blip, bloop
    d = 1.0
    a = squelch(0.35, 900, 300, 0.09)
    b = np.roll(g.fit(squelch(0.4, 650, 180, 0.11), int(d * SR)), int(0.18 * SR))
    g.write("split", g.mix(d, a, b * 0.9, g.lp(g.bubbles(1.0, 10, 400, 900), 2000) * 0.25))
    # The Great Puddle: splat spreading out, bubbling, then slurped back together
    d = 3.4
    t = g.t_of(d)
    splat = g.fit(squelch(0.6, 300, 50, 0.22) * 1.3 + g.lp(g.noise(0.6), 1200) * np.exp(-g.t_of(0.6) / 0.12), int(d * SR))
    spread = g.lp(g.noise(d), 600) * np.exp(-t / 0.9) * 0.5
    bub = np.roll(g.fit(g.lp(g.bubbles(2.2, 60, 150, 600), 1500) * 0.55, int(d * SR)), int(0.3 * SR))
    back = np.roll(g.fit(slurp(0.6, 200, 1200) * 0.7 + np.roll(g.fit(squelch(0.4, 200, 600, 0.1), int(0.6 * SR)), int(0.35 * SR)), int(d * SR)), int(2.7 * SR))
    g.write("great_puddle", g.mix(d, splat, spread, bub, back))


if __name__ == "__main__":
    main()
