"""Synthesise the Ashen Caldera's sounds (no samples needed), with the little synth voices of
tools/gen_thog_kit_sounds.py:

audio/caldera/lava_bubble.wav       a slow, thick bubbling and popping of molten rock (loops)
audio/caldera/rumble.wav            a distant volcanic rumble rolling in and out
audio/caldera/eruption.wav          the volcano erupting: a deep blast, a roaring jet, rocks raining
audio/caldera/bomb_whistle.wav      a lava bomb's rushing fall
audio/caldera/bomb_impact.wav       a lava bomb hitting the ground: a heavy thud, a splash, sizzling
audio/caldera/sizzle.wav            the hiss of something (you) burning in the lava
audio/caldera/crack_open.wav        the ground cracking open, lava welling up (things clawing out)
audio/caldera/imp_death_1..2.wav    a magma imp bursting: a crackling pop, embers, rock chunks
audio/caldera/imp_chitter_1..2.wav  an imp's hissing, clicking chatter
audio/caldera/bat_screech_1..2.wav  a cinder bat's shrill crackling screech
audio/caldera/bat_flap.wav          leathery wingbeats with a flicker of fire
audio/caldera/golem_step.wav        an obsidian golem's heavy, glassy footfall
audio/caldera/golem_shatter.wav     the golem shattering: a crack and a cascade of glass
audio/caldera/slug_squelch.wav      a lava slug squelching and sizzling along
audio/caldera/slug_death.wav        a slug melting into a hissing puddle
audio/caldera/singe_cackle.wav      Singe's cackle: a gleeful, crackling "ha-ha-ha-HA" from a giant coal imp
audio/caldera/singe_giggle.wav      a quick, wicked little giggle (winding up his tricks)
audio/caldera/singe_breath.wav      his fire breath: a spluttering spew of flame
audio/caldera/singe_splash.wav      cannonballing into the lava: a heavy SPLOOSH and gurgling
audio/caldera/singe_emerge.wav      popping up out of the lava: a surge, a splash, spattering
audio/caldera/singe_swipe.wav       the claw swipe: a swish and a rake of sparks
audio/caldera/singe_scamper.wav     scampering off: a patter of clawed feet and crackling
audio/caldera/flood.wav             the Caldera Eruption landing: the whole floor turning to lava
audio/caldera/singe_fizzle.wav      his death: a falling, sputtering whine, crackles dying away, a long fizz
audio/caldera/singe_puff.wav        the last puff of smoke

    python3 tools/gen_caldera_sounds.py
"""
import importlib.util
import os
import numpy as np

_spec = importlib.util.spec_from_file_location("g", os.path.join(os.path.dirname(__file__), "gen_thog_kit_sounds.py"))
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)
SR = g.SR
g.OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "caldera") + os.sep
os.makedirs(g.OUT, exist_ok=True)
rng = np.random.default_rng(61)


def at(x, d, start):
    return np.roll(g.fit(x, int(d * SR)), int(start * SR))


def blorp(d, n, lo, hi, decay=0.09):
    """Thick, slow bubbles: low gliding tones that pop."""
    t = g.t_of(d)
    out = np.zeros_like(t)
    for _ in range(n):
        t0 = rng.uniform(0, d * 0.92)
        f = rng.uniform(lo, hi)
        tt = np.clip(t - t0, 0, None)
        out += np.sin(2 * np.pi * (f + f * 3.0 * tt) * tt) * np.exp(-tt / decay) * (t >= t0) * rng.uniform(0.4, 1.0)
        pop = np.exp(-np.clip(t - t0 - decay * 1.5, 0, None) / 0.004) * (t >= t0 + decay * 1.5)
        out += g.hp(pop * rng.normal(0, 1, t.size), 1500) * 0.15
    return out


def crackle(d, density=0.995, lo=1500):
    """Fire / embers crackling: sparse clicks."""
    t = g.t_of(d)
    c = (rng.random(t.size) > density).astype(float) * rng.uniform(0.2, 1.0, t.size)
    return g.hp(c, lo)


def hiss(d, lo=2500, hi=9000):
    return g.bp(g.noise(d), lo, hi)


def rumble_tone(d, f=28, wob=0.7):
    t = g.t_of(d)
    return g.lp(g.noise(d), 120) * (1 + 0.5 * np.sin(2 * np.pi * wob * t)) + np.sin(2 * np.pi * np.cumsum(f + 4 * np.sin(2 * np.pi * 0.3 * t)) / SR) * 0.4


def roar_jet(d, lo=150, hi=1800):
    """A roaring jet of flame / gas: band noise with a turbulent flutter."""
    t = g.t_of(d)
    flutter = 1 + 0.35 * np.sin(2 * np.pi * 13 * t + 2 * np.sin(2 * np.pi * 3 * t))
    return (g.bp(g.noise(d), lo, hi) + g.lp(g.noise(d), 200) * 0.6) * flutter


def glass(d, n=50, lo=2500, hi=9000, spread=0.5):
    """Glass breaking: bright inharmonic pings scattered over a decaying spray."""
    t = g.t_of(d)
    out = np.zeros_like(t)
    for _ in range(n):
        t0 = rng.exponential(spread * 0.3)
        if t0 > d * 0.9:
            continue
        f = rng.uniform(lo, hi)
        tt = np.clip(t - t0, 0, None)
        out += (np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 2.3 * tt)) * np.exp(-tt / rng.uniform(0.02, 0.09)) * (t >= t0) * rng.uniform(0.2, 1.0)
    return out


def chitter(d, f0):
    """Hissing, clicking imp chatter: rapid clicks through a nasal formant, a hiss."""
    t = g.t_of(d)
    rate = 26 + 10 * np.sin(2 * np.pi * 2.5 * t)
    clicks = (np.sin(2 * np.pi * np.cumsum(rate) / SR) > 0.92).astype(float)
    voice = np.sign(np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.2 * np.sin(2 * np.pi * 9 * t))) / SR))
    return g.bp(clicks * 2.0 + voice * 0.4, 900, 4000) * np.sin(np.pi * t / d) + hiss(d, 3000, 8000) * 0.2 * np.sin(np.pi * t / d)


def screech(d, f0):
    t = g.t_of(d)
    f = f0 * (1 + 0.5 * np.sin(np.pi * t / d)) + rng.normal(0, f0 * 0.04, t.size)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sign(np.sin(ph)) * 0.5 + np.sin(2 * ph) * 0.3
    return g.bp(tone + g.hp(g.noise(d), 4000) * 0.3, 1800, 8000) * g.env(t, 0.02, d * 0.4)


def laugh(d, f0, rate, n, start):
    """A cackle: "ha" syllables (a breathy h, then a voiced vowel through formants) at `rate` a
    second, pitch leaping up then tumbling down, from `start` s."""
    t = g.t_of(d)
    out = np.zeros_like(t)
    for k in range(n):
        t0 = start + k / rate * (1 + 0.15 * rng.uniform(-1, 1))
        if t0 > d - 0.12:
            break
        u = k / max(1, n - 1)
        f = f0 * (1.0 + 0.6 * np.sin(np.pi * min(1.0, u * 1.4)) - 0.25 * u)
        sl = 0.11
        tt = t - t0
        on = (tt >= 0) & (tt < sl)
        tts = np.clip(tt, 0, sl)
        fk = f * (1 + 0.15 * tts / sl)
        ph = 2 * np.pi * fk * tts
        src = sum(np.sin(h * ph) / h ** 0.8 for h in range(1, 24))
        env = np.sin(np.pi * tts / sl) ** 0.6 * on
        out += src * env * (0.7 + 0.3 * rng.random())
        breath = (tt >= -0.03) & (tt < 0.01)
        out += g.noise(d) * breath * 0.25
    vowel = g.bp(out, 600, 1100) + g.bp(out, 1100, 1800) * 0.7 + g.bp(out, 2300, 3200) * 0.35 + g.bp(out, 120, 400) * 0.5
    grit = 1 + 0.3 * np.sign(np.sin(2 * np.pi * 37 * t))
    return vowel * grit


def main():
    # The lava: bubbling (a loop: the ends fade into each other), rumbles, eruptions, bombs
    d = 4.0
    t = g.t_of(d)
    bub = g.mix(d, blorp(d, 26, 60, 180, 0.12), g.lp(g.noise(d), 160) * 0.35, crackle(d, 0.9985) * 0.25)
    fade = int(SR * 0.4)
    bub[:fade] = bub[:fade] * np.linspace(0, 1, fade) + bub[-fade:] * np.linspace(1, 0, fade)
    bub = bub[:-fade]
    g.write("lava_bubble", bub)
    d = 4.5
    t = g.t_of(d)
    g.write("rumble", rumble_tone(d) * np.sin(np.pi * t / d) ** 1.5 + g.boom(d, 40, 22, 1.4) * 0.5)
    d = 4.0
    t = g.t_of(d)
    rain = sum(at(g.boom(0.4, 90, 50, 0.1), d, rng.uniform(1.2, 3.6)) * rng.uniform(0.2, 0.5) for _ in range(12))
    g.write("eruption", g.mix(d, g.boom(d, 45, 18, 1.2) * 1.4, roar_jet(d, 120, 1400) * np.clip(t / 0.15, 0, 1) * np.exp(-np.clip(t - 0.4, 0, None) / 1.4) * 0.8, rain, crackle(d, 0.993) * 0.4))
    d = 1.2
    t = g.t_of(d)
    g.write("bomb_whistle", g.whoosh(d, 400, 2400, 0.75) + crackle(d, 0.996) * 0.3)
    d = 1.6
    t = g.t_of(d)
    g.write("bomb_impact", g.mix(d, g.boom(d, 70, 30, 0.35) * 1.3, g.bp(g.noise(d), 300, 2500) * np.exp(-t / 0.12) * 0.7, hiss(d) * np.exp(-t / 0.6) * 0.35 * np.clip(t / 0.05, 0, 1), crackle(d, 0.992) * np.exp(-t / 0.5) * 0.5))
    d = 0.9
    t = g.t_of(d)
    g.write("sizzle", g.mix(d, hiss(d, 2000, 9000) * g.env(t, 0.02, 0.35), crackle(d, 0.985) * 0.6 * np.exp(-t / 0.4)))
    d = 1.3
    t = g.t_of(d)
    crk = g.hp(g.noise(d), 600) * (rng.random(t.size) > 0.97) * np.exp(-t / 0.2) * 1.5
    g.write("crack_open", g.mix(d, crk, g.boom(d, 60, 35, 0.3) * 0.6, blorp(d, 8, 70, 160, 0.15) * np.clip((t - 0.2) / 0.3, 0, 1) * 0.7))
    # Imps
    for k in range(2):
        d = 0.7
        t = g.t_of(d)
        g.write("imp_death_%d" % (k + 1), g.mix(d, g.boom(d, 160 + 40 * k, 70, 0.08) * 0.9, crackle(d, 0.97) * np.exp(-t / 0.25) * 0.9, g.bp(g.noise(d), 800, 3000) * np.exp(-t / 0.05) * 0.6,
            sum(at(g.clank(0.15, rng.uniform(300, 600)), d, rng.uniform(0.08, 0.4)) * 0.15 for _ in range(4))))
        d = 0.6 + 0.15 * k
        g.write("imp_chitter_%d" % (k + 1), chitter(d, 380 + 120 * k))
    # Bats
    for k, f0 in enumerate([2200, 2700]):
        d = 0.55 + 0.1 * k
        t = g.t_of(d)
        g.write("bat_screech_%d" % (k + 1), g.mix(d, screech(d, f0), crackle(d, 0.99) * 0.25))
    d = 0.6
    t = g.t_of(d)
    beat = g.lp(g.noise(0.18), 700) * np.exp(-g.t_of(0.18) / 0.05)
    g.write("bat_flap", g.mix(d, beat, at(beat, d, 0.2), at(beat, d, 0.4), crackle(d, 0.993) * 0.3))
    # Golems
    d = 0.9
    t = g.t_of(d)
    g.write("golem_step", g.mix(d, g.boom(d, 55, 30, 0.25) * 1.2, glass(d, 6, 1800, 4000, 0.1) * 0.25, g.lp(g.noise(d), 300) * np.exp(-t / 0.06) * 0.5))
    d = 2.0
    t = g.t_of(d)
    g.write("golem_shatter", g.mix(d, g.hp(g.noise(d), 800) * np.exp(-t / 0.05) * 1.2, glass(d, 90, 2000, 9500, 1.2) * 0.8, g.boom(d, 80, 40, 0.3) * 0.7, crackle(d, 0.99) * np.exp(-t / 0.8) * 0.3))
    # Slugs
    d = 0.8
    t = g.t_of(d)
    g.write("slug_squelch", g.mix(d, blorp(d, 5, 110, 260, 0.08) * 0.8, g.bp(g.noise(d), 400, 1600) * np.sin(np.pi * t / d) ** 2 * 0.4, hiss(d) * 0.15 * np.sin(np.pi * t / d)))
    d = 1.6
    t = g.t_of(d)
    g.write("slug_death", g.mix(d, blorp(d, 10, 80, 220, 0.1) * np.exp(-t / 0.6), hiss(d, 1800, 8000) * g.env(t, 0.05, 0.7) * 0.6, g.boom(d, 90, 45, 0.2) * 0.4))
    # Singe
    d = 2.4
    t = g.t_of(d)
    g.write("singe_cackle", g.mix(d, laugh(d, 150, 7.0, 13, 0.25), np.roll(laugh(d, 150, 7.0, 13, 0.25), int(0.18 * SR)) * 0.25, crackle(d, 0.99) * 0.35, roar_jet(d, 300, 1500) * 0.06))
    d = 1.0
    t = g.t_of(d)
    g.write("singe_giggle", g.mix(d, laugh(d, 260, 10.0, 7, 0.1), crackle(d, 0.993) * 0.3))
    d = 2.0
    t = g.t_of(d)
    splutter = 1 + 0.5 * (np.sin(2 * np.pi * 7 * t) > 0.3)
    g.write("singe_breath", g.mix(d, roar_jet(d, 250, 3000) * g.env(t, 0.06, 1.0) * splutter, g.boom(d, 70, 40, 0.4) * 0.35, crackle(d, 0.98) * np.sin(np.pi * t / d) * 0.7))
    d = 2.0
    t = g.t_of(d)
    g.write("singe_splash", g.mix(d, g.boom(d, 60, 28, 0.6) * 1.2, g.bp(g.noise(d), 250, 2500) * np.exp(-t / 0.18) * 1.1, blorp(d, 16, 60, 170, 0.15) * np.clip((t - 0.15) / 0.2, 0, 1) * np.exp(-t / 0.9), hiss(d, 2000, 8000) * np.exp(-t / 0.7) * 0.3))
    d = 2.0
    t = g.t_of(d)
    spat = sum(at(g.boom(0.25, 160, 80, 0.06), d, rng.uniform(0.3, 1.4)) * rng.uniform(0.15, 0.4) for _ in range(9))
    g.write("singe_emerge", g.mix(d, roar_jet(d, 150, 1200) * g.env(t, 0.15, 0.8) * 0.7, g.boom(d, 50, 25, 0.8) * 0.9, blorp(d, 14, 70, 190, 0.12) * 0.7, spat))
    d = 0.9
    t = g.t_of(d)
    g.write("singe_swipe", g.mix(d, g.whoosh(d, 300, 2500, 0.3) * 1.1, at(crackle(0.5, 0.95), d, 0.3) * 0.8, at(g.bp(g.noise(0.3), 2500, 7000) * np.exp(-g.t_of(0.3) / 0.06), d, 0.3) * 0.6))
    d = 1.4
    t = g.t_of(d)
    feet = sum(at(g.lp(g.noise(0.06), 900) * np.exp(-g.t_of(0.06) / 0.015) + g.bp(g.noise(0.06), 3000, 7000) * np.exp(-g.t_of(0.06) / 0.008) * 0.6, d, k * 0.09 + rng.uniform(0, 0.02)) * (1.0 - k / 16.0) for k in range(15))
    g.write("singe_scamper", g.mix(d, feet, crackle(d, 0.985) * 0.4 * np.exp(-t / 0.8), laugh(d, 280, 11.0, 5, 0.6) * 0.4))
    d = 4.0
    t = g.t_of(d)
    g.write("flood", g.mix(d, roar_jet(d, 80, 900) * g.env(t, 0.2, 2.0), g.boom(d, 35, 18, 2.0) * 1.2, blorp(d, 40, 50, 200, 0.15) * 0.8, hiss(d, 1500, 8000) * g.env(t, 0.5, 2.0) * 0.4, crackle(d, 0.99) * 0.4))
    d = 4.0
    t = g.t_of(d)
    f = 320 * np.exp(-t * 0.9) + 60
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.08 * np.sin(2 * np.pi * 9 * t))) / SR
    whine = g.bp(sum(np.sin(h * ph) / h for h in range(1, 14)) + 0.4 * g.noise(d), 200, 3000) * g.env(t, 0.05, 0.9) * (0.6 + 0.4 * (rng.random(t.size) > 0.3))
    dying = crackle(d, 0.97) * np.exp(-t / 0.9)
    g.write("singe_fizzle", g.mix(d, whine, dying * 0.9, hiss(d, 2500, 9000) * np.clip((t - 0.6) / 0.4, 0, 1) * np.exp(-np.clip(t - 1.2, 0, None) / 1.2) * 0.7))
    d = 1.6
    t = g.t_of(d)
    g.write("singe_puff", g.mix(d, g.lp(g.noise(d), 500) * g.env(t, 0.02, 0.35) * 1.2, g.boom(d, 90, 45, 0.25) * 0.5, hiss(d, 1500, 6000) * g.env(t, 0.05, 0.6) * 0.35))


if __name__ == "__main__":
    main()
