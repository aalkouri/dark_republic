"""Synthesise An Argyle Sock's ability sounds (no samples needed), using the same little synth
voices as tools/gen_thog_kit_sounds.py:

audio/abilities/spin_cycle.wav   a washing-machine whirr spinning up, with static crackle
audio/abilities/lost_pair.wav    a happy "pop!" and a two-note chime: found you!
audio/abilities/laundry_day.wav  a falling whistle, a heavy clunk, then sloshing suds

    python3 tools/gen_sock_sounds.py
"""
import importlib.util
import os
import numpy as np

_spec = importlib.util.spec_from_file_location("g", os.path.join(os.path.dirname(__file__), "gen_thog_kit_sounds.py"))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
SR = g.SR


def main():
    # Spin Cycle: a drum spinning up, a whoosh going round, crackles of static
    t = g.t_of(2.2)
    rate = 4 + 14 * np.clip(t / 1.2, 0, 1)
    ph = 2 * np.pi * np.cumsum(rate) / SR
    whirr = g.lp(g.noise(2.2), 900) * (0.55 + 0.45 * np.sin(ph)) * np.clip(t / 0.3, 0, 1) * np.clip((2.2 - t) / 0.4, 0, 1)
    hum = np.sin(2 * np.pi * np.cumsum(60 + 80 * np.clip(t / 1.2, 0, 1)) / SR) * 0.4 * np.clip(t / 0.4, 0, 1)
    crackle = g.hp(g.noise(2.2), 3000) * (g.rng.random(t.size) > 0.997) * 6.0
    g.write("spin_cycle", g.mix(2.2, whirr, hum, crackle))
    # Lost Pair: pop + rising two-note chime + sparkle
    pop = np.sin(2 * np.pi * np.cumsum(300 + 900 * np.exp(-g.t_of(1.2) * 30)) / SR) * np.exp(-g.t_of(1.2) / 0.05)
    g.write("lost_pair", g.mix(1.2, pop, g.chime(1.2, [784, 1175], 0.35, 0.08) * 0.7, g.shimmer(1.2, 2500, 6000, 18) * 0.25))
    # Laundry Day: falling whistle, clunk, then sloshing
    t = g.t_of(3.2)
    fall = np.sin(2 * np.pi * np.cumsum(1800 - 1300 * np.clip(t / 0.7, 0, 1)) / SR) * (t < 0.7) * 0.35
    clunk = np.roll(g.boom(3.2, 90, 40, 0.25) * 1.3 + g.clank(3.2, 420) * 0.6, int(0.7 * SR))
    slosh = np.roll(g.lp(g.noise(3.2), 700) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 2.5 * t))) * 0.6 + g.bubbles(3.2, 50, 200, 700) * 0.5, int(0.9 * SR))
    g.write("laundry_day", g.mix(3.2, fall, clunk, slosh))


if __name__ == "__main__":
    main()
