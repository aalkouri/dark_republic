"""Synthesise the Forest and Castle bosses' sounds (no samples needed).

The Toadstool Knight (audio/bosses/):
  knight_roar.wav     a muffled war cry under the cap: a hollow voice through a narrow formant,
                      with a metallic ring
  knight_slash.wav    a heavy blade whoosh ending in a ringing steel scrape
  mushroom_burst.wav  mushrooms bursting out of the ground: a deep thump and wet pops
  spore_lob.wav       a mortar "thoomp" and a rising whistle
  spore_splat.wav     a soft wet splat with a hiss of spores
  court_summon.wav    a rising earthy rumble with a shimmer: the Fungus Court arrives
  armor_step.wav      a heavy footstep with a clank of plate
The Arachnid:
  spider_screech.wav  a shrill, rasping shriek (her roar)
  spider_hiss.wav     a long breathy hiss
  spider_skitter.wav  a burst of quick clicky leg taps
  spider_spit.wav     a wet "ptoo"
  spider_web.wav      a stringy "thwip"

    python3 tools/gen_boss_sounds.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/bosses/"
rng = np.random.default_rng(11)


def t_of(d):
    return np.arange(int(SR * d)) / SR


def lp(x, hz, o=3):
    return sosfilt(butter(o, hz, "low", fs=SR, output="sos"), x)


def hp(x, hz, o=2):
    return sosfilt(butter(o, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, min(hi, SR / 2 - 100)], "band", fs=SR, output="sos"), x)


def place(buf, snd, at):
    i = int(at * SR)
    n = min(len(snd), len(buf) - i)
    buf[i:i + n] += snd[:n]


def write(name, x, peak=0.9, spread=0.004):
    x = np.tanh(x * 1.1)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(SR * 0.02)
    x[-fade:] *= np.linspace(1, 0, fade)
    st = np.stack([x, np.roll(x, int(SR * spread))], 1)
    wavfile.write(OUT + name, SR, (st * 32767).astype(np.int16))
    print(name, f"{len(x) / SR:.2f}s")


def thump(d, f0, f1, decay):
    t = t_of(d)
    return np.sin(2 * np.pi * np.cumsum(f1 + (f0 - f1) * np.exp(-t / 0.04)) / SR) * np.exp(-t * decay)


def knight_roar():
    d = 1.8
    t = t_of(d)
    f0 = 140 + 40 * np.sin(np.pi * np.clip(t / d, 0, 1)) + 5 * np.sin(2 * np.pi * 7 * t)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    voice = sum(np.sin(h * ph) / h for h in range(1, 20))
    v = bp(voice, 300, 1100) * 1.2 + bp(rng.normal(0, 1, t.size), 500, 2500) * 0.25
    env = np.clip(t / 0.15, 0, 1) * np.clip((d - t) / 0.6, 0, 1)
    ring = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(523, 0.3), (1307, 0.18), (2210, 0.1)]) * np.exp(-t * 2.5)
    write("knight_roar.wav", v * env + ring * 0.4)


def knight_slash():
    d = 0.9
    t = t_of(d)
    sweep = np.zeros_like(t)
    noise = rng.normal(0, 1, t.size)
    for i in range(0, t.size, 512):
        j = min(t.size, i + 512)
        f = 300 + 2500 * np.exp(-((t[i] - 0.28) / 0.12) ** 2)
        sweep[i:j] = bp(noise[max(0, i - 2048):j], f * 0.6, f * 1.6)[-(j - i):]
    sweep *= np.exp(-((t - 0.28) / 0.15) ** 2)
    ring = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(1870, 0.5), (2950, 0.3), (4400, 0.2)])
    ring = ring * np.exp(-np.clip(t - 0.33, 0, None) * 6) * (t > 0.33)
    write("knight_slash.wav", sweep * 1.4 + ring * 0.5 + thump(d, 160, 60, 14) * (t > 0.33) * 0.5)


def mushroom_burst():
    d = 0.9
    buf = thump(d, 120, 45, 7) * 1.0
    for k in range(6):
        tt = t_of(0.08)
        pop = np.sin(2 * np.pi * np.cumsum(900 - 500 * tt / 0.08 + 200 * k) / SR) * np.exp(-tt * 50)
        place(buf, pop * 0.5, 0.03 + k * 0.045 + rng.random() * 0.02)
    buf += lp(rng.normal(0, 1, buf.size), 1800) * np.exp(-t_of(d) * 9) * 0.5
    write("mushroom_burst.wav", buf)


def spore_lob():
    d = 0.9
    t = t_of(d)
    boom = thump(d, 110, 50, 16)
    whistle = np.sin(2 * np.pi * np.cumsum(500 + 900 * np.clip(t - 0.1, 0, None)) / SR) * np.clip((t - 0.1) / 0.1, 0, 1) * np.exp(-np.clip(t - 0.1, 0, None) * 2.5) * 0.25
    write("spore_lob.wav", boom + whistle + bp(rng.normal(0, 1, t.size), 200, 900) * np.exp(-t * 20) * 0.6, peak=0.8)


def spore_splat():
    d = 0.6
    t = t_of(d)
    splat = lp(rng.normal(0, 1, t.size), 1400) * np.exp(-t * 18)
    hiss = hp(rng.normal(0, 1, t.size), 4000) * np.exp(-t * 6) * 0.25
    write("spore_splat.wav", splat + hiss + thump(d, 180, 70, 22) * 0.6, peak=0.75)


def court_summon():
    d = 1.8
    t = t_of(d)
    rumble = lp(rng.normal(0, 1, t.size), 140) * np.clip(t / 1.2, 0, 1) * 3.0
    rise = np.sin(2 * np.pi * np.cumsum(80 + 120 * t / d) / SR) * np.clip(t / d, 0, 1) * 0.6
    shimmer = sum(np.sin(2 * np.pi * f * t) for f in [880, 1108, 1320, 1760]) * 0.06 * np.clip((t - 0.8) / 0.6, 0, 1)
    write("court_summon.wav", (rumble + rise + shimmer) * np.clip((d - t) / 0.3, 0, 1))


def armor_step():
    d = 0.5
    t = t_of(d)
    clank = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(820, 0.4), (1340, 0.3), (2170, 0.2)]) * np.exp(-t * 25)
    write("armor_step.wav", thump(d, 110, 50, 16) + clank * 0.4 + bp(rng.normal(0, 1, t.size), 200, 800) * np.exp(-t * 30) * 0.4, peak=0.7)


def spider_screech():
    d = 1.4
    t = t_of(d)
    f0 = 900 + 500 * np.sin(np.pi * np.clip(t / d, 0, 1)) + 60 * np.sin(2 * np.pi * 23 * t)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    tone = np.sign(np.sin(ph)) * 0.4 + np.sin(2.01 * ph) * 0.3
    rasp = bp(rng.normal(0, 1, t.size), 2000, 7000) * (0.6 + 0.4 * np.sin(2 * np.pi * 40 * t))
    env = np.clip(t / 0.05, 0, 1) * np.clip((d - t) / 0.5, 0, 1)
    write("spider_screech.wav", lp(tone + rasp * 0.7, 8000) * env)


def spider_hiss():
    d = 1.2
    t = t_of(d)
    h = bp(rng.normal(0, 1, t.size), 2500, 9000) * np.clip(t / 0.08, 0, 1) * np.clip((d - t) / 0.5, 0, 1)
    write("spider_hiss.wav", h * (0.8 + 0.2 * np.sin(2 * np.pi * 9 * t)), peak=0.7)


def spider_skitter():
    d = 0.4
    buf = np.zeros(int(SR * d))
    for k in range(8):
        tt = t_of(0.02)
        click = bp(rng.normal(0, 1, tt.size), 1500, 6000) * np.exp(-tt * 250)
        place(buf, click * (0.6 + 0.4 * rng.random()), k * 0.042 + rng.random() * 0.01)
    write("spider_skitter.wav", buf, peak=0.6)


def spider_spit():
    d = 0.5
    t = t_of(d)
    p = bp(rng.normal(0, 1, t.size), 600, 3000) * np.exp(-t * 14) + thump(d, 400, 120, 20) * 0.5
    write("spider_spit.wav", p, peak=0.75)


def spider_web():
    d = 0.5
    t = t_of(d)
    s = np.sin(2 * np.pi * np.cumsum(2400 - 1800 * np.clip(t / 0.25, 0, 1)) / SR) * np.exp(-t * 9)
    write("spider_web.wav", s * 0.6 + hp(rng.normal(0, 1, t.size), 5000) * np.exp(-t * 18) * 0.3, peak=0.7)


for f in [knight_roar, knight_slash, mushroom_burst, spore_lob, spore_splat, court_summon, armor_step,
          spider_screech, spider_hiss, spider_skitter, spider_spit, spider_web]:
    f()
