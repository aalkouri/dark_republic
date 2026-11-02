"""Synthesise the boss portal's and the shard pickups' sounds (no samples needed).

audio/portal/portal_open.wav   the portal rising: a grinding stone rumble, then a rising magical
                               shimmer and a deep "whomp" as the vortex ignites (about 3 s)
audio/portal/portal_hum.wav    a soft, seamless hum loop: two detuned drones, a slow beat and a
                               faint airy swirl (exactly 4 s, loops cleanly)
audio/portal/portal_whoosh.wav entering: a rushing whoosh that sweeps up and is sucked away,
                               with a bright sparkle tail (about 1.8 s)
audio/portal/shard_chime.wav   picking up a shard: a glassy bell chime (two partials and a
                               sparkle), about 1.2 s
audio/portal/shard_burst.wav   the shards bursting out of the fallen boss: a crystalline crack
                               and a spray of tinkles (about 1.4 s)

    python3 tools/gen_portal_sounds.py
"""
import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "portal")


def lowpass(x, hz, order=4):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def highpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bandpass(x, lo, hi, order=3):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def finish(st, fade_s, peak=0.9, drive=1.2):
    st = np.tanh(st * drive)
    n = st.shape[0]
    if fade_s > 0:
        fade = np.ones(n)
        fade[-int(SR * fade_s):] = np.linspace(1, 0, int(SR * fade_s)) ** 2
        st *= fade[:, None]
    st /= np.max(np.abs(st)) / peak
    return (st * 32767).astype(np.int16)


def sweep(t, f):
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def portal_open():
    t = np.arange(int(SR * 3.2)) / SR
    chans = []
    for seed in (11, 12):
        r = np.random.default_rng(seed)
        noise = r.normal(0, 1, t.size)
        # grinding stone: low noise with a gritty, wobbling band, for the first 1.5 s
        grind_env = np.minimum(1.0, t / 0.15) * np.clip((1.6 - t) / 0.4, 0, 1)
        grind = (lowpass(noise, 180) * 3.0 + bandpass(noise, 300, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t))) * grind_env
        # shimmer: a cluster of rising sines from 1.2 s
        sh_env = np.clip((t - 1.0) / 0.9, 0, 1) * np.exp(-np.maximum(t - 2.2, 0) / 0.6)
        shimmer = np.zeros_like(t)
        for k, base in enumerate((330, 495, 660, 990, 1320)):
            f = base * (1 + 0.5 * np.clip((t - 1.0) / 1.4, 0, 1)) * (1 + 0.004 * (seed - 11.5) * k)
            shimmer += sweep(t, f) * (0.5 / (k + 1)) * (1 + 0.3 * np.sin(2 * np.pi * (5 + k) * t))
        shimmer *= sh_env
        # the whomp: a falling sub thump as the vortex ignites at 2.2 s
        tw = np.maximum(t - 2.2, 0)
        whomp = sweep(t, 40 + 90 * np.exp(-tw / 0.12)) * np.exp(-tw / 0.45) * (t >= 2.2) * 1.6
        air = bandpass(noise, 1500, 7000) * np.exp(-tw / 0.3) * (t >= 2.2) * 0.6
        chans.append(grind + shimmer + whomp + air)
    return finish(np.stack(chans, axis=1), 0.5)


def portal_hum():
    n = int(SR * 4.0)
    t = np.arange(n) / SR
    chans = []
    for k, seed in enumerate((21, 22)):
        # whole-cycle frequencies over 4 s so the loop is seamless
        d1 = np.sin(2 * np.pi * 55.0 * t)
        d2 = np.sin(2 * np.pi * (55.5 + 0.25 * k) * t)       # slow beating
        d3 = np.sin(2 * np.pi * 110.25 * t) * 0.4
        d4 = np.sin(2 * np.pi * 165.0 * t + np.sin(2 * np.pi * 0.5 * t) * 2.0) * 0.18
        # airy swirl: noise made periodic (circular filtering of one loop's worth)
        r = np.random.default_rng(seed)
        spec = np.fft.rfft(r.normal(0, 1, n))
        f = np.fft.rfftfreq(n, 1 / SR)
        spec *= np.exp(-((f - 900) / 500) ** 2)
        air = np.fft.irfft(spec, n)
        air /= np.max(np.abs(air))
        air *= 0.18 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.75 * t + k))
        chans.append((d1 + d2) * 0.5 + d3 + d4 + air)
    return finish(np.stack(chans, axis=1), 0.0, peak=0.6, drive=1.0)


def portal_whoosh():
    t = np.arange(int(SR * 1.8)) / SR
    chans = []
    for seed in (31, 32):
        r = np.random.default_rng(seed)
        noise = r.normal(0, 1, t.size)
        env = np.minimum(1.0, t / 0.35) ** 2 * np.exp(-np.maximum(t - 0.45, 0) / 0.18)
        # a band sweeping up as you're pulled in
        out = np.zeros_like(t)
        hop = 1024
        for i in range(0, t.size, hop):
            j = min(i + hop * 2, t.size)
            c = 300 + 3500 * min(1.0, t[i] / 0.55)
            out[i:j] += bandpass(noise[i:j], c * 0.6, min(c * 1.6, 18000)) * np.hanning(j - i)
        suck = sweep(t, 120 + 600 * np.clip(t / 0.5, 0, 1)) * np.exp(-np.maximum(t - 0.4, 0) / 0.1) * 0.5
        tail = np.zeros_like(t)
        for _ in range(40):
            at = 0.45 + r.exponential(0.3)
            if at > 1.6:
                continue
            i = int(at * SR)
            m = int(SR * 0.25)
            tt = np.arange(min(m, t.size - i)) / SR
            tail[i:i + tt.size] += np.sin(2 * np.pi * r.uniform(2000, 5000) * tt) * np.exp(-tt / 0.06) * r.uniform(0.05, 0.2)
        chans.append(out * env * 2.0 + suck + tail)
    return finish(np.stack(chans, axis=1), 0.4)


def shard_chime():
    t = np.arange(int(SR * 1.2)) / SR
    chans = []
    for k in range(2):
        f0 = 1568.0   # G6
        bell = (np.sin(2 * np.pi * f0 * t) * np.exp(-t / 0.35)
                + 0.6 * np.sin(2 * np.pi * f0 * 2.01 * t) * np.exp(-t / 0.2)
                + 0.35 * np.sin(2 * np.pi * f0 * 1.5 * t + k) * np.exp(-t / 0.28)
                + 0.25 * np.sin(2 * np.pi * f0 * 3.98 * t) * np.exp(-t / 0.09))
        r = np.random.default_rng(41 + k)
        sparkle = highpass(r.normal(0, 1, t.size), 6000) * np.exp(-t / 0.05) * 0.3
        chans.append(bell * np.minimum(1.0, t / 0.003) + sparkle)
    return finish(np.stack(chans, axis=1), 0.2, peak=0.8, drive=1.0)


def shard_burst():
    t = np.arange(int(SR * 1.4)) / SR
    chans = []
    for seed in (51, 52):
        r = np.random.default_rng(seed)
        noise = r.normal(0, 1, t.size)
        crack = bandpass(noise, 1800, 9000) * np.exp(-t / 0.025) * 1.5
        thud = sweep(t, 70 + 80 * np.exp(-t / 0.05)) * np.exp(-t / 0.15) * 0.8
        tinkles = np.zeros_like(t)
        for _ in range(26):
            at = r.uniform(0.02, 0.9)
            i = int(at * SR)
            m = int(SR * 0.4)
            tt = np.arange(min(m, t.size - i)) / SR
            f = r.uniform(1800, 4200)
            tinkles[i:i + tt.size] += (np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(2 * np.pi * f * 2.7 * tt)) * np.exp(-tt / 0.08) * r.uniform(0.08, 0.3)
        chans.append(crack + thud + tinkles)
    return finish(np.stack(chans, axis=1), 0.3)


def main():
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(os.path.join(OUT, "portal_open.wav"), SR, portal_open())
    wavfile.write(os.path.join(OUT, "portal_hum.wav"), SR, portal_hum())
    wavfile.write(os.path.join(OUT, "portal_whoosh.wav"), SR, portal_whoosh())
    wavfile.write(os.path.join(OUT, "shard_chime.wav"), SR, shard_chime())
    wavfile.write(os.path.join(OUT, "shard_burst.wav"), SR, shard_burst())
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
