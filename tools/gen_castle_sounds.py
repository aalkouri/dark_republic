"""Synthesise the castle sounds (no samples needed).

audio/castle/door_slam.wav    - two huge oak doors slamming: a low thump with a long stone-hall
                                reverb tail, iron bands rattling, and the latch clank.
audio/castle/bone_clatter.wav - a skeleton collapsing: a few dozen dry, woody bone knocks
                                bouncing on flagstones, quickly thinning out.
audio/castle/chandelier_snap.wav  - a chain giving way overhead: groaning creak, a sharp snap
                                and a jingle of links as it starts to fall.
audio/castle/chandelier_crash.wav - an iron chandelier hitting the table: a heavy wooden thump,
                                clanging iron rings, smashing crockery and candle clatter.

    python3 tools/gen_castle_sounds.py
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = "audio/castle/"


def lp(x, hz, order=3):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def hall_reverb(x, rng, seconds=2.6, wet=0.45):
    """Cheap big-room reverb: convolve with exponentially decaying filtered noise."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = rng.normal(0, 1, n) * np.exp(-t / (seconds / 6.0))
    ir = lp(ir, 2500)
    ir[: int(SR * 0.03)] *= np.linspace(0, 1, int(SR * 0.03))   # pre-delay swell
    ir /= np.sqrt(np.sum(ir ** 2))
    out = np.convolve(x, ir)[: x.size + n]
    dry = np.pad(x, (0, out.size - x.size))
    return dry * (1 - wet) + out * wet * 3.0


def write(name, chans):
    st = np.stack(chans, axis=1)
    st /= np.max(np.abs(st)) + 1e-9
    st *= 0.89
    fade = int(SR * 0.05)
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    wavfile.write(OUT + name, SR, (st * 32767).astype(np.int16))
    print(name, f"{st.shape[0] / SR:.2f}s")


def door_slam():
    dur = 1.2
    chans = []
    for c in range(2):
        rng = np.random.default_rng(11 + c)
        t = np.arange(int(SR * dur)) / SR
        # the boom: a pitched-down thud with a body resonance
        f = 55 * np.exp(-t * 3.0) + 32
        boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.22)
        thud = lp(rng.normal(0, 1, t.size), 380) * np.exp(-t / 0.06) * 1.6
        wood = bp(rng.normal(0, 1, t.size), 180, 900) * np.exp(-t / 0.09) * 0.8
        # iron bands rattling a moment later
        rattle = np.zeros_like(t)
        for _ in range(9):
            t0 = rng.uniform(0.03, 0.25)
            tt = np.clip(t - t0, 0, None)
            fr = rng.uniform(900, 2400)
            rattle += np.sin(2 * np.pi * fr * tt) * np.exp(-tt / 0.03) * (t >= t0) * rng.uniform(0.1, 0.25)
        # latch: a sharp metallic clank
        t0 = 0.32
        tt = np.clip(t - t0, 0, None)
        latch = (np.sin(2 * np.pi * 1350 * tt) + 0.6 * np.sin(2 * np.pi * 2210 * tt)) * np.exp(-tt / 0.05) * (t >= t0) * 0.5
        x = boom * 1.3 + thud + wood + rattle + latch
        chans.append(hall_reverb(x, rng, 2.8, 0.5))
    write("door_slam.wav", chans)


def bone_clatter():
    dur = 0.9
    chans = []
    for c in range(2):
        rng = np.random.default_rng(31 + c)
        t = np.arange(int(SR * dur)) / SR
        x = np.zeros_like(t)
        hits = 34
        for k in range(hits):
            # knocks get sparser and quieter: bones settling
            t0 = (rng.uniform(0, 1) ** 1.8) * dur * 0.75
            tt = np.clip(t - t0, 0, None)
            fr = rng.uniform(700, 2600)
            q = rng.uniform(0.006, 0.018)
            knock = (np.sin(2 * np.pi * fr * tt) + 0.5 * np.sin(2 * np.pi * fr * 2.7 * tt)) * np.exp(-tt / q)
            click = rng.normal(0, 1, t.size) * np.exp(-tt / 0.002)
            x += (knock + click * 0.6) * (t >= t0) * rng.uniform(0.3, 1.0) * (1.0 - 0.6 * t0 / dur)
        x = bp(x, 300, 7000)
        chans.append(hall_reverb(x, rng, 1.2, 0.25))
    write("bone_clatter.wav", chans)


def chandelier_snap():
    dur = 1.1
    chans = []
    for c in range(2):
        rng = np.random.default_rng(51 + c)
        t = np.arange(int(SR * dur)) / SR
        # creak: a slow, wobbling, nasal rub
        f = 140 + 60 * np.sin(2 * np.pi * 3.5 * t) + 40 * t
        rub = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * (t < 0.4) * np.clip(t / 0.05, 0, 1)
        creak = bp(rub, 300, 1800) * 0.35
        # snap at 0.4 s
        tt = np.clip(t - 0.4, 0, None)
        snap = rng.normal(0, 1, t.size) * np.exp(-tt / 0.008) * (t >= 0.4) * 1.4
        # chain links jingling as it drops
        links = np.zeros_like(t)
        for _ in range(22):
            t0 = rng.uniform(0.42, 0.95)
            u = np.clip(t - t0, 0, None)
            fr = rng.uniform(2500, 5200)
            links += np.sin(2 * np.pi * fr * u) * np.exp(-u / 0.02) * (t >= t0) * rng.uniform(0.1, 0.3)
        chans.append(hall_reverb(creak + snap + links, rng, 1.6, 0.35))
    write("chandelier_snap.wav", chans)


def chandelier_crash():
    dur = 1.6
    chans = []
    for c in range(2):
        rng = np.random.default_rng(61 + c)
        t = np.arange(int(SR * dur)) / SR
        f = 70 * np.exp(-t * 4.0) + 40
        boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18) * 1.4
        thud = lp(rng.normal(0, 1, t.size), 500) * np.exp(-t / 0.05) * 1.5
        # iron rings clanging (inharmonic partials)
        clang = np.zeros_like(t)
        for base in [310, 470]:
            for r in [1.0, 2.76, 5.4]:
                clang += np.sin(2 * np.pi * base * r * t) * np.exp(-t * (2.5 + r)) / r
        # crockery smashing: bright bursts scattered over the first half-second
        smash = np.zeros_like(t)
        for _ in range(40):
            t0 = (rng.uniform(0, 1) ** 1.5) * 0.6
            u = np.clip(t - t0, 0, None)
            smash += bp(rng.normal(0, 1, t.size), 2500, 9000) * np.exp(-u / 0.012) * (t >= t0) * rng.uniform(0.2, 0.7)
        x = boom + thud + clang * 0.5 + smash * 0.6
        chans.append(hall_reverb(x, rng, 2.4, 0.4))
    write("chandelier_crash.wav", chans)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    door_slam()
    bone_clatter()
    chandelier_snap()
    chandelier_crash()
