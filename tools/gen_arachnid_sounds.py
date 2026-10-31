"""Synthesise the Arachnid's sounds (no samples needed), using the same little synth voices
as tools/gen_thog_kit_sounds.py:

audio/abilities/venom_spit.wav  a short wet "ptoo": a hiss of breath and a gloopy pop
audio/abilities/web_trap.wav    a stringy twang as the web shoots out, then a sticky splat
                                and the threads stretching taut
audio/abilities/brood.wav       an egg sac squelching open, then a rush of tiny skittering legs
audio/abilities/cocoon.wav      silk whipping round and round (rising whirrs), then a tight
                                creak as everything is wrapped

    python3 tools/gen_arachnid_sounds.py
"""
import importlib.util
import os
import numpy as np

_spec = importlib.util.spec_from_file_location("g", os.path.join(os.path.dirname(__file__), "gen_thog_kit_sounds.py"))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
SR = g.SR


def pop(d, f0, f1, decay=0.08):
    """A wet, gloopy pitch drop."""
    t = g.t_of(d)
    f = f1 + (f0 - f1) * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + 0.3 * np.sin(2 * ph)) * np.exp(-t / decay)


def twang(d, f0, decay=0.35):
    """A plucked, stretchy thread: a string tone bending down, with a buzz."""
    t = g.t_of(d)
    f = f0 * (1 + 0.5 * np.exp(-t * 12))
    ph = 2 * np.pi * np.cumsum(f) / SR
    v = sum(np.sin(h * ph) * (0.7 ** h) for h in range(1, 8))
    return v * np.exp(-t / decay)


def skitter(d, n=120, lo=2500, hi=6500):
    """Lots of tiny legs tapping: very short clicks scattered in time."""
    t = g.t_of(d)
    out = np.zeros_like(t)
    rng = np.random.default_rng(11)
    for _ in range(n):
        t0 = rng.uniform(0, d * 0.95)
        f = rng.uniform(lo, hi)
        tt = np.clip(t - t0, 0, None)
        out += np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.004) * (t >= t0) * rng.uniform(0.3, 1.0)
    return out


def whirr(d, lo, hi):
    """Silk whipping past: a noise band sweeping up."""
    t = g.t_of(d)
    out = np.zeros_like(t)
    n = g.noise(d)
    for s in range(6):
        sl = slice(s * t.size // 6, (s + 1) * t.size // 6)
        c = lo + (hi - lo) * (s / 5.0)
        out[sl] = g.bp(n, c, c * 1.5)[sl]
    return out * np.sin(np.pi * t / d) ** 2


def creak(d, f0=140):
    """Silk pulled tight: a slow rasping creak."""
    t = g.t_of(d)
    clicks = np.zeros_like(t)
    step = int(SR / f0)
    clicks[::step] = 1.0
    return g.bp(clicks * (1 + 0.5 * g.noise(d)), 400, 2400) * np.sin(np.pi * t / d)


def main():
    # Venom Spit: breathy hiss into a gloopy pop
    d = 0.32
    t = g.t_of(d)
    hiss = g.hp(g.noise(d), 2500) * np.exp(-t / 0.05) * 0.5
    blob = np.roll(g.fit(pop(0.25, 900, 260, 0.06), int(d * SR)), int(0.025 * SR))
    wet = g.bp(g.noise(d), 500, 2000) * np.exp(-t / 0.04) * 0.35
    g.write("venom_spit", g.mix(d, hiss, blob, wet))
    # Web Trap: twang, sticky splat, threads stretching
    d = 1.4
    t = g.t_of(d)
    shot = g.whoosh(0.35, 800, 3000, 0.6) * 0.5
    tw = twang(1.0, 220, 0.4) * 0.6
    splat = np.roll(g.fit(pop(0.4, 400, 90, 0.12) + g.lp(g.noise(0.4), 1500) * np.exp(-g.t_of(0.4) / 0.06), int(d * SR)), int(0.33 * SR))
    stretch = np.roll(g.fit(twang(0.9, 330, 0.3) * 0.3 + twang(0.9, 440, 0.25) * 0.25, int(d * SR)), int(0.42 * SR))
    g.write("web_trap", g.mix(d, shot, tw, splat, stretch))
    # Brood: the sac squelches open, then a rush of little legs
    d = 2.0
    sac = g.fit(pop(0.5, 300, 60, 0.15) * 1.2 + g.bp(g.noise(0.5), 300, 1500) * np.exp(-g.t_of(0.5) / 0.1) * 0.6, int(d * SR))
    sac2 = np.roll(g.fit(pop(0.3, 500, 120, 0.08), int(d * SR)), int(0.15 * SR))
    legs = np.roll(g.fit(skitter(1.6, 260) * 0.45 * np.linspace(1, 0.3, int(1.6 * SR)), int(d * SR)), int(0.3 * SR))
    g.write("brood", g.mix(d, sac, sac2 * 0.8, legs))
    # Cocoon: silk whips round three times, faster and higher, then creaks tight
    d = 2.2
    w1 = g.fit(whirr(0.45, 500, 1500), int(d * SR))
    w2 = np.roll(g.fit(whirr(0.4, 700, 2200), int(d * SR)), int(0.35 * SR))
    w3 = np.roll(g.fit(whirr(0.35, 900, 3000), int(d * SR)), int(0.65 * SR))
    tight = np.roll(g.fit(creak(1.0, 120) * 0.8 + twang(1.0, 160, 0.5) * 0.3, int(d * SR)), int(1.0 * SR))
    thump = np.roll(g.fit(g.boom(0.6, 90, 40, 0.18) * 0.6, int(d * SR)), int(0.95 * SR))
    g.write("cocoon", g.mix(d, w1, w2, w3, tight, thump))


if __name__ == "__main__":
    main()
