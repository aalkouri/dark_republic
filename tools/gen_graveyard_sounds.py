"""Synthesise the Haunted Graveyard's sounds (no samples needed).

audio/graveyard/wail.wav          - a ghost's wail: a breathy hollow "ooo" gliding up and down
                                    with a slow wobble, in a big cold reverb.
audio/graveyard/ghost_death.wav   - a ghost fading out: a shriek sliding down into a sigh.
audio/graveyard/snarl.wav         - a ghoul's snarl: a rasping, jittering growl.
audio/graveyard/ghoul_death.wav   - a ghoul going down: a wet gurgle and a thud.
audio/graveyard/grave_crumble.wav - earth crumbling as the dead claw out: grit, clods, a thump.
audio/graveyard/crow_caw_1.wav    - crows: harsh caws (two calls) far off in the night.
audio/graveyard/crow_caw_2.wav
audio/graveyard/bell_toll.wav     - the chapel bell tolling three times, distant.
audio/graveyard/necro_laugh.wav   - the Necromancer's laugh: a deep, slow "ha... ha ha ha".
audio/graveyard/necro_spell.wav   - a spell: a rising whoosh with a cold shimmer.
audio/graveyard/bone_spikes.wav   - bone spikes bursting out of the ground: cracks and scrapes.
audio/graveyard/soul_drain.wav    - the soul-drain beam: a droning hum and whispering rush.
audio/graveyard/graves_open.wav   - his ultimate: the ground rumbling and groaning open.
audio/graveyard/necro_death.wav   - his death: a long falling scream, souls rushing out.

    python3 tools/gen_graveyard_sounds.py
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/graveyard/"


def lp(x, hz, order=3):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def hp(x, hz, order=3):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def reverb(x, rng, seconds=2.4, wet=0.4, bright=2500):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = rng.normal(0, 1, n) * np.exp(-t / (seconds / 6.0))
    ir = lp(ir, bright)
    ir[: int(SR * 0.025)] *= np.linspace(0, 1, int(SR * 0.025))
    ir /= np.sqrt(np.sum(ir ** 2))
    out = np.convolve(x, ir)[: x.size + n]
    dry = np.pad(x, (0, out.size - x.size))
    return dry * (1 - wet) + out * wet * 3.0


def tone(freq, t):
    """A sine following a frequency curve (array) over time t."""
    return np.sin(2 * np.pi * np.cumsum(freq) / SR)


def saw(freq):
    ph = np.cumsum(freq) / SR
    return 2.0 * (ph - np.floor(ph + 0.5))


def env(t, attack, decay):
    return np.clip(t / max(attack, 1e-4), 0, 1) * np.exp(-np.clip(t - attack, 0, None) / decay)


def write(name, chans, peak=0.89):
    st = np.stack(chans, axis=1)
    st /= np.max(np.abs(st)) + 1e-9
    st *= peak
    fade = int(SR * 0.05)
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    wavfile.write(OUT + name, SR, (st * 32767).astype(np.int16))
    print(name, f"{st.shape[0] / SR:.2f}s")


def stereo(make, name, seed, **kw):
    write(name, [make(np.random.default_rng(seed + c), c, **kw) for c in range(2)])


# ------------------------------------------------------------------ the dead

def wail(rng, c):
    dur = 2.2
    t = np.arange(int(SR * dur)) / SR
    glide = 380 + 320 * np.sin(np.clip(t / dur, 0, 1) * np.pi) ** 1.5 - 60 * t
    f = glide * (1 + 0.025 * np.sin(2 * np.pi * 5.2 * t + c)) * (1 + 0.004 * rng.normal(0, 1, t.size).cumsum() / 200)
    voice = tone(f, t) + 0.35 * tone(f * 2.01, t) + 0.15 * tone(f * 3.02, t)
    breath = bp(rng.normal(0, 1, t.size), 300, 1100) * 0.6
    x = (voice * 0.7 + breath) * env(t, 0.35, 0.9) * np.clip(1.6 - t / dur * 1.2, 0, 1)
    x = bp(x, 200, 3000)
    return reverb(x, rng, 3.0, 0.55, 2200)


def ghost_death(rng, c):
    dur = 1.4
    t = np.arange(int(SR * dur)) / SR
    f = 950 * np.exp(-t * 1.6) + 180
    x = tone(f * (1 + 0.03 * np.sin(2 * np.pi * 9 * t)), t) * 0.8 + bp(rng.normal(0, 1, t.size), 500, 2500) * 0.45
    x *= env(t, 0.03, 0.45)
    sigh = bp(rng.normal(0, 1, t.size), 250, 900) * env(np.clip(t - 0.5, 0, None), 0.2, 0.4) * (t > 0.5) * 0.5
    return reverb(x + sigh, rng, 2.6, 0.55, 2500)


def snarl(rng, c):
    dur = 0.95
    t = np.arange(int(SR * dur)) / SR
    f = 95 + 25 * np.sin(2 * np.pi * 1.7 * t) + 12 * rng.normal(0, 1, t.size).cumsum() / np.sqrt(np.arange(1, t.size + 1))
    rasp = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 27 * t + rng.uniform(0, 6)))
    x = saw(np.maximum(f, 40)) * rasp
    x = bp(x, 140, 2600) + bp(rng.normal(0, 1, t.size), 1500, 5000) * 0.25
    x *= env(t, 0.06, 0.45) * np.clip(1.2 - t, 0, 1)
    return reverb(x, rng, 1.0, 0.18)


def ghoul_death(rng, c):
    dur = 0.9
    t = np.arange(int(SR * dur)) / SR
    gurgle = np.zeros_like(t)
    for _ in range(14):
        t0 = rng.uniform(0.0, 0.5)
        tt = np.clip(t - t0, 0, None)
        fr = rng.uniform(250, 700)
        gurgle += np.sin(2 * np.pi * (fr + 600 * tt) * tt) * np.exp(-tt / 0.03) * (t >= t0) * rng.uniform(0.3, 0.8)
    growl = bp(saw(80 + 30 * np.exp(-t * 4)), 100, 1200) * env(t, 0.02, 0.25)
    thud = lp(rng.normal(0, 1, t.size), 200) * env(np.clip(t - 0.45, 0, None), 0.005, 0.08) * (t > 0.45) * 2.0
    return reverb(gurgle * 0.6 + growl * 0.7 + thud, rng, 0.8, 0.15)


def grave_crumble(rng, c):
    dur = 1.3
    t = np.arange(int(SR * dur)) / SR
    x = np.zeros_like(t)
    for _ in range(180):   # grit and clods
        t0 = rng.uniform(0.0, 0.9) ** 1.3
        n = int(SR * rng.uniform(0.004, 0.025))
        i0 = int(t0 * SR)
        if i0 + n >= t.size:
            continue
        grain = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (n * 0.3))
        x[i0:i0 + n] += grain * rng.uniform(0.1, 0.6)
    x = lp(x, 2600) + lp(hp(x, 2000), 7000) * 0.2
    thump = lp(rng.normal(0, 1, t.size), 150) * env(t, 0.01, 0.15) * 2.5
    scrape = bp(rng.normal(0, 1, t.size), 600, 1800) * env(np.clip(t - 0.2, 0, None), 0.1, 0.3) * (t > 0.2) * 0.4
    return reverb((x + thump + scrape) * np.clip(1.4 - t, 0, 1), rng, 0.9, 0.15)


# ------------------------------------------------------------------ ambience

def caw(rng, t, t0, base):
    tt = np.clip(t - t0, 0, None)
    on = (t >= t0) & (tt < 0.32)
    f = base * (1.0 - 0.18 * tt / 0.32) * (1 + 0.02 * np.sin(2 * np.pi * 38 * tt))
    v = saw(f) + 0.5 * saw(f * 1.5)
    e = np.clip(tt / 0.02, 0, 1) * np.exp(-tt / 0.14) * on
    return v * e


def crow(rng, c, variant=0):
    dur = 1.6
    t = np.arange(int(SR * dur)) / SR
    base = 560 if variant == 0 else 690
    x = caw(rng, t, 0.05, base) + caw(rng, t, 0.48 + 0.1 * variant, base * 0.97)
    if variant == 1:
        x += caw(rng, t, 0.95, base * 1.02) * 0.8
    x = bp(x, 700, 3200) + bp(x, 1800, 2600) * 0.8
    return reverb(lp(x, 4500), rng, 2.4, 0.5, 2000)


def bell_toll(rng, c):
    dur = 9.0
    t = np.arange(int(SR * dur)) / SR
    f0 = 196.0
    partials = [(0.5, 1.0, 4.5), (1.0, 0.8, 3.2), (1.19, 0.55, 2.4), (1.5, 0.4, 2.0), (2.0, 0.45, 1.6), (2.51, 0.22, 1.1), (3.0, 0.18, 0.9), (4.2, 0.12, 0.6)]
    x = np.zeros_like(t)
    for k in range(3):
        t0 = 0.05 + k * 2.6
        tt = np.clip(t - t0, 0, None)
        strike = (t >= t0)
        for ratio, amp, dec in partials:
            beat = 1 + 0.002 * (c - 0.5)
            x += np.sin(2 * np.pi * f0 * ratio * beat * tt) * amp * np.exp(-tt / dec) * strike
        x += bp(rng.normal(0, 1, t.size), 800, 3000) * np.exp(-tt / 0.02) * strike * 0.3
    x = lp(x, 2400)   # far off
    return reverb(x, rng, 3.5, 0.5, 1800)


# ------------------------------------------------------------------ the Necromancer

def laugh(rng, c):
    dur = 2.8
    t = np.arange(int(SR * dur)) / SR
    x = np.zeros_like(t)
    hits = [0.05, 0.62, 0.92, 1.18, 1.42, 1.66]
    for k, t0 in enumerate(hits):
        tt = np.clip(t - t0, 0, None)
        on = (t >= t0) & (tt < 0.38)
        f = (118 - k * 3) * np.exp(-tt * 0.8)
        v = saw(np.maximum(f, 50))
        ha = bp(v, 550, 900) * 1.2 + bp(v, 1050, 1400) * 0.7 + bp(rng.normal(0, 1, t.size), 900, 3000) * 0.15
        x += ha * np.clip(tt / 0.025, 0, 1) * np.exp(-tt / 0.16) * on * (1.3 if k == 0 else 1.0)
    low = lp(x, 500)
    x = x + np.interp(np.arange(t.size) * 0.5, np.arange(t.size), low) * 0.6   # an octave-down shadow
    return reverb(x, rng, 3.0, 0.5, 2000)


def spell(rng, c):
    dur = 1.3
    t = np.arange(int(SR * dur)) / SR
    noise = rng.normal(0, 1, t.size)
    sweep = np.zeros_like(t)
    seg = int(SR * 0.05)
    for i in range(0, t.size, seg):
        ctr = 300 * (12 ** (i / t.size))
        sweep[i:i + seg] = bp(noise[max(0, i - 2000):i + seg], ctr * 0.7, min(ctr * 1.4, 18000))[-len(sweep[i:i + seg]):]
    sweep *= env(t, 0.6, 0.35)
    shimmer = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) for f in [1320, 1661, 1975, 2489]) * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * t)) * env(np.clip(t - 0.4, 0, None), 0.2, 0.5) * (t > 0.4) * 0.15
    return reverb(sweep * 0.8 + shimmer, rng, 2.2, 0.45)


def bone_spikes(rng, c):
    dur = 1.0
    t = np.arange(int(SR * dur)) / SR
    x = np.zeros_like(t)
    for _ in range(22):
        t0 = rng.uniform(0.0, 0.35)
        tt = np.clip(t - t0, 0, None)
        fr = rng.uniform(700, 2300)
        x += (np.sin(2 * np.pi * fr * tt) + 0.5 * np.sin(2 * np.pi * fr * 2.7 * tt)) * np.exp(-tt / rng.uniform(0.008, 0.03)) * (t >= t0) * rng.uniform(0.3, 1.0)
    scrape = bp(rng.normal(0, 1, t.size), 1200, 4000) * env(t, 0.02, 0.18) * 0.5
    thud = lp(rng.normal(0, 1, t.size), 160) * env(t, 0.005, 0.12) * 2.0
    return reverb(x + scrape + thud, rng, 1.2, 0.25)


def soul_drain(rng, c):
    dur = 3.0
    t = np.arange(int(SR * dur)) / SR
    f = 110 * (1 + 0.15 * t / dur)
    hum = tone(f, t) + 0.6 * tone(f * 1.5, t) + 0.3 * tone(f * 2.02, t)
    hum *= 0.7 + 0.3 * np.sin(2 * np.pi * 6 * t)
    rush = bp(rng.normal(0, 1, t.size), 400, 2600) * (0.5 + 0.5 * np.sin(2 * np.pi * 1.3 * t + c))
    whisper = bp(rng.normal(0, 1, t.size), 2000, 6000) * (0.5 + 0.5 * np.sin(2 * np.pi * 7.3 * t)) * 0.2
    x = (hum * 0.6 + rush * 0.5 + whisper) * env(t, 0.25, 2.2) * np.clip((dur - t) / 0.3, 0, 1)
    return reverb(x, rng, 2.0, 0.4)


def graves_open(rng, c):
    dur = 6.5
    t = np.arange(int(SR * dur)) / SR
    rumble = lp(rng.normal(0, 1, t.size), 90) * np.clip(t / 4.0, 0, 1) ** 1.5 * 3.0
    groans = np.zeros_like(t)
    for _ in range(5):
        t0 = rng.uniform(0.5, 4.5)
        tt = np.clip(t - t0, 0, None)
        f = rng.uniform(70, 130) * np.exp(-tt * 0.2)
        groans += bp(saw(f), 90, 900) * np.clip(tt / 0.4, 0, 1) * np.exp(-tt / 0.9) * (t >= t0) * 0.5
    crack = np.zeros_like(t)
    for _ in range(60):
        t0 = rng.uniform(1.0, 6.0)
        n = int(SR * 0.02)
        i0 = int(t0 * SR)
        if i0 + n < t.size:
            crack[i0:i0 + n] += rng.normal(0, 1, n) * np.exp(-np.arange(n) / (n * 0.2)) * rng.uniform(0.1, 0.5)
    return reverb(rumble + groans + lp(crack, 3000), rng, 3.0, 0.4, 1500)


def necro_death(rng, c):
    dur = 3.4
    t = np.arange(int(SR * dur)) / SR
    f = 520 * np.exp(-t * 0.7) + 90
    scream = saw(f * (1 + 0.04 * np.sin(2 * np.pi * 7 * t)))
    scream = bp(scream, 500, 900) + bp(scream, 1100, 2400) * 0.6
    scream *= env(t, 0.05, 1.2)
    souls = bp(rng.normal(0, 1, t.size), 600, 3500) * env(np.clip(t - 0.8, 0, None), 0.3, 0.8) * (t > 0.8) * 0.6
    collapse = lp(rng.normal(0, 1, t.size), 220) * env(np.clip(t - 1.2, 0, None), 0.01, 0.25) * (t > 1.2) * 1.5
    return reverb(scream * 0.8 + souls + collapse, rng, 3.0, 0.5)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    stereo(wail, "wail.wav", 10)
    stereo(ghost_death, "ghost_death.wav", 20)
    stereo(snarl, "snarl.wav", 30)
    stereo(ghoul_death, "ghoul_death.wav", 40)
    stereo(grave_crumble, "grave_crumble.wav", 50)
    stereo(crow, "crow_caw_1.wav", 60, variant=0)
    stereo(crow, "crow_caw_2.wav", 70, variant=1)
    stereo(bell_toll, "bell_toll.wav", 80)
    stereo(laugh, "necro_laugh.wav", 90)
    stereo(spell, "necro_spell.wav", 100)
    stereo(bone_spikes, "bone_spikes.wav", 110)
    stereo(soul_drain, "soul_drain.wav", 120)
    stereo(graves_open, "graves_open.wav", 130)
    stereo(necro_death, "necro_death.wav", 140)
