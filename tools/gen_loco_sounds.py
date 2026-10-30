"""Synthesise Loco Robotico's sounds (no samples needed), using the same little synth voices as
tools/gen_thog_kit_sounds.py:

audio/abilities/maraca_shake.wav   one shake of a maraca: a short burst of rattling seeds
audio/abilities/party_mode.wav     a robot "beep-boop", then a disco beat and a party whistle
audio/abilities/pinata_drop.wav    a launch whoop, a party horn, then a candy burst of pops
audio/abilities/destroy_mode.wav   servos powering up into a deep alarm and a laser hum

    python3 tools/gen_loco_sounds.py
"""
import importlib.util
import os
import numpy as np

_spec = importlib.util.spec_from_file_location("g", os.path.join(os.path.dirname(__file__), "gen_thog_kit_sounds.py"))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
SR = g.SR


def tone(d, f, kind="sine"):
    t = g.t_of(d)
    ph = 2 * np.pi * np.cumsum(np.broadcast_to(f, t.shape)) / SR
    if kind == "square":
        return np.sign(np.sin(ph)) * 0.5
    if kind == "saw":
        return (ph / (2 * np.pi)) % 1.0 * 2 - 1
    return np.sin(ph)


def at(x, secs, total):
    n = int(total * SR)
    y = np.zeros(n)
    s = int(secs * SR)
    m = min(n - s, x.size)
    if m > 0:
        y[s:s + m] = x[:m]
    return y


def shaker(d=0.16):
    t = g.t_of(d)
    grains = g.hp(g.noise(d), 4500) * (g.rng.random(t.size) > 0.6)
    return g.bp(grains, 5000, 11000) * g.env(t, 0.012, 0.05)


def main():
    # Maraca shake: two quick rattles (shake-shake)
    s = shaker()
    g.write("maraca_shake", g.mix(0.32, s, at(s * 0.7, 0.11, 0.32)))

    # Party Mode: beep-boop, then four-on-the-floor with a hi-hat and a whistle
    D = 2.4
    beep = at(tone(0.09, 1320, "square") * g.env(g.t_of(0.09), 0.005, 0.05), 0.0, D) + \
        at(tone(0.12, 880, "square") * g.env(g.t_of(0.12), 0.005, 0.07), 0.11, D)
    beat = np.zeros(int(D * SR))
    for k in range(8):
        beat += at(g.boom(0.3, 120, 45, 0.12), 0.3 + k * 0.25, D)
        beat += at(shaker(0.08) * 0.6, 0.425 + k * 0.25, D)
    t = g.t_of(0.9)
    whistle = tone(0.9, 2400 + 500 * np.sin(2 * np.pi * 9 * t)) * g.env(t, 0.02, 0.4) * 0.3
    g.write("party_mode", g.mix(D, beep * 0.6, beat, at(whistle, 0.35, D), g.shimmer(D, 3000, 7000, 25) * 0.15))

    # Pinata Drop: whoop up, party horn, then a candy burst of pops at 3 s
    D = 4.2
    t = g.t_of(0.6)
    whoop = tone(0.6, 300 + 900 * t / 0.6) * g.env(t, 0.03, 0.3) * 0.5
    th = g.t_of(0.5)
    horn = g.bp(tone(0.5, 420 + 40 * np.sin(2 * np.pi * 6 * th), "saw"), 300, 2500) * g.env(th, 0.02, 0.3)
    pops = np.zeros(int(D * SR))
    for k in range(20):
        pops += at(g.boom(0.25, 260, 90, 0.05) * 0.5 + g.hp(g.noise(0.25), 1500) * np.exp(-g.t_of(0.25) / 0.03) * 0.3,
                   3.0 + k * 0.045 + g.rng.uniform(0, 0.03), D)
    bang = at(g.boom(1.0, 70, 30, 0.35) * 1.2, 3.0, D)
    g.write("pinata_drop", g.mix(D, whoop, at(horn, 0.45, D), bang, pops, at(g.chime(1.0, [1568, 2093, 2637], 0.2) * 0.4, 3.05, D)))

    # DESTROY Mode: servo whine up, alarm, then a buzzing laser hum
    D = 3.0
    t = g.t_of(0.8)
    servo = tone(0.8, 200 + 1100 * (t / 0.8) ** 2, "square") * g.env(t, 0.05, 0.6) * 0.3
    alarm = np.zeros(int(D * SR))
    for k in range(3):
        alarm += at(tone(0.22, 160, "saw") * g.env(g.t_of(0.22), 0.01, 0.15), 0.8 + k * 0.28, D)
    t = g.t_of(2.0)
    hum = g.lp(tone(2.0, 110 + 6 * np.sin(2 * np.pi * 30 * t), "saw"), 1800) * np.clip(t / 0.15, 0, 1) * np.clip((2.0 - t) / 0.6, 0, 1)
    zap = g.bp(g.noise(2.0), 2000, 6000) * 0.15 * np.clip(t / 0.15, 0, 1) * np.clip((2.0 - t) / 0.6, 0, 1)
    g.write("destroy_mode", g.mix(D, servo, alarm * 0.7, at(hum + zap, 1.0, D)))


if __name__ == "__main__":
    main()
