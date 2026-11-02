"""Synthesise the playable bosses' kit sounds (no samples needed), using the little synth voices
in tools/gen_thog_kit_sounds.py. Into audio/abilities/:

The Pharaoh
  scarab_bolt       a dry chittering buzz of wings (every Scarab Bolts volley; short)
  curse_sands       a rising, hollow wail over a low drone, then a crack of light
  sandstorm         a howling, whirling wind of hissing sand
  wrath_sands       a deep stone rumble rising, a choir-like chord as the Sphinx's eyes blaze
  wrath_storm       the storm breaking: a roaring blast of wind and grit
The Necromancer
  soul_bolt         a short ghostly whoosh with a hollow moan (every Soul Bolts shot)
  necro_raise       earth breaking, bones rattling, a low choir of moans
  soul_drain        a sucking, warbling drone with souls whispering along it
  graves_open       a deep toll, the ground splitting
  bone_spikes       a clattering crunch of bone bursting from the earth
Singe
  fireflick         a flick and a crackling sizzle (every Fireflick pair; short)
  scorch_trail      a whoosh of catching flame and a cackling crackle
  lava_cannonball   a springy launch, a spinning roar of fire
  cannonball_land   a heavy splashing thump of lava
  caldera_eruption  a volcano's deep boom and roar
  lava_bomb         one bomb's thudding splat and hiss

    python3 tools/gen_playable_boss_sounds.py
"""
import importlib.util
import os
import numpy as np

_spec = importlib.util.spec_from_file_location("g", os.path.join(os.path.dirname(__file__), "gen_thog_kit_sounds.py"))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
SR = g.SR


def at(x, secs, n):
    return np.roll(g.fit(x, n), int(secs * SR))


def tone(d, f0, f1, decay, harm=(1.0,)):
    t = g.t_of(d)
    f = f0 + (f1 - f0) * t / d
    ph = 2 * np.pi * np.cumsum(f) / SR
    return sum(a * np.sin((k + 1) * ph) for k, a in enumerate(harm)) * np.exp(-t / decay)


def buzz(d, rate=90, lo=1500, hi=5000):
    """Chittering insect wings: noise gated at a fast rate."""
    t = g.t_of(d)
    gate = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rate * t))) * (0.6 + 0.4 * np.sin(2 * np.pi * 13 * t))
    return g.bp(g.noise(d), lo, hi) * gate * g.env(t, 0.01, d * 0.5)


def wind(d, lo=300, hi=1600, wobble=0.7):
    t = g.t_of(d)
    base = g.bp(g.noise(d), lo, hi)
    howl = sum(np.sin(2 * np.pi * (f + 40 * np.sin(2 * np.pi * 0.6 * t + f)) * t) for f in (220, 330, 410)) * 0.15
    return (base + howl) * (1 - wobble + wobble * (0.5 + 0.5 * np.sin(2 * np.pi * 1.3 * t)))


def moan(d, f0=180, f1=140):
    t = g.t_of(d)
    f = f0 + (f1 - f0) * t / d + 6 * np.sin(2 * np.pi * 5 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    v = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)
    return g.bp(v + 0.3 * g.noise(d), 200, 1400) * g.env(t, d * 0.3, d * 0.4)


def rattle(d, n=24):
    out = np.zeros(int(d * SR))
    for _ in range(n):
        t0 = g.rng.uniform(0, d * 0.8)
        out += at(g.clank(0.08, g.rng.uniform(1400, 2600)) * g.rng.uniform(0.2, 0.5), t0, out.size)
    return out


def crackle(d, n=60):
    out = np.zeros(int(d * SR))
    for _ in range(n):
        t0 = g.rng.uniform(0, d * 0.9)
        out += at(g.hp(g.noise(0.01), 2000) * g.rng.uniform(0.2, 0.8), t0, out.size)
    return out


def main():
    # --- The Pharaoh
    g.write("scarab_bolt", g.mix(0.35, buzz(0.3) * 0.8, g.whoosh(0.3, 1200, 4000, 0.4) * 0.5))
    d = 1.4
    n = int(d * SR)
    t = g.t_of(d)
    drone = np.sin(2 * np.pi * 73 * t) * g.env(t, 0.1, 0.8) * 0.5
    wail = tone(0.9, 300, 620, 0.6, (1.0, 0.4, 0.2)) * 0.4
    g.write("curse_sands", g.mix(d, drone, wail, at(g.boom(0.5, 140, 60, 0.15) * 0.6, 0.25, n),
                                 at(g.shimmer(0.7, 2500, 6000, 20) * 0.35, 0.25, n)))
    d = 2.2
    t = g.t_of(d)
    g.write("sandstorm", g.mix(d, wind(d) * g.env(t, 0.4, 1.4), g.hp(g.noise(d), 3000) * g.env(t, 0.3, 1.2) * 0.4))
    d = 2.6
    n = int(d * SR)
    t = g.t_of(d)
    rumble = g.lp(g.noise(d), 120) * g.env(t, 0.8, 1.2) * 1.4
    chord = sum(np.sin(2 * np.pi * f * t) for f in (110, 165, 220, 277)) * g.env(t, 1.2, 0.9) * 0.15
    g.write("wrath_sands", g.mix(d, rumble, chord, at(g.chime(1.2, [880, 1320, 1760], 0.5) * 0.25, 1.1, n)))
    d = 2.4
    t = g.t_of(d)
    g.write("wrath_storm", g.mix(d, g.boom(1.0, 70, 30, 0.5) * 1.2, wind(d, 200, 2400, 0.3) * g.env(t, 0.05, 1.0) * 1.2,
                                 g.hp(g.noise(d), 2500) * g.env(t, 0.02, 0.7) * 0.6))
    # --- The Necromancer
    g.write("soul_bolt", g.mix(0.45, g.whoosh(0.4, 500, 2500, 0.35) * 0.8, moan(0.4, 420, 300) * 0.5))
    d = 1.8
    n = int(d * SR)
    g.write("necro_raise", g.mix(d, g.boom(0.6, 80, 35, 0.3) * 0.8, at(rattle(1.2) * 0.9, 0.2, n),
                                 at(moan(1.4, 150, 120) * 0.8, 0.25, n), at(moan(1.3, 190, 160) * 0.5, 0.35, n)))
    d = 2.0
    t = g.t_of(d)
    suck = tone(d, 160, 110, 1.5, (1.0, 0.5, 0.3)) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t))
    whisper = g.bp(g.noise(d), 2000, 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * 3 * t)) * 0.3
    g.write("soul_drain", g.mix(d, suck * g.env(t, 0.2, 1.4) * 0.7, whisper * g.env(t, 0.3, 1.2)))
    d = 2.6
    n = int(d * SR)
    t = g.t_of(d)
    toll = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / 1.5) for f in (98, 196 * 1.01, 247, 392)) * 0.3
    g.write("graves_open", g.mix(d, toll, at(g.lp(g.noise(1.4), 200) * g.env(g.t_of(1.4), 0.2, 0.6) * 1.2, 0.4, n),
                                 at(moan(1.6, 130, 100) * 0.5, 0.8, n)))
    d = 0.8
    g.write("bone_spikes", g.mix(d, g.boom(0.4, 110, 50, 0.12) * 0.8, rattle(0.6, 30) * 1.0, crackle(0.4, 40) * 0.6))
    # --- Singe
    g.write("fireflick", g.mix(0.4, g.whoosh(0.18, 2000, 6000, 0.3) * 0.6, crackle(0.35, 25) * 0.7,
                               g.hp(g.noise(0.35), 3500) * g.env(g.t_of(0.35), 0.01, 0.12) * 0.4))
    d = 1.4
    n = int(d * SR)
    t = g.t_of(d)
    g.write("scorch_trail", g.mix(d, g.whoosh(0.8, 300, 2500, 0.3) * 1.0, crackle(d, 90) * 0.6 * g.env(t, 0.2, 0.8),
                                  at(tone(0.5, 600, 900, 0.15, (1.0, 0.5)) * 0.2, 0.5, n), at(tone(0.4, 700, 1000, 0.12, (1.0, 0.5)) * 0.2, 0.75, n)))
    d = 1.0
    t = g.t_of(d)
    g.write("lava_cannonball", g.mix(d, tone(0.3, 200, 500, 0.12) * 0.5, g.whoosh(0.9, 200, 1600, 0.5) * 1.0,
                                     g.lp(g.noise(d), 600) * g.env(t, 0.3, 0.5) * 0.5))
    d = 1.4
    t = g.t_of(d)
    g.write("cannonball_land", g.mix(d, g.boom(1.0, 70, 32, 0.35) * 1.3, g.bubbles(1.0, 30, 150, 500) * 0.5,
                                     g.hp(g.noise(d), 2500) * g.env(t, 0.1, 0.5) * 0.4))
    d = 3.0
    n = int(d * SR)
    t = g.t_of(d)
    g.write("caldera_eruption", g.mix(d, g.boom(2.0, 50, 25, 0.9) * 1.4, g.lp(g.noise(d), 400) * g.env(t, 0.3, 1.5) * 1.0,
                                      crackle(d, 140) * 0.4, at(g.boom(0.8, 90, 40, 0.3) * 0.6, 0.6, n)))
    d = 0.7
    t = g.t_of(d)
    g.write("lava_bomb", g.mix(d, g.boom(0.5, 90, 40, 0.15) * 1.0, g.hp(g.noise(d), 3000) * g.env(t, 0.05, 0.3) * 0.5))


if __name__ == "__main__":
    main()
