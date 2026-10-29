"""Synthesise the level-up / reward-card sounds (no samples). Three candidates for each:

  audio/ui/levelup_chime.wav     rising bell arpeggio with a shimmer tail (arcane)
  audio/ui/levelup_fanfare.wav   bright brassy stab chord with an upward sweep and sparkle
  audio/ui/levelup_flame.wav     fiery whoosh up, a warm boom and crackling embers
  audio/ui/hover_tick.wav        soft wooden tick
  audio/ui/hover_glass.wav       tiny glassy "tink"
  audio/ui/hover_page.wav        quick paper/page flick (tomes!)
  audio/ui/pick_shing.wav        magical "shing": bright sweep into a ringing bell
  audio/ui/pick_slam.wav         heavy book slam with a sparkle on top
  audio/ui/pick_rune.wav         low rune "thrum" with a rising chime
  audio/ui/ban_stamp.wav         BAN: a heavy rubber-stamp thunk and a falling, "denied" two-note drone

    python3 tools/gen_ui_sounds.py
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
rng = np.random.default_rng(5)


def t_of(d):
    return np.arange(int(SR * d)) / SR


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo, hi], "band", fs=SR, output="sos"), x)


def lp(x, hz, o=2):
    return sosfilt(butter(o, hz, "low", fs=SR, output="sos"), x)


def hp(x, hz, o=2):
    return sosfilt(butter(o, hz, "high", fs=SR, output="sos"), x)


def bell(f, d, decay=1.2, bright=1.0):
    t = t_of(d)
    out = np.zeros_like(t)
    for k, (r, a) in enumerate([(1, 1.0), (2.0, 0.45), (3.01, 0.25 * bright), (4.2, 0.12 * bright), (5.4, 0.06 * bright)]):
        out += a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * decay * (1 + 0.6 * k))
    out[: int(SR * 0.003)] *= np.linspace(0, 1, int(SR * 0.003))
    return out


def place(buf, snd, at):
    i = int(at * SR)
    n = min(len(snd), len(buf) - i)
    buf[i:i + n] += snd[:n]


def finish(x, name, peak=0.9, stereo_spread=0.0):
    x = np.tanh(x * 1.2)
    x /= np.max(np.abs(x)) / peak
    fade = int(SR * 0.02)
    x[-fade:] *= np.linspace(1, 0, fade)
    st = np.stack([x, x], 1)
    if stereo_spread:
        d = int(SR * stereo_spread)
        st[d:, 1] = x[:-d]
    wavfile.write("audio/ui/" + name, SR, (st * 32767).astype(np.int16))


# ---------------- level up
def levelup_chime():
    d = 1.8
    buf = np.zeros(int(SR * d))
    notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]   # C E G C E
    for i, f in enumerate(notes):
        place(buf, bell(f, 1.4, decay=2.2) * (0.7 + 0.08 * i), i * 0.075)
    # shimmer: sparse high glints
    for k in range(26):
        at = 0.25 + rng.exponential(0.35)
        if at < d - 0.2:
            place(buf, bell(rng.uniform(2500, 4200), 0.25, decay=14) * 0.12, at)
    finish(buf, "levelup_chime.wav", stereo_spread=0.008)


def levelup_fanfare():
    d = 1.5
    t = t_of(d)
    chord = [261.63, 329.63, 392.0, 523.25]
    x = np.zeros_like(t)
    for f in chord:
        for h in range(1, 9):   # brassy saw-ish
            x += np.sin(2 * np.pi * f * h * t * (1 + 0.002 * np.sin(2 * np.pi * 5 * t))) / h
    env = np.minimum(1, t / 0.02) * np.exp(-t * 1.6)
    x = lp(x * env, 3500)
    sweep = np.sin(2 * np.pi * np.cumsum(300 + 1500 * np.minimum(1, t / 0.25)) / SR) * np.exp(-t * 6) * 0.25
    buf = x * 0.5 + sweep
    for k in range(18):
        at = 0.15 + rng.exponential(0.3)
        if at < d - 0.2:
            place(buf, bell(rng.uniform(2000, 3500), 0.2, decay=16) * 0.15, at)
    finish(buf, "levelup_fanfare.wav", stereo_spread=0.006)


def levelup_flame():
    d = 1.7
    t = t_of(d)
    noise = rng.normal(0, 1, t.size)
    # rising whoosh: band sweeps 300 -> 3000 Hz over 0.5 s
    whoosh = np.zeros_like(t)
    for k in range(8):
        a, b = int(t.size * k / 8 * 0.35), int(t.size * (k + 1) / 8 * 0.35)
        c = 300 * (10 ** (k / 7))
        whoosh[a:b] = bp(noise, c * 0.6, min(c * 1.6, 15000))[a:b]
    whoosh *= np.minimum(1, t / 0.35) * np.exp(-np.maximum(0, t - 0.35) * 7)
    boom = np.sin(2 * np.pi * np.cumsum(55 + 60 * np.exp(-np.maximum(0, t - 0.35) / 0.1)) / SR)
    boom *= np.where(t > 0.35, np.exp(-(t - 0.35) * 4), 0)
    crackle = np.zeros_like(t)
    for k in range(70):
        at = 0.4 + rng.exponential(0.4)
        if at < d - 0.05:
            n = int(SR * rng.uniform(0.002, 0.008))
            i = int(at * SR)
            crackle[i:i + n] += rng.normal(0, 1, n) * rng.uniform(0.2, 0.6)
    crackle = hp(crackle, 1500)
    chime = np.zeros_like(t)
    place(chime, bell(784, 1.2, decay=2.5) * 0.35, 0.36)
    place(chime, bell(1175, 1.1, decay=2.8) * 0.3, 0.42)
    finish(whoosh * 0.9 + boom * 0.8 + crackle * 0.5 + chime, "levelup_flame.wav", stereo_spread=0.007)


# ---------------- hover
def hover_tick():
    t = t_of(0.07)
    x = np.sin(2 * np.pi * 1700 * t) * np.exp(-t * 90) + bp(rng.normal(0, 1, t.size), 1500, 5000) * np.exp(-t * 160) * 0.5
    finish(x, "hover_tick.wav", peak=0.45)


def hover_glass():
    x = bell(2900, 0.18, decay=22, bright=0.6)
    finish(x, "hover_glass.wav", peak=0.4)


def hover_page():
    t = t_of(0.13)
    n = bp(rng.normal(0, 1, t.size), 2000, 9000)
    env = np.sin(np.pi * np.minimum(1, t / 0.13)) ** 2 * (1 + 0.6 * np.sin(2 * np.pi * 45 * t))
    finish(n * env, "hover_page.wav", peak=0.4)


# ---------------- pick
def pick_shing():
    d = 0.9
    t = t_of(d)
    sweep = bp(rng.normal(0, 1, t.size), 3000, 12000) * np.exp(-t * 18) * 0.8
    buf = sweep + bell(1568, d, decay=3.5) * 0.8 + bell(2093, d, decay=4.5) * 0.4
    finish(buf, "pick_shing.wav", peak=0.8)


def pick_slam():
    d = 0.8
    t = t_of(d)
    thud = np.sin(2 * np.pi * np.cumsum(70 + 90 * np.exp(-t / 0.03)) / SR) * np.exp(-t * 14)
    slap = lp(rng.normal(0, 1, t.size), 2500) * np.exp(-t * 60) * 0.8
    buf = thud + slap
    place(buf, bell(1760, 0.6, decay=5) * 0.3, 0.05)
    place(buf, bell(2637, 0.5, decay=6) * 0.2, 0.09)
    finish(buf, "pick_slam.wav", peak=0.85)


def pick_rune():
    d = 1.0
    t = t_of(d)
    thrum = (np.sin(2 * np.pi * 110 * t) + 0.5 * np.sin(2 * np.pi * 165 * t)) * np.minimum(1, t / 0.02) * np.exp(-t * 3.5)
    thrum *= 1 + 0.3 * np.sin(2 * np.pi * 9 * t)
    buf = thrum * 0.7
    place(buf, bell(880, 0.8, decay=4) * 0.4, 0.06)
    place(buf, bell(1320, 0.7, decay=4.5) * 0.35, 0.14)
    finish(buf, "pick_rune.wav", peak=0.8)


def ban_stamp():
    d = 0.9
    t = t_of(d)
    thunk = np.sin(2 * np.pi * np.cumsum(60 + 140 * np.exp(-t / 0.02)) / SR) * np.exp(-t * 16)
    slap = bp(rng.normal(0, 1, t.size), 300, 2500) * np.exp(-t * 45) * 0.9
    buf = thunk + slap
    # falling minor second, buzzy (square-ish): "nope"
    for at, f in [(0.07, 311.13), (0.22, 233.08)]:
        tt = t_of(0.45)
        tone = np.sign(np.sin(2 * np.pi * f * tt)) * 0.25 + np.sin(2 * np.pi * f * tt) * 0.5
        tone = lp(tone * np.minimum(1, tt / 0.01) * np.exp(-tt * 5), 1800)
        place(buf, tone * 0.45, at)
    finish(buf, "ban_stamp.wav", peak=0.85)


for f in [levelup_chime, levelup_fanfare, levelup_flame, hover_tick, hover_glass, hover_page, pick_shing, pick_slam, pick_rune, ban_stamp]:
    f()
print("wrote audio/ui/*.wav")
