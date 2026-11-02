"""Natural-sounding (physically modelled, not synth-tone) sounds:
  audio/ui/chest_open.wav   - an old wooden chest: latch clack, hinge creak (stick-slip friction
                              exciting wood resonances), the lid thudding back, a few coins
                              shifting inside
  audio/ui/slot_jackpot.wav - the jackpot: a pile of metal coins tumbling and spilling (modal
                              coin impacts with real inharmonic metal partials) and a small hand
                              bell ringing over it
All of it goes through a little room reverb. python3 tools/gen_natural_sounds.py
"""
import numpy as np
from scipy.signal import butter, lfilter, fftconvolve
import wave, os

SR = 44100
rng = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "ui")


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = butter(order, f / (SR / 2))
    return lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = butter(order, f / (SR / 2), btype="high")
    return lfilter(b, a, x)


def room(x, size=0.35, mix=0.22):
    n = int(SR * size)
    ir = rng.standard_normal(n) * np.exp(-np.linspace(0, 7, n))
    ir = lp(ir, 5000)
    ir[0] = 0
    wet = fftconvolve(x, ir)[: len(x)]
    wet /= np.max(np.abs(wet)) + 1e-9
    return x * (1 - mix) + wet * mix * np.max(np.abs(x))


def modal(t0, total, freqs, amps, decays, length=0.6):
    """Add a struck object (sum of decaying partials, random phases) at t0."""
    out = np.zeros(total)
    i0 = int(t0 * SR)
    n = min(int(length * SR), total - i0)
    if n <= 0:
        return out
    t = np.arange(n) / SR
    s = np.zeros(n)
    for f, a, d in zip(freqs, amps, decays):
        if f < SR / 2 - 500:
            s += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi)) * np.exp(-t / d)
    # the tiny contact click of the strike
    click = rng.standard_normal(min(n, 90)) * np.exp(-np.arange(min(n, 90)) / 18.0)
    s[: len(click)] += hp(click, 2500) * 0.5
    out[i0 : i0 + n] += s
    return out


COIN_RATIOS = [1.0, 2.32, 4.25, 6.63, 9.38]   # a thin metal disc's partials (inharmonic)


def coin(t0, total, size=1.0, hard=1.0):
    f0 = rng.uniform(2300, 4200) / size
    freqs = [f0 * r * rng.uniform(0.985, 1.015) for r in COIN_RATIOS]
    amps = [1.0, 0.7, 0.45, 0.25, 0.12]
    decays = [rng.uniform(0.18, 0.45) * hard, 0.12, 0.07, 0.04, 0.025]
    return modal(t0, total, freqs, [a * rng.uniform(0.5, 1.0) for a in amps], decays, 0.7)


def creak(t0, dur, total, f_lo=180, f_hi=900, rate0=55, rate1=140):
    """Stick-slip friction: a train of tiny slips (rate sweeping) ringing wood resonances."""
    out = np.zeros(total)
    t = t0
    while t < t0 + dur:
        k = (t - t0) / dur
        rate = rate0 + (rate1 - rate0) * np.sin(k * np.pi) + rng.normal(0, 6)
        i = int(t * SR)
        if i < total - 200:
            out[i] += rng.uniform(0.4, 1.0) * np.sin(k * np.pi) ** 0.5
        t += 1.0 / max(rate, 20)
    # wood body: a few resonances
    body = np.zeros(total)
    for f, q in [(f_lo, 1.0), (f_lo * 1.9, 0.8), (f_hi * 0.6, 0.6), (f_hi, 0.4)]:
        body += bp(out, f * 0.92, f * 1.08) * q * 6
    return body + bp(out, 1500, 4000) * 0.6   # the dry squeak on top


def thud(t0, total, f=95, amp=1.0, length=0.35):
    out = np.zeros(total)
    i0 = int(t0 * SR)
    n = min(int(length * SR), total - i0)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t * (1 - 0.15 * t)) * np.exp(-t / 0.08)
    s += lp(rng.standard_normal(n), 900) * np.exp(-t / 0.03) * 0.8
    s += bp(rng.standard_normal(n), 300, 1400) * np.exp(-t / 0.05) * 0.4   # the wood knock
    out[i0 : i0 + n] += s * amp
    return out


def norm(x, peak=0.85):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def write(name, x):
    x = norm(x)
    fade = int(0.03 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, "%.2fs" % (len(x) / SR))


def chest_open():
    total = int(1.9 * SR)
    x = np.zeros(total)
    # iron latch: two quick clacks
    x += modal(0.02, total, [1650, 3900, 6100], [1, 0.5, 0.3], [0.03, 0.02, 0.012], 0.15) * 0.8
    x += modal(0.07, total, [1500, 3500], [0.6, 0.3], [0.025, 0.015], 0.12) * 0.5
    # the hinges creak as the lid swings up (slows as it opens)
    x += creak(0.16, 0.85, total, f_lo=210, f_hi=820, rate0=70, rate1=150) * 0.55
    x += creak(0.3, 0.55, total, f_lo=330, f_hi=1200, rate0=120, rate1=210) * 0.25
    # the lid falls back against the hinges: a wooden thud and a small rebound
    x += thud(1.05, total, f=88, amp=1.0)
    x += thud(1.2, total, f=110, amp=0.3, length=0.2)
    # coins inside shift from the knock
    for k in range(7):
        x += coin(1.08 + rng.uniform(0.0, 0.35), total, size=rng.uniform(0.9, 1.3), hard=0.6) * rng.uniform(0.08, 0.2)
    write("chest_open.wav", room(x, 0.4, 0.25))


def jackpot():
    total = int(3.2 * SR)
    x = np.zeros(total)
    # a pile of coins tumbling out: dense at first, thinning out, with bounces
    t = 0.05
    while t < 2.2:
        density = 70 * np.exp(-t / 0.9) + 6
        x += coin(t, total, size=rng.uniform(0.85, 1.35)) * rng.uniform(0.25, 0.7) * np.exp(-t / 1.6)
        if rng.random() < 0.35:   # a bounce or two of the same coin
            x += coin(t + rng.uniform(0.04, 0.09), total, size=1.0) * 0.2
        t += rng.exponential(1.0 / density)
    # a few coins rolling to a stop: a little "spin-down" rattle
    for k in range(3):
        t0 = rng.uniform(1.6, 2.4)
        n = 14
        for j in range(n):
            dt = 0.09 * (1 - j / n) ** 1.5 + 0.008
            t0 += dt
            x += coin(t0, total, size=1.1, hard=0.4) * 0.12 * (1 - j / n)
    # a small brass hand bell rung twice over it (real bell partial ratios)
    bell = [1.0, 2.0, 2.4, 3.0, 4.07, 5.43]
    for t0, a in [(0.08, 0.55), (0.45, 0.45), (0.85, 0.3)]:
        f0 = 880 * rng.uniform(0.995, 1.005)
        x += modal(t0, total, [f0 * r for r in bell], [1, 0.6, 0.5, 0.35, 0.25, 0.15], [1.1, 0.8, 0.6, 0.45, 0.3, 0.2], 2.2) * a
    write("slot_jackpot.wav", room(x, 0.5, 0.28))


if __name__ == "__main__":
    chest_open()
    jackpot()
