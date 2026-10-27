"""Synthesise every TIMBUK sound (numpy only) and process the creature voices.

Run from the repo root:  python3 source/audio/sfxgen.py [name ...]
Writes 16-bit mono WAVs to assets/audio/{ambience,sfx,creatures,voices}/.
Files whose name contains "_loop" or starts with "amb_" are made seamless
and imported by Godot as looping (see tools/audio_import_stubs.py).
Voices: raw Windows-TTS takes in source/audio/raw_voice/ (see voice_lines.txt)
are pitched, stuttered, ring-modulated and reverbed per creature.
"""
import math
import os
import sys
import wave

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")
RAW = os.path.join(os.path.dirname(__file__), "raw_voice")
RNG = np.random.default_rng(7)
SOUNDS = {}


def snd(folder):
    def deco(fn):
        SOUNDS[fn.__name__] = (fn, folder)
        return fn
    return deco


# ------------------------------------------------------------------ io

def write(folder, name, x, peak=0.9):
    os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    x = np.asarray(x, np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, folder, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def read(path):
    with wave.open(path, "rb") as w:
        sr, n, ch, sw = w.getframerate(), w.getnframes(), w.getnchannels(), w.getsampwidth()
        raw = np.frombuffer(w.readframes(n), np.int16 if sw == 2 else np.uint8).astype(np.float64)
    if ch > 1:
        raw = raw.reshape(-1, ch).mean(1)
    raw /= 32768.0
    return resample(raw, sr / SR)


# ------------------------------------------------------------------ dsp helpers

def t_(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return RNG.standard_normal(int(dur * SR))


def resample(x, ratio):
    """ratio > 1 shortens (and raises pitch when played at SR)."""
    n = int(len(x) / ratio)
    return np.interp(np.arange(n) * ratio, np.arange(len(x)), x)


def band(x, lo, hi, order=2.0):
    """Smooth FFT band-pass (lo/hi in Hz, lo=0 -> low-pass)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo > 0:
        g *= 1 / (1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    if hi:
        g *= 1 / (1 + (f / hi) ** (2 * order))
    return np.fft.irfft(X * g, len(x))


def lp(x, hi):
    return band(x, 0, hi)


def env_exp(dur, decay, attack=0.002):
    t = t_(dur)
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t / decay)


def reverb(x, size=1.6, mix=0.35, damp=4000):
    """Convolution with an exponentially decaying noise impulse response."""
    n = int(size * SR)
    ir = RNG.standard_normal(n) * np.exp(-np.arange(n) / (SR * size / 6))
    ir = lp(ir, damp)
    ir[0] = 0
    y = np.fft.irfft(np.fft.rfft(np.concatenate([x, np.zeros(n)])) * np.fft.rfft(np.concatenate([ir, np.zeros(len(x))])),
                     len(x) + n)
    y = y / (np.max(np.abs(y)) + 1e-9) * np.max(np.abs(x))
    out = np.concatenate([x, np.zeros(n)]) * (1 - mix) + y * mix
    return out


def seamless(x, fade=1.0):
    """Crossfade the tail into the head so the file loops without a click."""
    f = int(fade * SR)
    head, tail = x[:f], x[-f:]
    w = np.linspace(0, 1, f)
    body = x[f:-f]
    return np.concatenate([tail * (1 - w) + head * w, body])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def place(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    if i < len(dst):
        dst[i:j] += src[:j - i]
    return dst


def tone(freq, dur, kind="sine", phase=0.0):
    t = t_(dur)
    ph = 2 * np.pi * np.cumsum(np.broadcast_to(freq, t.shape)) / SR + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    if kind == "square":
        return np.sign(np.sin(ph))
    raise ValueError(kind)


def click(freq=2500, decay=0.006, dur=0.05):
    return tone(freq, dur) * env_exp(dur, decay) + lp(noise(dur), 6000) * env_exp(dur, decay * 0.5) * 0.6


def formant(x, freqs, q=8.0):
    """Very small vocal-tract filter: sum of narrow band-passes."""
    return sum(band(x, f * (1 - 1 / q), f * (1 + 1 / q), 3) for f in freqs)


# ==================================================================
# Ambience (seamless loops)
# ==================================================================

@snd("ambience")
def amb_facility_hum():
    d = 21
    t = t_(d)
    hum = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((50, 0.5), (100, 0.35), (150, 0.15), (200, 0.08)))
    hum *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.07 * t)
    air = lp(noise(d), 900) * 0.25
    return seamless(hum * 0.4 + air)


@snd("ambience")
def amb_lab():
    d = 21
    t = t_(d)
    buzz = sum(np.sin(2 * np.pi * 120 * k * t) / k for k in range(1, 9)) * 0.12
    hiss = band(noise(d), 2000, 9000) * 0.05
    air = lp(noise(d), 600) * 0.2
    return seamless(buzz + hiss + air)


@snd("ambience")
def amb_containment():
    d = 24
    t = t_(d)
    drone = (np.sin(2 * np.pi * 38 * t) + 0.6 * np.sin(2 * np.pi * 57.3 * t) + 0.3 * np.sin(2 * np.pi * 76.1 * t)) * 0.3
    throb = lp(noise(d), 120) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.8 * t) ** 8) * 0.8
    out = drone + throb
    for k in range(9):        # drips and distant metal knocks
        place(out, tone(RNG.uniform(900, 1600), 0.15) * env_exp(0.15, 0.02) * 0.4, RNG.uniform(0.5, d - 1.5))
    for k in range(3):
        place(out, band(noise(1.5), 200, 900) * env_exp(1.5, 0.5) * 0.6, RNG.uniform(1, d - 3))
    return seamless(reverb(out, 2.5, 0.3)[:len(out)])


@snd("ambience")
def amb_lower():
    d = 26
    t = t_(d)
    drone = (np.sin(2 * np.pi * 31 * t) + 0.5 * np.sin(2 * np.pi * 46.5 * t)) * 0.35
    wind = band(noise(d), 300, 1200) * (0.4 + 0.6 * np.sin(2 * np.pi * 0.05 * t + 1) ** 2) * 0.5
    out = drone + wind
    for k in range(14):
        place(out, tone(RNG.uniform(1100, 2200), 0.12) * env_exp(0.12, 0.015) * 0.3, RNG.uniform(0.5, d - 1))
    for k in range(2):   # distant groan
        g = tone(np.linspace(110, 70, int(2.2 * SR)), 2.2, "saw")
        g = formant(g, (500, 900)) * np.hanning(len(g)) * 0.25
        place(out, g, RNG.uniform(2, d - 4))
    return seamless(reverb(out, 3.0, 0.4)[:len(out)])


@snd("ambience")
def amb_chamber():
    d = 24
    t = t_(d)
    drone = (np.sin(2 * np.pi * 27.5 * t) + 0.7 * np.sin(2 * np.pi * 41.2 * t) + 0.4 * np.sin(2 * np.pi * 55 * t + np.sin(t))) * 0.35
    out = drone + lp(noise(d), 200) * 0.2
    for k in range(d):        # giant clock: heavy tick every second, deeper "tock" on odd beats
        f = 420 if k % 2 == 0 else 300
        tick = tone(f, 0.4) * env_exp(0.4, 0.06) + lp(noise(0.4), 3000) * env_exp(0.4, 0.01) * 0.6
        place(out, tick * 0.7, k + 0.02)
    return seamless(reverb(out, 3.5, 0.45)[:len(out)])


@snd("ambience")
def amb_exterior():
    d = 26
    t = t_(d)
    wind = band(noise(d), 150, 800) * (0.35 + 0.65 * (np.sin(2 * np.pi * 0.04 * t) * 0.5 + 0.5)) * 0.6
    gust = band(noise(d), 800, 3000) * (np.sin(2 * np.pi * 0.11 * t) * 0.5 + 0.5) ** 4 * 0.2
    out = wind + gust
    rumble = lp(noise(5), 80) * env_exp(5, 1.4, 0.4)
    place(out, rumble * 1.4, 9.0)
    return seamless(out)


# ==================================================================
# Point-source loops (props, lights, effects)
# ==================================================================

@snd("sfx")
def buzz_fluorescent_loop():
    d = 6
    t = t_(d)
    buzz = sum(np.sin(2 * np.pi * 120 * k * t) / k ** 0.8 for k in range(1, 14))
    buzz *= 0.7 + 0.3 * np.sin(2 * np.pi * 0.5 * t)
    for k in range(10):
        place(buzz, band(noise(0.05), 2000, 8000) * env_exp(0.05, 0.01) * 3, RNG.uniform(0, d - 0.1))
    return seamless(buzz * 0.3, 0.3)


@snd("sfx")
def alarm_beacon_loop():
    d = 2.0
    a = tone(880, 0.5, "square") * np.hanning(int(0.5 * SR))
    b = tone(660, 0.5, "square") * np.hanning(int(0.5 * SR))
    out = np.zeros(int(d * SR))
    place(out, lp(a, 3000), 0.0)
    place(out, lp(b, 3000), 0.5)
    return reverb(out, 1.0, 0.25)[:len(out)]


@snd("sfx")
def clock_tick_loop():
    out = np.zeros(int(4 * SR))
    for k in range(4):
        place(out, click(3200 if k % 2 == 0 else 2600, 0.004) * 0.8, k + 0.01)
    return out


@snd("sfx")
def machine_hum_loop():
    d = 8
    t = t_(d)
    hum = tone(55 + 2 * np.sin(2 * np.pi * 0.3 * t), d, "saw")
    hum = lp(hum, 400) * (0.8 + 0.2 * np.sin(2 * np.pi * 4 * t))
    whine = np.sin(2 * np.pi * (1800 + 30 * np.sin(2 * np.pi * 0.2 * t)) * t) * 0.04
    return seamless(hum * 0.5 + whine + lp(noise(d), 300) * 0.2, 0.5)


@snd("sfx")
def tank_bubbles_loop():
    d = 8
    out = lp(noise(d), 250) * 0.15
    for k in range(70):
        f = RNG.uniform(300, 900)
        dur = RNG.uniform(0.03, 0.08)
        b = np.sin(2 * np.pi * np.linspace(f, f * 1.6, int(dur * SR)) * t_(dur)) * np.hanning(int(dur * SR))
        place(out, b * RNG.uniform(0.2, 0.6), RNG.uniform(0, d - 0.1))
    return seamless(out, 0.3)


@snd("sfx")
def computer_hum_loop():
    d = 8
    t = t_(d)
    out = lp(noise(d), 1500) * 0.15 + np.sin(2 * np.pi * 15600 * t) * 0.01
    for k in range(5):
        place(out, tone(RNG.choice([1200, 1800, 2400]), 0.08, "square") * 0.1 * np.hanning(int(0.08 * SR)), RNG.uniform(0, d - 0.2))
    return seamless(out, 0.3)


@snd("sfx")
def electric_crackle_loop():
    d = 6
    out = lp(noise(d), 400) * 0.05 + np.sin(2 * np.pi * 60 * t_(d)) * 0.08
    for k in range(40):
        dur = RNG.uniform(0.01, 0.12)
        place(out, band(noise(dur), 1500, 9000) * env_exp(dur, dur * 0.3) * RNG.uniform(0.3, 1.0), RNG.uniform(0, d - 0.2))
    return seamless(out, 0.2)


@snd("sfx")
def drip_loop():
    out = np.zeros(int(5 * SR))
    for at in (0.3, 1.9, 2.6, 4.1):
        f = RNG.uniform(1200, 1700)
        d = np.sin(2 * np.pi * np.linspace(f, f * 1.8, int(0.06 * SR)) * t_(0.06)) * env_exp(0.06, 0.012)
        place(out, d, at)
    return reverb(out, 1.2, 0.4)[:len(out)]


@snd("sfx")
def steam_hiss_loop():
    d = 5
    t = t_(d)
    return seamless(band(noise(d), 2500, 10000) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.3 * t)) * 0.4, 0.4)


@snd("sfx")
def fire_loop():
    d = 8
    out = lp(noise(d), 500) * 0.4 + band(noise(d), 800, 3000) * 0.08
    for k in range(260):
        dur = RNG.uniform(0.003, 0.02)
        place(out, band(noise(dur), 1500, 8000) * env_exp(dur, dur * 0.4) * RNG.uniform(0.2, 1.0), RNG.uniform(0, d - 0.05))
    return seamless(out, 0.4)


@snd("sfx")
def suspend_loop():
    """Slowed-time bed: deep pulse, smeared ticking, airy shimmer."""
    d = 8
    t = t_(d)
    pulse = np.sin(2 * np.pi * 42 * t) * (np.sin(2 * np.pi * 0.5 * t) * 0.5 + 0.5) * 0.4
    shimmer = band(noise(d), 3000, 7000) * (np.sin(2 * np.pi * 0.25 * t) * 0.5 + 0.5) * 0.08
    out = pulse + shimmer
    for k in range(8):
        tk = resample(click(2600, 0.01, 0.1), 0.35)       # slowed, low ticks
        place(out, tk * 0.5, k * 1.0 + 0.05)
    return seamless(reverb(out, 3.0, 0.55)[:len(out)], 0.5)


@snd("sfx")
def tracker_ping_loop():
    out = np.zeros(int(1.5 * SR))
    ping = tone(1760, 0.25) * env_exp(0.25, 0.06) + tone(2640, 0.25) * env_exp(0.25, 0.04) * 0.4
    place(out, ping, 0.0)
    return reverb(out, 0.8, 0.3)[:len(out)]


# ==================================================================
# One-shots
# ==================================================================

@snd("sfx")
def gunshot():
    d = 1.4
    crack = band(noise(d), 1500, 10000) * env_exp(d, 0.012)
    body = lp(noise(d), 1200) * env_exp(d, 0.06)
    thump = tone(np.linspace(140, 45, int(d * SR)), d) * env_exp(d, 0.08)
    return reverb(crack * 0.9 + body * 0.8 + thump * 0.9, 1.4, 0.3)


@snd("sfx")
def impact_ricochet():
    d = 0.9
    hit = band(noise(0.05), 1000, 9000) * env_exp(0.05, 0.006)
    ric = tone(np.linspace(3200, 1700, int(0.6 * SR)), 0.6) * env_exp(0.6, 0.15) * 0.35
    out = np.zeros(int(d * SR))
    place(out, hit, 0)
    place(out, ric, 0.02)
    return reverb(out, 0.9, 0.3)


@snd("sfx")
def impact_concrete():
    d = 0.6
    out = band(noise(d), 300, 6000) * env_exp(d, 0.03)
    for k in range(6):
        place(out, band(noise(0.03), 2000, 8000) * env_exp(0.03, 0.006) * 0.4, RNG.uniform(0.05, 0.4))
    return out


@snd("sfx")
def hit_flesh():
    d = 0.5
    return lp(noise(d), 700) * env_exp(d, 0.05) + tone(np.linspace(120, 60, int(d * SR)), d) * env_exp(d, 0.06) * 0.8


@snd("sfx")
def explosion():
    d = 4.5
    t = t_(d)
    blast = lp(noise(d), 1800) * env_exp(d, 0.35, 0.004)
    rumble = lp(noise(d), 120) * env_exp(d, 1.3, 0.01) * 1.6
    boom = tone(np.linspace(80, 28, len(t)), d) * env_exp(d, 0.5) * 1.2
    debris = np.zeros(len(t))
    for k in range(40):
        place(debris, band(noise(0.04), 1500, 7000) * env_exp(0.04, 0.008) * RNG.uniform(0.1, 0.4), RNG.uniform(0.3, 2.5))
    return reverb(blast + rumble + boom + debris, 2.5, 0.35)


@snd("sfx")
def suspend_activate():
    """Reverse-swell into a deep bell hit: time grinds to a halt."""
    d = 3.0
    swell = band(noise(1.2), 400, 5000) * np.linspace(0, 1, int(1.2 * SR)) ** 3
    bell = sum(np.sin(2 * np.pi * f * t_(2.5)) * a for f, a in ((110, 1), (276, 0.5), (412, 0.3), (589, 0.2))) * env_exp(2.5, 0.8)
    down = tone(np.linspace(600, 60, int(1.0 * SR)), 1.0, "saw")
    down = lp(down, 1500) * env_exp(1.0, 0.4) * 0.3
    out = np.zeros(int(d * SR))
    place(out, swell, 0)
    place(out, bell, 1.15)
    place(out, down, 1.15)
    return reverb(out, 3.0, 0.5)


@snd("sfx")
def tracker_lock():
    out = np.zeros(int(0.8 * SR))
    for k, f in enumerate((1320, 1760, 2640)):
        place(out, tone(f, 0.09, "square") * np.hanning(int(0.09 * SR)) * 0.3, k * 0.08)
    return reverb(out, 0.6, 0.2)


@snd("sfx")
def door_slide():
    d = 2.2
    t = t_(d)
    servo = lp(tone(np.linspace(180, 260, len(t)), d, "saw"), 1500) * np.sin(np.pi * t / d) * 0.4
    grind = band(noise(d), 300, 2500) * np.sin(np.pi * t / d) * 0.25
    clunk = lp(noise(0.3), 400) * env_exp(0.3, 0.05)
    out = servo + grind
    place(out, clunk * 1.5, d - 0.3)
    return reverb(out, 1.5, 0.3)


@snd("sfx")
def blast_door_groan():
    d = 5.0
    t = t_(d)
    groan = lp(tone(np.linspace(55, 40, len(t)) + 4 * np.sin(2 * np.pi * 3 * t), d, "saw"), 600)
    screech = band(tone(np.linspace(900, 700, len(t)), d, "saw"), 600, 2400) * (np.sin(np.pi * t / d) ** 3) * 0.15
    return reverb(groan * np.sin(np.pi * t / d) * 0.6 + screech, 3.0, 0.4)


@snd("sfx")
def reveal_sting():
    """Low brass-like cluster swelling into a metallic shriek and a clock strike."""
    d = 6.0
    t = t_(d)
    cluster = sum(lp(tone(f, d, "saw"), 900) for f in (55, 58.3, 82.4, 87.3)) * np.clip(t / 2.5, 0, 1) * 0.25
    shriek = band(tone(np.linspace(1400, 2600, len(t)), d, "saw"), 1200, 5000) * np.clip((t - 2.0) / 1.5, 0, 1) * np.exp(-np.maximum(t - 3.6, 0) * 2) * 0.12
    out = cluster + shriek
    strike = sum(np.sin(2 * np.pi * f * t_(3.0)) * a for f, a in ((98, 1), (247, 0.6), (392, 0.4), (523, 0.25))) * env_exp(3.0, 1.0)
    place(out, strike * 0.9, 3.6)
    return reverb(out, 4.0, 0.5)


def footsteps(kind):
    outs = []
    for k in range(4):
        d = 0.35
        if kind == "concrete":
            x = band(noise(d), 150, 3500) * env_exp(d, 0.03) + lp(noise(d), 200) * env_exp(d, 0.02) * 0.8
        else:
            x = band(noise(d), 300, 5000) * env_exp(d, 0.04) + tone(RNG.uniform(380, 520), d) * env_exp(d, 0.06) * 0.35
        outs.append(resample(x, RNG.uniform(0.9, 1.1)))
    return outs


@snd("sfx")
def footsteps_all():
    for kind in ("concrete", "metal"):
        for i, x in enumerate(footsteps(kind)):
            write("sfx", f"footstep_{kind}_{i}", x, 0.8)
    return None


# ==================================================================
# Creature sounds (non-verbal)
# ==================================================================

def groan(dur, f0, f1, formants, rough=0.3):
    t = t_(dur)
    f = np.linspace(f0, f1, len(t)) * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * t))
    src = tone(f, dur, "saw") + band(noise(dur), 200, 3000) * rough
    v = formant(src, formants, 6)
    return v * np.sin(np.pi * t / dur) ** 0.7


@snd("creatures")
def failed_breath_loop():
    d = 8
    out = np.zeros(int(d * SR))
    for at in (0.2, 2.9, 5.4):
        inhale = band(noise(1.1), 400, 2500) * np.sin(np.pi * t_(1.1) / 1.1) ** 2 * 0.4
        rattle = groan(1.2, 80, 70, (400, 700), 0.8) * 0.5
        place(out, inhale, at)
        place(out, rattle, at + 1.2)
    return seamless(out, 0.3)


@snd("creatures")
def failed_groans():
    for i in range(3):
        x = groan(RNG.uniform(1.4, 2.4), RNG.uniform(140, 190), RNG.uniform(60, 90), (RNG.uniform(450, 650), RNG.uniform(900, 1300)), 0.5)
        write("creatures", f"failed_groan_{i}", reverb(x, 1.6, 0.35))
    shriek = groan(1.2, 380, 520, (1100, 2400), 0.9)
    write("creatures", "failed_shriek", reverb(shriek, 2.0, 0.4))
    return None


@snd("creatures")
def augmented_servo_loop():
    d = 6
    t = t_(d)
    out = lp(noise(d), 300) * 0.1
    for k in range(6):
        dur = RNG.uniform(0.3, 0.7)
        f = RNG.uniform(300, 600)
        s = lp(tone(np.linspace(f, f * 1.5, int(dur * SR)), dur, "square"), 2500) * np.hanning(int(dur * SR)) * 0.25
        place(out, s, RNG.uniform(0, d - 1))
        place(out, click(1800, 0.003) * 0.6, RNG.uniform(0, d - 0.1))
    return seamless(out, 0.3)


@snd("creatures")
def augmented_glitches():
    for i in range(3):
        x = groan(1.2, 160, 110, (600, 1400), 0.3)
        x = x * np.sin(2 * np.pi * 70 * np.arange(len(x)) / SR)      # ring mod
        x = np.round(x * 6) / 6                                 # bit crush
        write("creatures", f"augmented_glitch_{i}", reverb(x, 1.0, 0.25))
    return None


@snd("creatures")
def chemical_gurgle_loop():
    d = 8
    out = lp(noise(d), 300) * 0.2
    for k in range(50):
        dur = RNG.uniform(0.04, 0.12)
        f = RNG.uniform(120, 350)
        place(out, np.sin(2 * np.pi * np.linspace(f, f * 2, int(dur * SR)) * t_(dur)) * np.hanning(int(dur * SR)) * 0.5, RNG.uniform(0, d - 0.2))
    for at in (1.0, 4.6):
        place(out, groan(1.6, 90, 70, (350, 650), 1.0) * 0.4, at)
    return seamless(out, 0.3)


@snd("creatures")
def chemical_coughs():
    for i in range(2):
        d = 1.6
        out = np.zeros(int(d * SR))
        for k in range(3):
            c = band(noise(0.18), 300, 2500) * env_exp(0.18, 0.05) + groan(0.18, 200, 150, (500, 900), 1.0) * 0.6
            place(out, c, k * 0.33)
        write("creatures", f"chemical_cough_{i}", reverb(out, 1.4, 0.3))
    return None


@snd("creatures")
def twin_tick_loop():
    """The twin's own heartbeat: fast tick-tock, gear whirr, eye servo."""
    d = 4
    t = t_(d)
    out = lp(noise(d), 200) * 0.08 + np.sin(2 * np.pi * 47 * t) * 0.12
    for k in range(8):
        place(out, click(3600 if k % 2 == 0 else 2900, 0.004) * 0.7, k * 0.5)
    whirr = lp(tone(220 + 40 * np.sin(2 * np.pi * 0.5 * t), d, "saw"), 800) * 0.05
    return seamless(out + whirr, 0.2)


@snd("creatures")
def twin_whirr():
    d = 1.5
    t = t_(d)
    w = lp(tone(np.linspace(300, 900, len(t)), d, "square"), 3000) * np.sin(np.pi * t / d) * 0.3
    place(w, click(2000, 0.004, 0.05), d - 0.08)
    return reverb(w, 1.0, 0.2)


# ==================================================================
# Voices: distorted TTS takes
# ==================================================================

def stutter(x, n=3, grain=0.07):
    """Repeat a few short grains (broken-record speech)."""
    out = []
    i = 0
    g = int(grain * SR)
    while i < len(x):
        seg = x[i:i + g]
        out.append(seg)
        if RNG.random() < 0.12 and len(seg) == g:
            for k in range(RNG.integers(1, n + 1)):
                out.append(seg * 0.85)
        i += g
    return np.concatenate(out)


def voice_failed(x):
    v = resample(x, 0.72)                                  # slower and lower
    v = stutter(v)
    breath = band(RNG.standard_normal(len(v)), 600, 4000) * np.abs(v).max() * 0.25 * (np.abs(lp(v, 30)) > 0.02)
    rev_tail = reverb(v[::-1], 1.5, 1.0)[::-1] * 0.35      # reversed reverb swells in before the words
    return mix(np.concatenate([np.zeros(len(rev_tail) - len(v)), v + breath]), rev_tail)


def voice_augmented(x):
    v = resample(x, 0.9)
    v = band(v, 300, 3200)                                 # radio band
    v = v * (0.6 + 0.4 * np.sin(2 * np.pi * 55 * np.arange(len(v)) / SR))   # ring modulation
    v = np.round(v / (np.abs(v).max() + 1e-9) * 10) / 10   # crush
    return reverb(v, 0.8, 0.2)


def voice_chemical(x):
    v = resample(x, 0.66)
    trem = 0.65 + 0.35 * np.sin(2 * np.pi * 9 * np.arange(len(v)) / SR)   # wet, bubbling throat
    v = lp(v, 2500) * trem
    gurgle = np.zeros(len(v))
    for k in range(int(len(v) / SR * 25)):
        dur = 0.05
        f = RNG.uniform(150, 400)
        place(gurgle, np.sin(2 * np.pi * f * t_(dur)) * np.hanning(int(dur * SR)) * 0.15, RNG.uniform(0, len(v) / SR))
    return reverb(v + gurgle * np.abs(v).max(), 1.2, 0.3)


def voice_twin(x):
    a = resample(x, 0.86)
    b = resample(x, 0.6)
    n = max(len(a), len(b))
    v = mix(a, b * 0.7)
    for k in range(int(n / SR / 0.5) + 1):                 # ticking underneath the words
        place(v, click(3200, 0.004) * 0.25 * np.abs(v).max(), k * 0.5)
    return reverb(v, 3.0, 0.5)


@snd("voices")
def voices():
    if not os.path.isdir(RAW):
        print("no raw voices; run the TTS step first")
        return None
    fx = {"failed": voice_failed, "augmented": voice_augmented, "chemical": voice_chemical, "twin": voice_twin}
    for f in sorted(os.listdir(RAW)):
        if not f.endswith(".wav"):
            continue
        creature = f.split("_")[0]
        x = read(os.path.join(RAW, f))
        x = x[np.argmax(np.abs(x) > 0.01):]            # trim leading silence
        write("voices", f[:-4], fx[creature](x), 0.85)
    return None


if __name__ == "__main__":
    names = sys.argv[1:] or list(SOUNDS)
    for name in names:
        fn, folder = SOUNDS[name]
        print("sound:", name, flush=True)
        x = fn()
        if x is not None:
            write(folder, name, x)
    print("done", len(names))
