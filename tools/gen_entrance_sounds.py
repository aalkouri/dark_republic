"""Synthesise the run-start entrance sounds (audio/entrances/<id>.wav), one per character,
each timed to its entrance in scripts/hero_entrances.gd (times below are seconds into it).

ice_wizard        frost crackling outward, a rising crystal shimmer, two cracks, a glass shatter (2.3)
dark_wizard       a low drone and whispers, a burst of crow wings and caws (~1.0), a dark pulse (2.5)
merlin            a reversed swell (cymbal and bells run backwards) into a twinkle (2.6), an owl's hoot
ogre              a deep rumble, a wet mud geyser (1.6), splats, a thud (2.54), a shake-off and grunt
ghast             wind rising, a wavering wail (1.1-2.4) and rattling chains, the wail's blast (2.5)
vampire_hunter    a growing flutter of bats with squeaks, a whoosh (2.0), crossbow twang and thunk
vicki             a choir swelling, a shimmer, the spear's impact and a ringing shockwave (2.6)
rogue             a lob and a clink (0.6), the fuse hissing, a smoke-bomb poof (1.0), a dagger's ring
gaiden            wind and leaves whirling, three blade slashes (1.6-1.9), a sheathing click (2.78)
dr_croc           fizzing, bubbling chemicals, a gurgle, a surging splash (1.9), a goggle snap
blob              gurgling bubbles, a rising glorp, a wet splort (2.5)
arachnid          silk creaking as it pays out, a twang as it lets go (2.3), a thump and a web puff
loco_robotico     rope creaks, a pop and a party horn (1.5), a box thud, boot-up beeps, a disco beat
toadstool_knight  mushrooms popping up in a run, a rubbery growth, a boing (2.05), a spore thump (2.5)
pharaoh           sand hissing into a whirlpool, stone grinding up, the lid's thud (2.2), scarabs skittering
necromancer       ghost-fire whooshing alight, a low moan, bones clattering up, stone cracking and bursting (1.95)
singe             a fuse fizzing in, a rising sizzle, a whoomp of flame (1.9) and a hot little landing
thog              a distant launch, a rising whoosh as he comes, a huge crash (2.45) and rubble

    python3 tools/gen_entrance_sounds.py
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/entrances/"
rng = np.random.default_rng(41)


class Snd(np.ndarray):
    """A mono sound: adding two of different lengths pads the shorter with silence."""

    def __add__(self, o):
        if isinstance(o, np.ndarray) and o.ndim == 1 and self.ndim == 1 and len(o) != len(self):
            out = np.zeros(max(len(self), len(o)))
            out[:len(self)] += np.asarray(self)
            out[:len(o)] += np.asarray(o)
            return out.view(Snd)
        return np.ndarray.__add__(self, o)

    __radd__ = __add__


def snd(x):
    return np.asarray(x, dtype=float).view(Snd)


def t_of(d):
    return snd(np.arange(int(SR * d)) / SR)


def lp(x, hz, o=3):
    return snd(sosfilt(butter(o, hz, "low", fs=SR, output="sos"), np.asarray(x)))


def hp(x, hz, o=2):
    return snd(sosfilt(butter(o, hz, "high", fs=SR, output="sos"), np.asarray(x)))


def bp(x, lo, hi, o=2):
    return snd(sosfilt(butter(o, [lo, min(hi, SR / 2 - 100)], "band", fs=SR, output="sos"), np.asarray(x)))


def noise(d):
    return snd(rng.standard_normal(int(SR * d)))


def env(n, a, r):
    e = np.ones(n)
    na = max(1, min(n, int(a * SR)))
    nr = max(1, min(n, int(r * SR)))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr) ** 1.5
    return snd(e)


def dec(d, k):
    """Exponential decay over d seconds at rate k."""
    return np.exp(-k * t_of(d))


def sweep(f0, f1, d, shape="sine"):
    f = snd(np.geomspace(f0, f1, int(SR * d)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    return np.sin(ph)


def tone(f, d, shape="sine", vib=0.0, vib_hz=5.0):
    t = t_of(d)
    ph = 2 * np.pi * np.cumsum(f * (1 + vib * np.sin(2 * np.pi * vib_hz * t))) / SR
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    return np.sin(ph)


def mix(*xs):
    """Sum sounds of different lengths (padded to the longest)."""
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[:len(x)] += x
    return out


def place(buf, snd, at, gain=1.0):
    i = int(at * SR)
    if i >= len(buf):
        return
    n = min(len(snd), len(buf) - i)
    buf[i:i + n] += snd[:n] * gain


def ramp(d, a, b, curve=1.0):
    return snd(np.linspace(0, 1, int(SR * d)) ** curve * (b - a) + a)


def ping(f, d=0.25, k=18.0):
    return np.sin(2 * np.pi * f * t_of(d)) * dec(d, k)


def thump(f0=90, f1=35, d=0.5, k=7.0):
    return sweep(f0, f1, d) * dec(d, k)


def burst(d, lo, hi, k):
    return bp(noise(d), lo, hi) * dec(d, k)


def flutter(d, rate, lo=300, hi=3000):
    t = t_of(d)
    am = (0.5 + 0.5 * np.sin(2 * np.pi * rate * t + rng.uniform(0, 6))) ** 3
    return bp(noise(d), lo, hi) * am


def pluck(f, d=0.6, damp=0.996):
    """Karplus-Strong string."""
    n = int(SR / f)
    buf = rng.uniform(-1, 1, n)
    out = np.zeros(int(SR * d))
    for i in range(len(out)):
        out[i] = buf[i % n]
        buf[i % n] = damp * 0.5 * (buf[i % n] + buf[(i + 1) % n])
    return snd(out)


def bubbles(buf, t0, t1, rate, f_lo, f_hi, gain=0.3, d=0.07):
    t = t0
    while t < t1:
        f = rng.uniform(f_lo, f_hi)
        place(buf, sweep(f, f * 2.2, d) * env(int(SR * d), 0.005, 0.03), t, gain * rng.uniform(0.5, 1.0))
        t += rng.exponential(1.0 / rate)


def save(name, x):
    x = x - np.mean(x)
    x = np.tanh(x / (np.max(np.abs(x)) + 1e-9) * 1.4) / np.tanh(1.4)
    n = int(0.02 * SR)
    x[-n:] *= np.linspace(1, 0, n)
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(OUT + name + ".wav", SR, (x * 0.9 * 32767).astype(np.int16))
    print("wrote", OUT + name + ".wav", "%.2f s" % (len(x) / SR))


def canvas(d):
    return np.zeros(int(SR * d))


# ------------------------------------------------------------------ characters

def ice_wizard():
    b = canvas(4.2)
    t = 0.0
    while t < 2.2:   # frost crackle racing out: dense tiny ticks
        place(b, hp(noise(0.006), 4000) * env(int(SR * 0.006), 0.0005, 0.004), t, rng.uniform(0.1, 0.35))
        t += rng.exponential(0.012 if t < 0.9 else 0.03)
    place(b, hp(noise(1.2), 5000) * env(int(SR * 1.2), 0.05, 0.6), 0.0, 0.12)
    grow = sum(np.sin(2 * np.pi * np.cumsum(np.geomspace(f, f * 2.0, int(SR * 1.7))) / SR) for f in (880, 1108, 1320))
    place(b, grow * env(len(grow), 0.5, 0.3) * 0.12, 0.55)
    for at in (1.75, 2.05):
        place(b, burst(0.12, 1500, 9000, 40) + ping(2400, 0.12, 40) * 0.4, at, 0.5)
    shat = burst(0.6, 2000, 12000, 9) * 0.9 + thump(140, 60, 0.4, 10) * 0.6
    place(b, shat, 2.3, 1.0)
    for k in range(40):   # glass pings in the shatter
        place(b, ping(rng.uniform(2500, 7500), 0.35, rng.uniform(12, 30)), 2.3 + rng.uniform(0, 0.4), 0.25)
    for k in range(24):   # shards tinkling down
        place(b, ping(rng.uniform(3000, 8000), 0.2, 30), 2.6 + rng.uniform(0, 1.2), 0.12)
    save("ice_wizard", b)


def caw(d=0.28):
    t = t_of(d)
    f = 520 * (1 - 0.25 * t / d) * (1 + 0.04 * np.sin(2 * np.pi * 30 * t))
    x = 2 * ((np.cumsum(f) / SR) % 1.0) - 1
    x = bp(x, 700, 2400) + bp(x, 1600, 3200) * 0.6
    return x * env(len(t), 0.02, 0.12)


def dark_wizard():
    b = canvas(4.3)
    d = 3.8
    drone = sum(tone(f, d, "saw") for f in (55, 55.4, 82.5))
    place(b, lp(drone, 220) * env(int(SR * d), 0.8, 1.0) * 0.35, 0.0)
    wh = bp(noise(3.0), 1800, 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * 3.3 * t_of(3.0))) ** 2
    place(b, wh * env(len(wh), 0.4, 0.8) * 0.18, 0.2)
    place(b, flutter(1.6, 16, 400, 4000) * env(int(SR * 1.6), 0.05, 0.9) * 0.7, 0.9)
    place(b, flutter(1.4, 21, 300, 3000) * env(int(SR * 1.4), 0.05, 0.9) * 0.5, 0.95)
    for at in (1.0, 1.25, 1.5, 1.85, 2.2):
        place(b, caw(), at, 0.45 * rng.uniform(0.7, 1.0))
    rise = lp(noise(1.3), 300) * env(int(SR * 1.3), 0.6, 0.2)
    place(b, rise * 0.35, 1.2)
    pulse = thump(70, 30, 0.9, 4) + lp(burst(0.5, 100, 1200, 6), 900) * 0.5
    place(b, pulse, 2.5, 1.0)
    save("dark_wizard", b)


def merlin():
    b = canvas(4.4)
    d = 2.45
    swell = hp(noise(d), 3000) * ramp(d, 0, 1, 3.0)   # reversed cymbal
    place(b, swell * 0.5, 2.6 - d)
    for k, f in enumerate((523, 659, 784, 1047, 1319, 1568)):   # bells, run backwards
        bell = ping(f, 0.9, 4)[::-1] * 0.25
        place(b, bell, 0.5 + k * 0.3 - 0.9 + 0.9, 1.0)
    rev = lp(noise(2.0), 1200)[::-1] * ramp(2.0, 0, 1, 2.5)
    place(b, rev * 0.3, 0.6)
    for f, at in ((2093, 2.6), (2637, 2.66), (3136, 2.72), (4186, 2.8)):
        place(b, ping(f, 0.9, 5) + ping(f * 2.01, 0.5, 9) * 0.3, at, 0.35)
    for at in (2.85, 3.15):   # the owl: hoo... hoo
        h = tone(370, 0.32) * env(int(SR * 0.32), 0.08, 0.15) + tone(740, 0.32) * 0.15 * env(int(SR * 0.32), 0.08, 0.15)
        place(b, lp(h + bp(noise(0.32), 300, 900) * 0.1, 1500), at, 0.4)
    place(b, flutter(0.8, 9, 200, 1500) * env(int(SR * 0.8), 0.05, 0.5) * 0.25, 2.9)
    save("merlin", b)


def ogre():
    b = canvas(4.4)
    rum = lp(noise(1.7), 90) * ramp(1.7, 0.2, 1.0, 1.5)
    place(b, rum * 1.6, 0.0)
    bubbles(b, 0.4, 1.6, 9, 60, 180, 0.35, 0.09)
    boom = thump(110, 30, 1.0, 4) * 1.2 + lp(burst(0.9, 80, 2500, 5), 1400) + sweep(400, 80, 0.5) * dec(0.5, 6) * 0.4
    place(b, boom, 1.6, 1.0)
    for k in range(26):   # mud splats coming down
        place(b, lp(burst(0.1, 200, 2000, 35), 1500), 1.8 + rng.uniform(0, 1.2), rng.uniform(0.15, 0.4))
    place(b, thump(90, 40, 0.4, 9) + lp(burst(0.2, 100, 1500, 20), 800) * 0.5, 2.54, 0.8)
    place(b, flutter(0.55, 14, 300, 2500) * env(int(SR * 0.55), 0.02, 0.2) * 0.6, 2.75)
    g = tone(105, 0.6, "saw", vib=0.04, vib_hz=7) * env(int(SR * 0.6), 0.05, 0.3)
    place(b, bp(g, 150, 900) + lp(g, 400) * 0.5, 2.9, 0.5)
    save("ogre", b)


def ghast():
    b = canvas(4.4)
    d = 2.6
    t = t_of(d)
    wind = bp(noise(d), 300, 1400) * (0.4 + 0.6 * ramp(d, 0, 1)) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.7 * t))
    place(b, wind * env(len(t), 0.4, 0.4) * 0.45, 0.0)
    d = 1.5
    t = t_of(d)
    f = 520 + 140 * np.sin(np.pi * t / d) + 18 * np.sin(2 * np.pi * 6 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    wail = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    place(b, (wail + bp(noise(d), 400, 2500) * 0.2) * env(len(t), 0.25, 0.35) * 0.45, 1.1)
    for k in range(22):   # chains
        at = 1.2 + rng.uniform(0, 1.6)
        clink = sum(ping(rng.uniform(1800, 5200), 0.15, 35) for _ in range(3))
        place(b, clink, at, 0.12)
    blast = bp(noise(0.9), 200, 3000) * dec(0.9, 4) + thump(80, 40, 0.5, 8) * 0.6
    place(b, blast, 2.5, 0.9)
    save("ghast", b)


def vampire_hunter():
    b = canvas(4.2)
    for k in range(5):
        fl = flutter(2.2, rng.uniform(15, 24), 500, 5000) * ramp(2.2, 0.1, 1.0, 1.2)
        place(b, fl, 0.0 + k * 0.05, 0.28)
    for k in range(14):   # squeaks
        sq = sweep(rng.uniform(4500, 6500), rng.uniform(3500, 5500), 0.05) * env(int(SR * 0.05), 0.005, 0.02)
        place(b, sq, rng.uniform(0.3, 2.6), 0.15)
    place(b, bp(noise(0.8), 300, 3000) * env(int(SR * 0.8), 0.02, 0.6) * 0.8, 2.0)
    place(b, flutter(1.4, 20, 500, 5000) * env(int(SR * 1.4), 0.01, 1.2) * 0.5, 2.0)
    tw = pluck(165, 0.6, 0.994) * 0.8 + burst(0.03, 2000, 8000, 80) * 0.5
    place(b, tw, 2.38, 0.8)
    place(b, thump(220, 90, 0.15, 30) + burst(0.08, 300, 2500, 50) * 0.6, 2.47, 0.8)
    save("vampire_hunter", b)


def vicki():
    b = canvas(4.4)
    d = 3.0
    choir = np.zeros(int(SR * d))
    for f in (220, 277.2, 329.6, 440, 554.4):
        for det in (0.997, 1.003):
            choir += tone(f * det, d, "saw", vib=0.006, vib_hz=5.2 + rng.uniform(-0.4, 0.4))
    choir = bp(choir, 300, 1400) + bp(choir, 2400, 3200) * 0.3   # "aah" formants
    place(b, choir * env(len(choir), 1.2, 0.6) * 0.12, 0.0)
    for k in range(10):
        place(b, ping(rng.uniform(2000, 4500), 0.6, 6), 0.3 + rng.uniform(0, 2.0), 0.06)
    hit = thump(120, 40, 0.7, 6) + lp(burst(0.3, 200, 3000, 12), 2500) * 0.6
    place(b, hit, 2.6, 1.0)
    ringing = sum(ping(f, 1.4, 3) for f in (880, 1320, 1760, 2640))
    place(b, ringing * 0.15, 2.6)
    save("vicki", b)


def rogue():
    b = canvas(4.1)
    place(b, bp(noise(0.6), 400, 3000) * env(int(SR * 0.6), 0.3, 0.2) * 0.3, 0.0)
    place(b, ping(1700, 0.12, 40) + ping(2500, 0.1, 50) * 0.5 + thump(200, 100, 0.1, 40) * 0.5, 0.6, 0.5)
    place(b, hp(noise(0.4), 3000) * env(int(SR * 0.4), 0.02, 0.1) * 0.12, 0.62)
    hiss = hp(noise(0.5), 4000) * (0.6 + 0.4 * np.sin(2 * np.pi * 40 * t_of(0.5)))
    place(b, hiss * 0.18, 0.5)
    poof = lp(noise(1.2), 900) * dec(1.2, 3.5) * 1.2 + thump(120, 50, 0.4, 10) * 0.7
    place(b, poof, 1.0, 1.0)
    place(b, hp(noise(1.6), 1500) * env(int(SR * 1.6), 0.05, 1.2) * 0.12, 1.1)
    shing = sum(ping(f, 0.5, 9) for f in (3200, 4300, 5100)) * 0.3 + bp(noise(0.15), 2000, 8000) * dec(0.15, 25) * 0.4
    place(b, shing, 2.3, 0.6)
    place(b, ping(2600, 0.06, 80) + thump(400, 200, 0.05, 60) * 0.4, 2.95, 0.5)
    save("rogue", b)


def swish(d=0.18):
    t = t_of(d)
    f = np.geomspace(800, 6000, len(t))
    x = bp(noise(d), 1500, 7000) * np.sin(np.pi * t / d) ** 2
    return x


def gaiden():
    b = canvas(4.0)
    d = 2.0
    w = bp(noise(d), 300, 2000) * ramp(d, 0.2, 1.0, 1.3) * (0.7 + 0.3 * np.sin(2 * np.pi * 3.5 * t_of(d)))
    place(b, w * env(len(w), 0.2, 0.15) * 0.5, 0.0)
    rustle = hp(noise(d), 2500) * (0.5 + 0.5 * np.sin(2 * np.pi * 11 * t_of(d))) ** 4
    place(b, rustle * 0.2, 0.0)
    for at in (1.6, 1.74, 1.88):
        sl = swish(0.12) * 0.9 + sum(ping(f, 0.3, 14) for f in (2800, 3700)) * 0.15
        place(b, sl, at, 0.8)
    place(b, bp(noise(1.2), 600, 4000) * dec(1.2, 3) * 0.3, 1.95)
    for k, at in enumerate((2.74, 2.78)):
        place(b, ping(3000 - k * 800, 0.05, 90) + burst(0.02, 2000, 9000, 120) * 0.4, at, 0.5)
    save("gaiden", b)


def dr_croc():
    b = canvas(4.3)
    fizz = hp(noise(2.8), 5000) * env(int(SR * 2.8), 0.4, 0.6)
    t = 0.0
    crackle = np.zeros(int(SR * 2.8))
    while t < 2.75:
        place(crackle, hp(noise(0.004), 3000), t, rng.uniform(0.2, 0.6))
        t += rng.exponential(0.01)
    place(b, (fizz * 0.1 + crackle * 0.25), 0.1)
    bubbles(b, 0.2, 2.9, 14, 250, 900, 0.22, 0.06)
    place(b, lp(sweep(160, 70, 0.6, "saw"), 500) * env(int(SR * 0.6), 0.1, 0.3) * 0.4, 0.85)
    splash = lp(burst(1.0, 150, 5000, 4.5), 4000) * 1.1 + thump(100, 45, 0.4, 9) * 0.6
    place(b, splash, 1.9, 1.0)
    bubbles(b, 1.95, 2.6, 25, 300, 1200, 0.3, 0.05)
    snap = sweep(900, 300, 0.06) * dec(0.06, 50) + burst(0.03, 1500, 6000, 100) * 0.4
    place(b, snap, 2.85, 0.5)
    save("dr_croc", b)


def boing(f0=180, d=0.5, depth=0.3):
    t = t_of(d)
    f = f0 * (1 + depth * np.sin(2 * np.pi * 9 * t) * np.exp(-5 * t)) * (1 + 0.6 * t)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * dec(d, 5)


def blob():
    b = canvas(4.2)
    bubbles(b, 0.05, 2.5, 10, 70, 260, 0.45, 0.12)
    d = 1.3
    t = t_of(d)
    f = np.geomspace(110, 380, len(t)) * (1 + 0.12 * np.sin(2 * np.pi * 7 * t))
    glorp = np.sin(2 * np.pi * np.cumsum(f) / SR)
    place(b, lp(glorp, 900) * env(len(t), 0.2, 0.2) * 0.45, 1.15)
    splort = lp(burst(0.5, 100, 2500, 9), 1800) * 1.0 + sweep(500, 120, 0.25) * dec(0.25, 12) * 0.5
    place(b, splort, 2.5, 1.0)
    for k in range(10):
        place(b, lp(burst(0.07, 200, 1500, 40), 1200), 2.6 + rng.uniform(0, 0.7), 0.2)
    save("blob", b)


def arachnid():
    b = canvas(4.2)
    d = 2.0
    t = t_of(d)
    f = np.geomspace(2600, 900, len(t))
    zip_ = bp(noise(d), 600, 4000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * np.cumsum(f / 40.0) / SR)))
    place(b, zip_ * env(len(t), 0.05, 0.3) * 0.25, 0.0)
    for k in range(4):   # tension creaks
        cr = sweep(rng.uniform(300, 500), rng.uniform(200, 300), 0.12, "saw") * env(int(SR * 0.12), 0.02, 0.05)
        place(b, bp(cr, 300, 2500), 1.9 + k * 0.1, 0.25)
    place(b, pluck(330, 0.4, 0.99) * 0.6, 2.3)
    place(b, bp(noise(0.3), 400, 2500) * np.sin(np.pi * t_of(0.3) / 0.3) * 0.3, 2.3)
    place(b, thump(130, 50, 0.4, 10) + lp(burst(0.4, 200, 3000, 8), 2000) * 0.6, 2.6, 0.9)
    save("arachnid", b)


def loco_robotico():
    b = canvas(4.4)
    for at in (0.05, 1.0):
        cr = bp(tone(140, 0.4, "saw", vib=0.08, vib_hz=6), 300, 2000) * env(int(SR * 0.4), 0.05, 0.2)
        place(b, cr, at, 0.18)
    place(b, bp(noise(1.4), 400, 1800) * np.sin(np.pi * t_of(1.4) / 1.4) * 0.25, 0.0)
    pop = lp(burst(0.3, 100, 5000, 14), 4000) * 1.0 + thump(150, 60, 0.2, 15) * 0.5
    place(b, pop, 1.5, 1.0)
    horn = tone(440, 0.55, "saw", vib=0.01, vib_hz=8) * env(int(SR * 0.55), 0.02, 0.2)
    place(b, bp(horn, 400, 3500), 1.53, 0.5)
    for k in range(18):
        place(b, ping(rng.uniform(3000, 7000), 0.1, 40), 1.55 + rng.uniform(0, 0.8), 0.08)
    place(b, thump(140, 70, 0.2, 18) + lp(burst(0.1, 200, 1500, 30), 1000) * 0.5, 1.82, 0.6)
    place(b, lp(burst(0.12, 300, 2000, 30), 1500), 2.0, 0.3)
    for k, f in enumerate((523, 659, 784, 1047)):
        bp_ = tone(f, 0.09, "square") * env(int(SR * 0.09), 0.003, 0.03)
        place(b, lp(bp_, 4000), 2.1 + k * 0.1, 0.25)
    place(b, sweep(200, 1600, 0.4, "square") * env(int(SR * 0.4), 0.01, 0.1) * 0.12, 2.15)
    beat = 60.0 / 128
    t = 2.45
    k = 0
    while t < 4.3:   # disco beat
        place(b, thump(130, 45, 0.25, 14), t, 0.6)
        place(b, hp(noise(0.05), 7000) * dec(0.05, 60), t + beat / 2, 0.2)
        t += beat
        k += 1
    save("loco_robotico", b)


def toadstool_knight():
    b = canvas(4.2)
    for k in range(13):
        at = 0.05 + 0.9 * k / 13
        f = 300 * 2 ** (k / 13.0)
        place(b, sweep(f, f * 1.8, 0.08) * env(int(SR * 0.08), 0.003, 0.05) + burst(0.04, 800, 3000, 60) * 0.3, at, 0.35)
    d = 0.9
    t = t_of(d)
    f = np.geomspace(90, 260, len(t)) * (1 + 0.1 * np.sin(2 * np.pi * 6 * t))
    place(b, lp(np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * (2 * ((np.cumsum(f) / SR) % 1.0) - 1), 1200) * env(len(t), 0.1, 0.2) * 0.35, 0.6)
    place(b, boing(200, 0.45, 0.45), 2.05, 0.6)
    place(b, bp(noise(0.45), 500, 3000) * np.sin(np.pi * t_of(0.45) / 0.45) * 0.35, 2.05)
    place(b, thump(140, 50, 0.4, 10) + lp(burst(0.6, 300, 4000, 6), 3000) * 0.5, 2.5, 0.9)
    for k in range(12):
        place(b, ping(rng.uniform(2000, 5000), 0.3, 10), 2.55 + rng.uniform(0, 0.8), 0.05)
    save("toadstool_knight", b)


def thog():
    b = canvas(4.4)
    place(b, lp(thump(80, 40, 0.6, 7), 300) * 0.4 + lp(burst(0.4, 100, 900, 9), 600) * 0.2, 0.45)
    d = 2.0
    t = t_of(d)
    f = np.geomspace(250, 900, len(t))
    wh = bp(noise(d), 200, 2500) * ramp(d, 0.05, 1.0, 2.5)
    place(b, wh * 0.55, 0.45)
    crash = thump(80, 25, 1.4, 3.0) * 1.5 + lp(burst(1.2, 60, 3000, 4), 2000) * 1.0 + burst(0.3, 1500, 8000, 14) * 0.3
    place(b, crash, 2.45, 1.0)
    place(b, lp(noise(1.6), 120) * dec(1.6, 2.5) * 1.2, 2.5)
    for k in range(30):   # rubble
        place(b, lp(burst(0.08, 300, 3000, 40), 2500), 2.6 + rng.uniform(0, 1.3), rng.uniform(0.1, 0.35))
    g = tone(85, 0.8, "saw", vib=0.05, vib_hz=9) * env(int(SR * 0.8), 0.1, 0.4)
    place(b, bp(g, 120, 800) + lp(g, 300) * 0.6, 2.85, 0.45)
    save("thog", b)


def pharaoh():
    b = canvas(4.4)
    d = 2.2
    hiss = bp(noise(d), 1500, 7000) * (0.6 + 0.4 * np.sin(2 * np.pi * 2.5 * t_of(d)))
    place(b, hiss * env(int(SR * d), 0.3, 0.4) * 0.35, 0.0)
    grind = lp(noise(1.2), 400) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 13 * t_of(1.2))))
    place(b, (grind + tone(55, 1.2, "saw") * 0.3) * env(int(SR * 1.2), 0.1, 0.2) * 0.6, 0.5)
    place(b, thump(110, 40, 0.6, 7) + lp(burst(0.5, 150, 3000, 7), 2000) * 0.8, 2.2, 1.0)
    for k in range(40):
        place(b, hp(noise(0.012), 2500) * env(int(SR * 0.012), 0.002, 0.006), 2.25 + rng.uniform(0, 1.4), 0.25)
    chord = sum(tone(f, 1.2) for f in (220, 261.6, 311.1)) * env(int(SR * 1.2), 0.3, 0.6)
    place(b, lp(chord, 1200) * 0.15, 2.1)
    save("pharaoh", b)


def necromancer():
    b = canvas(4.4)
    place(b, bp(noise(0.8), 200, 2000) * env(int(SR * 0.8), 0.3, 0.3) * 0.5, 0.0)
    d = 3.0
    moan = sum(tone(f, d, vib=0.02, vib_hz=3.0) for f in (110, 164.8, 220)) * env(int(SR * d), 0.6, 0.8)
    place(b, lp(moan, 900) * 0.3, 0.2)
    for k in range(18):   # bones clattering
        place(b, ping(rng.uniform(900, 2200), 0.06, 70) + burst(0.03, 1000, 5000, 90) * 0.4, 0.4 + rng.uniform(0, 1.1), 0.25)
    for at in (1.4, 1.7):
        place(b, burst(0.1, 800, 6000, 40) * 0.6 + thump(200, 90, 0.1, 30) * 0.3, at, 0.5)
    place(b, thump(90, 35, 0.8, 5) + lp(burst(0.7, 100, 4000, 6), 3000) * 0.9 + burst(0.2, 2000, 8000, 20) * 0.3, 1.95, 1.0)
    for k in range(20):
        place(b, lp(burst(0.08, 300, 3000, 40), 2500), 2.05 + rng.uniform(0, 1.0), rng.uniform(0.1, 0.3))
    save("necromancer", b)


def singe():
    b = canvas(4.0)
    t = 0.0
    while t < 1.6:   # the fuse: dense crackle
        place(b, hp(noise(0.005), 3000) * env(int(SR * 0.005), 0.0005, 0.003), t, rng.uniform(0.15, 0.4))
        t += rng.exponential(0.008)
    place(b, hp(noise(1.6), 4000) * ramp(1.6, 0.2, 0.6) * 0.2, 0.0)
    place(b, bp(noise(0.6), 300, 2500) * ramp(0.6, 0.0, 1.0, 2.0) * 0.4, 1.3)
    whoomp = lp(noise(0.9), 1200) * dec(0.9, 4) * 1.2 + thump(100, 45, 0.5, 7) * 0.8
    place(b, whoomp, 1.9, 1.0)
    roar = bp(noise(0.8), 200, 1800) * env(int(SR * 0.8), 0.05, 0.5)
    place(b, roar * 0.5, 1.95)
    place(b, thump(160, 80, 0.15, 25) + hp(noise(0.3), 3000) * dec(0.3, 10) * 0.3, 2.45, 0.6)
    save("singe", b)


if __name__ == "__main__":
    for f in (ice_wizard, dark_wizard, merlin, ogre, ghast, vampire_hunter, vicki, rogue, gaiden,
              dr_croc, blob, arachnid, loco_robotico, toadstool_knight, thog, pharaoh, necromancer, singe):
        f()
