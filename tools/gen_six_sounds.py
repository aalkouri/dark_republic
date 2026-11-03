"""Synthesise the sounds of the last six characters' abilities (audio/abilities/).

Death:          harvest (a cold whoosh and a chime), mark (a deep bell), death_toll (a struck
                bell as a mark comes due), overtime (a slowing clock tick and a low drone)
Billy Bulldog:  fetch (a whistle and a swish), boom (an explosion thump), zoomies (scrabbling
                paws and a whoosh), good_boy (a happy whine), bark (a big woof)
Cowboy:         lasso (a rope whirling), dynamite (a fuse hiss), high_noon (a long whistled
                note over a gong), gunshots (a rapid volley of shots)
Platypus:       electro_bill (an electric zap), eggs (soft plops), pop (a popping burst),
                lecture (a drowsy descending tone)
Bog Witch:      cauldron (bubbling), hex (a dark whisper chord), swamp_fury (a deep bog
                gurgle and rumble), bile_throw (a wet slosh and glugs) and bile_splash (a splat,
                an acid sizzle and a puff of smoke) for her Ladle of Bile
Kong:           chest_pound (three hollow drum thumps), log_toss (a heave and a rolling
                rumble), rampage (a roar)

Entrances (audio/entrances/<id>.wav, timed to HeroEntrances' timelines): death (mist and a toll),
billy_bulldog (digging and a bark), cowboy (wind and jingling spurs), platypus (a splash),
bog_witch (bubbling bog), kong (a whistling drop and a huge landing).

    python3 tools/gen_six_sounds.py
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/abilities/"
R = np.random.default_rng(66)


def t_of(d):
    return np.arange(int(SR * d)) / SR


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, min(hi, SR / 2 - 100)], "band", fs=SR, output="sos"), x)


def lp(x, hz, o=2):
    return sosfilt(butter(o, hz, "low", fs=SR, output="sos"), x)


def noise(d):
    return R.standard_normal(int(SR * d))


def env(d, a=0.01, r=None):
    t = t_of(d)
    e = np.minimum(1.0, t / max(a, 1e-4))
    if r is not None:
        e *= np.exp(-t / r)
    return e


def place(buf, snd, at):
    i = int(at * SR)
    n = min(len(snd), len(buf) - i)
    if n > 0:
        buf[i:i + n] += snd[:n]


def bell(f, d, decay, amp=1.0):
    t = t_of(d)
    x = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * decay * dm) for r, a, dm in
            [(1.0, 1.0, 1.0), (2.0, 0.5, 1.4), (2.76, 0.35, 1.8), (5.4, 0.15, 2.6)])
    return x * np.minimum(1.0, t / 0.003) * amp


def thump(f0, d, amp=1.0):
    t = t_of(d)
    f = f0 * (1.0 + 1.5 * np.exp(-t * 30))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 9) * amp


def whoosh(d, lo, hi, amp=0.5):
    n = noise(d)
    e = np.sin(np.pi * np.linspace(0, 1, len(n))) ** 2
    return bp(n, lo, hi) * e * amp


def save(name, x, peak=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    f = int(SR * 0.02)
    x[-f:] *= np.linspace(1, 0, f)
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(OUT + name + ".wav", SR, (x * 32767).astype(np.int16))


def sweep(f0, f1, d, amp=1.0):
    t = t_of(d)
    f = np.geomspace(f0, f1, len(t))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * amp


def main():
    # --- Death
    b = np.zeros(int(SR * 1.4))
    place(b, whoosh(0.7, 300, 3000, 0.7), 0.0)
    place(b, bell(1320, 1.0, 4.0, 0.4), 0.35)
    save("harvest", b)
    save("mark", bell(196, 2.2, 1.2) + bell(392, 2.2, 1.6, 0.3))
    save("death_toll", bell(262, 1.6, 2.0) * 0.9)
    b = np.zeros(int(SR * 2.2))
    for k, at in enumerate([0.0, 0.35, 0.8, 1.4]):
        place(b, bp(noise(0.03), 2000, 6000) * env(0.03, 0.001, 0.01), at)
    place(b, np.sin(2 * np.pi * 55 * t_of(2.2)) * np.minimum(1, t_of(2.2) / 0.3) * np.exp(-t_of(2.2) * 0.8) * 0.6, 0.0)
    save("overtime", b)
    # --- Billy Bulldog
    b = np.zeros(int(SR * 0.8))
    place(b, sweep(1400, 2600, 0.25, 0.5) * env(0.25, 0.02), 0.0)
    place(b, whoosh(0.4, 600, 4000, 0.5), 0.2)
    save("fetch", b)
    save("boom", thump(55, 1.0, 1.0) + lp(noise(1.0), 900) * env(1.0, 0.005, 0.25) * 2.0)
    b = np.zeros(int(SR * 1.0))
    for k in range(10):
        place(b, bp(noise(0.02), 800, 4000) * env(0.02, 0.001, 0.008), k * 0.05)
    place(b, whoosh(0.6, 400, 3000, 0.6), 0.3)
    save("zoomies", b)
    save("good_boy", sweep(700, 1400, 0.25, 0.4) * env(0.25, 0.02) + np.concatenate([np.zeros(int(SR * 0.25)), sweep(1300, 800, 0.4, 0.4) * env(0.4, 0.02, 0.3)])[:int(SR * 0.25)])
    t = t_of(0.35)
    woof = bp(noise(0.35) * 0.6 + np.sin(2 * np.pi * 180 * t * (1 - 0.3 * t)) * 0.8, 150, 1800) * env(0.35, 0.01, 0.12)
    save("bark", woof)
    # --- Cowboy
    t = t_of(1.2)
    save("lasso", bp(noise(1.2), 300, 1500) * (0.5 + 0.5 * np.sin(2 * np.pi * 5 * t) ** 2) * np.minimum(1, t / 0.2))
    save("dynamite", bp(noise(1.0), 3000, 9000) * (0.6 + 0.4 * (R.random(int(SR * 1.0)) < 0.05)) * np.minimum(1, t_of(1.0) / 0.05), 0.5)
    b = np.zeros(int(SR * 2.4))
    place(b, np.sin(2 * np.pi * 1760 * t_of(1.2) + 3 * np.sin(2 * np.pi * 5 * t_of(1.2))) * env(1.2, 0.1) * np.linspace(1, 0.3, int(SR * 1.2)) * 0.4, 0.0)
    place(b, bell(110, 1.6, 1.5, 0.8), 0.9)
    save("high_noon", b)
    b = np.zeros(int(SR * 1.6))
    for k in range(10):
        place(b, (lp(noise(0.2), 2500) * 1.5 + thump(90, 0.2, 0.6)) * env(0.2, 0.001, 0.04), k * 0.11 + R.uniform(0, 0.02))
    save("gunshots", b)
    # --- Platypus
    t = t_of(0.5)
    save("electro_bill", (np.sign(np.sin(2 * np.pi * 70 * t)) * 0.3 + bp(noise(0.5), 2000, 8000)) * env(0.5, 0.005, 0.15))
    b = np.zeros(int(SR * 0.8))
    for k in range(4):
        place(b, thump(320 + 40 * k, 0.15, 0.6), k * 0.12)
    save("eggs", b)
    save("pop", bp(noise(0.25), 400, 5000) * env(0.25, 0.002, 0.05) + thump(150, 0.25, 0.5))
    save("lecture", sweep(520, 260, 1.8, 0.5) * env(1.8, 0.1) * np.linspace(1, 0.2, int(SR * 1.8)))
    # --- Bog Witch
    b = np.zeros(int(SR * 1.5))
    for k in range(14):
        f = R.uniform(180, 420)
        place(b, sweep(f, f * 1.8, 0.06, 0.4) * env(0.06, 0.005, 0.03), R.uniform(0, 1.4))
    save("cauldron", b)
    t = t_of(1.4)
    chord = sum(np.sin(2 * np.pi * f * t) for f in (110, 131, 156)) * np.minimum(1, t / 0.3) * np.exp(-t * 1.2)
    save("hex", chord * 0.5 + bp(noise(1.4), 1500, 5000) * np.sin(np.pi * t / 1.4) * 0.25)
    b = lp(noise(2.5), 120, 4) * 5.0 * np.minimum(1, t_of(2.5) / 0.4) * np.exp(-t_of(2.5) * 0.6)
    for k in range(10):
        place(b, sweep(90, 200, 0.12, 0.5) * env(0.12, 0.01, 0.06), R.uniform(0.1, 2.2))
    save("swamp_fury", b)
    # --- Kong
    b = np.zeros(int(SR * 1.3))
    for k in range(3):
        place(b, thump(75, 0.4, 1.0) + lp(noise(0.4), 500) * env(0.4, 0.002, 0.06), k * 0.35)
    save("chest_pound", b)
    b = np.zeros(int(SR * 1.8))
    place(b, whoosh(0.4, 200, 1500, 0.8), 0.0)
    place(b, lp(noise(1.4), 250) * 3.0 * np.minimum(1, t_of(1.4) / 0.1) * np.exp(-t_of(1.4) * 1.2), 0.3)
    save("log_toss", b)
    t = t_of(1.4)
    f = 110 + 40 * np.sin(np.pi * t / 1.4)
    roar = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.6 + bp(noise(1.4), 200, 2500) * 0.8
    save("rampage", lp(roar, 2500) * np.minimum(1, t / 0.1) * np.exp(-t * 1.0))
    bile()


def bile():
    """The Bog Witch's Ladle of Bile: bile_throw (a wet slosh as the ladle flings a glob, a
    couple of glugs), bile_splash (a wet splat, an acid sizzle that crackles away and a soft
    puff of smoke)."""
    r = np.random.default_rng(77)
    b = np.zeros(int(SR * 0.45))
    # the slosh: a band of liquid noise swelling and falling, wobbling like liquid in a ladle
    d = 0.32
    t = t_of(d)
    slosh = bp(r.standard_normal(len(t)), 250, 1400) * np.sin(np.pi * t / d) ** 1.5
    slosh *= 0.7 + 0.3 * np.sin(2 * np.pi * 14 * t)
    place(b, slosh * 0.9, 0.0)
    # two glugs: short resonant blips sweeping up, like bubbles leaving the ladle
    for at, f in [(0.05, 260), (0.14, 340)]:
        place(b, sweep(f, f * 2.2, 0.07, 0.5) * env(0.07, 0.004, 0.025), at)
    save("bile_throw", b, 0.7)
    b = np.zeros(int(SR * 1.3))
    # the splat: a wet low thud with a smack of mid noise
    place(b, thump(110, 0.25, 0.8) + bp(r.standard_normal(int(SR * 0.25)), 300, 2500) * env(0.25, 0.002, 0.05) * 1.4, 0.0)
    # the sizzle: bright hissing noise that crackles (random pops) and dies away
    d = 1.15
    t = t_of(d)
    hiss = bp(r.standard_normal(len(t)), 3500, 11000) * np.exp(-t * 2.4) * np.minimum(1, t / 0.03)
    crackle = (r.random(len(t)) < 0.004) * r.uniform(0.5, 1.0, len(t))
    crackle = bp(crackle, 2000, 9000) * np.exp(-t * 2.0) * 6.0
    place(b, (hiss * 0.55 + crackle * 0.5), 0.04)
    # the puff: a soft low whoomp of air as the smoke goes up
    d = 0.5
    t = t_of(d)
    puff = lp(r.standard_normal(len(t)), 500) * np.sin(np.pi * t / d) ** 2 * 1.6
    place(b, puff, 0.08)
    save("bile_splash", b, 0.75)


def entrances():
    global OUT
    OUT = "audio/entrances/"
    b = np.zeros(int(SR * 3.4))
    place(b, whoosh(2.2, 200, 1500, 0.5), 0.0)
    place(b, bell(196, 1.2, 2.0, 0.9), 2.2)
    save("death", b)
    b = np.zeros(int(SR * 3.2))
    for k in range(24):
        place(b, lp(noise(0.05), 1500) * env(0.05, 0.002, 0.02), 0.2 + k * 0.055)
    t = t_of(0.35)
    place(b, bp(noise(0.35) * 0.6 + np.sin(2 * np.pi * 180 * t * (1 - 0.3 * t)) * 0.8, 150, 1800) * env(0.35, 0.01, 0.12), 1.7)
    save("billy_bulldog", b)
    b = np.zeros(int(SR * 3.4))
    place(b, bp(noise(2.2), 300, 1200) * np.sin(np.pi * np.linspace(0, 1, int(SR * 2.2))) * 0.6, 0.0)
    for k in range(4):
        place(b, bell(3200 + 300 * k, 0.3, 14.0, 0.25), 1.9 + k * 0.28)
    save("cowboy", b)
    b = np.zeros(int(SR * 3.2))
    place(b, bp(noise(0.8), 300, 4000) * env(0.8, 0.005, 0.2) * 1.2, 1.7)
    for k in range(12):
        place(b, sweep(R.uniform(400, 900), R.uniform(900, 1600), 0.05, 0.3) * env(0.05, 0.005, 0.02), 1.75 + R.uniform(0, 0.6))
    save("platypus", b)
    b = np.zeros(int(SR * 3.4))
    for k in range(30):
        f = R.uniform(140, 380)
        place(b, sweep(f, f * 1.8, 0.07, 0.4) * env(0.07, 0.005, 0.035), R.uniform(0.0, 2.6))
    place(b, lp(noise(1.0), 300) * env(1.0, 0.02, 0.3) * 2.0, 2.1)
    save("bog_witch", b)
    b = np.zeros(int(SR * 3.2))
    place(b, sweep(2400, 500, 1.6, 0.25) * np.linspace(0.2, 1, int(SR * 1.6)), 0.3)
    place(b, thump(50, 1.2, 1.6) + lp(noise(1.2), 400) * env(1.2, 0.002, 0.3) * 2.5, 1.9)
    save("kong", b)


if __name__ == "__main__":
    main()
    entrances()
