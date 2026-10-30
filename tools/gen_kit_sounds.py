"""Synthesise the roster kits' ability sounds and the melee whoosh (audio/abilities/).

Merlin:          time_warp (a tick-tock slowing into a deep warble), polymorph (a magic "bloing"
                 and croaks), rewind (a tape-reverse swell)
Ogre:            bellow (a huge low roar), belly_flop (a whistling fall), slam (a ground thump with
                 a mud splash), swamp_rage (a growl rising into a roar)
Ghast:           phase (an airy whoosh through a filter), haunt (a hollow moan), haunt_burst (a
                 wet spectral pop), banshee (a piercing wavering shriek)
Vampire Hunter:  holy_water (a glass vial whirring), splash (glass break and splash),
                 stake_volley (many quick thunks), hunters_night (a deep bell toll and wind)
Vicki:           shield_wall (a metallic clang and shimmer), wings (big wing flaps),
                 valkyries (galloping hooves under a heroic horn)
Rogue:           smoke_bomb (a pop and a hiss), pickpocket (a quick swish and coin jingle),
                 thousand_cuts (a rising rush), cut (a short blade swish)
Gaiden:          shadow_step (a reversed whoosh and a blade ring), shuriken (a spinning whirr),
                 whirl (a short throw), reed_clones (a breathy chord in fifths)
Dr. Croc:        mutagen (gulping and bubbles), death_roll (a churning splashy roll),
                 toxic_spill (glass crash and a bubbling gush)
Weapons:         whoosh (a short melee swing)

    python3 tools/gen_kit_sounds.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/abilities/"
rng = np.random.default_rng(23)


def t_of(d):
    return np.arange(int(SR * d)) / SR


def lp(x, hz, o=3):
    return sosfilt(butter(o, hz, "low", fs=SR, output="sos"), x)


def hp(x, hz, o=2):
    return sosfilt(butter(o, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, min(hi, SR / 2 - 100)], "band", fs=SR, output="sos"), x)


def noise(d):
    return rng.standard_normal(int(SR * d))


def env(n, a, r):
    """Attack/release envelope of n samples (a, r in seconds)."""
    e = np.ones(n)
    na = max(1, int(a * SR))
    nr = max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr) ** 1.5
    return e


def sweep(f0, f1, d, shape="sine"):
    t = t_of(d)
    f = np.geomspace(f0, f1, len(t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    return np.sin(ph)


def fit(x, d):
    n = int(SR * d)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def place(buf, snd, at):
    i = int(at * SR)
    n = min(len(snd), len(buf) - i)
    if n > 0:
        buf[i:i + n] += snd[:n]


def write(name, x, peak=0.85, spread=0.004):
    x = np.tanh(x * 1.1)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(SR * 0.02)
    x[-fade:] *= np.linspace(1, 0, fade)
    st = np.stack([x, np.roll(x, int(SR * spread))], 1)
    wavfile.write(OUT + name + ".wav", SR, (st * 32767).astype(np.int16))
    print(name, f"{len(x) / SR:.2f}s")


def whoosh(d, lo=300, hi=3000):
    n = noise(d)
    t = t_of(d)
    centre = lo + (hi - lo) * np.sin(np.pi * t / d) ** 2
    out = np.zeros_like(n)
    for k in range(6):   # crude moving band: blend a few fixed bands by the moving centre
        f = lo * (hi / lo) ** (k / 5)
        w = np.exp(-((np.log(centre) - np.log(f)) ** 2) / 0.15)
        out += bp(n, f * 0.7, f * 1.4) * w
    return out * env(len(n), d * 0.4, d * 0.5)


def thump(d=0.4, f=60):
    t = t_of(d)
    return np.sin(2 * np.pi * f * t * (1 - t / d * 0.5)) * np.exp(-t * 9) + lp(noise(d), 300) * np.exp(-t * 20) * 0.5


def clang(d=1.2, f=620):
    t = t_of(d)
    x = sum(np.sin(2 * np.pi * f * r * t) * np.exp(-t * (3 + r)) / r for r in [1, 2.76, 5.4, 8.93])
    return x + hp(noise(d), 3000) * np.exp(-t * 40) * 0.6


def voice(f, d, formants, vib=5.0, depth=0.03):
    t = t_of(d)
    ff = f * (1 + depth * np.sin(2 * np.pi * vib * t))
    ph = 2 * np.pi * np.cumsum(ff) / SR
    src = 2 * ((ph / (2 * np.pi)) % 1.0) - 1 + lp(noise(d), 2000) * 0.15
    return sum(bp(src, a, b) for a, b in formants)


def main():
    # ---------------------------------------------------------------- weapons
    write("whoosh", whoosh(0.22, 400, 2600), 0.7)

    # ---------------------------------------------------------------- Merlin
    d = 2.2
    x = np.zeros(int(SR * d))
    gap = 0.18
    at = 0.0
    for k in range(9):   # tick-tock, slowing down
        tick = hp(noise(0.03), 2500) * np.exp(-t_of(0.03) * 120) * (0.9 if k % 2 == 0 else 0.6)
        place(x, tick, at)
        at += gap
        gap *= 1.18
    x += sweep(600, 120, d) * env(int(SR * d), 0.05, 0.8) * 0.35 * (1 + 0.5 * np.sin(2 * np.pi * 3 * t_of(d)))
    write("time_warp", x)
    d = 1.4
    x = sweep(300, 1400, 0.35) * env(int(SR * 0.35), 0.01, 0.2)
    x = fit(x, d)
    for k, at in enumerate([0.45, 0.7, 0.9, 1.05]):
        cr = voice(140 + k * 25, 0.18, [(300, 700), (1100, 1800)], vib=30, depth=0.2) * env(int(SR * 0.18), 0.01, 0.08)
        place(x, cr * 0.8, at)
    x += hp(noise(d), 5000) * np.exp(-t_of(d) * 4) * 0.12
    write("polymorph", x)
    d = 1.8
    t = t_of(d)
    rev = (lp(noise(d), 1800) * 0.6 + sweep(900, 200, d, "saw") * 0.3) * np.linspace(0.05, 1, len(t)) ** 2
    rev[-int(SR * 0.08):] *= np.linspace(1, 0, int(SR * 0.08))
    x = rev
    place(x, clang(0.2, 900) * 0.6, 1.6)
    write("rewind", x)

    # ---------------------------------------------------------------- Ogre
    d = 1.6
    x = voice(70, d, [(150, 450), (500, 900), (1200, 1900)], vib=7, depth=0.08) * env(int(SR * d), 0.1, 0.6)
    x += lp(noise(d), 600) * env(int(SR * d), 0.1, 0.5) * 0.6
    write("bellow", x)
    write("belly_flop", sweep(1800, 400, 0.7) * env(int(SR * 0.7), 0.05, 0.1) * 0.4 + whoosh(0.7, 200, 1200))
    d = 0.9
    x = thump(d, 50) * 1.4 + lp(noise(d), 1500) * np.exp(-t_of(d) * 6) * 0.5
    write("slam", x)
    d = 2.0
    t = t_of(d)
    x = voice(55 + 45 * (t / d) ** 2, d, [(120, 400), (450, 900), (1100, 1800)], vib=11, depth=0.1) * env(len(t), 0.3, 0.4)
    write("swamp_rage", x)

    # ---------------------------------------------------------------- Ghast
    write("phase", whoosh(1.0, 200, 1600) + sweep(400, 1200, 1.0) * env(int(SR), 0.3, 0.6) * 0.15)
    d = 1.8
    write("haunt", voice(180, d, [(250, 500), (600, 900)], vib=3, depth=0.15) * env(int(SR * d), 0.3, 0.8))
    d = 0.5
    write("haunt_burst", thump(d, 90) + bp(noise(d), 600, 3000) * np.exp(-t_of(d) * 12))
    d = 2.2
    t = t_of(d)
    x = voice(900 + 250 * np.sin(2 * np.pi * 0.8 * t), d, [(800, 1600), (2000, 3200), (3500, 5000)], vib=9, depth=0.06)
    x = x * env(len(t), 0.05, 0.9) + hp(noise(d), 2000) * env(len(t), 0.02, 1.2) * 0.3
    write("banshee", x)

    # ---------------------------------------------------------------- Vampire Hunter
    write("holy_water", whoosh(0.5, 600, 2400) * 0.7 + sweep(1400, 2400, 0.5) * env(int(SR * 0.5), 0.05, 0.2) * 0.1)
    d = 0.9
    t = t_of(d)
    x = hp(noise(d), 2500) * np.exp(-t * 10) * 0.7
    for k in range(6):
        place(x, clang(0.4, 2200 + 700 * k) * 0.15, 0.01 * k)
    x += lp(noise(d), 1200) * env(len(t), 0.02, 0.7) * 0.6
    write("splash", x)
    d = 0.8
    x = np.zeros(int(SR * d))
    for k in range(16):
        place(x, thump(0.12, 160 + rng.random() * 60) * 0.5, k * 0.035)
        place(x, hp(noise(0.05), 1500) * np.exp(-t_of(0.05) * 60) * 0.4, k * 0.035)
    write("stake_volley", x)
    d = 3.0
    t = t_of(d)
    bell = sum(np.sin(2 * np.pi * 110 * r * t) * np.exp(-t * (0.8 + r * 0.4)) / r for r in [1, 2.0, 2.4, 3.0, 4.2])
    wind = bp(noise(d), 300, 900) * (0.4 + 0.3 * np.sin(2 * np.pi * 0.4 * t)) * env(len(t), 0.8, 1.0)
    write("hunters_night", bell + wind * 0.6)

    # ---------------------------------------------------------------- Vicki
    d = 1.4
    write("shield_wall", clang(d, 440) + sweep(800, 2400, d) * env(int(SR * d), 0.1, 1.0) * 0.12)
    d = 1.2
    x = np.zeros(int(SR * d))
    for k in range(3):
        place(x, lp(noise(0.25), 700) * env(int(SR * 0.25), 0.08, 0.12), k * 0.35)
    write("wings", x + whoosh(d, 300, 900) * 0.4)
    d = 3.0
    x = np.zeros(int(SR * d))
    at = 0.0
    while at < d - 0.1:
        for off in [0.0, 0.07, 0.16]:
            place(x, thump(0.1, 120) * 0.5, at + off)
        at += 0.36
    horn_t = t_of(1.6)
    horn = sum(np.sign(np.sin(2 * np.pi * f * horn_t)) * 0.2 for f in [220, 277, 330])
    horn = lp(horn, 1800) * env(len(horn_t), 0.15, 0.5)
    place(x, horn * 0.7, 0.2)
    write("valkyries", x)

    # ---------------------------------------------------------------- Rogue
    d = 1.4
    t = t_of(d)
    x = thump(0.2, 140) * 1.0
    x = fit(x, d)
    x += hp(noise(d), 1500) * env(len(t), 0.05, 1.1) * 0.6
    write("smoke_bomb", x)
    d = 0.7
    x = whoosh(0.25, 800, 4000)
    x = fit(x, d)
    for k in range(5):
        place(x, clang(0.25, 2600 + rng.random() * 1400) * 0.25, 0.22 + k * 0.06)
    write("pickpocket", x)
    d = 1.6
    t = t_of(d)
    write("thousand_cuts", whoosh(d, 300, 5000) * np.linspace(0.6, 1, len(t)) + sweep(200, 1600, d) * env(len(t), 0.2, 0.3) * 0.15)
    write("cut", whoosh(0.12, 1200, 6000), 0.6)

    # ---------------------------------------------------------------- Gaiden
    d = 0.7
    w = whoosh(0.4, 400, 3000)[::-1]
    x = fit(w, d)
    place(x, clang(0.3, 1900) * 0.5, 0.38)
    write("shadow_step", x)
    d = 2.1
    t = t_of(d)
    x = bp(noise(d), 1500, 4000) * (0.5 + 0.5 * np.sin(2 * np.pi * 28 * t)) * env(len(t), 0.1, 0.4)
    write("shuriken", x * 0.8)
    write("whirl", whoosh(0.18, 1500, 5000), 0.5)
    d = 2.0
    t = t_of(d)
    chord = sum(np.sin(2 * np.pi * f * t) for f in [110, 165, 220, 330]) * env(len(t), 0.4, 1.0) * 0.25
    write("reed_clones", chord + bp(noise(d), 500, 2000) * env(len(t), 0.2, 1.2) * 0.4)

    # ---------------------------------------------------------------- Dr. Croc
    d = 1.4
    x = np.zeros(int(SR * d))
    for k in range(3):   # gulps
        place(x, sweep(220, 110, 0.12) * env(int(SR * 0.12), 0.01, 0.08) * 0.7, 0.1 + k * 0.22)
    for k in range(14):   # bubbles
        f = 500 + rng.random() * 900
        place(x, sweep(f, f * 1.8, 0.05) * env(int(SR * 0.05), 0.005, 0.04) * 0.3, 0.75 + rng.random() * 0.6)
    write("mutagen", x)
    d = 1.3
    t = t_of(d)
    x = lp(noise(d), 900) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t)) * env(len(t), 0.05, 0.3)
    write("death_roll", x + bp(noise(d), 1500, 4000) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t + 1)) * 0.3)
    d = 2.6
    t = t_of(d)
    x = hp(noise(d), 2500) * np.exp(-t * 9) * 0.6
    for k in range(5):
        place(x, clang(0.3, 2400 + 600 * k) * 0.12, 0.02 * k)
    x += lp(noise(d), 700) * env(len(t), 0.1, 1.5) * 0.7
    for k in range(30):
        f = 300 + rng.random() * 700
        place(x, sweep(f, f * 1.6, 0.06) * env(int(SR * 0.06), 0.005, 0.05) * 0.25, 0.3 + rng.random() * 2.1)
    write("toxic_spill", x)


if __name__ == "__main__":
    main()
